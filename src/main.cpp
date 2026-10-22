#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlEngine>
#include <QJSEngine>
#include <QQuickStyle>
#include <QUrl>

#include "Public/AppLogger.h"
#include "Public/BatchSettingsTask.h"
#include "Public/ConfigureManager.h"
#include "Public/DeviceApiClient.h"
#include "Public/DeviceManager.h"
#include "Public/DeviceScanner.h"
#include "Public/DeviceUpgradeTask.h"
#include "Public/TranslatorManager.h"
#include "Public/screentools.h"
#include "Rtsp/RtspVideoItem.h"

#include <Windows.h>
#include <shellscalingapi.h>

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

// 与 VmsTools 对齐：进程级 Per-Monitor DPI 感知，
// 否则修改缩放比后启动程序概率获取的是修改之前的 dpi，导致 ui 兼容问题
void setDPIAwareness()
{
    HMODULE hShCore = GetModuleHandleA("shcore.dll");

    // 如果没有加载，则加载它
    if (!hShCore) {
        hShCore = LoadLibraryA("shcore.dll");
        if (!hShCore)
            return;
    } else {
        qDebug() << "shcore.dll already loaded at: 0x" << hShCore;
    }
    if (hShCore) {
        typedef HRESULT(WINAPI * SetProcessDpiAwarenessProc)(PROCESS_DPI_AWARENESS);
        auto SetProcessDpiAwareness = (SetProcessDpiAwarenessProc)GetProcAddress(hShCore, "SetProcessDpiAwareness");

        if (SetProcessDpiAwareness) {
            SetProcessDpiAwareness(PROCESS_PER_MONITOR_DPI_AWARE);
            return;
        }
    } else {
        DWORD err = GetLastError();
        qDebug() << "LoadLibraryA failed with error: " << err;
    }
}

int main(int argc, char* argv[]) {
    // 与 VmsTools 对齐：DPI 感知 + Qt 高 DPI 缩放，必须在 QGuiApplication 构造前设置
    setDPIAwareness();
    QGuiApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
    QGuiApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
    QGuiApplication::setAttribute(Qt::AA_UseHighDpiPixmaps);

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
    // 通用异步 HTTP 调用封装（处理链同 VmsTools queryRequestV5：组包 -> AsynRequest -> 按 customMessage 分发响应）
    registerSingleton<DeviceApiClient>("DeviceApiClient");
    // 批量下发"配置其他参数"：设备间并行、设备内串行、失败 2 秒重试
    registerSingleton<BatchSettingsTask>("BatchSettingsTask");
    // WiFi 设备固件一键升级：multipart 文件上传 + 广播轮询版本变化
    registerSingleton<DeviceUpgradeTask>("DeviceUpgradeTask");

    // RTSP 直播渲染组件（模块 IPCam.Rtsp 1.0）：device 赋值自动拉流，
    // 内部走 Live555 收流 + FFmpeg 解码（同步自 VmsTools，固定 RTSP 单路）
    qmlRegisterType<RtspVideoItem>("IPCam.Rtsp", 1, 0, "RtspVideoItem");

    // 界面语言初始化必须在 QML 加载前完成：安装翻译器后再创建 QML，
    // 组件树创建时 qsTr 直接按译文求值，避免先按源文本创建再依赖 retranslate 刷新
    TranslatorManager::instance()->initSystemDefaultLanguage();

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
