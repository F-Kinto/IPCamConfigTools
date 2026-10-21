#include "AsynRequest.h"
#include <QByteArray>
#include <QJsonObject>
#include <QJsonDocument>

AsynRequest::AsynRequest(QObject* parent) : BaseRequest(parent) {}

AsynRequest::~AsynRequest()
{
    quitRequest();
}

void AsynRequest::startRequest(const RequestMessageData& data)
{
    startInitRequest();
    m_questMessageList.append(data);
    if (m_isRequesting)
        return;
    if (!requestOnePack()) {
        RequestMessageData responseMessage = data;
        responseMessage.setErrorMessage(QString("request one pack return error.").toLatin1());
        responseMessage.setResponseType(RequestMessageData::ResponseType::eFail);
        emit signalResponseRequest(responseMessage);
    }
}

void AsynRequest::giveUpRequest(const RequestMessageData& data)
{
    if (!m_isRequesting) {
        RequestMessageData responseMessage(data);
        responseMessage.setErrorMessage(QString("giveUpRequest return error.").toLatin1());
        responseMessage.setResponseType(RequestMessageData::ResponseType::eFail);
        emit signalResponseRequest(responseMessage);
        return;
    }
    if (m_timer)
        m_timer->stop();
    if (m_currentReply) {
        m_currentReply->abort();
        m_currentReply->deleteLater();
        m_currentReply = nullptr;
    }

    RequestMessageData responseMessage(data);
    responseMessage.setErrorMessage(QString("giveUpRequest success.").toLatin1());
    responseMessage.setResponseType(RequestMessageData::ResponseType::eSuccess);
    emit signalResponseRequest(responseMessage);

    requestOnePack();
}

void AsynRequest::quitRequest()
{
    BaseRequest::quitRequest();
}

void AsynRequest::slotsRequestFinish(const RequestMessageData& data, QNetworkReply* reply)
{
    RequestMessageData responseMessage(data);
    const auto         responseData(reply->readAll());
    responseMessage.setTokenIsValid(TokenIsInvaild(responseData));
    responseMessage.setResponseType(!responseData.isEmpty() ? RequestMessageData::ResponseType::eSuccess : RequestMessageData::ResponseType::eFail);
    responseMessage.setResponseData(responseData);
    auto jsonn = QJsonDocument::fromJson(responseData.data()).object();
    if (jsonn.contains("error_code") && jsonn.value("error_code").toString() != "0")
        qWarning() << "LOG::Http Error" << QJsonDocument::fromJson(responseData).object();
    emit signalResponseRequest(responseMessage);
    reply->deleteLater();
    m_isRequesting = false;
    requestOnePack();
}

void AsynRequest::slotsTimeOut()
{
    if (m_currentQuestMessage.requestType() == RequestMessageData::RequestType::eHttpMultiPartType && m_currentQuestMessage.httpMultPart()) {
        m_currentQuestMessage.setHttpMultPart(nullptr); // QSharedPointer 释放引用，自定义删除器自动 deleteLater
    }
    m_timer->stop();
    m_currentQuestMessage.setErrorMessage(QString("send data time out.").toLatin1());
    m_currentQuestMessage.setResponseType(RequestMessageData::ResponseType::eFail);
    emit signalResponseRequest(m_currentQuestMessage);
    m_isRequesting = false;
    requestOnePack();
}

bool AsynRequest::TokenIsInvaild(const QByteArray& data)
{
    auto jsonn = QJsonDocument::fromJson(data.data()).object();
    if (jsonn.value("error_code").toString().contains("E_000_003", Qt::CaseInsensitive)) {
        qWarning() << "customMessage =" << m_currentQuestMessage.customMessage().toString() << "error_code =" << jsonn.value("error_code").toString();
        return true;
    }
    return false;
}
