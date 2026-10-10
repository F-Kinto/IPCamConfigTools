#pragma once

namespace EnumNameSpace {

// 界面语言类型
enum class LanguageType {
    eEnglish = 0, // 英文
    eChinese,     // 简体中文
    eSpanish,     // 西班牙语
    eFrench,      // 法语
    eThailand,    // 泰语
    eGermany,     // 德语
    eJapan,       // 日语
    eRussia,      // 俄语
    eItaly,       // 意大利语
    ePortugal,    // 葡萄牙语
    eArabia       // 阿拉伯语
};

// 应用目录类型
enum class AppDir {
    eApp = 0, // 程序所在目录
    eTest,    // 测试目录（TestDir）
    eConfig,  // 配置目录
    eLog      // 日志目录
};

} // namespace EnumNameSpace
