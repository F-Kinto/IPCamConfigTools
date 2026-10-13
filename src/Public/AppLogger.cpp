#pragma execution_character_set("utf-8")
#include "AppLogger.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QMutexLocker>
#include <QStandardPaths>
#include <QTextStream>

#include <cstdio>
#include <string>

#ifdef Q_OS_WIN
#include <windows.h>
#endif

namespace {
// 日志文件固定名称
const char* kLogFileName = "LogText.txt";

void outputToDebugConsole(const QString& record)
{
#ifdef Q_OS_WIN
    const wchar_t* wide = reinterpret_cast<const wchar_t*>(record.utf16());
    const DWORD    wideLen = static_cast<DWORD>(record.length());

    if (::IsDebuggerPresent()) {
        ::OutputDebugStringW((std::wstring(wide) + L"\n").c_str());
        return;
    }

    const HANDLE err = ::GetStdHandle(STD_ERROR_HANDLE);
    DWORD        written = 0;
    if (err != NULL && err != INVALID_HANDLE_VALUE
        && ::WriteConsoleW(err, wide, wideLen, &written, NULL)) {
        ::WriteConsoleW(err, L"\n", 1, &written, NULL);
        return;
    }
#endif
    std::fprintf(stderr, "%s\n", record.toLocal8Bit().constData());
    std::fflush(stderr);
}

QString levelName(QtMsgType type)
{
    switch (type) {
        case QtDebugMsg: return QStringLiteral("DEBUG");
        case QtInfoMsg: return QStringLiteral("INFO");
        case QtWarningMsg: return QStringLiteral("WARN");
        case QtCriticalMsg: return QStringLiteral("CRITICAL");
        case QtFatalMsg: return QStringLiteral("FATAL");
        default: return QStringLiteral("DEBUG");
    }
}
} // namespace

AppLogger* AppLogger::m_instance = nullptr;
QMutex     AppLogger::m_lock;

AppLogger::AppLogger(QObject* parent) : QObject(parent) {}

AppLogger::~AppLogger() {}

AppLogger* AppLogger::instance()
{
    QMutexLocker locker(&m_lock);
    if (!m_instance)
        m_instance = new AppLogger();
    return m_instance;
}

QString AppLogger::logFilePath()
{
    static QString path;
    if (!path.isEmpty())
        return path;

    // 优先放在程序目录（便携），程序目录不可写时回退到系统数据目录
    const QString appDir = QCoreApplication::applicationDirPath();
    QString       candidate = appDir + "/" + kLogFileName;
    QFile         file(candidate);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
        const QString fallbackDir = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
        QDir().mkpath(fallbackDir);
        candidate = fallbackDir + "/" + kLogFileName;
    } else {
        file.close();
    }
    path = candidate;
    return path;
}

void AppLogger::writeRecord(const QString& level, const QString& file, int line, const QString& function, const QString& text)
{
    static QMutex mutex;
    QMutexLocker  locker(&mutex);

    const QString time = QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd hh:mm:ss.zzz"));
    // 格式：[时间] [级别] [文件 : 行号 : 函数] 内容
    const QString record = QStringLiteral("[%1] [%2] [%3 : %4 : %5] %6")
                               .arg(time)
                               .arg(level)
                               .arg(file.isEmpty() ? QStringLiteral("<unknown file>") : file)
                               .arg(line)
                               .arg(function.isEmpty() ? QStringLiteral("<unknown function>") : function)
                               .arg(text);

    QFile out(logFilePath());
    if (out.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
        QTextStream stream(&out);
        stream.setCodec("UTF-8");
        stream << record << "\n";
        out.close();
    }

    // 同时输出到调试控制台（不经过 Qt 日志，避免递归调用消息处理器）。
    // 内部按场景选择：调试器 -> OutputDebugStringW；控制台 -> WriteConsoleW（Unicode，
    // 不受控制台 GBK 代码页影响）；重定向到文件/管道 -> 回退 UTF-8 字节
    outputToDebugConsole(record);
}

void AppLogger::write(const QString& file, int line, const QString& function, const QString& text)
{
    writeRecord(QStringLiteral("DEBUG"), file, line, function, text);
}

void AppLogger::messageHandler(QtMsgType type, const QMessageLogContext& context, const QString& msg)
{
    QString file;
    if (context.file) {
        file = QString::fromUtf8(context.file);
        // C++ 源文件只保留文件名；QML 保留原始路径（qrc:/qml/xxx.qml 或本地路径）
        if (!file.startsWith(QStringLiteral("qrc:")) && !file.endsWith(QStringLiteral(".qml")))
            file = QFileInfo(file).fileName();
    }
    const QString function = context.function ? QString::fromUtf8(context.function) : QString();

    writeRecord(levelName(type), file, context.line, function, msg);
}

void AppLogger::install()
{
    qInstallMessageHandler(AppLogger::messageHandler);
    qInfo().noquote() << QStringLiteral("=============== 程序启动 ===============");
    qInfo().noquote() << QStringLiteral("日志文件: %1").arg(logFilePath());
}
