#pragma execution_character_set("utf-8")
#include "DeviceManager.h"
#include "ConfigureManager.h"
#include "SynRequestBlock.h"
#include "RequestMessageData.h"
#include "RtspLiveTask.h"
#include <QDebug>
#include <QPointer>
#include <QtConcurrent>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QSslConfiguration>
#include <QSslSocket>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTextDocumentFragment>

DeviceManager* DeviceManager::m_instance = nullptr;

DeviceManager* DeviceManager::instance()
{
    if (!m_instance)
        m_instance = new DeviceManager();
    return m_instance;
}

DeviceManager::DeviceManager(QObject* parent)
    : QObject(parent), m_hasCurrent(false)
{
}

DeviceManager::~DeviceManager()
{
    m_instance = nullptr;
}

int DeviceManager::checkedCount() const
{
    return m_checkedDevices.size();
}

QStringList DeviceManager::checkedUids() const
{
    return m_checkedDevices.keys();
}

QString DeviceManager::currentUid() const
{
    return m_hasCurrent ? m_currentDevice.uid : QString();
}

QVariantMap DeviceManager::currentDeviceMap() const
{
    return m_hasCurrent ? m_currentDevice.toVariantMap() : QVariantMap();
}

void DeviceManager::setCheckedDevice(const QVariantMap& device)
{
    const DeviceInfo info = DeviceInfo::fromVariantMap(device);
    if (!info.isValid())
        return;

    const QString key = keyOf(device);
    if (key.isEmpty())
        return;

    // uid 为空时用实际 key 兜底，保证后续按 uid 取值与 key 一致
    DeviceInfo stored = info;
    if (stored.uid.isEmpty())
        stored.uid = key;

    const bool isNew = !m_checkedDevices.contains(key);
    m_checkedDevices.insert(key, stored);

    if (isNew)
        emit checkedDevicesChanged();
}

void DeviceManager::removeCheckedDevice(const QString& uid)
{
    if (m_checkedDevices.remove(uid) == 0)
        return;

    emit checkedDevicesChanged();
}

void DeviceManager::clearCheckedDevices()
{
    if (m_checkedDevices.isEmpty())
        return;

    m_checkedDevices.clear();
    emit checkedDevicesChanged();
}

bool DeviceManager::isChecked(const QString& uid) const
{
    return m_checkedDevices.contains(uid);
}

QVariantMap DeviceManager::checkedDevice(const QString& uid) const
{
    const auto it = m_checkedDevices.constFind(uid);
    if (it == m_checkedDevices.constEnd())
        return QVariantMap();

    return it.value().toVariantMap();
}

QVariantList DeviceManager::checkedDevices() const
{
    QVariantList list;
    for (auto it = m_checkedDevices.constBegin(); it != m_checkedDevices.constEnd(); ++it)
        list << it.value().toVariantMap();

    return list;
}

void DeviceManager::syncCheckedDevices(const QVariantList& devices)
{
    QMap<QString, DeviceInfo> newMap;
    for (const QVariant& item : devices) {
        const QVariantMap map  = item.toMap();
        const QString     key  = keyOf(map);
        if (key.isEmpty())
            continue;

        DeviceInfo info = DeviceInfo::fromVariantMap(map);
        if (!info.isValid())
            continue;

        if (info.uid.isEmpty())
            info.uid = key;

        newMap.insert(key, info);
    }

    // 内容没变就不抛信号，避免界面无谓刷新
    if (newMap.keys() == m_checkedDevices.keys()) {
        bool same = true;
        for (auto it = newMap.constBegin(); it != newMap.constEnd(); ++it) {
            if (it.value().toVariantMap() != m_checkedDevices.value(it.key()).toVariantMap()) {
                same = false;
                break;
            }
        }
        if (same)
            return;
    }

    m_checkedDevices = newMap;
    emit checkedDevicesChanged();
}

void DeviceManager::setCurrentDevice(const QVariantMap& device)
{
    const DeviceInfo info = DeviceInfo::fromVariantMap(device);
    if (!info.isValid()) {
        clearCurrentDevice();
        return;
    }

    const QString key = keyOf(device);
    DeviceInfo    stored = info;
    if (stored.uid.isEmpty())
        stored.uid = key;

    // 同一台设备重复设置不抛信号
    if (m_hasCurrent && m_currentDevice.uid == stored.uid && m_currentDevice.toVariantMap() == stored.toVariantMap())
        return;

    m_currentDevice = stored;
    m_hasCurrent    = true;
    emit currentDeviceChanged();
}

void DeviceManager::clearCurrentDevice()
{
    if (!m_hasCurrent)
        return;

    m_currentDevice = DeviceInfo();
    m_hasCurrent    = false;
    emit currentDeviceChanged();
}

QString DeviceManager::keyOf(const QVariantMap& device) const
{
    QString key = device.value("uid").toString();
    if (key.isEmpty())
        key = device.value("mac").toString();
    if (key.isEmpty())
        key = device.value("ip").toString();

    return key;
}

void DeviceManager::addLiveDevice(const QVariantMap& device)
{
    const DeviceInfo info = DeviceInfo::fromVariantMap(device);
    // 直播必须依赖 ip 拼装 RTSP 地址，无 ip 的设备不加入
    if (!info.isValid() || info.ip.isEmpty())
        return;

    const QString key = keyOf(device);
    if (key.isEmpty())
        return;

    DeviceInfo stored = info;
    if (stored.uid.isEmpty())
        stored.uid = key;

    // 已在直播中的设备只更新信息，保持原位置（避免重复窗口）
    for (int i = 0; i < m_liveDevices.size(); ++i) {
        if (m_liveDevices.at(i).uid == stored.uid) {
            m_liveDevices[i] = stored;
            emit liveDevicesChanged();
            return;
        }
    }

    m_liveDevices.append(stored);
    emit liveDevicesChanged();
}

void DeviceManager::removeLiveDevice(const QString& uid)
{
    for (int i = 0; i < m_liveDevices.size(); ++i) {
        if (m_liveDevices.at(i).uid == uid) {
            m_liveDevices.removeAt(i);
            emit liveDevicesChanged();
            return;
        }
    }
}

void DeviceManager::clearLiveDevices()
{
    if (m_liveDevices.isEmpty())
        return;

    m_liveDevices.clear();
    emit liveDevicesChanged();
}

bool DeviceManager::waitForLiveStreamsExit(int timeoutMs)
{
    // 阻塞轮询所有存活拉流任务的 init + recv 视频/音频线程退出。
    // 仅供退出程序前 QML 同步调用，无任务在跑时立即返回
    return RtspLiveTask::waitForAllThreadsExit(timeoutMs);
}

QVariantList DeviceManager::liveDevicesMap() const
{
    QVariantList list;
    for (const DeviceInfo& info : m_liveDevices)
        list << info.toVariantMap();

    return list;
}

int DeviceManager::liveCount() const
{
    return m_liveDevices.size();
}

void DeviceManager::fetchRtspCredential(const QVariantMap& device)
{
    const QString key = keyOf(device);
    if (key.isEmpty())
        return;

    // ip 为空无法请求 HTTP
    if (device.value("ip").toString().isEmpty())
        return;

    // 去重：同一设备正在请求中就不再发
    if (m_pendingRtsp.contains(key))
        return;
    m_pendingRtsp.insert(key);

    QPointer<DeviceManager> self(this);
    QtConcurrent::run([self, key, device]() {
        const QString ip = device.value("ip").toString();

        // 构造请求（SSL 配置同 VmsTools_v2）
        QNetworkRequest requestObj;
        QSslConfiguration conf = requestObj.sslConfiguration();
        conf.setPeerVerifyMode(QSslSocket::VerifyNone);
        conf.setProtocol(QSsl::TlsV1SslV3);
        requestObj.setSslConfiguration(conf);
        requestObj.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

        QString url = ConfigureManager::getDeviceUrl(
            EnumNameSpace::DeviceQuestUrl::eGetRtspInfoUrl);
        if (url.isEmpty()) {
            // URL 模板为空，直接发信号（凭据为空，调用方按默认值处理）
            if (self) {
                QMetaObject::invokeMethod(self, [self, key, device]() {
                    self->m_pendingRtsp.remove(key);
                    emit self->rtspCredentialFetched(device);
                }, Qt::QueuedConnection);
            }
            return;
        }
        url = url.arg(ip);
        requestObj.setUrl(url);

        // 重试一次（同 VmsTools_v2：两次都空才算失败）
        QByteArray recvData;
        bool requestOk = false;
        for (int attempt = 0; attempt <= 1; ++attempt) {
            SynRequestBlock questObj;
            RequestMessageData questData;
            questData.reset();
            questData.setRequest(requestObj);
            questData.setRequestType(RequestMessageData::RequestType::eGetType);
            questData.setRequestIntervel(5 * 1000);
            questObj.startRequest(questData);

            recvData = questObj.recvData();
            qInfo() << "LOG::fetchRtspCredential request attempt:" << attempt
                    << "url:" << url;
            if (!recvData.isEmpty()) {
                requestOk = true;
                break;
            }
        }

        // 合并凭据字段
        QVariantMap result = device;
        if (requestOk) {
            // 设备可能返回 HTML 包裹的 JSON，先剥离 HTML 标签
            QJsonObject resultObj =
                QJsonDocument::fromJson(
                    QTextDocumentFragment::fromHtml(QString::fromUtf8(recvData))
                        .toPlainText()
                        .toUtf8())
                    .object();
            result["rtspUserName"] = resultObj.value("user").toString();
            result["rtspPassword"] = resultObj.value("key").toString();
            qInfo() << "LOG::fetchRtspCredential parse, ip:" << ip
                    << "user:" << result.value("rtspUserName").toString()
                    << "keyLen:" << result.value("rtspPassword").toString();
        } else {
            qWarning() << "LOG::fetchRtspCredential http failed after retry, ip:" << ip;
        }
        // 失败时 rtspUserName/rtspPassword 保持原 map 里的值（通常为空串）

        if (self) {
            QMetaObject::invokeMethod(self, [self, key, result]() {
                self->m_pendingRtsp.remove(key);
                // 拿到用户名才写缓存（密码允许为空），供后续播放直接读取
                const QString user = result.value("rtspUserName").toString();
                if (!user.isEmpty()) {
                    RtspCredential cred;
                    cred.userName = user;
                    cred.password = result.value("rtspPassword").toString();
                    self->m_rtspCredentials.insert(key, cred);
                }
                emit self->rtspCredentialFetched(result);
            }, Qt::QueuedConnection);
        }
    });
}

QVariantMap DeviceManager::mergeRtspCredential(const QVariantMap& device) const
{
    QVariantMap result = device;
    const auto it = m_rtspCredentials.constFind(keyOf(device));
    if (it != m_rtspCredentials.constEnd()) {
        result["rtspUserName"] = it.value().userName;
        result["rtspPassword"] = it.value().password;
    }

    return result;
}
