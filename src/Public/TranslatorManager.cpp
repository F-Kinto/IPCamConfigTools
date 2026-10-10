#include "TranslatorManager.h"
#include <QCoreApplication>
#include <QSettings>
#include "ConfigureManager.h"
#include <QLocale>
#include <QDebug>
#include "Log4qt/QALogmanger.h"

TranslatorManager* TranslatorManager::m_instance = nullptr;
QMutex             TranslatorManager::m_lock;

TranslatorManager::TranslatorManager() {}

TranslatorManager::~TranslatorManager() {}

TranslatorManager* TranslatorManager::instance()
{
    m_lock.lock();
    if (!m_instance)
        m_instance = new TranslatorManager();
    m_lock.unlock();
    return m_instance;
}

void TranslatorManager::initSystemDefaultLanguage()
{
    // 初始化默认语言
    // 如果第一次安装，即还没有设置语言，则使用系统语言
    if (ConfigureManager::instance()->isHasSetLanguage()) {
        setInitLangusge();
        return;
    }
    QADebug() << "First Start Program, Preparing check system language: " << QLocale::system().language();
    // 检测系统语言
    if (QLocale::system().language() == QLocale::Chinese) {
        ConfigureManager::instance()->setLanguageType((int)EnumNameSpace::LanguageType::eChinese);
    } else if (QLocale::system().language() == QLocale::English) {
        ConfigureManager::instance()->setLanguageType((int)EnumNameSpace::LanguageType::eEnglish);
    } else if (QLocale::system().language() == QLocale::Spanish) {
        // 西班牙语
        ConfigureManager::instance()->setLanguageType((int)EnumNameSpace::LanguageType::eSpanish);
    } else if (QLocale::system().language() == QLocale::French) {
        // 法语
        ConfigureManager::instance()->setLanguageType((int)EnumNameSpace::LanguageType::eFrench);
    } else if (QLocale::system().language() == QLocale::Thai) {
        // 泰语
        ConfigureManager::instance()->setLanguageType((int)EnumNameSpace::LanguageType::eThailand);
    } else if (QLocale::system().language() == QLocale::German) {
        // 德语
        ConfigureManager::instance()->setLanguageType((int)EnumNameSpace::LanguageType::eGermany);
    } else if (QLocale::system().language() == QLocale::Japanese) {
        // 日语
        ConfigureManager::instance()->setLanguageType((int)EnumNameSpace::LanguageType::eJapan);
    } else if (QLocale::system().language() == QLocale::Russian) {
        // 俄罗斯语
        ConfigureManager::instance()->setLanguageType((int)EnumNameSpace::LanguageType::eRussia);
    } else if (QLocale::system().language() == QLocale::Italian) {
        // 意大利语
        ConfigureManager::instance()->setLanguageType((int)EnumNameSpace::LanguageType::eItaly);
    } else if (QLocale::system().language() == QLocale::Portuguese) {
        // 葡萄牙语
        ConfigureManager::instance()->setLanguageType((int)EnumNameSpace::LanguageType::ePortugal);
    } else if (QLocale::system().language() == QLocale::Arabic) {
        // 阿拉伯语
        ConfigureManager::instance()->setLanguageType((int)EnumNameSpace::LanguageType::eArabia);
    }
    else {
        // 默认使用英文，如果检测道到语言失败不支持或者失败，则使用英文
        ConfigureManager::instance()->setLanguageType((int)EnumNameSpace::LanguageType::eEnglish);
    }
}

void TranslatorManager::setInitLangusge()
{
    if (ConfigureManager::instance()->languageType() == (int)EnumNameSpace::LanguageType::eEnglish) {
        changeLanguage("EN", "en"); //英文
    } else if (ConfigureManager::instance()->languageType() == (int)EnumNameSpace::LanguageType::eChinese) {
        changeLanguage("zh_CN", "zh_CN"); // 中文
    } else if (ConfigureManager::instance()->languageType() == (int)EnumNameSpace::LanguageType::eSpanish) {
        changeLanguage("ESP", "es"); // 西班牙
    } else if (ConfigureManager::instance()->languageType() == (int)EnumNameSpace::LanguageType::eFrench) {
        changeLanguage("FR", "fr"); // 法语
    } else if (ConfigureManager::instance()->languageType() == (int)EnumNameSpace::LanguageType::eThailand) {
        changeLanguage("TH", "th"); // 泰语
    } else if (ConfigureManager::instance()->languageType() == (int)EnumNameSpace::LanguageType::eGermany) {
        changeLanguage("DE", "de"); // 德语
    } else if (ConfigureManager::instance()->languageType() == (int)EnumNameSpace::LanguageType::eJapan) {
        changeLanguage("JA", "ja"); // 日本語
    } else if (ConfigureManager::instance()->languageType() == (int)EnumNameSpace::LanguageType::eRussia) {
        changeLanguage("RU", "ru"); // 俄语
    } else if (ConfigureManager::instance()->languageType() == (int)EnumNameSpace::LanguageType::eItaly) {
        changeLanguage("IT", "it"); // 意大利语
    } else if (ConfigureManager::instance()->languageType() == (int)EnumNameSpace::LanguageType::ePortugal) {
        changeLanguage("PT", "pt"); // 葡萄牙语
    } else if (ConfigureManager::instance()->languageType() == (int)EnumNameSpace::LanguageType::eArabia) {
        changeLanguage("AR", "ar"); // 阿拉伯语
    }
    // else if(ConfigureManager::instance()->languageType() == (int)EnumNameSpace::LanguageType::eVietnam)
    // {
    // 	changeLanguage("VI", "vi"); // 越南语
    // }
    // else if(ConfigureManager::instance()->languageType() == (int)EnumNameSpace::LanguageType::eMalaysia)
    // {
    // 	changeLanguage("MS", "ms"); // 马来语
    // }
    // else if(ConfigureManager::instance()->languageType() == (int)EnumNameSpace::LanguageType::ePoland)
    // {
    // 	changeLanguage("PL", "pl"); // 波兰语
    // }
    // else if(ConfigureManager::instance()->languageType() == (int)EnumNameSpace::LanguageType::eIndia)
    // {
    // 	changeLanguage("IN", "hi"); // 印第安语
    // }
    // else if(ConfigureManager::instance()->languageType() == (int)EnumNameSpace::LanguageType::eIsrael)
    // {
    // 	changeLanguage("HE", "he"); // 希伯来语
    // }
    // else if(ConfigureManager::instance()->languageType() == (int)EnumNameSpace::LanguageType::eKorea)
    // {
    // 	changeLanguage("KO", "ko"); // 韩语
    // }
    // else if(ConfigureManager::instance()->languageType() == (int)EnumNameSpace::LanguageType::eIndonesia)
    // {
    // 	changeLanguage("ID", "id"); // 印尼语
    // }
    // else if(ConfigureManager::instance()->languageType() == (int)EnumNameSpace::LanguageType::eDutch)
    // {
    // 	changeLanguage("NL", "nl"); // 荷兰语
    // }
    else {
        // 默认为英文
        changeLanguage("EN", "en");
    }
}

void TranslatorManager::changeLanguage(const QString& str, const QString& str2)
{
    std::unique_lock<std::mutex> lock(translateMutex);

    if (m_curLanguage == str)
        return;
    // 先删除当前安装的翻译
    removeCurrentTrans();

    QString      webQmFile   = QString(":/translations/%2/qtwebengine_%1.qm").arg(str2).arg(str2);
    QString      localQmFile = QString(":/translations/%2/qt_%1.qm").arg(str2).arg(str2);
    QString      uiQmFile    = QString(":/translations/%2/VmsTranslator_%1.qm").arg(str).arg(str2);
    QTranslator* trans       = new QTranslator;
    if (trans->load(webQmFile) && QCoreApplication::installTranslator(trans)) {
        m_installTrans.push_back(trans);
    } else {
        delete trans;
    }
    trans = new QTranslator;
    if (trans->load(localQmFile) && QCoreApplication::installTranslator(trans)) {
        m_installTrans.push_back(trans);
    } else {
        delete trans;
    }
    // 加载ui的qm文件
    trans = new QTranslator;
    if (trans->load(uiQmFile) && QCoreApplication::installTranslator(trans)) {
        m_installTrans.push_back(trans);
    } else {
        delete trans;
    }
    m_curLanguage = str;
    emit languageChanged(str);
}

const QString& TranslatorManager::getCurrentLanguage() const
{
    return m_curLanguage;
}

bool TranslatorManager::chineseLanguage() const
{
    std::unique_lock<std::mutex> lock(translateMutex);
    return m_curLanguage == "zh_CN";
}

void TranslatorManager::removeCurrentTrans()
{
    for (auto t : m_installTrans) {
        QCoreApplication::removeTranslator(t);
        delete t;
    }
    m_installTrans.clear();
}
