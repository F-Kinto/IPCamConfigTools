/*********************************************************************
File : DeviceUpgradeTask.cpp
Module : Public
Authors: QA
date : 2026/10/22 16:00
Ver : 1.0.0
History:
QA 2026/10/22 1.0.0 build this module
********************************************************************/
#pragma execution_character_set("utf-8")

#include "DeviceUpgradeTask.h"
#include "AsynRequest.h"
#include "ConfigureManager.h"
#include "RequestMessageData.h"
#include "WifiBroadcast.h"
#include "GlobalEnum.h"

#include <QFile>
#include <QFileInfo>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QHttpMultiPart>
#include <QHttpPart>
#include <QTimer>
#include <QDebug>

namespace {
// 上传超时：5 分钟（固件包较大，需足够时间）
const int kUploadTimeoutMs = 5 * 60 * 1000;
// 广播轮询超时：3 分钟（对齐 DeviceUpgrade.cpp 694 行 3*60）
const int kPollTimeoutSec = 3 * 60;
// 广播发送间隔
const int kBroadcastIntervalMs = 1000;

/**
 * @brief 把结构体里的 char 数组字段转成 QString（遇 \0 截断）
 */
QString toStringField(const char* field, int maxLen)
{
    return QString::fromUtf8(QByteArray(field, maxLen).constData());
}

/**
 * @brief 从固件文件名提取版本号回退值
 *
 * 规则：取最后一个下划线到文件后缀之间的字符串。
 * 例：B14_IronMan_05.03.32.36.img → 05.03.32.36
 *     app_1.0.2.bin → 1.0.2
 * 提取失败返回空串。
 */
QString extractVersionFromFileName(const QString& baseName)
{
    const int lastUnderscore = baseName.lastIndexOf(QLatin1Char('_'));
    if (lastUnderscore < 0)
        return QString();

    const int lastDot = baseName.lastIndexOf(QLatin1Char('.'));
    // lastDot 必须在 lastUnderscore 之后，且中间至少一个字符
    if (lastDot <= lastUnderscore + 1)
        return QString();

    return baseName.mid(lastUnderscore + 1, lastDot - lastUnderscore - 1);
}
} // namespace

DeviceUpgradeTask* DeviceUpgradeTask::m_instance = nullptr;

DeviceUpgradeTask* DeviceUpgradeTask::instance()
{
    if (!m_instance)
        m_instance = new DeviceUpgradeTask();
    return m_instance;
}

QString DeviceUpgradeTask::extractFileVersion(const QString& fileName)
{
    // 取纯文件名（去掉路径）
    const QString baseName = fileName.mid(qMax(fileName.lastIndexOf(QLatin1Char('/')),
                                                fileName.lastIndexOf(QLatin1Char('\\'))) + 1);
    return ::extractVersionFromFileName(baseName);
}

int DeviceUpgradeTask::compareVersions(const QString& v1, const QString& v2)
{
    if (v1.isEmpty() || v2.isEmpty())
        return 0;

    const QStringList seg1 = v1.split(QLatin1Char('.'));
    const QStringList seg2 = v2.split(QLatin1Char('.'));
    const int maxSeg = qMax(seg1.size(), seg2.size());

    for (int i = 0; i < maxSeg; ++i) {
        bool ok1 = false, ok2 = false;
        const int n1 = (i < seg1.size()) ? seg1[i].toInt(&ok1) : 0;
        const int n2 = (i < seg2.size()) ? seg2[i].toInt(&ok2) : 0;
        if (!ok1 || !ok2)
            return 0; // 无法解析的段视为相等
        if (n1 != n2)
            return (n1 > n2) ? 1 : -1;
    }
    return 0;
}

DeviceUpgradeTask::DeviceUpgradeTask(QObject* parent)
    : QObject(parent)
    , m_broadcast(nullptr)
    , m_pollTimer(nullptr)
    , m_pollSeconds(0)
    , m_running(false)
{
}

DeviceUpgradeTask::~DeviceUpgradeTask()
{
    stopBroadcastPoll();
    // 清理上传 runner
    for (auto& runner : m_uploadRunners) {
        if (runner.request) {
            runner.request->disconnect(this);
            runner.request->quitRequest();
            runner.request->deleteLater();
            runner.request = nullptr;
        }
    }
    m_uploadRunners.clear();
    if (m_broadcast) {
        delete m_broadcast;
        m_broadcast = nullptr;
    }
    m_instance = nullptr;
}

bool DeviceUpgradeTask::running() const
{
    return m_running;
}

QString DeviceUpgradeTask::lastUpgradeDir() const
{
    return m_lastDir;
}

bool DeviceUpgradeTask::startUpgrade(const QString& filePath, const QVariantList& devices)
{
    if (m_running) {
        qWarning() << "DeviceUpgradeTask: upgrade already in progress";
        return false;
    }
    if (filePath.isEmpty() || devices.isEmpty()) {
        qWarning() << "DeviceUpgradeTask: invalid parameters";
        return false;
    }

    // 读取升级文件
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly)) {
        qWarning() << "DeviceUpgradeTask: cannot open file:" << filePath;
        return false;
    }
    QByteArray fileBuf = file.readAll();
    file.close();
    if (fileBuf.isEmpty()) {
        qWarning() << "DeviceUpgradeTask: file is empty:" << filePath;
        return false;
    }
    const QString fileName = QFileInfo(filePath).fileName();
    m_lastDir = QFileInfo(filePath).absolutePath();
    m_fileBaseName = fileName;

    qInfo().noquote() << QString("Firmware upgrade start: file=%1, size=%2, devices=%3")
                             .arg(fileName)
                             .arg(fileBuf.size())
                             .arg(devices.size());

    // 初始化状态
    m_entries.clear();
    for (auto& runner : m_uploadRunners) {
        if (runner.request) {
            runner.request->disconnect(this);
            runner.request->quitRequest();
            runner.request->deleteLater();
            runner.request = nullptr;
        }
    }
    m_uploadRunners.clear();
    m_pollSeconds = 0;
    m_running = true;

    // 构建升级 URL 模板
    const QString urlTemplate = ConfigureManager::getDeviceUrl(
        EnumNameSpace::DeviceQuestUrl::eUpdateFileToDeviceWifi);

    // 为每台设备创建上传 runner
    for (int i = 0; i < devices.size(); ++i) {
        const QVariantMap dev = devices[i].toMap();
        const QString key = dev.value("uid").toString();
        const QString ip  = dev.value("ip").toString();
        const QString mac = dev.value("mac").toString();
        const QString ver = dev.value("currentVersion").toString();

        if (key.isEmpty() || ip.isEmpty()) {
            qWarning() << "DeviceUpgradeTask: skip invalid device:" << key << ip;
            continue;
        }

        // 记录升级状态
        UpgradeEntry entry;
        entry.key = key;
        entry.ip = ip;
        entry.mac = mac;
        entry.oldVersion = ver;
        m_entries[key] = entry;

        // 每设备一条 AsynRequest（并行）
        UploadRunner runner;
        runner.deviceKey = key;
        runner.request = new AsynRequest(this);

        // 响应路由：customMessage = "upgrade_<deviceKey>"
        const QString customMsg = "upgrade_" + key;
        connect(runner.request, &AsynRequest::signalResponseRequest,
                this, [this, key](const RequestMessageData& data) {
                    const bool ok = data.responseType() == RequestMessageData::ResponseType::eSuccess;
                    slotUploadResponse(key, ok, data.responseData(),
                                       QString::fromUtf8(data.errorMessage()));
        });

        // 构造 multipart 请求
        const QString url = urlTemplate.arg(ip);
        QNetworkRequest netRequest;
        netRequest.setUrl(url);

        QHttpMultiPart* multiPart = new QHttpMultiPart(QHttpMultiPart::FormDataType);
        QHttpPart filePart;
        filePart.setHeader(QNetworkRequest::ContentTypeHeader,
                           QVariant("application/octet-stream"));
        filePart.setHeader(QNetworkRequest::ContentDispositionHeader,
                           QString("form-data; name=\"file\"; filename=\"%1\"").arg(fileName));
        filePart.setBody(fileBuf);
        multiPart->append(filePart);

        RequestMessageData questData;
        questData.reset();
        questData.setRequest(netRequest);
        questData.setRequestType(RequestMessageData::RequestType::eHttpMultiPartType);
        questData.setRequestIntervel(kUploadTimeoutMs);
        questData.setHttpMultPart(multiPart);
        questData.setCustomMessage(customMsg);

        runner.request->startRequest(questData);
        m_uploadRunners.append(runner);

        emit deviceProgress(key, eUploading);
        qInfo().noquote() << QString("Firmware upload: device=%1, ip=%2").arg(key).arg(ip);
    }

    if (m_entries.isEmpty()) {
        m_running = false;
        qWarning() << "DeviceUpgradeTask: no valid devices to upgrade";
        return false;
    }

    return true;
}

void DeviceUpgradeTask::slotUploadResponse(const QString& deviceKey, bool success,
                                            const QByteArray& responseData,
                                            const QString& errorMessage)
{
    Q_UNUSED(responseData);

    // 迟到回调守卫：checkAllDone 已清理过就不再处理
    if (!m_running)
        return;

    auto it = m_entries.find(deviceKey);
    if (it == m_entries.end())
        return;

    // 重复回调守卫：已收到过该设备的上传结果就忽略
    if (it->uploaded)
        return;

    it->uploaded = true;
    it->uploadOk = success;

    if (success) {
        qInfo().noquote() << QString("Firmware upload OK: device=%1").arg(deviceKey);
        emit deviceProgress(deviceKey, eUpgraded);
    } else {
        qWarning().noquote() << QString("Firmware upload FAIL: device=%1, err=%2").arg(deviceKey).arg(errorMessage);
        it->done = true;
        emit deviceProgress(deviceKey, eFailed);
        emit deviceResult(deviceKey, false, QString());
        checkAllDone();
        return;
    }

    // 所有设备上传完成（无论成败）后启动广播轮询
    bool allUploaded = true;
    for (auto& e : m_entries) {
        if (!e.uploaded) {
            allUploaded = false;
            break;
        }
    }
    if (allUploaded && !m_pollTimer) {
        // 只有上传成功的设备才需要轮询
        bool hasPending = false;
        for (auto& e : m_entries) {
            if (e.uploadOk && !e.done) {
                hasPending = true;
                break;
            }
        }
        if (hasPending) {
            startBroadcastPoll();
        } else {
            checkAllDone();
        }
    }
}

void DeviceUpgradeTask::startBroadcastPoll()
{
    qInfo() << "Firmware upgrade: start broadcast poll, waiting for device reboot";

    // 懒创建 WifiBroadcast（与 DeviceScanner 类似）
    if (!m_broadcast) {
        m_broadcast = new WifiBroadcast();
        connect(m_broadcast, &WifiBroadcast::signalSendOneIp,
                this, &DeviceUpgradeTask::slotHandleBroadcastReply, Qt::QueuedConnection);
        connect(this, &DeviceUpgradeTask::signalSendBroadcast,
                m_broadcast, &WifiBroadcast::slotSendBroadcast, Qt::QueuedConnection);
    }

    // 启动 1 秒轮询定时器
    m_pollTimer = new QTimer(this);
    m_pollTimer->setInterval(kBroadcastIntervalMs);
    connect(m_pollTimer, &QTimer::timeout, this, &DeviceUpgradeTask::slotPollTimeout);
    m_pollSeconds = 0;

    // 开始广播
    emit signalSendBroadcast(true, kBroadcastIntervalMs);
    m_pollTimer->start();
}

void DeviceUpgradeTask::stopBroadcastPoll()
{
    if (m_pollTimer) {
        m_pollTimer->stop();
        delete m_pollTimer;
        m_pollTimer = nullptr;
    }
    if (m_broadcast) {
        emit signalSendBroadcast(false, kBroadcastIntervalMs);
    }
}

void DeviceUpgradeTask::slotHandleBroadcastReply(const QByteArray& data, const QString& ip)
{
    Q_UNUSED(ip);

    if (!m_running)
        return;

    // 解析广播回包，提取 MAC 与固件版本
    BroadcastIPCAMINFO info;
    const int copySize = qMin(data.size(), static_cast<int>(sizeof(BroadcastIPCAMINFO)));
    memcpy(&info, data.constData(), copySize);

    const QString mac = toStringField(info.szMacAddr, sizeof(info.szMacAddr));
    const QString newVer = toStringField(info.firmware_ver, sizeof(info.firmware_ver));

    if (mac.isEmpty() && newVer.isEmpty())
        return;

    // 遍历正在升级的设备，匹配 MAC 地址
    for (auto it = m_entries.begin(); it != m_entries.end(); ++it) {
        if (it->done || !it->uploadOk)
            continue;

        // 匹配 MAC（不区分大小写）
        if (!it->mac.isEmpty() && it->mac.compare(mac, Qt::CaseInsensitive) != 0)
            continue;

        // 版本变化 = 升级成功
        if (!newVer.isEmpty() && newVer != it->oldVersion) {
            it->done = true;
            it->newVersion = newVer;
            qInfo().noquote() << QString("Firmware upgrade SUCCESS: device=%1, old=%2, new=%3")
                                     .arg(it->key).arg(it->oldVersion).arg(newVer);
            emit deviceProgress(it->key, eSuccess);
            emit deviceResult(it->key, true, it->newVersion);
            checkAllDone();
            return; // 一次回包只处理一台
        }
    }
}

void DeviceUpgradeTask::slotPollTimeout()
{
    if (!m_running)
        return;

    m_pollSeconds++;

    if (m_pollSeconds >= kPollTimeoutSec) {
        // 超时：未判定成功的设备标记失败
        qWarning() << "Firmware upgrade: poll timeout, marking remaining as failed";
        const QString fallbackVer = extractVersionFromFileName(m_fileBaseName);
        for (auto it = m_entries.begin(); it != m_entries.end(); ++it) {
            if (!it->done) {
                it->done = true;
                emit deviceProgress(it->key, eFailed);
                emit deviceResult(it->key, false, fallbackVer);
            }
        }
        stopBroadcastPoll();
        checkAllDone();
    }
}

void DeviceUpgradeTask::checkAllDone()
{
    // 重入守卫
    if (!m_running)
        return;

    bool allDone = true;
    for (auto& e : m_entries) {
        if (!e.done) {
            allDone = false;
            break;
        }
    }

    if (allDone) {
        stopBroadcastPoll();
        m_running = false;

        // 清理上传 runner：断开信号 → quitRequest → deleteLater
        //（不用 delete：slotsTimeOut 不中止 m_currentReply，迟到回包
        //  的 finished lambda 可能访问已 delete 的 m_timer → 崩溃）
        for (auto& runner : m_uploadRunners) {
            if (runner.request) {
                runner.request->disconnect(this);
                runner.request->quitRequest();
                runner.request->deleteLater();
                runner.request = nullptr;
            }
        }
        m_uploadRunners.clear();

        qInfo() << "Firmware upgrade: all finished";
        emit allFinished();
    }
}
