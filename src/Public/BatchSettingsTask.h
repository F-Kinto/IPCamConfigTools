/*********************************************************************
File : BatchSettingsTask.h
Module : Public
Authors: QA
date : 2026/10/16 16:00
Ver : 1.0.0
History:
QA 2026/10/16 1.0.0 build this module
********************************************************************/
#pragma once

#include "common_global.h"
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVector>

class AsynRequest;
class QTimer;

/**
 * @class BatchSettingsTask
 * @brief "执行修改（配置其他参数）"的批量下发调度器。
 *
 * 输入：勾选设备列表 + 按界面勾选顺序排列的设置项列表（每项含 URL 模板与请求体）。
 * 调度规则：
 *   - 设备间并行：每设备一条独立异步链（各自 AsynRequest 实例，共享 QNAM 单例）；
 *   - 设备内串行：前一设置项到达终态（成功 / 两次失败跳过）后才发下一项；
 *   - 失败重试：单项失败间隔 2 秒重发，共尝试 2 次仍失败则跳过该项继续下一项；
 *   - 重启等待：网络设置/视频编码/音频编码三项成功后设备重启进程生效，
 *     等 25 秒再发下一项（界面侧已把这三项排到最后发送）。
 * 进度与结果经信号上报，界面文本由 QML 侧按状态码组装（保持 qsTr 翻译体系）。
 *
 * @note 全部在主线程工作（AsynRequest/QNAM 主线程），QML 调用天然满足。
 */
class COMMON_EXPORT BatchSettingsTask : public QObject {
    Q_OBJECT

  public:
    // 单项下发状态（deviceProgress 信号的 state 参数）
    enum ItemState {
        eSetting = 0, // 正在设置
        eSuccess,     // 设置成功
        eRetrying,    // 第 1 次失败，2 秒后重试
        eSkipped,     // 两次尝试均失败，已跳过
        eDeviceDone,  // 该设备全部设置项完成
        eRestart      // 设置成功，设备进程重启中（25 秒后继续下一项）
    };

    static BatchSettingsTask* instance();

    /**
     * @brief 是否有批量任务执行中（执行期间禁止再次 start）
     * @return true=执行中
     */
    Q_INVOKABLE bool running() const;

    /**
     * @brief 启动批量下发
     * @param devices 设备列表 [{uid, ip}]（uid 即 deviceKey，响应靠它路由）
     * @param items   设置项列表（按界面勾选顺序）[{key, name, action}]
     *                - key/name: 界面标识与显示名（结果详情用）
     *                - action: 动作名（进度提示文本用，如"以太网"）
     *
     * URL 与 JSON 请求体全部在本类（C++ 侧）从 other_settings.json 组装：
     * 统一接口 http://<设备IP>/goform/ipcParams——面板保存过（文件里有该协议条目）发
     * POST {"cmd": "setXxx", "payload": {文件里的 payload 原样}}；没保存过发 GET
     * {"cmd": "getXxx"}。网络设置成功后设备切到保存的 IP，该设备后续设置项的 URL
     * 自动重填为新 IP。
     */
    Q_INVOKABLE void start(const QVariantList& devices, const QVariantList& items);

  signals:
    /**
     * @brief 某设备进度变化（文本由 QML 按 state 组装）
     * @param deviceKey 设备标识（start 时 devices[i].uid）
     * @param itemAction 当前设置项动作名（eDeviceDone 时为空串）
     * @param state ItemState 状态码
     */
    void deviceProgress(const QString& deviceKey, const QString& itemAction, int state);

    /**
     * @brief 某设备某设置项到达终态（成功 / 两次失败跳过）
     * @param success true=设置成功；false=两次尝试均失败已跳过
     */
    void itemResult(const QString& deviceKey, const QString& itemKey, const QString& itemName, bool success);

    /**
     * @brief 全部设备全部设置项完成（随后可弹结果详情）
     */
    void allFinished();

  private:
    explicit BatchSettingsTask(QObject* parent = nullptr);

    // 单个设置项描述（URL 与 JSON 请求体均在 start 时由 C++ 从 other_settings.json 组装）
    struct ItemSpec {
        QString key;
        QString name;
        QString action;
        QString urlTemplate; // http://%1/goform/ipcParams（%1 = 设备 IP）
        QString url;         // 已按设备当前 IP 填好
        QString newIp;       // 网络设置项专用：该项成功后设备切到此 IP（保存的 IP）
        QByteArray body;     // JSON 请求体（GET 也带 {"cmd": "getXxx"} 包体）
        bool isGet = false;  // true=GET（读设备当前配置），false=POST(JSON)
        bool restartAfter = false; // 该项成功后设备需重启进程生效（等 25 秒再发下一项）
    };

    // 每设备一条执行链（设备间并行、设备内串行）
    struct Runner {
        QString key;
        QVector<ItemSpec> items;
        int cur = 0;                     // 当前设置项下标
        int attempt = 0;                 // 当前项已尝试次数（1=首发, 2=重试）
        AsynRequest* request = nullptr;  // 该设备专属异步请求对象（并行关键）
        QTimer* retryTimer = nullptr;    // 失败 2 秒重发定时器
        QTimer* restartTimer = nullptr;  // 成功后进程重启 25 秒等待定时器
    };

    Runner* findRunner(const QString& deviceKey);
    void sendCurrent(Runner& runner);
    void advance(Runner& runner);
    void finishAll();

  private:
    QVector<Runner> m_runners;
    int m_finishedCount = 0; // 已完成的设备数
};
