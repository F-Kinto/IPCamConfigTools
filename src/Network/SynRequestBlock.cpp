#include "SynRequestBlock.h"
#include <QTimer>

SynRequestBlock::SynRequestBlock(QObject* parent) : BaseRequest(parent)
{
    m_questMessageList.clear();
}

SynRequestBlock::~SynRequestBlock()
{
    quitRequest();
    m_loop.quit();
}

void SynRequestBlock::startRequest(const RequestMessageData& data)
{
    if (m_isRequesting) {
        RequestMessageData responseMessage = data;
        responseMessage.setErrorMessage(QString("SynRequestBlock is busy, reject reentrant request.").toLatin1());
        responseMessage.setResponseType(RequestMessageData::ResponseType::eFail);
        emit signalResponseRequest(responseMessage);
        return;
    }

    m_recvData.clear();
    startInitRequest();
    connect(m_timer, &QTimer::timeout, &m_loop, &QEventLoop::quit, Qt::UniqueConnection);
    m_questMessageList.append(data);
    if (!requestOnePack()) {
        RequestMessageData responseMessage = data;
        responseMessage.setErrorMessage(QString("request one pack return error.").toLatin1());
        responseMessage.setResponseType(RequestMessageData::ResponseType::eFail);
        emit signalResponseRequest(responseMessage);
        return;
    }
    m_loop.exec();
}

void SynRequestBlock::startRequest(const RequestMessageData& data, std::atomic_bool* stopFlag)
{
    if (m_isRequesting) {
        RequestMessageData responseMessage = data;
        responseMessage.setErrorMessage(QString("SynRequestBlock is busy, reject reentrant request.").toLatin1());
        responseMessage.setResponseType(RequestMessageData::ResponseType::eFail);
        emit signalResponseRequest(responseMessage);
        return;
    }

    m_recvData.clear();
    startInitRequest();
    connect(m_timer, &QTimer::timeout, &m_loop, &QEventLoop::quit, Qt::UniqueConnection);

    m_questMessageList.append(data);
    if (!requestOnePack()) {
        RequestMessageData responseMessage = data;
        responseMessage.setErrorMessage(QString("request one pack return error.").toLatin1());
        responseMessage.setResponseType(RequestMessageData::ResponseType::eFail);
        emit signalResponseRequest(responseMessage);
        return;
    }
    QTimer checkStopTimer;
    if (stopFlag) {
        connect(&checkStopTimer, &QTimer::timeout, this, [this, stopFlag]() {
            if (stopFlag->load()) {
                qInfo() << "stopFlag is true, give up request";
                if (m_isRequesting) {
                    quitRequest();
                } else {
                    m_loop.quit();
                }
            }
        });
        checkStopTimer.start(100);
    }

    m_loop.exec();

    if (stopFlag) {
        checkStopTimer.stop();
    }
}

void SynRequestBlock::giveUpRequest(const RequestMessageData& data)
{
    if (!m_isRequesting) {
        RequestMessageData responseMessage = data;
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

void SynRequestBlock::quitRequest()
{
    m_loop.quit();
    if (m_timer)
        disconnect(m_timer, &QTimer::timeout, &m_loop, &QEventLoop::quit);
    BaseRequest::quitRequest();
}

void SynRequestBlock::slotsRequestFinish(const RequestMessageData& data, QNetworkReply* reply)
{
    m_timer->stop();
    if (reply->error() == QNetworkReply::NoError) {
        auto recvData = reply->readAll();
        //if (!TokenIsInvaild(recvData)) {
            m_recvData = recvData;
        //}
    }
    reply->deleteLater();
    m_currentReply = nullptr;
    m_isRequesting = false;
    m_loop.quit();
    m_currentQuestMessage.reset();
}

void SynRequestBlock::slotsTimeOut()
{
    if (m_currentQuestMessage.requestType() == RequestMessageData::RequestType::eHttpMultiPartType && m_currentQuestMessage.httpMultPart()) {
        m_currentQuestMessage.setHttpMultPart(nullptr);  // QSharedPointer 释放引用，自定义删除器自动 deleteLater
    }
    m_timer->stop();
    m_currentQuestMessage.setErrorMessage(QString("send data time out.").toLatin1());
    m_currentQuestMessage.setResponseType(RequestMessageData::ResponseType::eFail);
    emit signalResponseRequest(m_currentQuestMessage);
    m_isRequesting = false;
    m_currentQuestMessage.reset();
    m_loop.quit();
}

bool SynRequestBlock::TokenIsInvaild(const QByteArray& data)
{
    auto jsonn = QJsonDocument::fromJson(data.data()).object();
    if (jsonn.value("error_code").toString().contains("E_000_003", Qt::CaseInsensitive)) {
        return true;
    }
    return false;
}
