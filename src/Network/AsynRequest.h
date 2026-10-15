/*********************************************************************
File : AsynRequest.h
Module : common
Authors: guangnan
date : 2023/03/06 16:00
Ver : 1.0.0
History:
guangnan 2023/03/06 1.0.0 build this module
********************************************************************/
#pragma once

#include "BaseRequest.h"

/**
 * @class AsynRequest
 * @brief 异步请求处理类，继承自 BaseRequest（同步自 VmsTools_v2/common）。
 *
 * 该类用于发起异步网络请求，不阻塞调用线程。
 * 使用全局共享的 QNetworkAccessManager（sharedManager()），
 * QNAM 的 get()/post() 本身就是非阻塞的，无需额外的 worker thread。
 * 请求完成后经 signalResponseRequest 携带 RequestMessageData 回调，
 * 调用方用请求时塞入的 customMessage 匹配分发。
 */
class COMMON_EXPORT AsynRequest : public BaseRequest {
    Q_OBJECT

  public:
    /**
     * @brief 构造函数
     * @param parent Qt对象父指针，默认为 nullptr
     */
    explicit AsynRequest(QObject* parent = nullptr);

    /**
     * @brief 析构函数
     */
    ~AsynRequest();

  public slots:

    /**
     * @brief 启动异步请求
     * @param data 请求消息数据，包含URL、参数等信息
     */
    virtual void startRequest(const RequestMessageData& data) override;

    /**
     * @brief 放弃当前请求
     * @param data 请求消息数据，用于标识要放弃的请求
     */
    virtual void giveUpRequest(const RequestMessageData& data) override;

    /**
     * @brief 退出请求处理
     */
    virtual void quitRequest() override;

  protected slots:

    /**
     * @brief 请求完成槽函数
     * @param data 原始请求消息数据
     * @param reply 网络回复对象
     */
    virtual void slotsRequestFinish(const RequestMessageData& data, QNetworkReply* reply) override;

    /**
     * @brief 超时处理槽函数
     */
    virtual void slotsTimeOut() override;

    /**
     * @brief 检查Token是否无效
     * @param data 服务器返回的原始字节数据
     * @return bool 如果Token无效返回 true，否则返回 false
     */
    virtual bool TokenIsInvaild(const QByteArray& data) override;
};
