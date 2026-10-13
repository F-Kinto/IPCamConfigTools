#include "decodevideo.h"
#include <QVector>
#include "g711.h"
#include <QDebug>
#include <QThread>
#include <QDateTime>
#include <forward_list>
#include "videohardwareaccel.h"
// 确保像素格式描述和缩放上下文可用
#include <libavutil/pixdesc.h>
#include <libavutil/imgutils.h>
#include <libavutil/hwcontext.h>
#include <libswscale/swscale.h>
#include <atomic>
#ifndef _WIN64
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h> // GlobalMemoryStatusEx，用于动态计算32位虚拟内存阈值
#endif

namespace {
// 硬件解码并发路数上限：仅用于 64 位进程，防止 GPU 显存耗尽。
// 32 位进程不使用路数上限，而是通过虚拟内存阈值
// 动态判断是否允许硬件解码——阈值检查比路数上限更精确，
// 直接反映实际内存压力，而非粗略估算每路占用。
#ifdef _WIN64
constexpr int kMaxHardwareDecodeStreams = 99; // 实际受GPU显存约束
#else
constexpr int kMaxHardwareDecodeStreams = 0; // 32位不使用路数限制，靠虚拟内存阈值
#endif

// 32 位进程：运行时动态计算虚拟内存安全阈值。
// 取进程实际虚拟地址空间上限的 75%，自适应 LAA（3GB/4GB）和 非 LAA（2GB）：
//   - 非 LAA (2GB) → 阈值 1.5GB，预留 500MB（线程栈、DLL、QML渲染、突发分配）
//   - LAA 3GB      → 阈值 2.25GB，预留 750MB
//   - LAA 4GB(Win64) → 阈值 3.0GB，预留 1.0GB
// 75% 比硬编码更合理：无论地址空间多大，都留 25% 余量给非解码开销。
#ifndef _WIN64
size_t getVirtualMemThreshold()
{
    MEMORYSTATUSEX ms = {};
    ms.dwLength       = sizeof(ms);
    GlobalMemoryStatusEx(&ms);
    // ms.ullTotalVirtual 是当前进程可用的用户态虚拟地址空间总量
    const size_t threshold = static_cast<size_t>(ms.ullTotalVirtual * 75 / 100);
    return threshold;
}
#endif

// 当前成功预留名额的硬件解码并发流计数（原子，跨线程安全）。
// 64 位下用于路数上限检查；32 位下仅用于日志统计（不做限制判断）。
std::atomic<int> g_activeHwStreamCount{0};

// 出流内存监控：周期性打印虚拟内存和硬件解码状态，帮助诊断 32 位地址空间压力。
// 每 kMemLogIntervalFrames 帧打印一次（15fps 下约 5 秒一次）。
constexpr int    kMemLogIntervalFrames = 75;
std::atomic<int> g_memLogFrameCounter{0};
} // namespace

DecodeVideo::DecodeVideo(QObject* parent)
    : QObject(parent), m_isVideoInit(false), m_videoCodec(nullptr), m_videoCodecCtx(nullptr), m_videoSwsCtx(nullptr), m_rgbCache(nullptr), m_rgbLeftCache(nullptr), m_rgbRightCache(nullptr),
      m_videoWidth(-1), m_videoHeight(-1), m_isAudioDecodeInit(0), m_audioCodec(nullptr), m_audioContext(nullptr), m_pcmData(nullptr), m_videoFramCache(nullptr), m_videoRgbFramCache(nullptr),
      m_isMp4ParamInit(false), m_mp4outputFormatContext(nullptr), m_mp4outputFormat(nullptr), m_mp4outputVideoStream(nullptr), m_mp4FilePath(""), m_mp4codeId(AV_CODEC_ID_H264),
      m_mp4AudioCodeId(AV_CODEC_ID_AAC), m_mp4encodeContext(nullptr), m_mp4encodeCodec(nullptr), m_outPutPacket(nullptr), m_mp4OutputAudioStream(nullptr), m_mp4AudioEncodeContext(nullptr),
      m_audioSwrCtx(nullptr), m_aacFrame(nullptr), m_aacOneFrameBuf(nullptr), m_twoChannelData(nullptr), m_aacOutPacket(nullptr), m_aacAdtsOutPacket(nullptr), m_isSupportHw(false),
      m_hw_device_ctx(nullptr), m_hw_pix_fmt(AV_PIX_FMT_NONE), m_aacSwrCtx(nullptr), m_aacPcmDataBuf(nullptr), m_opusSwrCtx(nullptr), m_opusPcmDataBuf(nullptr), m_leftYuvFrame(nullptr),
      m_rightYuvFrame(nullptr), m_leftYuvCachedW(0), m_leftYuvCachedH(0), m_rightYuvCachedW(0), m_rightYuvCachedH(0), m_videoFps(15.0), m_video_time_base({1, 1000}), m_videoPtsAcc(0),
      m_lastInputTsMs(-1), m_lastVideoPts(0)
{
    m_iTimeStamp         = 0;
    m_av_time_base_q.num = 1;
    m_av_time_base_q.den = AV_TIME_BASE;
    m_hwAccel            = std::make_unique<VideoHardwareAccel>(); // 初始化硬件加速
}

DecodeVideo::~DecodeVideo()
{
    unInitVideoCodec();
    unInitG711AudioCodec();
    unInitAACAudioCodec();
    unInitOpusAudioCodec();
    unInitMp4Codec();
}

void DecodeVideo::unInitVideoCodec()
{
    m_hwAccel->unInit();
    if (m_hwStreamCounted) { // 释放本实例占用的硬件解码名额
        g_activeHwStreamCount.fetch_sub(1, std::memory_order_relaxed);
        m_hwStreamCounted = false;
    }
    m_isSupportHw = false;
    if (m_videoCodec) {
        m_videoCodec = nullptr;
    }
    if (m_rgbCache) {
        av_free(m_rgbCache);
        m_rgbCache = nullptr;
    }
    if (m_rgbLeftCache) {
        av_free(m_rgbLeftCache);
        m_rgbLeftCache = nullptr;
    }
    if (m_rgbRightCache) {
        av_free(m_rgbRightCache);
        m_rgbRightCache = nullptr;
    }
    if (m_videoRgbFramCache) {
        av_frame_free(&m_videoRgbFramCache);
        m_videoRgbFramCache = nullptr;
    }
    if (m_videoFramCache) {
        av_frame_free(&m_videoFramCache);
        m_videoFramCache = nullptr;
    }
    if (m_leftYuvFrame) {
        av_frame_free(&m_leftYuvFrame);
        m_leftYuvFrame   = nullptr;
        m_leftYuvCachedW = 0;
        m_leftYuvCachedH = 0;
    }
    if (m_rightYuvFrame) {
        av_frame_free(&m_rightYuvFrame);
        m_rightYuvFrame   = nullptr;
        m_rightYuvCachedW = 0;
        m_rightYuvCachedH = 0;
    }
    // 释放裁剪路径跨帧复用缓冲区
    if (m_cropTmpLeft) {
        av_frame_free(&m_cropTmpLeft);
        m_cropTmpLeft = nullptr;
    }
    if (m_cropTmpRight) {
        av_frame_free(&m_cropTmpRight);
        m_cropTmpRight = nullptr;
    }
    if (m_cropStretchCtx) {
        sws_freeContext(m_cropStretchCtx);
        m_cropStretchCtx = nullptr;
    }
    m_cropCachedTargetW = 0;
    m_cropCachedTargetH = 0;
    m_cropCachedCropW   = 0;

    if (m_videoCodecCtx) {
        avcodec_free_context(&m_videoCodecCtx);
        m_videoCodecCtx = nullptr;
    }
    if (m_videoSwsCtx) {
        sws_freeContext(m_videoSwsCtx);
        m_videoSwsCtx = nullptr;
    }

    freeDecodedFrames(true); // 释放结构体和内容，指针置nullptr

    clearTimestampCache(); // 清除时间戳缓存

    m_videoWidth  = -1;
    m_videoHeight = -1;
    m_isVideoInit = false;
}

void DecodeVideo::unInitG711AudioCodec()
{
    if (m_audioCodec) {
        m_audioCodec = nullptr;
    }
    if (m_pcmData) {
        av_frame_free(&m_pcmData);
        m_pcmData = nullptr;
    }
    if (m_audioContext) {
        avcodec_free_context(&m_audioContext);
        m_audioContext = nullptr;
    }

    m_isAudioDecodeInit = 0;
    m_audioTotalSamples = 0;
    m_audioFrameCount   = 0;
}

void DecodeVideo::unInitAACAudioCodec()
{
    if (m_audioCodec) {
        m_audioCodec = nullptr;
    }
    if (m_pcmData) {
        av_frame_free(&m_pcmData);
        m_pcmData = nullptr;
    }
    if (m_audioContext) {
        avcodec_free_context(&m_audioContext);
        m_audioContext = nullptr;
    }
    if (m_aacSwrCtx) {
        swr_free(&m_aacSwrCtx);
        m_aacSwrCtx = nullptr;
    }
    if (m_aacPcmDataBuf) {
        free(m_aacPcmDataBuf);
        m_aacPcmDataBuf = nullptr;
    }

    m_isAudioDecodeInit = 0;
    m_audioTotalSamples = 0;
    m_audioFrameCount   = 0;
}

void DecodeVideo::unInitOpusAudioCodec()
{
    if (m_audioCodec) {
        m_audioCodec = nullptr;
    }
    if (m_pcmData) {
        av_frame_free(&m_pcmData);
        m_pcmData = nullptr;
    }
    if (m_audioContext) {
        avcodec_free_context(&m_audioContext);
        m_audioContext = nullptr;
    }
    if (m_opusSwrCtx) {
        swr_free(&m_opusSwrCtx);
        m_opusSwrCtx = nullptr;
    }
    if (m_opusPcmDataBuf) {
        free(m_opusPcmDataBuf);
        m_opusPcmDataBuf = nullptr;
    }

    m_isAudioDecodeInit = 0;
    m_audioTotalSamples = 0;
    m_audioFrameCount   = 0;
}

bool DecodeVideo::initG711AudioCodec(const AVSampleFormat& sampltFmt, const int& channels, const int& sampltRate)
{
    if (m_isAudioDecodeInit)
        return false;
    m_audioCodec = (AVCodec*)avcodec_find_decoder(AV_CODEC_ID_PCM_ALAW);
    if (!m_audioCodec) {
        unInitG711AudioCodec();
        return false;
    }
    m_audioContext = avcodec_alloc_context3(m_audioCodec);
    if (!m_audioContext) {
        unInitG711AudioCodec();
        return false;
    }
    m_pcmData = av_frame_alloc();
    if (!m_pcmData) {
        unInitG711AudioCodec();
        return false;
    }
    m_audioContext->sample_fmt  = sampltFmt;
    m_audioContext->sample_rate = sampltRate;
    m_audioContext->channels    = channels;
    const int ret               = avcodec_open2(m_audioContext, m_audioCodec, nullptr);
    if (ret < 0) {
        char buf[1024] = {0};
        av_strerror(ret, buf, sizeof(buf));
        unInitG711AudioCodec();
        return false;
    }
    m_isAudioDecodeInit = 1;
    m_audioTotalSamples = 0;
    m_audioFrameCount   = 0;
    return true;
}

bool DecodeVideo::initAACAudioCodec(const AVSampleFormat& sampltFmt, const int& channels, const int& sampltRate)
{
    if (m_isAudioDecodeInit)
        return false;
    m_audioCodec = (AVCodec*)avcodec_find_decoder(AV_CODEC_ID_AAC);
    if (!m_audioCodec) {
        unInitAACAudioCodec();
        return false;
    }
    m_audioContext = avcodec_alloc_context3(m_audioCodec);
    if (!m_audioContext) {
        unInitAACAudioCodec();
        return false;
    }
    m_pcmData = av_frame_alloc();
    if (!m_pcmData) {
        unInitAACAudioCodec();
        return false;
    }
    m_aacSwrCtx = swr_alloc();
    if (!m_aacSwrCtx) {
        unInitAACAudioCodec();
        return false;
    }
    if (!m_aacPcmDataBuf) {
        m_aacPcmDataBuf = (uint8_t*)malloc(1 * 1024 * 1024);
        if (!m_aacPcmDataBuf) {
            // QADebug() << "Could not allocate m_aacPcmDataBuf buffer\n";
            unInitAACAudioCodec();
            return false;
        }
        memset(m_aacPcmDataBuf, 0, 1 * 1024 * 1024); // 将内存初始化为零
    }

    m_audioContext->sample_fmt     = sampltFmt;
    m_audioContext->sample_rate    = sampltRate;
    m_audioContext->channels       = channels;
    m_audioContext->channel_layout = AV_CH_LAYOUT_MONO;
    int ret                        = avcodec_open2(m_audioContext, m_audioCodec, nullptr);
    if (ret < 0) {
        char buf[1024] = {0};
        av_strerror(ret, buf, sizeof(buf));
        unInitAACAudioCodec();
        return false;
    }

    ret = av_opt_set_int(m_aacSwrCtx, "in_channel_layout", AV_CH_LAYOUT_MONO, 0);
    if (ret != 0) {
        char buf[1024] = {0};
        av_strerror(ret, buf, sizeof(buf));
        unInitAACAudioCodec();
        return false;
    }
    ret = av_opt_set_int(m_aacSwrCtx, "in_sample_rate", sampltRate, 0);
    if (ret != 0) {
        char buf[1024] = {0};
        av_strerror(ret, buf, sizeof(buf));
        unInitAACAudioCodec();
        return false;
    }
    ret = av_opt_set_sample_fmt(m_aacSwrCtx, "in_sample_fmt", sampltFmt, 0);
    if (ret != 0) {
        char buf[1024] = {0};
        av_strerror(ret, buf, sizeof(buf));
        unInitAACAudioCodec();
        return false;
    }
    ret = av_opt_set_int(m_aacSwrCtx, "out_channel_layout", AV_CH_LAYOUT_MONO, 0);
    if (ret != 0) {
        char buf[1024] = {0};
        av_strerror(ret, buf, sizeof(buf));
        unInitAACAudioCodec();
        return false;
    }
    ret = av_opt_set_int(m_aacSwrCtx, "out_sample_rate", sampltRate, 0);
    if (ret != 0) {
        char buf[1024] = {0};
        av_strerror(ret, buf, sizeof(buf));
        unInitAACAudioCodec();
        return false;
    }
    ret = av_opt_set_sample_fmt(m_aacSwrCtx, "out_sample_fmt", AV_SAMPLE_FMT_S16, 0);
    if (ret != 0) {
        char buf[1024] = {0};
        av_strerror(ret, buf, sizeof(buf));
        unInitAACAudioCodec();
        return false;
    }

    ret = swr_init(m_aacSwrCtx);
    if (ret < 0) {
        char buf[1024] = {0};
        av_strerror(ret, buf, sizeof(buf));
        unInitAACAudioCodec();
        return false;
    }

    m_isAudioDecodeInit = 2;
    m_audioTotalSamples = 0;
    m_audioFrameCount   = 0;
    return true;
}

bool DecodeVideo::initOpusAudioCodec(const AVSampleFormat& sampltFmt, const int& channels, const int& sampltRate)
{
    if (m_isAudioDecodeInit)
        return false;
    m_audioCodec = (AVCodec*)avcodec_find_decoder(AV_CODEC_ID_OPUS);
    if (!m_audioCodec) {
        unInitOpusAudioCodec();
        return false;
    }
    m_audioContext = avcodec_alloc_context3(m_audioCodec);
    if (!m_audioContext) {
        unInitOpusAudioCodec();
        return false;
    }
    m_pcmData = av_frame_alloc();
    if (!m_pcmData) {
        unInitOpusAudioCodec();
        return false;
    }
    m_opusSwrCtx = swr_alloc();
    if (!m_opusSwrCtx) {
        unInitOpusAudioCodec();
        return false;
    }
    if (!m_opusPcmDataBuf) {
        m_opusPcmDataBuf = (uint8_t*)malloc(1 * 1024 * 1024);
        if (!m_opusPcmDataBuf) {
            unInitOpusAudioCodec();
            return false;
        }
        memset(m_opusPcmDataBuf, 0, 1 * 1024 * 1024);
    }

    m_audioContext->sample_fmt     = sampltFmt;
    m_audioContext->sample_rate    = sampltRate;
    m_audioContext->channels       = channels;
    m_audioContext->channel_layout = AV_CH_LAYOUT_MONO;

    // 设备端PMT缺少0x7F扩展描述符，FFmpeg无法构建OpusHead extradata
    // 客户端手动构建标准19字节OpusHead，使avcodec_open2正确初始化Opus解码器
    {
        uint8_t opusHead[19];
        memcpy(opusHead, "OpusHead", 8);     // magic (8字节)
        opusHead[8]     = 1;                 // version
        opusHead[9]     = (uint8_t)channels; // channel_count
        opusHead[10]    = 0x38;
        opusHead[11]    = 0x01; // pre_skip = 312 (0x0138, 小端)，Opus标准推荐值
        uint32_t rateLE = (uint32_t)sampltRate;
        memcpy(opusHead + 12, &rateLE, 4); // input_sample_rate (4字节小端)
        opusHead[16] = 0;
        opusHead[17] = 0; // output_gain = 0 (2字节小端)
        opusHead[18] = 0; // channel_mapping_family = 0 (单声道/立体声用0)

        if (m_audioContext->extradata) {
            av_freep(&m_audioContext->extradata);
        }
        m_audioContext->extradata = (uint8_t*)av_mallocz(19 + AV_INPUT_BUFFER_PADDING_SIZE);
        if (m_audioContext->extradata) {
            memcpy(m_audioContext->extradata, opusHead, 19);
            m_audioContext->extradata_size = 19;
        }
    }

    int ret = avcodec_open2(m_audioContext, m_audioCodec, nullptr);
    if (ret < 0) {
        char buf[1024] = {0};
        av_strerror(ret, buf, sizeof(buf));
        unInitOpusAudioCodec();
        return false;
    }

    // avcodec_open2后回读Opus解码器实际输出参数
    // Opus解码器内部固定48000Hz，可能输出立体声，必须用实际值配置SwrContext
    int      actualSampleRate    = m_audioContext->sample_rate;
    int      actualChannels      = m_audioContext->channels;
    uint64_t actualChannelLayout = m_audioContext->channel_layout;
    // 如果channel_layout为0，根据channels推导
    if (actualChannelLayout == 0) {
        actualChannelLayout = av_get_default_channel_layout(actualChannels);
    }

    // opus解码输出为FLTP，需要重采样为S16用于QAudioOutput播放
    // 输入参数使用解码器实际输出值，输出统一为单声道48000Hz S16
    ret = av_opt_set_int(m_opusSwrCtx, "in_channel_layout", actualChannelLayout, 0);
    if (ret != 0) {
        char buf[1024] = {0};
        av_strerror(ret, buf, sizeof(buf));
        unInitOpusAudioCodec();
        return false;
    }
    ret = av_opt_set_int(m_opusSwrCtx, "in_sample_rate", actualSampleRate, 0);
    if (ret != 0) {
        char buf[1024] = {0};
        av_strerror(ret, buf, sizeof(buf));
        unInitOpusAudioCodec();
        return false;
    }
    ret = av_opt_set_sample_fmt(m_opusSwrCtx, "in_sample_fmt", sampltFmt, 0);
    if (ret != 0) {
        char buf[1024] = {0};
        av_strerror(ret, buf, sizeof(buf));
        unInitOpusAudioCodec();
        return false;
    }
    ret = av_opt_set_int(m_opusSwrCtx, "out_channel_layout", AV_CH_LAYOUT_MONO, 0);
    if (ret != 0) {
        char buf[1024] = {0};
        av_strerror(ret, buf, sizeof(buf));
        unInitOpusAudioCodec();
        return false;
    }
    ret = av_opt_set_int(m_opusSwrCtx, "out_sample_rate", actualSampleRate, 0);
    if (ret != 0) {
        char buf[1024] = {0};
        av_strerror(ret, buf, sizeof(buf));
        unInitOpusAudioCodec();
        return false;
    }
    ret = av_opt_set_sample_fmt(m_opusSwrCtx, "out_sample_fmt", AV_SAMPLE_FMT_S16, 0);
    if (ret != 0) {
        char buf[1024] = {0};
        av_strerror(ret, buf, sizeof(buf));
        unInitOpusAudioCodec();
        return false;
    }

    ret = swr_init(m_opusSwrCtx);
    if (ret < 0) {
        char buf[1024] = {0};
        av_strerror(ret, buf, sizeof(buf));
        unInitOpusAudioCodec();
        return false;
    }

    m_isAudioDecodeInit = 3;
    m_audioTotalSamples = 0;
    m_audioFrameCount   = 0;
    return true;
}

bool DecodeVideo::initVideoCodec(const bool& isH265, const int& threadCount)
{
    if (m_isVideoInit)
        return false;

    m_isH265 = isH265;

    // 硬件加速开关（VmsTools 经 ConfigureManager 读取用户配置，此处默认开启，
    // 按系统支持类型初始化硬件加速 DXVA2/D3D11VA，不支持时自动回退软解）
    m_isSupportHw = true;
#ifndef _WIN64
    // 32 位进程：虚拟内存阈值检查（唯一的硬件解码准入判断）
    // 阈值 = 进程虚拟地址空间上限 × 75%，运行时动态计算，自适应 LAA。
    // 非 LAA (2GB) → 1.5GB 阈值；LAA 3GB → 2.25GB；LAA 4GB → 3.0GB。
    // 超过阈值的新流回退软件解码，防止地址空间耗尽导致进程崩溃。
    if (m_isSupportHw) {
        const size_t virtualBytes = VideoHardwareAccel::getCommittedVirtualSize();
        const size_t threshold    = getVirtualMemThreshold();
        if (virtualBytes >= threshold) {
            m_isSupportHw = false;
            qDebug() << "[DecodeVideo] 32位进程虚拟内存已达" << (virtualBytes / 1024 / 1024) << "MB"
                     << "超过安全阈值" << (threshold / 1024 / 1024) << "MB"
                     << "本路回退软件解码";
        }
    }
#endif
    if (m_isSupportHw) {
        // 原子预留一个硬件解码名额
        const int prev = g_activeHwStreamCount.fetch_add(1, std::memory_order_relaxed);
#ifdef _WIN64
        // 64 位：路数上限检查（防止 GPU 显存耗尽）
        if (prev >= kMaxHardwareDecodeStreams) {
            g_activeHwStreamCount.fetch_sub(1, std::memory_order_relaxed);
            m_isSupportHw = false;
            qDebug() << "[DecodeVideo] 硬件解码并发已达上限" << kMaxHardwareDecodeStreams << "路，本路回退软件解码";
        } else
#endif
        {
            m_hwStreamCounted = true; // 本实例已占用一个硬件解码名额
            qDebug() << "[DecodeVideo] 本路使用硬件解码，当前硬件解码并发=" << g_activeHwStreamCount.load();
        }
        const AVCodecID codecId = isH265 ? AV_CODEC_ID_H265 : AV_CODEC_ID_H264;
        AVCodec*        codec   = (AVCodec*)avcodec_find_decoder(codecId);
        if (codec && m_hwAccel->init(codec, isH265)) {
            m_videoCodec    = codec;
            m_videoCodecCtx = avcodec_alloc_context3(m_videoCodec);
            if (!m_videoCodecCtx) {
                m_hwAccel->unInit();
                unInitVideoCodec();
                return false;
            }

            // 移除 AV_EF_EXPLODE：25路高码率流网络抖动时 EXPLODE 会直接 abort 进程
            // 保留 CRCCHECK + CAREFUL 即可检测错误帧，不会导致崩溃
            m_videoCodecCtx->err_recognition = AV_EF_CRCCHECK | AV_EF_CAREFUL;
            m_videoCodecCtx->codec_type      = AVMEDIA_TYPE_VIDEO;
            // 硬件解码设 thread_count=1：GPU 解码本身是并行的，不需要 CPU 端多线程。
            // 若不限制，FFmpeg 会按 CPU 核心数创建线程（8-16），每个线程在 D3D11VA
            // 表面池中分配独立的解码表面，导致每路超清流占用 500MB+ 虚拟内存。
            // thread_count=1 后表面池仅保留参考帧所需的最小数量，
            // 每路超清流从 ~520MB 降至 ~80-100MB。
            m_videoCodecCtx->thread_count = 1;
            m_videoCodecCtx->thread_type  = 0; // 禁用帧级/片级线程，配合 thread_count=1
            // 告知解码器使用硬件像素格式，并通过 opaque 回传本对象
            m_videoCodecCtx->get_format    = VideoHardwareAccel::getFormatCallback;
            m_videoCodecCtx->opaque        = m_hwAccel.get();
            m_videoCodecCtx->hw_device_ctx = av_buffer_ref(m_hwAccel->hwDeviceCtx());

            m_videoFramCache = av_frame_alloc();
            if (!m_videoFramCache) {
                unInitVideoCodec();
                return false;
            }
            m_videoRgbFramCache = av_frame_alloc();
            if (!m_videoRgbFramCache) {
                unInitVideoCodec();
                return false;
            }

            // 诊断：测量 avcodec_open2 前后的虚拟内存增量，
            // 确认每路硬件解码初始化消耗多少虚拟地址空间。
            const size_t virtualBytesBefore = VideoHardwareAccel::getCommittedVirtualSize();
            const int    ret                = avcodec_open2(m_videoCodecCtx, m_videoCodec, nullptr);
            if (ret < 0) {
                unInitVideoCodec();
                return false;
            }
            const size_t virtualBytesAfter = VideoHardwareAccel::getCommittedVirtualSize();
            const size_t deltaMB           = (virtualBytesAfter - virtualBytesBefore) / 1024 / 1024;
            // qDebug() << "[DecodeVideo] avcodec_open2 内存增量"
            // 		 << "delta=" << deltaMB << "MB"
            // 		 << "thread_count=" << m_videoCodecCtx->thread_count
            // 		 << "hw_frames_ctx=" << (m_videoCodecCtx->hw_frames_ctx ? "yes" : "null")
            // 		 << "res=" << m_videoCodecCtx->width << "x" << m_videoCodecCtx->height;

            m_isVideoInit      = true;
            m_needWaitKeyFrame = true; // 新解码器必须等首个 I 帧：seek/倍速/清晰度切换重建后，避免无参考帧解 P 帧导致花屏
            return true;
        }
        // 硬件加速不可用，回退软件解码
        m_isSupportHw = false;
        if (m_hwStreamCounted) { // 释放预留的硬件解码名额
            g_activeHwStreamCount.fetch_sub(1, std::memory_order_relaxed);
            m_hwStreamCounted = false;
        }
        m_hwAccel->unInit();
    }

    // 软件解码（原有逻辑）
    {
        const auto codecId(isH265 ? AV_CODEC_ID_H265 : AV_CODEC_ID_H264);
        m_videoCodec = (AVCodec*)avcodec_find_decoder(codecId);
        if (!m_videoCodec) {
            unInitVideoCodec();
            return false;
        }
        m_videoCodecCtx = avcodec_alloc_context3(m_videoCodec);
        if (!m_videoCodecCtx) {
            unInitVideoCodec();
            return false;
        }

        // 移除 AV_EF_EXPLODE：25路高码率流网络抖动时 EXPLODE 会直接 abort 进程
        // 保留 CRCCHECK + CAREFUL 即可检测错误帧，不会导致崩溃
        m_videoCodecCtx->err_recognition = AV_EF_CRCCHECK | AV_EF_CAREFUL;

        m_videoFramCache = av_frame_alloc();
        if (!m_videoFramCache) {
            unInitVideoCodec();
            return false;
        }
        m_videoRgbFramCache = av_frame_alloc();
        if (!m_videoRgbFramCache) {
            unInitVideoCodec();
            return false;
        }
        m_videoCodecCtx->codec_type = AVMEDIA_TYPE_VIDEO;
        m_videoCodecCtx->codec_id   = codecId;
        m_videoCodecCtx->pix_fmt    = AV_PIX_FMT_YUV420P;

        // 诊断：测量软件解码 avcodec_open2 的虚拟内存增量
        const size_t virtualBytesBeforeSw = VideoHardwareAccel::getCommittedVirtualSize();
        const int    ret                  = avcodec_open2(m_videoCodecCtx, m_videoCodec, nullptr);
        const size_t virtualBytesAfterSw  = VideoHardwareAccel::getCommittedVirtualSize();
        if (ret < 0) {
            char buf[1024] = {0};
            av_strerror(ret, buf, sizeof(buf));
            unInitVideoCodec();
            return false;
        }

        m_isVideoInit      = true;
        m_needWaitKeyFrame = true; // 新解码器必须等首个 I 帧：seek/倍速/清晰度切换重建后，避免无参考帧解 P 帧导致花屏
        return true;
    }
}

AVFrame* DecodeVideo::decodeG711Audio(unsigned char* data, const int& dataLen)
{
    if (1 != m_isAudioDecodeInit)
        return nullptr;
    if (!data || !dataLen)
        return nullptr;

    AVPacket* avpkt = av_packet_alloc();
    if (!avpkt) {
        return nullptr;
    }

    avpkt->size         = dataLen;
    avpkt->data         = data;
    avpkt->stream_index = 1;
    avpkt->dts = avpkt->pts = 0;

    int ret = avcodec_send_packet(m_audioContext, avpkt);
    if (ret < 0) {
        av_packet_free(&avpkt);
        return nullptr;
    }
    bool findFrame(false);
    while (ret >= 0) {
        ret = avcodec_receive_frame(m_audioContext, m_pcmData);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF || ret < 0) {
            break;
        }
        findFrame = true;
        break;
    }
    av_packet_free(&avpkt);
    if (findFrame) {
        return m_pcmData;
    }
    return nullptr;
}

AVFrame* DecodeVideo::decodeAAcAudio(unsigned char* data, const int& dataLen)
{
    if (2 != m_isAudioDecodeInit)
        return nullptr;
    if (!data || !dataLen)
        return nullptr;

    AVPacket* avpkt = av_packet_alloc();
    if (!avpkt) {
        return nullptr;
    }

    avpkt->size         = dataLen;
    avpkt->data         = data;
    avpkt->stream_index = 1;
    avpkt->dts = avpkt->pts = 0;

    int ret = avcodec_send_packet(m_audioContext, avpkt);
    if (ret < 0) {
        av_packet_free(&avpkt);
        return nullptr;
    }
    bool findFrame(false);
    while (ret >= 0) {
        ret = avcodec_receive_frame(m_audioContext, m_pcmData);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF || ret < 0) {
            break;
        }
        findFrame = true;
        break;
    }
    av_packet_free(&avpkt);
    if (findFrame) {
        /*int resampled_data_size = av_samples_get_buffer_size(NULL, 1, m_pcmData->nb_samples, AV_SAMPLE_FMT_S16, 1);
        swr_convert(m_aacSwrCtx, &m_aacPcmDataBuf, 1 * 1024 * 1024, (const uint8_t**)m_pcmData->data, m_pcmData->nb_samples);
        memset(m_pcmData->data[0], 0, m_pcmData->linesize[0]);
        memcpy(m_pcmData->data[0], m_aacPcmDataBuf, resampled_data_size);
        m_pcmData->linesize[0] = resampled_data_size;*/

        int resampled_data_size = av_samples_get_buffer_size(NULL, 1, m_pcmData->nb_samples, AV_SAMPLE_FMT_S16, 1);

        // 使用指针直接操作，而非memcpy
        uint8_t* pcmDataPtr       = m_pcmData->data[0];
        uint8_t* resampledDataPtr = m_aacPcmDataBuf;

        swr_convert(m_aacSwrCtx, &m_aacPcmDataBuf, 1 * 1024 * 1024, (const uint8_t**)m_pcmData->data, m_pcmData->nb_samples);

        // 清空原数据区域并拷贝新的数据
        // 直接通过指针操作替换内存区域的内容
        for (int i = 0; i < resampled_data_size; i++) {
            pcmDataPtr[i] = resampledDataPtr[i];
        }

        m_pcmData->linesize[0] = resampled_data_size;

        return m_pcmData;
    }
    return nullptr;
}

AVFrame* DecodeVideo::decodeOpusAudio(unsigned char* data, const int& dataLen)
{
    if (3 != m_isAudioDecodeInit)
        return nullptr;
    if (!data || !dataLen)
        return nullptr;

    AVPacket* avpkt = av_packet_alloc();
    if (!avpkt) {
        return nullptr;
    }

    avpkt->size         = dataLen;
    avpkt->data         = data;
    avpkt->stream_index = 1;
    avpkt->dts = avpkt->pts = 0;

    int ret = avcodec_send_packet(m_audioContext, avpkt);
    if (ret < 0) {
        av_packet_free(&avpkt);
        return nullptr;
    }
    bool findFrame(false);
    while (ret >= 0) {
        ret = avcodec_receive_frame(m_audioContext, m_pcmData);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF || ret < 0) {
            break;
        }
        findFrame = true;
        break;
    }
    av_packet_free(&avpkt);
    if (findFrame) {
        // opus解码输出为FLTP，重采样为S16格式用于播放
        int resampled_data_size = av_samples_get_buffer_size(NULL, 1, m_pcmData->nb_samples, AV_SAMPLE_FMT_S16, 1);

        uint8_t* pcmDataPtr       = m_pcmData->data[0];
        uint8_t* resampledDataPtr = m_opusPcmDataBuf;

        swr_convert(m_opusSwrCtx, &m_opusPcmDataBuf, 1 * 1024 * 1024, (const uint8_t**)m_pcmData->data, m_pcmData->nb_samples);

        for (int i = 0; i < resampled_data_size; i++) {
            pcmDataPtr[i] = resampledDataPtr[i];
        }

        m_pcmData->linesize[0] = resampled_data_size;

        return m_pcmData;
    }
    return nullptr;
}

QByteArray DecodeVideo::encodeG711Audio(unsigned char* frameData, const int& frameDataLen)
{

    if (!frameData || frameDataLen <= 0)
        return QByteArray();

    QByteArray data;
    data.resize(frameDataLen / 2);
    G711_EnCode(data.data(), frameData, frameDataLen, 0);

    return data;
}

void DecodeVideo::pause()
{
    m_needWaitKeyFrame = true;
    if (m_videoCodecCtx) {
        avcodec_flush_buffers(m_videoCodecCtx); // 清除内部参考帧缓存
    }
}

bool DecodeVideo::isAbnormalFrame(AVFrame* frame)
{
    if (!frame || !frame->data[0])
        return true;

    // 优化：采样检测替代逐像素扫描，25路并发时从 7.5亿次/秒 降到 ~75万次/秒
    // 每隔 8 行 8 列采样一个像素，覆盖率足够判断灰屏异常
    const int step      = 8;
    int       grayCount = 0, total = 0;
    uint8_t*  y        = frame->data[0];
    int       linesize = frame->linesize[0];

    for (int h = 0; h < frame->height; h += step) {
        for (int w = 0; w < frame->width; w += step) {
            uint8_t pixel = y[h * linesize + w];
            total++;
            if (pixel >= 120 && pixel <= 135)
                grayCount++;
        }
    }

    // 超过一定比例视为灰屏
    if (total > 0 && grayCount * 100 / total > 80)
        return true;

    return false;
}

void DecodeVideo::clearTimestampCache()
{
    m_cachedTimestampImage = QImage();
    m_lastTimestampSecond  = -1;
    m_lastTimeString.clear();
}

void DecodeVideo::addTimestampToYuvFrame(AVFrame* frame, const QDateTime& timestamp)
{
    if (!frame)
        return;

    const int width  = frame->width;
    const int height = frame->height;

    if (width <= 0 || height <= 0)
        return;

    // 获取当前时间戳（精确到秒）
    qint64 currentSecond = timestamp.toSecsSinceEpoch();

    // 如果时间戳不同或图像尺寸不同，则重新绘制
    if (currentSecond != m_lastTimestampSecond || m_cachedTimestampImage.width() != width || m_cachedTimestampImage.height() != height) {

        // 更新缓存时间
        m_lastTimestampSecond = currentSecond;
        m_lastTimeString      = timestamp.toString("yyyy-MM-dd HH:mm:ss");

        // 重新创建图像并绘制时间戳
        m_cachedTimestampImage = QImage(width, height, QImage::Format_ARGB32_Premultiplied);
        if (m_cachedTimestampImage.isNull()) {
            qWarning() << "LOG::Image memory allocation failed: width: " << width << " height: " << height;
            return;
        }
        m_cachedTimestampImage.fill(Qt::transparent);

        QPainter painter(&m_cachedTimestampImage);
        painter.setPen(Qt::white);
        QFont font = painter.font();
        font.setFamily("Arial");
        font.setPointSize(qMax(10, height / 30));
        font.setBold(true);
        painter.setFont(font);

        QRect textRect = painter.boundingRect(10, 10, width - 20, 50, Qt::TextSingleLine, m_lastTimeString);
        painter.drawText(textRect, m_lastTimeString);
        painter.end();
    }

    // 将缓存图像叠加到 YUV 帧上
    uint8_t* yuvData[4];
    int      linesize[4];
    for (int i = 0; i < 4; ++i) {
        yuvData[i]  = frame->data[i];
        linesize[i] = frame->linesize[i];
    }

    // 转换 Y 分量（亮度）
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const QRgb pixel = m_cachedTimestampImage.pixel(x, y);
            if (qAlpha(pixel) > 0) {
                int r                           = qRed(pixel);
                int g                           = qGreen(pixel);
                int b                           = qBlue(pixel);
                int yValue                      = static_cast<int>(0.299 * r + 0.587 * g + 0.114 * b);
                yuvData[0][y * linesize[0] + x] = static_cast<uint8_t>(qBound(0, yValue, 255));
            }
        }
    }

    // 转换 U/V 分量（色度），按 YUV420 格式 2x2 块采样
    const int uvWidth  = width / 2;
    const int uvHeight = height / 2;

    for (int y = 0; y < uvHeight; ++y) {
        for (int x = 0; x < uvWidth; ++x) {
            int uX = 2 * x;
            int uY = 2 * y;
            int vX = qMin(uX + 1, width - 1);
            int vY = qMin(uY + 1, height - 1);

            const QRgb pixelU = m_cachedTimestampImage.pixel(uX, uY);
            const QRgb pixelV = m_cachedTimestampImage.pixel(vX, vY);

            if (qAlpha(pixelU) > 0 || qAlpha(pixelV) > 0) {
                int rU = qRed(pixelU);
                int gU = qGreen(pixelU);
                int bU = qBlue(pixelU);

                int rV = qRed(pixelV);
                int gV = qGreen(pixelV);
                int bV = qBlue(pixelV);

                int uValue = static_cast<int>(-0.14713 * rU - 0.28886 * gU + 0.436 * bU + 128.0);
                int vValue = static_cast<int>(0.615 * rV - 0.51499 * gV - 0.10001 * bV + 128.0);

                yuvData[1][y * linesize[1] + x] = static_cast<uint8_t>(qBound(0, uValue, 255));
                yuvData[2][y * linesize[2] + x] = static_cast<uint8_t>(qBound(0, vValue, 255));
            }
        }
    }
}

DecodedFrames DecodeVideo::decodeVideo(unsigned char* data, const int& dataLen, int frameFlags)
{
    freeDecodedFrames(false); // 只清空帧内容，不释放结构体本身

    if (!m_isVideoInit || !data || !dataLen)
        return m_outVideoFrames;

    // 周期性出流内存日志：每 75 帧（~5秒@15fps）打印一次进程内存和硬件解码状态，
    // 帮助实时监控 32 位地址空间压力，及时发现碎片化或 OOM 趋势。
    // const int logCounter = g_memLogFrameCounter.fetch_add(1, std::memory_order_relaxed);
    // if (logCounter % kMemLogIntervalFrames == 0) {
    //     const size_t virtualBytes = VideoHardwareAccel::getCommittedVirtualSize();
    //     qDebug() << "[DecodeVideo] 出流内存监控"
    //              << "virtualBytes=" << (virtualBytes / 1024 / 1024) << "MB"
    //              << "hwStreams=" << g_activeHwStreamCount.load()
    //              << "hw=" << m_isSupportHw
    //              << "res=" << m_videoWidth << "x" << m_videoHeight;
    // }

    const bool needOriginalYuv = (frameFlags & ORIGINAL_YUV) || (frameFlags & ORIGINAL_RGB);
    const bool needLeftYuv     = (frameFlags & LEFT_YUV) || (frameFlags & LEFT_RGB);
    const bool needRightYuv    = (frameFlags & RIGHT_YUV) || (frameFlags & RIGHT_RGB);
    const bool needOriginalRgb = frameFlags & ORIGINAL_RGB;
    const bool needLeftRgb     = frameFlags & LEFT_RGB;
    const bool needRightRgb    = frameFlags & RIGHT_RGB;
    const bool needAnyCrop     = needLeftYuv || needRightYuv || needLeftRgb || needRightRgb;

    {
        AVPacket* avpkt = av_packet_alloc();
        if (!avpkt)
            return m_outVideoFrames;
        avpkt->size         = dataLen;
        avpkt->data         = data;
        avpkt->stream_index = 0;
        avpkt->dts = avpkt->pts = 0;
        if (m_isH265)
            avpkt->flags |= AV_PKT_FLAG_KEY;

        int ret = avcodec_send_packet(m_videoCodecCtx, avpkt);
        if (ret < 0) {
            av_packet_free(&avpkt);
            return m_outVideoFrames;
        }

        bool findFrame = false;
        while (ret >= 0) {
            ret = avcodec_receive_frame(m_videoCodecCtx, m_videoFramCache);
            if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF)
                break;
            if (ret < 0)
                break;

            if (m_needWaitKeyFrame) {
                if (m_videoFramCache->pict_type == AV_PICTURE_TYPE_I)
                    m_needWaitKeyFrame = false;
                else {
                    av_packet_free(&avpkt);
                    return m_outVideoFrames;
                }
            }
            findFrame = true;
            break;
        }
        av_packet_free(&avpkt);
        if (!findFrame)
            return m_outVideoFrames;
        if (isAbnormalFrame(m_videoFramCache))
            return m_outVideoFrames;

        // 硬件加速：将硬件帧直接下载+转换为 CPU 端 YUV420P 帧
        if (m_isSupportHw && m_hwAccel->isEnabled()) {
            const AVPixFmtDescriptor* hwDesc = av_pix_fmt_desc_get(static_cast<AVPixelFormat>(m_videoFramCache->format));
            if (hwDesc && (hwDesc->flags & AV_PIX_FMT_FLAG_HWACCEL)) {
                // 保存 HW 帧元数据（av_frame_unref 后将丢失）
                const int           hwW        = m_videoFramCache->width;
                const int           hwH        = m_videoFramCache->height;
                const int64_t       hwPts      = m_videoFramCache->pts;
                const int64_t       hwPktDts   = m_videoFramCache->pkt_dts;
                const int           hwKeyFrame = m_videoFramCache->key_frame;
                const AVPictureType hwPictType = m_videoFramCache->pict_type;

                // 步骤 1：将 HW 帧下载到 NV12 中间帧（m_transferFrame）
                // 必须在 av_frame_unref 之前完成，因为 unref 后 HW 帧数据不可访问
                if (!m_hwAccel->hwDownloadToIntermediate(m_videoFramCache)) {
                    return m_outVideoFrames; // hwdownload 失败，丢弃本帧
                }

                // 释放 HW 帧引用（数据已下载到 m_transferFrame，可安全释放）
                av_frame_unref(m_videoFramCache);

                // 步骤 2：分配引用计数的 YUV420P 缓冲区
                // 优化：如果分辨率未变，复用上一帧的缓冲区（避免每帧 malloc/free 导致
                // 32 位多路并发时虚拟地址碎片化和 OOM 崩溃）。
                // av_frame_get_buffer 创建 AVBufferRef，使下游 av_frame_ref 为浅拷贝
                // （共享数据、引用计数管理），省去深拷贝。对齐 32 满足 sws_scale SIMD 要求。
                m_videoFramCache->format = AV_PIX_FMT_YUV420P;
                m_videoFramCache->width  = hwW;
                m_videoFramCache->height = hwH;
                // 仅在分辨率变化时重新分配缓冲区，否则复用已有缓冲区
                bool needRealloc = !m_videoFramCache->data[0] || m_videoFramCache->linesize[0] < hwW || m_videoFramCache->height != hwH;
                if (needRealloc) {
                    if (av_frame_get_buffer(m_videoFramCache, 32) < 0) {
                        return m_outVideoFrames;
                    }
                }

                // 步骤 3：从 NV12 中间帧直接 sws_scale 到 m_videoFramCache
                // 省去 m_cpuFrame 中间缓存和 av_image_copy 深拷贝，
                // 32 位多路并发时显著降低内存峰值
                if (!m_hwAccel->scaleFromIntermediate(m_videoFramCache, hwW, hwH)) {
                    return m_outVideoFrames;
                }

                // 恢复元数据
                m_videoFramCache->pts       = hwPts;
                m_videoFramCache->pkt_dts   = hwPktDts;
                m_videoFramCache->key_frame = hwKeyFrame;
                m_videoFramCache->pict_type = hwPictType;
            }
        }

        m_videoWidth  = m_videoCodecCtx->width;
        m_videoHeight = m_videoCodecCtx->height;
    }

    int targetWidth  = m_videoWidth;
    int targetHeight = m_videoHeight;

    auto assign_ref_frame = [&](AVFrame* src, AVFrame*& dst, FrameRequest flag) {
        if (!src)
            return;
        // 复用 AVFrame 结构体：仅释放数据引用，不 free 结构体本身，
        // 避免每帧 alloc/free 小块内存导致 32 位地址空间碎片化。
        if (dst) {
            av_frame_unref(dst); // 释放旧数据引用，保留结构体供复用
        } else {
            dst = av_frame_alloc(); // 仅首次分配结构体
            if (!dst)
                return;
        }
        if (av_frame_ref(dst, src) < 0) {
            av_frame_unref(dst); // ref 失败时只清空数据，不 free 结构体
            return;
        }
        m_outVideoFrames.setValid(flag);
    };

    if (needOriginalYuv) {
        assign_ref_frame(m_videoFramCache, m_outVideoFrames.originalYuv, ORIGINAL_YUV);
    }

    int cropWidth    = static_cast<int>(targetWidth * 0.3);
    cropWidth        = (cropWidth + 1) & ~1;
    int croppedWidth = targetWidth - cropWidth;

    if (needAnyCrop && croppedWidth > 0) {
        bool cropSuccess = false;

        // ---- 裁剪临时帧：跨帧复用，仅分辨率变化时重分配 ----
        // 替换原来的每帧 av_image_alloc + av_freep，消除 ~4MB/帧 的碎片化 alloc/free
        if (!m_cropTmpLeft)
            m_cropTmpLeft = av_frame_alloc();
        if (!m_cropTmpRight)
            m_cropTmpRight = av_frame_alloc();
        bool needReallocTmp = !m_cropTmpLeft->data[0] || m_cropCachedCropW != croppedWidth || m_cropCachedTargetH != targetHeight;
        if (needReallocTmp) {
            av_frame_unref(m_cropTmpLeft);
            m_cropTmpLeft->format = AV_PIX_FMT_YUV420P;
            m_cropTmpLeft->width  = croppedWidth;
            m_cropTmpLeft->height = targetHeight;
            if (av_frame_get_buffer(m_cropTmpLeft, 32) < 0) {
                cropSuccess = false;
            } else {
                av_frame_unref(m_cropTmpRight);
                m_cropTmpRight->format = AV_PIX_FMT_YUV420P;
                m_cropTmpRight->width  = croppedWidth;
                m_cropTmpRight->height = targetHeight;
                if (av_frame_get_buffer(m_cropTmpRight, 32) < 0) {
                    cropSuccess = false;
                } else {
                    m_cropCachedCropW   = croppedWidth;
                    m_cropCachedTargetH = targetHeight;
                }
            }
        } else {
            av_frame_make_writable(m_cropTmpLeft);
            av_frame_make_writable(m_cropTmpRight);
        }

        if (m_cropTmpLeft->data[0] && m_cropTmpRight->data[0]) {

            for (int i = 0; i < targetHeight; ++i) {
                memcpy(m_cropTmpLeft->data[0] + i * m_cropTmpLeft->linesize[0], m_videoFramCache->data[0] + i * m_videoFramCache->linesize[0], croppedWidth);
                memcpy(m_cropTmpRight->data[0] + i * m_cropTmpRight->linesize[0], m_videoFramCache->data[0] + i * m_videoFramCache->linesize[0] + cropWidth, croppedWidth);
            }
            int uvHeight    = targetHeight / 2;
            int uvCropWidth = croppedWidth / 2;
            for (int i = 0; i < uvHeight; ++i) {
                memcpy(m_cropTmpLeft->data[1] + i * m_cropTmpLeft->linesize[1], m_videoFramCache->data[1] + i * m_videoFramCache->linesize[1], uvCropWidth);
                memcpy(m_cropTmpLeft->data[2] + i * m_cropTmpLeft->linesize[2], m_videoFramCache->data[2] + i * m_videoFramCache->linesize[2], uvCropWidth);

                memcpy(m_cropTmpRight->data[1] + i * m_cropTmpRight->linesize[1], m_videoFramCache->data[1] + i * m_videoFramCache->linesize[1] + cropWidth / 2, uvCropWidth);
                memcpy(m_cropTmpRight->data[2] + i * m_cropTmpRight->linesize[2], m_videoFramCache->data[2] + i * m_videoFramCache->linesize[2] + cropWidth / 2, uvCropWidth);
            }

            // ---- 裁剪输出帧：跨帧复用，仅分辨率变化时重分配 ----
            // 替换原来的每帧 av_freep + av_image_alloc，消除 ~6MB/帧 的碎片化 alloc/free
            // av_frame_get_buffer 创建引用计数缓冲区，使下游 av_frame_ref 为浅拷贝
            if (!m_leftYuvFrame)
                m_leftYuvFrame = av_frame_alloc();
            if (!m_rightYuvFrame)
                m_rightYuvFrame = av_frame_alloc();

            bool needReallocLeft  = !m_leftYuvFrame->data[0] || m_leftYuvCachedW != targetWidth || m_leftYuvCachedH != targetHeight;
            bool needReallocRight = !m_rightYuvFrame->data[0] || m_rightYuvCachedW != targetWidth || m_rightYuvCachedH != targetHeight;

            bool allocOk = true;
            if (needReallocLeft) {
                av_frame_unref(m_leftYuvFrame);
                m_leftYuvFrame->format = AV_PIX_FMT_YUV420P;
                m_leftYuvFrame->width  = targetWidth;
                m_leftYuvFrame->height = targetHeight;
                if (av_frame_get_buffer(m_leftYuvFrame, 32) < 0) {
                    allocOk = false;
                } else {
                    m_leftYuvCachedW = targetWidth;
                    m_leftYuvCachedH = targetHeight;
                }
            } else {
                av_frame_make_writable(m_leftYuvFrame);
            }

            if (allocOk && needReallocRight) {
                av_frame_unref(m_rightYuvFrame);
                m_rightYuvFrame->format = AV_PIX_FMT_YUV420P;
                m_rightYuvFrame->width  = targetWidth;
                m_rightYuvFrame->height = targetHeight;
                if (av_frame_get_buffer(m_rightYuvFrame, 32) < 0) {
                    allocOk = false;
                } else {
                    m_rightYuvCachedW = targetWidth;
                    m_rightYuvCachedH = targetHeight;
                }
            } else if (allocOk) {
                av_frame_make_writable(m_rightYuvFrame);
            }

            if (allocOk && m_leftYuvFrame->data[0] && m_rightYuvFrame->data[0]) {
                // ---- 裁剪拉伸上下文：跨帧复用，仅尺寸变化时重建 ----
                bool needReallocStretch = !m_cropStretchCtx || m_cropCachedCropW != croppedWidth || m_cropCachedTargetW != targetWidth || m_cropCachedTargetH != targetHeight;
                if (needReallocStretch) {
                    if (m_cropStretchCtx) {
                        sws_freeContext(m_cropStretchCtx);
                        m_cropStretchCtx = nullptr;
                    }
                    m_cropStretchCtx = sws_getContext(croppedWidth, targetHeight, AV_PIX_FMT_YUV420P, targetWidth, targetHeight, AV_PIX_FMT_YUV420P, SWS_FAST_BILINEAR, nullptr, nullptr, nullptr);
                    if (m_cropStretchCtx) {
                        m_cropCachedCropW   = croppedWidth;
                        m_cropCachedTargetW = targetWidth;
                        m_cropCachedTargetH = targetHeight;
                    }
                }

                if (m_cropStretchCtx) {
                    if (m_leftYuvFrame && m_leftYuvFrame->data[0]) {
                        sws_scale(m_cropStretchCtx, m_cropTmpLeft->data, m_cropTmpLeft->linesize, 0, targetHeight, m_leftYuvFrame->data, m_leftYuvFrame->linesize);
                    }
                    if (m_rightYuvFrame && m_rightYuvFrame->data[0]) {
                        sws_scale(m_cropStretchCtx, m_cropTmpRight->data, m_cropTmpRight->linesize, 0, targetHeight, m_rightYuvFrame->data, m_rightYuvFrame->linesize);
                    }

                    for (AVFrame* frame : {m_leftYuvFrame, m_rightYuvFrame}) {
                        frame->width     = targetWidth;
                        frame->height    = targetHeight;
                        frame->format    = m_videoFramCache->format;
                        frame->pkt_dts   = m_videoFramCache->pkt_dts;
                        frame->opaque    = m_videoFramCache->opaque;
                        frame->key_frame = m_videoFramCache->key_frame;
                    }

                    AVRational internalBase   = {1, static_cast<int>(m_videoFps)};
                    AVRational streamTimeBase = m_videoStream ? m_videoStream->time_base : internalBase;
                    if (m_leftYuvFrame && m_leftYuvFrame->data[0]) {
                        int64_t idxLeft     = m_cropOutputFrameIndex++;
                        m_leftYuvFrame->pts = av_rescale_q(idxLeft, internalBase, streamTimeBase);
                    }
                    if (m_rightYuvFrame && m_rightYuvFrame->data[0]) {
                        int64_t idxRight     = m_cropOutputFrameIndex++;
                        m_rightYuvFrame->pts = av_rescale_q(idxRight, internalBase, streamTimeBase);
                    }

                    if (needRightYuv && m_rightYuvFrame && m_rightYuvFrame->data[0]) {
                        qint64    timestampMs      = timeStamp();
                        QDateTime currentTimestamp = QDateTime::fromSecsSinceEpoch(timestampMs);
                        if (currentTimestamp.isValid() && !currentTimestamp.isNull() && currentTimestamp.date().year() == QDateTime::currentDateTime().date().year()) {
                            addTimestampToYuvFrame(m_rightYuvFrame, currentTimestamp);
                        }
                    }

                    if (needLeftYuv && m_leftYuvFrame && m_leftYuvFrame->data[0]) {
                        assign_ref_frame(m_leftYuvFrame, m_outVideoFrames.leftYuv, LEFT_YUV);
                    }
                    if (needRightYuv && m_rightYuvFrame && m_rightYuvFrame->data[0]) {
                        assign_ref_frame(m_rightYuvFrame, m_outVideoFrames.rightYuv, RIGHT_YUV);
                    }
                    cropSuccess = true;
                }
            }
        }

        if (!cropSuccess) {
            if (m_leftYuvFrame) {
                av_frame_unref(m_leftYuvFrame);
                m_leftYuvCachedW = 0;
                m_leftYuvCachedH = 0;
            }
            if (m_rightYuvFrame) {
                av_frame_unref(m_rightYuvFrame);
                m_rightYuvCachedW = 0;
                m_rightYuvCachedH = 0;
            }
        }
    }

    auto convertYuvToRgbCached = [&](AVFrame* srcYuv, AVFrame*& dstRgb, unsigned char*& cache, int width, int height) {
        // 基本校验
        if (!srcYuv || !srcYuv->data[0])
            return;
        const int srcW = srcYuv->width;
        const int srcH = srcYuv->height;
        if (srcW <= 0 || srcH <= 0 || width <= 0 || height <= 0)
            return;

        // 源像素格式（可能并非固定 YUV420P）
        AVPixelFormat             srcFmt = static_cast<AVPixelFormat>(srcYuv->format);
        const AVPixFmtDescriptor* desc   = av_pix_fmt_desc_get(srcFmt);
        if (!desc)
            return;

        // 跳过硬件像素格式（需先做 hwframe download，当前仅防御避免崩溃）
        if (desc->flags & AV_PIX_FMT_FLAG_HWACCEL)
            return;

        // 目标帧与缓存按分辨率变化重建
        if (!dstRgb)
            dstRgb = av_frame_alloc();
        const int bufSize = av_image_get_buffer_size(AV_PIX_FMT_RGB32, width, height, 1);
        if (bufSize <= 0)
            return;
        const bool needRealloc = (!cache) || (dstRgb->width != width) || (dstRgb->height != height) || (dstRgb->format != AV_PIX_FMT_RGB32);
        if (needRealloc) {
            if (cache) {
                av_free(cache);
                cache = nullptr;
            }
            cache = static_cast<unsigned char*>(av_malloc(bufSize));
            if (!cache)
                return;
            if (av_image_fill_arrays(dstRgb->data, dstRgb->linesize, cache, AV_PIX_FMT_RGB32, width, height, 1) < 0) {
                av_free(cache);
                cache = nullptr;
                return;
            }
            dstRgb->width  = width;
            dstRgb->height = height;
            dstRgb->format = AV_PIX_FMT_RGB32;
        }

        // 复用/更新缩放上下文（避免频繁创建/释放）
        m_videoSwsCtx = sws_getCachedContext(m_videoSwsCtx, srcW, srcH, srcFmt, width, height, AV_PIX_FMT_RGB32, SWS_FAST_BILINEAR, nullptr, nullptr, nullptr);
        if (!m_videoSwsCtx)
            return;

        sws_scale(m_videoSwsCtx, (const uint8_t* const*)srcYuv->data, srcYuv->linesize, 0, srcH, dstRgb->data, dstRgb->linesize);
    };

    if (needOriginalRgb) {
        convertYuvToRgbCached(m_videoFramCache, m_outVideoFrames.originalRgb, m_rgbCache, targetWidth, targetHeight);
        if (m_outVideoFrames.originalRgb)
            m_outVideoFrames.setValid(ORIGINAL_RGB);
    }
    if (needLeftRgb && m_leftYuvFrame) {
        convertYuvToRgbCached(m_leftYuvFrame, m_outVideoFrames.leftRgb, m_rgbLeftCache, targetWidth, targetHeight);
        if (m_outVideoFrames.leftRgb)
            m_outVideoFrames.setValid(LEFT_RGB);
    }
    if (needRightRgb && m_rightYuvFrame) {
        convertYuvToRgbCached(m_rightYuvFrame, m_outVideoFrames.rightRgb, m_rgbRightCache, targetWidth, targetHeight);
        if (m_outVideoFrames.rightRgb)
            m_outVideoFrames.setValid(RIGHT_RGB);
    }

    return m_outVideoFrames;
}

void DecodeVideo::freeDecodedFrames(const bool& isFreeAll)
{
    if (m_outVideoFrames.originalYuv) {
        av_frame_unref(m_outVideoFrames.originalYuv);
        if (isFreeAll) {
            av_frame_free(&m_outVideoFrames.originalYuv);
            m_outVideoFrames.originalYuv = nullptr;
        }
    }
    if (m_outVideoFrames.leftYuv) {
        av_frame_unref(m_outVideoFrames.leftYuv);
        if (isFreeAll) {
            av_frame_free(&m_outVideoFrames.leftYuv);
            m_outVideoFrames.leftYuv = nullptr;
        }
    }
    if (m_outVideoFrames.rightYuv) {
        av_frame_unref(m_outVideoFrames.rightYuv);
        if (isFreeAll) {
            av_frame_free(&m_outVideoFrames.rightYuv);
            m_outVideoFrames.rightYuv = nullptr;
        }
    }
    if (m_outVideoFrames.originalRgb) {
        av_frame_unref(m_outVideoFrames.originalRgb);
        if (isFreeAll) {
            av_frame_free(&m_outVideoFrames.originalRgb);
            m_outVideoFrames.originalRgb = nullptr;
        }
    }
    if (m_outVideoFrames.leftRgb) {
        av_frame_unref(m_outVideoFrames.leftRgb);
        if (isFreeAll) {
            av_frame_free(&m_outVideoFrames.leftRgb);
            m_outVideoFrames.leftRgb = nullptr;
        }
    }
    if (m_outVideoFrames.rightRgb) {
        av_frame_unref(m_outVideoFrames.rightRgb);
        if (isFreeAll) {
            av_frame_free(&m_outVideoFrames.rightRgb);
            m_outVideoFrames.rightRgb = nullptr;
        }
    }
    m_outVideoFrames.validFlags = 0;
}

void DecodeVideo::initAdtsHeader(char* const p_adts_header, const int data_length, const int profile, const int samplerate, const int channels)
{

    int sampling_frequency_index = 11;
    int adtsLen                  = data_length + 7;

    p_adts_header[0] = 0xff;
    p_adts_header[1] = 0xf0;
    p_adts_header[1] |= (0 << 3);
    p_adts_header[1] |= (0 << 1);
    p_adts_header[1] |= 1;

    p_adts_header[2] = (profile) << 6;
    p_adts_header[2] |= (sampling_frequency_index & 0x0f) << 2;
    p_adts_header[2] |= (0 << 1);
    p_adts_header[2] |= (channels & 0x04) >> 2;

    p_adts_header[3] = (channels & 0x03) << 6;
    p_adts_header[3] |= (0 << 5);
    p_adts_header[3] |= (0 << 4);
    p_adts_header[3] |= (0 << 3);
    p_adts_header[3] |= (0 << 2);
    p_adts_header[3] |= ((adtsLen & 0x1800) >> 11);

    p_adts_header[4] = (uint8_t)((adtsLen & 0x7f8) >> 3);
    p_adts_header[5] = (uint8_t)((adtsLen & 0x7) << 5);
    p_adts_header[5] |= 0x1f;
    p_adts_header[6] = 0xfc;
}

bool DecodeVideo::initMp4Codec(const bool& isH265, const QString& mp4FilePath, const int& frameWidth, const int& frameHeight, const int& iSampleRate)
{
    // 修正采样率
    int actualSampleRate = iSampleRate;
    if (actualSampleRate != 8000 && actualSampleRate != 16000 && actualSampleRate != 48000) {
        // qWarning() << "Invalid sample rate:" << actualSampleRate << ", using default 8000";
        actualSampleRate = 8000;
    }
    if (m_isMp4ParamInit)
        return false;
    if (mp4FilePath.isEmpty())
        return false;
    if (frameWidth <= 0 || frameHeight <= 0)
        return false;
    bool isInitOk(false);
    m_mp4FilePath = mp4FilePath;
    bool isFileOPen(false);
    // 获取CPU核心线程数（至少为1）
    //  int cores = QThread::idealThreadCount();
    //  cores = cores > 0 ? cores : 1;
    do {
        m_outPutPacket = av_packet_alloc();
        if (!m_outPutPacket)
            break;
        m_aacFrame = av_frame_alloc();
        if (!m_aacFrame)
            break;
        m_mp4encodeCodec = (AVCodec*)avcodec_find_encoder(m_mp4codeId);
        if (!m_mp4encodeCodec) {
            break;
        }
        m_mp4encodeContext = avcodec_alloc_context3(m_mp4encodeCodec);
        if (!m_mp4encodeContext) {
            break;
        }
        auto aacCodec = avcodec_find_encoder(m_mp4AudioCodeId);
        if (!aacCodec)
            break;
        m_mp4AudioEncodeContext = avcodec_alloc_context3(aacCodec);
        if (!m_mp4AudioEncodeContext) {

            break;
        }
        m_mp4AudioEncodeContext->codec_id       = m_mp4AudioCodeId;
        m_mp4AudioEncodeContext->codec_type     = AVMEDIA_TYPE_AUDIO;
        m_mp4AudioEncodeContext->sample_fmt     = AV_SAMPLE_FMT_FLTP;
        m_mp4AudioEncodeContext->channel_layout = AV_CH_LAYOUT_STEREO;
        m_mp4AudioEncodeContext->channels       = av_get_channel_layout_nb_channels(m_mp4AudioEncodeContext->channel_layout);
        m_mp4AudioEncodeContext->sample_rate    = actualSampleRate;
        m_mp4AudioEncodeContext->bit_rate       = 128000;
        m_mp4AudioEncodeContext->frame_size     = 1024;
        m_mp4AudioEncodeContext->profile        = FF_PROFILE_AAC_LOW; // FF_PROFILE_AAC_SSR 兼容性很差（很多播放器 / 浏览器不支持），改为 FF_PROFILE_AAC_LOW
        av_opt_set_int(m_mp4AudioEncodeContext->priv_data, "profile", FF_PROFILE_AAC_LOW, 0);
        av_opt_set_int(m_mp4AudioEncodeContext, "flags", AV_CODEC_FLAG_GLOBAL_HEADER, 0);
        int ret = avcodec_open2(m_mp4AudioEncodeContext, aacCodec, NULL);
        if (ret < 0) {
            break;
        }
        m_mp4encodeContext->bit_rate     = 5000000;
        m_mp4encodeContext->pix_fmt      = AV_PIX_FMT_YUV420P;
        m_mp4encodeContext->height       = /*frameHeight > 1080 ? 1080 :*/ frameHeight;
        m_mp4encodeContext->width        = /*frameWidth > 1920 ? 1920 :*/ frameWidth;
        m_mp4encodeContext->gop_size     = 30;
        m_mp4encodeContext->max_b_frames = 0; // 最大B帧数
        m_mp4encodeContext->has_b_frames = 0;
        // 使用固定 time_base = {1, 1000}，1 tick = 1 毫秒
        // 这样不管帧率如何变化（15fps/1fps），PTS 都直接等于相对毫秒数，不需要随帧率切换
        m_mp4encodeContext->time_base   = {1, 1000};
        m_mp4encodeContext->framerate   = {m_targetFps, 1};
        m_mp4encodeContext->codec_type  = AVMEDIA_TYPE_VIDEO;
        m_mp4encodeContext->thread_type = FF_THREAD_FRAME; // FF_THREAD_FRAME：帧间并行（需要 ≥2 帧延迟，可接受）
        // m_mp4encodeContext->thread_count = qMax(cores / 2, 1);        // 并行编码线程数手动指定
        m_mp4encodeContext->thread_count = 2; // 将线程数设置为2 即可，避免某些环境下线程数过多导致的性能问题
        // profile/preset/tune 属于私有选项，放在 priv_data
        av_opt_set(m_mp4encodeContext->priv_data, "profile", "main", 0);     // 限制编码器只使用 H.264 Main Profile 的工具集，提升与旧设备/浏览器的兼容性。
        av_opt_set(m_mp4encodeContext->priv_data, "preset", "ultrafast", 0); // 以牺牲压缩率为代价，换取最快的编码速度；关闭大量算法优化（如 lookahead、b-adapt）
        av_opt_set(m_mp4encodeContext->priv_data, "tune", "zerolatency", 0); // 禁用 B 帧,实时编码优化延迟,关闭 threaded-lookahead、vbv-buffer、rc-lookahead 等会引入帧级缓存的功能
        ret = avcodec_open2(m_mp4encodeContext, m_mp4encodeCodec, NULL);
        if (ret < 0) {
            break;
        }
        m_mp4outputFormatContext = avformat_alloc_context();
        if (!m_mp4outputFormatContext)
            break;
        m_mp4outputFormat = (AVOutputFormat*)av_guess_format(NULL, m_mp4FilePath.toStdString().data(), NULL);
        if (!m_mp4outputFormat) {
            break;
        }
        m_mp4outputFormatContext->oformat = m_mp4outputFormat;

        m_mp4outputVideoStream = avformat_new_stream(m_mp4outputFormatContext, NULL);
        if (!m_mp4outputVideoStream) {
            break;
        }
        auto codecParameters = m_mp4outputVideoStream->codecpar;
        // 使用通用帧率标记，因为SD卡下载的MP4可能包含多种帧率的片段
        m_mp4outputVideoStream->r_frame_rate   = {15, 1};
        m_mp4outputVideoStream->avg_frame_rate = {15, 1};
        codecParameters->codec_id              = m_mp4codeId;
        codecParameters->codec_type            = AVMEDIA_TYPE_VIDEO;
        codecParameters->width                 = m_mp4encodeContext->width;
        codecParameters->height                = m_mp4encodeContext->height;
        codecParameters->format                = AV_PIX_FMT_YUV420P;

        m_mp4OutputAudioStream = avformat_new_stream(m_mp4outputFormatContext, NULL);
        if (!m_mp4OutputAudioStream) {
            break;
        }
        auto codecAudioParameters = m_mp4OutputAudioStream->codecpar;

        codecAudioParameters->frame_size     = 1024;
        codecAudioParameters->codec_id       = m_mp4AudioCodeId;
        codecAudioParameters->codec_type     = AVMEDIA_TYPE_AUDIO;
        codecAudioParameters->format         = AV_SAMPLE_FMT_FLTP;
        codecAudioParameters->channel_layout = AV_CH_LAYOUT_STEREO;
        codecAudioParameters->channels       = av_get_channel_layout_nb_channels(m_mp4AudioEncodeContext->channel_layout);
        codecAudioParameters->sample_rate    = actualSampleRate;
        codecAudioParameters->bit_rate       = m_mp4AudioEncodeContext->bit_rate;

        m_aacFrame->channels   = m_mp4AudioEncodeContext->channels;
        m_aacFrame->format     = m_mp4AudioEncodeContext->sample_fmt;
        m_aacFrame->nb_samples = m_mp4AudioEncodeContext->frame_size;

        m_aacOneFrameSize = av_samples_get_buffer_size(NULL, m_mp4AudioEncodeContext->channels, m_mp4AudioEncodeContext->frame_size, m_mp4AudioEncodeContext->sample_fmt, 1);
        if (m_aacOneFrameSize < 0) {
            // QADebug() << "Failed to allocate memory for m_aacOneFrameSize.";
            break; // 返回内存不足错误
        }
        m_aacOneFrameBuf = (uint8_t*)av_malloc(m_aacOneFrameSize);
        if (!m_aacOneFrameBuf) {
            // QADebug() << "Failed to allocate memory for m_aacOneFrameBuf.";
            break; // 返回内存不足错误
        }
        avcodec_fill_audio_frame(m_aacFrame, m_mp4AudioEncodeContext->channels, m_mp4AudioEncodeContext->sample_fmt, (const uint8_t*)m_aacOneFrameBuf, m_aacOneFrameSize, 1);

        m_twoChannelData = (uint8_t**)av_calloc(m_mp4AudioEncodeContext->channels, sizeof(*m_twoChannelData));
        if (!m_twoChannelData) {
            // QADebug() << "Failed to allocate memory for m_twoChannelData.";
            break; // 返回内存不足错误
        }
        ret = av_samples_alloc(m_twoChannelData, NULL, m_mp4AudioEncodeContext->channels, m_mp4AudioEncodeContext->frame_size, m_mp4AudioEncodeContext->sample_fmt, 1);
        if (ret < 0) {
            char buf[AV_ERROR_MAX_STRING_SIZE] = {0};
            av_strerror(ret, buf, sizeof(buf));
            // QADebug() << "Failed to allocate audio samples: " << buf;

            // 释放之前分配的内存
            av_freep(&m_twoChannelData);
            break; // ret 返回错误码
        }

        m_audioSwrCtx = swr_alloc_set_opts(NULL, m_mp4AudioEncodeContext->channel_layout, m_mp4AudioEncodeContext->sample_fmt, m_mp4AudioEncodeContext->sample_rate, AV_CH_LAYOUT_MONO,
                                           AV_SAMPLE_FMT_S16, actualSampleRate, 0, NULL);
        if (!m_audioSwrCtx) {
            // QADebug() << "Failed to allocate SwrContext.";// 返回内存不足错误
            break;
        }
        if (swr_init(m_audioSwrCtx) < 0) {
            fprintf(stderr, "Could not open resample context\n");
            // 释放重采样器
            swr_free(&m_audioSwrCtx);
            break;
        }

        if (avio_open(&m_mp4outputFormatContext->pb, m_mp4FilePath.toStdString().data(), AVIO_FLAG_WRITE) < 0) {
            break;
        }

        if (avformat_write_header(m_mp4outputFormatContext, NULL) < 0) {
            isFileOPen = true;
            break;
        }
        m_aacOutPacket = av_packet_alloc();
        if (!m_aacOutPacket)
            break;
        m_aacAdtsOutPacket = av_packet_alloc();
        if (!m_aacAdtsOutPacket)
            break;

        isInitOk = true;
        m_pcmCacheData.clear();
        m_audioPts = 0;
    } while (0);
    if (!isInitOk) {
        if (isFileOPen && m_mp4outputFormatContext)
            av_write_trailer(m_mp4outputFormatContext);
        if (m_mp4outputVideoStream && m_mp4outputVideoStream->codecpar)
            avcodec_parameters_free(&(m_mp4outputVideoStream->codecpar));
        if (m_mp4OutputAudioStream && m_mp4OutputAudioStream->codecpar)
            avcodec_parameters_free(&(m_mp4OutputAudioStream->codecpar));
        if (m_mp4encodeContext) {
            avcodec_close(m_mp4encodeContext);
            avcodec_free_context(&m_mp4encodeContext);
        }
        if (m_mp4outputFormatContext)
            avio_close(m_mp4outputFormatContext->pb);
        if (m_mp4outputFormatContext)
            avformat_free_context(m_mp4outputFormatContext);
        if (m_mp4AudioEncodeContext) {
            avcodec_close(m_mp4AudioEncodeContext);
            avcodec_free_context(&m_mp4AudioEncodeContext);
        }
        if (m_audioSwrCtx)
            swr_free(&m_audioSwrCtx);
        if (m_outPutPacket)
            av_packet_free(&m_outPutPacket);
        if (m_aacFrame) {
            av_frame_free(&m_aacFrame);
        }
        if (m_aacAdtsOutPacket) {
            av_packet_free(&m_aacAdtsOutPacket);
        }
        if (m_aacOneFrameBuf)
            av_free(m_aacOneFrameBuf);
        if (m_twoChannelData)
            av_freep(&m_twoChannelData[0]);
        m_twoChannelData = nullptr;
        m_aacOneFrameBuf = nullptr;
        m_pcmCacheData.clear();
        m_mp4outputFormatContext = nullptr;
        m_mp4outputVideoStream   = nullptr;
        m_mp4encodeContext       = nullptr;
        m_outPutPacket           = nullptr;
        m_mp4encodeCodec         = nullptr;
        m_mp4FilePath.clear();
        m_isMp4ParamInit    = false;
        m_audioSwrCtx       = nullptr;
        m_aacFrame          = nullptr;
        m_aacAdtsOutPacket  = nullptr;
        m_mp4FrameCount     = 0;
        m_lastVideoPts      = 0;
        m_videoPts          = 0;
        m_audioPts          = 0;
        m_isTimerStarted    = false;
        m_startTimeMs       = 0;
        m_audioTotalSamples = 0;
        m_audioFrameCount   = 0;
        return false;
    }
    m_mp4FrameCount  = 0;
    m_isTimerStarted = false;
    m_startTimeMs    = 0;

    m_isMp4ParamInit    = true;
    m_audioTotalSamples = 0;
    m_audioFrameCount   = 0;
    return true;
}

void DecodeVideo::unInitMp4Codec()
{
    if (!m_isMp4ParamInit)
        return;
    if (m_mp4outputFormatContext) {
        av_interleaved_write_frame(m_mp4outputFormatContext, NULL);
        av_write_trailer(m_mp4outputFormatContext);
        avio_close(m_mp4outputFormatContext->pb);
    }
    if (m_mp4outputVideoStream && m_mp4outputVideoStream->codecpar)
        avcodec_parameters_free(&(m_mp4outputVideoStream->codecpar));
    if (m_mp4OutputAudioStream && m_mp4OutputAudioStream->codecpar)
        avcodec_parameters_free(&(m_mp4OutputAudioStream->codecpar));
    if (m_mp4encodeContext) {
        avcodec_close(m_mp4encodeContext);
        avcodec_free_context(&m_mp4encodeContext);
    }
    if (m_mp4AudioEncodeContext) {
        avcodec_close(m_mp4AudioEncodeContext);
        avcodec_free_context(&m_mp4AudioEncodeContext);
    }
    if (m_mp4outputFormatContext)
        avformat_free_context(m_mp4outputFormatContext);

    if (m_outPutPacket) {
        av_packet_unref(m_outPutPacket);
        av_packet_free(&m_outPutPacket);
        m_outPutPacket = nullptr;
    }

    if (m_aacOutPacket) {
        av_packet_unref(m_aacOutPacket);
        av_packet_free(&m_aacOutPacket);
        m_aacOutPacket = nullptr;
    }

    if (m_audioSwrCtx)
        swr_free(&m_audioSwrCtx);
    if (m_aacFrame) {
        av_frame_free(&m_aacFrame);
    }
    if (m_aacAdtsOutPacket) {
        av_packet_free(&m_aacAdtsOutPacket);
    }
    if (m_aacOneFrameBuf)
        av_free(m_aacOneFrameBuf);
    if (m_twoChannelData)
        av_freep(&m_twoChannelData[0]);

    m_twoChannelData         = nullptr;
    m_aacOneFrameBuf         = nullptr;
    m_mp4outputFormatContext = nullptr;
    m_mp4outputVideoStream   = nullptr;
    m_mp4encodeContext       = nullptr;
    m_outPutPacket           = nullptr;
    m_mp4encodeCodec         = nullptr;
    m_audioSwrCtx            = nullptr;
    m_aacFrame               = nullptr;
    m_aacAdtsOutPacket       = nullptr;

    m_mp4FilePath.clear();
    m_isMp4ParamInit = false;
    m_mp4FrameCount  = 0;
    m_isMp4ParamInit = false;
    m_firstInputTsMs = -1; // 重置首帧锚点，避免上一个文件的起点影响新文件 PTS
    m_videoPtsAcc    = 0;
    m_lastVideoPts   = 0;
    m_videoPts       = 0;
    m_audioPts       = 0;

    m_isTimerStarted    = false;
    m_startTimeMs       = 0;
    m_isAOVDevice       = false;
    m_isRecord          = false;
    m_audioTotalSamples = 0;
    m_audioFrameCount   = 0;
}

bool DecodeVideo::saveDataToMp4(AVFrame* videoFrame, const AVMediaType& mediaType, const bool& isFlushEndAudio)
{
    if (!m_isMp4ParamInit)
        return false;
    if (!videoFrame)
        return false;
    bool isWrite(false);

    if (mediaType == AVMEDIA_TYPE_VIDEO) {
        // 用"真实时间累计的 pts"，兼容帧率动态切换
        // 这里 curPts 约定传 ms；如果外部没传，就用 m_iTimeStamp
        const int64_t pts = getPlaybackVideoPts(videoFrame->pts);

        m_videoPts      = (int)pts;
        m_mp4FrameCount = (uint64_t)m_videoPts; // 仅用于你其他逻辑（计数/显示），不再作为 pts 来源

        videoFrame->pts     = m_videoPts;
        videoFrame->pkt_dts = m_videoPts;

        int ret = avcodec_send_frame(m_mp4encodeContext, videoFrame);
        if (ret < 0) {
            av_frame_unref(videoFrame);
            return false;
        }

        while (true) {
            ret = avcodec_receive_packet(m_mp4encodeContext, m_outPutPacket);
            if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF)
                break;
            if (ret < 0)
                break;

            av_packet_rescale_ts(m_outPutPacket, m_mp4encodeContext->time_base, m_mp4outputVideoStream->time_base);
            m_outPutPacket->stream_index = m_mp4outputVideoStream->index;
            av_interleaved_write_frame(m_mp4outputFormatContext, m_outPutPacket);
            av_packet_unref(m_outPutPacket);
            isWrite = true;
        }

        av_frame_unref(videoFrame);

        return isWrite;
    }
    if (mediaType == AVMEDIA_TYPE_AUDIO) {
        int size;
        int inputSample = videoFrame->nb_samples;
        if (inputSample <= 0)
            return false;
        int inputPcmSize = inputSample * 2;
        if (!isFlushEndAudio) {
            int pcmDataLen = videoFrame->linesize[0];
            if (pcmDataLen != inputPcmSize)
                return false;
            QByteArray pcmData((const char*)videoFrame->data[0], pcmDataLen);
            if (pcmData.isEmpty())
                return false;
            m_pcmCacheData.append(pcmData);
            size = m_aacFrame->nb_samples * 2;
            if (m_pcmCacheData.size() < size)
                return false;
            memset(m_aacOneFrameBuf, 0, m_aacOneFrameSize);
            memcpy(m_aacOneFrameBuf, m_pcmCacheData, size);
            m_pcmCacheData = m_pcmCacheData.mid(size);
        } else {
            memset(m_aacOneFrameBuf, 0, m_aacOneFrameSize); // 先清空，默认填充静音
            if (!m_pcmCacheData.isEmpty()) {
                size         = m_aacFrame->nb_samples * 2;
                int copySize = qMin(size, m_pcmCacheData.size());
                memcpy(m_aacOneFrameBuf, m_pcmCacheData, copySize);
                m_pcmCacheData.clear();
            } else {
                return false;
            }
        }
        const uint8_t* inData[1]        = {(const uint8_t*)m_aacOneFrameBuf};
        int            convertedSamples = swr_convert(m_audioSwrCtx, m_twoChannelData, m_mp4AudioEncodeContext->frame_size, inData, m_aacFrame->nb_samples);
        if (convertedSamples != m_aacFrame->nb_samples) { // 必须转换出1024采样
            return false;
        }
        int bytesPerSample = av_get_bytes_per_sample(m_mp4AudioEncodeContext->sample_fmt);
        size               = convertedSamples * bytesPerSample;
        if (size <= 0 || !m_twoChannelData[0] || !m_twoChannelData[1])
            return false;
        memcpy(m_aacFrame->data[0], m_twoChannelData[0], size);
        memcpy(m_aacFrame->data[1], m_twoChannelData[1], size);
        if (m_audioPts == AV_NOPTS_VALUE || m_audioPts < 0) {
            m_audioPts = 0;
        }
        AVRational sampleRateTimeBase = {1, m_mp4AudioEncodeContext->sample_rate};
        m_aacFrame->pts               = av_rescale_q(m_audioPts, sampleRateTimeBase, m_mp4OutputAudioStream->time_base);
        // 每次累加1024采样，与编码器帧大小严格对应
        m_audioPts += m_aacFrame->nb_samples;
        m_audioTotalSamples += m_aacFrame->nb_samples; // 累计音频采样数
        m_audioFrameCount++;                           // 音频帧计数+1

        int iRret = avcodec_send_frame(m_mp4AudioEncodeContext, m_aacFrame);
        if (iRret < 0) {
            return false;
        }

        while (avcodec_receive_packet(m_mp4AudioEncodeContext, m_aacOutPacket) >= 0) {
            av_packet_rescale_ts(m_aacOutPacket, m_mp4AudioEncodeContext->time_base, m_mp4OutputAudioStream->time_base);
            m_aacOutPacket->stream_index = m_mp4OutputAudioStream->index;
            av_interleaved_write_frame(m_mp4outputFormatContext, m_aacOutPacket);
            av_packet_unref(m_aacOutPacket);
            isWrite = true;
        }

        av_packet_unref(m_aacOutPacket);

        return isWrite;
    }

    return true;
}

bool DecodeVideo::reInitMp4Codec(const bool& isH265, const int& newWidth, const int& newHeight, const int& iSampleRate)
{
    // ====== 1. 参数校验 ======
    if (newWidth <= 0 || newHeight <= 0) {
        qWarning() << "LOG::reInitMp4Codec: invalid resolution" << newWidth << "x" << newHeight;
        return false;
    }

    // ====== 2. 首次初始化：委托给 initMp4Codec ======
    if (!m_isMp4ParamInit) {
        if (m_mp4FilePath.isEmpty()) {
            qWarning() << "LOG::reInitMp4Codec: first init but no file path stored";
            return false;
        }
        qDebug() << "LOG::reInitMp4Codec: first init, delegating to initMp4Codec"
                 << ", file=" << m_mp4FilePath << ", res=" << newWidth << "x" << newHeight;
        return initMp4Codec(isH265, m_mp4FilePath, newWidth, newHeight, iSampleRate);
    }

    // ====== 3. 已初始化：分辨率切换时只重建视频编码器 ======
    qDebug() << "LOG::reInitMp4Codec: resolution change detected"
             << ", old=" << (m_mp4encodeContext ? m_mp4encodeContext->width : -1) << "x" << (m_mp4encodeContext ? m_mp4encodeContext->height : -1) << ", new=" << newWidth << "x" << newHeight;

    // --- 3a. Flush 旧视频编码器的残留帧 ---
    if (m_mp4encodeContext) {
        // 发送 NULL 帧通知编码器刷新输出所有缓存帧
        int ret = avcodec_send_frame(m_mp4encodeContext, nullptr);
        if (ret == 0) {
            // 接收并写入所有残留 packet
            AVPacket* flushPkt = av_packet_alloc();
            if (flushPkt) {
                while (avcodec_receive_packet(m_mp4encodeContext, flushPkt) == 0) {
                    av_packet_rescale_ts(flushPkt, m_mp4encodeContext->time_base, m_mp4outputVideoStream->time_base);
                    flushPkt->stream_index = m_mp4outputVideoStream->index;
                    av_interleaved_write_frame(m_mp4outputFormatContext, flushPkt);
                    av_packet_unref(flushPkt);
                }
                av_packet_free(&flushPkt);
            }
        }
    }

    // --- 3b. 记录当前 PTS 状态（用于后续恢复继承） ---
    const int64_t savedVideoPtsAcc  = m_videoPtsAcc;
    const int     savedLastVideoPts = m_lastVideoPts;

    // --- 3c. 销毁旧的视频编码器 ---
    if (m_mp4encodeContext) {
        avcodec_close(m_mp4encodeContext);
        avcodec_free_context(&m_mp4encodeContext);
        m_mp4encodeContext = nullptr;
    }
    // 注意：不销毁 m_mp4encodeCodec（编码器指针复用）、不动文件和音频编码器

    // --- 3d. 用新分辨率创建新的视频编码器 ---
    m_mp4encodeContext = avcodec_alloc_context3(m_mp4encodeCodec);
    if (!m_mp4encodeContext) {
        qWarning() << "LOG::reInitMp4Codec: failed to allocate new encode context";
        return false;
    }

    // 配置新编码器参数（与 initMp4Codec 保持一致）
    m_mp4encodeContext->bit_rate     = 5000000;
    m_mp4encodeContext->pix_fmt      = AV_PIX_FMT_YUV420P;
    m_mp4encodeContext->height       = newHeight;
    m_mp4encodeContext->width        = newWidth;
    m_mp4encodeContext->gop_size     = 30;
    m_mp4encodeContext->max_b_frames = 0;
    m_mp4encodeContext->has_b_frames = 0;
    // 使用固定 time_base = {1, 1000}，与 initMp4Codec 保持一致
    m_mp4encodeContext->time_base    = {1, 1000};
    m_mp4encodeContext->framerate    = {m_targetFps, 1};
    m_mp4encodeContext->codec_type   = AVMEDIA_TYPE_VIDEO;
    m_mp4encodeContext->thread_type  = FF_THREAD_FRAME;
    m_mp4encodeContext->thread_count = 2;

    // profile/preset/tune 私有选项
    av_opt_set(m_mp4encodeContext->priv_data, "profile", "main", 0);
    av_opt_set(m_mp4encodeContext->priv_data, "preset", "ultrafast", 0);
    av_opt_set(m_mp4encodeContext->priv_data, "tune", "zerolatency", 0);

    int ret = avcodec_open2(m_mp4encodeContext, m_mp4encodeCodec, nullptr);
    if (ret < 0) {
        char buf[AV_ERROR_MAX_STRING_SIZE] = {0};
        av_strerror(ret, buf, sizeof(buf));
        qWarning() << "LOG::reInitMp4Codec: failed to open new encoder:" << buf;
        avcodec_free_context(&m_mp4encodeContext);
        m_mp4encodeContext = nullptr;
        return false;
    }

    // --- 3e. 更新视频流的 codecpar（让容器知道分辨率变了） ---
    if (m_mp4outputVideoStream && m_mp4outputVideoStream->codecpar) {
        auto codecParameters    = m_mp4outputVideoStream->codecpar;
        codecParameters->width  = newWidth;
        codecParameters->height = newHeight;
    }

    // --- 3f. 恢复 PTS 状态（保证时间戳连续） ---
    m_videoPtsAcc    = savedVideoPtsAcc;
    m_lastVideoPts   = savedLastVideoPts;
    m_lastInputTsMs  = -1; // 重置 delta 计算，避免旧间隔影响新节奏
    m_firstInputTsMs = -1; // 重置首帧锚点，避免旧文件的起点影响新节奏 PTS

    // qDebug() << "LOG::reInitMp4Codec: success"
    //     << ", new encoder res=" << newWidth << "x" << newHeight
    //     << ", pts restored at" << m_videoPtsAcc;

    return true;
}

qint64 DecodeVideo::timeStamp()
{
    return m_iTimeStamp;
}

void DecodeVideo::setTimeStamp(const qint64& timestamp)
{
    m_iTimeStamp = timestamp;
}

void DecodeVideo::setInputVideoFps(double fps)
{
    if (fps <= 0.0)
        return;

    m_videoFps = fps;

    // 让 time_base = 1/fps（用四舍五入到合理分母；只覆盖常见 1/15 这种）
    // 若你还有 12.5/29.97 等需求，建议换成固定 1/90000 并用 ms->tick 的方式。
    if (m_videoFps < 1.0) {
        // 对于低帧率，如0.2fps，time_base = {1, 5}（因为1/5 = 0.2）
        int den           = (int)qRound(1.0 / m_videoFps);
        m_video_time_base = {1, den};
    } else {
        const int den     = qMax(1, (int)qRound(m_videoFps));
        m_video_time_base = {1, den};
    }

    // 帧率切换时不重置 m_videoPtsAcc，保证 pts 连续单调
    // 但需要避免旧的 delta 影响新节奏
    m_lastInputTsMs = -1;
}

void DecodeVideo::setInputFrameIntervalMs(qint64 intervalMs)
{
    if (intervalMs <= 0)
        return;
    const double fps = 1000.0 / (double)intervalMs;
    setInputVideoFps(fps);
}

void DecodeVideo::setTargetFps(int fps)
{
    if (fps > 0) {
        m_targetFps = fps;
    }
}

int DecodeVideo::targetFps() const
{
    return m_targetFps;
}

int64_t DecodeVideo::getPlaybackVideoPts(const int64_t& curPts)
{
    // 录屏操作 使用自定义计时器：保持你原逻辑，但产出 pts 仍按当前 m_video_time_base
    if (m_isRecord) {
        if (!m_isTimerStarted) {
            m_startTimeMs    = QDateTime::currentMSecsSinceEpoch();
            m_isTimerStarted = true;
        }

        const qint64 nowMs     = QDateTime::currentMSecsSinceEpoch();
        const qint64 elapsedMs = nowMs - m_startTimeMs;

        // ms -> tick（time_base = {1, 1000}，所以 1 tick = 1 ms）
        const int64_t pts = elapsedMs;
        if (pts > m_videoPtsAcc)
            m_videoPtsAcc = pts;

        // 强制单调递增（即使 elapsedMs 相同）
        if (m_videoPtsAcc <= m_lastVideoPts)
            m_videoPtsAcc = m_lastVideoPts + 1;
        m_lastVideoPts = (int)m_videoPtsAcc;
        return m_videoPtsAcc;
    }

    // SD卡下载/回放模式：curPts 是相对时间戳（毫秒），编码器 time_base = {1, 1000}
    // PTS 直接等于相对毫秒数，帧率切换不影响PTS计算
    // 注意：curPts == 0 是合法的"首帧"相对时间起点，必须当作有效时间戳，
    // 不能因 curPts>0 判断被误判为"无效"（否则首帧锚点错乱、退化成 +1 递增）
    qint64 inputTsMs = -1;
    if (curPts >= 0)
        inputTsMs = (qint64)curPts;
    else if (m_iTimeStamp >= 0)
        inputTsMs = (qint64)m_iTimeStamp;
    else
        inputTsMs = -1;

    if (inputTsMs >= 0 && m_firstInputTsMs < 0) {
        m_firstInputTsMs = inputTsMs;
    }

    if (inputTsMs >= 0 && m_firstInputTsMs >= 0) {
        // elapsedMs = 相对首帧经过的毫秒数，直接作为 PTS（因为 time_base = {1, 1000}）
        const qint64 elapsedMs = inputTsMs - m_firstInputTsMs;
        m_videoPtsAcc          = qMax<int64_t>(0, elapsedMs);
        m_lastInputTsMs        = inputTsMs;
    } else {
        // 没有有效时间戳时，简单递增
        m_videoPtsAcc += 1;
    }

    // 强制单调递增
    if (m_videoPtsAcc <= m_lastVideoPts)
        m_videoPtsAcc = m_lastVideoPts + 1;
    m_lastVideoPts = (int)m_videoPtsAcc;
    return m_videoPtsAcc;
}

void DecodeVideo::setIsRecord(bool isRecord)
{
    m_isRecord = isRecord;
}

void DecodeVideo::setDeviceType(bool isAOV)
{
    m_isAOVDevice = isAOV;
}

void DecodeVideo::setSDCardDownloadType(bool isAOV)
{
    m_isSDCardDownloadAOV = isAOV;
}