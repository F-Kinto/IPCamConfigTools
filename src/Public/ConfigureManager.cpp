#pragma execution_character_set("utf-8")
#include "ConfigureManager.h"
#include <QFile>
#include <QFileInfo>
#include <QDateTime>
#include <QSettings>
#include <QObject>
#include <QCoreApplication>
#include <QDir>
#include <QNetworkInterface>
#include <QStandardPaths>

// 语言设置键
constexpr char LanguageSetting[] = "AppSettings/Language";
// 网卡设置键
constexpr char NetworkCardSetting[] = "AppSettings/NetworkCard";
// 选中“所有网卡”时写入配置文件的内容
constexpr char AllNetCard[] = "All netCard";

ConfigureManager* ConfigureManager::m_instance = nullptr;
QMutex            ConfigureManager::m_lock;

ConfigureManager::ConfigureManager(QObject* parent) : QObject(parent) {}

ConfigureManager::~ConfigureManager() {}

ConfigureManager* ConfigureManager::instance()
{
    m_lock.lock();
    if (!m_instance)
        m_instance = new ConfigureManager();
    m_lock.unlock();
    return m_instance;
}

void ConfigureManager::loadConfigureFile(const QString& configureFilePath)
{
    Q_ASSERT(!configureFilePath.isEmpty());
    QFileInfo fileInfo(configureFilePath);
    m_settingFilePath = configureFilePath;
    //// 检查配置文件是否存在，如果不存在，就创建它
    QFile file(m_settingFilePath);
    if (!file.exists()) {
        file.open(QIODevice::WriteOnly);
        file.close();
    }
    emit settingFilePathChanged();
}

qint64 ConfigureManager::getCurrentMSecsSinceEpoch()
{
    QMutexLocker lock(&m_lock);
    QDateTime    dateTime = QDateTime::currentDateTime();
    return dateTime.toMSecsSinceEpoch();
}

QString ConfigureManager::getMACAddrFirst()
{
    QString                  strMac;
    QList<QNetworkInterface> iFaces = QNetworkInterface::allInterfaces();
    for (int i = 0; i < iFaces.count(); i++) {
        QNetworkInterface iface = iFaces.at(i);
        if (iface.flags().testFlag(QNetworkInterface::IsUp) && iface.flags().testFlag(QNetworkInterface::IsRunning) && !iface.flags().testFlag(QNetworkInterface::IsLoopBack)) {
            for (int j = 0; j < iface.addressEntries().count(); j++) {
                strMac = iface.hardwareAddress();
                return strMac;
            }
        }
    }
    return strMac;
}

QString ConfigureManager::settingFilePath() const
{
    return m_settingFilePath;
}

bool ConfigureManager::isHasSetLanguage() const
{
    QSettings settings;
    return settings.contains(LanguageSetting);
}

int ConfigureManager::languageType() const
{
    QSettings settings;
    return settings.value(LanguageSetting, static_cast<int>(EnumNameSpace::LanguageType::eEnglish)).toInt();
}

void ConfigureManager::setLanguageType(int type)
{
    QSettings settings;
    if (settings.value(LanguageSetting, -1).toInt() == type)
        return;
    settings.setValue(LanguageSetting, type);
    emit languageTypeChanged();
}

QString ConfigureManager::networkCardConfigPath() const
{
    // 配置文件放在程序目录下（便携优先），程序目录不可写时回退到系统配置目录
    static QString configPath;
    if (!configPath.isEmpty())
        return configPath;

    const QString appDir = QCoreApplication::applicationDirPath();
    QString       path   = appDir + "/config.ini";
    // 以读写方式打开：文件不存在且目录可写时会自动创建；目录不可写则打开失败
    QFile file(path);
    if (!file.open(QIODevice::ReadWrite)) {
        const QString fallbackDir = QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation);
        QDir().mkpath(fallbackDir);
        path = fallbackDir + "/config.ini";
    } else {
        file.close();
    }
    configPath = path;
    return configPath;
}

QString ConfigureManager::defaultNetworkCard() const
{
    return QString(AllNetCard);
}

QString ConfigureManager::networkCard() const
{
    QSettings settings(networkCardConfigPath(), QSettings::IniFormat);
    settings.setIniCodec("UTF-8");
    // 首次运行（无配置）时按“所有网卡”处理
    return settings.value(NetworkCardSetting, defaultNetworkCard()).toString();
}

void ConfigureManager::setNetworkCard(const QString& name)
{
    // 空值按“所有网卡”处理，保证配置文件里始终是一个明确的网卡名
    const QString newValue = name.isEmpty() ? defaultNetworkCard() : name;
    if (networkCard() == newValue)
        return;

    QSettings settings(networkCardConfigPath(), QSettings::IniFormat);
    settings.setIniCodec("UTF-8");
    settings.setValue(NetworkCardSetting, newValue);
    settings.sync();
    emit networkCardChanged();
}
