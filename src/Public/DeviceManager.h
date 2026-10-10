/*********************************************************************
File : DeviceManager.h
Module : Public
date : 2026/10/10
Ver : 1.0.0
History:
1.0.0 build this module
********************************************************************/
#pragma once
#include <QMap>
#include <QObject>
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
    QString cloudId;        /**< 云ID（表格里显示的就是 DeviceUID） */
    QString deviceType;     /**< 设备类型（产品名） */
    QString currentVersion; /**< 升级当前版本号 */
    QString targetVersion;  /**< 升级后版本号 */
    QString osdTitle;       /**< OSD 标题 */
    QString status;         /**< 状态信息 */
    QString companyName;    /**< 厂家名（附加信息） */
    QString systemModel;    /**< 系统型号（附加信息） */

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
        map["cloudId"]        = cloudId;
        map["deviceType"]     = deviceType;
        map["currentVersion"] = currentVersion;
        map["targetVersion"]  = targetVersion;
        map["osdTitle"]       = osdTitle;
        map["status"]         = status;
        map["companyName"]    = companyName;
        map["systemModel"]    = systemModel;
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
        info.cloudId        = map.value("cloudId").toString();
        info.deviceType     = map.value("deviceType").toString();
        info.currentVersion = map.value("currentVersion").toString();
        info.targetVersion  = map.value("targetVersion").toString();
        info.osdTitle       = map.value("osdTitle").toString();
        info.status         = map.value("status").toString();
        info.companyName    = map.value("companyName").toString();
        info.systemModel    = map.value("systemModel").toString();
        // 表格里的“云ID”列就是 uid，个别设备 uid 为空时用它兜底
        if (info.uid.isEmpty())
            info.uid = info.cloudId;

        return info;
    }
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
     * @brief 取设备 key：uid 优先，为空时依次用 cloudId、mac、ip 兜底
     */
    Q_INVOKABLE QString keyOf(const QVariantMap& device) const;

  signals:
    void checkedDevicesChanged();
    void currentDeviceChanged();

  private:
    explicit DeviceManager(QObject* parent = nullptr);

    static DeviceManager*        m_instance;       /**< 单例指针 */
    QMap<QString, DeviceInfo>    m_checkedDevices; /**< 勾选的设备：uid -> 设备信息 */
    DeviceInfo                   m_currentDevice;  /**< 当前选中的那一条 */
    bool                         m_hasCurrent;     /**< 是否有当前选中项 */
};
