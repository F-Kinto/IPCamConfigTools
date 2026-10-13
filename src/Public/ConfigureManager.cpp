#pragma execution_character_set("utf-8")
// QueryValue 用到 Win32 版本信息 API（GetFileVersionInfoA 等），须先于 Qt 头包含
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
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
// 上次打开的“升级文件”目录
constexpr char UpgradeDirSetting[] = "AppSettings/UpgradeDir";

ConfigureManager* ConfigureManager::m_instance = nullptr;
QMutex            ConfigureManager::m_lock;

ConfigureManager::ConfigureManager(QObject* parent) : QObject(parent)
{
    init();
}

ConfigureManager::~ConfigureManager() {}

void ConfigureManager::init()
{

}

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

bool ConfigureManager::QueryValue(const std::string& ValueName, const std::string& szModuleName, std::string& RetStr)
{
    bool  bSuccess        = FALSE;
    BYTE* m_lpVersionData = NULL;
    DWORD m_dwLangCharset = 0;
    CHAR* tmpstr          = NULL;

    do {
        if (!ValueName.size() || !szModuleName.size())
            break;

        DWORD dwHandle;

        DWORD dwDataSize = ::GetFileVersionInfoSizeA((LPCSTR)szModuleName.c_str(), &dwHandle);
        if (dwDataSize == 0) {
            dwDataSize = GetLastError();
            break;
        }

        m_lpVersionData = new (std::nothrow) BYTE[dwDataSize];
        if (NULL == m_lpVersionData)
            break;

        if (!::GetFileVersionInfoA((LPCSTR)szModuleName.c_str(), dwHandle, dwDataSize, (void*)m_lpVersionData))
            break;

        UINT   nQuerySize;
        DWORD* pTransTable;

        if (!::VerQueryValueA(m_lpVersionData, "\\VarFileInfo\\Translation", (void**)&pTransTable, &nQuerySize))
            break;

        m_dwLangCharset = MAKELONG(HIWORD(pTransTable[0]), LOWORD(pTransTable[0]));
        if (m_lpVersionData == NULL)
            break;

        tmpstr = new (std::nothrow) CHAR[128];
        if (NULL == tmpstr)
            break;
        sprintf_s(tmpstr, 128, "\\StringFileInfo\\%08lx\\%s", m_dwLangCharset, ValueName.c_str());
        LPVOID lpData;

        if (::VerQueryValueA((void*)m_lpVersionData, tmpstr, &lpData, &nQuerySize))
            RetStr = (char*)lpData;

        bSuccess = TRUE;
    } while (FALSE);

    if (m_lpVersionData) {
        delete[] m_lpVersionData;
        m_lpVersionData = NULL;
    }
    if (tmpstr) {
        delete[] tmpstr;
        tmpstr = NULL;
    }

    return bSuccess;
}

qint64 ConfigureManager::getCurrentMSecsSinceEpoch()
{
    QMutexLocker lock(&m_lock);
    QDateTime    dateTime  = QDateTime::currentDateTime();
    QString      timestamp = dateTime.toString("yyyy-MM-dd hh:mm:ss.zzz");
    qint64       epochTime = dateTime.toMSecsSinceEpoch();
    return epochTime;
}

bool ConfigureManager::resetJsonObjValue(QJsonObject& rootObj)
{
    if (rootObj.isEmpty())
        return false;
    const auto  keys(rootObj.keys());
    QJsonObject tempObject;
    for (const auto& key : keys) {
        auto value = rootObj[key];
        switch (value.type()) {
            case QJsonValue::Bool:
                tempObject.insert(key, false);
                break;
            case QJsonValue::Double:
                tempObject.insert(key, 0.0);
                break;
            case QJsonValue::String:
                tempObject.insert(key, "");
                break;
            case QJsonValue::Array:
                tempObject.insert(key, QJsonValue(QJsonValue::Array));
                break;
            case QJsonValue::Object: {
                auto childJsonObj = value.toObject();
                resetJsonObjValue(childJsonObj);
                tempObject.insert(key, childJsonObj);
            } break;
            case QJsonValue::Null:
            case QJsonValue::Undefined:
            default:
                Q_ASSERT(false);
                break;
        }
    }
    rootObj = tempObject;
    return true;
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

void ConfigureManager::initAppDir()
{
    QDir dir;
    dir.setPath(qApp->applicationDirPath() + "/" + "TestDir/");
    if (!dir.exists())
        dir.mkdir(qApp->applicationDirPath() + "/" + "TestDir/");
}

QString ConfigureManager::getAppDir(const EnumNameSpace::AppDir& cmd)
{
    return qApp->applicationDirPath() + "/" + "TestDir/";
}

QString ConfigureManager::getDeviceUrl(const EnumNameSpace::DeviceQuestUrl& cmd)
{
    // URL 模板：%1 占位为设备 IP，调用方用 .arg(ip) 替换
    switch (cmd) {
        case EnumNameSpace::DeviceQuestUrl::eGetDeviceInfoList:
            return "http://%1/goform/getAPLanP2PSupport";
        case EnumNameSpace::DeviceQuestUrl::eGetDeviceFeatures:
            return "http://%1:9898/get?singleCMD=get_deviceFeatures";
        case EnumNameSpace::DeviceQuestUrl::eGetDeviceInfo:
            return "http://%1/goform/getOtherSetttings?singleCMD=get_data_json&userid=admin&userkey=0192023a7bbd73250516f069df18b500&json_string=DeviceInfo";
        case EnumNameSpace::DeviceQuestUrl::eGetJsonConfUrlWifi:
            return "http://%1/goform/getOtherSetttings?singleCMD=get_data_json&userid=admin&userkey=0192023a7bbd73250516f069df18b500&json_string=Wifi";
        case EnumNameSpace::DeviceQuestUrl::eGetRtspInfoUrl:
            return "http://%1/goform/getOtherSetttings?singleCMD=RtspConf&userid=admin&userkey=0192023a7bbd73250516f069df18b500";
        default:
            return "";
    }
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

QString ConfigureManager::upgradeDir() const
{
    QSettings settings(networkCardConfigPath(), QSettings::IniFormat);
    settings.setIniCodec("UTF-8");
    // 没选过时返回空串，由调用方决定默认目录
    return settings.value(UpgradeDirSetting, QString()).toString();
}

void ConfigureManager::setUpgradeDir(const QString& dir)
{
    const QString newValue = dir.trimmed();
    if (upgradeDir() == newValue)
        return;

    QSettings settings(networkCardConfigPath(), QSettings::IniFormat);
    settings.setIniCodec("UTF-8");
    settings.setValue(UpgradeDirSetting, newValue);
    settings.sync();
    emit upgradeDirChanged();
}
