#pragma execution_character_set("utf-8")
#include "DeviceScanner.h"
#include "WifiBroadcast.h"
#include <QTimer>
#include <QDebug>

namespace {
// 广播重复发送间隔（毫秒）：与 WifiBroadcast 内部扫描频率保持一致
const int kBroadcastIntervalMs = 1000;

/**
 * @brief 把结构体里的 char 数组字段转成 QString
 * @param field 字段首地址
 * @param maxLen 字段长度（含结尾 \0）
 * @return 遇到 \0 截断后的字符串
 */
QString toStringField(const char* field, int maxLen)
{
    return QString::fromUtf8(QByteArray(field, maxLen).constData());
}
} // namespace

DeviceScanner* DeviceScanner::m_instance = nullptr;

DeviceScanner* DeviceScanner::instance()
{
    if (!m_instance)
        m_instance = new DeviceScanner();
    return m_instance;
}

DeviceScanner::DeviceScanner(QObject* parent)
    : QObject(parent), m_broadcast(nullptr), m_stopTimer(new QTimer(this)), m_searching(false)
{
    m_stopTimer->setSingleShot(true);
    connect(m_stopTimer, &QTimer::timeout, this, &DeviceScanner::slotSearchTimeout);
}

DeviceScanner::~DeviceScanner()
{
    if (m_broadcast) {
        disconnect(m_broadcast, &WifiBroadcast::signalSendOneIp, this, &DeviceScanner::slotHandleLanDevice);
        disconnect(this, &DeviceScanner::signalSendBroadcast, m_broadcast, &WifiBroadcast::slotSendBroadcast);
        disconnect(this, &DeviceScanner::signalSetTargetNic, m_broadcast, &WifiBroadcast::slotSetTargetNic);
        delete m_broadcast;
        m_broadcast = nullptr;
    }
    m_instance = nullptr;
}

bool DeviceScanner::searching() const
{
    return m_searching;
}

QVariantList DeviceScanner::devices() const
{
    return m_devices;
}

void DeviceScanner::startSearch(const QString& nicName, int timeoutSec)
{
    // 广播对象懒创建：内部自带工作线程，UDP 收发都在子线程完成
    if (!m_broadcast) {
        m_broadcast = new WifiBroadcast();
        connect(m_broadcast, &WifiBroadcast::signalSendOneIp, this, &DeviceScanner::slotHandleLanDevice, Qt::QueuedConnection);
        connect(this, &DeviceScanner::signalSendBroadcast, m_broadcast, &WifiBroadcast::slotSendBroadcast, Qt::QueuedConnection);
        connect(this, &DeviceScanner::signalSetTargetNic, m_broadcast, &WifiBroadcast::slotSetTargetNic, Qt::QueuedConnection);
    }

    // 每次搜索都是全新一轮：清掉上次的去重表与结果
    m_foundIps.clear();
    m_devices.clear();

    // 先限定网卡网段，再触发广播
    emit signalSetTargetNic(nicName);
    emit signalSendBroadcast(true, kBroadcastIntervalMs);

    const int sec = timeoutSec > 0 ? timeoutSec : 5;
    m_stopTimer->start(sec * 1000);
    setSearching(true);

    qInfo().noquote() << QString("设备搜索-开始: 网卡=%1, 时长=%2秒").arg(nicName.isEmpty() ? "所有网卡" : nicName).arg(sec);
}

void DeviceScanner::stopSearch()
{
    if (!m_searching)
        return;

    m_stopTimer->stop();
    emit signalSendBroadcast(false, kBroadcastIntervalMs);
    setSearching(false);

    qInfo().noquote() << QString("设备搜索-结束: 共发现 %1 台设备").arg(m_devices.size());
    emit searchFinished(m_devices.size());
}

void DeviceScanner::slotSearchTimeout()
{
    stopSearch();
}

void DeviceScanner::slotHandleLanDevice(const QByteArray& data, const QString& ip)
{
    if (ip.isEmpty())
        return;

    // 同一个 IP 的回包只处理一次
    if (m_foundIps.contains(ip))
        return;

    // 按广播协议结构体解析回包（回包不足一整包时按实际长度拷贝，其余字段为 0）
    BroadcastIPCAMINFO info;
    const int          copySize = qMin(data.size(), static_cast<int>(sizeof(BroadcastIPCAMINFO)));
    memcpy(&info, data.constData(), copySize);

    const QString productName = toStringField(info.product_name, sizeof(info.product_name));
    const QString uid         = toStringField(info.DeviceUID, sizeof(info.DeviceUID));
    const QString mac         = toStringField(info.szMacAddr, sizeof(info.szMacAddr));
    const QString ethMac      = toStringField(info.ethMacAddr, sizeof(info.ethMacAddr));

    // 既没有产品名、也没有 UID / MAC 的包不是设备回包，丢弃
    if (productName.isEmpty() && uid.isEmpty() && mac.isEmpty() && ethMac.isEmpty()) {
        qDebug().noquote() << QString("设备搜索-忽略无效回包: ip=%1, 长度=%2").arg(ip).arg(data.size());
        return;
    }

    QVariantMap device;
    // 与设备表格列一一对应
    device["ip"]             = ip;
    device["mac"]            = mac.isEmpty() ? ethMac : mac;
    // 设备ID（DeviceUID）填在“UID”列
    device["cloudId"]        = uid;
    device["deviceType"]     = productName;
    device["currentVersion"] = toStringField(info.firmware_ver, sizeof(info.firmware_ver));
    device["status"]         = QString("在线");
    // 广播包里没有这些字段，先留空，后续对接设备指令时再补
    // （必须给出键，否则 TableModel 追加行时会报 “no role named display”）
    device["osdTitle"]       = QString("");
    device["targetVersion"]  = QString("");
    // 附加信息，供后续扩展使用
    device["uid"]            = uid;
    device["companyName"]    = toStringField(info.company_name, sizeof(info.company_name));
    device["systemModel"]    = toStringField(info.system_model, sizeof(info.system_model));

    appendDevice(device);

    qInfo().noquote() << QString("设备搜索-发现设备: ip=%1, mac=%2, 型号=%3, uid=%4")
                             .arg(ip)
                             .arg(device["mac"].toString())
                             .arg(productName)
                             .arg(uid);
}

void DeviceScanner::appendDevice(const QVariantMap& device)
{
    m_foundIps.insert(device.value("ip").toString());
    m_devices << device;
    // 逐台上抛，界面收到一条就追加一行
    emit deviceFound(device);
}

void DeviceScanner::setSearching(bool searching)
{
    if (m_searching == searching)
        return;

    m_searching = searching;
    emit searchingChanged();
}
