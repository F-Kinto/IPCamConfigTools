#include "RequestMessageData.h"

/**
 * @brief RequestMessageData 默认构造函数
 *
 * 初始化基类 BaseDataStruct，注册 Qt 元类型以支持信号槽通信，
 * 并调用 reset()将成员变量初始化为默认状态。
 */
RequestMessageData::RequestMessageData() : BaseDataStruct()
{
    qRegisterMetaType<RequestMessageData>("RequestMessageData");
    qRegisterMetaType<RequestMessageData>("RequestMessageData&");
    RequestMessageData::reset();
}

/**
 * @brief RequestMessageData 拷贝构造函数
 *
 * 执行拷贝操作，将源对象 otherObj 的所有成员变量复制到当前对象。
 * m_httpMultPart 使用 QSharedPointer 共享所有权，拷贝时引用计数递增，
 * 无需 const_cast 修改源对象，彻底消除旧版 const_cast 导致的未定义行为。
 *
 * @param otherObj 被拷贝的源 RequestMessageData 对象引用
 */
RequestMessageData::RequestMessageData(const RequestMessageData& otherObj)
{
    m_requestIntervel  = otherObj.m_requestIntervel;
    m_requestType      = otherObj.m_requestType;
    m_request          = otherObj.m_request;
    m_sendData         = otherObj.m_sendData;
    m_responseType     = otherObj.m_responseType;
    m_errorMessage     = otherObj.m_errorMessage;
    m_customMessage    = otherObj.m_customMessage;
    m_customData       = otherObj.m_customData;
    m_responseData     = otherObj.m_responseData;
    m_httpMultPart     = otherObj.m_httpMultPart;   // QSharedPointer 共享所有权，引用计数 +1
    m_tipsInformation  = otherObj.m_tipsInformation;
    m_tokenIsValid     = otherObj.m_tokenIsValid;
}

/**
 * @brief RequestMessageData 析构函数
 *
 * QSharedPointer 自动管理 m_httpMultPart 的生命周期，
 * 引用计数归零时通过自定义删除器调用 deleteLater 安全析构。
 */
RequestMessageData::~RequestMessageData() {}

/**
 * @brief 重置所有成员变量为默认初始值
 *
 * 将请求间隔、类型、URL、数据缓冲区、响应状态等恢复至初始状态，
 * 用于复用对象或初始化新对象。
 */
void RequestMessageData::reset()
{
    m_requestIntervel = 3 * 1000;
    m_requestType     = RequestMessageData::RequestType::eGetType;
    m_request         = QNetworkRequest(QUrl(""));
    m_sendData.clear();
    m_responseType = ResponseType::eNullType;
    m_errorMessage.clear();
    m_customMessage = "";
    m_customData    = "";
    m_responseData  = "";
    m_httpMultPart  = nullptr;  // QSharedPointer 赋 nullptr，引用计数 -1
    m_tipsInformation.clear();
    m_tokenIsValid = true;
}

/**
 * @brief 打印请求调试信息：URL、请求头、响应数据
 */
void RequestMessageData::printInfo() const
{
    qDebug() << "========== RequestMessageData Debug ==========";

    // URL
    qDebug() << "[URL]" << m_request.url().toString();

    // 请求类型
    qDebug() << "[RequestType]" << static_cast<int>(m_requestType);

    // 请求头
    qDebug() << "[Headers]";
    const QList<QByteArray>& headers = m_request.rawHeaderList();
    for (const QByteArray& header : headers) {
        qDebug() << "  " << header << ":" << m_request.rawHeader(header);
    }

    // 发送数据
    if (!m_sendData.isEmpty()) {
        qDebug() << "[SendData]" << m_sendData.left(512);
    }

    // 响应状态
    qDebug() << "[ResponseType]" << static_cast<int>(m_responseType);

    // 响应数据
    if (!m_responseData.isEmpty()) {
        qDebug() << "[ResponseData]" << m_responseData.left(512);
    }

    // 错误信息
    if (!m_errorMessage.isEmpty()) {
        qDebug() << "[ErrorMessage]" << m_errorMessage;
    }

    qDebug() << "===============================================";
}
