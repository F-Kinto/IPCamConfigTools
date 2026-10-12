/*********************************************************************
File : ScreenTools.h
Module : tools
Authors: guangnan
date : 2023/06/29 16:00
Ver : 1.0.0
History:
guangnan 2023/06/29 1.0.0 build this module
********************************************************************/
#ifndef SCREENTOOLS_H
#define SCREENTOOLS_H

#include <qabstractsocket.h>
#include <QObject>
#include <QScopedPointer>
#include <QColor>
#include <QCursor>
#include <QVariant>
#include <QStringList>

class QQuickItem;

class ScreenTools : public QObject {
    Q_OBJECT
    Q_PROPERTY(qreal realMbxPixelRatio READ realMbxPixelRatio NOTIFY pixelRatioChanged)
    Q_PROPERTY(QString fontFamily READ fontFamily NOTIFY fontFamilyChanged)
    Q_PROPERTY(bool isWin7System READ isWin7System NOTIFY isWin7SystemChanged)
    Q_PROPERTY(int screenWidth READ screenWidth NOTIFY signalScreenWidthChanged)
    Q_PROPERTY(int screenHeight READ screenHeight NOTIFY signalScreenHeightChanged)
    Q_PROPERTY(qreal rectWidthScale READ rectWidthScale NOTIFY signalRectWidthScaleChanged)
    Q_PROPERTY(qreal rectHeightScale READ rectHeightScale NOTIFY signalRectHeightScaleChanged)
    Q_PROPERTY(bool isDebug READ isDebug WRITE setDebug NOTIFY isDebugChanged)
  public:
    ~ScreenTools();
    static ScreenTools* instance();
    void                reset();

    bool isDebug() const;
    void setDebug(bool debug);
    void isDebug(bool debug); // 兼容旧写法 isDebug(true/false)

  public:
    inline const QString&      fontFamily() const;
    inline void                setFontFamily(const QString& f);
    Q_INVOKABLE qreal          getCurrentDevicePixelRatio() const;
    Q_INVOKABLE qreal          getDevicePixelRatio() const;
    inline const qreal&        mbxPixelRatio() const;
    inline const qreal&        realMbxPixelRatio() const;
    Q_INVOKABLE static QString getLocalIpv4Address();
    Q_INVOKABLE static QString getLocalOuterIpv4Address();
    // 获取当前设备所有网卡信息（QVariantMap 列表，见 cpp 注释中的字段说明）
    Q_INVOKABLE static QVariantList getNetworkInterfaces();
    // 网卡展示名列表（"可读名 (IPv4)"，方便直接作为 ComboBox 的 model）
    Q_INVOKABLE static QStringList getNetworkInterfaceNames(bool onlyUp = true);
    inline const bool&         isWin7System() const; // 是否是win7系统
    bool                       getSystemIsWin7();    // 获取系统是否是win7
    Q_INVOKABLE static bool    hasAudioDevice();     // 检查是否存在音频设备
    Q_INVOKABLE static int     calculateMultiLineHeight(const QString& text, const int fontSize, int maxWidth, bool bold = false, bool isPixelFont = false);
    Q_INVOKABLE static int     calculateTextWidth(const QString& text, const int fontSize = scaleNum(10, true), bool bold = false, bool isPixelFont = false);
    Q_INVOKABLE static int     calculateLineCount(const QString& text, const QFont& font, int maxWidth);
    Q_INVOKABLE static int     calculateMultiTextWidth(const QString& text, const QString& text2 = "", const QString& text3 = "", const QString& text4 = "", const int fontSize = scaleNum(10, true),
                                                       bool bold = false, bool isPixelFont = false);
    Q_INVOKABLE static QString getFormatString(const QString& str, int width, int fontSize = scaleNum(10, true), bool isBold = false);
    Q_INVOKABLE static int     scaleNum(int originValue = 10, bool isFont = false);
    Q_INVOKABLE static bool    imageIsSvgSource(const QString& imageUrl);
    // 通过 SendArp 判断 IPv4 是否被占用：true=已占用，false=空闲（详见 cpp 注释）
    Q_INVOKABLE static bool    isIpOccupied(const QString& ip);
    // 异步探测 IP 占用：不阻塞 UI 线程，结果经 signalIpOccupied 信号回传（详见 cpp 注释）
    Q_INVOKABLE void           checkIpOccupiedAsync(const QString& ip);
    // 异步批量查找空闲 IP：从 baseIp 末段起向上叠加到 .254，不足再从其下方递减到 .1，
    // 跳过被占用的地址，凑满 count 个即止；结果经 signalFreeIpsFound 信号回传（详见 cpp 注释）
    Q_INVOKABLE void           findFreeIpsAsync(const QString& baseIp, int count);

    bool                getOutOfScreen();
    const bool&         outOfScreen() const;
    inline const int&   screenWidth() const;
    inline void         setScreenWidth(const int& s);
    inline const int&   screenHeight() const;
    inline void         setScreenHeight(const int& s);
    void                getScreenWidHeight();
    inline const qreal& rectWidthScale() const;
    void                setRectWidthScale();
    inline const qreal& rectHeightScale() const;
    void                setRectHeightScale();
  signals:
    void isDebugChanged();
    void fontFamilyChanged();
    void pixelRatioChanged();
    void isWin7SystemChanged();
    void signalScreenWidthChanged();
    void signalScreenHeightChanged();
    void signalRectWidthScaleChanged();
    void signalRectHeightScaleChanged();
    // checkIpOccupiedAsync 的探测结果：ip 为请求的地址，occupied=true 表示已被占用
    void signalIpOccupied(const QString& ip, bool occupied);
    // findFreeIpsAsync 的查找结果：baseIp 为请求的起始地址，wanted 为请求的数量，
    // freeIps 为按发现顺序排列的空闲地址列表；数量不足 wanted 表示网段内已穷尽
    void signalFreeIpsFound(const QString& baseIp, int wanted, const QStringList& freeIps);

  private:
    explicit ScreenTools(QObject* parent = nullptr);

  private:
    /**
     * @brief 单例模式实例指针
     * 静态成员变量，用于保存ScreenTools类的唯一实例
     */
    static ScreenTools* m_instance;

    /**
     * @brief 屏幕宽度
     * 以像素为单位的屏幕宽度值
     */
    int m_screenWidth;
    /**
     * @brief 屏幕高度
     * 以像素为单位的屏幕高度值
     */
    int m_screenHeight;
    /**
     * @brief 字体族
     * 用于存储界面使用的字体名称
     */
    QString m_fontFamily;

    /**
     * @brief MBX像素比例
     * 用于MBX显示的像素比例系数
     */
    qreal m_mbxPixelRatio;
    /**
     * @brief 是否为Windows 7系统
     * 标识当前操作系统是否为Windows 7
     */
    bool m_isWin7System = false;
    /**
     * @brief 缩放光标
     * 用于缩放操作时的自定义光标样式
     */
    QCursor m_zoomCursor;
    /**
     * @brief 是否超出屏幕范围
     * 标示当前窗口是否超出屏幕显示范围
     */
    bool m_outOfScreen = false;
    /**
     * @brief 缩放比例整数部分
     * 存储缩放比例的整数部分，默认值为1
     */
    int m_scaleInt = 1;
    /**
     * @brief 缩放比例小数部分
     * 存储缩放比例的小数部分，默认值为0
     */
    int m_scaleFrac = 0;
    /**
     * @brief 矩形宽度缩放比例
     * 用于矩形元素宽度方向的缩放系数
     */
    qreal m_rectWidthScale = 1.0;
    /**
     * @brief 矩形高度缩放比例
     * 用于矩形元素高度方向的缩放系数
     */
    qreal m_rectHeightScale = 1.0;

    qreal m_testScale = 1.0;
    bool  m_isDebug   = false;
};

const qreal& ScreenTools::mbxPixelRatio() const
{
    // QT默认的缩放比为四舍五入 即 125%的缩放比默认实现效果为100%，150%-》200%，175%-》200%
    // 故此处只对1.00<dpi<1.50的进行处理,其他dpi使用默认的处理
    // 如果缩放比 >=1.5 按照比例缩放
    return (m_mbxPixelRatio < 1.5 && m_mbxPixelRatio > 1.0) ? m_mbxPixelRatio : 1.0;
}

/**
 * @brief ScreenTools::realMbxPixelRatio 获取MBX像素比率的常量引用
 * @return 返回m_mbxPixelRatio的常量引用，这是一个qreal类型的值
 */
const qreal& ScreenTools::realMbxPixelRatio() const
{
    return m_mbxPixelRatio; // 返回成员变量m_mbxPixelRatio的常量引用
}

/**
 * @brief 获取当前字体家族名称
 * @return 返回字体家族的常量引用
 */
const QString& ScreenTools::fontFamily() const
{
    return m_fontFamily;
}

/**
 * @brief 设置字体家族名称
 * @param f 要设置的字体家族名称
 */
void ScreenTools::setFontFamily(const QString& f)
{
    m_fontFamily = f;         // 更新字体家族成员变量
    emit fontFamilyChanged(); // 发射字体家族改变信号
}

/**
 * @brief 检查当前系统是否为Windows 7系统
 * @return 返回一个布尔值的常量引用，表示系统是否为Windows 7
 */
const bool& ScreenTools::isWin7System() const
{
    return m_isWin7System;
}

/**
 * @brief 获取屏幕宽度
 * @return 返回一个整型常量引用，表示当前屏幕的宽度
 */
const int& ScreenTools::screenWidth() const
{
    return m_screenWidth;
}

/**
 * @brief 设置屏幕宽度
 * @param s 要设置的屏幕宽度值
 * @note 设置后会触发signalScreenWidthChanged()信号
 */
void ScreenTools::setScreenWidth(const int& s)
{
    m_screenWidth = s;
    emit signalScreenWidthChanged();
}

/**
 * @brief 获取屏幕高度
 * @return 返回一个整型常量引用，表示当前屏幕的高度
 */
const int& ScreenTools::screenHeight() const
{
    return m_screenHeight;
}

/**
 * @brief 设置屏幕高度
 * @param s 要设置的屏幕高度值
 * @note 设置后会触发signalScreenHeightChanged()信号
 */
void ScreenTools::setScreenHeight(const int& s)
{
    m_screenHeight = s;
    emit signalScreenHeightChanged();
}

/**
 * @brief 获取矩形宽度缩放比例
 * @return 返回一个浮点型常量引用，表示矩形宽度的缩放比例
 */
const qreal& ScreenTools::rectWidthScale() const
{
    return m_rectWidthScale;
}

/**
 * @brief 获取矩形高度缩放比例
 * @return 返回一个浮点型常量引用，表示矩形高度的缩放比例
 */
const qreal& ScreenTools::rectHeightScale() const
{
    return m_rectHeightScale;
}
#endif // SCREENTOOLS_H
