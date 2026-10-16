/*********************************************************************
File : DeviceApiClient.h
Module : Public
Authors: QA
date : 2026/10/15 16:00
Ver : 1.0.0
History:
QA 2026/10/15 1.0.0 build this module
********************************************************************/
#pragma once

#include "common_global.h"
#include <QObject>
#include <QJsonObject>
#include <QString>
#include <QByteArray>

class AsynRequest;
class QNetworkRequest;

/**
 * @class DeviceApiClient
 * @brief 通用异步 HTTP 调用封装（处理链参考 VmsTools_v2 的
 *        DeviceManagerModel::queryRequestV5 / queryRequestSSLV5
 *        与 DeviceApiClient::postAsyncRequest）。
 *
 * 组包口径与 DeviceManager::fetchRtspCredential / queryRequestSSLV5 一致：
 *   SSL 关闭对端校验（VerifyNone + TlsV1SslV3）+ Content-Type: application/json。
 * 底层走 AsynRequest（BaseRequest 异步子类，共享 QNAM 单例），
 * 发起后立即返回，不阻塞调用线程；结果经 signalHttpResponse 回调，
 * 用请求时传入的 customMessage 匹配分发。
 *
 * 用法（QML）：
 *   DeviceApiClient.getAsync("http://192.168.1.10/goform/xxx", "MyQuery");
 *   Connections { target: DeviceApiClient; function onSignalHttpResponse(customMsg, success, data, errMsg) { ... } }
 *
 * @note QNAM 单例在主线程创建，本类的调用应发生在主线程（QML 调用天然满足）。
 */
class COMMON_EXPORT DeviceApiClient : public QObject {
    Q_OBJECT

  public:
    /**
     * @brief 获取全局单例
     * @return DeviceApiClient 全局唯一实例
     */
    static DeviceApiClient* instance();

    /**
     * @brief 缺省超时时间（毫秒）：10 秒
     *
     * 说明：QML 不识别 C++ 默认参数（调用参数个数必须与声明匹配），
     * 因此每个入口提供"省略 intervalMs"与"显式 intervalMs"两个重载，
     * 省略版内部转调本常量，保证 QML/C++ 两侧缺省均为 5 秒。
     */
    static const int kDefaultIntervalMs = 5 * 1000;

    /**
     * @brief 异步 GET 请求（超时缺省 10 秒）
     * @param url 完整请求地址，如 "http://192.168.1.10/goform/xxx"
     * @param customMessage 请求标识，响应回调时原样带回，用于分发
     */
    Q_INVOKABLE void getAsync(const QString& url, const QString& customMessage);

    /**
     * @brief 异步 GET 请求
     * @param url 完整请求地址，如 "http://192.168.1.10/goform/xxx"
     * @param customMessage 请求标识，响应回调时原样带回，用于分发
     * @param intervalMs 超时时间（毫秒）
     */
    Q_INVOKABLE void getAsync(const QString& url, const QString& customMessage, int intervalMs);

    /**
     * @brief 异步 GET 请求（URL 模板版，超时缺省 10 秒）
     *        模板取 ConfigureManager::getDeviceUrl(cmd)，其中 %1 用设备 IP 填充
     * @param cmd EnumNameSpace::DeviceQuestUrl 枚举值（QML 传整数）
     * @param ip 设备 IP
     * @param customMessage 请求标识，响应回调时原样带回
     */
    Q_INVOKABLE void getDeviceAsync(int cmd, const QString& ip, const QString& customMessage);

    /**
     * @brief 异步 GET 请求（URL 模板版）
     *        模板取 ConfigureManager::getDeviceUrl(cmd)，其中 %1 用设备 IP 填充
     * @param cmd EnumNameSpace::DeviceQuestUrl 枚举值（QML 传整数）
     * @param ip 设备 IP
     * @param customMessage 请求标识，响应回调时原样带回
     * @param intervalMs 超时时间（毫秒）
     */
    Q_INVOKABLE void getDeviceAsync(int cmd, const QString& ip, const QString& customMessage, int intervalMs);

    /**
     * @brief 异步 POST 请求（JSON body，组包同 VmsTools queryRequestSSLV5；超时缺省 10 秒）
     * @param url 完整请求地址
     * @param body JSON 请求体（QML 传 JS 对象自动转换）
     * @param customMessage 请求标识，响应回调时原样带回
     */
    Q_INVOKABLE void postJsonAsync(const QString& url, const QJsonObject& body, const QString& customMessage);

    /**
     * @brief 异步 POST 请求（JSON body，组包同 VmsTools queryRequestSSLV5）
     * @param url 完整请求地址
     * @param body JSON 请求体（QML 传 JS 对象自动转换）
     * @param customMessage 请求标识，响应回调时原样带回
     * @param intervalMs 超时时间（毫秒）
     */
    Q_INVOKABLE void postJsonAsync(const QString& url, const QJsonObject& body, const QString& customMessage, int intervalMs);

  signals:
    /**
     * @brief HTTP 响应回调（成功/超时/失败都会发一次）
     * @param customMessage 与请求一致，用于分发
     * @param success 收到非空响应体为 true（超时/网络错误/空响应为 false）
     * @param responseData 响应体原始字节（设备可能返回 HTML 包裹的 JSON，调用方自行剥离）
     * @param errorMessage 错误信息（成功时为空）
     */
    void signalHttpResponse(const QString& customMessage, bool success, const QByteArray& responseData, const QString& errorMessage);

  private:
    explicit DeviceApiClient(QObject* parent = nullptr);

    /**
     * @brief 组装 QNetworkRequest（SSL/请求头口径同 fetchRtspCredential）
     * @param url 完整请求地址
     * @return 已配置 SSL 与 Content-Type 的请求对象
     */
    static QNetworkRequest makeRequest(const QString& url);

  private:
    AsynRequest* m_asynRequest; /**< 底层异步请求对象 */
};
