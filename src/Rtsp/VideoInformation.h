/*********************************************************************
File : VideoInformation.h
Module : Rtsp
date : 2026/10/13
Ver : 1.0.0
History:
1.0.0 同步自 VmsTools/DataStructure/videoinformation.h
     去掉 BaseDataStruct/Task 体系依赖，仅保留 RTSP 直播渲染
     所需的 YUV420P 帧字段（整帧打包 m_yuvData = Y+U+V 平面连续存储）
********************************************************************/
#ifndef VIDEOINFORMATION_H
#define VIDEOINFORMATION_H

#include <QByteArray>
#include <QtGlobal>

/**
 * @brief 一帧解码后的视频数据（YUV420P 整帧）
 *
 * m_yuvData 布局与 QVideoFrame::Format_YUV420P 一致：
 *   Y 平面 width*height，U 平面 width*height/4，V 平面 width*height/4
 * 渲染端按 width*height*3/2 校验长度后直接 memcpy 进 QVideoFrame。
 */
class VideoInformation {

  public:
    VideoInformation()
        : m_width(0),
          m_height(0),
          m_timeStamp(0)
    {
    }

    VideoInformation(const VideoInformation& other) = default;
    VideoInformation& operator=(const VideoInformation& other) = default;

    void reset()
    {
        m_yuvData.clear();
        m_width    = 0;
        m_height   = 0;
        m_timeStamp = 0;
    }

    /** 是否携带有效帧数据 */
    bool isValid() const
    {
        return !m_yuvData.isEmpty() && m_width > 0 && m_height > 0;
    }

  public:
    QByteArray m_yuvData;   /**< YUV420P 整帧数据（Y+U+V 连续平面） */
    int        m_width;     /**< 帧宽度（像素） */
    int        m_height;    /**< 帧高度（像素） */
    quint64    m_timeStamp; /**< 帧时间戳（毫秒） */
};

Q_DECLARE_METATYPE(VideoInformation)

#endif // VIDEOINFORMATION_H
