#pragma once

namespace EnumNameSpace {

// 界面语言类型
enum class LanguageType {
    eChinese = 0,     // 简体中文
    eEnglish, // 英文
};

// 应用目录类型
enum class AppDir {
    eApp = 0, // 程序所在目录
    eTest,    // 测试目录（TestDir）
    eConfig,  // 配置目录
    eLog      // 日志目录
};

// 设备 HTTP 请求 URL 模板（%1 = 设备 IP）
enum class DeviceQuestUrl {
    eGetDeviceInfoList,    // http://%1/goform/getAPLanP2PSupport
    eGetDeviceFeatures,    // http://%1:9898/get?singleCMD=get_deviceFeatures
    eGetDeviceInfo,        // http://%1/goform/getOtherSetttings?...
    eGetJsonConfUrlWifi,   // http://%1/goform/getOtherSetttings?... (WiFi 配置)
    eGetRtspInfoUrl,       // http://%1/goform/getOtherSetttings?singleCMD=RtspConf&userid=admin&userkey=0192023a7bbd73250516f069df18b500
    eDeviceRestart,        // http://%1/goform/reboot?userid=admin&userkey=0192023a7bbd73250516f069df18b500
    eFactoryReset,         // http://%1/goform/restoreDefault?userid=admin&userkey=0192023a7bbd73250516f069df18b500
    eUpdateFileToDeviceWifi, // http://%1/cgi-bin/upload_app.cgi?userid=admin&userkey=0192023a7bbd73250516f069df18b500
};

} // namespace EnumNameSpace
