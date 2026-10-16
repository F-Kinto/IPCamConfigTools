#pragma once

namespace EnumNameSpace {

// 界面语言类型
enum class LanguageType {
    eEnglish = 0, // 英文
    eChinese,     // 简体中文
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
};

// 设备 HTTP 设置接口 URL 模板（%1 = 设备 IP）
// 与 OtherSettingsDialog 的子节点 key 一一对应，顺序同界面分组顺序
// TODO: 设置类接口路径暂按设备 goform 风格占位，待固件协议确认后修正 singleCMD 指令名
enum class DeviceSetUrl {
    eSetNetwork = 0,     // 网络设置（以太网） -> network
    eSetGb28181,         // 28181接入设置 -> gb28181
    eSetVideoCapture,    // 视频采集设置 -> videoCapture
    eSetOsd,             // OSD设置 -> timeTitle
    eSetVideoEncode,     // 视频编码 -> videoEncode
    eSetAudioEncode,     // 音频编码 -> audioEncode
    eSetAudioReconfig,   // 音量配置 -> audioReconfig
    eSetMotionDetect,    // 移动侦测 -> motionDetect
    eSetAudioDetect,     // 声音侦测 -> audioDetect
    eSetAccount,         // 账号管理 -> account
    eSetClock,           // 时钟设置 -> clock
    eSetMaintenance,     // 定期维护 -> maintenance
    eSetLanguage         // 设备语言 -> language
};

} // namespace EnumNameSpace
