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
    } else {
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
    }
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

    QString      webQmFile   = QString(":/%2/qtwebengine_%1.qm").arg(str2).arg(str2);
    QString      localQmFile = QString(":/%2/qt_%1.qm").arg(str2).arg(str2);
    QString      uiQmFile    = QString(":/%2/VmsTranslator_%1.qm").arg(str).arg(str2);
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
