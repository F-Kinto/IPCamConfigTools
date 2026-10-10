/*********************************************************************
File : AppLogger.h
Module : tools
date : 2026/10/08
Ver : 1.0.0
History:
1.0.0 build this module
********************************************************************/
#pragma once

#include <QMutex>
#include <QObject>
#include <QString>
#include <QtGlobal>

// 应用日志：接管 Qt 全局消息（C++ 的 qDebug/qInfo 与 QML 的 console.log），
// 统一追加写入 LogText.txt，每条包含：触发时间、级别、文件、函数、行号、内容
//
// C++ 侧的文件/函数/行号由 QMessageLogContext 提供；
// QML 侧由 logAction() 从调用栈解析出调用方位置后，通过 write() 传入。
class AppLogger : public QObject {
    Q_OBJECT

  public:
    ~AppLogger();

    static AppLogger* instance();

    // 安装全局消息处理器，并写出一行启动日志（含日志文件路径）
    static void install();
    // 日志文件路径（程序目录不可写时回退到系统数据目录）
    static QString logFilePath();

    // 供 QML 调用：写一条日志，位置信息由 QML 传入（file 如 "main.qml"，line 为行号）
    Q_INVOKABLE void write(const QString& file, int line, const QString& function, const QString& text);

  private:
    explicit AppLogger(QObject* parent = nullptr);

    static void messageHandler(QtMsgType type, const QMessageLogContext& context, const QString& msg);
    static void writeRecord(const QString& level, const QString& file, int line, const QString& function, const QString& text);

  private:
    static AppLogger* m_instance;
    static QMutex     m_lock;
};
