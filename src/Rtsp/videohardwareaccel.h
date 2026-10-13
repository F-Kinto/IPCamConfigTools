/*********************************************************************
File : VideoHardwareAccel.h
Module : tools
Author : jsw
date : 2026/07/23
Ver : 1.0.0
Desc : 硬件加速封装类。负责按系统支持类型（DXVA2/D3D11VA）
       创建 FFmpeg 硬件设备上下文、提供 get_format 回调，
       并将硬件帧下载（hwdownload）为 CPU 端 YUV420P 帧，
       供现有解码/渲染/录制流程消费。现有解码主流程只需在
       开关开启时注入本对象，改动最小。
********************************************************************/
#ifndef VIDEOHARDWAREACCEL_H
#define VIDEOHARDWAREACCEL_H

#include <QObject>
#include <QDebug>

// 头文件只前置声明所需的 FFmpeg C 类型，不引入任何 Windows/FFmpeg 头。
// 否则 windows.h / d3d 头中的宏（interface 等）会泄漏到包含本头的翻译单元，
// 污染后续 Qt 头（如 qversionnumber.h）的解析，导致级联语法错误。
// 真正的 Windows/FFmpeg 头仅在 videohardwareaccel.cpp 中引入。
extern "C" {
struct AVCodec;
struct AVCodecContext;
struct AVFrame;
struct AVBufferRef;
struct SwsContext;
enum AVPixelFormat;
enum AVHWDeviceType;
}

class VideoHardwareAccel {
  public:
    // 系统支持的硬件加速后端
    enum class HwBackend {
        None = 0, // 软解码
        DXVA2,    // DirectX 9 (Win7+, 全厂商)
        D3D11VA,  // DirectX 11 (Win8+, 全厂商)
        QSV       // Intel Quick Sync
    };

    VideoHardwareAccel();
    ~VideoHardwareAccel();

    // 尝试为指定通用解码器（h264/hevc）初始化硬件加速。
    // 按 D3D11VA -> DXVA2 顺序探测，命中即用。
    // 返回 true 表示硬件加速可用，并填充设备上下文与硬件像素格式。
    bool init(AVCodec* codec, bool isH265);

    // 供 AVCodecContext::get_format 使用的静态回调。
    // 通过 ctx->opaque 取到本对象，返回匹配到的硬件像素格式；
    // 若不可用则回退到 AV_PIX_FMT_YUV420P（软件解码）。
    static AVPixelFormat getFormatCallback(AVCodecContext* ctx, const AVPixelFormat* pixFmts);

    // 零拷贝优化：拆分 hwdownload + sws_scale 为两步，
    // 允许调用方在两步之间释放 HW 帧引用并重新分配目标帧缓冲区，
    // 从而省去 m_cpuFrame 中间缓存和 av_image_copy 深拷贝。
    // 步骤 1：将硬件帧下载到内部 NV12 中间帧（m_transferFrame）。
    //         必须在释放 HW 帧引用之前调用。
    bool hwDownloadToIntermediate(AVFrame* hwFrame);
    // 步骤 2：从内部 NV12 中间帧 sws_scale 到目标 YUV420P 帧。
    //         dst 必须已通过 av_frame_get_buffer 分配引用计数缓冲区。
    bool scaleFromIntermediate(AVFrame* dst, int srcWidth, int srcHeight);

    AVBufferRef* hwDeviceCtx() const
    {
        return m_hwDeviceCtx;
    }

    AVPixelFormat hwPixelFormat() const; // 返回外部 enum，定义见 .cpp

    bool isEnabled() const
    {
        return m_enabled;
    }

    HwBackend backend() const
    {
        return m_backend;
    }

    void unInit();

    // 全局硬件设备上下文共享管理。
    // 所有 VideoHardwareAccel 实例复用同一套 hw_device_ctx（按后端类型），
    // 避免 N 路并发时每路独立 av_hwdevice_ctx_create 导致 32 位地址空间耗尽。
    // 内部通过 AVBufferRef 引用计数管理生命周期：引用归零才真正释放。
    static void releaseSharedDevices(); // 进程退出/重置时调用，释放全部共享设备

    // 查询当前进程已提交的虚拟内存总量（字节）。
    // 用于 32 位进程地址空间压力检测：当虚拟内存接近上限时，
    // 新的解码流应回退软件解码，防止地址空间耗尽导致进程崩溃。
    static size_t getCommittedVirtualSize();

  private:
    // 探测单个后端：找到解码器匹配的 hw 像素格式并获取（或创建）共享设备上下文。
    bool tryBackend(AVHWDeviceType type, AVCodec* codec, AVPixelFormat& outPixFmt);

    AVBufferRef*   m_hwDeviceCtx = nullptr; // 硬件设备上下文（共享引用）
    AVHWDeviceType m_sharedBackendType;     // 本实例使用的后端类型
    AVPixelFormat  m_hwPixFmt;              // 解码器输出的硬件像素格式
    HwBackend      m_backend = HwBackend::None;
    bool           m_enabled = false;
    bool           m_isH265  = false;

    AVFrame*           m_transferFrame = nullptr; // hwdownload 中间帧（通常为 NV12）
    struct SwsContext* m_swsCtx        = nullptr; // NV12 -> YUV420P 转换上下文
};

#endif // VIDEOHARDWAREACCEL_H
