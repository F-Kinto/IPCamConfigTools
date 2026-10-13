/*********************************************************************
File : RtspVideoItem.cpp
Module : Rtsp
date : 2026/10/13
Ver : 1.3.0
History:
1.0.0 同步自 VmsTools/DataStructure/videoitem.cpp
1.1.0 新增 reconnect()（Q_INVOKABLE，QML 断流后手动重建任务）
1.2.0 修复关闭直播崩溃：任务无父创建，销毁改走 stopAndDeleteLater()，精简为 RTSP 直播：
     - YuvProvider          ← videoitem.cpp:19（原样）
     - 构造/析构与定时器    ← videoitem.cpp:66（15fps 渲染节流）
     - updatePaintNode      ← videoitem.cpp:93（底色）
     - updateVideoData      ← videoitem.cpp:135（帧入缓冲，上限 5 丢旧）
     - preseentFrameVideoData ← videoitem.cpp:165（YUV420P QVideoFrame present，
       去掉 CardVideoPlayTask 回放进度 200 行）
     新增 device 属性驱动的起停逻辑（替代 VmsTools 的 RenderTask 任务链接入）。
1.3.0 "连接中"loading 加 5s 无流去抖（NO_STREAM_DEBOUNCE_MS）：
     断流瞬间不再立即置 hasVideoData=false（偶断频繁出现/消失观感卡顿），
     连续 5s 无帧才显示遮罩，期间来帧即取消计时；首连/切流不去抖
********************************************************************/
#include "RtspVideoItem.h"

#include "DeviceManager.h"

#include <QDebug>
#include <QSGSimpleRectNode>

/** 渲染节流帧率（与 VmsTools VideoItem 一致） */
#define FRAM_TIME_SPEED 15

/** 待渲染帧缓冲上限（超限丢旧两帧，同步自 VmsTools） */
#define MAX_RENDER_BUFFER 5

/** 无流去抖时长：断流后连续这么久没帧才显示"连接中"遮罩 */
#define NO_STREAM_DEBOUNCE_MS 5000

// 跨线程 queued 信号传递自定义类型需注册 metatype（幂等）
static const int s_videoInfoMetaType = qRegisterMetaType<VideoInformation>("VideoInformation");

YuvProvider::YuvProvider(QObject* parent) : QObject(parent) {}

YuvProvider::~YuvProvider() {}

QAbstractVideoSurface* YuvProvider::videoSurface() const
{
    return m_surface;
}

void YuvProvider::setVideoSurface(QAbstractVideoSurface* surface)
{
    if (m_surface && m_surface != surface && m_surface->isActive()) {
        m_surface->stop();
    }

    m_surface = surface;

    if (m_surface && m_format.isValid()) {
        m_format = m_surface->nearestFormat(m_format);
        m_surface->start(m_format);
    }
}

void YuvProvider::setFormat(int width, int height, QVideoFrame::PixelFormat format)
{
    QSize               size(width, height);
    QVideoSurfaceFormat vsformat(size, format);
    m_format = vsformat;

    if (m_surface) {
        if (m_surface->isActive()) {
            m_surface->stop();
        }
        m_format = m_surface->nearestFormat(m_format);
        m_surface->start(m_format);
    }
}

void YuvProvider::onNewVideoContentReceived(const QVideoFrame& frame)
{
    if (!frame.isValid()) {
        if (m_surface && m_surface->isActive())
            m_surface->stop();
        return;
    }

    setFormat(frame.width(), frame.height(), frame.pixelFormat());

    if (m_surface)
        m_surface->present(frame);
}

RtspVideoItem::RtspVideoItem(QQuickItem* parent) : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
    setAntialiasing(true);
    m_userName = "admin"; // 默认账号（与设备端出厂一致）

    m_timer.setInterval(1000.0 / FRAM_TIME_SPEED); // 渲染速度
    connect(&m_timer, &QTimer::timeout, this, &RtspVideoItem::presentFrameVideoData);

    // 无流去抖：断流后只有连续 5s 没帧才进入"连接中"态（置 hasVideoData=false
    // 显示遮罩）。偶断（如网络抖动几秒）期间计时被来帧取消，loading 不闪现；
    // 恢复出流后遮罩隐藏仍走 onFrameReady 的即时置 true，不受去抖影响
    m_noStreamDebounce.setSingleShot(true);
    m_noStreamDebounce.setInterval(NO_STREAM_DEBOUNCE_MS);
    connect(&m_noStreamDebounce, &QTimer::timeout, this, [this]() {
        if (!m_hasVideoData)
            return;
        qInfo() << "LOG::RtspVideoItem no stream for" << NO_STREAM_DEBOUNCE_MS << "ms, show loading mask";
        setHasVideoData(false);
    });

    m_frameProvider = new YuvProvider(this);
}

RtspVideoItem::~RtspVideoItem()
{
    m_timer.stop();
    m_noStreamDebounce.stop();
    // 任务无父对象（见 restartTask），寿命由 stopAndDeleteLater 控制：
    // 等 init + recv 视频/音频线程全部退出后才释放，期间回访成员安全
    if (m_task) {
        m_task->disconnect(this);
        m_task->stopAndDeleteLater();
        m_task = nullptr;
    }
    setHasVideoData(false);
}

QSGNode* RtspVideoItem::updatePaintNode(QSGNode* oldNode, UpdatePaintNodeData*)
{
    auto node = dynamic_cast<QSGSimpleRectNode*>(oldNode);
    if (!node) {
        node = new QSGSimpleRectNode();
        node->setColor("#666666");
    }
    node->setRect(boundingRect());
    return node;
}

const QVariantMap& RtspVideoItem::device() const
{
    return m_device;
}

void RtspVideoItem::setDevice(const QVariantMap& device)
{
    if (m_device == device)
        return;

    m_device = device;

    // 换设备：先重置为出厂默认凭据，防止上一台设备的凭证残留串到本台
    m_userName = "admin"; // 默认账号（与设备端出厂一致）
    m_password.clear();

    // map 带 RTSP 凭据（user 非空）则成对填入；缓存兜底由 restartTask 起流前再查
    const QString user = device.value("rtspUserName").toString();
    if (!user.isEmpty()) {
        m_userName = user;
        m_password = device.value("rtspPassword").toString();
    }

    emit userNameChanged();
    emit passwordChanged();
    emit deviceChanged();
    restartTask();
}

void RtspVideoItem::reconnect()
{
    // 断流/超时后 QML 手动重连：同值 setDevice 会短路返回，
    // 直接走任务重建（含凭据缓存合并、playState 归位）
    restartTask();
}

QString RtspVideoItem::userName() const
{
    return m_userName;
}

void RtspVideoItem::setUserName(const QString& name)
{
    if (m_userName == name)
        return;

    m_userName = name;
    emit userNameChanged();
    restartTask();
}

QString RtspVideoItem::password() const
{
    return m_password;
}

void RtspVideoItem::setPassword(const QString& pwd)
{
    if (m_password == pwd)
        return;

    m_password = pwd;
    emit passwordChanged();
    restartTask();
}

int RtspVideoItem::sampleRate() const
{
    return m_sampleRate;
}

void RtspVideoItem::setSampleRate(int rate)
{
    if (m_sampleRate == rate)
        return;

    m_sampleRate = rate;
    emit sampleRateChanged();
}

YuvProvider* RtspVideoItem::yuvProvider() const
{
    return m_frameProvider;
}

bool RtspVideoItem::hasVideoData() const
{
    return m_hasVideoData;
}

int RtspVideoItem::playState() const
{
    return m_playState;
}

void RtspVideoItem::restartTask()
{
    // 旧任务停止（内部优雅退出，不阻塞 GUI）。注意不能 stop()+deleteLater()
    // 直接组合：对象须存活到 startOpenUrl() 返回（MultiRtspClient 约定），
    // 且 recv 线程访问成员期间也不能释放；stopAndDeleteLater 等全部线程
    // 退出后才 deleteLater
    if (m_task) {
        m_task->disconnect(this);
        m_task->stopAndDeleteLater();
        m_task = nullptr;
    }

    m_mutexInfolist.lock();
    m_infoList.clear();
    m_mutexInfolist.unlock();

    m_timer.stop();
    // 作废旧任务遗留的无流去抖计时；首连/切流场景 hasVideoData 立即置
    // false（loading 遮罩马上出现），不走去抖——去抖只针对偶断流
    m_noStreamDebounce.stop();
    setHasVideoData(false);
    setPlayState(0);

    // device 为空字典时仅清理，不拉流
    const QString ip = m_device.value("ip").toString();
    if (ip.isEmpty())
        return;

    // 起流凭据闸门：优先取 DeviceManager 缓存中该设备（HTTP 接口获取）的凭证，
    // 未命中（预取失败/尚未返回）时沿用属性值（setDevice 已按 map 重置/填充），
    // 保证传给 RtspLiveTask::start 的 userName/password 对应该 ip 设备
    const QVariantMap credDevice = DeviceManager::instance()->mergeRtspCredential(m_device);
    const QString credUser = credDevice.value("rtspUserName").toString();
    if (!credUser.isEmpty()) {
        m_userName = credUser;
        m_password = credDevice.value("rtspPassword").toString();
    }

    qInfo() << "LOG::RtspVideoItem start task, ip:" << ip
            << "user:" << m_userName
            << "credSource:" << (!credUser.isEmpty() ? "DeviceManager cache" : "device map/default");

    // 无父对象创建：任务寿命完全由 stopAndDeleteLater 控制
    // （父子挂接会在本对象析构时被同步 delete，破坏"存活至 startOpenUrl
    //   返回"的约定，导致 Live555 回调崩溃）
    m_task = new RtspLiveTask();
    // frameReady 从 recv 解码线程 emit，必须 QueuedConnection 回 GUI 线程
    connect(m_task, &RtspLiveTask::frameReady, this, &RtspVideoItem::onFrameReady, Qt::QueuedConnection);
    connect(m_task, &RtspLiveTask::playResult, this, &RtspVideoItem::onPlayResult, Qt::QueuedConnection);

    setPlayState(1); // 连接中
    m_task->start(ip, m_userName, m_password, m_sampleRate);
}

void RtspVideoItem::onPlayResult(int errorCode, const QString& message)
{
    if (errorCode == 0) {
        qInfo() << "LOG::RtspVideoItem play success, ip:" << m_device.value("ip").toString();
        setPlayState(2); // 播放中
    } else {
        setPlayState(3); // 连接失败/超时
        qWarning() << "LOG::RtspVideoItem play error:" << message << "ip:" << m_device.value("ip").toString();
    }
}

void RtspVideoItem::onFrameReady(const VideoInformation& frame)
{
    // 空帧：停止渲染（同步自 VideoItem::updateVideoData 的空数据分支）。
    // 不立即置 hasVideoData=false：进入 5s 去抖，连续无流才显示"连接中"
    // 遮罩（断流瞬间就弹 loading 会频繁出现/消失，观感卡顿）
    if (!frame.isValid()) {
        m_timer.stop();
        m_noStreamDebounce.start();
        return;
    }

    // 有效帧到达：取消无流去抖计时（无论计时是否在跑）
    m_noStreamDebounce.stop();

    m_mutexInfolist.lock();
    if (m_infoList.size() > MAX_RENDER_BUFFER) {
        m_infoList.removeAt(0);
        m_infoList.removeAt(0);
    }
    m_infoList.append(frame);
    m_mutexInfolist.unlock();

    if (!m_timer.isActive()) {
        m_timer.start();
        setHasVideoData(true);
    }
}

void RtspVideoItem::presentFrameVideoData()
{
    // 渲染队列空：停渲染并进入 5s 去抖（连续无帧才显示"连接中"遮罩）
    if (!m_task || m_infoList.isEmpty()) {
        m_timer.stop();
        m_noStreamDebounce.start();
        return;
    }

    m_mutexInfolist.lock();
    auto info = m_infoList.takeFirst();
    m_mutexInfolist.unlock();

    if (info.m_yuvData.isEmpty())
        return;

    int expectedSize = info.m_width * info.m_height * 3 / 2;
    if (info.m_yuvData.size() != expectedSize) {
        qWarning() << "LOG::RtspVideoItem data size does not match YUV420P format, frame skipped";
        return;
    }

    // YUV420P 整帧 → QVideoFrame（同步自 VideoItem::preseentFrameVideoData）
    QVideoFrame f(info.m_yuvData.size(), QSize(info.m_width, info.m_height), info.m_width, QVideoFrame::Format_YUV420P);
    if (f.map(QAbstractVideoBuffer::ReadWrite)) {
        memcpy(f.bits(), info.m_yuvData.constData(), info.m_yuvData.size());
        f.setStartTime(0);
        f.unmap();
        if (m_frameProvider)
            m_frameProvider->onNewVideoContentReceived(f);
    }
}

void RtspVideoItem::setHasVideoData(bool hasData)
{
    if (m_hasVideoData == hasData)
        return;
    m_hasVideoData = hasData;
    emit hasVideoDataChanged();
}

void RtspVideoItem::setPlayState(int state)
{
    if (m_playState == state)
        return;
    m_playState = state;
    emit playStateChanged();
}
