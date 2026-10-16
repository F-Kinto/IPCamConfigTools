/*********************************************************************
File : ConfigureManager.h
Module : tools
Authors: guangnan
date : 2023/03/07 16:00
Ver : 1.0.0
History:
guangnan 2023/03/07 1.0.0 build this module
********************************************************************/
#pragma once

#include <QObject>
#include <QMutex>
#include <QJsonObject>
#include <QString>
#include <string>
#include "GlobalEnum.h"

class ConfigureManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString settingFilePath READ settingFilePath NOTIFY settingFilePathChanged)
    Q_PROPERTY(int languageType READ languageType WRITE setLanguageType NOTIFY languageTypeChanged)
    Q_PROPERTY(bool hasSetLanguage READ isHasSetLanguage NOTIFY languageTypeChanged)
    // 上次选择的网卡名（持久化到本地 ini，选中“所有网卡”时写入 "All netCard"）
    Q_PROPERTY(QString networkCard READ networkCard WRITE setNetworkCard NOTIFY networkCardChanged)
    // 上次打开“升级文件”选择框时所在的目录（持久化到本地 ini，供下次打开时默认定位）
    Q_PROPERTY(QString upgradeDir READ upgradeDir WRITE setUpgradeDir NOTIFY upgradeDirChanged)

  public:
    ~ConfigureManager();

    static ConfigureManager* instance();

    Q_INVOKABLE static qint64 getCurrentMSecsSinceEpoch();
    Q_INVOKABLE static QString getMACAddrFirst(); //(保留旧的代码逻辑) 网卡列表中，获取使用中的第一张的MAC地址
    Q_INVOKABLE static QString getDeviceUrl(const EnumNameSpace::DeviceQuestUrl& cmd);
    Q_INVOKABLE static QString getDeviceSetUrl(int cmd);

    Q_INVOKABLE void loadConfigureFile(const QString& configureFilePath);

    QString settingFilePath() const;

    // 语言设置（持久化到 QSettings，供 TranslatorManager / QML 使用）
    Q_INVOKABLE bool isHasSetLanguage() const;
    Q_INVOKABLE int  languageType() const;
    Q_INVOKABLE void setLanguageType(int type);

    // 网卡名称（持久化到本地 ini 配置文件）
    // 配置文件路径：程序目录下 config.ini，程序目录不可写时回退到系统配置目录
    Q_INVOKABLE QString networkCardConfigPath() const;
    // 选中“所有网卡”时写入配置文件的固定内容
    Q_INVOKABLE QString defaultNetworkCard() const;

    QString networkCard() const;
    void    setNetworkCard(const QString& name);

    // 上次选择的升级文件目录（本地路径，如 "C:/Firmware"）；为空表示还没选过
    QString upgradeDir() const;
    void    setUpgradeDir(const QString& dir);

  signals:
    void settingFilePathChanged();
    void languageTypeChanged();
    void networkCardChanged();
    void upgradeDirChanged();

  private:
    explicit ConfigureManager(QObject* parent = nullptr);
    void init();
    bool QueryValue(const std::string& ValueName, const std::string& szModuleName, std::string& RetStr);
    // 递归把 JSON 对象里的所有值重置为类型对应的零值
    bool resetJsonObjValue(QJsonObject& rootObj);
    // 初始化（并按需创建）程序目录下的工作目录
    void    initAppDir();
    QString getAppDir(const EnumNameSpace::AppDir& cmd);

  private:
    static ConfigureManager* m_instance;
    static QMutex            m_lock;

    QString m_settingFilePath;
};

#define CONFIGUREMANAGER_INSTANCE ConfigureManager::instance()
