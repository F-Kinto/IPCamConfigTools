#include "BatchSettingsTask.h"
#include "AsynRequest.h"
#include "RequestMessageData.h"
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSslConfiguration>
#include <QSslSocket>
#include <QTimer>

namespace {
// 单项请求超时：5 秒（与 DeviceApiClient 缺省口径一致）
constexpr int kRequestIntervalMs = 5 * 1000;
// 失败重试间隔：2 秒
constexpr int kRetryDelayMs = 2 * 1000;
// 单项最多尝试次数（首发 + 重试一次）
constexpr int kMaxAttempts = 2;
// 该项成功后设备重启进程生效的等待间隔：25 秒
constexpr int kRestartWaitMs = 25 * 1000;

// 这些设置项成功后设备需重启进程生效：成功后等 25 秒再发下一项
bool isRestartKey(const QString& key)
{
    return key == QLatin1String("network") || key == QLatin1String("videoEncode") || key == QLatin1String("audioEncode");
}
} // namespace

BatchSettingsTask* BatchSettingsTask::instance()
{
    static BatchSettingsTask s_instance;
    return &s_instance;
}

BatchSettingsTask::BatchSettingsTask(QObject* parent) : QObject(parent) {}

bool BatchSettingsTask::running() const
{
    return !m_runners.isEmpty();
}

void BatchSettingsTask::start(const QVariantList& devices, const QVariantList& items)
{
    if (running())
        return;

    m_finishedCount = 0;
    for (const QVariant& devVar : devices) {
        const QVariantMap dev = devVar.toMap();
        const QString key = dev.value("uid").toString();
        const QString ip = dev.value("ip").toString();
        if (key.isEmpty() || ip.isEmpty())
            continue;

        Runner runner;
        runner.key = key;
        // 设备 map 可携带专属 items（网络设置按设备分配空闲 IP时逐台定制），未携带则共用全局列表
        const QVariantList devItems = dev.contains("items") ? dev.value("items").toList() : items;
        for (const QVariant& itemVar : devItems) {
            const QVariantMap item = itemVar.toMap();
            ItemSpec spec;
            spec.key = item.value("key").toString();
            spec.name = item.value("name").toString();
            spec.action = item.value("action").toString();
            spec.urlTemplate = item.value("url").toString();
            spec.url = spec.urlTemplate.arg(ip); // %1 = 设备 IP
            spec.newIp = item.value("newIp").toString();
            spec.body = item.value("body").toString().toUtf8();
            spec.restartAfter = isRestartKey(spec.key);
            if (spec.key.isEmpty() || spec.url.isEmpty())
                continue;
            runner.items.append(spec);
        }
        if (runner.items.isEmpty())
            continue;

        runner.request = new AsynRequest(this);
        // 所有设备的响应统一回到这里，靠 customMessage 里的 "deviceKey|itemKey" 路由
        connect(runner.request, &AsynRequest::signalResponseRequest, this, [this](const RequestMessageData& data) {
            const QString custom = data.customMessage().toString();
            const int sep = custom.indexOf('|');
            if (sep <= 0)
                return;
            const QString deviceKey = custom.left(sep);
            const QString itemKey = custom.mid(sep + 1);

            Runner* runner = findRunner(deviceKey);
            if (!runner || runner->cur >= runner->items.size() || runner->items[runner->cur].key != itemKey)
                return; // 过期/无关响应

            if (data.responseType() == RequestMessageData::ResponseType::eSuccess) {
                const ItemSpec& spec = runner->items[runner->cur];
                emit deviceProgress(deviceKey, spec.action, eSuccess);
                emit itemResult(deviceKey, itemKey, spec.name, true);
                // 网络设置成功：设备已切到 newIp，该设备后续设置项的 URL 重填为新 IP
                if (!spec.newIp.isEmpty()) {
                    for (int k = runner->cur + 1; k < runner->items.size(); ++k)
                        runner->items[k].url = runner->items[k].urlTemplate.arg(spec.newIp);
                }
                // 该项成功后设备重启进程生效：提示后等 25 秒再发下一项
                if (spec.restartAfter) {
                    emit deviceProgress(deviceKey, spec.action, eRestart);
                    runner->restartTimer->start();
                    return;
                }
                advance(*runner);
            } else {
                runner->attempt++;
                if (runner->attempt < kMaxAttempts) {
                    // 第 1 次失败：2 秒后重发当前项
                    emit deviceProgress(deviceKey, runner->items[runner->cur].action, eRetrying);
                    runner->retryTimer->start();
                } else {
                    // 两次尝试均失败：跳过，继续下一设置项
                    emit deviceProgress(deviceKey, runner->items[runner->cur].action, eSkipped);
                    emit itemResult(deviceKey, itemKey, runner->items[runner->cur].name, false);
                    advance(*runner);
                }
            }
        });

        runner.retryTimer = new QTimer(this);
        runner.retryTimer->setSingleShot(true);
        runner.retryTimer->setInterval(kRetryDelayMs);
        // 2 秒后重发当前项（捕获 key 字符串，每次现查 runner，避免悬垂引用）
        connect(runner.retryTimer, &QTimer::timeout, this, [this, key]() {
            Runner* runner = findRunner(key);
            if (runner)
                sendCurrent(*runner);
        });

        runner.restartTimer = new QTimer(this);
        runner.restartTimer->setSingleShot(true);
        runner.restartTimer->setInterval(kRestartWaitMs);
        // 该项成功后设备重启进程：25 秒后继续下一设置项（同样现查 runner 防悬垂）
        connect(runner.restartTimer, &QTimer::timeout, this, [this, key]() {
            Runner* runner = findRunner(key);
            if (runner)
                advance(*runner);
        });

        m_runners.append(runner);
    }

    if (m_runners.isEmpty()) {
        // 输入无有效设备/设置项：直接结束，避免界面遮罩悬空
        emit allFinished();
        return;
    }

    // 设备间并行：每设备立即发起第一项
    for (Runner& runner : m_runners)
        sendCurrent(runner);
}

BatchSettingsTask::Runner* BatchSettingsTask::findRunner(const QString& deviceKey)
{
    for (Runner& runner : m_runners) {
        if (runner.key == deviceKey)
            return &runner;
    }
    return nullptr;
}

void BatchSettingsTask::sendCurrent(Runner& runner)
{
    const ItemSpec& spec = runner.items[runner.cur];
    emit deviceProgress(runner.key, spec.action, eSetting);

    // SSL/请求头口径同 DeviceApiClient::makeRequest：
    // 关闭对端校验（设备自签名证书）+ TLS 兼容协议 + JSON Content-Type
    QNetworkRequest requestObj;
    QSslConfiguration conf = requestObj.sslConfiguration();
    conf.setPeerVerifyMode(QSslSocket::VerifyNone);
    conf.setProtocol(QSsl::TlsV1SslV3);
    requestObj.setSslConfiguration(conf);
    requestObj.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    requestObj.setUrl(spec.url);

    RequestMessageData data;
    data.reset();
    data.setRequest(requestObj);
    // 有请求体走 POST(JSON)，无请求体（面板没保存过参数）走 GET
    data.setRequestType(spec.body.isEmpty() ? RequestMessageData::RequestType::eGetType : RequestMessageData::RequestType::ePostType);
    if (!spec.body.isEmpty())
        data.setSendData(spec.body);
    data.setRequestIntervel(kRequestIntervalMs);
    data.setCustomMessage(QString("%1|%2").arg(runner.key).arg(spec.key));
    runner.request->startRequest(data);
}

void BatchSettingsTask::advance(Runner& runner)
{
    runner.attempt = 0;
    runner.cur++;
    if (runner.cur < runner.items.size()) {
        sendCurrent(runner);
        return;
    }

    // 该设备全部设置项完成
    runner.retryTimer->stop();
    emit deviceProgress(runner.key, QString(), eDeviceDone);
    m_finishedCount++;
    if (m_finishedCount >= m_runners.size())
        finishAll();
}

void BatchSettingsTask::finishAll()
{
    for (Runner& runner : m_runners) {
        if (runner.request) {
            runner.request->quitRequest();
            runner.request->deleteLater();
        }
        if (runner.retryTimer) {
            runner.retryTimer->stop();
            runner.retryTimer->deleteLater();
        }
        if (runner.restartTimer) {
            runner.restartTimer->stop();
            runner.restartTimer->deleteLater();
        }
    }
    m_runners.clear();
    m_finishedCount = 0;
    emit allFinished();
}
