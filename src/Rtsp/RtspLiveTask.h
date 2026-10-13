/*********************************************************************
File : RtspLiveTask.h
Module : Rtsp
date : 2026/10/13
Ver : 1.3.1
History:
1.0.0 同步自 VmsTools/Functional/PreviewModule/RtspDecodeTask（RtspDeviceTask）
     按本项目需求精简：
     - 固定走 RTSP 拉流（删除 TUTK/星桥/RTC 的连接方式判断与全部 TUTK 遗留）
     - 单设备单路主码流（ch00_0），删除多目通道矩阵
     - 删除 MP4 录制 / 流量统计 / 卡回放 / 双目裁剪等直播无关链路
     保留 VmsTools 的核心线程模型与背压设计：
     - init 线程（阻塞式 startOpenUrl）+ QFutureWatcher 结果回调
     - SharedStopFlag + quitPromise 优雅退出（绝不阻塞主线程）
     - 通道缓存队列上限丢旧帧 + QPointer selfGuard 跨线程析构防护
     - 音频 G711/AAC 解码 + QAudioOutput 播放
1.1.0 新增 stopAndDeleteLater()：对象必须存活到 startOpenUrl() 返回
     （MultiRtspClient 头文件约定），否则 Live555 收流线程带着悬垂 this
     回调，rtspDataCallBack 锁 m_rawVideoLock 即崩溃（关闭直播复现点）
1.2.0 第二轮崩溃修复：recv 视频/音频线程的 QFuture 此前未保存，
     stopAndDeleteLater 只等 init future 就释放对象，音频线程仍持
     this 访问 m_rawAudioLock/m_ip（recvAudioData 清理段崩溃）。
     现保存 recv 两线程 future，init+recv 全部退出后才 deleteLater
1.3.0 新增静态存活登记 + waitForAllThreadsExit()：退出程序前由 GUI
     阻塞轮询所有存活任务的线程真实退出（等不到 deleteLater 跑完，
     只等 future 退出），替代 QML 固定延时盲等，杜绝进程拆除时
     拉流线程仍在跑的崩溃窗口
1.3.1 修复 waitForAllThreadsExit 死锁式等待：等待前先对所有存活
     任务主动调 stop()。原本停止指令依赖 deleteLater 析构链送达，
     而等待阻塞 GUI 事件循环导致析构链无法执行——超时必触发，
     线程退出被推迟到 Qt.quit() 拆进程期间
********************************************************************/
#ifndef RTSDLIVETASK_H
#define RTSDLIVETASK_H

#include <QObject>
#include <QPointer>
#include <QMutex>
#include <QByteArrayList>
#include <QFuture>
#include <QFutureWatcher>
#include <QList>
#include <atomic>
#include <future>
#include <memory>

#include "VideoInformation.h"

class DecodeVideo;

/** 跨线程共享停止标记（init 线程 / recv 线程的协作式退出信号） */
struct SharedStopFlag {
    std::atomic<bool> stopped{false};
};

/**
 * @brief 单设备 RTSP 直播拉流任务
 *
 * 线程模型（同步自 VmsTools RtspDeviceTask）：
 *  - init 线程：QtConcurrent 跑 initRtspService，阻塞于 MultiRtspClient::startOpenUrl
 *    收流（RTP over TCP），数据经 rtspDataCallBack 回调入缓存队列
 *  - recv 视频线程：收到首包数据后由 rtspDataCallBack 拉起（VmsTools 为定时器轮询
 *    检测数据到达，本项目改为首包回调驱动，原子防重复），
 *    消费队列 → DecodeVideo 解码（H264/H265，软/硬解自适应）
 *    → frameReady 信号（Queued 回 GUI 线程渲染）
 *  - recv 音频线程：消费队列 → G711/AAC 解码 → QAudioOutput 播放
 *  注意：startOpenUrl 阻塞到流结束/退出才返回，其返回不能作为"连接成功"信号，
 *  播放成功的判定是首包数据到达（playResult(0)），流结束由 onInitFinished 收尾
 *
 * 退出策略（stop/析构 均不阻塞主线程）：
 *  - m_isStopTask + m_recvStopFlag 通知 recv 线程
 *  - quitPromise set_value 解除 startOpenUrl 阻塞
 *  - init 线程经 selfGuard 检查点安全退出
 */
class RtspLiveTask : public QObject {
    Q_OBJECT

  public:
    explicit RtspLiveTask(QObject* parent = nullptr);
    ~RtspLiveTask();

    /**
     * @brief 启动拉流（异步：内部起 init 线程，结果经 playResult 通知）
     * @param ip       设备 IP
     * @param userName RTSP 用户名（空则拼无认证 URL）
     * @param password RTSP 密码
     * @param sampleRate 音频采样率（默认 8000，与设备端一致）
     */
    void start(const QString& ip, const QString& userName, const QString& password, int sampleRate = 8000);

    /** 停止拉流并复位状态（可重复调用；不等待线程退出） */
    void stop();

    /**
     * @brief 停止拉流，并在全部工作线程（init + recv 视频/音频）退出后自动释放本对象
     *
     * MultiRtspClient 约定：调用方必须存活到 startOpenUrl() 返回为止
     * （期间 Live555 收流线程会持续带着 this 回调 rtspDataCallBack）。
     * stop() 只解除阻塞、不等线程退出，故析构释放必须推迟到 init future
     * 完成之后——直接 stop()+deleteLater() 会释放出悬垂 this 导致回调崩溃。
     * recv 视频/音频线程虽带 selfGuard 检查点，但其循环体内仍在访问
     * 本对象成员（锁/队列/m_ip），同样必须等线程退出后才能析构。
     * 外部（RtspVideoItem）应通过本接口销毁任务，且任务须无父对象创建。
     */
    void stopAndDeleteLater();

    /** 是否处于播放中（init 已完成且未停止） */
    bool isPlaying() const;

    /**
     * @brief 停止并阻塞等待所有存活任务的拉流线程退出（退出程序前调用）
     *
     * GUI 线程专用（会阻塞事件循环，调用方 UI 冻结属预期）。先对所有
     * 存活任务调 stop()（幂等）再轮询：等待期间事件循环冻结，常规停止
     * 路径（closeLivePreview → deleteLater 析构链 → stopAndDeleteLater）
     * 无法执行，必须由本函数主动发出停止指令，否则超时必触发（1.3.1）。
     *
     * 轮询所有存活任务（构造登记 / 析构注销，均在 GUI 线程）的 init +
     * recv 视频 + recv 音频三个 future 的 isRunning，全部退出返回 true，
     * 超时 false。
     *
     * 注意不能等 deleteLater 析构：GUI 阻塞期间 watcher 信号无法送达，
     * tryDeleteAfterThreadsExit 不执行，任务对象保持存活——本函数只保证
     * "线程已退出"（回调不再触达对象），内存释放交给进程退出统一回收。
     *
     * @param timeoutMs 最长等待毫秒数
     * @return true=所有线程已退出；false=超时仍有线程未退（调用方记日志兜底）
     */
    static bool waitForAllThreadsExit(int timeoutMs);

  signals:
    /** 解码后的一帧 YUV420P（QueuedConnection 回 GUI 线程） */
    void frameReady(const VideoInformation& frame);

    /** 连接结果：errorCode 0=init 成功开始收流；1=连接失败/超时（message 附原因） */
    void playResult(int errorCode, const QString& message);

  private slots:
    /** init 线程结束后回调（QFutureWatcher）：流结束收尾（停止 recv 线程、上报结果） */
    void onInitFinished();

    /** stopAndDeleteLater 的自毁检查：三个线程 future 全部退出后 deleteLater */
    void tryDeleteAfterThreadsExit();

  private:
    bool initRtspService(const std::shared_future<bool>& quitFuture);

    /**
     * @brief 首包数据到达处理：上报播放成功并拉起 recv 视频/音频线程
     *
     * Live555 内部线程调用（rtspDataCallBack 内），原子标记防重复拉起；
     * 对应 VmsTools checkTutkInitTimer 的数据到达检测。
     */
    void launchRecvThreadsIfNeeded(const char* firstType, const char* codeName);

    /** Live555 收流回调（Live555 内部线程，只做入队） */
    void rtspDataCallBack(unsigned char* data, int size, const char* type, const char* codeName, int index, char* rtspUrl, void* customObj);

    /** recv 视频线程主体：消费队列并解码渲染 */
    void recvVideoData(std::shared_ptr<SharedStopFlag> stopFlag);

    /** recv 音频线程主体：消费队列并播放 */
    void recvAudioData(int sampleRate, std::shared_ptr<SharedStopFlag> stopFlag);

    /** 解码一包视频数据并 emit frameReady（同步自 DecodeTask::decodeVideoData） */
    void decodeOnePacket(DecodeVideo& decoder, QByteArrayList& dataArray);

    /** 清空视频/音频缓存队列 */
    void clearCache();

    /** 本任务三个线程（init/recv视频/recv音频）是否仍在运行 */
    bool anyThreadRunning();

  private:
    static const int MAX_VIDEO_LIST_SIZE = 10; /**< 视频缓存上限（超限丢旧帧防积压） */
    static const int MAX_AUDIO_LIST_SIZE = 20; /**< 音频缓存上限 */

    /**
     * 全部存活任务登记（构造入列 / 析构注销，均在 GUI 线程）：
     * waitForAllThreadsExit 遍历它轮询线程退出状态。析构与等待同在
     * GUI 线程（阻塞期间 deleteLater 不会执行），理论上无并发修改，
     * 加锁仅作防御。
     */
    static QList<RtspLiveTask*> s_aliveTasks;
    static QMutex               s_aliveLock;

    QString m_ip;        /**< 设备 IP */
    QString m_userName;  /**< RTSP 用户名 */
    QString m_password;  /**< RTSP 密码 */
    int     m_sampleRate = 8000; /**< 音频采样率 */

    std::atomic<int> m_isStopTask{0};   /**< 停止标记（0 运行 1 停止） */
    std::atomic<int> m_isInitDone{0};   /**< init 完成标记（recv 线程循环条件） */
    std::atomic<int> m_dataReceived{0};    /**< 是否收到过流数据（1=已收到，供流结束收尾区分失败/中断） */
    std::atomic<bool> m_recvLaunched{false}; /**< recv 线程是否已拉起（防重复拉起） */

    QFuture<int>                  m_initFuture;       /**< init 线程 future */
    QFutureWatcher<int>           m_initWatcher;       /**< init 完成监听（业务回调 + 自毁触发） */
    QFuture<void>                 m_recvVideoFuture;   /**< recv 视频线程 future */
    QFuture<void>                 m_recvAudioFuture;   /**< recv 音频线程 future */
    QFutureWatcher<void>          m_recvVideoWatcher;  /**< recv 视频线程退出监听（仅用于自毁等待） */
    QFutureWatcher<void>          m_recvAudioWatcher;  /**< recv 音频线程退出监听（仅用于自毁等待） */
    std::shared_ptr<SharedStopFlag> m_initStopFlag;    /**< init 线程停止标记 */
    std::shared_ptr<SharedStopFlag> m_recvStopFlag;    /**< recv 线程停止标记 */
    std::promise<bool>            m_quitPromise;  /**< 通知 startOpenUrl 解除阻塞 */
    bool                          m_quitIssued = false; /**< quitPromise 是否已 set_value */
    bool                          m_deletePending = false; /**< stopAndDeleteLater 是否已调用（防重入） */

    /**
     * recv 线程拉起/自毁检测互斥锁：launchRecvThreadsIfNeeded（Live555 线程）
     * 写 recv future 与 stopAndDeleteLater/tryDeleteAfterThreadsExit（GUI 线程）
     * 读同一批 future 的互斥，防止撕裂与漏挂 watcher。
     * 锁内只有 future 赋值/查询，无重活，不与队列锁嵌套。
     */
    QMutex                        m_recvLaunchLock;

    // 收流缓存队列（rtspDataCallBack 生产 → recv 线程消费）
    QMutex               m_rawVideoLock;           /**< 视频队列锁 */
    QList<QByteArrayList> m_videoList;             /**< 视频帧队列：[codeName, 帧数据] */
    QMutex               m_rawAudioLock;           /**< 音频队列锁 */
    QList<QByteArrayList> m_audioList;             /**< 音频帧队列：[codeName, 音频数据] */
};

#endif // RTSDLIVETASK_H
