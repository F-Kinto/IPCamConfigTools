/*********************************************************************
File : RtspVideoItem.h
Module : Rtsp
date : 2026/10/13
Ver : 1.2.0
History:
1.0.0 同步自 VmsTools/DataStructure/videoitem.h（VideoItem + YuvProvider）
     精简为 RTSP 直播专用：
     - 去掉 RenderTask/CardVideoPlayTask 任务链接入（回放进度/时长逻辑）
     - 内嵌 RtspLiveTask：device 属性变化自动起停拉流
     保留 VmsTools 的渲染核心：
     - YuvProvider（QAbstractVideoSurface）供 QML VideoOutput 消费
     - 15fps 定时器消费帧缓冲（上限 5 帧丢旧）+ YUV420P QVideoFrame 呈现
     QML 用法（与 VmsTools VideoItem 一致）：
        RtspVideoItem { id: videoItem; device: modelData
            VideoOutput { anchors.fill: parent; source: videoItem.yuvProvider } }
1.1.0 新增 Q_INVOKABLE reconnect()：断流/超时后 QML 手动重建拉流任务
      （setDevice 同值短路返回，无法充当重连入口）
1.2.0 修复关闭直播崩溃：任务改为无父对象创建，销毁统一走
      RtspLiveTask::stopAndDeleteLater()（等 init 线程返回后再释放，
      否则 Live555 回调带悬垂 this 在锁队列时崩溃）
1.3.0 "连接中"loading 加 5s 无流去抖：断流瞬间不再立即显示遮罩
      （偶断频繁出现/消失观感卡顿），连续 5s 无帧才置 hasVideoData=false
      显示；期间来帧即取消计时，恢复出流隐藏遮罩仍是即时的。首连/切流
      （restartTask）不去抖，loading 立即出现
********************************************************************/
#ifndef RTSPVIDEOITEM_H
#define RTSPVIDEOITEM_H

#include <QAbstractVideoSurface>
#include <QVideoSurfaceFormat>
#include <QList>
#include <QMutex>
#include <QObject>
#include <QQuickItem>
#include <QTimer>
#include <QVariantMap>

#include "RtspLiveTask.h"
#include "VideoInformation.h"

/**
 * @brief YUV 帧提供者：把 QVideoFrame present 给 QML VideoOutput 的 videoSurface
 *        （同步自 VmsTools YuvProvider，原样保留）
 */
class YuvProvider : public QObject {
    Q_OBJECT
    // VideoOutput 的 source 协议属性：source 对象需暴露 videoSurface
    Q_PROPERTY(QAbstractVideoSurface* videoSurface READ videoSurface WRITE setVideoSurface)

  public:
    explicit YuvProvider(QObject* parent = nullptr);
    ~YuvProvider();

    QAbstractVideoSurface* videoSurface() const;
    void                   setVideoSurface(QAbstractVideoSurface* surface);

    /** 按帧宽高设置 surface 格式并 present（空帧只复位格式） */
    void setFormat(int width, int height, QVideoFrame::PixelFormat format);
    void onNewVideoContentReceived(const QVideoFrame& frame);

  private:
    QAbstractVideoSurface* m_surface = nullptr;
    QVideoSurfaceFormat    m_format;
};

/**
 * @brief RTSP 直播窗口组件（QML 注册类型）
 *
 * 生命周期：QML delegate 创建 → device 赋值 → 自动 start 拉流；
 *           delegate 销毁（或 device 清空）→ 析构/置空 → 自动 stop。
 */
class RtspVideoItem : public QQuickItem {
    Q_OBJECT
    // 设备信息字典（DeviceInfo::toVariantMap 的字段，ip 必填）
    Q_PROPERTY(QVariantMap device READ device WRITE setDevice NOTIFY deviceChanged)
    // RTSP 认证（默认 admin/空；设备未开认证时传空）
    Q_PROPERTY(QString userName READ userName WRITE setUserName NOTIFY userNameChanged)
    Q_PROPERTY(QString password READ password WRITE setPassword NOTIFY passwordChanged)
    // 音频采样率（默认 8000，与设备端约定一致）
    Q_PROPERTY(int sampleRate READ sampleRate WRITE setSampleRate NOTIFY sampleRateChanged)
    // 主码流标志（true=ch00_0 主码流，false=ch00_1 子码流；起流时快照，变更不触发重连）
    Q_PROPERTY(bool mainStream READ mainStream WRITE setMainStream NOTIFY mainStreamChanged)
    // YUV 帧提供者（QML VideoOutput 的 source）
    Q_PROPERTY(YuvProvider* yuvProvider READ yuvProvider CONSTANT)
    // 是否已收到视频帧（首帧到达后置 true）
    Q_PROPERTY(bool hasVideoData READ hasVideoData NOTIFY hasVideoDataChanged)
    // 播放状态：0=空闲 1=连接中 2=播放中 3=连接失败/超时
    Q_PROPERTY(int playState READ playState NOTIFY playStateChanged)

  public:
    explicit RtspVideoItem(QQuickItem* parent = nullptr);
    ~RtspVideoItem();

    /**
     * @brief 手动重连：在现有 device 上重建拉流任务（QML 调用）
     *
     * 断流/超时后由界面"重新连接"按钮触发；setDevice 对相同 map 直接
     * 短路返回，无法作为重连入口，故提供独立方法。
     */
    Q_INVOKABLE void reconnect();

    const QVariantMap& device() const;
    void               setDevice(const QVariantMap& device);

    QString userName() const;
    void    setUserName(const QString& name);

    QString password() const;
    void    setPassword(const QString& pwd);

    int  sampleRate() const;
    void setSampleRate(int rate);

    bool mainStream() const;
    void setMainStream(bool main);

    YuvProvider* yuvProvider() const;

    bool hasVideoData() const;
    int  playState() const;

  signals:
    void deviceChanged();
    void userNameChanged();
    void passwordChanged();
    void sampleRateChanged();
    void mainStreamChanged();
    void hasVideoDataChanged();
    void playStateChanged();

  protected:
    /** 无帧时画深灰底色（同步自 VmsTools VideoItem::updatePaintNode） */
    QSGNode* updatePaintNode(QSGNode* oldNode, UpdatePaintNodeData* data) override;

  private slots:
    /** RtspLiveTask::frameReady 接收（QueuedConnection，GUI 线程） */
    void onFrameReady(const VideoInformation& frame);

    /** RtspLiveTask::playResult 接收（连接成功/失败） */
    void onPlayResult(int errorCode, const QString& message);

    /** 15fps 渲染定时器：取一帧 present 给 VideoOutput */
    void presentFrameVideoData();

  private:
    /** device/userName/password 变化后重启拉流任务 */
    void restartTask();

    void setHasVideoData(bool hasData);
    void setPlayState(int state);

  private:
    QVariantMap   m_device;     /**< 当前播放的设备信息 */
    QString       m_userName;   /**< RTSP 用户名（默认 admin） */
    QString       m_password;   /**< RTSP 密码（默认空） */
    int           m_sampleRate = 8000;
    bool          m_mainStream = false; /**< 主码流标志（true=ch00_0，false=ch00_1），默认子码流 */

    RtspLiveTask* m_task = nullptr;  /**< 拉流任务（无父对象，寿命由 stopAndDeleteLater 控制） */
    YuvProvider*  m_frameProvider = nullptr; /**< YUV 帧提供者 */

    QTimer                m_timer;      /**< 渲染定时器（15fps） */
    QTimer                m_noStreamDebounce; /**< 无流去抖定时器（连续 5s 无帧才显示"连接中"遮罩） */
    QMutex                m_mutexInfolist; /**< 帧缓冲锁 */
    QList<VideoInformation> m_infoList; /**< 待渲染帧缓冲（上限 5，超限丢旧） */

    bool m_hasVideoData = false;
    int  m_playState    = 0;
};

#endif // RTSPVIDEOITEM_H
