/*********************************************************************
File : DeviceScanner.h
Module : Public
date : 2026/10/10
Ver : 1.0.0
History:
1.0.0 build this module
********************************************************************/
#pragma once
#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QSet>
#include <QString>

class QTimer;
class WifiBroadcast;

/**
 * @brief 设备搜索的“调用者”：串联广播扫描与界面列表
 *
 * 职责：
 * 1) 通过 signalSendBroadcast(true/false, 间隔) 触发 / 停止 WifiBroadcast 的广播扫描；
 * 2) 通过 signalSetTargetNic() 限定只扫描主界面所选网卡的网段；
 * 3) 接收 WifiBroadcast::signalSendOneIp(datagram, ip)，解析设备信息并按 IP 去重；
 * 4) 每发现一台设备就抛出 deviceFound()，扫描结束时抛出 searchFinished(总数)。
 *
 * 本对象常驻主线程，WifiBroadcast 在子线程收发 UDP，两者之间全部用 QueuedConnection 通信。
 */
class DeviceScanner : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool searching READ searching NOTIFY searchingChanged)

  public:
    /**
     * @brief 单例
     */
    static DeviceScanner* instance();
    ~DeviceScanner();

    /**
     * @brief 是否正在搜索
     */
    bool searching() const;

    /**
     * @brief 开始一次搜索（供 QML 调用）
     * @param nicName 目标网卡：可读名 / 网卡名 / 网卡 IPv4；传空串表示扫描所有网卡网段
     * @param timeoutSec 搜索时长（秒），到点自动停止
     */
    Q_INVOKABLE void startSearch(const QString& nicName, int timeoutSec);

    /**
     * @brief 提前停止搜索（供 QML 调用）
     */
    Q_INVOKABLE void stopSearch();

    /**
     * @brief 本次搜索到的设备列表（每项为 QVariantMap，字段与设备表格列对应）
     */
    Q_INVOKABLE QVariantList devices() const;

  signals:
    /**
     * @brief 触发/停止广播扫描，连接到 WifiBroadcast::slotSendBroadcast
     */
    void signalSendBroadcast(const bool& isSend, const int& intervel);

    /**
     * @brief 设置目标网卡，连接到 WifiBroadcast::slotSetTargetNic
     */
    void signalSetTargetNic(const QString& nicName);

    /**
     * @brief 发现一台设备（主线程抛出，QML 直接追加到列表）
     */
    void deviceFound(const QVariantMap& device);

    /**
     * @brief 一次搜索结束
     * @param count 本次发现的设备数量
     */
    void searchFinished(int count);

    void searchingChanged();

  private slots:
    /**
     * @brief 处理广播回包（子线程 -> 主线程，队列连接）
     */
    void slotHandleLanDevice(const QByteArray& data, const QString& ip);

    /**
     * @brief 搜索时长到点，自动停止
     */
    void slotSearchTimeout();

  private:
    explicit DeviceScanner(QObject* parent = nullptr);
    void setSearching(bool searching);

    /**
     * @brief 按 IP 去重后缓存设备，并上抛给界面
     */
    void appendDevice(const QVariantMap& device);

    static DeviceScanner* m_instance; /**< 单例指针 */

    WifiBroadcast* m_broadcast; /**< 广播扫描对象（内部运行在子线程） */
    QTimer*        m_stopTimer; /**< 搜索时长定时器（主线程） */

    QSet<QString>  m_foundIps; /**< 已处理过的 IP，用于去重 */
    QVariantList   m_devices;  /**< 本次搜索结果 */
    bool           m_searching;
};
