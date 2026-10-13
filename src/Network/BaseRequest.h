/*********************************************************************
File : BaseRequest.h
Module : common
Authors: guangnan
date : 2023/03/06 16:00
Ver : 1.0.0
History:
guangnan 2023/03/06 1.0.0 build this module
********************************************************************/
#pragma once

#include <QObject>
#include <QNetworkAccessManager>
#include "RequestMessageData.h"
#include <QTimer>
#include <QNetworkReply>
#include <QList>
#include <QJsonDocument>
#include <QJsonObject>
#include "common_global.h"

/**
 * @class BaseRequest
 * @brief 网络请求基类，封装了基于Qt的网络请求管理、超时处理及队列机制。
 *        该类提供了请求的发起、取消、退出以及响应处理的基础框架，
 *        具体业务逻辑需通过继承此类并实现纯虚函数完成。
 *
 *        所有子类共享同一个 QNetworkAccessManager 单例（sharedManager()），
 *        符合 Qt 官方推荐的单 QNAM 模式，复用连接池和缓存。
 *        QNAM 在主线程创建且永不析构，避免 Win7 下析构崩溃问题。
 */
class COMMON_EXPORT BaseRequest : public QObject {
    Q_OBJECT

  public:
    /**
     * @brief 构造函数
     * @param parent Qt对象父指针，用于内存管理
     */
    explicit BaseRequest(QObject* parent);

    /**
     * @brief 析构函数
     */
    ~BaseRequest();

    /**
     * @brief 获取全局共享的 QNetworkAccessManager 单例
     *        在主线程创建，永不析构。符合 Qt 官方推荐的单 QNAM 模式。
     *        避免每个请求对象创建独立 QNAM。
     * @return 全局 QNetworkAccessManager 指针
     */
    static QNetworkAccessManager* sharedManager();

  signals:
    /**
     * @brief signalResponseRequest: 请求响应的结果信号
     * @param data: 包含请求结果数据的结构体
     */
    void signalResponseRequest(const RequestMessageData& data);

  public slots:
    /**
     * @brief startRequest: 开始某一个任务的请求
     * @param data: 请求的数据结构体，包含URL、参数等信息
     */
    virtual void startRequest(const RequestMessageData& data) = 0;

    /**
     * @brief giveUpRequest: 放弃当前的请求任务
     * @param data: 自定义的数据，用于成功操作或者失败操作的应答
     */
    virtual void giveUpRequest(const RequestMessageData& data);

    /**
     * @brief quitRequest: 直接退出所有的请求，包括删除请求的对象，超时对象
     * @note 此操作通常会清理内部维护的请求队列和定时器
     */
    virtual void quitRequest();

    /**
     * @brief TokenIsInvaild: 获取响应后检查token是否失效
     * @param data: 服务器返回的原始数据
     * @return bool 如果Token失效返回true，否则返回false
     */
    virtual bool TokenIsInvaild(const QByteArray& data) = 0;

  protected slots:
    /**
     * @brief slotsRequestFinish: 完成某个请求后的处理槽函数
     * @param data 正在请求的对象数据
     * @param reply 网络请求的原始回复对象
     */
    virtual void slotsRequestFinish(const RequestMessageData& data, QNetworkReply* reply) = 0;

    /**
     * @brief slotsTimeOut: 超时之后的处理方案
     */
    virtual void slotsTimeOut() = 0;

  protected:
    /**
     * @brief startInitRequest: 初始化当前请求环境
     * @note 创建定时器（QNAM 使用共享单例，不再单独创建）
     */
    void startInitRequest();

    /**
     * @brief requestOnePack: 处理请求队列中的第一个包
     * @return bool 成功发起请求返回true，否则返回false
     */
    bool requestOnePack();

  protected:
    /** @brief 定时器指针，用于监控请求超时 */
    QTimer* m_timer;

    /** @brief 当前正在进行的网络回复对象 */
    QNetworkReply* m_currentReply;

    /** @brief 待处理的请求消息队列 */
    QList<RequestMessageData> m_questMessageList;

    /** @brief 当前正在处理的请求消息 */
    RequestMessageData m_currentQuestMessage;

    /** @brief 标记当前是否正在进行请求操作 */
    bool m_isRequesting;
};
