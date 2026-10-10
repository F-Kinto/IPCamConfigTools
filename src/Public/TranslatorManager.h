#pragma once
#include <vector>
#include <QTranslator>
#include <mutex>
#include <QMutex>
#include <QObject>
#if defined(_MSC_VER) && (_MSC_VER >= 1500)
#pragma execution_character_set("utf-8")
#endif

// 界面翻译切换
class TranslatorManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString currentLanguage READ getCurrentLanguage NOTIFY languageChanged)

  public:
    TranslatorManager();
    ~TranslatorManager();
    static TranslatorManager* instance();
    // static inline TranslatorManager &instance()
    //{
    //	static TranslatorManager _instance;
    //	return _instance;
    // }

    // 初始化系统默认语言
    Q_INVOKABLE void initSystemDefaultLanguage();

    // 设置语言
    Q_INVOKABLE void setInitLangusge();

    // 切换语言
    Q_INVOKABLE void changeLanguage(const QString& str, const QString& str1);

    // 获取当前语言
    Q_INVOKABLE const QString& getCurrentLanguage() const;

    Q_INVOKABLE bool chineseLanguage() const;

  private:
    // 删除当前所有翻译
    void removeCurrentTrans();

  signals:
    void languageChanged(const QString& language);

  private:
    // 当前界面显示的语言
    std::vector<QTranslator*> m_installTrans;
    QString                   m_curLanguage;
    mutable std::mutex        translateMutex;
    static TranslatorManager* m_instance;
    static QMutex             m_lock;
};
