/*********************************************************************
File : RtspLiveTask.cpp
Module : Rtsp
date : 2026/10/13
Ver : 1.3.1
History:
1.0.0 同步自 VmsTools RtspDecodeTask.cpp，精简为固定 RTSP 单路拉流：
     - initRtspService      ← RtspDecodeTask.cpp:985（URL 拼装 + MultiRtspClient 启动）
     - rtspDataCallBack     ← RtspDecodeTask.cpp:847（3+1 字节头组包 + 通道入队）
     - recvVideoData        ← RtspDecodeTask.cpp:377（selfGuard 检查点 + 队列消费）
     - decodeOnePacket      ← decodetask_video.cpp:252（initVideoCodec + decodeVideo + YUV 拷贝 emit）
     - recvAudioData        ← RtspDecodeTask.cpp:621（G711/AAC 判断 + QAudioOutput 播放）
     - stopTask             ← RtspDecodeTask.cpp:160（SharedStopFlag + quitPromise，不阻塞主线程）
1.1.0 新增 stopAndDeleteLater()：修复关闭直播时 rtspDataCallBack 崩溃。
     根因：stop()+deleteLater() 在 GUI 线程很快释放对象，而 init 线程仍
     堵在 startOpenUrl 退出中，Live555 收流线程继续带着悬垂 this 回调，
     锁已销毁的 m_rawVideoLock 即崩（MultiRtspClient.h 约定 this 须存活
     至 startOpenUrl 返回）。改为等 init future 完成后再 deleteLater。
1.2.0 第二轮崩溃修复：recv 视频/音频线程的 QFuture 此前未保存，
     stopAndDeleteLater 只等 init future 就释放对象，音频线程仍在
     循环体内访问 m_rawAudioLock/m_ip（RtspLiveTask.cpp:455-461
     recvAudioData 清理段崩溃）。现保存 recv 两线程 future，三个
     watcher 全部发出 finished 后才 deleteLater，并通过
     tryDeleteAfterThreadsExit + isRunning() 兜底处理默认 future。
1.3.0 新增静态存活登记 + waitForAllThreadsExit()（见头文件 1.3.0）：
     退出程序前 GUI 阻塞轮询所有存活任务线程真实退出，替代 QML
     固定延时盲等（500ms 赌运气，Live555 慢退出时拆进程仍崩）
1.3.1 修复 waitForAllThreadsExit 死锁式等待：等待前未发停止指令，
     停止依赖 deleteLater 析构链（delegate → RtspVideoItem →
     stopAndDeleteLater → stop），而等待本身阻塞 GUI 事件循环，
     析构链在等待期间无法执行——超时必触发，线程实际退出被推迟到
     Qt.quit() 拆进程期间（与 1.0 修复的崩溃同一竞态）。
     现轮询前先对所有存活任务主动调 stop()（幂等、GUI 线程安全）
********************************************************************/
#include "RtspLiveTask.h"
#include "DecodeVideo.h"

#include "MultiRtspClient.h"

#include <QAudioFormat>
#include <QAudioDeviceInfo>
#include <QAudioOutput>
#include <QDebug>
#include <QElapsedTimer>
#include <QThread>
#include <QtConcurrent>

extern "C" {
#include <libavutil/imgutils.h>
}

// 存活任务登记（见 RtspLiveTask.h 1.3.0 注释）：增删均在 GUI 线程
QList<RtspLiveTask*> RtspLiveTask::s_aliveTasks;
QMutex               RtspLiveTask::s_aliveLock;

RtspLiveTask::RtspLiveTask(QObject* parent) : QObject(parent)
{
    // 登记进存活集合（GUI 线程）：供 waitForAllThreadsExit 退出程序前轮询
    {
        QMutexLocker lock(&s_aliveLock);
        s_aliveTasks.append(this);
    }
    connect(&m_initWatcher, &QFutureWatcher<int>::finished, this, &RtspLiveTask::onInitFinished);
}

RtspLiveTask::~RtspLiveTask()
{
    // 注销存活登记（GUI 线程，析构只可能经 deleteLater 走到这里）
    {
        QMutexLocker lock(&s_aliveLock);
        s_aliveTasks.removeOne(this);
    }
    RtspLiveTask::stop();
    // 到这里 init + recv 视频/音频线程必已退出（stopAndDeleteLater 保证），
    // stop() 只是复位幂等兜底。
}

void RtspLiveTask::start(const QString& ip, const QString& userName, const QString& password, int sampleRate,
                         bool mainStream)
{
    if (ip.isEmpty()) {
        emit playResult(1, "device ip is empty");
        return;
    }

    m_ip         = ip;
    m_userName   = userName;
    m_password   = password;
    m_sampleRate = sampleRate;
    m_mainStream = mainStream;

    m_isStopTask = 0;
    m_isInitDone = 0;
    m_dataReceived = 0;
    m_recvLaunched = false;

    // 创建新的 SharedStopFlag 供新 init 线程使用（对应 VmsTools doTask 的阶段1解耦逻辑）
    m_initStopFlag = std::make_shared<SharedStopFlag>();
    m_recvStopFlag = std::make_shared<SharedStopFlag>();
    m_quitIssued   = false;
    m_quitPromise  = std::promise<bool>();
    auto quitFuture = m_quitPromise.get_future().share();

    qInfo() << "LOG::RtspLiveTask start, ip:" << m_ip << "user:" << m_userName
            << "QThread ID:" << QThread::currentThreadId();
    qInfo() << "LOG::RtspLiveTask step[1/5] connecting: ip=" << m_ip;
    m_initFuture = QtConcurrent::run([this, quitFuture]() -> int { return initRtspService(quitFuture) ? 1 : 0; });
    m_initWatcher.setFuture(m_initFuture);
}

void RtspLiveTask::stop()
{
    m_isStopTask = 1;
    m_isInitDone = 0;

    // 通知 recv 线程退出（协作式，不 wait）
    if (m_recvStopFlag)
        m_recvStopFlag->stopped.store(true);

    // 通知 RTSP 客户端退出：解除 startOpenUrl 阻塞
    if (!m_quitIssued) {
        m_quitIssued = true;
        try {
            m_quitPromise.set_value(true);
        } catch (const std::future_error& e) {
            qInfo() << "LOG::RtspLiveTask quitPromise future_error:" << QString::fromUtf8(e.what());
        }
    }

    // 通知 init 线程：下次检查点退出
    if (m_initStopFlag)
        m_initStopFlag->stopped.store(true);

    // 断开 init 完成回调，防止 init 线程退出后再拉起 recv 线程
    disconnect(&m_initWatcher, &QFutureWatcher<int>::finished, this, &RtspLiveTask::onInitFinished);

    // 清空缓存队列，让 recv 线程自然结束消费
    clearCache();
}

void RtspLiveTask::stopAndDeleteLater()
{
    // 防重入：restartTask 与析构可能先后调用（首次调用后对象已在等自毁）
    if (m_deletePending)
        return;
    m_deletePending = true;

    // 停止（解除 startOpenUrl 阻塞、通知 recv 线程退出）
    stop();

    // init + recv 视频/音频全部退出后才能析构：
    //  - init 线程：MultiRtspClient 约定 this 须存活到 startOpenUrl 返回
    //  - recv 线程：循环体内持续访问 m_rawVideoLock/m_rawAudioLock/m_ip 等
    //    成员，selfGuard 仅是析构已发生时的兜底，不能替代"等线程退出
    //    再析构"的正确顺序
    // 检测方式：三个 watcher 的 finished 都连到 tryDeleteAfterThreadsExit，
    // 每次触发时补挂仍在跑的 future 并检查是否全部退出。
    // （同线程内先连后查无竞态：future 完成事件的派发必然晚于 connect
    //   建立时点，不会漏收）
    connect(&m_initWatcher, &QFutureWatcher<int>::finished, this, &RtspLiveTask::tryDeleteAfterThreadsExit);
    connect(&m_recvVideoWatcher, &QFutureWatcher<void>::finished, this, &RtspLiveTask::tryDeleteAfterThreadsExit);
    connect(&m_recvAudioWatcher, &QFutureWatcher<void>::finished, this, &RtspLiveTask::tryDeleteAfterThreadsExit);
    qInfo() << "LOG::RtspLiveTask deferred delete until all threads exit, ip:" << m_ip;

    // 主动检查一次：init 已退出或从未启动时其 finished 不会再触发；
    // 仍在跑时进入也无害（后续对应 watcher 的 finished 会再进）
    tryDeleteAfterThreadsExit();
}

void RtspLiveTask::tryDeleteAfterThreadsExit()
{
    // init 仍在跑：其 watcher finished 会再次进入本函数
    if (m_initFuture.isRunning())
        return;

    // recv 线程仍在跑：补挂对应 watcher（launch 晚于本函数时此补挂，
    // 对已完成 future 挂 watcher 也会补发 finished，不会漏；已挂过/未
    // 启动的 future 由 != 检查与 isRunning 短路排除）。锁内读写与
    // launchRecvThreadsIfNeeded 的赋值互斥，防止撕裂与漏挂。
    {
        QMutexLocker lock(&m_recvLaunchLock);
        if (m_recvVideoFuture.isRunning() && m_recvVideoWatcher.future() != m_recvVideoFuture)
            m_recvVideoWatcher.setFuture(m_recvVideoFuture);
        if (m_recvAudioFuture.isRunning() && m_recvAudioWatcher.future() != m_recvAudioFuture)
            m_recvAudioWatcher.setFuture(m_recvAudioFuture);
        // isRunning==false 覆盖"已退出"与"从未启动"（默认构造的 future 不发事件）
        if (m_recvVideoFuture.isRunning() || m_recvAudioFuture.isRunning())
            return; // 还有 recv 线程未退，其 watcher finished 会再次进入本函数
    }

    // 全部退出：断开自毁检测（防止 deleteLater 排队期间重复触发）
    disconnect(&m_initWatcher, &QFutureWatcher<int>::finished, this, &RtspLiveTask::tryDeleteAfterThreadsExit);
    disconnect(&m_recvVideoWatcher, &QFutureWatcher<void>::finished, this, &RtspLiveTask::tryDeleteAfterThreadsExit);
    disconnect(&m_recvAudioWatcher, &QFutureWatcher<void>::finished, this, &RtspLiveTask::tryDeleteAfterThreadsExit);

    qInfo() << "LOG::RtspLiveTask all threads exited, deleteLater now, ip:" << m_ip;
    deleteLater();
}

bool RtspLiveTask::isPlaying() const
{
    return m_isInitDone && !m_isStopTask;
}

bool RtspLiveTask::anyThreadRunning()
{
    // init 线程：m_initFuture 仅在 GUI 线程 start() 赋值，无竞争可直接查
    if (m_initFuture.isRunning())
        return true;
    // recv 两线程：future 由 Live555 线程（launchRecvThreadsIfNeeded）写入，
    // 与 tryDeleteAfterThreadsExit 相同做法——锁内查询，防撕裂写入
    QMutexLocker lock(&m_recvLaunchLock);
    return m_recvVideoFuture.isRunning() || m_recvAudioFuture.isRunning();
}

bool RtspLiveTask::waitForAllThreadsExit(int timeoutMs)
{
    // 先主动发停止指令再轮询（v1.3.1 修复死锁式等待）：本函数阻塞 GUI
    // 线程，事件循环随之冻结，closeLivePreview 触发的 deleteLater 析构链
    // （delegate → RtspVideoItem → stopAndDeleteLater → stop）在本函数
    // 返回前无法执行——不主动停止，停止标记永远送不到工作线程，超时必
    // 触发，线程实际退出被推迟到 Qt.quit() 拆进程期间（与退出崩溃同一
    // 竞态）。stop() 本就设计为 GUI 线程调用且幂等（m_quitIssued 守卫、
    // 原子标记重复置位无害），后续 deleteLater 链再调一次也无副作用。
    {
        QMutexLocker lock(&s_aliveLock);
        for (RtspLiveTask* task : s_aliveTasks)
            task->stop();
    }

    QElapsedTimer elapsed;
    elapsed.start();
    while (true) {
        bool anyRunning = false;
        {
            // 集合增删均在 GUI 线程（本函数也在 GUI 线程阻塞轮询，
            // 期间 deleteLater 不会执行），锁为防御性
            QMutexLocker lock(&s_aliveLock);
            for (RtspLiveTask* task : s_aliveTasks) {
                if (task->anyThreadRunning()) {
                    anyRunning = true;
                    break;
                }
            }
        }
        if (!anyRunning) {
            if (elapsed.elapsed() > 0)
                qInfo() << "LOG::RtspLiveTask all live threads exited after" << elapsed.elapsed() << "ms";
            return true;
        }
        if (elapsed.elapsed() >= timeoutMs) {
            int alive = 0;
            {
                QMutexLocker lock(&s_aliveLock);
                alive = s_aliveTasks.size();
            }
            qWarning() << "LOG::RtspLiveTask waitForAllThreadsExit timeout" << timeoutMs
                       << "ms, alive tasks:" << alive;
            return false;
        }
        // 线程收尾以 msleep 粒度轮询检查点，20ms 步进足够跟得上
        QThread::msleep(20);
    }
}

void RtspLiveTask::clearCache()
{
    QMutexLocker videoLocker(&m_rawVideoLock);
    m_videoList.clear();
    QMutexLocker audioLocker(&m_rawAudioLock);
    m_audioList.clear();
}

bool RtspLiveTask::initRtspService(const std::shared_future<bool>& quitFuture)
{
    // selfGuard 防护：本方法在 QtConcurrent 工作线程中运行，
    // startOpenUrl 阻塞期间 stop() 可能被调用并析构本对象，
    // 阻塞返回后若 this 已析构则所有成员访问均为 UB。
    QPointer<RtspLiveTask> selfGuard(this);

    qInfo() << "LOG::initRtspService QThread ID:" << QThread::currentThreadId();

    // URL 拼装（同步自 RtspDecodeTask.cpp:1001）：rtsp://user:pwd@ip/live/ch00_0
    // 码流后缀由主界面“主码流播放”勾选状态决定：勾选 ch00_0 主码流，未勾选 ch00_1 子码流
    const QString streamSuffix = m_mainStream ? QStringLiteral("ch00_0") : QStringLiteral("ch00_1");
    QString rtspUrl = (!m_userName.isEmpty() && !m_password.isEmpty())
                          ? QString("rtsp://%1:%2@%3/live/%4").arg(m_userName).arg(m_password).arg(m_ip).arg(streamSuffix)
                          : QString("rtsp://%1/live/%2").arg(m_ip).arg(streamSuffix);

    qInfo() << "LOG::RtspLiveTask step[2/5] open rtsp url:" << rtspUrl;

    MultiRtspClient rtspClient;
    rtspClient.setRtspDataCallBack(std::bind(&RtspLiveTask::rtspDataCallBack, this, std::placeholders::_1, std::placeholders::_2, std::placeholders::_3,
                                              std::placeholders::_4, std::placeholders::_5, std::placeholders::_6, std::placeholders::_7));
    rtspClient.setRtpOverTcp(true); // 固定 RTP over TCP（VmsTools 默认方式）
    rtspClient.insertRtspUrl(rtspUrl.toStdString(), 0);

    bool initResult = rtspClient.startOpenUrl(quitFuture); // 阻塞收流，直到 quitFuture ready 或流结束

    if (!selfGuard) { // 检查点1：startOpenUrl 阻塞期间对象可能已析构
        qInfo() << "LOG::RtspLiveTask destroyed during startOpenUrl, abort init";
        return false;
    }
    qInfo() << "LOG::RtspLiveTask step[5/5] stream closed, initResult:" << initResult << "ip:" << m_ip;
    return initResult;
}

void RtspLiveTask::launchRecvThreadsIfNeeded(const char* firstType, const char* codeName)
{
    // 首包日志（只打一次）
    if (!m_dataReceived.exchange(1))
        qInfo() << "LOG::RtspLiveTask step[3/5] first data arrived:" << firstType
                << "codec:" << codeName << "ip:" << m_ip;

    // 停止后迟到的数据不再拉线程
    if (m_isStopTask)
        return;

    // 防重复拉起（视频/音频回调都可能首发到达）
    bool expected = false;
    if (!m_recvLaunched.compare_exchange_strong(expected, true))
        return;

    qInfo() << "LOG::RtspLiveTask launch recv threads (data-driven), ip:" << m_ip;
    m_isInitDone = 1;
    emit playResult(0, QString()); // 接收方 Queued 回 GUI：播放中

    auto recvStopFlag = m_recvStopFlag;

    // 锁内赋值 recv future + 拉线程：
    // 与 stopAndDeleteLater/tryDeleteAfterThreadsExit 中读同一批 future 互斥，
    // 防止撕裂写入与 watcher 漏挂（QtConcurrent::run 仅提交任务，瞬间返回，
    // 锁内不做重活所以不与队列锁嵌套）
    {
        QMutexLocker lock(&m_recvLaunchLock);
        // recv 视频线程
        m_recvVideoFuture = QtConcurrent::run([this, recvStopFlag]() { recvVideoData(recvStopFlag); });
        // recv 音频线程（采样率固定取设备端约定值，VmsTools 取 localRtspDeviceSampleRate）
        m_recvAudioFuture = QtConcurrent::run([this, recvStopFlag]() { recvAudioData(m_sampleRate, recvStopFlag); });
    }
}

void RtspLiveTask::onInitFinished()
{
    // startOpenUrl 已返回：正常 stop / 流结束 / 连接失败
    if (m_isStopTask) {
        qInfo() << "LOG::RtspLiveTask stopped, init finished but not proceeding";
        return;
    }

    int result = m_initWatcher.result();

    // 流已结束：通知 recv 线程退出
    m_isInitDone = 0;
    if (m_recvStopFlag)
        m_recvStopFlag->stopped.store(true);

    if (m_dataReceived.load()) {
        // 收过数据后流中断（设备断开/网络异常）
        qWarning() << "LOG::RtspLiveTask stream ended unexpectedly, initResult:" << result << "ip:" << m_ip;
        emit playResult(1, "Stream ended");
        return;
    }

    // 从未收到数据：连接失败/超时/认证被拒（含 startOpenUrl 返回 false）
    qWarning() << "LOG::RtspLiveTask init failed (no data received), initResult:" << result << "ip:" << m_ip;
    emit playResult(1, "Connection timed out, Please try again later");
}

void RtspLiveTask::rtspDataCallBack(unsigned char* data, int size, const char* type, const char* codeName, int index, char* rtspUrl, void* customObj)
{
    Q_UNUSED(rtspUrl);
    Q_UNUSED(customObj);

    if (size <= 0)
        return;

    bool isVideo(std::string(type).find("video") != std::string::npos);
    if (isVideo) {
        if (index != 0) // 单路任务只收 ch0
            return;
        // 首包数据驱动拉起 recv 线程（startOpenUrl 阻塞收流中，等它返回就晚了）
        launchRecvThreadsIfNeeded("video", codeName);
        // 帧组包（同步自 VmsDecodeTask.cpp:858）：3 字节 0 头 + 1 字节类型 + 裸流
        QByteArrayList bytesList;
        QByteArray      bytes;
        bytes.append(3, 0);
        bytes.append(1, 1);
        bytes.append((char*)data, size);
        bool isH265(std::string(codeName).find("H265") != std::string::npos);
        bytesList.append(!isH265 ? "H264" : "H265");
        bytesList.append(bytes);

        QMutexLocker locker(&m_rawVideoLock);
        while (m_videoList.size() > MAX_VIDEO_LIST_SIZE) // 超限丢旧帧防积压
            m_videoList.removeFirst();
        m_videoList.append(bytesList);
        return;
    }

    bool isAudio(std::string(type).find("audio") != std::string::npos);
    if (isAudio) {
        // 首包数据驱动拉起 recv 线程（音/视频谁先到谁触发）
        launchRecvThreadsIfNeeded("audio", codeName);
        QByteArrayList bytesList;
        QByteArray      bytes;
        bytes.append((char*)data, size);
        bytesList.append(QString::fromUtf8(codeName).toUtf8()); // codeName 含 PCM 走 G711，否则 AAC
        bytesList.append(bytes);

        QMutexLocker locker(&m_rawAudioLock);
        while (m_audioList.size() > MAX_AUDIO_LIST_SIZE)
            m_audioList.removeFirst();
        m_audioList.append(bytesList);
    }
}

void RtspLiveTask::recvVideoData(std::shared_ptr<SharedStopFlag> stopFlag)
{
    QPointer<RtspLiveTask> selfGuard(this);
    DecodeVideo            decoder;

    qInfo() << "LOG::[thread_ReceiveVideo] start, ip:" << m_ip << "QThread ID:" << QThread::currentThreadId();

    while (m_isInitDone && !m_isStopTask && !(stopFlag && stopFlag->stopped.load())) {
        // selfGuard 检查点：每次迭代检查对象是否已析构
        if (!selfGuard)
            return;

        QByteArrayList bytes;
        {
            QMutexLocker locker(&m_rawVideoLock);
            if (!m_videoList.isEmpty())
                bytes = m_videoList.takeFirst();
        }
        if (bytes.isEmpty()) {
            QThread::msleep(1); // 避免空转 CPU 占用过高
            continue;
        }

        decodeOnePacket(decoder, bytes);

        // selfGuard 检查点：decodeOnePacket 内含解码耗时操作，
        // 期间本对象可能被析构，返回后需再次验证对象有效性
        if (!selfGuard)
            return;
    }
    qInfo() << "LOG::[thread_ReceiveVideo] exit, ip:" << m_ip;
}

void RtspLiveTask::decodeOnePacket(DecodeVideo& decoder, QByteArrayList& dataArray)
{
    QPointer<RtspLiveTask> selfGuard(this);
    QByteArrayList         oneData = dataArray;

    if (!decoder.isVideoInit()) {
        // 解码线程数按 CPU 核数选择（同步自 DecodeTask::decodeVideoData）
        int threadCount = QThread::idealThreadCount() <= 4 ? 2 : 4;
        bool isH265(std::string(oneData.at(0)).find("H265") != std::string::npos);
        qInfo() << "LOG::RtspLiveTask step[4/5] init video codec:"
                << (isH265 ? "H265" : "H264") << "threads:" << threadCount << "ip:" << m_ip;
        if (!decoder.initVideoCodec(isH265, threadCount))
            return;
    }

    // 只请求 YUV（直播渲染不需要 RGB/裁剪分支）
    DecodedFrames df = decoder.decodeVideo((unsigned char*)oneData.last().data(), oneData.last().size(), ORIGINAL_YUV);
    if (!df.has(ORIGINAL_YUV))
        return;

    auto yuvFrame = df.originalYuv;
    if (!yuvFrame)
        return;

    // 清晰度切换后分辨率不匹配则丢弃此数据，否则会引起渲染崩溃（VmsTools 20250217 修复）
    if (yuvFrame->width != decoder.videoWidth() || yuvFrame->height != decoder.videoHeight())
        return;

    // YUV 拷贝成整帧（同步自 renderFrame lambda：av_image_copy_to_buffer）
    VideoInformation videoInfo;
    int              imageSize = av_image_get_buffer_size(AV_PIX_FMT_YUV420P, yuvFrame->width, yuvFrame->height, 1);
    if (imageSize <= 0) {
        qWarning() << "LOG::RtspLiveTask imagesize invalid:" << imageSize;
        return;
    }
    try {
        videoInfo.m_yuvData.resize(imageSize);
    } catch (...) {
        return;
    }
    videoInfo.m_height    = decoder.videoHeight();
    videoInfo.m_width     = decoder.videoWidth();
    videoInfo.m_timeStamp = decoder.timeStamp();
    av_image_copy_to_buffer((uint8_t*)videoInfo.m_yuvData.data(), imageSize, yuvFrame->data, yuvFrame->linesize, AV_PIX_FMT_YUV420P, yuvFrame->width, yuvFrame->height, 1);

    if (selfGuard)
        emit frameReady(videoInfo); // 接收方以 QueuedConnection 在 GUI 线程消费
}

void RtspLiveTask::recvAudioData(int sampleRate, std::shared_ptr<SharedStopFlag> stopFlag)
{
    QPointer<RtspLiveTask> selfGuard(this);
    DecodeVideo            decoder;

    QAudioFormat audioFormat;
    audioFormat.setSampleRate(sampleRate);
    audioFormat.setChannelCount(1);
    audioFormat.setSampleSize(16);
    audioFormat.setCodec("audio/pcm");
    audioFormat.setByteOrder(QAudioFormat::LittleEndian);
    audioFormat.setSampleType(QAudioFormat::SignedInt);

    QAudioDeviceInfo info = QAudioDeviceInfo::defaultOutputDevice();
    if (!info.isFormatSupported(audioFormat)) {
        qWarning() << "LOG::[thread_ReceiveAudio] audio format not supported, sampleRate:" << sampleRate;
        return;
    }

    QAudioOutput* audioOutput = new QAudioOutput(audioFormat);
    QIODevice*    streamOut   = audioOutput->start();

    QByteArray pcmBuffer;
    pcmBuffer.reserve(4096);

    while (m_isInitDone && !m_isStopTask && !(stopFlag && stopFlag->stopped.load())) {
        // selfGuard 检查点：每次迭代检查对象是否已析构
        if (!selfGuard)
            return;

        QByteArrayList byteArrayList;
        {
            QMutexLocker locker(&m_rawAudioLock);
            if (!m_audioList.isEmpty())
                byteArrayList = m_audioList.takeFirst();
        }
        if (byteArrayList.isEmpty()) {
            QThread::msleep(1);
            continue;
        }

        const QByteArray& codeName  = byteArrayList.at(0);
        const auto&       audioData = byteArrayList.last();

        bool isG711Audio = codeName.contains("PCM");

        if (!decoder.isAudioInit()) {
            if (isG711Audio) {
                if (!decoder.initG711AudioCodec(AV_SAMPLE_FMT_S16, 1, sampleRate)) {
                    decoder.unInitG711AudioCodec();
                    continue;
                }
            } else {
                if (!decoder.initAACAudioCodec(AV_SAMPLE_FMT_FLTP, 1, sampleRate)) {
                    decoder.unInitAACAudioCodec();
                    continue;
                }
            }
        }

        int  audioSize  = audioData.size();
        auto audioFrame = isG711Audio ? decoder.decodeG711Audio((unsigned char*)audioData.data(), audioSize)
                                      : decoder.decodeAAcAudio((unsigned char*)audioData.data(), audioSize);
        if (!audioFrame)
            continue;

        // 音频数据写入（分片写满，减少 write 次数）
        pcmBuffer.clear();
        pcmBuffer.append((const char*)audioFrame->data[0], audioFrame->linesize[0]);
        if (audioOutput->state() != QAudio::StoppedState && audioOutput->state() != QAudio::SuspendedState) {
            int bytesToWrite = pcmBuffer.size();
            int written      = 0;
            while (m_isInitDone && !m_isStopTask && !(stopFlag && stopFlag->stopped.load()) && bytesToWrite > 0) {
                int chunk = qMin(bytesToWrite, audioOutput->bytesFree());
                if (chunk <= 0) {
                    QThread::msleep(1);
                    continue;
                }
                int retWrite = streamOut->write(pcmBuffer.constData() + written, chunk);
                if (retWrite < 0)
                    break;
                written += retWrite;
                bytesToWrite -= retWrite;
            }
        }
        // selfGuard 检查点：写音频期间对象可能析构
        if (!selfGuard) {
            audioOutput->stop();
            delete audioOutput;
            return;
        }
    }

    // QAudioOutput::stop() 会自动销毁 start() 返回的 QIODevice*，
    // 不能手动 delete streamOut，否则 double-free 导致堆损坏（VmsTools 注释经验）
    audioOutput->stop();
    delete audioOutput;
    audioOutput = nullptr;
    streamOut   = nullptr;
    qInfo() << "LOG::[thread_ReceiveAudio] exit, ip:" << m_ip;
}
