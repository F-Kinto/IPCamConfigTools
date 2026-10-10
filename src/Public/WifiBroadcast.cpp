#include "WifiBroadcast.h"
#include <QNetworkInterface>

/**
 * @brief 构造函数，初始化 WifiBroadcast 对象并启动工作线程。
 *
 * 该函数创建一个独立的 QThread 线程，将当前对象移动到该线程中运行，
 * 以确保网络操作和定时器事件在子线程中执行，避免阻塞主 UI 线程。
 *
 * @param parent Qt 父对象指针，用于内存管理和对象树构建。
 */
WifiBroadcast::WifiBroadcast(QObject* parent) : QObject(parent), m_udpSocket(nullptr), m_timer(nullptr)
{
    // Create a thread object
    m_thread = new QThread();
    connect(m_thread, &QThread::started, this, &WifiBroadcast::start);
    connect(m_thread, &QThread::finished, this, &WifiBroadcast::finish);

    // Move the current object to this thread; the object's slot functions will be executed in the child thread.
    moveToThread(m_thread);

    // Thread Startup
    m_thread->start();
}

/**
 * @brief 析构函数，安全地停止工作线程并清理资源。
 *
 * 请求线程退出，等待线程结束，并安排线程对象稍后删除，防止内存泄漏。
 */
WifiBroadcast::~WifiBroadcast()
{
    m_thread->quit();
    if (QThread::currentThread() != m_thread) {
        m_thread->wait();
    }
    m_thread->deleteLater();
    m_thread = nullptr;
}

/**
 * @brief 槽函数：控制广播扫描的启动与停止。
 *
 * 根据输入参数决定是否立即发送一次广播探测包，并启动或停止周期性扫描定时器。
 *
 * @param isSend 布尔值，true 表示开始扫描，false 表示停止扫描。
 * @param intervel 整数，表示周期性扫描的时间间隔（单位：毫秒）。
 */
void WifiBroadcast::slotSendBroadcast(const bool& isSend, const int& intervel)
{
    if (isSend) {
        // Scan immediately
        slotInterSendBroadcast();
        // Then scan once every intervel seconds
        m_timer->start(intervel);
    } else {
        // After sending a stop LAN discovery signal, stop this timer and cease scanning.
        m_timer->stop();
    }
}

/**
 * @brief 槽函数：在线程启动时初始化 UDP 套接字和定时器。
 *
 * 创建并配置 QUdpSocket，绑定到指定端口并加入多播组；
 * 同时创建 QTimer 用于触发周期性的广播发送任务。
 * 此函数在 m_thread 线程上下文中执行。
 */
void WifiBroadcast::start()
{
    if (!m_udpSocket) {

        m_udpSocket = new QUdpSocket();

        // Upon receiving the response packet, the socket signal readyRead is triggered.
        connect(m_udpSocket, &QUdpSocket::readyRead, this, &WifiBroadcast::slotReadPendingDatagrams);

        // Bind to listening port
        // AnyIPv4 is a wildcard address (0.0.0.0), the socket is bound to the wildcard address
        // Bind port number: 7188
        // Result: As long as the data packet is sent to port 7188 of any network card on your machine, the socket will receive it.
        // ShareAddress: Allows multiple sockets/processes to share the same port.
        // ReuseAddressHint: Gives the underlying system a "allow port reuse" hint.
        // Purpose: Reduces the probability of bind failure.
        m_udpSocket->bind(QHostAddress::AnyIPv4, 7188, QUdpSocket::ShareAddress | QUdpSocket::ReuseAddressHint);

        // Disable multicast loopback
        // Will the multicast packets you send be automatically "reclaimed" onto this socket by the local machine ?
        // Effect : Prevents multicast packets you send from triggering readyRead, thus avoiding interference / misjudgment caused by "self-sending and receiving".
        m_udpSocket->setSocketOption(QAbstractSocket::MulticastLoopbackOption, 0);

        // Obtain a list of all network cards on the local machine. This step only enumerates the interfaces that can be seen in the system; it does not mean that all of them can be used for
        // multicast.
        QList<QNetworkInterface> list = QNetworkInterface::allInterfaces();
        // Traverse each network card
        for (int i = 0; i < list.size(); i++) {
            QNetworkInterface intf = list.at(i);

            // Construct a set of flags that must be satisfied
            // IsUp: The interface is enabled
            // IsRunning: The interface is running
            // CanMulticast: The interface supports multicast
            QNetworkInterface::InterfaceFlags flagsCheck = QNetworkInterface::IsUp;
            flagsCheck |= QNetworkInterface::IsRunning;
            flagsCheck |= QNetworkInterface::CanMulticast;

            // Skip network cards with missing capabilities and loopback network cards.
            if (flagsCheck != (flagsCheck & intf.flags()) || QNetworkInterface::IsLoopBack == (QNetworkInterface::IsLoopBack & intf.flags())) {
                continue;
            }

            // Multicast address
            QHostAddress multiAddr = QHostAddress("234.235.236.237");

            // Add the multicast address 234.235.236.237 to the current network interface's intf.
            // Result: Whenever a data packet is sent to 234.235.236.237 (and the port is the one your socket binds to, such as 7188 you bound earlier), the operating system will deliver the response
            // packet to this socket.
            bool success = m_udpSocket->joinMulticastGroup(multiAddr, intf);
            if (!success) {
                qDebug() << "joinMulticastGroup failed";
            }
        }
    }

    if (!m_timer) {
        m_timer = new QTimer(); // Event loop belonging to the current thread (m_thread)
        m_timer->setInterval(1 * 100);
        connect(m_timer, &QTimer::timeout, this, &WifiBroadcast::slotInterSendBroadcast);
    }
}

/**
 * @brief 槽函数：在线程结束时清理 UDP 套接字和定时器资源。
 *
 * 关闭套接连接，断开信号槽连接，并安排对象稍后删除以释放内存。
 * 此函数在 m_thread 线程上下文中执行。
 */
void WifiBroadcast::finish()
{
    if (m_udpSocket) {
        m_udpSocket->close();
        disconnect(m_udpSocket, &QUdpSocket::readyRead, this, &WifiBroadcast::slotReadPendingDatagrams);
        m_udpSocket->deleteLater();
        m_udpSocket = nullptr;
    }
    if (m_timer) {
        disconnect(m_timer, &QTimer::timeout, this, &WifiBroadcast::slotInterSendBroadcast);
        m_timer->stop();
        m_timer->deleteLater();
    }
}

/**
 * @brief 槽函数：处理接收到的 UDP 数据报。
 *
 * 当 UDP 套接字有 pending 数据时触发。循环读取所有可用的数据报，
 * 解析发送者的 IP 地址，并将原始数据和 IP 字符串通过信号发射出去。
 */
void WifiBroadcast::slotReadPendingDatagrams()
{
    // Continue reading as long as there are still response packets in the socket receive buffer.
    while (m_udpSocket->hasPendingDatagrams()) {
        QByteArray datagram;
        // pendingDatagramSize() returns the number of bytes in the "next packet"
        // Allocates a buffer of exactly the size for the "current packet"
        datagram.resize(m_udpSocket->pendingDatagramSize());

        QHostAddress targetAddrIP;
        quint16      targetPort = 0;

        // Read the packet body + sender address
        // The datagram contains the response payload (e.g., device information in binary format)
        // targetAddrIP is the device IP address
        // targetPort is the source port used by the device when sending the packet
        m_udpSocket->readDatagram(datagram.data(), datagram.size(), &targetAddrIP, &targetPort);

        // Convert sender IP to string IP
        QString IP = QString("%1.%2.%3.%4")
                         .arg((targetAddrIP.toIPv4Address() >> 24) & 0xFF)
                         .arg((targetAddrIP.toIPv4Address() >> 16) & 0xFF)
                         .arg((targetAddrIP.toIPv4Address() >> 8) & 0xFF)
                         .arg(targetAddrIP.toIPv4Address() & 0xFF);

        // IP address is valid, send signal carrying data
        if (!QHostAddress(IP).isNull())
            emit signalSendOneIp(datagram, IP);
    }
}

/**
 * @brief 槽函数：执行局域网设备探测广播。
 *
 * 向所有有效的非回环网络接口发送 UDP 广播包，并向指定的多播地址发送多播包。
 * 此函数通常由定时器触发或手动调用，用于发现局域网内的兼容设备。
 *
 * 扫描步骤：
 * 1. 生成固定的探测载荷。
 * 2. 遍历所有网络接口，对每个 IPv4 地址条目的广播地址发送探测包（端口 7788）。
 * 3. 向多播地址 234.235.236.237 发送探测包（端口 7788）。
 */
void WifiBroadcast::slotInterSendBroadcast()
{
    // Prepare the probe content to be sent. This string is always the same UDP payload sent out for each scan.
    // If the device implements the corresponding protocol, it will typically listen on a specific port (7788 in your case). After receiving this content, it will send back device information.
    const QByteArray datagram = "Hello from JOOAN broadcast";

    // Enumerate all network cards (interfaces) on this machine
    foreach (QNetworkInterface netInterface, QNetworkInterface::allInterfaces()) {
        // Skip the loopback network card
        if (QNetworkInterface::IsLoopBack == (QNetworkInterface::IsLoopBack & netInterface.flags())) {
            continue;
        }

        // Get all IPs under this network interface card. A network interface card may have multiple IPs/network segments (e.g., multiple addresses configured on the same card, virtual network
        // segments, etc.), so it is necessary to iterate through each entry.
        QList<QNetworkAddressEntry> entryList = netInterface.addressEntries();

        foreach (QNetworkAddressEntry entry, entryList) {
            // Retrieve the subnet broadcast address corresponding to this IP entry
            QHostAddress broadcastAddress = entry.broadcast();

            // For those meeting the conditions
            // Filtering conditions
            // Must have a broadcast address (cannot broadcast without one)
            // Exclude local loopback addresses
            // Only broadcast to IPv4 (the concept of broadcasting is different for IPv6)
            if (broadcastAddress != QHostAddress::Null && entry.ip() != QHostAddress::LocalHost && entry.ip().protocol() == QAbstractSocket::IPv4Protocol) {

                // Broadcast to IPs that meet the criteria
                // Destination address = Broadcast address of this network segment
                // Destination port = 7788
                // Content = "Hello from JOOAN broadcast"
                // Effect: All devices on the same subnet receive the broadcast message
                // The system will use the corresponding network interface card/router to send the message based on the network segment to which the destination broadcast address belongs; the source
                // IP of the probe packet is usually the IP of that network interface card, and the return packet will return to the source IP along the same path.
                m_udpSocket->writeDatagram(datagram.data(), datagram.size(), entry.broadcast(), 7788);
            }
        }

        // ---Invalid code begin---
        QNetworkInterface::InterfaceFlags flagsCheck = QNetworkInterface::IsUp;
        flagsCheck |= QNetworkInterface::IsRunning;
        flagsCheck |= QNetworkInterface::CanMulticast;
        if (flagsCheck != (flagsCheck & netInterface.flags())) {
            continue;
        }
        // ---Invalid code end---
    }

    // Send the multicast one last time
    // Destination address = 234.235.236.237 (multicast address)
    // Destination port = 7788
    // Content is also "Hello from JOOAN broadcast"
    // When sending multicast, the source IP is the outgoing interface IP selected by the operating system, and the return packet naturally returns to the source IP.
    // Which devices receive it depends on whether the device has performed the "join multicast group" operation (the device usually joins this multicast address on a certain network card and listens
    // on port 7788).
    m_udpSocket->writeDatagram(datagram.data(), datagram.size(), QHostAddress("234.235.236.237"), 7788);
}