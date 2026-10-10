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

  public:
    ~ConfigureManager();

    static ConfigureManager* instance();

    Q_INVOKABLE static qint64 getCurrentMSecsSinceEpoch();
    Q_INVOKABLE static QString getMACAddrFirst(); //(保留旧的代码逻辑) 网卡列表中，获取使用中的第一张的MAC地址

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

  signals:
    void settingFilePathChanged();
    void languageTypeChanged();
    void networkCardChanged();

  private:
    explicit ConfigureManager(QObject* parent = nullptr);

  private:
    static ConfigureManager* m_instance;
    static QMutex            m_lock;

    QString m_settingFilePath;
};
