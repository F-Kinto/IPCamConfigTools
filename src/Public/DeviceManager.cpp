#pragma execution_character_set("utf-8")
#include "DeviceManager.h"
#include <QDebug>

DeviceManager* DeviceManager::m_instance = nullptr;

DeviceManager* DeviceManager::instance()
{
    if (!m_instance)
        m_instance = new DeviceManager();
    return m_instance;
}

DeviceManager::DeviceManager(QObject* parent)
    : QObject(parent), m_hasCurrent(false)
{
}

DeviceManager::~DeviceManager()
{
    m_instance = nullptr;
}

int DeviceManager::checkedCount() const
{
    return m_checkedDevices.size();
}

QStringList DeviceManager::checkedUids() const
{
    return m_checkedDevices.keys();
}

QString DeviceManager::currentUid() const
{
    return m_hasCurrent ? m_currentDevice.uid : QString();
}

QVariantMap DeviceManager::currentDeviceMap() const
{
    return m_hasCurrent ? m_currentDevice.toVariantMap() : QVariantMap();
}

void DeviceManager::setCheckedDevice(const QVariantMap& device)
{
    const DeviceInfo info = DeviceInfo::fromVariantMap(device);
    if (!info.isValid())
        return;

    const QString key = keyOf(device);
    if (key.isEmpty())
        return;

    // uid 为空时用实际 key 兜底，保证后续按 uid 取值与 key 一致
    DeviceInfo stored = info;
    if (stored.uid.isEmpty())
        stored.uid = key;

    const bool isNew = !m_checkedDevices.contains(key);
    m_checkedDevices.insert(key, stored);

    if (isNew)
        emit checkedDevicesChanged();
}

void DeviceManager::removeCheckedDevice(const QString& uid)
{
    if (m_checkedDevices.remove(uid) == 0)
        return;

    emit checkedDevicesChanged();
}

void DeviceManager::clearCheckedDevices()
{
    if (m_checkedDevices.isEmpty())
        return;

    m_checkedDevices.clear();
    emit checkedDevicesChanged();
}

bool DeviceManager::isChecked(const QString& uid) const
{
    return m_checkedDevices.contains(uid);
}

QVariantMap DeviceManager::checkedDevice(const QString& uid) const
{
    const auto it = m_checkedDevices.constFind(uid);
    if (it == m_checkedDevices.constEnd())
        return QVariantMap();

    return it.value().toVariantMap();
}

QVariantList DeviceManager::checkedDevices() const
{
    QVariantList list;
    for (auto it = m_checkedDevices.constBegin(); it != m_checkedDevices.constEnd(); ++it)
        list << it.value().toVariantMap();

    return list;
}

void DeviceManager::syncCheckedDevices(const QVariantList& devices)
{
    QMap<QString, DeviceInfo> newMap;
    for (const QVariant& item : devices) {
        const QVariantMap map  = item.toMap();
        const QString     key  = keyOf(map);
        if (key.isEmpty())
            continue;

        DeviceInfo info = DeviceInfo::fromVariantMap(map);
        if (!info.isValid())
            continue;

        if (info.uid.isEmpty())
            info.uid = key;

        newMap.insert(key, info);
    }

    // 内容没变就不抛信号，避免界面无谓刷新
    if (newMap.keys() == m_checkedDevices.keys()) {
        bool same = true;
        for (auto it = newMap.constBegin(); it != newMap.constEnd(); ++it) {
            if (it.value().toVariantMap() != m_checkedDevices.value(it.key()).toVariantMap()) {
                same = false;
                break;
            }
        }
        if (same)
            return;
    }

    m_checkedDevices = newMap;
    emit checkedDevicesChanged();
}

void DeviceManager::setCurrentDevice(const QVariantMap& device)
{
    const DeviceInfo info = DeviceInfo::fromVariantMap(device);
    if (!info.isValid()) {
        clearCurrentDevice();
        return;
    }

    const QString key = keyOf(device);
    DeviceInfo    stored = info;
    if (stored.uid.isEmpty())
        stored.uid = key;

    // 同一台设备重复设置不抛信号
    if (m_hasCurrent && m_currentDevice.uid == stored.uid && m_currentDevice.toVariantMap() == stored.toVariantMap())
        return;

    m_currentDevice = stored;
    m_hasCurrent    = true;
    emit currentDeviceChanged();
}

void DeviceManager::clearCurrentDevice()
{
    if (!m_hasCurrent)
        return;

    m_currentDevice = DeviceInfo();
    m_hasCurrent    = false;
    emit currentDeviceChanged();
}

QString DeviceManager::keyOf(const QVariantMap& device) const
{
    QString key = device.value("uid").toString();
    if (key.isEmpty())
        key = device.value("cloudId").toString();
    if (key.isEmpty())
        key = device.value("mac").toString();
    if (key.isEmpty())
        key = device.value("ip").toString();

    return key;
}
