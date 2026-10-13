/*********************************************************************
File : SynRequestBlock.h
Module : common
Authors: guangnan
date : 2023/03/06 16:00
Ver : 1.0.0
History:
guangnan 2023/03/06 1.0.0 build this module
********************************************************************/
#pragma once

#include "BaseRequest.h"
#include <QEventLoop>
#include <atomic>

/**
 * @class SynRequestBlock
 * @brief 同步请求阻塞类，继承自 BaseRequest。
 *        该类通过内部维护一个 QEventLoop 来实现同步等待网络请求完成，
 *        适用于需要按顺序执行且必须等待前一个请求结果才能继续后续逻辑的场景。
 *        使用全局共享的 QNetworkAccessManager（sharedManager()）。
 */
class COMMON_EXPORT SynRequestBlock : public BaseRequest {
    Q_OBJECT

  public:
    explicit SynRequestBlock(QObject* parent = nullptr);
    ~SynRequestBlock();

    inline const QByteArray& recvData() const;

  public slots:
    virtual void startRequest(const RequestMessageData& data) override;
    virtual void startRequest(const RequestMessageData& data, std::atomic_bool* stopFlag);
    virtual void giveUpRequest(const RequestMessageData& data) override;
    virtual void quitRequest() override;

  protected slots:
    virtual void slotsRequestFinish(const RequestMessageData& data, QNetworkReply* reply) override;
    virtual void slotsTimeOut() override;
    virtual bool TokenIsInvaild(const QByteArray& data) override;

  private:
    QEventLoop m_loop;
    QByteArray m_recvData;
};

const QByteArray& SynRequestBlock::recvData() const
{
    return m_recvData;
}
