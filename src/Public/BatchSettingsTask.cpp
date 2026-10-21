#include "BatchSettingsTask.h"
#include "AsynRequest.h"
#include "ConfigureManager.h"
#include "RequestMessageData.h"
#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSslConfiguration>
#include <QSslSocket>
#include <QTimer>
#include <QUrl>

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

// 统一下发接口（%1 = 设备 IP）
constexpr char kUrlTemplate[] = "http://%1/goform/ipcParams";

// 面板 key → ipcParams 指令名（与 OtherSettingsDialog.qml 的 protocolMaps[key].cmd 对应，
// protocolMaps 调整面板协议名时同步维护此表）
// clock 的协议名为 setTimeAttr，get/set 指令按 get/set+首字母大写推导，固件确认后如有出入直接改这里
struct PanelCmdSpec {
    const char* key;    // 界面面板 key
    const char* cmd;    // 协议命令名（other_settings.json 顶层条目键）
    const char* getCmd; // GET 指令（读设备当前配置）
    const char* setCmd; // POST 指令（设置）
};
const PanelCmdSpec kPanelCmds[] = {
    {"network",       "netInfo",      "getNetInfo",      "setNetInfo"},
    {"gb28181",       "gb28181",     "getGb28181Attr",     "setGb28181Attr"},
    {"videoCapture",  "videoCapture", "getImageAttr", "setImageAttr"},
    {"timeTitle",     "osd",         "getOSDAttr",         "setOSDAttr"},
    {"videoEncode",   "videoEncode",  "getVideoAttr",  "setVideoAttr"},
    {"audioEncode",   "audioEncode",  "getAudioAttr",  "setAudioAttr"},
    {"audioReconfig", "audioReconfig", "getAudioVolumeAttr", "setAudioVolumeAttr"},
    {"motionDetect",  "motionDetect", "getMotionDetectAttr", "setMotionDetectAttr"},
    {"audioDetect",   "audioDetect",  "getAudioDetectAttr",  "setAudioDetectAttr"},
    {"account",       "account",     "getUserPwd",     "setUserPwd"},
    {"clock",         "setTimeAttr", "getTimeAttr", "setTimeAttr"},
    {"maintenance",   "maintenance", "getAutoRebootAttr", "setAutoRebootAttr"},
};

const PanelCmdSpec* panelCmdSpec(const QString& key)
{
    for (const PanelCmdSpec& s : kPanelCmds) {
        if (key == QLatin1String(s.key))
            return &s;
    }
    return nullptr;
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

    // 请求体数据源：other_settings.json——面板保存时已按协议格式写入
    // （{协议名: {"switch", "payload"}}），下发的 payload 与文件里的一模一样；
    // 文件不存在/内容损坏时全部按 GET（读设备当前配置）处理
    const QJsonObject fileRoot = QJsonDocument::fromJson(
        ConfigureManager::instance()->loadOtherSettingsValues().toUtf8()).object();

    for (const QVariant& devVar : devices) {
        const QVariantMap dev = devVar.toMap();
        const QString key = dev.value("uid").toString();
        const QString ip = dev.value("ip").toString();
        if (key.isEmpty() || ip.isEmpty())
            continue;

        Runner runner;
        runner.key = key;
        for (const QVariant& itemVar : items) {
            const QVariantMap item = itemVar.toMap();
            ItemSpec spec;
            spec.key = item.value("key").toString();
            spec.name = item.value("name").toString();
            spec.action = item.value("action").toString();
            spec.restartAfter = isRestartKey(spec.key);

            const PanelCmdSpec* cs = panelCmdSpec(spec.key);
            if (!cs)
                continue; // 无指令映射的面板（language 等）：不下发

            spec.urlTemplate = QLatin1String(kUrlTemplate);
            spec.url = spec.urlTemplate.arg(ip); // %1 = 设备 IP

            const QJsonObject entry = fileRoot.value(QLatin1String(cs->cmd)).toObject();
            QJsonObject body;
            if (!entry.isEmpty()) {
                // 面板保存过：POST，payload 为文件里该面板的 payload 对象原样
                body.insert("cmd", QLatin1String(cs->setCmd));
                body.insert("payload", entry.value("payload"));
                // 网络设置成功后设备切到保存的 IP：该设备后续设置项的 URL 重填为新 IP
                if (spec.key == QLatin1String("network"))
                    spec.newIp = entry.value("payload").toObject().value("ip").toString();
            } else {
                // 面板没保存过：GET 读设备当前配置（同样带 {"cmd": "getXxx"} 包体）
                body.insert("cmd", QLatin1String(cs->getCmd));
                spec.isGet = true;
            }
            spec.body = QJsonDocument(body).toJson(QJsonDocument::Compact);
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

            const ItemSpec& spec = runner->items[runner->cur];
            // 响应日志：设备 uid、指令名、HTTP 返回结果（失败时打印错误信息）
            {
                const QString cmd = QJsonDocument::fromJson(spec.body).object().value("cmd").toString();
                const QString result = data.responseType() == RequestMessageData::ResponseType::eSuccess
                        ? QString::fromUtf8(data.responseData())
                        : QString::fromUtf8(data.errorMessage());
                qDebug().noquote() << QString("[%1 - 响应] cmd=%2 结果=%3")
                                          .arg(deviceKey, cmd, result);
            }

            if (data.responseType() == RequestMessageData::ResponseType::eSuccess) {
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
                    qDebug() << "twice failed, skip" << deviceKey << itemKey;
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
    // ipcParams 协议：GET（读设备当前配置）也带 {"cmd": "getXxx"} JSON 包体，
    // POST 带 {"cmd": "setXxx", "payload": {...}}（payload 为 other_settings.json 里的 payload 原样）
    data.setRequestType(spec.isGet ? RequestMessageData::RequestType::eGetType : RequestMessageData::RequestType::ePostType);
    data.setSendData(spec.body);
    data.setRequestIntervel(kRequestIntervalMs);
    data.setCustomMessage(QString("%1|%2").arg(runner.key).arg(spec.key));

    // 发送日志：设备 uid/IP、指令名、完整 JSON 包体
    {
        const QString cmd = QJsonDocument::fromJson(spec.body).object().value("cmd").toString();
        qDebug().noquote() << QString("[设备 - %1 - %2] >>> 发送指令为 %3  发送数据为 json=%4")
                                  .arg(runner.key, QUrl(spec.url).host(), cmd, QString::fromUtf8(spec.body));
    }
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
