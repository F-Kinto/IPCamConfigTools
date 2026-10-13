/*********************************************************************
File : DecodeVideo.h
Module : tools
Authors: guangnan
date : 2023/08/08 16:00
Ver : 1.0.1
History:
guangnan 2023/08/08 1.0.0 build this module
guangnan 2023/09/20 1.0.1 add save mp4 function
********************************************************************/
#ifndef DECODEVIDEO_H
#define DECODEVIDEO_H

#include <QObject>
extern "C" {
#define __STDC_CONSTANT_MACROS
#include "libavcodec/avcodec.h"
#include "libswscale/swscale.h"
#include "libavutil/imgutils.h"
#include "libavutil/opt.h"
#include "libavformat/avformat.h"
#include "libswresample/swresample.h"
#include "libavutil/error.h"
}
#include <QMutex>
#include <QStringList>
#include <QPainter>
#include "videohardwareaccel.h"

enum FrameRequest : int {
    ORIGINAL_YUV = 1 << 0,
    LEFT_YUV     = 1 << 1,
    RIGHT_YUV    = 1 << 2,
    ORIGINAL_RGB = 1 << 3,
    LEFT_RGB     = 1 << 4,
    RIGHT_RGB    = 1 << 5,
};

struct DecodedFrames
{
    int      validFlags  = 0; // 哪些成员是有效的（按 FrameRequest 里的位）
    AVFrame* originalYuv = nullptr;
    AVFrame* leftYuv     = nullptr;
    AVFrame* rightYuv    = nullptr;
    AVFrame* originalRgb = nullptr;
    AVFrame* leftRgb     = nullptr;
    AVFrame* rightRgb    = nullptr;

    bool has(FrameRequest f) const
    {
        return (validFlags & f) != 0;
    } /* 单个 */

    bool hasAll(int mask) const
    {
        return (validFlags & mask) == mask;
    } /* 全都有 */

    bool hasAny(int mask) const
    {
        return (validFlags & mask) != 0;
    } /* 有任意一个 */

    void setValid(FrameRequest f)
    {
        validFlags |= f;
    }
};

class DecodeVideo : public QObject {
    Q_OBJECT
  public:
    explicit DecodeVideo(QObject* parent = nullptr);
    ~DecodeVideo();
    bool          initVideoCodec(const bool& isH265, const int& threadCount);
    bool          initG711AudioCodec(const AVSampleFormat& sampltFmt, const int& channels, const int& sampltRate);
    bool          initAACAudioCodec(const AVSampleFormat& sampltFmt, const int& channels, const int& sampltRate);
    void          unInitAACAudioCodec();
    void          unInitVideoCodec();
    void          unInitG711AudioCodec();
    void          unInitMp4Codec();
    bool          initMp4Codec(const bool& isH265, const QString& mp4FilePath, const int& frameWidth, const int& frameHeight, const int& iSampleRate = 8000);
    DecodedFrames decodeVideo(unsigned char* data, const int& dataLen, int frameFlags);
    void          freeDecodedFrames(const bool& isFreeAll = false);
    void          clearTimestampCache();
    void          addTimestampToYuvFrame(AVFrame* frame, const QDateTime& timestamp);
    AVFrame*      decodeG711Audio(unsigned char* data, const int& dataLen);
    AVFrame*      decodeAAcAudio(unsigned char* data, const int& dataLen);
    bool          initOpusAudioCodec(const AVSampleFormat& sampltFmt, const int& channels, const int& sampltRate);
    AVFrame*      decodeOpusAudio(unsigned char* data, const int& dataLen);
    void          unInitOpusAudioCodec();
    bool          saveDataToMp4(AVFrame* videoFrame, const AVMediaType& mediaType, const bool& isFlushEndAudio = false);
    // 检测到分辨率变化时：重新初始化视频编码器
    bool              reInitMp4Codec(const bool& isH265, const int& newWidth, const int& newHeight, const int& iSampleRate);
    qint64            timeStamp();
    void              setTimeStamp(const qint64& timestamp);
    static QByteArray encodeG711Audio(unsigned char* frameData, const int& frameDataLen);
    void              pause();
    int64_t           getPlaybackVideoPts(const int64_t& curPts = 0);
    void              setDeviceType(bool isAOV);
    void              setSDCardDownloadType(bool isAOV); // 设置当前下载帧片段是否未AOV片段
    void              setIsRecord(bool isRecord);        // 是否本地录屏

    bool isAbnormalFrame(AVFrame* frame);

    inline const bool&     isVideoInit() const;
    inline const int&      isAudioInit() const;
    inline const bool&     isMp4ParamInit() const;
    inline const int&      videoWidth() const;
    inline const int&      videoHeight() const;
    inline int             mp4EncodeWidth() const;  // <-- 新增：返回MP4视频编码器当前工作宽度
    inline int             mp4EncodeHeight() const; // <-- 新增：返回MP4视频编码器当前工作高度
    inline AVCodecContext* videoCodecCtx() const;

    static void          initAdtsHeader(char* const p_adts_header, const int data_length, const int profile, const int samplerate, const int channels);
    inline const bool&   isSupportHw() const;
    inline const qint64& timeStamp() const;

    void    setInputVideoFps(double fps);               // 动态切换输入帧率（如 15 -> 1）
    void    setInputFrameIntervalMs(qint64 intervalMs); // 若外部更易拿到帧间隔，用它更新 fps
    void    setTargetFps(int fps);                      // 设置目标播放帧率
    int     targetFps() const;                          // 查询目标帧率
    int64_t m_lowFpsFrameCount = 0;                     // 低帧率模式帧计数

  public:
    // QMutex m_rawVideoLock;
    // QMutex m_saveMp4VideoLock[0];
    bool m_needWaitKeyFrame = false; // 是否需要等待关键帧

  private:
    bool               m_isVideoInit;
    AVCodec*           m_videoCodec;
    AVCodecContext*    m_videoCodecCtx;
    struct SwsContext* m_videoSwsCtx;
    AVFrame*           m_videoFramCache;
    AVFrame*           m_videoRgbFramCache;
    AVFrame*           m_leftYuvFrame;
    AVFrame*           m_rightYuvFrame;
    // 裁剪路径跨帧复用缓冲区，避免每帧 alloc/free 导致 32 位地址空间碎片化
    AVFrame*           m_cropTmpLeft       = nullptr; // 裁剪临时帧（左），跨帧复用
    AVFrame*           m_cropTmpRight      = nullptr; // 裁剪临时帧（右），跨帧复用
    struct SwsContext* m_cropStretchCtx    = nullptr; // 裁剪拉伸上下文，跨帧复用
    int                m_cropCachedTargetW = 0;       // 上次裁剪目标宽度（用于判断是否需要重新分配）
    int                m_cropCachedTargetH = 0;       // 上次裁剪目标高度
    int                m_cropCachedCropW   = 0;       // 上次裁剪的裁剪区域宽度
    unsigned char*     m_rgbCache;
    unsigned char*     m_rgbLeftCache;
    unsigned char*     m_rgbRightCache;
    int                m_videoWidth;
    int                m_videoHeight;
    bool               m_isH265;

    int             m_leftYuvCachedW    = 0; // m_leftYuvFrame 上次分配的宽度（用于判断是否需要重新分配）
    int             m_leftYuvCachedH    = 0; // m_leftYuvFrame 上次分配的高度
    int             m_rightYuvCachedW   = 0; // m_rightYuvFrame 上次分配的宽度
    int             m_rightYuvCachedH   = 0; // m_rightYuvFrame 上次分配的高度
    int             m_isAudioDecodeInit = 0;
    AVCodec*        m_audioCodec;
    AVCodecContext* m_audioContext;
    AVFrame*        m_pcmData;

    AVFormatContext*                    m_mp4outputFormatContext;
    AVOutputFormat*                     m_mp4outputFormat;
    AVStream*                           m_mp4outputVideoStream;
    AVStream*                           m_mp4OutputAudioStream;
    QString                             m_mp4FilePath;
    AVCodecID                           m_mp4codeId;
    AVCodecID                           m_mp4AudioCodeId;
    AVCodecContext*                     m_mp4encodeContext;
    AVCodecContext*                     m_mp4AudioEncodeContext;
    AVCodec*                            m_mp4encodeCodec;
    bool                                m_isMp4ParamInit;
    uint64_t                            m_mp4FrameCount;
    AVPacket*                           m_outPutPacket;
    struct SwrContext*                  m_audioSwrCtx;
    AVFrame*                            m_aacFrame;
    uint8_t*                            m_aacOneFrameBuf;
    uint8_t**                           m_twoChannelData;
    AVPacket*                           m_aacOutPacket;
    AVPacket*                           m_aacAdtsOutPacket;
    int                                 m_aacOneFrameSize;
    QByteArray                          m_pcmCacheData;
    int                                 m_lastVideoPts;
    int                                 m_videoPts;
    int                                 m_audioPts;
    qint64                              m_iTimeStamp;
    bool                                m_isSupportHw;
    bool                                m_hwStreamCounted = false; // 本实例是否已占用硬件解码并发名额（用于退出时释放计数）
    std::unique_ptr<VideoHardwareAccel> m_hwAccel;                 // 硬件加速封装对象（按系统支持类型初始化）
    AVBufferRef*                        m_hw_device_ctx;
    AVPixelFormat                       m_hw_pix_fmt;
    struct SwrContext*                  m_aacSwrCtx;
    uint8_t*                            m_aacPcmDataBuf;
    struct SwrContext*                  m_opusSwrCtx;
    uint8_t*                            m_opusPcmDataBuf;

    QImage  m_cachedTimestampImage;     // 缓存的时间戳图像
    qint64  m_lastTimestampSecond = -1; // 上一次绘制的时间戳（秒）
    QString m_lastTimeString;           // 上一次的时间字符串

    int64_t    m_cropOutputFrameIndex = 0;         // 递增索引用于唯一 pts
    double     m_videoFps             = 15.0;      // 当前输入帧率（可动态更新）
    qint64     m_lastInputTsMs        = -1;        // 上一帧输入时间戳(ms)，用于计算 delta
    int64_t    m_videoPtsAcc          = 0;         // 累计的视频 pts（以 m_video_time_base 为单位 tick）
    qint64     m_firstInputTsMs       = -1;        // 记录首帧时间戳
    AVRational m_video_time_base      = {1, 1000}; // 写文件用：内部视频时间基（固定1ms精度，支持帧率动态切换）
    AVStream*  m_videoStream          = nullptr;   // 用于取 time_base（不能是 {1,1}，建议 {1,fps} 或 {1,1000}）

    DecodedFrames m_outVideoFrames;

    // 初始化起始时间-本地计时器
    bool       m_isTimerStarted      = false;
    qint64     m_startTimeMs         = 0;     // 起始时间（毫秒）
    bool       m_isAOVDevice         = false; // 是否是AOV设备
    bool       m_isSDCardDownloadAOV = false; // 是否是SD卡下载的AOV片段
    bool       m_isRecord            = false; // 是否正在录制视频
    int64_t    m_audioTotalSamples   = 0;     // 音频累计采样数（用于同步视频PTS）
    int        m_audioFrameCount     = 0;     // 音频编码帧计数（每1024采样=1帧）
    AVRational m_av_time_base_q;              // 替代AV_TIME_BASE_Q的变量（声明）
    friend int fillVideo1Iobuffer(void* opaque, uint8_t* buf, int buf_size);
    int        m_targetFps = 15; // 目标播放帧率（默认15）
};

const bool& DecodeVideo::isVideoInit() const
{
    return m_isVideoInit;
}

const int& DecodeVideo::videoWidth() const
{
    return m_videoWidth;
}

const int& DecodeVideo::videoHeight() const
{
    return m_videoHeight;
}

int DecodeVideo::mp4EncodeWidth() const
{
    return (m_isMp4ParamInit && m_mp4encodeContext) ? m_mp4encodeContext->width : -1;
}

int DecodeVideo::mp4EncodeHeight() const
{
    return (m_isMp4ParamInit && m_mp4encodeContext) ? m_mp4encodeContext->height : -1;
}

const int& DecodeVideo::isAudioInit() const
{
    return m_isAudioDecodeInit;
}

const bool& DecodeVideo::isMp4ParamInit() const
{
    return m_isMp4ParamInit;
}

AVCodecContext* DecodeVideo::videoCodecCtx() const
{
    return m_videoCodecCtx;
}

const bool& DecodeVideo::isSupportHw() const
{
    return m_isSupportHw;
}

const qint64& DecodeVideo::timeStamp() const
{
    return m_iTimeStamp;
}
#endif // DECODEVIDEO_H
