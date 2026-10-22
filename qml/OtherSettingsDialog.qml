import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import IPCam.Public 1.0
// 项目内封装的通用控件目录
import "Controls"

// 其它设置弹窗：左侧分类树 + 右侧参数面板（样式与设定IP/OSD修改弹窗一致）
// 分类树为静态配置项；当前仅“网络设置”页有内容，其余页显示占位，待对接协议后逐页补充
Dialog {
    id: root

    // 统一控件高度
    readonly property int ctrlH: ScreenTools.scaleNum(28)
    // 左侧分类树宽度
    readonly property int treeWidth: ScreenTools.scaleNum(220)
    // 右侧面板标签列宽（容纳“最大心跳超时次数”等长标签）
    readonly property int panelLabelWidth: ScreenTools.scaleNum(120)
    // 当前选中的设置页 key（对应 groups 里子项的 key）
    property string selectedKey: "network"
    // 打开时快照左侧树勾选状态；本次打开中没点过“保存”的页面，关闭时回滚其勾选状态
    property var openCheckedMap: ({
    })
    // 本次打开后点过“保存”的页面 key
    property var savedKeys: ({
    })
    // 关闭窗口后卸掉右侧面板：Dialog 关闭只是隐藏，面板实例不会销毁，
    // 不卸掉的话未保存的编辑会一直留着，下次打开也不会重新走“回填已保存值/默认值”的流程
    property bool panelSuspended: false
    // ===== 网络设置联动数据源（由 main.qml 注入）=====
    // 本机网卡列表（ipv4/netmask/gateway 等字段）
    property var nicList: []
    // 主界面当前选中的网卡；选中“所有网卡”时为 null
    property var selectedNic: null
    // 设备列表第一台设备的 IP；列表为空时为空串
    property string firstDeviceIp: ""
    // 分类树数据：key 用于右侧面板路由
    readonly property var groups: [{
        "name": qsTr("网络参数"),
        "items": [{
            "key": "network",
            "name": qsTr("网络设置")
        }, {
            "key": "gb28181",
            "name": qsTr("28181接入设置")
        }]
    }, {
        "name": qsTr("媒体设置"),
        "items": [{
            "key": "videoCapture",
            "name": qsTr("视频采集设置")
        }, {
            "key": "timeTitle",
            "name": qsTr("OSD设置")
        }, {
            "key": "videoEncode",
            "name": qsTr("视频编码")
        }, {
            "key": "audioEncode",
            "name": qsTr("音频编码")
        }, {
            "key": "audioReconfig",
            "name": qsTr("音量配置")
        }]
    }, {
        "name": qsTr("告警设置"),
        "items": [{
            "key": "motionDetect",
            "name": qsTr("移动侦测")
        }, {
            "key": "audioDetect",
            "name": qsTr("声音侦测")
        }]
    }, {
        "name": qsTr("系统设置"),
        "items": [{
            "key": "account",
            "name": qsTr("账号管理")
        }, {
            "key": "clock",
            "name": qsTr("时钟设置")
        }, {
            "key": "maintenance",
            "name": qsTr("定期维护")
        }, {
            "key": "language",
            "name": qsTr("设备语言")
        }]
    }]
    // 各设置页的勾选状态（key -> bool）；父节点勾选时批量设置整个分组
    property var checkedMap: ({
    })
    // 与“OSD修改”弹窗共用的 OSD 参数（由 main.qml 注入）：本页保存走 savedPanelValues 写 other_settings.json
    // 的 osd 条目，弹窗保存经 osdSavedFromDialog 信号回写同一条目；启动读回后由 syncSharedOsdFromStore 同步进来
    property QtObject sharedOsd: null
    // ===== 参数持久化：只有点面板上的“保存”才提交；关闭窗口/切换页面丢弃未保存的修改 =====
    // 结构：savedPanelValues[面板 key][控件 objectName] = { k: 类型, v: 值 }
    property var savedPanelValues: ({
    })
    // 同步收集的控件可读名（写 other_settings.json 时附在条目上便于人工辨识，恢复时忽略）
    property var savedPanelNames: ({})

    // 设备协议字段映射（覆盖除 language 外的全部面板；language 无设备协议，走旧格式）：
    // - cmd：面板对应的协议命令名（other_settings.json 顶层键与下发 body 外层标识）；
    //   命令名未提供的面板暂用面板 key 占位（gb28181/videoCapture/osd/videoEncode/audioEncode/
    //   audioReconfig/motionDetect/audioDetect/account/maintenance），固件确认后改此一处即可
    // - fixed：无控件对应的固定字段（协议要求但面板无控件，按默认值发：字符串 ""、数字 0）
    // - fields：控件 objectName -> {"f": 协议字段路径, "k": 控件类型}，可选 vals/num/if：
    //   - f 支持 "a/b" 嵌套路径（组 payload 时按路径逐层嵌套，如 mainStream/encodeType）
    //   - k 供读回时还原运行结构（ip=IpInput.text()、currentIndex=下拉、checked=勾选、text=文本、time=时间）
    //   - vals：下拉选项值映射（UI 选项 index -> 协议值；[启用,禁用]类 UI 顺序与协议 1/0 相反时必配）
    //   - num：文本值数字化（parseInt 后进 payload，如端口/音量；IP 与密码仍为字符串）
    //   - if：条件字段 {c: 条件控件 objectName, v: 期望值}，仅当条件控件保存值为 v 时进 payload
    //     （如时钟 NTP 字段仅 timeMode=1 时发、手动字段仅 timeMode=2 时发）
    // 有映射的面板：文件与下发 body 均按协议格式 {"switch": "checked"/"none", "payload": {协议字段: 控件值}}
    // 无映射的面板（language）：沿用旧格式（键=objectName 的 {k, v, name, p} 表）；两种格式读写自动兼容
    property var protocolMaps: {
        "network": {
            "cmd": "netInfo",
            "fields": {
                "ipAddrInput": {"f": "ip", "k": "ip"},
                "maskInput": {"f": "netmask", "k": "ip"},
                "gwInput": {"f": "gateway", "k": "ip"},
                "dns1Input": {"f": "dns", "k": "ip"},
                "dns2Input": {"f": "dns1", "k": "ip"},
                "dhcpCombo": {"f": "dhcp", "k": "currentIndex"},
                "mtuInput": {"f": "mtu", "k": "text", "num": true}
            }
        },
        "gb28181": {
            "cmd": "gb28181",
            "fixed": {
                "sipagreement": "",
                "registerstate": "",
                "videochannelencodingid": "",
                "numbervideochannels": 0
            },
            "fields": {
                "gbEnableCombo": {"f": "enable", "k": "currentIndex"},
                "localSipPortInput": {"f": "localsipport", "k": "text", "num": true},
                "sipServerIdInput": {"f": "serversipid", "k": "text"},
                "sipServerDomainInput": {"f": "serversipdomain", "k": "text"},
                "sipServerIpInput": {"f": "serversipip", "k": "text"},
                "sipServerPortInput": {"f": "serversipport", "k": "text", "num": true},
                "sipUserInput": {"f": "sipusername", "k": "text"},
                "sipAuthIdInput": {"f": "sipuserid", "k": "text"},
                "passwordInput": {"f": "userpassword", "k": "text"},
                "confirmPasswordInput": {"f": "passwordconfirmation", "k": "text"},
                "alarmIdInput": {"f": "sn", "k": "text"},
                "registerExpireInput": {"f": "registerperiodvalidity", "k": "text", "num": true},
                "heartbeatInput": {"f": "heartbeatcycle", "k": "text", "num": true},
                "heartbeatTimeoutInput": {"f": "maximumheartbeattimeout", "k": "text", "num": true},
                "streamIndexCombo": {"f": "streamType", "k": "currentIndex"}
            }
        },
        "videoCapture": {
            "cmd": "videoCapture",
            "fields": {
                "vcBrightnessInput": {"f": "brightness", "k": "text", "num": true},
                "vcSaturationInput": {"f": "saturation", "k": "text", "num": true},
                "vcSharpnessInput": {"f": "sharpness", "k": "text", "num": true},
                "vcContrastInput": {"f": "contrast", "k": "text", "num": true},
                "vcBacklightInput": {"f": "backlight", "k": "text", "num": true},
                "vcWhiteBalanceCombo": {"f": "whiteBalance", "k": "currentIndex", "vals": ["auto"]},
                "vcHFlipCombo": {"f": "hFlip", "k": "currentIndex"},
                "vcVFlipCombo": {"f": "vFlip", "k": "currentIndex"},
                "vcWdrCombo": {"f": "wdr", "k": "currentIndex"}
            }
        },
        "timeTitle": {
            "cmd": "osd",
            "fields": {
                "osdEnableCombo": {"f": "osdEnable", "k": "currentIndex", "vals": [1, 0]},
                "osdOverlayCombo": {"f": "extraInfo", "k": "currentIndex"},
                "osdShowWeekCheck": {"f": "showWeekDay", "k": "checked"},
                "osdTimePosCombo": {"f": "timePos", "k": "currentIndex"},
                "osdTimeFormatCombo": {"f": "timeFormat", "k": "currentIndex"},
                "osdTimeShowPosCombo": {"f": "titleTextPos", "k": "currentIndex"},
                "osdTitleInput": {"f": "titleContent", "k": "text"}
            }
        },
        "videoEncode": {
            "cmd": "videoEncode",
            "fields": {
                "veMainCodecCombo": {"f": "mainStream/encodeType", "k": "currentIndex", "vals": [1, 0]},
                "veSubCodecCombo": {"f": "subStream/encodeType", "k": "currentIndex", "vals": [1, 0]},
                "veMainResCombo": {"f": "mainStream/resolution", "k": "currentIndex"},
                "veSubResCombo": {"f": "subStream/resolution", "k": "currentIndex"},
                "veMainRateCtlCombo": {"f": "mainStream/bitrateMode", "k": "currentIndex"},
                "veSubRateCtlCombo": {"f": "subStream/bitrateMode", "k": "currentIndex"},
                "veMainGopInput": {"f": "mainStream/iFrameInterval", "k": "text", "num": true},
                "veSubGopInput": {"f": "subStream/iFrameInterval", "k": "text", "num": true},
                "veMainBitrateInput": {"f": "mainStream/bitrate", "k": "text", "num": true},
                "veSubBitrateInput": {"f": "subStream/bitrate", "k": "text", "num": true},
                "veMainFpsCombo": {"f": "mainStream/fps", "k": "currentIndex", "vals": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30]},
                "veSubFpsCombo": {"f": "subStream/fps", "k": "currentIndex", "vals": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30]}
            }
        },
        "audioEncode": {
            "cmd": "audioEncode",
            "fields": {
                "aeEnableCombo": {"f": "enable", "k": "currentIndex", "vals": [1, 0]},
                "aeTypeCombo": {"f": "encodeType", "k": "currentIndex", "vals": ["G711", "AAC"]},
                "aeSampleCombo": {"f": "sampleRate", "k": "currentIndex", "vals": [8000, 16000]},
                "aeBitrateInput": {"f": "bitrate", "k": "text", "num": true}
            }
        },
        "audioReconfig": {
            "cmd": "audioReconfig",
            "fields": {
                "arCaptureInput": {"f": "captureVolume", "k": "text", "num": true},
                "arPlayInput": {"f": "playVolume", "k": "text", "num": true}
            }
        },
        "motionDetect": {
            "cmd": "motionDetect",
            "fields": {
                "mdEnableCombo": {"f": "enable", "k": "currentIndex", "vals": [1, 0]}
            }
        },
        "audioDetect": {
            "cmd": "audioDetect",
            "fields": {
                "adEnableCombo": {"f": "enable", "k": "currentIndex", "vals": [1, 0]}
            }
        },
        "account": {
            "cmd": "account",
            "fixed": {
                "username": "admin"
            },
            "fields": {
                "accNewPwdInput": {"f": "password", "k": "text"}
            }
        },
        "clock": {
            "cmd": "setTimeAttr",
            "fields": {
                "ckModeCombo": {"f": "timeMode", "k": "currentIndex"},
                "ckZoneCombo": {"f": "timezone", "k": "currentIndex", "vals": ["GMT-12:00", "GMT-11:00", "GMT-10:00", "GMT-09:00", "GMT-08:00", "GMT-07:00", "GMT-06:00", "GMT-05:00", "GMT-04:00", "GMT-03:00", "GMT-02:00", "GMT-01:00", "GMT+00:00", "GMT+01:00", "GMT+02:00", "GMT+03:00", "GMT+04:00", "GMT+05:00", "GMT+06:00", "GMT+07:00", "GMT+08:00", "GMT+09:00", "GMT+10:00", "GMT+11:00", "GMT+12:00"]},
                "ckNtpIpInput": {"f": "ntpServer", "k": "text", "if": {"c": "ckModeCombo", "v": 1}},
                "ckNtpPortInput": {"f": "ntpPort", "k": "text", "num": true, "if": {"c": "ckModeCombo", "v": 1}},
                "ckRefreshInput": {"f": "ntpInterval", "k": "text", "num": true, "if": {"c": "ckModeCombo", "v": 1}},
                "ckTimeInput": {"f": "manualTime", "k": "text", "if": {"c": "ckModeCombo", "v": 2}},
                "ckSetTimeCheck": {"f": "manualSetTimeEnable", "k": "checked", "if": {"c": "ckModeCombo", "v": 2}},
                "ckDstEnableCombo": {"f": "dstEnable", "k": "currentIndex", "vals": [1, 0]},
                "ckDstStartMonthCombo": {"f": "dstStart/month", "k": "currentIndex", "vals": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]},
                "ckDstStartWeekSeqCombo": {"f": "dstStart/weekOrder", "k": "currentIndex", "vals": [1, 2, 3, 4, 5]},
                "ckDstStartWeekDayCombo": {"f": "dstStart/weekDay", "k": "currentIndex", "vals": [1, 2, 3, 4, 5, 6, 0]},
                "ckDstStartTimePicker": {"f": "dstStart/time", "k": "time"},
                "ckDstEndMonthCombo": {"f": "dstEnd/month", "k": "currentIndex", "vals": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]},
                "ckDstEndWeekSeqCombo": {"f": "dstEnd/weekOrder", "k": "currentIndex", "vals": [1, 2, 3, 4, 5]},
                "ckDstEndWeekDayCombo": {"f": "dstEnd/weekDay", "k": "currentIndex", "vals": [1, 2, 3, 4, 5, 6, 0]},
                "ckDstEndTimePicker": {"f": "dstEnd/time", "k": "time"},
                "ckDstOffsetCombo": {"f": "dstOffset", "k": "currentIndex", "vals": [30, 60, 90, 120]}
            }
        },
        "maintenance": {
            "cmd": "maintenance",
            "fields": {
                "mtEnableCombo": {"f": "enable", "k": "currentIndex", "vals": [1, 0]},
                "mtDayCombo": {"f": "cycleType", "k": "currentIndex"},
                "mtTimeInput": {"f": "rebootTime", "k": "time"}
            }
        }
    }

    // 程序启动：读回上次点"保存"持久化的各面板参数（面板打开时由 restorePanel 回填控件）；
    // 键为控件 objectName（面板增删控件不错位）；协议格式面板（含 payload）反向映射回运行结构
    Component.onCompleted: {
        var saved = ConfigureManager.loadOtherSettingsValues();
        if (saved === "")
            return ;
        var m = ({});
        var sw = ({});
        try {
            var parsed = JSON.parse(saved);
            for (var key in parsed) {
                // 跳过下划线开头的说明性键（_hint 等）
                if (key.charAt(0) === "_")
                    continue;
                var store = parsed[key];
                if (!store || typeof store !== "object")
                    continue;
                // 协议格式面板：{"switch": ..., "payload": {协议字段: 值}}——顶层键是协议命令名，反查面板 key；
                // switch 记入启动勾选表：随启动整体灌入 checkedMap，打开界面时左侧子节点与本页
                // 复选框立即显示上次保存的勾选（不再逐面板点击激活）；
                // payload 可能是嵌套对象（mainStream/encodeType 等），先按 "/" 路径展平再反查控件，
                // 协议值按映射还原为控件原生值（vals 反查 index、num 数字转文本、1/0 转勾选）
                if (store.payload !== undefined && store.payload !== null && typeof store.payload === "object") {
                    var pkey = root.panelKeyOfCmd(key);
                    if (pkey === "")
                        continue;
                    var pm = root.protocolMaps[pkey];
                    var flat = ({});
                    root.flattenPayload(store.payload, "", flat);
                    var ppanel = ({});
                    for (var fp in flat) {
                        var oname = root.objectNameOfField(pm, fp);
                        if (oname === "")
                            continue;
                        var fld = pm.fields[oname];
                        ppanel[oname] = {"k": fld.k, "v": root.valueFromProtocol(fld, flat[fp])};
                    }
                    m[pkey] = ppanel;
                    sw[pkey] = store.switch === "checked";
                    continue;
                }
                var panel = ({});
                for (var path in store) {
                    var rec = store[path];
                    // 跳过面板说明键（_name）与坏条目；name 字段不进运行结构；p 保留（下发时还原位置键）
                    if (path.charAt(0) === "_" || !rec || typeof rec !== "object" || typeof rec.k !== "string")
                        continue;
                    panel[path] = typeof rec.p === "string" ? {
                        "k": rec.k,
                        "v": rec.v,
                        "p": rec.p
                    } : {
                        "k": rec.k,
                        "v": rec.v
                    };
                }
                m[key] = panel;
            }
        } catch (e) {
            // 配置内容损坏：放弃恢复，保持代码默认值
            return ;
        }
        root.savedPanelValues = m;
        // 勾选状态随启动整体恢复：文件里各面板的 switch 直接灌入 checkedMap，
        // 打开“配置其它参数”界面时左侧子节点与本页复选框立即显示上次保存的勾选
        root.checkedMap = sw;
        // OSD 数据同步进与“OSD修改”弹窗共用的参数对象（两边重启后显示一致）
        root.syncSharedOsdFromStore();
    }

    // 启动读回后把 OSD 数据同步进与“OSD修改”弹窗共用的参数对象：
    // 两边共用 other_settings.json 的 osd 条目，重启后弹窗（applyShared）与本页（回填+readShared）显示一致
    function syncSharedOsdFromStore() {
        if (!root.sharedOsd)
            return ;

        var store = root.savedPanelValues["timeTitle"];
        if (store === undefined)
            return ;

        var s = root.sharedOsd;
        var hit = false;
        if (store["osdSetCheck"] !== undefined) {
            s.setTimeTitle = store["osdSetCheck"].v;
            hit = true;
        }
        if (store["osdEnableCombo"] !== undefined) {
            s.osdDisplayIndex = store["osdEnableCombo"].v;
            hit = true;
        }
        if (store["osdTimeFormatCombo"] !== undefined) {
            s.timeFormatIndex = store["osdTimeFormatCombo"].v;
            hit = true;
        }
        if (store["osdShowWeekCheck"] !== undefined) {
            s.showWeek = store["osdShowWeekCheck"].v;
            hit = true;
        }
        if (store["osdTimeShowPosCombo"] !== undefined) {
            s.titlePosIndex = store["osdTimeShowPosCombo"].v;
            hit = true;
        }
        if (store["osdTitleInput"] !== undefined) {
            s.titleContent = store["osdTitleInput"].v;
            hit = true;
        }
        if (hit)
            s.saved = true;
    }

    function copyMap(src) {
        var m = {
        };
        for (var k in src) m[k] = src[k]
        return m;
    }

    // 记录某个页面已保存
    function markSaved(key) {
        var s = {
        };
        for (var k in root.savedKeys) s[k] = root.savedKeys[k]
        s[key] = true;
        root.savedKeys = s;
    }

    // 未保存的页面：其“设置XXX”勾选（含左侧树对应节点）回到打开弹窗前的状态
    function rollbackUnsavedChecks() {
        var m = root.copyMap(root.checkedMap);
        var changed = false;
        for (var key in m) {
            if (root.savedKeys[key] === true)
                continue;

            var orig = root.openCheckedMap[key] === true;
            if (m[key] !== orig) {
                m[key] = orig;
                changed = true;
            }
        }
        if (changed)
            root.checkedMap = m;

    }

    // 子项是否已勾选
    function isChecked(key) {
        return root.checkedMap[key] === true;
    }

    // 设置单个子项勾选状态（重建对象以触发绑定更新）
    function setChecked(key, value) {
        if (root.checkedMap[key] === value)
            return ;

        var m = {
        };
        for (var k in root.checkedMap) m[k] = root.checkedMap[k]
        m[key] = value;
        root.checkedMap = m;
    }

    // 勾选/取消勾选整个分组（整组一次赋值，只触发一轮绑定更新）
    function setGroupChecked(groupIndex, value) {
        var items = root.groups[groupIndex].items;
        var m = {
        };
        for (var k in root.checkedMap) m[k] = root.checkedMap[k]
        for (var i = 0; i < items.length; i++) m[items[i].key] = value
        root.checkedMap = m;
    }

    // ===== "执行修改（配置其他参数）"：按勾选子节点构造下发序列 =====
    // 子节点 key -> 动作名（遮罩进度提示用）
    function batchActionName(key) {
        var map = {
            "network": qsTr("以太网"),
            "gb28181": qsTr("28181接入"),
            "videoCapture": qsTr("视频采集"),
            "timeTitle": "OSD",
            "videoEncode": qsTr("视频编码"),
            "audioEncode": qsTr("音频编码"),
            "audioReconfig": qsTr("音量配置"),
            "motionDetect": qsTr("移动侦测"),
            "audioDetect": qsTr("声音侦测"),
            "account": qsTr("账号"),
            "clock": qsTr("时钟"),
            "maintenance": qsTr("定期维护"),
            "language": qsTr("设备语言")
        };
        return map[key] || key;
    }

    // 按 groups 顺序收集勾选的子节点，构造下发给 BatchSettingsTask 的设置项序列：
    // [{key, name, action}]——URL/请求方法/JSON 包体全部由 BatchSettingsTask（C++）从
    // other_settings.json 组装：保存过 → POST {"cmd": "setXXX", "payload": {...}}，
    // 没保存过 → GET {"cmd": "getXXX"}；无协议映射的面板（language 等没有指令名）C++ 侧跳过
    function buildBatchItems() {
        var items = [];
        for (var g = 0; g < root.groups.length; g++) {
            var list = root.groups[g].items;
            for (var i = 0; i < list.length; i++) {
                var key = list[i].key;
                if (!root.isChecked(key))
                    continue;

                if (root.protocolMaps[key] === undefined)
                    continue;

                items.push({
                    "key": key,
                    "name": list[i].name,
                    "action": root.batchActionName(key)
                });
                console.log("buildBatchItems: key=" + key + ", name=" + list[i].name);
            }
        }
        return items;
    }

    // 已保存的网络设置 IP 地址
    // savedPanelValues["network"] 是 collectValues 按控件声明顺序收集的
    // {键: {k, v}} 表（键为控件 objectName），第一个 k==="ip" 的控件即
    // "IP地址"输入框（其后依次为子网掩码、网关），故取首个 ip 记录即可
    function networkSavedIp() {
        var saved = root.savedPanelValues["network"];
        if (saved === undefined)
            return "";
        for (var path in saved) {
            var rec = saved[path];
            if (rec !== undefined && rec.k === "ip")
                return rec.v;
        }
        return "";
    }

    function persistedKind(obj) {
        // 密码框（协议 userpassword/passwordconfirmation/password 需要密码值）：显式声明 objectName 的
        // 才随面板持久化（映射在 protocolMaps 里的密码框都带 objectName）；未命名密码框仍不收集
        if (obj.echoMode !== undefined && obj.echoMode === TextInput.Password)
            return typeof obj.objectName === "string" && obj.objectName !== "" ? "text" : "";

        if (obj.time !== undefined && typeof obj.time === "string")
            return "time";

        if (obj.checkState !== undefined)
            return "checked";

        if (obj.currentIndex !== undefined && obj.popup !== undefined)
            return "currentIndex";

        if (typeof obj.text === "function" && typeof obj.value === "string")
            return "ip";

        // 只读文本框也参与收集（联动计算值随面板保存/下发；当前全文件仅音频编码 bitrate 一处只读）
        if (obj instanceof TextArea || obj instanceof TextField)
            return "text";

        return "";
    }

    // 这些对象及其内部不遍历：避免误改下拉项 delegate、按钮文本等
    function isSkipped(obj) {
        return obj instanceof Popup || obj instanceof ListView || obj instanceof Menu || obj instanceof ItemDelegate || obj instanceof AbstractButton || obj instanceof ScrollBar || obj instanceof ScrollIndicator || obj instanceof Tumbler || obj instanceof Repeater;
    }

    // 取子对象列表
    function childList(obj) {
        var list = [];
        var i;
        if (obj.data !== undefined) {
            for (i = 0; i < obj.data.length; i++) list.push(obj.data[i]);
        }
        if (obj.contentData !== undefined && obj.contentData !== obj.data) {
            for (i = 0; i < obj.contentData.length; i++) list.push(obj.contentData[i]);
        }
        if (obj.contentItem !== undefined && obj.contentItem !== null && list.indexOf(obj.contentItem) < 0)
            list.push(obj.contentItem);

        return list;
    }

    // 可持久化控件的配置键：objectName（各面板控件 objectName 直接抄自己的 id，语义唯一且增删控件不错位）
    // 优先；未设置时回退位置索引（新面板控件漏写 objectName 的兜底）
    function persistedKeyOf(obj, path) {
        var name = obj.objectName;
        return typeof name === "string" && name !== "" && name.indexOf("/") < 0 ? name : path;
    }

    // 协议命令名 → 面板 key（protocolMaps 反查；读协议格式文件时用）
    function panelKeyOfCmd(cmd) {
        for (var key in root.protocolMaps) {
            if (root.protocolMaps[key].cmd === cmd)
                return key;
        }
        return "";
    }

    // 面板协议映射内：协议字段名 → 控件 objectName
    function objectNameOfField(pm, fld) {
        for (var oname in pm.fields) {
            if (pm.fields[oname].f === fld)
                return oname;
        }
        return "";
    }

    // 条件字段是否满足（fld.if = {c: 条件控件 objectName, v: 期望值}：该控件保存值为 v 时才进 payload）
    function condMatch(saved, fld) {
        if (fld.if === undefined)
            return true;
        var rec = saved[fld.if.c];
        return rec !== undefined && rec.v === fld.if.v;
    }

    // 运行结构值 → 协议值（写文件/下发时：currentIndex 按 vals 换算；checked → 1/0；num 文本数字化；其余原样）
    function valueToProtocol(fld, v) {
        if (fld.k === "currentIndex")
            return fld.vals !== undefined ? fld.vals[v] : v;
        if (fld.k === "checked")
            return v === true || v === 1 ? 1 : 0;
        if (fld.num === true && typeof v === "string") {
            var n = parseInt(v);
            return isNaN(n) ? 0 : n;
        }
        return v;
    }

    // 协议值 → 运行结构原生值（读回文件时：vals 反查 index、1/0 → 勾选、数字 → 文本，控件回填不跑类型）
    function valueFromProtocol(fld, v) {
        if (fld.k === "currentIndex")
            return fld.vals !== undefined ? fld.vals.indexOf(v) : v;
        if (fld.k === "checked")
            return v === 1 || v === true;
        if (fld.num === true)
            return String(v);
        return v;
    }

    // 嵌套路径（"a/b"）写入 payload 对象（中间层级不存在时逐层创建）
    function setPayloadPath(payload, path, v) {
        var parts = path.split("/");
        var cur = payload;
        for (var i = 0; i < parts.length - 1; i++) {
            if (cur[parts[i]] === undefined)
                cur[parts[i]] = {};
            cur = cur[parts[i]];
        }
        cur[parts[parts.length - 1]] = v;
    }

    // 嵌套 payload 对象展平成 {"a/b": 值} 路径表（读回文件时反查控件用）
    function flattenPayload(obj, prefix, out) {
        for (var k in obj) {
            var path = prefix === "" ? k : prefix + "/" + k;
            if (obj[k] !== null && typeof obj[k] === "object")
                root.flattenPayload(obj[k], path, out);
            else
                out[path] = obj[k];
        }
    }

    // 协议面板 payload 组装（写文件与下发共用）：fixed 固定字段在前，控件字段按映射换算，
    // 映射外的控件（如面板勾选框、无协议对应的控件）不进 payload，if 条件不满足的字段跳过
    function protocolPayload(key, saved) {
        var pm = root.protocolMaps[key];
        var payload = {};
        if (pm.fixed !== undefined) {
            for (var fx in pm.fixed)
                root.setPayloadPath(payload, fx, pm.fixed[fx]);
        }
        for (var oname in saved) {
            var fld = pm.fields[oname];
            if (fld === undefined || !root.condMatch(saved, fld))
                continue;
            root.setPayloadPath(payload, fld.f, root.valueToProtocol(fld, saved[oname].v));
        }
        return payload;
    }

    // 遍历面板，收集所有可持久化控件的当前值（labels 同步收集控件可读名，仅供人工查看配置文件；
    // 每条附 p=位置索引，供下发时按设备协议还原位置键）
    function collectValues(obj, path, out, labels) {
        var kind = root.persistedKind(obj);
        if (kind !== "") {
            var key = root.persistedKeyOf(obj, path);
            var v;
            if (kind === "time")
                v = obj.time;
            else if (kind === "checked")
                v = obj.checked;
            else if (kind === "currentIndex")
                v = obj.currentIndex;
            else if (kind === "ip")
                v = obj.text();
            else
                v = obj.text;
            out[key] = {"k": kind, "v": v, "p": path};
            labels[key] = root.controlLabel(obj);
            return ;
        }
        if (root.isSkipped(obj))
            return ;

        var kids = root.childList(obj);
        for (var i = 0; i < kids.length; i++) root.collectValues(kids[i], path + "/" + i, out, labels)
    }

    // 用已保存的值回填面板控件（objectName 键优先；旧配置文件是位置键，miss 时回退位置键兼容）
    function applyValues(obj, path, store) {
        var kind = root.persistedKind(obj);
        if (kind !== "") {
            var rec = store[root.persistedKeyOf(obj, path)];
            if (rec === undefined)
                rec = store[path];
            if (rec === undefined)
                return ;

            if (kind === "time")
                obj.time = rec.v;
            else if (kind === "checked")
                obj.checked = rec.v;
            else if (kind === "currentIndex")
                obj.currentIndex = rec.v;
            else if (kind === "ip")
                obj.value = rec.v;
            else
                obj.text = rec.v;
            return ;
        }
        if (root.isSkipped(obj))
            return ;

        var kids = root.childList(obj);
        for (var i = 0; i < kids.length; i++) root.applyValues(kids[i], path + "/" + i, store)
    }

    // 点“保存”：提交当前面板所有控件的值，并弹出保存成功提示
    function saveCurrentPanel() {
        if (!panelLoader.item)
            return ;

        var values = {
        };
        var labels = {
        };
        root.collectValues(panelLoader.item, "0", values, labels);
        var m = {
        };
        for (var k in root.savedPanelValues) m[k] = root.savedPanelValues[k]
        m[root.selectedKey] = values;
        root.savedPanelValues = m;
        var nm = {
        };
        for (var nk in root.savedPanelNames) nm[nk] = root.savedPanelNames[nk]
        nm[root.selectedKey] = labels;
        root.savedPanelNames = nm;
        // OSD设置页额外写入与“OSD修改”弹窗共用的参数（同步函数定义在面板内部，通过 item 调用）
        if (root.selectedKey === "timeTitle" && panelLoader.item.writeShared)
            panelLoader.item.writeShared(root.sharedOsd);

        root.markSaved(root.selectedKey);
        // 保存即固化全部勾选状态：任何界面点保存，左侧子节点勾选与各页
        root.openCheckedMap = root.copyMap(root.checkedMap);
        // 各面板参数持久化到独立 JSON 文件 other_settings.json：程序下次启动时按其恢复
        root.persistPanelValues();
        saveTipBox.show(qsTr("温馨提示"), qsTr("保存成功"));
    }

    // 各面板参数表写入独立 JSON 文件 other_settings.json（缩进格式，便于手工查看编辑）：
    // - 有协议映射的面板（protocolMaps）：按设备协议格式存——顶层键为协议命令名，
    //   {"switch": 面板勾选状态("checked"/"none"), "payload": {协议字段: 控件值}}，手工修改只改 payload 里的值
    // - 其余面板：键=控件 objectName 的 {k, v, name, p} 表（手工修改只改 v）
    // - "_hint"：文件结构说明；旧格式面板的 "_name"/"name" 为显示名注释
    // 下划线开头的键与 name 字段不参与恢复
    function persistPanelValues() {
        var out = {
            "_hint": "各设置页点保存后的参数; 协议格式面板(如netInfo): switch=面板勾选状态, payload内按设备协议字段存值(手工修改只改payload里的值); 其余面板: 键=控件id(objectName), 每条v=控件值(只改v), k=控件类型, name=控件说明, p=下发位置索引(勿改); 下划线开头的键为说明, 不参与恢复"
        };
        for (var key in root.savedPanelValues) {
            var store = root.savedPanelValues[key];
            var pm = root.protocolMaps[key];
            if (pm !== undefined) {
                // 协议格式面板：{"switch": 面板勾选状态, "payload": {协议字段: 控件值}}；
                // payload 组装走 protocolPayload（fixed 固定字段 + vals/num/if 换算，映射外的控件不进 payload）
                out[pm.cmd] = {
                    "switch": root.isChecked(key) ? "checked" : "none",
                    "payload": root.protocolPayload(key, store)
                };
                continue;
            }
            var names = root.savedPanelNames[key];
            var panel = {
                "_name": root.panelNameOf(key)
            };
            for (var path in store) {
                var rec = store[path];
                panel[path] = {
                    "k": rec.k,
                    "v": rec.v,
                    "name": names !== undefined && names[path] !== undefined ? names[path] : "",
                    "p": rec.p !== undefined ? rec.p : path
                };
            }
            out[key] = panel;
        }
        ConfigureManager.saveOtherSettingsValues(JSON.stringify(out));
    }

    // 面板 key → 左侧分类树显示名
    function panelNameOf(key) {
        for (var g = 0; g < root.groups.length; g++) {
            var list = root.groups[g].items;
            for (var i = 0; i < list.length; i++) {
                if (list[i].key === key)
                    return list[i].name;
            }
        }
        return "";
    }

    // 取控件可读名：优先同容器里的 Label 文本；找不到再取自身 text（复选框等，输入框的 text 是值不取）
    function controlLabel(obj) {
        var p = obj.parent;
        if (p) {
            var kids = root.childList(p);
            for (var i = 0; i < kids.length; i++) {
                var k = kids[i];
                if (k === obj || root.persistedKind(k) !== "" || root.isSkipped(k))
                    continue;
                var t = k.text;
                if (typeof t === "string" && t !== "")
                    return t;
            }
        }
        if (typeof obj.text === "string" && obj.text !== "" && !(obj instanceof TextField) && !(obj instanceof TextArea))
            return obj.text;
        return "";
    }

    // 点分 IP 转 4 段整数数组；格式非法返回 null
    function ipToIntArray(ip) {
        if (typeof ip !== "string")
            return null;

        var parts = ip.split(".");
        if (parts.length !== 4)
            return null;

        var out = [];
        for (var i = 0; i < 4; i++) {
            var n = parseInt(parts[i], 10);
            if (isNaN(n) || n < 0 || n > 255)
                return null;

            out.push(n);
        }
        return out;
    }

    // 按 mask 判断两 IP 是否处于同一网段
    function sameSubnet(ipA, ipB, mask) {
        var a = ipToIntArray(ipA);
        var b = ipToIntArray(ipB);
        var m = ipToIntArray(mask);
        if (!a || !b || !m)
            return false;

        for (var i = 0; i < 4; i++) {
            if ((a[i] & m[i]) !== (b[i] & m[i]))
                return false;

        }
        return true;
    }

    // 网卡信息 → IP/掩码/网关 显示值（网关取不到时显示 0.0.0.0，与设定IP弹窗口径一致）
    function nicInfoOf(nic) {
        var ips = nic["ipv4"] || [];
        var gw = nic["gateway"] || "";
        return {
            "ip": ips.length > 0 ? ips[0] : "",
            "mask": nic["netmask"] || "",
            "gateway": gw.length > 0 ? gw : "0.0.0.0"
        };
    }

    // 网络设置 IP/掩码/网关 的联动默认值：
    // 1) 设备列表非空：与本机中与第一台设备同网段的网卡一致（找不到同网段网卡回退到后两条）；
    // 2) 列表为空且选中具体网卡：与选中网卡一致；
    // 3) 列表为空且选中“所有网卡”：与本机第一张有 IPv4 的网卡一致
    readonly property var networkInfo: {
        if (root.firstDeviceIp !== "") {
            for (var i = 0; i < root.nicList.length; i++) {
                var ips = root.nicList[i]["ipv4"] || [];
                var mask = root.nicList[i]["netmask"] || "";
                if (ips.length > 0 && root.sameSubnet(ips[0], root.firstDeviceIp, mask))
                    return root.nicInfoOf(root.nicList[i]);
            }
        }
        if (root.selectedNic)
            return root.nicInfoOf(root.selectedNic);
        for (var j = 0; j < root.nicList.length; j++) {
            if (((root.nicList[j]["ipv4"] || []).length) > 0)
                return root.nicInfoOf(root.nicList[j]);
        }
        return {
            "ip": "",
            "mask": "",
            "gateway": ""
        };
    }

    // 面板加载完成后回填已保存的参数（没有保存过则保持默认值）
    function restorePanel(panelItem) {
        if (!panelItem)
            return ;

        var store = root.savedPanelValues[root.selectedKey];
        if (store !== undefined)
            root.applyValues(panelItem, "0", store);

        // OSD设置页：共享参数优先（可能刚被“OSD修改”弹窗保存过）
        if (root.selectedKey === "timeTitle" && panelItem.readShared)
            panelItem.readShared(root.sharedOsd);

    }

    // 把表单容器内的行统一启用/禁用（exempt 指定的行除外，一般是“开关”所在行）
    function setRowsEnabled(container, exempt, enabled) {
        if (!container || container.data === undefined)
            return ;

        var kids = container.data;
        for (var i = 0; i < kids.length; i++) {
            var k = kids[i];
            if (k === exempt || k.enabled === undefined)
                continue;

            k.enabled = enabled;
        }
    }

    width: ScreenTools.scaleNum(1000)
    height: ScreenTools.scaleNum(660)
    modal: true
    dim: true
    closePolicy: Popup.CloseOnEscape
    clip: true
    anchors.centerIn: Overlay.overlay
    title: qsTr("其它设置")
    // 每次打开恢复默认选中“网络设置”，并记录当前勾选状态用于未保存回滚
    // “OSD修改”弹窗点保存：把这份数据并入本弹窗的 OSD 运行结构并按协议格式写入 other_settings.json
    // （两边共用同一个 osd 条目）；勾选状态一并固化——弹窗“设定时间和标题”勾选等同本页“OSD设置”面板勾选，
    // 之后关闭本弹窗不会被当作未保存修改回滚
    Connections {
        target: root.sharedOsd

        function onOsdSavedFromDialog() {
            var s = root.sharedOsd;
            var values = {
                "osdSetCheck": {
                    "k": "checked",
                    "v": s.setTimeTitle
                },
                "osdEnableCombo": {
                    "k": "currentIndex",
                    "v": s.osdDisplayIndex
                },
                "osdTimeFormatCombo": {
                    "k": "currentIndex",
                    "v": s.timeFormatIndex
                },
                "osdShowWeekCheck": {
                    "k": "checked",
                    "v": s.showWeek
                },
                "osdTimeShowPosCombo": {
                    "k": "currentIndex",
                    "v": s.titlePosIndex
                },
                "osdTitleInput": {
                    "k": "text",
                    "v": s.titleContent
                }
            };
            // 映射外已有值（叠加方式/时间显示位置等弹窗没有的项）保留，弹窗拥有的项覆盖
            var merged = ({
            });
            var old = root.savedPanelValues["timeTitle"];
            for (var ok in old) merged[ok] = old[ok]
            for (var nk in values) merged[nk] = values[nk]
            var m = ({
            });
            for (var pk in root.savedPanelValues) m[pk] = root.savedPanelValues[pk]
            m["timeTitle"] = merged;
            root.savedPanelValues = m;
            root.setChecked("timeTitle", s.setTimeTitle);
            root.markSaved("timeTitle");
            root.openCheckedMap = root.copyMap(root.checkedMap);
            root.persistPanelValues();
        }

    }

    onAboutToShow: {
        selectedKey = "network";
        root.openCheckedMap = root.copyMap(root.checkedMap);
        root.savedKeys = {
        };
        // 重新加载面板：未保存的编辑被丢弃，按“已保存值 or 默认值”重建
        root.panelSuspended = false;
    }
    // 关闭窗口（✕ / ESC / 程序关闭）时：卸掉面板 + 回滚未保存页面的勾选状态
    onAboutToHide: {
        root.panelSuspended = true;
        root.rollbackUnsavedChecks();
    }
    padding: ScreenTools.scaleNum(16)

    // ===== 网络设置面板 =====
    Component {
        id: networkPanel

        ColumnLayout {
            anchors.fill: parent
            spacing: ScreenTools.scaleNum(10)

            AppCheckBox {
                id: ethCheck
                objectName: "ethCheck"

                text: qsTr("设置以太网")
                checked: false
                // 与左侧树“网络设置”前的复选框强绑定（双向同步）
                onCheckedChanged: root.setChecked("network", checked)

                Binding {
                    target: ethCheck
                    property: "checked"
                    value: root.isChecked("network")
                }

            }

            // ===== 中间：可设置项区域（浅色边框框起来） =====
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent"
                border.width: 1
                border.color: "#DCDCDC"
                radius: ScreenTools.scaleNum(4)
                clip: true

                // 表单总高度可能超过框内可用高度，超出时在框内滚动
                ScrollView {
                    id: netFieldScroll

                    anchors.fill: parent
                    anchors.margins: ScreenTools.scaleNum(10)
                    clip: true
                    background: null

                    ColumnLayout {
                        width: netFieldScroll.availableWidth
                        spacing: ScreenTools.scaleNum(10)

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("IP地址")
                            }

                            IpInput {
                                id: ipAddrInput
                                objectName: "ipAddrInput"

                                Layout.preferredWidth: ScreenTools.scaleNum(220)
                                // 联动默认值：与设备列表第一台设备同网段的网卡（详见 networkInfo）
                                value: root.networkInfo["ip"]
                            }

                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("子网掩码")
                            }

                            IpInput {
                                id: maskInput
                                objectName: "maskInput"

                                Layout.preferredWidth: ScreenTools.scaleNum(220)
                                // 联动默认值：与 IP 地址同源的网卡子网掩码
                                value: root.networkInfo["mask"]
                            }

                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("网关")
                            }

                            IpInput {
                                id: gwInput
                                objectName: "gwInput"

                                Layout.preferredWidth: ScreenTools.scaleNum(220)
                                // 联动默认值：与 IP 地址同源的网卡网关
                                value: root.networkInfo["gateway"]
                            }

                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: "DNS1"
                            }

                            IpInput {
                                id: dns1Input
                                objectName: "dns1Input"

                                Layout.preferredWidth: ScreenTools.scaleNum(220)
                                value: "114.114.114.114"
                            }

                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: "DNS2"
                            }

                            IpInput {
                                id: dns2Input
                                objectName: "dns2Input"

                                Layout.preferredWidth: ScreenTools.scaleNum(220)
                                value: "8.8.8.8"
                            }

                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: "DHCP"
                            }

                            AppComboBox {
                                id: dhcpCombo
                                objectName: "dhcpCombo"

                                Layout.preferredWidth: ScreenTools.scaleNum(220)
                                Layout.preferredHeight: root.ctrlH
                                model: [qsTr("禁用"), qsTr("启用")]
                            }

                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: "MTU"
                            }

                            AppTextField {
                                id: mtuInput
                                objectName: "mtuInput"

                                Layout.preferredWidth: ScreenTools.scaleNum(220)
                                text: "1400"
                            }

                        }

                    }

                }

            }

            // 网络设置共 8 项 ≤ 11：单列，保存行向上紧贴表单
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: ScreenTools.scaleNum(14)
                spacing: ScreenTools.scaleNum(8)

                Item {
                    Layout.fillWidth: true
                }

                AppButton {
                    Layout.preferredHeight: root.ctrlH
                    highlighted: true
                    text: qsTr("保存")
                    onClicked: {
                        root.saveCurrentPanel();
                    }
                }

            }

        }

    }

    // ===== OSD设置面板 =====
    Component {
        id: osdPanel

        ColumnLayout {
            id: osdRoot

            // 本页标签列宽（容纳“标题内容（多行用^分隔）”长标签）
            readonly property int osdLabelWidth: ScreenTools.scaleNum(200)

            // “OSD显示”为“禁用”时，除该开关所在行外，其余项全部不可编辑
            function applyEnableState() {
                root.setRowsEnabled(osdFormCol, osdEnableRow, osdEnableCombo.currentIndex === 0);
            }

            // 与“OSD修改”弹窗共用参数：本页点保存时写回（只同步两边都有的项）
            function writeShared(s) {
                if (!s)
                    return ;

                s.setTimeTitle = osdSetCheck.checked;
                s.osdDisplayIndex = osdEnableCombo.currentIndex;
                s.timeFormatIndex = osdTimeFormatCombo.currentIndex;
                s.showWeek = osdShowWeekCheck.checked;
                // 弹窗里的“标题位置”对应本页的“时间显示位置”
                s.titlePosIndex = osdTimeShowPosCombo.currentIndex;
                s.titleContent = osdTitleInput.text;
                s.saved = true;
            }

            // 与“OSD修改”弹窗共用参数：打开本页时回填（没保存过则保持默认）
            function readShared(s) {
                if (!s || !s.saved)
                    return ;

                // 总开关 osdSetCheck 不回填：它与左侧树勾选强绑定（Binding 正向同步 checkedMap），
                // 共享对象的 setTimeTitle 不随树勾选实时更新，用它覆盖面板开关会经
                // onCheckedChanged 反向回写树勾选——点进面板勾选被“偷掉”的根源
                osdEnableCombo.currentIndex = s.osdDisplayIndex;
                osdTimeFormatCombo.currentIndex = s.timeFormatIndex;
                osdShowWeekCheck.checked = s.showWeek;
                osdTimeShowPosCombo.currentIndex = s.titlePosIndex;
                osdTitleInput.text = s.titleContent;
            }

            anchors.fill: parent
            spacing: ScreenTools.scaleNum(10)
            Component.onCompleted: applyEnableState()

            AppCheckBox {
                id: osdSetCheck
                objectName: "osdSetCheck"

                text: qsTr("设置时间和标题")
                checked: false
                // 与左侧树“OSD设置”前的复选框强绑定（双向同步）
                onCheckedChanged: root.setChecked("timeTitle", checked)

                Binding {
                    target: osdSetCheck
                    property: "checked"
                    value: root.isChecked("timeTitle")
                }

            }

            // ===== 中间：可设置项区域（浅色边框框起来） =====
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent"
                border.width: 1
                border.color: "#DCDCDC"
                radius: ScreenTools.scaleNum(4)
                clip: true

                // 表单总高度可能超过框内可用高度，超出时在框内滚动
                ScrollView {
                    id: osdFieldScroll

                    anchors.fill: parent
                    anchors.margins: ScreenTools.scaleNum(10)
                    clip: true
                    background: null

                    ColumnLayout {
                        id: osdFormCol

                        width: osdFieldScroll.availableWidth
                        spacing: ScreenTools.scaleNum(10)

                        // 1) OSD显示
                        RowLayout {
                            id: osdEnableRow

                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: osdRoot.osdLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("OSD显示")
                            }

                            AppComboBox {
                                id: osdEnableCombo
                                objectName: "osdEnableCombo"

                                Layout.preferredWidth: ScreenTools.scaleNum(220)
                                Layout.preferredHeight: root.ctrlH
                                model: [qsTr("启用"), qsTr("禁用")]
                                onCurrentIndexChanged: osdRoot.applyEnableState()
                            }

                        }

                        // 2) 叠加附加信息
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: osdRoot.osdLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("叠加附加信息")
                            }

                            AppComboBox {
                                id: osdOverlayCombo
                                objectName: "osdOverlayCombo"

                                Layout.preferredWidth: ScreenTools.scaleNum(220)
                                Layout.preferredHeight: root.ctrlH
                                model: [qsTr("不叠加"), qsTr("叠加到分辨率"), qsTr("叠加到码率"), qsTr("叠加到分辨率和码率")]
                            }

                        }

                        // 3) 时间位置
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: osdRoot.osdLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("时间位置")
                            }

                            AppComboBox {
                                id: osdTimePosCombo
                                objectName: "osdTimePosCombo"

                                Layout.preferredWidth: ScreenTools.scaleNum(220)
                                Layout.preferredHeight: root.ctrlH
                                model: [qsTr("不显示"), qsTr("左上角"), qsTr("右上角"), qsTr("左下角"), qsTr("右下角")]
                                currentIndex: 1
                            }

                        }

                        // 4) 时间显示格式 + 显示星期
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: osdRoot.osdLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("时间显示格式")
                            }

                            AppComboBox {
                                id: osdTimeFormatCombo
                                objectName: "osdTimeFormatCombo"

                                Layout.preferredWidth: ScreenTools.scaleNum(220)
                                Layout.preferredHeight: root.ctrlH
                                model: ["yyyy-mm-dd hh:mm:ss", "yyyy/mm/dd hh:mm:ss", "yy-mm-dd hh:mm:ss", "yy/mm/dd hh:mm:ss", "hh:mm:ss dd/mm/yyyy", "hh:mm:ss dd-mm-yyyy", "hh:mm:ss mm/dd/yyyy", "hh:mm:ss mm-dd-yyyy"]
                            }

                            AppCheckBox {
                                id: osdShowWeekCheck
                                objectName: "osdShowWeekCheck"

                                text: qsTr("显示星期")
                                checked: false
                            }

                        }

                        // 5) 时间显示位置
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: osdRoot.osdLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("标题位置")
                            }

                            AppComboBox {
                                id: osdTimeShowPosCombo
                                objectName: "osdTimeShowPosCombo"

                                Layout.preferredWidth: ScreenTools.scaleNum(220)
                                Layout.preferredHeight: root.ctrlH
                                model: [qsTr("不显示"), qsTr("左上角"), qsTr("右上角"), qsTr("左下角"), qsTr("右下角")]
                                currentIndex: 4
                            }

                        }

                        // 6) 标题内容（多行用^分隔）
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: osdRoot.osdLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("标题内容（多行用^分隔）")
                            }

                            AppTextField {
                                id: osdTitleInput
                                objectName: "osdTitleInput"

                                // 与上方输入框保持同样的展示宽度（不再用 fillWidth 拉长），最大宽度上限 400
                                Layout.preferredWidth: ScreenTools.scaleNum(220)
                                Layout.maximumWidth: ScreenTools.scaleNum(400)
                            }

                        }

                    }

                }

            }

            // ===== 底部：保存按钮独占一行 =====
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: ScreenTools.scaleNum(14)
                spacing: ScreenTools.scaleNum(8)

                Item {
                    Layout.fillWidth: true
                }

                AppButton {
                    Layout.preferredHeight: root.ctrlH
                    highlighted: true
                    text: qsTr("保存")
                    onClicked: {
                        root.saveCurrentPanel();
                    }
                }

            }

        }

    }

    // ===== 其它设置页占位（待对接协议后逐页补充） =====
    Component {
        id: placeholderPanel

        Item {
            anchors.fill: parent

            Label {
                anchors.centerIn: parent
                color: "#888888"
                text: "No data"
            }

        }

    }

    // ===== 28181接入1设置面板 =====
    Component {
        id: gb28181Panel

        ColumnLayout {
            id: gbRoot

            // “启用28181”为“禁用”时，除该开关所在行外，其余项全部不可编辑
            function applyEnableState() {
                var on = gbEnableCombo.currentIndex === 1;
                root.setRowsEnabled(gbLeftCol, gbEnableRow, on);
                root.setRowsEnabled(gbRightCol, null, on);
            }

            anchors.fill: parent
            spacing: ScreenTools.scaleNum(10)
            Component.onCompleted: applyEnableState()

            // 设置28181 分组框（带边框）
            AppCheckBox {
                id: gbSetCheck
                objectName: "gbSetCheck"

                text: qsTr("设置28181")
                checked: false
                // 与左侧树“28181接入设置”前的复选框强绑定（双向同步）
                onCheckedChanged: root.setChecked("gb28181", checked)

                Binding {
                    target: gbSetCheck
                    property: "checked"
                    value: root.isChecked("gb28181")
                }

            }

            // ===== 中间：可设置项区域 =====
            // 项数 > 11：左右两列、宽度平均分配、高度填满剩余空间（本页 15 项走此分支）；
            // 项数 ≤ 11 时：改为单列，并将本区域 Layout.fillHeight 改为 false（高度自适应），
            // 下方保存按钮所在行会自动向上紧贴表单
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent"
                border.width: 1
                border.color: "#DCDCDC"
                radius: ScreenTools.scaleNum(4)
                clip: true

                // 表单总高度可能超过框内可用高度，超出时在框内滚动
                ScrollView {
                    id: gbFieldScroll

                    anchors.fill: parent
                    anchors.margins: ScreenTools.scaleNum(10)
                    clip: true
                    background: null

                    RowLayout {
                        width: gbFieldScroll.availableWidth
                        spacing: ScreenTools.scaleNum(16)

                        // ===== 左列（最多 11 项） =====
                        ColumnLayout {
                            id: gbLeftCol

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.alignment: Qt.AlignTop
                            spacing: ScreenTools.scaleNum(10)

                            RowLayout {
                                id: gbEnableRow

                                Layout.fillWidth: true
                                spacing: ScreenTools.scaleNum(8)

                                Label {
                                    Layout.preferredWidth: root.panelLabelWidth
                                    Layout.preferredHeight: root.ctrlH
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    text: qsTr("启用28181")
                                }

                                AppComboBox {
                                    id: gbEnableCombo
                                    objectName: "gbEnableCombo"

                                    Layout.preferredWidth: ScreenTools.scaleNum(180)
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.ctrlH
                                    model: [qsTr("禁用"), qsTr("启用")]
                                    onCurrentIndexChanged: gbRoot.applyEnableState()
                                }

                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: ScreenTools.scaleNum(8)

                                Label {
                                    Layout.preferredWidth: root.panelLabelWidth
                                    Layout.preferredHeight: root.ctrlH
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    text: qsTr("本地SIP端口")
                                }

                                AppTextField {
                                    id: localSipPortInput
                                    objectName: "localSipPortInput"

                                    Layout.preferredWidth: ScreenTools.scaleNum(180)
                                    Layout.fillWidth: true
                                    text: "0"
                                }

                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: ScreenTools.scaleNum(8)

                                Label {
                                    Layout.preferredWidth: root.panelLabelWidth
                                    Layout.preferredHeight: root.ctrlH
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    text: qsTr("SIP服务器ID")
                                }

                                AppTextField {
                                    id: sipServerIdInput
                                    objectName: "sipServerIdInput"

                                    Layout.preferredWidth: ScreenTools.scaleNum(180)
                                    Layout.fillWidth: true
                                }

                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: ScreenTools.scaleNum(8)

                                Label {
                                    Layout.preferredWidth: root.panelLabelWidth
                                    Layout.preferredHeight: root.ctrlH
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    text: qsTr("SIP服务器域")
                                }

                                AppTextField {
                                    id: sipServerDomainInput
                                    objectName: "sipServerDomainInput"

                                    Layout.preferredWidth: ScreenTools.scaleNum(180)
                                    Layout.fillWidth: true
                                }

                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: ScreenTools.scaleNum(8)

                                Label {
                                    Layout.preferredWidth: root.panelLabelWidth
                                    Layout.preferredHeight: root.ctrlH
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    text: qsTr("SIP服务器地址")
                                }

                                IpInput {
                                    id: sipServerIpInput
                                    objectName: "sipServerIpInput"

                                    Layout.preferredWidth: ScreenTools.scaleNum(180)
                                    Layout.fillWidth: true
                                }

                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: ScreenTools.scaleNum(8)

                                Label {
                                    Layout.preferredWidth: root.panelLabelWidth
                                    Layout.preferredHeight: root.ctrlH
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    text: qsTr("SIP服务器端口")
                                }

                                AppTextField {
                                    id: sipServerPortInput
                                    objectName: "sipServerPortInput"

                                    Layout.preferredWidth: ScreenTools.scaleNum(180)
                                    Layout.fillWidth: true
                                    text: "0"
                                }

                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: ScreenTools.scaleNum(8)

                                Label {
                                    Layout.preferredWidth: root.panelLabelWidth
                                    Layout.preferredHeight: root.ctrlH
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    text: qsTr("SIP用户名")
                                }

                                AppTextField {
                                    id: sipUserInput
                                    objectName: "sipUserInput"

                                    Layout.preferredWidth: ScreenTools.scaleNum(180)
                                    Layout.fillWidth: true
                                }

                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: ScreenTools.scaleNum(8)

                                Label {
                                    Layout.preferredWidth: root.panelLabelWidth
                                    Layout.preferredHeight: root.ctrlH
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    text: qsTr("SIP用户认证ID")
                                }

                                AppTextField {
                                    id: sipAuthIdInput
                                    objectName: "sipAuthIdInput"

                                    Layout.preferredWidth: ScreenTools.scaleNum(180)
                                    Layout.fillWidth: true
                                }

                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: ScreenTools.scaleNum(8)

                                Label {
                                    Layout.preferredWidth: root.panelLabelWidth
                                    Layout.preferredHeight: root.ctrlH
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    text: qsTr("密码")
                                }

                                AppPasswordField {
                                    id: passwordInput
                                    objectName: "passwordInput"

                                    Layout.preferredWidth: ScreenTools.scaleNum(180)
                                    Layout.fillWidth: true
                                }

                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: ScreenTools.scaleNum(8)

                                Label {
                                    Layout.preferredWidth: root.panelLabelWidth
                                    Layout.preferredHeight: root.ctrlH
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    text: qsTr("确认密码")
                                }

                                AppPasswordField {
                                    id: confirmPasswordInput
                                    objectName: "confirmPasswordInput"

                                    Layout.preferredWidth: ScreenTools.scaleNum(180)
                                    Layout.fillWidth: true
                                }

                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: ScreenTools.scaleNum(8)

                                Label {
                                    Layout.preferredWidth: root.panelLabelWidth
                                    Layout.preferredHeight: root.ctrlH
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    text: qsTr("注册有效期")
                                }

                                AppTextField {
                                    id: registerExpireInput
                                    objectName: "registerExpireInput"

                                    Layout.preferredWidth: ScreenTools.scaleNum(180)
                                    Layout.fillWidth: true
                                }

                            }

                        }

                        // ===== 右列（超出 11 项的其余项） =====
                        ColumnLayout {
                            id: gbRightCol

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.alignment: Qt.AlignTop
                            spacing: ScreenTools.scaleNum(10)

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: ScreenTools.scaleNum(8)

                                Label {
                                    Layout.preferredWidth: root.panelLabelWidth
                                    Layout.preferredHeight: root.ctrlH
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    text: qsTr("心跳周期")
                                }

                                AppTextField {
                                    id: heartbeatInput
                                    objectName: "heartbeatInput"

                                    Layout.preferredWidth: ScreenTools.scaleNum(180)
                                    Layout.fillWidth: true
                                    text: "0"
                                }

                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: ScreenTools.scaleNum(8)

                                Label {
                                    Layout.preferredWidth: root.panelLabelWidth
                                    Layout.preferredHeight: root.ctrlH
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    wrapMode: Text.WrapAnywhere
                                    text: qsTr("最大心跳超时次数")
                                }

                                AppTextField {
                                    id: heartbeatTimeoutInput
                                    objectName: "heartbeatTimeoutInput"

                                    Layout.preferredWidth: ScreenTools.scaleNum(180)
                                    Layout.fillWidth: true
                                    text: "0"
                                }

                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: ScreenTools.scaleNum(8)

                                Label {
                                    Layout.preferredWidth: root.panelLabelWidth
                                    Layout.preferredHeight: root.ctrlH
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    text: qsTr("28181码流索引")
                                }

                                AppComboBox {
                                    id: streamIndexCombo
                                    objectName: "streamIndexCombo"

                                    Layout.preferredWidth: ScreenTools.scaleNum(180)
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.ctrlH
                                    model: [qsTr("主码流"), qsTr("子码流")]
                                    currentIndex: 1
                                }

                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: ScreenTools.scaleNum(8)

                                Label {
                                    Layout.preferredWidth: root.panelLabelWidth
                                    Layout.preferredHeight: root.ctrlH
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignRight
                                    text: qsTr("报警ID")
                                }

                                AppTextField {
                                    id: alarmIdInput
                                    objectName: "alarmIdInput"

                                    Layout.preferredWidth: ScreenTools.scaleNum(180)
                                    Layout.fillWidth: true
                                }

                            }

                        }

                    }

                }

            }

            // ===== 底部：保存按钮独占一行 =====
            // 与上方内容区域间距 24px（面板统一行间距 10 + 本行上外边距 14）
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: ScreenTools.scaleNum(14)
                spacing: ScreenTools.scaleNum(8)

                Item {
                    Layout.fillWidth: true
                }

                AppButton {
                    Layout.preferredHeight: root.ctrlH
                    highlighted: true
                    text: qsTr("保存")
                    onClicked: {
                        root.saveCurrentPanel();
                    }
                }

            }

        }

    }

    // ===== 视频采集设置面板 =====
    Component {
        id: videoCapturePanel

        ColumnLayout {
            anchors.fill: parent
            spacing: ScreenTools.scaleNum(10)

            AppCheckBox {
                id: vcSetCheck
                objectName: "vcSetCheck"

                text: qsTr("设置视频采集")
                checked: false
                // 与左侧树“视频采集设置”前的复选框强绑定（双向同步）
                onCheckedChanged: root.setChecked("videoCapture", checked)

                Binding {
                    target: vcSetCheck
                    property: "checked"
                    value: root.isChecked("videoCapture")
                }

            }

            // ===== 中间：可设置项区域（浅色边框框起来） =====
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent"
                border.width: 1
                border.color: "#DCDCDC"
                radius: ScreenTools.scaleNum(4)
                clip: true

                // 左右各占一半：左表单（可滚动） + 右高级参数框（固定）
                ScrollView {
                    id: vcLeftScroll

                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: ScreenTools.scaleNum(10)
                    width: (parent.width - ScreenTools.scaleNum(20) - ScreenTools.scaleNum(24)) / 2
                    clip: true
                    background: null

                    ColumnLayout {
                        width: vcLeftScroll.availableWidth
                        spacing: ScreenTools.scaleNum(10)

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("亮度") + "(0-255)"
                            }

                            AppTextField {
                                id: vcBrightnessInput
                                objectName: "vcBrightnessInput"

                                Layout.preferredWidth: ScreenTools.scaleNum(200)
                                text: "128"
                            }

                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("饱和度") + "(0-255)"
                            }

                            AppTextField {
                                id: vcSaturationInput
                                objectName: "vcSaturationInput"

                                Layout.preferredWidth: ScreenTools.scaleNum(200)
                                text: "128"
                            }

                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("锐度") + "(0-255)"
                            }

                            AppTextField {
                                id: vcSharpnessInput
                                objectName: "vcSharpnessInput"

                                Layout.preferredWidth: ScreenTools.scaleNum(200)
                                text: "128"
                            }

                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("对比度") + "(0-255)"
                            }

                            AppTextField {
                                id: vcContrastInput
                                objectName: "vcContrastInput"

                                Layout.preferredWidth: ScreenTools.scaleNum(200)
                                text: "128"
                            }

                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("背光") + "(0-255)"
                            }

                            AppTextField {
                                id: vcBacklightInput
                                objectName: "vcBacklightInput"

                                Layout.preferredWidth: ScreenTools.scaleNum(200)
                                text: "128"
                            }

                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("白平衡")
                            }

                            AppComboBox {
                                id: vcWhiteBalanceCombo
                                objectName: "vcWhiteBalanceCombo"

                                Layout.preferredWidth: ScreenTools.scaleNum(200)
                                Layout.preferredHeight: root.ctrlH
                                model: [qsTr("自动白平衡")]
                            }

                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("水平翻转")
                            }

                            AppComboBox {
                                id: vcHFlipCombo
                                objectName: "vcHFlipCombo"

                                Layout.preferredWidth: ScreenTools.scaleNum(200)
                                Layout.preferredHeight: root.ctrlH
                                model: [qsTr("禁用"), qsTr("启用")]
                            }

                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("垂直翻转")
                            }

                            AppComboBox {
                                id: vcVFlipCombo
                                objectName: "vcVFlipCombo"

                                Layout.preferredWidth: ScreenTools.scaleNum(200)
                                Layout.preferredHeight: root.ctrlH
                                model: [qsTr("禁用"), qsTr("启用")]
                            }

                        }

                    }

                }

                // 右：高级参数分组框（标题压在边框上）
                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: ScreenTools.scaleNum(10)
                    width: (parent.width - ScreenTools.scaleNum(20) - ScreenTools.scaleNum(24)) / 2
                    color: "transparent"
                    border.width: 1
                    border.color: "#DCDCDC"
                    radius: ScreenTools.scaleNum(4)

                    Label {
                        text: qsTr("高级参数")
                        anchors.left: parent.left
                        anchors.leftMargin: ScreenTools.scaleNum(10)
                        anchors.top: parent.top
                        anchors.topMargin: -ScreenTools.scaleNum(8)

                        background: Rectangle {
                            color: "#FFFFFF"
                        }

                    }

                    ColumnLayout {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: ScreenTools.scaleNum(16)
                        anchors.topMargin: ScreenTools.scaleNum(20)
                        spacing: ScreenTools.scaleNum(10)

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth / 2
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("宽动态")
                            }

                            AppComboBox {
                                id: vcWdrCombo
                                objectName: "vcWdrCombo"

                                Layout.preferredWidth: ScreenTools.scaleNum(200)
                                Layout.preferredHeight: root.ctrlH
                                model: [qsTr("禁用"), qsTr("启用")]
                            }

                        }

                    }

                }

            }

            // ===== 底部：默认参数 + 保存按钮 =====
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: ScreenTools.scaleNum(14)
                spacing: ScreenTools.scaleNum(8)

                Item {
                    Layout.fillWidth: true
                }

                AppButton {
                    Layout.preferredHeight: root.ctrlH
                    text: qsTr("默认参数")
                    onClicked: {
                        vcBrightnessInput.text = "128";
                        vcSaturationInput.text = "128";
                        vcSharpnessInput.text = "128";
                        vcContrastInput.text = "128";
                        vcBacklightInput.text = "128";
                        vcWhiteBalanceCombo.currentIndex = 0;
                        vcHFlipCombo.currentIndex = 0;
                        vcVFlipCombo.currentIndex = 0;
                        vcWdrCombo.currentIndex = 0;
                    }
                }

                AppButton {
                    Layout.preferredHeight: root.ctrlH
                    highlighted: true
                    text: qsTr("保存")
                    onClicked: {
                        root.saveCurrentPanel();
                    }
                }

            }

        }

    }

    // ===== 视频编码设置面板 =====
    Component {
        id: videoEncodePanel

        ColumnLayout {
            id: veRoot

            // 本面板列宽：标签列 / 控件列
            readonly property int veLabelWidth: ScreenTools.scaleNum(180)
            readonly property int veFieldWidth: ScreenTools.scaleNum(180)

            anchors.fill: parent
            spacing: ScreenTools.scaleNum(10)

            AppCheckBox {
                id: veSetCheck
                objectName: "veSetCheck"

                text: qsTr("设置视频编码")
                checked: false
                // 与左侧树“视频编码”前的复选框强绑定（双向同步）
                onCheckedChanged: root.setChecked("videoEncode", checked)

                Binding {
                    target: veSetCheck
                    property: "checked"
                    value: root.isChecked("videoEncode")
                }

            }

            // ===== 中间：可设置项区域（浅色边框框起来） =====
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent"
                border.width: 1
                border.color: "#DCDCDC"
                radius: ScreenTools.scaleNum(4)
                clip: true

                // 表单总高度可能超过框内可用高度，超出时在框内滚动
                ScrollView {
                    id: veFieldScroll

                    anchors.fill: parent
                    anchors.margins: ScreenTools.scaleNum(10)
                    clip: true
                    background: null

                    ColumnLayout {
                        width: veFieldScroll.availableWidth
                        spacing: ScreenTools.scaleNum(10)

                        // 表头：主码流 / 子码流
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(16)

                            Item {
                                Layout.preferredWidth: veRoot.veLabelWidth
                                Layout.preferredHeight: root.ctrlH
                            }

                            Label {
                                Layout.preferredWidth: veRoot.veFieldWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: qsTr("主码流")
                            }

                            Label {
                                Layout.preferredWidth: veRoot.veFieldWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: qsTr("子码流")
                            }

                        }

                        // 编码格式
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(16)

                            Label {
                                Layout.preferredWidth: veRoot.veLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("编码格式")
                            }

                            AppComboBox {
                                id: veMainCodecCombo
                                objectName: "veMainCodecCombo"

                                Layout.preferredWidth: veRoot.veFieldWidth
                                Layout.preferredHeight: root.ctrlH
                                model: ["H265", "H264"]
                            }

                            AppComboBox {
                                id: veSubCodecCombo
                                objectName: "veSubCodecCombo"

                                Layout.preferredWidth: veRoot.veFieldWidth
                                Layout.preferredHeight: root.ctrlH
                                model: ["H265", "H264"]
                            }

                        }

                        // 分辨率
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(16)

                            Label {
                                Layout.preferredWidth: veRoot.veLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("分辨率")
                            }

                            AppComboBox {
                                id: veMainResCombo
                                objectName: "veMainResCombo"

                                Layout.preferredWidth: veRoot.veFieldWidth
                                Layout.preferredHeight: root.ctrlH
                                model: ["2560×1440", "2304×1296", "1920×1080", "1280×960", "1280×720"]
                                currentIndex: 1
                            }

                            AppComboBox {
                                id: veSubResCombo
                                objectName: "veSubResCombo"

                                Layout.preferredWidth: veRoot.veFieldWidth
                                Layout.preferredHeight: root.ctrlH
                                model: ["D1(720×576)", "800×448", "704×576", "640×480", "640×360", "352×288"]
                                currentIndex: 4
                            }

                        }

                        // 比特率控制
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(16)

                            Label {
                                Layout.preferredWidth: veRoot.veLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("比特率控制")
                            }

                            AppComboBox {
                                id: veMainRateCtlCombo
                                objectName: "veMainRateCtlCombo"

                                Layout.preferredWidth: veRoot.veFieldWidth
                                Layout.preferredHeight: root.ctrlH
                                model: ["VBR", "CBR", "CBVR"]
                            }

                            AppComboBox {
                                id: veSubRateCtlCombo
                                objectName: "veSubRateCtlCombo"

                                Layout.preferredWidth: veRoot.veFieldWidth
                                Layout.preferredHeight: root.ctrlH
                                model: ["VBR", "CBR", "CBVR"]
                            }

                        }

                        // 帧间隔（I 帧间隔）
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(16)

                            Label {
                                Layout.preferredWidth: veRoot.veLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("帧间隔") + "(s 1-200)"
                            }

                            AppTextField {
                                id: veMainGopInput
                                objectName: "veMainGopInput"

                                Layout.preferredWidth: veRoot.veFieldWidth
                                Layout.preferredHeight: root.ctrlH
                                text: "50"
                                // 失去焦点时校验：超出 1~200 区间则强制改为边界值
                                onEditingFinished: {
                                    var v = parseInt(text);
                                    if (isNaN(v))
                                        v = 1;

                                    if (v < 1)
                                        v = 1;
                                    else if (v > 200)
                                        v = 200;
                                    text = v.toString();
                                }
                            }

                            AppTextField {
                                id: veSubGopInput
                                objectName: "veSubGopInput"

                                Layout.preferredWidth: veRoot.veFieldWidth
                                Layout.preferredHeight: root.ctrlH
                                text: "50"
                                // 失去焦点时校验：超出 1~200 区间则强制改为边界值
                                onEditingFinished: {
                                    var v = parseInt(text);
                                    if (isNaN(v))
                                        v = 1;

                                    if (v < 1)
                                        v = 1;
                                    else if (v > 200)
                                        v = 200;
                                    text = v.toString();
                                }
                            }

                        }

                        // 比特率
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(16)

                            Label {
                                Layout.preferredWidth: veRoot.veLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("比特率") + "(kbps 500-8000)"
                            }

                            AppTextField {
                                id: veMainBitrateInput
                                objectName: "veMainBitrateInput"

                                Layout.preferredWidth: veRoot.veFieldWidth
                                Layout.preferredHeight: root.ctrlH
                                text: "500"
                                // 失去焦点时校验：超出 500~8000 区间则强制改为边界值
                                onEditingFinished: {
                                    var v = parseInt(text);
                                    if (isNaN(v))
                                        v = 500;

                                    if (v < 500)
                                        v = 500;
                                    else if (v > 8000)
                                        v = 8000;
                                    text = v.toString();
                                }
                            }

                            AppTextField {
                                id: veSubBitrateInput
                                objectName: "veSubBitrateInput"

                                Layout.preferredWidth: veRoot.veFieldWidth
                                Layout.preferredHeight: root.ctrlH
                                text: "500"
                                // 失去焦点时校验：超出 500~8000 区间则强制改为边界值
                                onEditingFinished: {
                                    var v = parseInt(text);
                                    if (isNaN(v))
                                        v = 500;

                                    if (v < 500)
                                        v = 500;
                                    else if (v > 8000)
                                        v = 8000;
                                    text = v.toString();
                                }
                            }

                        }

                        // 帧率
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(16)

                            Label {
                                Layout.preferredWidth: veRoot.veLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("帧率")
                            }

                            AppComboBox {
                                id: veMainFpsCombo
                                objectName: "veMainFpsCombo"

                                Layout.preferredWidth: veRoot.veFieldWidth
                                Layout.preferredHeight: root.ctrlH
                                model: {
                                    var arr = [];
                                    for (var i = 1; i <= 30; i++) arr.push(i)
                                    return arr;
                                }
                                currentIndex: 14
                            }

                            AppComboBox {
                                id: veSubFpsCombo
                                objectName: "veSubFpsCombo"

                                Layout.preferredWidth: veRoot.veFieldWidth
                                Layout.preferredHeight: root.ctrlH
                                model: {
                                    var arr = [];
                                    for (var i = 1; i <= 30; i++) arr.push(i)
                                    return arr;
                                }
                                currentIndex: 14
                            }

                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: ScreenTools.scaleNum(2)
                        }

                        // ===== 高级编码参数分组框（标题压在边框上） =====
                        Rectangle {
                            // 在表单列中水平居中显示
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: veLabelWidth + veFieldWidth + ScreenTools.scaleNum(48)
                            Layout.preferredHeight: veAdvancedCol.implicitHeight + ScreenTools.scaleNum(36)
                            color: "transparent"
                            border.width: 1
                            border.color: "#DCDCDC"
                            radius: ScreenTools.scaleNum(4)

                            Label {
                                text: qsTr("高级编码参数")
                                anchors.left: parent.left
                                anchors.leftMargin: ScreenTools.scaleNum(10)
                                anchors.top: parent.top
                                anchors.topMargin: -ScreenTools.scaleNum(8)

                                background: Rectangle {
                                    color: "#FFFFFF"
                                }

                            }

                            ColumnLayout {
                                id: veAdvancedCol

                                anchors.fill: parent
                                anchors.margins: ScreenTools.scaleNum(16)
                                anchors.topMargin: ScreenTools.scaleNum(18)
                                spacing: ScreenTools.scaleNum(10)

                                // BaseProfile
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: ScreenTools.scaleNum(8)

                                    Label {
                                        Layout.preferredWidth: veLabelWidth / 2
                                        Layout.preferredHeight: root.ctrlH
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: Text.AlignRight
                                        text: "BaseProfile"
                                    }

                                    AppComboBox {
                                        id: veBaseProfileCombo
                                        objectName: "veBaseProfileCombo"

                                        Layout.preferredWidth: veFieldWidth
                                        Layout.preferredHeight: root.ctrlH
                                        model: [qsTr("禁用"), qsTr("启用")]
                                    }

                                }

                                // WDR 模式
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: ScreenTools.scaleNum(8)

                                    Label {
                                        Layout.preferredWidth: veLabelWidth / 2
                                        Layout.preferredHeight: root.ctrlH
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: Text.AlignRight
                                        text: qsTr("WDR模式")
                                    }

                                    AppComboBox {
                                        id: veWdrModeCombo
                                        objectName: "veWdrModeCombo"

                                        Layout.preferredWidth: veFieldWidth
                                        Layout.preferredHeight: root.ctrlH
                                        model: [qsTr("禁用"), qsTr("启用")]
                                    }

                                }

                                // 私有数据
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: ScreenTools.scaleNum(8)

                                    Label {
                                        Layout.preferredWidth: veLabelWidth / 2
                                        Layout.preferredHeight: root.ctrlH
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: Text.AlignRight
                                        text: qsTr("私有数据")
                                    }

                                    AppComboBox {
                                        id: vePrivateDataCombo
                                        objectName: "vePrivateDataCombo"

                                        Layout.preferredWidth: veFieldWidth
                                        Layout.preferredHeight: root.ctrlH
                                        model: [qsTr("禁用"), qsTr("启用")]
                                    }

                                }

                            }

                        }

                    }

                }

            }

            // ===== 底部：保存按钮 =====
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: ScreenTools.scaleNum(14)
                spacing: ScreenTools.scaleNum(8)

                Item {
                    Layout.fillWidth: true
                }

                AppButton {
                    Layout.preferredHeight: root.ctrlH
                    highlighted: true
                    text: qsTr("保存")
                    onClicked: {
                        root.saveCurrentPanel();
                    }
                }

            }

        }

    }

    // ===== 音频编码设置面板 =====
    Component {
        id: audioEncodePanel

        ColumnLayout {
            id: aeRoot

            // “启用编码”为“禁用”时，除该开关所在行外，其余项全部不可编辑
            function applyEnableState() {
                root.setRowsEnabled(aeFormCol, aeEnableRow, aeEnableCombo.currentIndex === 0);
            }

            anchors.fill: parent
            spacing: ScreenTools.scaleNum(10)
            Component.onCompleted: applyEnableState()

            AppCheckBox {
                id: aeSetCheck
                objectName: "aeSetCheck"

                text: qsTr("设置音频编码")
                checked: false
                // 与左侧树“音频编码”前的复选框强绑定（双向同步）
                onCheckedChanged: root.setChecked("audioEncode", checked)

                Binding {
                    target: aeSetCheck
                    property: "checked"
                    value: root.isChecked("audioEncode")
                }

            }

            // ===== 中间：可设置项区域（浅色边框框起来） =====
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent"
                border.width: 1
                border.color: "#DCDCDC"
                radius: ScreenTools.scaleNum(4)
                clip: true

                ScrollView {
                    id: aeFieldScroll

                    anchors.fill: parent
                    anchors.margins: ScreenTools.scaleNum(10)
                    clip: true
                    background: null

                    ColumnLayout {
                        id: aeFormCol

                        width: aeFieldScroll.availableWidth
                        spacing: ScreenTools.scaleNum(10)

                        // 启用编码
                        RowLayout {
                            id: aeEnableRow

                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("启用编码")
                            }

                            AppComboBox {
                                id: aeEnableCombo
                                objectName: "aeEnableCombo"

                                Layout.preferredWidth: ScreenTools.scaleNum(180)
                                Layout.preferredHeight: root.ctrlH
                                model: [qsTr("启用"), qsTr("禁用")]
                                onCurrentIndexChanged: aeRoot.applyEnableState()
                            }

                        }

                        // 编码方式
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("编码方式")
                            }

                            AppComboBox {
                                id: aeTypeCombo
                                objectName: "aeTypeCombo"

                                Layout.preferredWidth: ScreenTools.scaleNum(180)
                                Layout.preferredHeight: root.ctrlH
                                model: ["G711", "AAC"]
                                onActivated: aeSampleCombo.currentIndex = 0
                            }

                        }

                        // 采样率：G711 可选 8000/16000；AAC 固定 16000
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("采样率")
                            }

                            AppComboBox {
                                id: aeSampleCombo
                                objectName: "aeSampleCombo"

                                Layout.preferredWidth: ScreenTools.scaleNum(180)
                                Layout.preferredHeight: root.ctrlH
                                model: aeTypeCombo.currentIndex === 0 ? ["8000", "16000"] : ["16000"]
                            }

                        }

                        // 码率：随编码方式/采样率联动，不可手动更改
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("码率")
                            }

                            AppTextField {
                                id: aeBitrateInput
                                objectName: "aeBitrateInput"

                                Layout.preferredWidth: ScreenTools.scaleNum(180)
                                Layout.preferredHeight: root.ctrlH
                                readOnly: true
                                // G711@8kHz→64000；G711@16kHz→128000；AAC→16000
                                text: aeTypeCombo.currentIndex === 0 ? (aeSampleCombo.currentText === "16000" ? "128000" : "64000") : "16000"
                            }

                        }

                    }

                }

            }

            // ===== 底部：保存按钮 =====
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: ScreenTools.scaleNum(14)
                spacing: ScreenTools.scaleNum(8)

                Item {
                    Layout.fillWidth: true
                }

                AppButton {
                    Layout.preferredHeight: root.ctrlH
                    highlighted: true
                    text: qsTr("保存")
                    onClicked: {
                        root.saveCurrentPanel();
                    }
                }

            }

        }

    }

    // ===== 音量配置面板 =====
    Component {
        id: audioReconfigPanel

        ColumnLayout {
            anchors.fill: parent
            spacing: ScreenTools.scaleNum(10)

            AppCheckBox {
                id: arSetCheck
                objectName: "arSetCheck"

                text: qsTr("设置音量配置")
                checked: false
                // 与左侧树“音量配置”前的复选框强绑定（双向同步）
                onCheckedChanged: root.setChecked("audioReconfig", checked)

                Binding {
                    target: arSetCheck
                    property: "checked"
                    value: root.isChecked("audioReconfig")
                }

            }

            // ===== 中间：可设置项区域（浅色边框框起来） =====
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent"
                border.width: 1
                border.color: "#DCDCDC"
                radius: ScreenTools.scaleNum(4)
                clip: true

                ScrollView {
                    id: arFieldScroll

                    anchors.fill: parent
                    anchors.margins: ScreenTools.scaleNum(10)
                    clip: true
                    background: null

                    ColumnLayout {
                        width: arFieldScroll.availableWidth
                        spacing: ScreenTools.scaleNum(10)

                        // 采集音量（与其它页面一致，选项行统一缩进）
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: ScreenTools.scaleNum(10)
                            spacing: ScreenTools.scaleNum(8)

                            AppCheckBox {
                                id: arCaptureCheck
                                objectName: "arCaptureCheck"

                                text: qsTr("采集音量") + "(1-100)"
                            }

                            AppTextField {
                                id: arCaptureInput
                                objectName: "arCaptureInput"

                                Layout.preferredWidth: ScreenTools.scaleNum(250)
                                Layout.preferredHeight: root.ctrlH
                                text: "80"
                                // 失去焦点时校验：超出 1~100 区间则强制改为边界值
                                onEditingFinished: {
                                    var v = parseInt(text);
                                    if (isNaN(v))
                                        v = 1;

                                    if (v < 1)
                                        v = 1;
                                    else if (v > 100)
                                        v = 100;
                                    text = v.toString();
                                }
                            }

                        }

                        // 播放音量（与其它页面一致，选项行统一缩进）
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: ScreenTools.scaleNum(10)
                            spacing: ScreenTools.scaleNum(8)

                            AppCheckBox {
                                id: arPlayCheck
                                objectName: "arPlayCheck"

                                text: qsTr("播放音量") + "(1-100)"
                            }

                            AppTextField {
                                id: arPlayInput
                                objectName: "arPlayInput"

                                Layout.preferredWidth: ScreenTools.scaleNum(250)
                                Layout.preferredHeight: root.ctrlH
                                text: "80"
                                // 失去焦点时校验：超出 1~100 区间则强制改为边界值
                                onEditingFinished: {
                                    var v = parseInt(text);
                                    if (isNaN(v))
                                        v = 1;

                                    if (v < 1)
                                        v = 1;
                                    else if (v > 100)
                                        v = 100;
                                    text = v.toString();
                                }
                            }

                        }

                    }

                }

            }

            // ===== 底部：保存按钮 =====
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: ScreenTools.scaleNum(14)
                spacing: ScreenTools.scaleNum(8)

                Item {
                    Layout.fillWidth: true
                }

                AppButton {
                    Layout.preferredHeight: root.ctrlH
                    highlighted: true
                    text: qsTr("保存")
                    onClicked: {
                        root.saveCurrentPanel();
                    }
                }

            }

        }

    }

    // ===== 移动侦测面板（与声音侦测共用 AppPanel 骨架，仅文案 / key / 日志不同） =====
    Component {
        id: motionDetectPanel

        AppPanel {
            id: mdPanel

            switchText: qsTr("设置移动侦测告警")
            ctrlH: root.ctrlH
            onSwitchToggled: root.setChecked("motionDetect", checked)
            onSaveClicked: {
                root.saveCurrentPanel();
            }

            // 与左侧树“移动侦测”前的复选框强绑定（双向同步）
            Binding {
                target: mdPanel
                property: "switchChecked"
                value: root.isChecked("motionDetect")
            }

            // 移动侦测告警开关
            RowLayout {
                Layout.fillWidth: true
                spacing: ScreenTools.scaleNum(8)
                Layout.leftMargin: ScreenTools.scaleNum(16)

                Label {
                    Layout.minimumWidth: root.panelLabelWidth
                    Layout.preferredHeight: root.ctrlH
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignRight
                    text: qsTr("设置移动侦测告警")
                }

                AppComboBox {
                    id: mdEnableCombo
                    objectName: "mdEnableCombo"

                    Layout.preferredWidth: ScreenTools.scaleNum(250)
                    Layout.preferredHeight: root.ctrlH
                    model: [qsTr("启用"), qsTr("禁用")]
                }

            }

        }

    }

    // ===== 声音侦测面板（与移动侦测同构，仅文案 / key / 日志不同） =====
    Component {
        id: audioDetectPanel

        AppPanel {
            id: adPanel

            switchText: qsTr("设置声音侦测告警")
            ctrlH: root.ctrlH
            onSwitchToggled: root.setChecked("audioDetect", checked)
            onSaveClicked: {
                root.saveCurrentPanel();
            }

            // 与左侧树“声音侦测”前的复选框强绑定（双向同步）
            Binding {
                target: adPanel
                property: "switchChecked"
                value: root.isChecked("audioDetect")
            }

            // 声音侦测告警开关
            RowLayout {
                Layout.fillWidth: true
                spacing: ScreenTools.scaleNum(8)
                Layout.leftMargin: ScreenTools.scaleNum(16)

                Label {
                    Layout.minimumWidth: root.panelLabelWidth
                    Layout.preferredHeight: root.ctrlH
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignRight
                    text: qsTr("设置声音侦测告警")
                }

                AppComboBox {
                    id: adEnableCombo
                    objectName: "adEnableCombo"

                    Layout.preferredWidth: ScreenTools.scaleNum(250)
                    Layout.preferredHeight: root.ctrlH
                    model: [qsTr("启用"), qsTr("禁用")]
                }

            }

        }

    }

    // ===== 账户管理面板 =====
    Component {
        id: accountPanel

        ColumnLayout {
            anchors.fill: parent
            spacing: ScreenTools.scaleNum(10)

            AppCheckBox {
                id: accSetCheck
                objectName: "accSetCheck"

                text: qsTr("修改admin账号密码")
                checked: false
                // 与左侧树“账号管理”前的复选框强绑定（双向同步）
                onCheckedChanged: root.setChecked("account", checked)

                Binding {
                    target: accSetCheck
                    property: "checked"
                    value: root.isChecked("account")
                }

            }

            // ===== 中间：可设置项区域（浅色边框框起来） =====
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent"
                border.width: 1
                border.color: "#DCDCDC"
                radius: ScreenTools.scaleNum(4)
                clip: true

                ScrollView {
                    id: accFieldScroll

                    anchors.fill: parent
                    anchors.margins: ScreenTools.scaleNum(10)
                    clip: true
                    background: null

                    ColumnLayout {
                        width: accFieldScroll.availableWidth
                        spacing: ScreenTools.scaleNum(10)

                        // 新密码
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("新密码")
                            }

                            PwdInput {
                                id: accNewPwdInput
                                objectName: "accNewPwdInput"

                                Layout.preferredWidth: ScreenTools.scaleNum(330)
                                Layout.preferredHeight: root.ctrlH
                            }

                        }

                        // 新密码确认
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("新密码确认")
                            }

                            PwdInput {
                                id: accConfirmPwdInput
                                objectName: "accConfirmPwdInput"

                                Layout.preferredWidth: ScreenTools.scaleNum(330)
                                Layout.preferredHeight: root.ctrlH
                            }

                        }

                    }

                }

            }

            // ===== 底部：保存按钮 =====
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: ScreenTools.scaleNum(14)
                spacing: ScreenTools.scaleNum(8)

                Item {
                    Layout.fillWidth: true
                }

                AppButton {
                    Layout.preferredHeight: root.ctrlH
                    highlighted: true
                    text: qsTr("保存")
                    onClicked: {
                        if (accNewPwdInput.text !== accConfirmPwdInput.text) {
                            saveTipBox.show(qsTr("温馨提示"), qsTr("两次输入的密码不一致"));
                            return ;
                        }
                        root.saveCurrentPanel();
                    }
                }

            }

        }

    }

    // ===== 定期维护面板 =====
    Component {
        id: maintenancePanel

        ColumnLayout {
            id: mtRoot

            // “定时维护”开关为“禁用”时，除该开关所在行外，其余项全部不可编辑
            function applyEnableState() {
                root.setRowsEnabled(mtFormCol, mtEnableRow, mtEnableCombo.currentIndex === 0);
            }

            anchors.fill: parent
            spacing: ScreenTools.scaleNum(10)
            Component.onCompleted: applyEnableState()

            AppCheckBox {
                id: mtSetCheck
                objectName: "mtSetCheck"

                text: qsTr("定时维护")
                checked: false
                // 与左侧树“定期维护”前的复选框强绑定（双向同步）
                onCheckedChanged: root.setChecked("maintenance", checked)

                Binding {
                    target: mtSetCheck
                    property: "checked"
                    value: root.isChecked("maintenance")
                }

            }

            // ===== 中间：可设置项区域（浅色边框框起来） =====
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent"
                border.width: 1
                border.color: "#DCDCDC"
                radius: ScreenTools.scaleNum(4)
                clip: true

                ScrollView {
                    id: mtFieldScroll

                    anchors.fill: parent
                    anchors.margins: ScreenTools.scaleNum(10)
                    clip: true
                    background: null

                    ColumnLayout {
                        id: mtFormCol

                        width: mtFieldScroll.availableWidth
                        spacing: ScreenTools.scaleNum(10)

                        // 定时维护开关
                        RowLayout {
                            id: mtEnableRow

                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("定时维护")
                            }

                            AppComboBox {
                                id: mtEnableCombo
                                objectName: "mtEnableCombo"

                                Layout.preferredWidth: ScreenTools.scaleNum(250)
                                Layout.preferredHeight: root.ctrlH
                                model: [qsTr("启用"), qsTr("禁用")]
                                onCurrentIndexChanged: mtRoot.applyEnableState()
                            }

                        }

                        // 维护日期：每天 + 星期一至星期日（单选）
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("维护日期")
                            }

                            AppComboBox {
                                id: mtDayCombo
                                objectName: "mtDayCombo"

                                Layout.preferredWidth: ScreenTools.scaleNum(250)
                                Layout.preferredHeight: root.ctrlH
                                model: [qsTr("每天"), qsTr("星期一"), qsTr("星期二"), qsTr("星期三"), qsTr("星期四"), qsTr("星期五"), qsTr("星期六"), qsTr("星期日")]
                            }

                        }

                        // 维护时间：00:00:00~23:59:59
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("维护时间")
                            }

                            AppTimePicker {
                                id: mtTimeInput
                                objectName: "mtTimeInput"

                                Layout.preferredWidth: ScreenTools.scaleNum(150)
                                Layout.preferredHeight: root.ctrlH
                                fieldWidth: ScreenTools.scaleNum(150)
                                ctrlHeight: root.ctrlH
                                time: "00:00:00"
                            }

                        }

                    }

                }

            }

            // ===== 底部：保存按钮 =====
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: ScreenTools.scaleNum(14)
                spacing: ScreenTools.scaleNum(8)

                Item {
                    Layout.fillWidth: true
                }

                AppButton {
                    Layout.preferredHeight: root.ctrlH
                    highlighted: true
                    text: qsTr("保存")
                    onClicked: {
                        root.saveCurrentPanel();
                    }
                }

            }

        }

    }

    // ===== 设备语言面板 =====
    Component {
        id: languagePanel

        ColumnLayout {
            anchors.fill: parent
            spacing: ScreenTools.scaleNum(10)

            AppCheckBox {
                id: langSetCheck
                objectName: "langSetCheck"

                text: qsTr("设置设备语言")
                checked: false
                // 与左侧树“设备语言”前的复选框强绑定（双向同步）
                onCheckedChanged: root.setChecked("language", checked)

                Binding {
                    target: langSetCheck
                    property: "checked"
                    value: root.isChecked("language")
                }

            }

            // ===== 中间：可设置项区域（浅色边框框起来） =====
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent"
                border.width: 1
                border.color: "#DCDCDC"
                radius: ScreenTools.scaleNum(4)
                clip: true

                ScrollView {
                    id: langFieldScroll

                    anchors.fill: parent
                    anchors.margins: ScreenTools.scaleNum(10)
                    clip: true
                    background: null

                    ColumnLayout {
                        width: langFieldScroll.availableWidth
                        spacing: ScreenTools.scaleNum(10)

                        // 语言列表
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("语言列表")
                            }

                            AppComboBox {
                                id: langCombo
                                objectName: "langCombo"

                                Layout.preferredWidth: ScreenTools.scaleNum(250)
                                Layout.preferredHeight: root.ctrlH
                                model: ["简体中文", "繁体中文", "English"]
                            }

                        }

                    }

                }

            }

            // ===== 底部：保存按钮 =====
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: ScreenTools.scaleNum(14)
                spacing: ScreenTools.scaleNum(8)

                Item {
                    Layout.fillWidth: true
                }

                AppButton {
                    Layout.preferredHeight: root.ctrlH
                    highlighted: true
                    text: qsTr("保存")
                    onClicked: {
                        root.saveCurrentPanel();
                    }
                }

            }

        }

    }

    // ===== 时钟设置面板 =====
    Component {
        id: clockPanel

        ColumnLayout {
            // 可复用的 DST 配置行模型
            readonly property var ckMonthModel: [qsTr("一月份"), qsTr("二月份"), qsTr("三月份"), qsTr("四月份"), qsTr("五月份"), qsTr("六月份"), qsTr("七月份"), qsTr("八月份"), qsTr("九月份"), qsTr("十月份"), qsTr("十一月份"), qsTr("十二月份")]
            readonly property var ckWeekSeqModel: [qsTr("第一个"), qsTr("第二个"), qsTr("第三个"), qsTr("第四个"), qsTr("最后一个")]
            readonly property var ckWeekDayModel: [qsTr("星期一"), qsTr("星期二"), qsTr("星期三"), qsTr("星期四"), qsTr("星期五"), qsTr("星期六"), qsTr("星期日")]

            anchors.fill: parent
            spacing: ScreenTools.scaleNum(10)

            AppCheckBox {
                id: ckSetCheck
                objectName: "ckSetCheck"

                text: qsTr("时钟设置")
                checked: false
                // 与左侧树“时钟设置”前的复选框强绑定（双向同步）
                onCheckedChanged: root.setChecked("clock", checked)

                Binding {
                    target: ckSetCheck
                    property: "checked"
                    value: root.isChecked("clock")
                }

            }

            // ===== 中间：可设置项区域（浅色边框框起来） =====
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent"
                border.width: 1
                border.color: "#DCDCDC"
                radius: ScreenTools.scaleNum(4)
                clip: true

                ScrollView {
                    id: ckFieldScroll

                    anchors.fill: parent
                    anchors.margins: ScreenTools.scaleNum(10)
                    clip: true
                    background: null

                    ColumnLayout {
                        width: ckFieldScroll.availableWidth
                        spacing: ScreenTools.scaleNum(10)

                        // 更新方式：云服务 / NTP / 手动
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth + ScreenTools.scaleNum(60)
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("更新方式")
                            }

                            AppComboBox {
                                id: ckModeCombo
                                objectName: "ckModeCombo"

                                Layout.preferredWidth: ScreenTools.scaleNum(360)
                                Layout.preferredHeight: root.ctrlH
                                model: [qsTr("使用云服务"), qsTr("使用NTP服务"), qsTr("手动设置")]
                            }

                        }

                        // 时区（三种方式均显示）
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth + ScreenTools.scaleNum(60)
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("时区")
                            }

                            AppComboBox {
                                id: ckZoneCombo
                                objectName: "ckZoneCombo"

                                Layout.preferredWidth: ScreenTools.scaleNum(360)
                                Layout.preferredHeight: root.ctrlH
                                model: [qsTr("(GMT-12:00)国际日期变更线西"), qsTr("(GMT-11:00)中途岛，萨摩亚"), qsTr("(GMT-10:00)夏威夷"), qsTr("(GMT-09:00)阿拉斯加"), qsTr("(GMT-08:00)太平洋时间（美国和加拿大）"), qsTr("(GMT-07:00)山地时间（美国和加拿大）"), qsTr("(GMT-06:00)中部时间（美国和加拿大），墨西哥城"), qsTr("(GMT-05:00)东部时间（美国和加拿大），波哥大"), qsTr("(GMT-04:00)大西洋时间（加拿大），加拉加斯"), qsTr("(GMT-03:00)巴西利亚，乔治敦"), qsTr("(GMT-02:00)中大西洋"), qsTr("(GMT-01:00)亚速尔群岛，佛得角群岛"), qsTr("(GMT+00:00)都柏林，伦敦，里斯本"), qsTr("(GMT+01:00)巴黎，柏林，罗马，马德里"), qsTr("(GMT+02:00)雅典，开罗，赫尔辛基"), qsTr("(GMT+03:00)莫斯科，圣彼得堡，内罗毕"), qsTr("(GMT+04:00)巴库，第比利斯，叶里温"), qsTr("(GMT+05:00)伊斯兰堡，卡拉奇，塔什干"), qsTr("(GMT+06:00)达卡，阿拉木图"), qsTr("(GMT+07:00)曼谷，河内，雅加达"), qsTr("(GMT+08:00)北京，重庆，乌鲁木齐，香港特别行政区"), qsTr("(GMT+09:00)东京，大阪，首尔"), qsTr("(GMT+10:00)悉尼，墨尔本，关岛"), qsTr("(GMT+11:00)所罗门群岛，新喀里多尼亚"), qsTr("(GMT+12:00)奥克兰，惠灵顿，斐济")]
                                currentIndex: 20
                            }

                        }

                        // ===== 仅 NTP 模式显示 =====
                        RowLayout {
                            visible: ckModeCombo.currentIndex === 1
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth + ScreenTools.scaleNum(60)
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("NTP服务器IP")
                            }

                            AppTextField {
                                id: ckNtpIpInput
                                objectName: "ckNtpIpInput"

                                Layout.preferredWidth: ScreenTools.scaleNum(360)
                                Layout.preferredHeight: root.ctrlH
                                text: ""
                            }

                        }

                        RowLayout {
                            visible: ckModeCombo.currentIndex === 1
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth + ScreenTools.scaleNum(60)
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("NTP端口") + "(1-65535)"
                            }

                            AppTextField {
                                id: ckNtpPortInput
                                objectName: "ckNtpPortInput"

                                Layout.preferredWidth: ScreenTools.scaleNum(360)
                                Layout.preferredHeight: root.ctrlH
                                text: "0"
                                // 失去焦点时校验：超出 1~65535 区间则强制改为边界值
                                onEditingFinished: {
                                    var v = parseInt(text);
                                    if (isNaN(v))
                                        v = 1;

                                    if (v < 1)
                                        v = 1;
                                    else if (v > 65535)
                                        v = 65535;
                                    text = v.toString();
                                }
                            }

                        }

                        RowLayout {
                            visible: ckModeCombo.currentIndex === 1
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth + ScreenTools.scaleNum(60)
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("刷新间隔") + "(60-999999)"
                            }

                            AppTextField {
                                id: ckRefreshInput
                                objectName: "ckRefreshInput"

                                Layout.preferredWidth: ScreenTools.scaleNum(360)
                                Layout.preferredHeight: root.ctrlH
                                text: "0"
                                // 失去焦点时校验：超出 60~999999 区间则强制改为边界值
                                onEditingFinished: {
                                    var v = parseInt(text);
                                    if (isNaN(v))
                                        v = 60;

                                    if (v < 60)
                                        v = 60;
                                    else if (v > 999999)
                                        v = 999999;
                                    text = v.toString();
                                }
                            }

                        }

                        // ===== 仅手动设置模式显示 =====
                        RowLayout {
                            visible: ckModeCombo.currentIndex === 2
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth + ScreenTools.scaleNum(60)
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("时间")
                            }

                            AppTextField {
                                id: ckTimeInput
                                objectName: "ckTimeInput"

                                Layout.preferredWidth: ScreenTools.scaleNum(200)
                                Layout.preferredHeight: root.ctrlH
                                // 默认填充当前电脑本地时间
                                text: Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm:ss")
                            }

                            AppCheckBox {
                                id: ckSetTimeCheck
                                objectName: "ckSetTimeCheck"

                                text: qsTr("设置时间")
                                checked: false
                            }

                        }

                        // 启用夏令时
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth + ScreenTools.scaleNum(60)
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("启用夏令时")
                            }

                            AppComboBox {
                                id: ckDstEnableCombo
                                objectName: "ckDstEnableCombo"

                                Layout.preferredWidth: ScreenTools.scaleNum(360)
                                Layout.preferredHeight: root.ctrlH
                                model: [qsTr("启用"), qsTr("禁用")]
                            }

                            Label {
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                text: qsTr("秒(s)")
                            }

                        }

                        // ===== 夏令时配置（启用时才显示） =====
                        // 夏令时开始时间：月份 / 周序 / 星期 / 时刻
                        RowLayout {
                            // 夏令时开关为“禁用”时，夏令时的配置项保留显示但不可编辑
                            enabled: ckDstEnableCombo.currentIndex === 0
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth + ScreenTools.scaleNum(60)
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("夏令时开始时间")
                            }

                            AppComboBox {
                                id: ckDstStartMonthCombo
                                objectName: "ckDstStartMonthCombo"

                                Layout.preferredWidth: ScreenTools.scaleNum(100)
                                Layout.preferredHeight: root.ctrlH
                                model: ckMonthModel
                            }

                            AppComboBox {
                                id: ckDstStartWeekSeqCombo
                                objectName: "ckDstStartWeekSeqCombo"

                                Layout.preferredWidth: ScreenTools.scaleNum(130)
                                Layout.preferredHeight: root.ctrlH
                                model: ckWeekSeqModel
                                currentIndex: 4
                            }

                            AppComboBox {
                                id: ckDstStartWeekDayCombo
                                objectName: "ckDstStartWeekDayCombo"

                                Layout.preferredWidth: ScreenTools.scaleNum(130)
                                Layout.preferredHeight: root.ctrlH
                                model: ckWeekDayModel
                                currentIndex: 6
                            }

                            AppTimePicker {
                                id: ckDstStartTimePicker
                                objectName: "ckDstStartTimePicker"

                                Layout.preferredHeight: root.ctrlH
                                fieldWidth: ScreenTools.scaleNum(110)
                                ctrlHeight: root.ctrlH
                                time: "23:59:59"
                            }

                        }

                        // 夏令时结束时间
                        RowLayout {
                            // 夏令时开关为“禁用”时，夏令时的配置项保留显示但不可编辑
                            enabled: ckDstEnableCombo.currentIndex === 0
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth + ScreenTools.scaleNum(60)
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("夏令时结束时间")
                            }

                            AppComboBox {
                                id: ckDstEndMonthCombo
                                objectName: "ckDstEndMonthCombo"

                                Layout.preferredWidth: ScreenTools.scaleNum(100)
                                Layout.preferredHeight: root.ctrlH
                                model: ckMonthModel
                            }

                            AppComboBox {
                                id: ckDstEndWeekSeqCombo
                                objectName: "ckDstEndWeekSeqCombo"

                                Layout.preferredWidth: ScreenTools.scaleNum(130)
                                Layout.preferredHeight: root.ctrlH
                                model: ckWeekSeqModel
                            }

                            AppComboBox {
                                id: ckDstEndWeekDayCombo
                                objectName: "ckDstEndWeekDayCombo"

                                Layout.preferredWidth: ScreenTools.scaleNum(130)
                                Layout.preferredHeight: root.ctrlH
                                model: ckWeekDayModel
                                currentIndex: 6
                            }

                            AppTimePicker {
                                id: ckDstEndTimePicker
                                objectName: "ckDstEndTimePicker"

                                Layout.preferredHeight: root.ctrlH
                                fieldWidth: ScreenTools.scaleNum(110)
                                ctrlHeight: root.ctrlH
                                time: "00:00:00"
                            }

                        }

                        // 夏令时偏移时间
                        RowLayout {
                            // 夏令时开关为“禁用”时，夏令时的配置项保留显示但不可编辑
                            enabled: ckDstEnableCombo.currentIndex === 0
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth + ScreenTools.scaleNum(60)
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("夏令时偏移时间")
                            }

                            AppComboBox {
                                id: ckDstOffsetCombo
                                objectName: "ckDstOffsetCombo"

                                Layout.preferredWidth: ScreenTools.scaleNum(150)
                                Layout.preferredHeight: root.ctrlH
                                model: [30 + qsTr("分钟"), 60 + qsTr("分钟"), 90 + qsTr("分钟"), 120 + qsTr("分钟")]
                            }

                        }

                    }

                }

            }

            // ===== 底部：保存按钮 =====
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: ScreenTools.scaleNum(14)
                spacing: ScreenTools.scaleNum(8)

                Item {
                    Layout.fillWidth: true
                }

                AppButton {
                    Layout.preferredHeight: root.ctrlH
                    highlighted: true
                    text: qsTr("保存")
                    onClicked: {
                        root.saveCurrentPanel();
                    }
                }

            }

        }

    }

    // ===== 28181接入2设置（草稿，尚未挂到左侧分类树） =====
    // 注意：QML 文件只能有一个根对象，新增面板必须写成 Component 放在 Dialog 内部；
    // 以后要启用：在上方 groups 里加一项 key，并在 Loader 的 sourceComponent 路由里指向它
    Component {
        id: gb28181Access2Panel

        Item {
            id: gb28181Access2

            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: false

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: ScreenTools.scaleNum(8)

                // ===== 顶部：标题 =====
                RowLayout {
                    Layout.fillWidth: true
                    spacing: ScreenTools.scaleNum(8)

                    Item {
                    }

                }

            }

        }

    }

    background: Rectangle {
        radius: ScreenTools.scaleNum(4)
        color: "#FFFFFF"
        border.width: 1
        border.color: "#DCDCDC"
    }

    // 4 段式 IP 输入框（IP地址/子网掩码/网关/DNS1/DNS2 共用）
    component IpInput: AppIpInput {
        ctrlHeight: root.ctrlH
    }

    // 密码输入框：复用统一封装的 AppPasswordField
    component PwdInput: AppPasswordField {
        Layout.minimumHeight: root.ctrlH
        Layout.preferredHeight: root.ctrlH
    }

    header: AppDialogHeader {
        title: root.title
        onClosed: root.reject()

        // 保存成功提示弹窗
        AppMessageBox {
            id: saveTipBox
        }

    }

    footer: Item {
        height: 0
    }
    // 四周外边距统一 16

    contentItem: RowLayout {
        width: root.availableWidth
        height: root.availableHeight
        spacing: ScreenTools.scaleNum(12)

        // ===== 左侧分类树 =====
        Rectangle {
            Layout.preferredWidth: root.treeWidth
            Layout.fillHeight: true
            color: "#FFFFFF"
            border.width: 1
            border.color: "#DCDCDC"

            Flickable {
                anchors.fill: parent
                anchors.margins: ScreenTools.scaleNum(4)
                contentWidth: width
                contentHeight: treeColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: treeColumn

                    width: parent.width
                    spacing: ScreenTools.scaleNum(2)

                    Repeater {
                        model: root.groups

                        delegate: Column {
                            id: groupCol

                            // 本分组在 root.groups 中的序号（显式保存，避免深层子项解析 index 出错）
                            readonly property int groupIndex: index
                            // 父节点展开状态（默认全部展开）
                            property bool expanded: true

                            width: treeColumn.width
                            spacing: ScreenTools.scaleNum(2)

                            // 父节点：展开/收起按钮 + 分类名
                            RowLayout {
                                width: parent.width
                                spacing: ScreenTools.scaleNum(4)

                                // 带边框的折叠按钮，鼠标悬停时高亮，便于识别为可点击控件
                                Rectangle {
                                    Layout.preferredWidth: ScreenTools.scaleNum(18)
                                    Layout.preferredHeight: ScreenTools.scaleNum(18)
                                    radius: ScreenTools.scaleNum(2)
                                    color: toggleArea.containsMouse ? "#DCE7FB" : "#FFFFFF"
                                    border.width: 1
                                    border.color: toggleArea.containsMouse ? "#004EEB" : "#DCDCDC"

                                    Label {
                                        anchors.centerIn: parent
                                        // 展开时向下箭头，收起时向右箭头
                                        text: groupCol.expanded ? "-" : "+"
                                        font.pointSize: ScreenTools.scaleNum(12, true)
                                        color: toggleArea.containsMouse ? "#004EEB" : "#333333"
                                    }

                                    MouseArea {
                                        id: toggleArea

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: groupCol.expanded = !groupCol.expanded
                                    }

                                }

                                // 只有勾选框控制整组勾选；点击分类名不会勾选
                                AppCheckBox {
                                    id: groupChk
                                    objectName: "groupChk"

                                    Layout.preferredWidth: ScreenTools.scaleNum(26)
                                    Layout.preferredHeight: ScreenTools.scaleNum(28)
                                    tristate: true
                                    text: ""
                                    // 子节点全部勾选才打勾；有任一未勾选则不是勾选态
                                    checkState: {
                                        var items = modelData.items;
                                        var count = 0;
                                        for (var i = 0; i < items.length; i++) {
                                            if (root.checkedMap[items[i].key] === true)
                                                count++;

                                        }
                                        if (count === 0)
                                            return Qt.Unchecked;

                                        return count === items.length ? Qt.Checked : Qt.PartiallyChecked;
                                    }

                                    // 接管点击：勾选/取消勾选整组，避免内部切换破坏上面的绑定
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.setGroupChecked(groupCol.groupIndex, groupChk.checkState !== Qt.Checked)
                                    }

                                }

                                Label {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: ScreenTools.scaleNum(28)
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignLeft
                                    elide: Text.ElideRight
                                    font.family: "Microsoft YaHei"
                                    font.bold: true
                                    font.pointSize: ScreenTools.scaleNum(10, true)
                                    text: modelData.name

                                    // 双击分类名展开/收起本分组
                                    TapHandler {
                                        onDoubleTapped: groupCol.expanded = !groupCol.expanded
                                    }

                                }

                            }

                            // 子节点列表
                            Column {
                                width: parent.width
                                visible: groupCol.expanded
                                spacing: ScreenTools.scaleNum(2)

                                Repeater {
                                    model: modelData.items

                                    delegate: Rectangle {
                                        readonly property string itemKey: modelData.key
                                        readonly property string itemTitle: modelData.name

                                        width: parent.width
                                        height: ScreenTools.scaleNum(28)
                                        color: root.selectedKey === itemKey ? "#E8E8E8" : "transparent"

                                        RowLayout {
                                            anchors.fill: parent
                                            // 子节点缩进：折叠按钮 + 一个勾选框的宽度，不与父节点顶格对齐
                                            anchors.leftMargin: ScreenTools.scaleNum(40)
                                            spacing: ScreenTools.scaleNum(4)

                                            // 勾选框与节点名分离：点框只勾选，点名字只切换参数页
                                            AppCheckBox {
                                                id: subChk
                                                objectName: "subChk"

                                                Layout.preferredWidth: ScreenTools.scaleNum(26)
                                                Layout.preferredHeight: ScreenTools.scaleNum(28)
                                                text: ""
                                                checked: root.checkedMap[itemKey] === true

                                                // 接管点击：只改自己的勾选状态，避免内部切换破坏上面的绑定
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setChecked(itemKey, !subChk.checked)
                                                }

                                            }

                                            Label {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: ScreenTools.scaleNum(28)
                                                verticalAlignment: Text.AlignVCenter
                                                horizontalAlignment: Text.AlignLeft
                                                elide: Text.ElideRight
                                                font.family: "Microsoft YaHei"
                                                font.pointSize: ScreenTools.scaleNum(10, true)
                                                color: root.selectedKey === itemKey ? "#2f6fed" : "#1A1A1A"
                                                text: itemTitle

                                                TapHandler {
                                                    onTapped: root.selectedKey = itemKey
                                                }

                                            }

                                        }

                                    }

                                }

                            }

                        }

                    }

                }

                ScrollBar.vertical: ScrollBar {
                }

            }

        }

        // ===== 右侧参数面板 =====
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#FFFFFF"
            border.width: 1
            border.color: "#DCDCDC"

            Loader {
                id: panelLoader

                // 面板加载完成后回填已保存的参数（没保存过则用默认值）
                onLoaded: root.restorePanel(item)
                anchors.fill: parent
                anchors.margins: ScreenTools.scaleNum(16)
                active: root.selectedKey !== "" && !root.panelSuspended
                sourceComponent: root.selectedKey === "network" ? networkPanel : root.selectedKey === "gb28181" ? gb28181Panel : root.selectedKey === "videoCapture" ? videoCapturePanel : root.selectedKey === "videoEncode" ? videoEncodePanel : root.selectedKey === "audioEncode" ? audioEncodePanel : root.selectedKey === "audioReconfig" ? audioReconfigPanel : root.selectedKey === "motionDetect" ? motionDetectPanel : root.selectedKey === "audioDetect" ? audioDetectPanel : root.selectedKey === "account" ? accountPanel : root.selectedKey === "maintenance" ? maintenancePanel : root.selectedKey === "language" ? languagePanel : root.selectedKey === "clock" ? clockPanel : root.selectedKey === "timeTitle" ? osdPanel : placeholderPanel
            }

        }

    }

}
