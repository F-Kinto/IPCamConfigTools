/*********************************************************************
File : DeviceUpgradeTask.h
Module : Public
Authors: QA
date : 2026/10/22 16:00
Ver : 1.0.0
History:
QA 2026/10/22 1.0.0 build this module
********************************************************************/
#pragma once

#include "common_global.h"
#include <QObject>
#include <QMap>
#include <QString>
#include <QVariantList>
#include <QVector>

class AsynRequest;
class WifiBroadcast;
class QTimer;

/**
 * @class DeviceUpgradeTask
 * @brief WiFi 设备固件一键升级任务（仅 DEVICEWIFI 类型）。
 *
 * 流程（对齐 DeviceUpgrade.cpp 596 行 DEVICEWIFI 分支）：
 *   1. QML 传入升级文件路径 + 勾选设备列表，C++ 读取文件到内存；
 *   2. 为每台设备构造 HTTP multipart 请求，并行上传到
 *      http://<IP>/cgi-bin/upload_app.cgi?userid=admin&userkey=...；
 *   3. 上传完成后启动广播轮询（1 秒间隔），通过 WifiBroadcast 回包检测
 *      设备固件版本变化：版本改变 = 升级成功；
 *   4. 超过 3 分钟未变化 = 升级失败。
 *
 * 信号上报设备级进度与结果，QML 侧展示进度遮罩 + 结果详情。
 * 全部在主线程工作（AsynRequest/QNAM 主线程）。
 */
class COMMON_EXPORT DeviceUpgradeTask : public QObject {
    Q_OBJECT

  public:
    /**
     * @brief 单设备升级状态（deviceProgress 信号的 state 参数）
     */
    enum DeviceState {
        eUploading = 0, // 正在上传固件
        eUpgraded,      // 上传完成，等待设备重启生效
        eSuccess,       // 升级成功（广播检测到版本变化）
        eFailed,        // 升级失败（上传失败或超时）
    };

    static DeviceUpgradeTask* instance();

    /**
     * @brief 是否有升级任务执行中
     */
    Q_INVOKABLE bool running() const;

    /**
     * @brief 启动一键升级
     * @param filePath 升级文件完整路径
     * @param devices  设备列表 [{uid, ip, mac, currentVersion}]
     * @return true=启动成功；false=参数无效或任务已在执行
     */
    Q_INVOKABLE bool startUpgrade(const QString& filePath, const QVariantList& devices);

    /**
     * @brief 取上次升级的文件目录（供文件对话框定位）
     */
    Q_INVOKABLE QString lastUpgradeDir() const;

    /**
     * @brief 从固件文件名提取版本号
     *
     * 规则：取最后一个下划线到文件后缀之间的字符串。
     * 例：B14_IronMan_05.03.32.36.img → 05.03.32.36
     */
    Q_INVOKABLE static QString extractFileVersion(const QString& fileName);

    /**
     * @brief 比较两个点分版本号
     * @return >0 若 v1>v2；0 若相等；<0 若 v1<v2；无法解析时返回 0
     *
     * 按 '.' 分段逐段数值比较：05.03.32.36 vs 05.04.00.01
     */
    Q_INVOKABLE static int compareVersions(const QString& v1, const QString& v2);

  signals:
    /**
     * @brief 某设备升级进度变化
     * @param deviceKey 设备标识（uid）
     * @param state DeviceState 状态码
     */
    void deviceProgress(const QString& deviceKey, int state);

    /**
     * @brief 某设备升级完成（成功/失败）
     * @param deviceKey 设备标识
     * @param success true=升级成功
     * @param newVersion 升级后版本号（广播读到则取广播值，否则从文件名提取）
     */
    void deviceResult(const QString& deviceKey, bool success, const QString& newVersion);

    /**
     * @brief 全部设备升级完成
     */
    void allFinished();

    /**
     * @brief 触发/停止广播扫描（连接到 WifiBroadcast::slotSendBroadcast）
     */
    void signalSendBroadcast(const bool& isSend, const int& intervel);

  private slots:
    /**
     * @brief 处理广播回包（检测版本变化判定升级成功）
     */
    void slotHandleBroadcastReply(const QByteArray& data, const QString& ip);

    /**
     * @brief 广播轮询定时器：检测超时
     */
    void slotPollTimeout();

  private:
    explicit DeviceUpgradeTask(QObject* parent = nullptr);
    ~DeviceUpgradeTask();

    void slotUploadResponse(const QString& deviceKey, bool success,
                            const QByteArray& responseData, const QString& errorMessage);

    void startBroadcastPoll();
    void stopBroadcastPoll();
    void checkAllDone();

    // 单设备升级状态
    struct UpgradeEntry {
        QString key;          // uid
        QString ip;
        QString mac;
        QString oldVersion;   // 升级前版本
        QString newVersion;   // 升级后版本（广播检测或文件名提取）
        bool uploaded = false; // 文件上传是否完成
        bool uploadOk = false; // 上传是否成功
        bool done = false;     // 是否已判定终态
    };

    static DeviceUpgradeTask* m_instance;

    WifiBroadcast* m_broadcast;      // 广播扫描对象（轮询版本变化用）
    QTimer*        m_pollTimer;       // 1 秒轮询定时器
    int            m_pollSeconds;     // 已轮询秒数
    bool           m_running;

    QMap<QString, UpgradeEntry> m_entries; // 正在升级的设备：deviceKey -> entry

    // 每设备独立 AsynRequest（并行上传）
    struct UploadRunner {
        QString deviceKey;
        AsynRequest* request = nullptr;
    };
    QVector<UploadRunner> m_uploadRunners;

    QString m_lastDir;      // 上次打开升级文件的目录
    QString m_fileBaseName; // 当前升级文件名（不含路径，用于提取版本号回退值）
};
