#include "screentools.h"
#include "Log4qt/QALogmanger.h"
#include <cmath>
#include <thread>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <Windows.h>
#include <wingdi.h>
#include <WinUser.h>
#include <iphlpapi.h>
#include <QRect>
#include <QScreen>
#include <QFontMetrics>
#include <QNetworkInterface>
#include <QNetworkRequest>
#include <QProcess>
#include <QSslSocket>
#include <QAudioDeviceInfo>
#include <QQuickItem>
#include <QPixmap>
#include <QGuiApplication>

ScreenTools* ScreenTools::m_instance = nullptr;

#pragma comment(lib, "Iphlpapi.lib")
#pragma comment(lib, "Ws2_32.lib")

/**
 * @brief 通过 GetAdaptersAddresses 查询到的网卡附加信息
 */
struct AdapterInfo
{
    // 接口类型 IF_TYPE_*（iptypes.h），如 IF_TYPE_TUNNEL = 131
    quint32     ifType   = 0;
    // 网卡描述（IP_ADAPTER_ADDRESSES::Description，即 ipconfig /all 的 Description）
    QString     description;
    // 默认网关列表（IPv4 优先）
    QStringList gateways;
};

/**
 * @brief 查询各网卡的附加信息（Windows：GetAdaptersAddresses）
 * @return key = 网卡 IfIndex（QNetworkInterface::index()），value = 接口类型 + 网关列表
 */
static QMap<quint32, AdapterInfo> queryAdapterInfos()
{
    QMap<quint32, AdapterInfo> result;

    ULONG bufLen  = 15 * 1024;
    QByteArray    buffer;
    ULONG         ret = ERROR_BUFFER_OVERFLOW;
    for (int retry = 0; retry < 3 && ret == ERROR_BUFFER_OVERFLOW; ++retry) {
        buffer.resize(static_cast<int>(bufLen));
        auto* adapters = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
        // GAA_FLAG_INCLUDE_GATEWAYS 必须带上，否则 FirstGatewayAddress 为空，取不到默认网关
        ret = ::GetAdaptersAddresses(AF_UNSPEC,
                                     GAA_FLAG_INCLUDE_GATEWAYS | GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST
                                         | GAA_FLAG_SKIP_DNS_SERVER,
                                     nullptr, adapters, &bufLen);
        if (ret != NO_ERROR)
            continue;

        for (const IP_ADAPTER_ADDRESSES* adapter = adapters; adapter != nullptr; adapter = adapter->Next) {
            QStringList v4Gateways;
            QStringList v6Gateways;
            for (const IP_ADAPTER_GATEWAY_ADDRESS* gw = adapter->FirstGatewayAddress; gw != nullptr; gw = gw->Next) {
                const sockaddr* sa = gw->Address.lpSockaddr;
                if (!sa)
                    continue;
                char text[INET6_ADDRSTRLEN] = {0};
                if (sa->sa_family == AF_INET) {
                    auto* sin = reinterpret_cast<const sockaddr_in*>(sa);
                    if (::inet_ntop(AF_INET, &sin->sin_addr, text, sizeof(text)))
                        v4Gateways << QString::fromLatin1(text);
                } else if (sa->sa_family == AF_INET6) {
                    auto* sin6 = reinterpret_cast<const sockaddr_in6*>(sa);
                    if (::inet_ntop(AF_INET6, &sin6->sin6_addr, text, sizeof(text)))
                        v6Gateways << QString::fromLatin1(text);
                }
            }
            AdapterInfo info;
            info.ifType      = adapter->IfType;
            info.description = QString::fromWCharArray(adapter->Description);
            info.gateways    = v4Gateways + v6Gateways;
            result.insert(adapter->IfIndex, info);
        }
        break;
    }

    return result;
}

/**
 * @brief 判断网卡是否会显示在 ipconfig /all 中
 *
 * 与 ipconfig /all 保持一致，过滤掉以下几类：
 *  1) 回环口（Loopback Pseudo-Interface、Npcap Loopback 等）
 *  2) 隧道适配器 IF_TYPE_TUNNEL(131)：Teredo / 6to4 / ISATAP / IP-HTTPS
 *  3) 没有物理地址（MAC）的虚拟接口：Hyper-V vSwitch、Wi-Fi Direct 虚拟适配器等
 *     （已连接的 PPP/VPN 例外，ipconfig 会显示它们）
 *  4) 名称含"本地连接"的隐藏/虚拟连接（按需求隐藏）
 *
 * @param iface 待判断的网卡
 * @param info  该网卡的附加信息（接口类型等）
 * @return true 表示需要加入返回列表
 */
static bool isIpconfigVisible(const QNetworkInterface& iface, const AdapterInfo& info)
{
    // 1) 回环口不显示
    if (iface.flags().testFlag(QNetworkInterface::IsLoopBack))
        return false;

    // 2) 隧道适配器不显示
    if (info.ifType == IF_TYPE_TUNNEL)
        return false;

    // 3) 没有 MAC 地址的虚拟接口不显示
    const QString mac = iface.hardwareAddress();
    if (mac.isEmpty() || mac.compare(QStringLiteral("00:00:00:00:00:00"), Qt::CaseInsensitive) == 0) {
        const bool connectedPpp = (iface.type() == QNetworkInterface::Ppp)
                               && iface.flags().testFlag(QNetworkInterface::IsUp);
        if (!connectedPpp)
            return false;
    }

    // 4) 名称含"本地连接"的连接不加入列表（英文系统为 Local Area Connection）
    //    包括 ipconfig 中显示为"无线局域网适配器 本地连接* N"的无线承载网络虚拟适配器
    const QString readableName = iface.humanReadableName();
    if (readableName.contains(QStringLiteral("本地连接"), Qt::CaseInsensitive)
     || readableName.contains(QStringLiteral("Local Area Connection"), Qt::CaseInsensitive))
        return false;

    return true;
}

ScreenTools::ScreenTools(QObject* parent) : QObject(parent)
{
    reset();
}

ScreenTools::~ScreenTools() {}

bool ScreenTools::isDebug() const
{
    return m_isDebug;
}

void ScreenTools::setDebug(bool debug)
{
    isDebug(debug);
}

void ScreenTools::isDebug(bool debug)
{
    if (m_isDebug == debug)
        return;
    m_isDebug = debug;
    emit isDebugChanged();
}

ScreenTools* ScreenTools::instance()
{
    if (!m_instance)
        m_instance = new ScreenTools();
    return m_instance;
}

void ScreenTools::reset()
{
    m_mbxPixelRatio = getCurrentDevicePixelRatio();
    m_scaleInt      = static_cast<int>(m_mbxPixelRatio * 100) / 100;
    m_scaleFrac     = static_cast<int>(m_mbxPixelRatio * 100) % 100;
    getScreenWidHeight();
    m_fontFamily   = "Microsoft YaHei UI";
    m_isWin7System = getSystemIsWin7();
    getOutOfScreen();

#ifdef DEBUG
    isDebug(true);
#else
    isDebug(false);
#endif
}

qreal ScreenTools::getCurrentDevicePixelRatio() const
{
    HMODULE hUser32 = GetModuleHandleA("user32.dll");
    if (!hUser32) {
        hUser32 = LoadLibraryA("user32.dll");
        if (!hUser32)
            return 1.0;
    }
    if (hUser32) {
        typedef UINT(WINAPI * GetDpiForSystemFunc)();
        GetDpiForSystemFunc pGetDpiForSystem = (GetDpiForSystemFunc)GetProcAddress(hUser32, "GetDpiForSystem");

        if (pGetDpiForSystem) {
            UINT dpi = pGetDpiForSystem();
            if (dpi > 0) {
                auto scale = dpi / 96.0;
                return scale;
            }
        }
    }
    return 1.0;
}

qreal ScreenTools::getDevicePixelRatio() const
{
    auto scale = getCurrentDevicePixelRatio();
    return (scale < 1.5 && scale > 1.0) ? scale : 1.0;
}

QString ScreenTools::getLocalIpv4Address()
{
    QList<QHostAddress> ipAddressesList = QNetworkInterface::allAddresses();
    for (const QHostAddress& address : ipAddressesList) {
        if (address.protocol() == QAbstractSocket::IPv4Protocol) {
            return address.toString();
        }
    }
    return "";
}

/**
 * @brief 获取当前设备所有网卡信息
 *
 * 返回 QVariantList，每一项是一个 QVariantMap，字段如下：
 *  index              : int        网卡索引
 *  name               : QString    系统内部名称（Windows 下如 "以太网" 的适配名）
 *  displayName        : QString    展示名：网卡描述（不含 IP，便于下拉框直接展示）
 *  humanReadableName  : QString    可读名称（如 "以太网"）
 *  description        : QString    网卡描述（ipconfig /all 的 Description，如 "Intel(R) ... I219-V"）
 *  hardwareAddress    : QString    MAC 地址
 *  type               : int        QNetworkInterface::InterfaceType
 *  isUp               : bool       是否已启用
 *  isRunning          : bool       是否已连接并运行
 *  isLoopBack         : bool       是否回环网卡
 *  ipv4               : QStringList 该网卡上的所有 IPv4 地址
 *  ipv6               : QStringList 该网卡上的所有 IPv6 地址（已去掉作用域 id）
 *  netmask            : QString    首个 IPv4 地址对应的子网掩码
 *
 * 只返回 ipconfig /all 能看到的网卡：过滤回环口、隧道适配器（Teredo/6to4/ISATAP）、
 * 无 MAC 的虚拟接口，并隐藏名称含"本地连接"的连接（详见 isIpconfigVisible）
 *
 * @return 网卡信息列表
 */
QVariantList ScreenTools::getNetworkInterfaces()
{
    QVariantList result;

    // 接口类型与网关信息来自 GetAdaptersAddresses，key 为网卡 IfIndex
    const QMap<quint32, AdapterInfo> adapterInfos = queryAdapterInfos();

    const QList<QNetworkInterface> interfaces = QNetworkInterface::allInterfaces();
    for (const QNetworkInterface& iface : interfaces) {
        const AdapterInfo info = adapterInfos.value(static_cast<quint32>(iface.index()));

        // 只保留 ipconfig /all 会显示的网卡
        if (!isIpconfigVisible(iface, info))
            continue;

        QStringList ipv4List;
        QStringList ipv6List;
        QString     netmask;

        for (const QNetworkAddressEntry& entry : iface.addressEntries()) {
            const QHostAddress& addr = entry.ip();
            if (addr.protocol() == QAbstractSocket::IPv4Protocol) {
                ipv4List << addr.toString();
                if (netmask.isEmpty())
                    netmask = entry.netmask().toString();
            } else if (addr.protocol() == QAbstractSocket::IPv6Protocol) {
                // 去掉 IPv6 的作用域 id（如 fe80::1%12）
                QString ipv6 = addr.toString();
                const int scopeIndex = ipv6.indexOf('%');
                if (scopeIndex >= 0)
                    ipv6 = ipv6.left(scopeIndex);
                ipv6List << ipv6;
            }
        }

        const QString readableName = iface.humanReadableName();
        QVariantMap   item;
        item["index"]             = iface.index();
        item["name"]              = iface.name();
        item["humanReadableName"] = readableName;
        item["description"]       = info.description;
        item["hardwareAddress"]   = iface.hardwareAddress();
        item["type"]              = static_cast<int>(iface.type());
        item["isUp"]              = iface.flags().testFlag(QNetworkInterface::IsUp);
        item["isRunning"]         = iface.flags().testFlag(QNetworkInterface::IsRunning);
        item["isLoopBack"]        = iface.flags().testFlag(QNetworkInterface::IsLoopBack);
        item["ipv4"]              = ipv4List;
        item["ipv6"]              = ipv6List;
        item["netmask"]           = netmask;
        item["gatewayList"]       = info.gateways;
        item["gateway"]           = info.gateways.value(0, QString());
        // 展示名用网卡描述（ipconfig /all 的 Description，如 "Intel(R) Ethernet Connection I219-V"），
        // 描述取不到时回退到可读名称；不拼接 IP（IP 通过 ipv4 字段单独取）
        item["displayName"]       = !info.description.isEmpty() ? info.description
                                                               : (readableName.isEmpty() ? iface.name() : readableName);
        result << item;
    }

    return result;
}

/**
 * @brief 获取网卡展示名列表，可直接作为 ComboBox 的 model
 * @param onlyUp 为 true 时只返回已启用的网卡
 * @return 展示名列表，形如 "以太网 (192.168.1.100)"
 */
QStringList ScreenTools::getNetworkInterfaceNames(bool onlyUp)
{
    QStringList names;

    const QVariantList interfaces = getNetworkInterfaces();
    for (const QVariant& var : interfaces) {
        const QVariantMap item = var.toMap();
        if (onlyUp && !item.value("isUp").toBool())
            continue;
        names << item.value("displayName").toString();
    }

    return names;
}

// 文件内静态探测函数：isIpOccupied（同步版）与 checkIpOccupiedAsync（异步版）共用
static bool probeIpOccupied(const QString& ip)
{
    // 解析 IPv4 字符串，非法地址直接判为空闲并告警
    in_addr addr;
    if (::inet_pton(AF_INET, ip.toStdString().c_str(), &addr) != 1) {
        qWarning() << "probeIpOccupied: invalid IPv4 address:" << ip;
        return false;
    }

    // SendARP：有人应答则返回 NO_ERROR 并写入对方 MAC（IPAddr 即网络字节序 ULONG）
    ULONG macAddr[2] = {0}; // MAC 共 6 字节，用 2 个 ULONG 承载
    ULONG macLen     = sizeof(macAddr);
    return ::SendARP(static_cast<IPAddr>(addr.s_addr), 0, macAddr, &macLen) == NO_ERROR;
}

/**
 * @brief 通过 SendArp 判断指定 IPv4 地址是否被占用
 *
 * 向目标 IP 发送 ARP 请求：
 *  - 目标主机在线应答：SendArp 返回 NO_ERROR 并带回其 MAC 地址 → 该 IP 已被占用
 *  - 无人应答：SendArp 返回错误码（如 31 ERROR_GEN_FAILURE）→ 该 IP 空闲
 *
 * 目标是本机 IP 时也会带回本机 MAC（NO_ERROR），适用于检测 IP 冲突。
 * 注意：ARP 仅在本地网段内生效，跨网段地址会因路由不可达而判为空闲。
 *
 * @param ip IPv4 地址字符串，如 "192.168.1.100"
 * @return true = 被占用；false = 空闲（或 IP 格式非法，此时打印告警）
 */
bool ScreenTools::isIpOccupied(const QString& ip)
{
    return probeIpOccupied(ip);
}

/**
 * @brief 异步探测 IPv4 占用状态（不阻塞 UI 线程）
 *
 * SendARP 是同步阻塞调用（无人应答时会等待较久），直接在 QML 里调用会
 * 冻结界面与动画。此接口把探测放到 std::thread 后台执行，结果经
 * signalIpOccupied 信号回传：
 *   - 跨线程 emit：接收方在主线程时 Qt 自动以排队连接投递，槽/QML 处理仍回到主线程
 *   - 请求/响应靠 ip 字符串匹配，调用方应保存请求地址，回调时核对后再处理
 *
 * @param ip IPv4 地址字符串，如 "192.168.1.100"
 */
void ScreenTools::checkIpOccupiedAsync(const QString& ip)
{
    // 值拷贝进线程，避免引用外部字符串的生命周期问题
    QString ipCopy = ip;
    std::thread([this, ipCopy]() {
        bool occupied = probeIpOccupied(ipCopy);
        emit signalIpOccupied(ipCopy, occupied);
    }).detach();
}

/**
 * @brief 异步批量查找空闲 IP（不阻塞 UI 线程）
 *
 * 以 baseIp 为起点在其所在网段内按序探测，凑满 count 个空闲地址即止：
 *   1) 末段从 baseIp 的末段起逐个 +1 叠加，跳过被占用（ARP 有人应答）的地址，
 *      一直叠加到 .254（.255 为广播地址不参与）；
 *   2) 到 .254 仍不足 count 个，再从 baseIp 末段的下方逐个 -1 递减探测，直到 .1；
 *   3) 两条路都穷尽仍不足，返回已找到的部分（freeIps.size() < wanted）。
 *
 * 探测在线程内串行执行（每个 SendARP 无人应答时约百毫秒级），期间界面由调用方
 * 的遮罩提示等待。结果经 signalFreeIpsFound 回传，请求/响应靠 baseIp 字符串匹配，
 * 调用方应保存请求地址，回调时核对后再处理。
 *
 * @param baseIp 起始 IPv4 地址字符串，如 "192.168.5.193"（格式非法时回传空列表）
 * @param count  需要的空闲地址数量（<= 0 时回传空列表）
 */
void ScreenTools::findFreeIpsAsync(const QString& baseIp, int count)
{
    QString ipCopy = baseIp;
    std::thread([this, ipCopy, count]() {
        QStringList freeIps;
        int lastIdx = ipCopy.lastIndexOf('.');
        int start   = -1;
        if (lastIdx > 0 && count > 0)
            start = ipCopy.mid(lastIdx + 1).toInt();

        // 起始末段合法（1~254）才进入查找：.0 是网络地址、.255 是广播地址，不参与叠加
        if (lastIdx > 0 && count > 0 && start >= 1 && start <= 254) {
            const QString prefix = ipCopy.left(lastIdx + 1); // "a.b.c."
            // 升序：起始末段 .. 254
            for (int last = start; last <= 254 && freeIps.size() < count; ++last) {
                QString ip = prefix + QString::number(last);
                if (!probeIpOccupied(ip))
                    freeIps << ip;
            }
            // 降序：起始末段-1 .. 1（升序已穷尽还不够时才走这里）
            for (int last = start - 1; last >= 1 && freeIps.size() < count; --last) {
                QString ip = prefix + QString::number(last);
                if (!probeIpOccupied(ip))
                    freeIps << ip;
            }
        }
        emit signalFreeIpsFound(ipCopy, count, freeIps);
    }).detach();
}

bool ScreenTools::imageIsSvgSource(const QString& imageUrl)
{
    return imageUrl.endsWith(".svg", Qt::CaseInsensitive);
}

int ScreenTools::scaleNum(int originValue, bool isFont)
/**
 * @brief 根据屏幕缩放比例对原始数值进行缩放处理
 *
 * 当屏幕超出显示范围时，将数值缩放为原始值的一半；
 * 当未超出显示范围时，若为字体缩放则保持原始值不变，否则按缩放比例进行缩放。
 * 缩放比例仅在 (1.0, 1.5) 范围内生效，其余情况视为 1.0。
 *
 * @param originValue 原始数值
 * @param isFont 是否为字体缩放，为 true 时在未超出屏幕的情况下保持原始值不变
 * @return 缩放后的数值，经四舍五入取整
 */
{
    auto scaleFrac = ScreenTools::instance()->m_scaleFrac;
    auto scaleInt  = ScreenTools::instance()->m_scaleInt;
    auto scale2    = 1.0;
    if (scaleFrac > 0 && scaleFrac < 50) {
        scale2 = 1.25; // ScreenTools::instance()->m_mbxPixelRatio;
    }
    if (ScreenTools::instance()->m_outOfScreen) {
        if (isFont) {
            return qRound(originValue * ScreenTools::instance()->m_testScale * 0.8 / scale2);
        }
        return qRound(originValue * ScreenTools::instance()->m_testScale * 0.8);
    } else {
        if (isFont) {
            return qRound((originValue * ScreenTools::instance()->m_testScale) / scale2);
        }
        return qRound((originValue * ScreenTools::instance()->m_testScale));
    }
}

//

QString ScreenTools::getFormatString(const QString& str, int columnWidth, int fontSize, bool isBold)
{
    // 如果文本宽度未超过列宽，直接返回原文本
    if (calculateTextWidth(str, fontSize, isBold) <= columnWidth) {
        return str;
    }
    const QStringList parts = str.split(' ');
    if (parts.size() <= 1) {
        QString result = str;
        while (result.length() > 0 && calculateTextWidth(result + "...", fontSize, isBold) > columnWidth) {
            result = result.left(result.length() - 1);
        }
        return result + "...";
    }

    QString     truncatedStr = str;
    QStringList currentParts = parts;

    while (currentParts.size() > 1) {
        currentParts.removeLast();
        truncatedStr = currentParts.join(' ') + "...";
        if (calculateTextWidth(truncatedStr, 9, isBold) <= columnWidth) {
            return truncatedStr;
        }
    }

    // 递归处理单个单词的情况
    return getFormatString(parts.first(), columnWidth, fontSize, isBold);
}

bool ScreenTools::getSystemIsWin7()
{
    if (QSysInfo::productType() != "windows") {
        return false;
    }
    // Windows 7 内核版本号是 6.1
    QString kernelVersion = QSysInfo::kernelVersion();
    return kernelVersion.startsWith("6.1");
}

bool ScreenTools::hasAudioDevice()
{
    QList<QAudioDeviceInfo> list = QAudioDeviceInfo::availableDevices(QAudio::AudioOutput);
    return !list.isEmpty();
}

/**
 * @brief 检查当前屏幕尺寸是否超出最小要求
 * @return 返回布尔值，表示是否超出屏幕限制
 */
bool ScreenTools::getOutOfScreen()
{
    // 获取主屏幕对象
    QScreen* screen = QGuiApplication::primaryScreen();
    if (screen) {
        // 获取屏幕的几何尺寸
        QRect screenGeometry = screen->geometry();
        // 计算缩放后的屏幕宽度
        // 如果缩放比例的小数部分大于25，则使用缩放整数部分加1，否则使用缩放整数部分
        int scale       = (m_scaleFrac > 25 ? m_scaleInt + 1 : m_scaleInt);
        int screenWidth = screenGeometry.width() * scale;
        // 计算缩放后的屏幕高度
        int screenHeight = screenGeometry.height() * scale;
        m_testScale      = (qRound((screenGeometry.width() / 1920.0) * 100.0) / 100.0);
        if (screenWidth < 1920) {
            m_testScale = (qRound((1.0 / scale) * 100.0) / 100.0);
        }
        qDebug() << "ScreenTools::getOutOfScreen screenGeometry:" << screenGeometry << m_scaleInt << screenWidth;
        // 检查屏幕尺寸是否小于最小要求(1280x756)
        if (1280 > screenWidth || 756 > screenHeight) {
            // 如果超出限制，设置m_outOfScreen为true
            m_outOfScreen = true;
        }
    }
    // 返回屏幕是否超出限制的状态
    return m_outOfScreen;
}

const bool& ScreenTools::outOfScreen() const
{
    return m_outOfScreen;
}

void ScreenTools::getScreenWidHeight()
{
    QScreen* screen = QGuiApplication::primaryScreen();
    if (screen) {
        QRect screenGeometry = screen->geometry();
        int   width          = screenGeometry.width() * (m_scaleFrac > 25 ? m_scaleInt + 1 : m_scaleInt);
        int   height         = screenGeometry.height() * (m_scaleFrac > 25 ? m_scaleInt + 1 : m_scaleInt);

        m_screenWidth  = qMin(1344, width);
        m_screenHeight = qMin(756, height);
        emit signalScreenWidthChanged();
        emit signalScreenHeightChanged();
        setRectWidthScale();
        setRectHeightScale();
    }
}

/**
 * @brief 设置矩形宽度比例
 * 根据屏幕宽度调整矩形的缩放比例，并在值改变后发出信号
 */
void ScreenTools::setRectWidthScale()
{
    // 判断屏幕宽度是否小于1200像素
    if (m_screenWidth < 1200) {
        // 当屏幕宽度小于1200时，将比例设置为1.2（保留两位小数）
        m_rectWidthScale = std::round(1.2 * 100.0) / 100.0;
    } else {
        // 否则使用默认比例1.0
        m_rectWidthScale = 1.0;
    }
    // 发出矩形宽度比例改变的信号
    emit signalRectWidthScaleChanged();
}

void ScreenTools::setRectHeightScale()
{
    if (m_screenHeight < 756) {
        m_rectHeightScale = std::round(1.05 * 100.0) / 100.0;
    } else {
        m_rectHeightScale = 1.0;
    }
    emit signalRectHeightScaleChanged();
}

int ScreenTools::calculateMultiTextWidth(const QString& str1, const QString& str2, const QString& str3, const QString& str4, const int fontSize, bool bold, bool isPixelFont)
{
    QString maxStr = str1;
    QString max1   = str1.length() >= str2.length() ? str1 : str2;
    QString max2   = str3.length() >= str4.length() ? str3 : str4;
    maxStr         = max1.length() > max2.length() ? max1 : max2;
    return calculateTextWidth(maxStr, fontSize, bold, isPixelFont);
}

int ScreenTools::calculateMultiLineHeight(const QString& text, int fontSize, int maxWidth, bool isBold, bool isPixelFont)
{
    QFont font("Microsoft YaHei UI");
    if (isPixelFont)
        font.setPixelSize(fontSize > 0 ? fontSize : 10);
    else
        font.setPointSize(fontSize > 0 ? fontSize : 10);
    font.setBold(isBold);
    QFontMetrics fm(font);
    int          lineCount = calculateLineCount(text, font, maxWidth);
    return lineCount * (fm.height() + 5);
}

int ScreenTools::calculateTextWidth(const QString& text, int fontSize, bool isBold, bool isPixelFont)
{
    QFont font("Microsoft YaHei UI");
    if (isPixelFont)
        font.setPixelSize(fontSize > 0 ? fontSize : 10);
    else
        font.setPointSize(fontSize > 0 ? fontSize : 10);
    font.setBold(isBold);
    QFontMetrics fm(font);
    return fm.width(text);
}

int ScreenTools::calculateLineCount(const QString& text, const QFont& font, int maxWidth)
{
    if (text.isEmpty() || maxWidth <= 0) {
        return 0;
    }
    QFontMetrics fm(font);
    int          textHeight = fm.boundingRect(4, 4, maxWidth, 0, Qt::TextWrapAnywhere | Qt::AlignLeft, text).height();
    int          lineHeight = fm.height();
    return (textHeight + lineHeight - 1) / lineHeight; // 向上取整
}

QString ScreenTools::getLocalOuterIpv4Address()
{
    // 获取当前出口IP，防止频繁获取
    QString  outerIp = "";
    QProcess process;
    process.start("curl", QStringList() << "-s"
                                        << "ifconfig.me");

    if (!process.waitForFinished(3000)) {
        qWarning() << "Curl command timed out or failed";
        return QString();
    }
    if (process.exitCode() != 0) {
        qWarning() << "Curl failed with error:" << process.errorString();
        return QString();
    }
    QByteArray output = process.readAllStandardOutput();
    outerIp           = QString::fromUtf8(output).trimmed();
    return outerIp.isEmpty() ? getLocalIpv4Address() : outerIp;
}
