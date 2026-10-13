#include "BaseRequest.h"
#include <QDebug>
#include <QCoreApplication>
#include <QThread>

/**
 * @brief 获取全局共享的 QNetworkAccessManager 单例
 *
 * 在主线程创建且永不析构，符合 Qt 官方推荐的单 QNAM 模式。
 * 避免每个请求对象创建独立 QNAM。
 * 进程退出时 OS 回收内存，QNAM 析构函数永不执行。
 */
QNetworkAccessManager* BaseRequest::sharedManager()
{
    static QNetworkAccessManager* s_instance = []() {
        QNetworkAccessManager* mgr = new QNetworkAccessManager();
        // 确保 QNAM 在主线程创建
        mgr->moveToThread(QCoreApplication::instance()->thread());
        return mgr;
    }();
    return s_instance;
}

BaseRequest::BaseRequest(QObject* parent) : QObject(parent), m_timer(nullptr), m_currentReply(nullptr), m_isRequesting(false) {}

BaseRequest::~BaseRequest() {}

void BaseRequest::startInitRequest()
{
    if (!m_timer) {
        m_timer = new QTimer();
        connect(m_timer, &QTimer::timeout, this, &BaseRequest::slotsTimeOut);
    }
}

void BaseRequest::giveUpRequest(const RequestMessageData& data)
{
    if (m_timer) {
        m_timer->stop();
    }
    if (m_currentReply) {
        m_currentReply->abort();
        m_currentReply->deleteLater();
        m_currentReply = nullptr;
    }
    RequestMessageData response(data);
    response.setErrorMessage(QString("giveup success.").toLatin1());
    response.setResponseType(RequestMessageData::ResponseType::eSuccess);
    emit signalResponseRequest(response);
    m_currentQuestMessage.reset();
}

void BaseRequest::quitRequest()
{
    if (m_timer) {
        m_timer->disconnect();
        m_timer->stop();
        delete m_timer;
        m_timer = nullptr;
    }
    if (m_currentReply) {
        m_currentReply->disconnect();
        m_currentReply->abort();
        m_currentReply->deleteLater();
        m_currentReply = nullptr;
    }
    if (m_currentQuestMessage.requestType() == RequestMessageData::RequestType::eHttpMultiPartType && m_currentQuestMessage.httpMultPart()) {
        m_currentQuestMessage.setHttpMultPart(nullptr);  // QSharedPointer 释放引用，自定义删除器自动 deleteLater
    }
    m_questMessageList.clear();
    m_isRequesting = false;
    m_currentQuestMessage.reset();
}

bool BaseRequest::requestOnePack()
{
    if (m_questMessageList.isEmpty())
        return false;
    m_isRequesting        = true;
    m_currentQuestMessage = m_questMessageList.front();
    m_questMessageList.pop_front();
    m_timer->setInterval(m_currentQuestMessage.requestIntervel());

    QNetworkAccessManager* mgr   = sharedManager();
    QNetworkReply*         reply = nullptr;

    switch (m_currentQuestMessage.requestType()) {
        case RequestMessageData::RequestType::eGetType:
            reply = mgr->get(m_currentQuestMessage.request());
            break;
        case RequestMessageData::RequestType::ePostType:
            reply = mgr->post(m_currentQuestMessage.request(), m_currentQuestMessage.GetSendData());
            break;
        case RequestMessageData::RequestType::eHttpMultiPartType: {
            if (!m_currentQuestMessage.httpMultPart())
                return false;
            reply = mgr->post(m_currentQuestMessage.request(), m_currentQuestMessage.httpMultPart());
            break;
        }
        default:
            return false;
    }

    if (!reply)
        return false;

    m_currentReply = reply;

    // 按 reply 路由 finished 信号到当前请求对象
    connect(reply, &QNetworkReply::finished, this, [this]() {
        QNetworkReply* reply = m_currentReply;
        if (!reply)
            return;
        m_currentReply = nullptr;

        // 定时器未激活说明已超时，丢弃响应
        if (!m_timer || !m_timer->isActive()) {
            reply->deleteLater();
            return;
        }
        m_timer->stop();

        // 处理 multipart 清理
        if (m_currentQuestMessage.requestType() == RequestMessageData::RequestType::eHttpMultiPartType && m_currentQuestMessage.httpMultPart()) {
            m_currentQuestMessage.setHttpMultPart(nullptr);  // QSharedPointer 释放引用，自定义删除器自动 deleteLater
        }

        slotsRequestFinish(m_currentQuestMessage, reply);
    });

    m_timer->start();
    return true;
}
