#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlEngine>
#include <QJSEngine>
#include <QQuickStyle>
#include <QUrl>

#include "Public/AppLogger.h"
#include "Public/ConfigureManager.h"
#include "Public/DeviceManager.h"
#include "Public/DeviceScanner.h"
#include "Public/TranslatorManager.h"
#include "Public/screentools.h"

// 把单例对象注册成 QML 类型（模块 IPCam.Public 1.0）
template <typename T>
static void registerSingleton(const char* name)
{
    qmlRegisterSingletonType<T>(
        "IPCam.Public", 1, 0, name,
        [](QQmlEngine* qmlEngine, QJSEngine*) -> QObject* {
            T* obj = T::instance();
            qmlEngine->setObjectOwnership(obj, QQmlEngine::CppOwnership);
            return obj;
        });
}

int main(int argc, char* argv[]) {
    QGuiApplication app(argc, argv);
    app.setOrganizationName("IPCamConfigTools");
    app.setApplicationName("IPC BatchTool");
    app.setApplicationVersion("3.2.5");

    QQuickStyle::setStyle("Default");

    // 接管全局日志：C++ 的 qDebug/qInfo 与 QML 的 console.log 都写入 LogText.txt
    AppLogger::install();

    QQmlApplicationEngine engine;

    registerSingleton<ScreenTools>("ScreenTools");
    registerSingleton<AppLogger>("AppLogger");
    registerSingleton<ConfigureManager>("ConfigureManager");
    registerSingleton<TranslatorManager>("TranslatorManager");
    // 设备搜索：串联 WifiBroadcast 广播扫描与界面列表
    registerSingleton<DeviceScanner>("DeviceScanner");
    // 界面选中设备的管理者：勾选多台（QMap<uid, 设备信息>）+ 当前选中一台
    registerSingleton<DeviceManager>("DeviceManager");

    const QUrl url(QStringLiteral("qrc:/qml/main.qml"));
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreated, &app,
        [url](QObject* obj, const QUrl& objUrl) {
            if (obj == nullptr && url == objUrl) {
                QCoreApplication::exit(-1);
            }
    },
        Qt::QueuedConnection);
    engine.load(url);

    return app.exec();
}
