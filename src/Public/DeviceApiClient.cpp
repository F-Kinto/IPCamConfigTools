#include "DeviceApiClient.h"
#include "AsynRequest.h"
#include "ConfigureManager.h"
#include "RequestMessageData.h"
#include <QNetworkRequest>
#include <QSslConfiguration>
#include <QSslSocket>
#include <QJsonDocument>

DeviceApiClient* DeviceApiClient::instance()
{
    static DeviceApiClient s_instance;
    return &s_instance;
}

DeviceApiClient::DeviceApiClient(QObject* parent) : QObject(parent), m_asynRequest(new AsynRequest(this))
{
    // 异步收包结果转发为 QML 友好信号：customMessage 匹配请求，success/响应体/错误信息一并带回
    connect(m_asynRequest, &AsynRequest::signalResponseRequest, this, [this](const RequestMessageData& data) {
        emit signalHttpResponse(data.customMessage().toString(),
                                data.responseType() == RequestMessageData::ResponseType::eSuccess,
                                data.responseData(),
                                QString::fromUtf8(data.errorMessage()));
    });
}

QNetworkRequest DeviceApiClient::makeRequest(const QString& url)
{
    // SSL/请求头口径同 DeviceManager::fetchRtspCredential 与 VmsTools queryRequestSSLV5：
    // 关闭对端校验（设备自签名证书）+ TLS 兼容协议 + JSON Content-Type
    QNetworkRequest   requestObj;
    QSslConfiguration conf = requestObj.sslConfiguration();
    conf.setPeerVerifyMode(QSslSocket::VerifyNone);
    conf.setProtocol(QSsl::TlsV1SslV3);
    requestObj.setSslConfiguration(conf);
    requestObj.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    requestObj.setUrl(url);
    return requestObj;
}

void DeviceApiClient::getAsync(const QString& url, const QString& customMessage)
{
    getAsync(url, customMessage, kDefaultIntervalMs);
}

void DeviceApiClient::getAsync(const QString& url, const QString& customMessage, int intervalMs)
{
    if (url.isEmpty())
        return;

    RequestMessageData questData;
    questData.reset();
    questData.setRequest(makeRequest(url));
    questData.setRequestType(RequestMessageData::RequestType::eGetType);
    questData.setRequestIntervel(intervalMs);
    questData.setCustomMessage(customMessage);
    m_asynRequest->startRequest(questData);
}

void DeviceApiClient::getDeviceAsync(int cmd, const QString& ip, const QString& customMessage)
{
    getDeviceAsync(cmd, ip, customMessage, kDefaultIntervalMs);
}

void DeviceApiClient::getDeviceAsync(int cmd, const QString& ip, const QString& customMessage, int intervalMs)
{
    // URL 模板：%1 占位为设备 IP（同 fetchRtspCredential）
    QString url = ConfigureManager::getDeviceUrl(static_cast<EnumNameSpace::DeviceQuestUrl>(cmd));
    if (url.isEmpty())
        return;

    getAsync(url.arg(ip), customMessage, intervalMs);
}

void DeviceApiClient::postJsonAsync(const QString& url, const QJsonObject& body, const QString& customMessage)
{
    postJsonAsync(url, body, customMessage, kDefaultIntervalMs);
}

void DeviceApiClient::postJsonAsync(const QString& url, const QJsonObject& body, const QString& customMessage, int intervalMs)
{
    if (url.isEmpty())
        return;

    RequestMessageData questData;
    questData.reset();
    questData.setRequest(makeRequest(url));
    questData.setRequestType(RequestMessageData::RequestType::ePostType);
    questData.setRequestIntervel(intervalMs);
    questData.setSendData(QJsonDocument(body).toJson(QJsonDocument::Compact));
    questData.setCustomMessage(customMessage);
    m_asynRequest->startRequest(questData);
}
