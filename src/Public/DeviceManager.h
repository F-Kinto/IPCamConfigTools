/*********************************************************************
File : DeviceManager.h
Module : Public
date : 2026/10/10
Ver : 1.1.0
History:
1.0.0 build this module
1.1.0 新增 waitForLiveStreamsExit()：退出程序前 QML 同步调用，
      阻塞等待所有 RTSP 拉流线程真实退出（转发 RtspLiveTask 静态接口）
********************************************************************/
#pragma once
#include <QMap>
#include <QObject>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

/**
 * @brief 一台设备的完整信息
 *
 * 字段与设备表格列、广播回包解析结果（DeviceScanner::slotHandleLanDevice）一一对应。
 * 界面勾选设备时按 uid 存进 DeviceManager，供“批量操作 / 单台操作”直接取用，
 * 不再依赖表格行号（行号会随排序、重新搜索而变化）。
 */
struct DeviceInfo {
    QString uid;            /**< 设备唯一标识（DeviceUID）；为空时由 mac / ip 兜底做 key */
    QString ip;             /**< IP 地址 */
    QString mac;            /**< 物理地址 */
    QString deviceType;     /**< 设备类型（产品名） */
    QString currentVersion; /**< 升级当前版本号 */
    QString targetVersion;  /**< 升级后版本号 */
    QString osdTitle;       /**< OSD 标题 */
    QString status;         /**< 状态信息 */
    QString companyName;    /**< 厂家名（附加信息） */
    QString systemModel;    /**< 系统型号（附加信息） */
    QString rtspUserName;   /**< RTSP 认证用户名（HTTP 接口获取，空则用默认 admin） */
    QString rtspPassword;   /**< RTSP 认证密码（HTTP 接口获取，空则用默认空密码） */

    /**
     * @brief 是否是一条有效设备信息（uid / mac / ip 三者至少有一个非空）
     */
    bool isValid() const {
        return !uid.isEmpty() || !mac.isEmpty() || !ip.isEmpty();
    }

    /**
     * @brief 转成 QVariantMap，方便直接给 QML 使用
     */
    QVariantMap toVariantMap() const {
        QVariantMap map;
        map["uid"]            = uid;
        map["ip"]             = ip;
        map["mac"]            = mac;
        map["deviceType"]     = deviceType;
        map["currentVersion"] = currentVersion;
        map["targetVersion"]  = targetVersion;
        map["osdTitle"]       = osdTitle;
        map["status"]         = status;
        map["companyName"]    = companyName;
        map["systemModel"]    = systemModel;
        map["rtspUserName"]   = rtspUserName;
        map["rtspPassword"]   = rtspPassword;
        return map;
    }

    /**
     * @brief 由 QML 传来的设备字典构造（缺字段按空串处理）
     */
    static DeviceInfo fromVariantMap(const QVariantMap& map) {
        DeviceInfo info;
        info.uid            = map.value("uid").toString();
        info.ip             = map.value("ip").toString();
        info.mac            = map.value("mac").toString();
        info.deviceType     = map.value("deviceType").toString();
        info.currentVersion = map.value("currentVersion").toString();
        info.targetVersion  = map.value("targetVersion").toString();
        info.osdTitle       = map.value("osdTitle").toString();
        info.status         = map.value("status").toString();
        info.companyName    = map.value("companyName").toString();
        info.systemModel    = map.value("systemModel").toString();
        info.rtspUserName   = map.value("rtspUserName").toString();
        info.rtspPassword   = map.value("rtspPassword").toString();

        return info;
    }
};

/**
 * @brief 设备的 RTSP 认证凭据（HTTP 接口预取后缓存）
 */
struct RtspCredential {
    QString userName; /**< RTSP 用户名（接口返回的 user 字段） */
    QString password; /**< RTSP 密码（接口返回的 key 字段） */
};

/**
 * @brief 界面选中设备的管理者（单例，注册为 QML 的 DeviceManager）
 *
 * 职责：
 * 1) 勾选（可多选）的设备按 uid 存进 QMap<QString, DeviceInfo>，供批量操作取用；
 * 2) 当前选中（表格浅蓝高亮）的那一条单独存一份，供单台操作取用；
 * 3) 只认设备本身，不认行号 —— 排序 / 重新搜索都不会让这份数据错位。
 */
class DeviceManager : public QObject {
    Q_OBJECT
    // 已勾选设备的数量
    Q_PROPERTY(int checkedCount READ checkedCount NOTIFY checkedDevicesChanged)
    // 已勾选设备的 uid 列表（QMap 按 uid 升序）
    Q_PROPERTY(QStringList checkedUids READ checkedUids NOTIFY checkedDevicesChanged)
    // 当前选中设备的 uid（没有选中时为空串）
    Q_PROPERTY(QString currentUid READ currentUid NOTIFY currentDeviceChanged)
    // 当前选中设备的完整信息（没有选中时为空字典）
    Q_PROPERTY(QVariantMap currentDevice READ currentDeviceMap NOTIFY currentDeviceChanged)
    // 直播中的设备列表（按加入时间排序，每项为 QVariantMap）
    Q_PROPERTY(QVariantList liveDevices READ liveDevicesMap NOTIFY liveDevicesChanged)
    // 直播中的设备数量
    Q_PROPERTY(int liveCount READ liveCount NOTIFY liveDevicesChanged)

  public:
    /**
     * @brief 单例
     */
    static DeviceManager* instance();
    ~DeviceManager();

    int         checkedCount() const;
    QStringList checkedUids() const;
    QString     currentUid() const;
    QVariantMap currentDeviceMap() const;

    /**
     * @brief 勾选一台设备（已存在则更新信息）
     * @param device 设备信息字典，字段见 DeviceInfo
     */
    Q_INVOKABLE void setCheckedDevice(const QVariantMap& device);

    /**
     * @brief 取消勾选一台设备
     */
    Q_INVOKABLE void removeCheckedDevice(const QString& uid);

    /**
     * @brief 清空所有勾选（重新搜索、清空列表时调用）
     */
    Q_INVOKABLE void clearCheckedDevices();

    /**
     * @brief 指定 uid 的设备是否已勾选
     */
    Q_INVOKABLE bool isChecked(const QString& uid) const;

    /**
     * @brief 取一台已勾选设备的完整信息（未勾选时返回空字典）
     */
    Q_INVOKABLE QVariantMap checkedDevice(const QString& uid) const;

    /**
     * @brief 取全部已勾选设备的信息列表（按 uid 升序；每项为 QVariantMap）
     */
    Q_INVOKABLE QVariantList checkedDevices() const;

    /**
     * @brief 整体同步勾选集合：以传入的设备列表为准，多的删、少的补
     * @param devices 界面当前勾选的设备信息列表
     */
    Q_INVOKABLE void syncCheckedDevices(const QVariantList& devices);

    /**
     * @brief 设置当前选中的那条设备（单台操作读它）
     */
    Q_INVOKABLE void setCurrentDevice(const QVariantMap& device);

    /**
     * @brief 清空当前选中的设备
     */
    Q_INVOKABLE void clearCurrentDevice();

    /**
     * @brief 取设备 key：uid 优先，为空时依次用 mac、ip 兜底
     */
    Q_INVOKABLE QString keyOf(const QVariantMap& device) const;

    /**
     * @brief 把一台设备加入直播列表（双击设备行时调用）
     *
     * 已在列表中的设备更新信息后保持原位置；列表按加入时间排序。
     * @param device 设备信息字典，ip 为空时不加入
     */
    Q_INVOKABLE void addLiveDevice(const QVariantMap& device);

    /**
     * @brief 把一台设备移出直播列表（直播窗口点关闭时调用）
     */
    Q_INVOKABLE void removeLiveDevice(const QString& uid);

    /**
     * @brief 清空直播列表（关闭所有窗口 / 重新搜索时调用）
     */
    Q_INVOKABLE void clearLiveDevices();

    /**
     * @brief 阻塞等待所有 RTSP 拉流线程退出（退出程序前由 QML 调用）
     *
     * 关直播页签/程序时先触发各路 stopAndDeleteLater（发停止标记），
     * 再调用本接口等 init + recv 视频/音频线程真实退出，避免进程
     * 拆除时线程仍在跑而崩溃。会阻塞 GUI（用户已确认退出，短暂冻结
     * 属预期），无任务在跑时立即返回。
     *
     * @param timeoutMs 最长等待毫秒数
     * @return true=全部退出；false=超时兜底（记日志后仍可退出）
     */
    Q_INVOKABLE bool waitForLiveStreamsExit(int timeoutMs);

    /**
     * @brief 取直播设备列表（按加入时间排序，每项为 QVariantMap）
     */
    QVariantList liveDevicesMap() const;

    /**
     * @brief 直播设备数量
     */
    int liveCount() const;

    /**
     * @brief 异步获取设备的 RTSP 认证凭据（用户名/密码）
     *
     * 通过 HTTP 接口（eGetRtspInfoUrl）向设备请求，成功后写入内部缓存
     * （设备 key -> 用户名/密码），并发出 rtspCredentialFetched 信号；失败时
     * 同样发信号（凭据字段为空串，调用方按默认值处理）。内部用 QtConcurrent
     * 工作线程执行，不阻塞 GUI 线程。同一设备在请求期间重复调用会被去重。
     * @param device 设备信息字典，至少包含 ip 字段
     */
    Q_INVOKABLE void fetchRtspCredential(const QVariantMap& device);

    /**
     * @brief 把缓存的 RTSP 凭据合并进设备字典
     *
     * 设备发现时（fetchRtspCredential）预取的凭据存在缓存里；播放前调本方法
     * 把 rtspUserName/rtspPassword 合并进设备字典，第一次起流即带真实凭据。
     * @param device 设备信息字典
     * @return 带凭据字段的设备字典（无缓存时原样返回）
     */
    Q_INVOKABLE QVariantMap mergeRtspCredential(const QVariantMap& device) const;

  signals:
    void checkedDevicesChanged();
    void currentDeviceChanged();
    void liveDevicesChanged();
    /**
     * @brief RTSP 凭据获取完成（无论成败都发一次）
     * @param device 设备字典：原字段 + rtspUserName/rtspPassword（失败时为空串）
     */
    void rtspCredentialFetched(const QVariantMap& device);

  private:
    explicit DeviceManager(QObject* parent = nullptr);

    static DeviceManager*        m_instance;       /**< 单例指针 */
    QMap<QString, DeviceInfo>    m_checkedDevices; /**< 勾选的设备：uid -> 设备信息 */
    DeviceInfo                   m_currentDevice;  /**< 当前选中的那一条 */
    bool                         m_hasCurrent;     /**< 是否有当前选中项 */
    QList<DeviceInfo>            m_liveDevices;    /**< 直播中的设备（按加入时间排序） */
    QSet<QString>                m_pendingRtsp;    /**< 正在获取 RTSP 凭据的设备 key 集合（去重） */
    QMap<QString, RtspCredential> m_rtspCredentials; /**< RTSP 凭据缓存：设备 key -> 用户名/密码 */
};
