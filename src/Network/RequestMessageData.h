/*********************************************************************
File : RequestMessageData.h
Module : common
Authors: guangnan
date : 2023/03/06 16:00
Ver : 1.0.0
History:
guangnan 2023/03/06 1.0.0 build this module
********************************************************************/
#pragma once
#include <QNetworkRequest>
#include "BaseDataStruct.h"
#include <QByteArray>
#include <QVariant>
#include <QHttpMultiPart>
#include <QSharedPointer>
#include <QDebug>
#include <QThread>

/**
 * @brief 网络请求消息数据结构类
 *
 * 该类继承自 BaseDataStruct，用于封装网络请求的相关数据，包括请求类型、请求参数、
 * 发送数据、响应结果、错误信息以及自定义数据等。支持 GET、POST 及 multipart/form-data 等多种请求方式。
 */
class COMMON_EXPORT RequestMessageData : public BaseDataStruct {
  public:
    /**
     * @brief 请求类型枚举
     */
    enum class RequestType {
        eNullType,          /**< 空类型 */
        eGetType,           /**< GET 请求 */
        ePostType,          /**< POST 请求 */
        eHttpMultiPartType, /**< HTTP Multipart 请求 */
    };

    /**
     * @brief 响应状态枚举
     */
    enum class ResponseType {
        eNullType, /**< 空状态 */
        eSuccess,  /**< 成功 */
        eFail,     /**< 失败 */
    };

    /**
     * @brief 构造函数
     */
    explicit RequestMessageData();

    /**
     * @brief 拷贝构造函数
     * @param other 源对象引用
     */
    RequestMessageData(const RequestMessageData& other);

    /**
     * @brief 析构函数
     */
    ~RequestMessageData();

    /**
     * @brief 获取数据结构类型
     * @return 返回当前数据结构的类型标识
     */
    virtual inline BaseDataStruct::DataStructType dataStructType() const;

    /**
     * @brief 重置数据成员至默认状态
     */
    virtual void reset() override;

    /**
     * @brief 设置请求间隔时间
     * @param interverl 请求间隔时间（单位通常为毫秒）
     */
    inline void setRequestIntervel(const int& interverl);

    /**
     * @brief 获取请求间隔时间
     * @return 返回请求间隔时间的常量引用
     */
    inline const int& requestIntervel() const;

    /**
     * @brief 设置请求类型
     * @param type 请求类型枚举值
     */
    inline void setRequestType(const RequestType& type);

    /**
     * @brief 获取请求类型
     * @return 返回请求类型的常量引用
     */
    inline const RequestType& requestType() const;

    /**
     * @brief 设置网络请求对象
     * @param type QNetworkRequest 对象引用
     */
    inline void setRequest(const QNetworkRequest& type);

    /**
     * @brief 获取网络请求对象
     * @return 返回 QNetworkRequest 对象的常量引用
     */
    inline const QNetworkRequest& request() const;

    /**
     * @brief 设置发送的数据内容
     * @param data 待发送的字节数组
     */
    inline void setSendData(const QByteArray& data);

    /**
     * @brief 获取发送的数据内容
     * @return 返回发送数据的常量引用
     */
    inline const QByteArray& GetSendData() const;

    /**
     * @brief 设置响应类型
     * @param type 响应类型枚举值
     */
    inline void setResponseType(const ResponseType& type);

    /**
     * @brief 获取响应类型
     * @return 返回响应类型的常量引用
     */
    inline const ResponseType& responseType() const;

    /**
     * @brief 设置错误信息
     * @param message 错误描述信息
     */
    inline void setErrorMessage(const QByteArray& message);

    /**
     * @brief 获取错误信息
     * @return 返回错误信息的常量引用
     */
    inline const QByteArray& errorMessage() const;

    /**
     * @brief 设置自定义消息
     * @param message 自定义消息变量
     */
    inline void setCustomMessage(const QVariant& message);

    /**
     * @brief 获取自定义消息
     * @return 返回自定义消息的常量引用
     */
    inline const QVariant& customMessage() const;

    /**
     * @brief 设置自定义数据
     * @param message 自定义数据变量
     */
    inline void setCustomData(const QVariant& message);

    /**
     * @brief 获取自定义数据
     * @return 返回自定义数据的常量引用
     */
    inline const QVariant& customData() const;

    /**
     * @brief 设置响应数据
     * @param data 接收到的响应字节数组
     */
    inline void setResponseData(const QByteArray& data);

    /**
     * @brief 获取响应数据
     * @return 返回响应数据的常量引用
     */
    inline const QByteArray& responseData() const;

    /**
     * @brief 设置 HTTP Multipart 数据
     * @param data QHttpMultiPart 对象指针，传入所有权（内部自动包装为 QSharedPointer）
     */
    inline void setHttpMultPart(QHttpMultiPart* data);

    /**
     * @brief 获取 HTTP Multipart 数据
     * @return 返回 QHttpMultiPart 对象指针（共享所有权，通过 QSharedPointer 管理）
     */
    inline QHttpMultiPart* httpMultPart() const;

    /**
     * @brief 设置提示信息
     * @param message 提示信息的字节数组
     */
    inline void setTipsInformation(const QByteArray& message);

    /**
     * @brief 获取提示信息
     * @return 返回提示信息的常量引用
     */
    inline const QByteArray& tipsInformation() const;

    /**
     * @brief 设置 Token 是否有效标志
     * @param valid true 表示有效，false 表示无效
     */
    inline void setTokenIsValid(const bool valid);

    /**
     * @brief 获取 Token 是否有效标志
     * @return 返回 Token 有效性布尔值
     */
    inline const bool tokenIsValid() const;

    /**
     * @brief 打印请求调试信息（URL、请求头、响应数据）
     */
    void printInfo() const;

  private:
    int             m_requestIntervel; /**< 请求间隔时间 */
    RequestType     m_requestType;     /**< 请求类型 */
    QNetworkRequest m_request;         /**< 网络请求对象 */
    QByteArray      m_sendData;        /**< 发送的数据 */
    ResponseType    m_responseType;    /**< 响应状态类型 */
    QByteArray      m_errorMessage;    /**< 错误信息 */
    QVariant        m_customMessage;   /**< 自定义消息 */
    QByteArray      m_responseData;    /**< 响应数据 */
    QSharedPointer<QHttpMultiPart> m_httpMultPart;    /**< HTTP Multipart 数据（共享所有权） */
    QByteArray      m_tipsInformation; /**< 提示信息 */
    QVariant        m_customData;      /**< 自定义数据 */
    bool            m_tokenIsValid;    /**< Token 有效性标志 */
};

/**
 * @brief 实现获取数据结构类型方法
 * @return 返回 eRequestMessageDataType 类型标识
 */
BaseDataStruct::DataStructType RequestMessageData::dataStructType() const
{
    return BaseDataStruct::DataStructType::eRequestMessageDataType;
}

/**
 * @brief 实现设置请求间隔时间方法
 * @param interverl 请求间隔时间
 */
void RequestMessageData::setRequestIntervel(const int& interverl)
{
    m_requestIntervel = interverl;
}

/**
 * @brief 实现获取请求间隔时间方法
 * @return 返回请求间隔时间的常量引用
 */
const int& RequestMessageData::requestIntervel() const
{
    return m_requestIntervel;
}

/**
 * @brief 实现设置请求类型方法
 * @param type 请求类型枚举值
 */
void RequestMessageData::setRequestType(const RequestMessageData::RequestType& type)
{
    m_requestType = type;
}

/**
 * @brief 实现获取请求类型方法
 * @return 返回请求类型的常量引用
 */
const RequestMessageData::RequestType& RequestMessageData::requestType() const
{
    return m_requestType;
}

/**
 * @brief 实现设置网络请求对象方法
 * @param type QNetworkRequest 对象引用
 */
void RequestMessageData::setRequest(const QNetworkRequest& type)
{
    m_request = type;
}

/**
 * @brief 实现获取网络请求对象方法
 * @return 返回 QNetworkRequest 对象的常量引用
 */
const QNetworkRequest& RequestMessageData::request() const
{
    return m_request;
}

/**
 * @brief 实现设置发送数据方法
 * @param data 待发送的字节数组
 */
void RequestMessageData::setSendData(const QByteArray& data)
{
    m_sendData = data;
    // qDebug() << "LOG::Request interface is:" << m_request.url() << "RequestMessageData::setSendData:" << m_sendData;
}

/**
 * @brief 实现获取发送数据方法
 * @return 返回发送数据的常量引用
 */
const QByteArray& RequestMessageData::GetSendData() const
{
    return m_sendData;
}

/**
 * @brief 实现设置响应类型方法
 * @param type 响应类型枚举值
 */
void RequestMessageData::setResponseType(const RequestMessageData::ResponseType& type)
{
    m_responseType = type;
}

/**
 * @brief 实现获取响应类型方法
 * @return 返回响应类型的常量引用
 */
const RequestMessageData::ResponseType& RequestMessageData::responseType() const
{
    return m_responseType;
}

/**
 * @brief 实现设置错误信息方法
 * @param message 错误描述信息
 */
void RequestMessageData::setErrorMessage(const QByteArray& message)
{
    m_errorMessage = message;
}

/**
 * @brief 实现获取错误信息方法
 * @return 返回错误信息的常量引用
 */
const QByteArray& RequestMessageData::errorMessage() const
{
    return m_errorMessage;
}

/**
 * @brief 实现设置自定义消息方法
 * @param message 自定义消息变量
 */
void RequestMessageData::setCustomMessage(const QVariant& message)
{
    m_customMessage = message;
}

/**
 * @brief 实现获取自定义消息方法
 * @return 返回自定义消息的常量引用
 */
const QVariant& RequestMessageData::customMessage() const
{
    return m_customMessage;
}

/**
 * @brief 实现设置自定义数据方法
 * @param message 自定义数据变量
 */
void RequestMessageData::setCustomData(const QVariant& message)
{
    m_customData = message;
}

/**
 * @brief 实现获取自定义数据方法
 * @return 返回自定义数据的常量引用
 */
const QVariant& RequestMessageData::customData() const
{
    return m_customData;
}

/**
 * @brief 实现设置响应数据方法
 * @param data 接收到的响应字节数组
 */
void RequestMessageData::setResponseData(const QByteArray& data)
{
    m_responseData = data;
}

/**
 * @brief 实现获取响应数据方法
 * @return 返回响应数据的常量引用
 */
const QByteArray& RequestMessageData::responseData() const
{
    return m_responseData;
}

/**
 * @brief 实现设置 HTTP Multipart 数据方法
 * @param data QHttpMultiPart 对象指针，传入所有权（自动包装为 QSharedPointer）
 *
 * 调用方传入裸指针后，所有权转移给 QSharedPointer 管理。
 * QSharedPointer 默认使用 delete 而非 deleteLater，
 * 但 QHttpMultiPart 继承自 QObject，在事件循环中析构更安全，
 * 因此使用自定义删除器调用 deleteLater。
 */
void RequestMessageData::setHttpMultPart(QHttpMultiPart* data)
{
    if (data) {
        // 使用自定义删除器：在对象所属线程事件循环中安全删除
        m_httpMultPart = QSharedPointer<QHttpMultiPart>(data, [](QHttpMultiPart* obj) {
            if (obj) {
                obj->deleteLater();
            }
        });
    } else {
        m_httpMultPart.clear();
    }
}

/**
 * @brief 实现获取 HTTP Multipart 数据方法
 * @return 返回 QHttpMultiPart 对象指针（共享所有权，QSharedPointer 仍持有引用）
 */
QHttpMultiPart* RequestMessageData::httpMultPart() const
{
    return m_httpMultPart.data();
}

/**
 * @brief 实现设置提示信息方法
 * @param message 提示信息的字节数组
 */
void RequestMessageData::setTipsInformation(const QByteArray& message)
{
    m_tipsInformation = message;
}

/**
 * @brief 实现获取提示信息方法
 * @return 返回提示信息的常量引用
 */
const QByteArray& RequestMessageData::tipsInformation() const
{
    return m_tipsInformation;
}

/**
 * @brief 实现设置 Token 有效性标志方法
 * @param valid true 表示有效，false 表示无效
 */
void RequestMessageData::setTokenIsValid(const bool valid)
{
    m_tokenIsValid = valid;
}

/**
 * @brief 实现获取 Token 有效性标志方法
 * @return 返回 Token 有效性布尔值
 */
const bool RequestMessageData::tokenIsValid() const
{
    return m_tokenIsValid;
}

