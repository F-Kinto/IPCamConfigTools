/*********************************************************************
File : WifiBroadcast.h
Module : common
Authors: guangnan
date : 2023/03/30 16:00
Ver : 1.0.0
History:
guangnan 2023/03/30 1.0.0 build this module
********************************************************************/
#pragma once
#include "common_global.h"
#include <QObject>
#include <QThread>
#include <QUdpSocket>
#include <QTimer>
#include <QString>

/**
 * @brief 结构体用于存储IP摄像头广播发现的信息
 */
typedef struct st_BroadcastIPCAMINFO
{
    int  total;                  /**< 总空间或总数 */
    int  free;                   /**< 剩余空间或空闲数 */
    char szMacAddr[24];          /**< MAC地址字符串 */
    char firmware_ver[24];       /**< 固件版本 */
    char product_name[64];       /**< 产品名称 */
    char DeviceUID[64];          /**< 设备唯一标识符 */
    int  u32language;            /**< 语言设置标识 */
    char system_model[16];       /**< 系统型号 */
    char company_name[24];       /**< 公司名称 */
    char ethMacAddr[24];         /**< 以太网MAC地址 */
    int  u32sensor_type;         /**< 传感器类型标识 */
    char software_framework[16]; /**< 软件框架版本 */
    char ext_cer[24];            /**< 扩展证书信息 */
    char cpu_info[24];           /**< CPU信息 */
    char json_str[256];          /**< JSON格式的额外信息字符串 */

    /**
     * @brief 构造函数，初始化结构体内存为零
     */
    st_BroadcastIPCAMINFO()
    {
        memset(this, 0, sizeof(st_BroadcastIPCAMINFO));
    };
} BroadcastIPCAMINFO;

/**
 * @brief WiFi广播类，用于通过UDP协议发现和通信网络设备
 *
 * 该类继承自QObject，支持信号槽机制，通常在单独线程中运行以处理网络广播消息。
 */
class COMMON_EXPORT WifiBroadcast : public QObject {
    Q_OBJECT

  public:
    /**
     * @brief 构造函数
     * @param parent 父对象指针，默认为nullptr
     */
    explicit WifiBroadcast(QObject* parent = nullptr);

    /**
     * @brief 析构函数，清理资源
     */
    ~WifiBroadcast();

  signals:
    /**
     * @brief 发送单个IP数据的信号
     * @param data 发送的数据字节数组
     * @param ip 目标IP地址
     */
    void signalSendOneIp(const QByteArray& data, const QString& ip);

  public slots:
    /**
     * @brief 槽函数：控制广播发送的启动与停止
     * @param isSend 是否开始发送广播，true为开始，false为停止
     * @param intervel 广播发送的时间间隔（毫秒）
     */
    void slotSendBroadcast(const bool& isSend, const int& intervel);

    /**
     * @brief 设置本次扫描的目标网卡（由调用方通过信号跨线程触发，在工作线程内执行）
     * @param nicName 网卡可读名 / 网卡名 / 网卡上的 IPv4 地址；传空串表示不限制（广播所有网卡网段）
     */
    void slotSetTargetNic(const QString& nicName);

  private slots:
    /**
     * @brief 内部槽函数：启动广播线程或相关逻辑
     */
    void start();

    /**
     * @brief 内部槽函数：结束广播线程或相关逻辑
     */
    void finish();

    /**
     * @brief 内部槽函数：定时触发广播发送
     */
    void slotInterSendBroadcast();

    /**
     * @brief 内部槽函数：读取待处理的UDP数据报
     */
    void slotReadPendingDatagrams();

  private:
    QThread* m_thread; /**< 工作线程指针 */

    // QUdpSocket is a Qt wrapper for UDP sockets used for network communication (receiving and sending packets). It broadcasts requests to find devices and receives responses from other devices.
    QUdpSocket* m_udpSocket; /**< UDP套接字指针，用于网络通信 */
    QTimer*     m_timer;     /**< 定时器指针，用于控制广播频率 */
    QString     m_targetNic; /**< 目标网卡：非空时只向该网卡所在网段发广播 */
};