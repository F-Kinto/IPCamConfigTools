/*********************************************************************
File : VideoHardwareAccel.cpp
Module : tools
Author : VmsTools
date : 2026/07/23
Ver : 1.0.0
Desc : 硬件加速封装实现，详见头文件说明。
********************************************************************/
#include "videohardwareaccel.h"

// Windows 平台头与 FFmpeg 硬件加速头集中放于此 .cpp，
// 避免污染头文件（防止 interface 等宏泄漏到 Qt 头）。
// NOMINMAX 避免 min/max 宏污染。
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h> // VirtualQuery / GlobalMemoryStatusEx

extern "C" {
#include "libavcodec/avcodec.h"
#include "libavutil/hwcontext.h"
#include "libavutil/pixdesc.h"
#include "libswscale/swscale.h"
}

#include <atomic>
#include <mutex>

namespace {
// 诊断辅助：统计当前存活的硬件设备引用数量（共享模式下为总引用数）。
std::atomic<int> g_activeHwDeviceCount{0};

// 将后端枚举转为可读字符串，便于日志打印。
const char* backendName(VideoHardwareAccel::HwBackend b)
{
    switch (b) {
        case VideoHardwareAccel::HwBackend::DXVA2:
            return "DXVA2";
        case VideoHardwareAccel::HwBackend::D3D11VA:
            return "D3D11VA";
        case VideoHardwareAccel::HwBackend::QSV:
            return "QSV";
        default:
            return "None";
    }
}

// 统计当前进程已提交的虚拟内存总量（字节），用于观察 32 位地址空间压力。
SIZE_T GetCommittedVirtualSize()
{
    MEMORY_BASIC_INFORMATION info;
    SIZE_T                   addr    = 0;
    SIZE_T                   total   = 0;
    const SIZE_T             maxAddr = static_cast<SIZE_T>(-1);
    while (addr < maxAddr) {
        if (VirtualQuery(reinterpret_cast<LPCVOID>(addr), &info, sizeof(info)) == 0)
            break;
        if (info.State == MEM_COMMIT)
            total += info.RegionSize;
        if (info.RegionSize == 0)
            break;
        addr += info.RegionSize;
    }
    return total;
}

// AVHWDeviceType -> 缓存索引映射（D3D11VA/DXVA2/QSV 各占一槽位）。
int hwTypeIndex(AVHWDeviceType type)
{
    switch (type) {
        case AV_HWDEVICE_TYPE_D3D11VA:
            return 0;
        case AV_HWDEVICE_TYPE_DXVA2:
            return 1;
        case AV_HWDEVICE_TYPE_QSV:
            return 2;
        default:
            return -1;
    }
}
} // namespace

// ============================================================================
// 全局共享硬件设备上下文缓存
// ============================================================================
// 每种后端类型只创建一个 av_hwdevice_ctx_create 结果，所有 DecodeVideo 路径
// 通过 av_buffer_ref / av_buffer_unref 复用。FFmpeg 的 AVBufferRef 引用计数
// 保证线程安全；首次创建时用 mutex 保护竞态。
namespace {
constexpr int kHwBackendCount = 3; // D3D11VA / DXVA2 / QSV

AVBufferRef* s_sharedDeviceCtx[kHwBackendCount] = {nullptr, nullptr, nullptr};
std::mutex   s_sharedDeviceMutex; // 保护首次创建

// 获取指定后端类型的共享设备上下文。
// 首次调用时创建并缓存；后续调用直接 av_buffer_ref 增加引用计数。
// 返回值调用方需通过 av_buffer_unref 释放自己的那份引用。
AVBufferRef* acquireSharedDeviceCtx(AVHWDeviceType type)
{
    int idx = hwTypeIndex(type);
    if (idx < 0 || idx >= kHwBackendCount)
        return nullptr;

    std::lock_guard<std::mutex> lock(s_sharedDeviceMutex);

    // 已有缓存 → 直接复用（引用计数 +1）
    if (s_sharedDeviceCtx[idx]) {
        ++g_activeHwDeviceCount;
        return av_buffer_ref(s_sharedDeviceCtx[idx]);
    }

    // 首次创建
    AVBufferRef* ctx = nullptr;
    int          err = av_hwdevice_ctx_create(&ctx, type, nullptr, nullptr, 0);
    if (err < 0 || !ctx)
        return nullptr;

    s_sharedDeviceCtx[idx] = ctx;
    ++g_activeHwDeviceCount;
    qDebug() << "[VideoHardwareAccel] 共享设备已创建 backend=" << type << "activeRefs=" << g_activeHwDeviceCount.load() << "virtualBytes=" << GetCommittedVirtualSize();
    return av_buffer_ref(ctx); // 返回调用方持有的独立引用
}

// 释放调用方对共享设备的引用（不销毁共享实例本身）。
void releaseSharedDeviceCtxRef(AVHWDeviceType type)
{
    int idx = hwTypeIndex(type);
    if (idx < 0 || idx >= kHwBackendCount)
        return;

    --g_activeHwDeviceCount;
    // 注意：此处不做 av_buffer_unref(&s_sharedDeviceCtx[idx])，
    // 因为 s_sharedDeviceCtx 是全局缓存，由 releaseSharedDevices() 统一释放。
    // 调用方在 tryBackend 中拿到的引用已在 unInit 中被 unref。
}

// 释放全部共享设备上下文（进程退出或重置硬件加速时调用）。
void releaseAllSharedDevices()
{
    std::lock_guard<std::mutex> lock(s_sharedDeviceMutex);
    for (int i = 0; i < kHwBackendCount; ++i) {
        if (s_sharedDeviceCtx[i]) {
            av_buffer_unref(&s_sharedDeviceCtx[i]);
            s_sharedDeviceCtx[i] = nullptr;
        }
    }
    g_activeHwDeviceCount.store(0);
    qDebug() << "[VideoHardwareAccel] 全部共享设备已释放";
}
} // namespace

// 头文件中声明的 hwPixelFormat 在此定义（返回完整 enum 类型）。
AVPixelFormat VideoHardwareAccel::hwPixelFormat() const
{
    return m_hwPixFmt;
}

// 静态方法：暴露虚拟内存查询给外部模块（如 DecodeVideo），
// 用于 32 位进程地址空间压力检测。
size_t VideoHardwareAccel::getCommittedVirtualSize()
{
    return GetCommittedVirtualSize();
}

VideoHardwareAccel::VideoHardwareAccel() : m_hwPixFmt(AV_PIX_FMT_NONE), m_sharedBackendType(AV_HWDEVICE_TYPE_NONE) {}

VideoHardwareAccel::~VideoHardwareAccel()
{
    unInit();
}

// 探测单个后端：找到解码器匹配的 hw 像素格式并获取共享设备上下文。
bool VideoHardwareAccel::tryBackend(AVHWDeviceType type, AVCodec* codec, AVPixelFormat& outPixFmt)
{
    // 从解码器的硬件配置列表中找到与本设备类型匹配、
    // 且使用 HW_DEVICE_CTX 方法的像素格式。
    AVPixelFormat hwPixFmt = AV_PIX_FMT_NONE;
    for (int i = 0;; ++i) {
        const AVCodecHWConfig* cfg = avcodec_get_hw_config(codec, i);
        if (!cfg)
            break;
        if ((cfg->methods & AV_CODEC_HW_CONFIG_METHOD_HW_DEVICE_CTX) && cfg->device_type == type) {
            hwPixFmt = cfg->pix_fmt;
            break;
        }
    }
    if (hwPixFmt == AV_PIX_FMT_NONE)
        return false;

    // 使用全局共享设备上下文（首路创建、后续复用），
    // 避免 N 路并发时每路独立 av_hwdevice_ctx_create 导致 32 位地址空间耗尽。
    m_hwDeviceCtx = acquireSharedDeviceCtx(type);
    if (!m_hwDeviceCtx) {
        m_sharedBackendType = type; // 记录后端类型，供 unInit 时释放引用
        return false;
    }

    m_sharedBackendType = type; // 记录后端类型，供 unInit 时释放引用
    outPixFmt           = hwPixFmt;
    return true;
}

// 尝试初始化硬件加速，按 D3D11VA -> DXVA2 顺序探测。
bool VideoHardwareAccel::init(AVCodec* codec, bool isH265)
{
    m_isH265   = isH265;
    m_enabled  = false;
    m_hwPixFmt = AV_PIX_FMT_NONE;

    // 探测优先级：D3D11VA（全厂商，Win8+）> DXVA2（全厂商，Win7+）> QSV（仅 Intel）
    AVHWDeviceType candidates[] = {AV_HWDEVICE_TYPE_D3D11VA, AV_HWDEVICE_TYPE_DXVA2, AV_HWDEVICE_TYPE_QSV};
    for (AVHWDeviceType t : candidates) {
        AVPixelFormat pixFmt = AV_PIX_FMT_NONE;
        if (tryBackend(t, codec, pixFmt)) {
            m_hwPixFmt = pixFmt;
            if (t == AV_HWDEVICE_TYPE_D3D11VA)
                m_backend = HwBackend::D3D11VA;
            else if (t == AV_HWDEVICE_TYPE_DXVA2)
                m_backend = HwBackend::DXVA2;
            else
                m_backend = HwBackend::QSV;
            m_enabled = true;
            qDebug() << "[VideoHardwareAccel] init OK backend=" << backendName(m_backend) << "(共享模式) activeRefs=" << g_activeHwDeviceCount.load() << "virtualBytes=" << GetCommittedVirtualSize();
            return true;
        }
    }
    return false;
}

// get_format 回调：优先返回硬件像素格式，失败回退软件解码。
AVPixelFormat VideoHardwareAccel::getFormatCallback(AVCodecContext* ctx, const AVPixelFormat* pixFmts)
{
    VideoHardwareAccel*  self = static_cast<VideoHardwareAccel*>(ctx->opaque);
    const AVPixelFormat* p    = pixFmts;
    while (*p != AV_PIX_FMT_NONE) {
        if (self && *p == self->m_hwPixFmt)
            return *p;
        ++p;
    }
    // 硬件像素格式不可用，回退软件解码（YUV420P）。
    return AV_PIX_FMT_YUV420P;
}

// 将硬件帧下载到内部 NV12 中间帧（零拷贝优化步骤 1）。
// 必须在释放 HW 帧引用之前调用，因为 av_hwframe_transfer_data 需要读取 HW 帧数据。
bool VideoHardwareAccel::hwDownloadToIntermediate(AVFrame* hwFrame)
{
    if (!m_enabled || !hwFrame)
        return false;

    if (!m_transferFrame)
        m_transferFrame = av_frame_alloc();
    if (!m_transferFrame)
        return false;

    av_frame_unref(m_transferFrame);
    int ret = av_hwframe_transfer_data(m_transferFrame, hwFrame, 0);
    if (ret < 0) {
        av_frame_unref(m_transferFrame);
        return false;
    }
    return true;
}

// 从内部 NV12 中间帧 sws_scale 到目标 YUV420P 帧（零拷贝优化步骤 2）。
// dst 必须已通过 av_frame_get_buffer 分配引用计数缓冲区，
// 这样下游 av_frame_ref 为浅拷贝（共享数据、引用计数管理），避免深拷贝浪费内存。
bool VideoHardwareAccel::scaleFromIntermediate(AVFrame* dst, int srcWidth, int srcHeight)
{
    if (!m_transferFrame || !dst)
        return false;

    // 使用 SWS_FAST_BILINEAR 替代 SWS_BICUBIC：实时监控不需要高质量缩放，
    // FAST_BILINEAR 比 BICUBIC 快 3-5 倍，25路并发时显著降低 CPU 负载
    m_swsCtx = sws_getCachedContext(m_swsCtx, srcWidth, srcHeight, static_cast<AVPixelFormat>(m_transferFrame->format), dst->width, dst->height, AV_PIX_FMT_YUV420P, SWS_FAST_BILINEAR, nullptr,
                                    nullptr, nullptr);
    if (!m_swsCtx)
        return false;

    sws_scale(m_swsCtx, m_transferFrame->data, m_transferFrame->linesize, 0, srcHeight, dst->data, dst->linesize);
    return true;
}

// 释放所有硬件加速相关资源。
void VideoHardwareAccel::unInit()
{
    if (m_hwDeviceCtx) {
        // 只释放本实例持有的引用，不销毁全局共享设备本身。
        // 共享设备由 releaseSharedDevices() 在进程退出/重置时统一释放。
        av_buffer_unref(&m_hwDeviceCtx);
        m_hwDeviceCtx = nullptr;
        releaseSharedDeviceCtxRef(m_sharedBackendType);
        qDebug() << "[VideoHardwareAccel] unInit 释放引用"
                 << "activeRefs=" << g_activeHwDeviceCount.load() << "virtualBytes=" << GetCommittedVirtualSize();
    }
    if (m_transferFrame) {
        av_frame_free(&m_transferFrame);
        m_transferFrame = nullptr;
    }
    if (m_swsCtx) {
        sws_freeContext(m_swsCtx);
        m_swsCtx = nullptr;
    }
    m_hwPixFmt          = AV_PIX_FMT_NONE;
    m_backend           = HwBackend::None;
    m_enabled           = false;
    m_sharedBackendType = AV_HWDEVICE_TYPE_NONE;
}

// 释放全部全局共享设备上下文（进程退出或重置硬件加速时调用）。
void VideoHardwareAccel::releaseSharedDevices()
{
    releaseAllSharedDevices();
}
