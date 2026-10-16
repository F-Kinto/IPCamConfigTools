import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import IPCam.Public 1.0
// 项目内封装的通用控件目录（AppButton / AppCheckBox 等）
import "Controls"

// 操作指令面板：设备列表页右侧 1/4 的批量操作指令集合。
ColumnLayout {
    id: panel

    // ===== 宿主注入的共享资源（QML id 不跨文件，实例化时传对象进来）=====
    // 主窗口：logAction 等宿主函数
    property var host
    // 全工程唯一确认/提示框（AppMessageBox 实例）
    property var confirmBox
    // 三个指令弹窗实例（由 main.qml 声明并注入）
    property var setIpDialog
    property var osdDialog
    property var otherSettingsDialog
    // 设备列表状态：搜索中 / 已勾选数 / 表格设备总数
    property bool searching: false
    property int selectedCount: 0
    property int deviceCount: 0
    // 统一控件高度（与 main.qml 的 controlHeight 同源）
    property int controlHeight: 30

    // ===== 上抛信号（面板入口，main.qml 连接实现）=====
    // “设备搜索”：搜索会清空表格/勾选并读“系统配置-搜索时间”，留在 main.qml
    signal searchRequested()
    // “播放勾选设备”：直播预览切换页签并合并播放列表，留在 main.qml
    signal livePreviewRequested()
    // 全部设备全部设置项完成：上抛 main.qml 打开结果详情弹窗
    signal batchAllFinished()
    // 网络设置成功后设备已切到新 IP：上抛 main.qml 更新设备列表 IP 栏并同步勾选数据
    signal deviceIpChanged(string deviceKey, string newIp)

    // ===== “执行修改（配置其他参数）”：批量下发勾选的设置项 =====
    // 执行中遮罩显隐（main.qml 全屏进度遮罩绑定）
    property bool batchRunning: false
    // 每设备一块：[{key, header, status, items: [{name, ok}]}]
    property var batchRows: []
    // 勾选了网络设置且多台设备：先异步凑等量空闲 IP 再下发
    property bool batchAllocating: false
    // 本次分配请求的起始 IP（网络面板已保存的 IP）
    property string batchAllocBaseIp: ""
    // 分配期间的暂存：凑齐空闲 IP 后按设备构造专属设置项再启动下发
    property var batchAllocDevs: []
    property var batchAllocItems: []
    // 设备 -> 本次设置的目标 IP（多台为分配的空闲 IP，单台为网络面板保存的 IP）；
    // 网络设置成功后据此上报 main.qml 更新设备列表
    property var batchNewIps: ({})

    // ===== “执行修改（设定IP）”：按勾选数量给勾选设备下发新 IP =====
    property bool ipAllocating: false
    // 本次分配请求的起始 IP：响应靠它匹配，防止过期响应串扰
    property string ipAllocatingBaseIp: ""

    // 设备操作前置校验：列表为空或没勾选任何设备时提示，返回 false 表示中断
    function ensureDeviceSelected() {
        if (panel.deviceCount === 0 || panel.selectedCount === 0) {
            confirmBox.showTip(qsTr("温馨提示"), qsTr("请先选择设备"));
            return false;
        }
        return true;
    }

    // 下发修改 IP 请求：勾选设备（uid 升序，与 ips 下标一一配对）
    function sendSetIpRequests(ips) {
        var devices = DeviceManager.checkedDevices();
        for (var i = 0; i < devices.length; i++) {
            var id = devices[i]["uid"] || devices[i]["mac"] || devices[i]["ip"] || "";
            host.logAction("发送修改IP请求: 设备ID=%1, 新IP=%2".arg(id).arg(ips[i]));
        }
    }

    // “执行修改”点击入口：没设IP先提示；没勾选时列表为空直接提示，
    // 有设备则弹“是|否”确认是否全选（是→全选并继续）；已勾选直接执行。
    // 1 台直接下发弹窗保存的 IP；多台从该 IP 起凑等量空闲 IP（末段叠加
    // 到 .254，不足再递减到 .1）后逐台下发
    function executeSetIp() {
        if (setIpDialog.savedParams === null) {
            confirmBox.showTip(qsTr("温馨提示"), qsTr("请先在[设定IP]中设定IP地址"));
            return ;
        }
        // 列表为空没有可全选的设备，维持单按钮提示
        if (panel.deviceCount === 0) {
            confirmBox.showTip(qsTr("温馨提示"), qsTr("请先选择设备"));
            return ;
        }
        // 没勾选任何设备：询问是否全选（是|否），点是走全选后继续
        if (panel.selectedCount === 0) {
            confirmBox.showConfirm("setIpSelectAll", qsTr("温馨提示"), qsTr("请先选择设备, 是否选择所有设备?"), qsTr("是"), qsTr("否"));
            return ;
        }
        panel.executeSetIpChecked();
    }

    // 修改IP执行主体：勾选与 IP 均已就绪，按台数分流。
    // 供本面板“执行修改”与 main.qml 的“是→全选”确认框共用
    function executeSetIpChecked() {
        var baseIp = setIpDialog.savedParams["ip"];
        if (panel.selectedCount === 1) {
            // 单台：直接发送该设备 id 与设定IP里的地址
            sendSetIpRequests([baseIp]);
            confirmBox.showTip(qsTr("温馨提示"), qsTr("修改IP地址请求已发送, 请等待设备响应"));
        } else {
            // 多台：先开遮罩再异步凑空闲 IP，结果在下方 Connections 处理
            panel.ipAllocatingBaseIp = baseIp;
            panel.ipAllocating = true;
            ScreenTools.findFreeIpsAsync(baseIp, panel.selectedCount);
        }
    }

    // ===== "执行修改（配置其他参数）"：批量下发 =====
    // 按其它设置弹窗勾选的子节点顺序，对每台勾选设备下发对应 HTTP 设置请求；
    // 设备间并行、设备内串行、失败 2 秒重试一次、两次失败跳过（调度在 BatchSettingsTask）
    function executeOtherSettings() {
        var items = otherSettingsDialog.buildBatchItems();
        if (items.length === 0) {
            confirmBox.showTip(qsTr("温馨提示"), qsTr("请先在[配置其他参数]中勾选要设置的项目"));
            return ;
        }

        var devices = DeviceManager.checkedDevices();
        var devs = [];
        var rows = [];
        for (var i = 0; i < devices.length; i++) {
            var uid = devices[i]["uid"] || devices[i]["mac"] || devices[i]["ip"] || "";
            var ip = devices[i]["ip"] || "";
            if (uid === "" || ip === "")
                continue;

            devs.push({
                "uid": uid,
                "ip": ip
            });
            rows.push({
                "key": uid,
                "header": "%1[%2]:".arg(uid).arg(ip),
                "status": "",
                "items": []
            });
        }
        if (devs.length === 0) {
            confirmBox.showTip(qsTr("温馨提示"), qsTr("请先选择设备"));
            return ;
        }

        // 网络设置/视频编码/音频编码需设备重启进程生效：整体排到最后发送, 其余项先发；调度器在这三项每项成功后等 25 秒再发下一项
        var restartKeys = ["network", "videoEncode", "audioEncode"];
        var normalItems = [];
        var restartItems = [];
        for (var g = 0; g < items.length; g++) {
            if (restartKeys.indexOf(items[g]["key"]) >= 0)
                restartItems.push(items[g]);
            else
                normalItems.push(items[g]);
        }
        items = normalItems.concat(restartItems);

        // 勾选了网络设置：记录各设备将设置的目标 IP（成功后据此更新设备列表）
        var hasNetwork = false;
        for (var j = 0; j < items.length; j++) {
            if (items[j]["key"] === "network") {
                hasNetwork = true;
                break;
            }
        }
        var networkIp = hasNetwork ? otherSettingsDialog.networkSavedIp() : "";
        panel.batchNewIps = ({});
        if (hasNetwork && networkIp !== "") {
            for (var k = 0; k < devs.length; k++)
                panel.batchNewIps[devs[k]["uid"]] = networkIp;
        }

        // 多台 + 网络设置：先凑等量空闲 IP（逻辑同“执行修改（设定IP）”多台分支），
        if (hasNetwork && devs.length > 1) {
            if (networkIp === "") {
                confirmBox.showTip(qsTr("温馨提示"), qsTr("请先在[配置其他参数-网络设置]中设置并保存IP地址"));
                return ;
            }
            for (var m = 0; m < rows.length; m++)
                rows[m].status = qsTr("正在设置...");
            panel.batchAllocDevs = devs;
            panel.batchAllocItems = items;
            panel.batchAllocBaseIp = networkIp;
            panel.batchAllocating = true;
            panel.batchRows = rows;
            panel.batchRunning = true;
            ScreenTools.findFreeIpsAsync(networkIp, devs.length);
            return ;
        }

        // 单台 + 网络设置：给 network 项补 newIp（面板保存的 IP）——该项成功后设备
        if (hasNetwork && networkIp !== "") {
            var withNewIp = [];
            for (var n = 0; n < items.length; n++) {
                var it = items[n];
                if (it["key"] === "network") {
                    it = {
                        "key": it["key"],
                        "name": it["name"],
                        "action": it["action"],
                        "url": it["url"],
                        "body": it["body"],
                        "newIp": networkIp
                    };
                }
                withNewIp.push(it);
            }
            items = withNewIp;
        }

        panel.batchRows = rows;
        panel.batchRunning = true;
        BatchSettingsTask.start(devs, items);
    }

    // 空闲 IP 凑齐后启动批量下发：每台设备配一个 IP，网络设置项的请求体按分配
    // 的 IP 定制（newIp 一并下发，调度器在该项成功后把该设备后续项 URL 切到新 IP）
    function startBatchWithFreeIps(freeIps) {
        var devs = [];
        for (var i = 0; i < panel.batchAllocDevs.length; i++) {
            var newIp = freeIps[i];
            panel.batchNewIps[panel.batchAllocDevs[i]["uid"]] = newIp;
            var devItems = [];
            for (var j = 0; j < panel.batchAllocItems.length; j++) {
                var it = panel.batchAllocItems[j];
                if (it["key"] === "network") {
                    it = {
                        "key": it["key"],
                        "name": it["name"],
                        "action": it["action"],
                        "url": it["url"],
                        "body": otherSettingsDialog.networkBodyWithIp(newIp),
                        "newIp": newIp
                    };
                }
                devItems.push(it);
            }
            devs.push({
                "uid": panel.batchAllocDevs[i]["uid"],
                "ip": panel.batchAllocDevs[i]["ip"],
                "items": devItems
            });
        }
        var items = panel.batchAllocItems;
        panel.batchAllocDevs = [];
        panel.batchAllocItems = [];
        BatchSettingsTask.start(devs, items);
    }

    // 更新某设备进度状态行文本
    function setRowStatus(deviceKey, text) {
        var rows = [];
        for (var i = 0; i < panel.batchRows.length; i++) {
            var row = panel.batchRows[i];
            rows.push(row.key === deviceKey ? {
                "key": row.key,
                "header": row.header,
                "status": text,
                "items": row.items
            } : row);
        }
        panel.batchRows = rows;
    }

    // 记录某设备某设置项终态结果（结果详情弹窗数据）
    function appendRowItem(deviceKey, itemName, ok) {
        var rows = [];
        for (var i = 0; i < panel.batchRows.length; i++) {
            var row = panel.batchRows[i];
            if (row.key === deviceKey) {
                var items = [];
                for (var j = 0; j < row.items.length; j++)
                    items.push(row.items[j]);
                items.push({
                    "name": itemName,
                    "ok": ok
                });
                rows.push({
                    "key": row.key,
                    "header": row.header,
                    "status": row.status,
                    "items": items
                });
            } else {
                rows.push(row);
            }
        }
        panel.batchRows = rows;
    }

    // 批量下发调度器的进度/结果回调（文本在此组装以保持 qsTr 翻译体系）：
    // state 0 正在设置 / 1 设置成功 / 2 失败重试中 / 3 失败已跳过 / 4 设备完成
    Connections {
        target: BatchSettingsTask

        function onDeviceProgress(deviceKey, itemAction, state) {
            var text = "";
            if (state === 0)
                text = qsTr("正在设置%1...").arg(itemAction);
            else if (state === 1)
                text = qsTr("%1设置成功").arg(itemAction);
            else if (state === 2)
                text = qsTr("%1设置失败, 正在重试...").arg(itemAction);
            else if (state === 3)
                text = qsTr("%1设置失败, 已跳过").arg(itemAction);
            else if (state === 4)
                text = qsTr("设置完成");
            else if (state === 5)
                text = qsTr("%1设置完成, 进程重启...").arg(itemAction);
            panel.setRowStatus(deviceKey, text);
        }

        function onItemResult(deviceKey, itemKey, itemName, success) {
            panel.appendRowItem(deviceKey, itemName, success);
            // 网络设置成功：设备已切到设置的 IP，上抛 main.qml 更新设备列表
            if (itemKey === "network" && success) {
                var newIp = panel.batchNewIps[deviceKey];
                if (newIp !== undefined && newIp !== "")
                    panel.deviceIpChanged(deviceKey, newIp);
            }
        }

        function onAllFinished() {
            panel.batchRunning = false;
            panel.batchAllFinished();
        }

    }

    // “执行修改（设定IP）”勾选多台时 findFreeIpsAsync 的结果：凑满等量空闲 IP 后逐台配对下发
    Connections {
        function onSignalFreeIpsFound(baseIp, wanted, freeIps) {
            // “执行修改（设定IP）”多台的分配结果：凑满等量空闲 IP 后逐台配对下发
            if (panel.ipAllocating && baseIp === panel.ipAllocatingBaseIp) {
                panel.ipAllocating = false;
                panel.ipAllocatingBaseIp = "";
                if (freeIps.length < wanted) {
                    // 网段内空闲 IP 不够：提示后中断，可换起始 IP 重试
                    confirmBox.showTip(qsTr("温馨提示"), qsTr("网段内空闲IP不足(需%1个, 只找到%2个), 请调整起始IP").arg(wanted).arg(freeIps.length));
                    return ;
                }
                panel.sendSetIpRequests(freeIps);
                confirmBox.showTip(qsTr("温馨提示"), qsTr("批量修改IP请求已发送, 请等待设备响应"));
                return ;
            }

            // “执行修改（配置其他参数）”含网络设置多台的分配结果：凑齐后下发
            if (!panel.batchAllocating || baseIp !== panel.batchAllocBaseIp)
                return ;

            panel.batchAllocating = false;
            panel.batchAllocBaseIp = "";
            if (freeIps.length < wanted) {
                // 空闲 IP 不够：关遮罩提示后中断，可调整网络面板 IP 重试
                panel.batchRunning = false;
                panel.batchNewIps = ({});
                confirmBox.showTip(qsTr("温馨提示"), qsTr("网段内空闲IP不足(需%1个, 只找到%2个), 请调整网络设置中的IP地址").arg(wanted).arg(freeIps.length));
                return ;
            }
            panel.startBatchWithFreeIps(freeIps);
        }

        target: ScreenTools
    }

    // ===== 面板 UI =====
    Label {
        Layout.preferredHeight: panel.controlHeight
        verticalAlignment: Text.AlignVCenter
        text: qsTr("操作指令")
    }

    AppButton {
        Layout.fillWidth: true
        text: panel.searching ? qsTr("搜索中...") : qsTr("设备搜索")
        enabled: !panel.searching
        onClicked: {
            host.logAction("我点击了%1按钮".arg("设备搜索"));
            panel.searchRequested();
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: ScreenTools.scaleNum(6)

        AppButton {
            Layout.fillWidth: true
            text: qsTr("设定IP")
            onClicked: {
                host.logAction("我点击了%1按钮".arg(text));
                setIpDialog.open();
            }
        }

        AppButton {
            Layout.fillWidth: true
            text: qsTr("执行修改")
            onClicked: {
                host.logAction("我点击了%1按钮（设定IP）".arg(text));
                panel.executeSetIp();
            }
        }

    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: ScreenTools.scaleNum(16)
    }

    AppButton {
        Layout.fillWidth: true
        text: qsTr("同步时间")
        onClicked: {
            host.logAction("我点击了%1按钮".arg(text));
            panel.ensureDeviceSelected();
        }
    }

    AppButton {
        Layout.fillWidth: true
        text: qsTr("重启设备")
        onClicked: {
            host.logAction("我点击了%1按钮".arg(text));
            if (!panel.ensureDeviceSelected())
                return ;
            confirmBox.showConfirm("reboot", qsTr("温馨提示"), qsTr("确定要重启已勾选的设备吗?"));
        }
    }

    AppButton {
        Layout.fillWidth: true
        text: qsTr("恢复出厂设置")
        onClicked: {
            host.logAction("我点击了%1按钮".arg(text));
            if (!panel.ensureDeviceSelected())
                return ;
            confirmBox.showConfirm("factoryReset", qsTr("温馨提示"), qsTr("恢复出厂设置后设备会重启且设备IP可能变更, 需要重新搜索设备, 确定要对已勾选的设备执行该操作吗?"));
        }
    }

    AppButton {
        Layout.fillWidth: true
        text: qsTr("播放勾选设备")
        onClicked: {
            host.logAction("我点击了%1按钮".arg(text));
            if (!panel.ensureDeviceSelected())
                return ;

            panel.livePreviewRequested();
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: ScreenTools.scaleNum(16)
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: ScreenTools.scaleNum(6)

        AppButton {
            Layout.fillWidth: true
            text: qsTr("设定OSD")
            onClicked: {
                host.logAction("我点击了%1按钮".arg(text));
                osdDialog.open();
            }
        }

        AppButton {
            Layout.fillWidth: true
            text: qsTr("执行修改")
            onClicked: {
                host.logAction("我点击了%1按钮（设定OSD）".arg(text));
                panel.ensureDeviceSelected();
            }
        }

    }

    AppCheckBox {
        Layout.preferredHeight: panel.controlHeight
        text: qsTr("锁定默认参数")
        onToggled: host.logAction("%1已%2".arg(text).arg(checked ? "勾选" : "取消勾选"))
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: ScreenTools.scaleNum(6)

        AppButton {
            Layout.fillWidth: true
            text: qsTr("配置其他参数")
            onClicked: {
                host.logAction("我点击了%1按钮".arg(text));
                otherSettingsDialog.open();
            }
        }

        AppButton {
            Layout.fillWidth: true
            text: qsTr("执行修改")
            onClicked: {
                host.logAction("我点击了%1按钮（配置其他参数）".arg(text));
                if (!panel.ensureDeviceSelected())
                    return ;

                panel.executeOtherSettings();
            }
        }

    }

    Item {
        Layout.fillHeight: true
        Layout.minimumHeight: 0
    }

}
