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
    // "设备搜索"：搜索会清空表格/勾选并读"系统配置-搜索时间"，留在 main.qml
    signal searchRequested()
    // "播放勾选设备"：直播预览切换页签并合并播放列表，留在 main.qml
    signal livePreviewRequested()
    // 全部设备全部设置项完成：上抛 main.qml 打开结果详情弹窗
    signal batchAllFinished()
    // 网络设置成功后设备已切到新 IP：上抛 main.qml 更新设备列表 IP 栏并同步勾选数据
    signal deviceIpChanged(string deviceKey, string newIp)

    // ===== "执行修改（配置其他参数）"：批量下发勾选的设置项 =====
    // 执行中遮罩显隐（main.qml 全屏进度遮罩绑定）
    property bool batchRunning: false
    // 每设备一块：[{key, header, status, items: [{name, ok}]}]
    property var batchRows: []
    // 设备 -> 本次设置的目标 IP（多台为分配的空闲 IP，单台为网络面板保存的 IP）；
    // 网络设置成功后据此上报 main.qml 更新设备列表
    property var batchNewIps: ({})

    // ===== "文件一键升级"：WiFi 设备固件升级 =====
    // 升级运行中（复用 batchRunning / batchRows 遮罩体系）
    property bool upgradeRunning: false

    // 启动固件升级：由 main.qml 的 startFileUpgrade() 调用
    function startUpgrade(filePath) {
        var devices = DeviceManager.checkedDevices();
        var devs = [];       // 需要升级的设备（传给 C++）
        var rows = [];       // 遮罩行数据
        var needUpgrade = 0; // 需要升级的设备数

        // 提取文件版本号
        var fileVer = DeviceUpgradeTask.extractFileVersion(filePath);

        for (var i = 0; i < devices.length; i++) {
            var uid = devices[i]["uid"] || devices[i]["mac"] || devices[i]["ip"] || "";
            var ip = devices[i]["ip"] || "";
            var mac = devices[i]["mac"] || "";
            var curVer = devices[i]["currentVersion"] || "";
            if (uid === "" || ip === "")
                continue;

            // 版本比较
            var cmp = DeviceUpgradeTask.compareVersions(fileVer, curVer);
            var statusText = "";
            var itemOk = true; // 结果详情弹窗里该项是否标记成功
            var itemMessage = ""; // 结果详情弹窗里该项的自定义提示（空=显示成功/失败）
            var skip = false;

            if (cmp < 0) {
                // 文件版本 < 当前版本 → 版本过低，红色
                statusText = "<font color=\"#E04040\">" + qsTr("当前选择版本过低!") + "</font>";
                itemOk = false;
                itemMessage = qsTr("当前选择版本过低!");
                skip = true;
            } else if (cmp === 0 && fileVer !== "" && curVer !== "") {
                // 版本相等 → 已是最新，蓝色
                statusText = "<font color=\"#2F80ED\">" + qsTr("当前已是最新版本!") + "</font>";
                itemOk = true;
                itemMessage = qsTr("当前已是最新版本!");
                skip = true;
            }

            var row = {
                "key": uid,
                "header": "%1[%2]:".arg(uid).arg(ip),
                "uid": uid,
                "ip": ip,
                "status": statusText,
                "items": skip ? [{"name": qsTr("固件升级"), "ok": itemOk, "message": itemMessage}] : []
            };
            rows.push(row);

            if (!skip) {
                devs.push({
                    "uid": uid,
                    "ip": ip,
                    "mac": mac,
                    "currentVersion": curVer
                });
                needUpgrade++;
            }
        }

        if (rows.length === 0) {
            confirmBox.showTip(qsTr("温馨提示"), qsTr("请先选择设备"));
            return false;
        }

        panel.batchRows = rows;

        if (needUpgrade === 0) {
            // 所有设备都不需要升级：显示遮罩片刻后弹出结果详情
            panel.batchRunning = true;
            panel.upgradeRunning = true;
            // 立即标记完成（延时让用户看到状态文本）
            upgradeCheckTimer.start();
            return true;
        }

        panel.batchRunning = true;
        panel.upgradeRunning = true;
        DeviceUpgradeTask.startUpgrade(filePath, devs);
        return true;
    }

    // 版本检查全跳过时：短暂显示遮罩后弹出结果详情
    Timer {
        id: upgradeCheckTimer
        interval: 1500
        onTriggered: {
            panel.batchRunning = false;
            panel.upgradeRunning = false;
            panel.batchAllFinished();
        }
    }

    // DeviceUpgradeTask 进度/结果回调
    // state: 0=eUploading, 1=eUpgraded, 2=eSuccess, 3=eFailed
    Connections {
        target: DeviceUpgradeTask

        function onDeviceProgress(deviceKey, state) {
            var text = "";
            if (state === 0)
                text = qsTr("正在上传固件...");
            else if (state === 1)
                text = qsTr("上传完成, 等待设备重启生效...");
            else if (state === 2)
                text = qsTr("升级成功");
            else if (state === 3)
                text = qsTr("升级失败");
            panel.setRowStatus(deviceKey, text);
        }

        function onDeviceResult(deviceKey, success, newVersion) {
            panel.appendRowItem(deviceKey, qsTr("固件升级"), success);
            // 升级成功且有新版本号 → 更新设备列表"升级后版本号"列
            if (newVersion && newVersion !== "")
                host.setDeviceTargetVersion(deviceKey, newVersion);
        }

        function onAllFinished() {
            panel.batchRunning = false;
            panel.upgradeRunning = false;
            panel.batchAllFinished();
        }

    }

    // ===== "执行修改（设定IP）"：按勾选数量给勾选设备下发新 IP =====
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

    // "执行修改"点击入口：没设IP先提示；没勾选时列表为空直接提示，
    // 有设备则弹"是|否"确认是否全选（是→全选并继续）；已勾选直接执行。
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
    // 供本面板"执行修改"与 main.qml 的"是→全选"确认框共用
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
                "uid": uid,
                "ip": ip,
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

        // 网络设置项的 newIp（设备切 IP 后续填 URL）由 BatchSettingsTask（C++）从
        // other_settings.json 里保存的 IP 取，QML 不再组装

        panel.batchRows = rows;
        panel.batchRunning = true;
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
                "uid": row.uid,
                "ip": row.ip,
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
                    "uid": row.uid,
                    "ip": row.ip,
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

    // "执行修改（设定IP）"勾选多台时 findFreeIpsAsync 的结果：凑满等量空闲 IP 后逐台配对下发
    Connections {
        function onSignalFreeIpsFound(baseIp, wanted, freeIps) {
            // "执行修改（设定IP）"多台的分配结果：凑满等量空闲 IP 后逐台配对下发
            if (panel.ipAllocating && baseIp === panel.ipAllocatingBaseIp) {
                panel.ipAllocating = false;
                panel.ipAllocatingBaseIp = "";
                if ((freeIps.length === 0 && wanted > 0) || freeIps.length < wanted) {
                    // 空闲 IP 数不够：提示具体差额，不下发任何 IP 避免冲突
                    confirmBox.showTip(qsTr("温馨提示"), qsTr("起始IP后续可用IP不足, 批量分配失败, 请更换起始IP, 减少设备或更换网段").arg(freeIps.length).arg(wanted));
                    return ;
                }
                panel.sendSetIpRequests(freeIps);
                confirmBox.showTip(qsTr("温馨提示"), qsTr("批量修改IP请求已发送, 请等待设备响应"));
                return ;
            }
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
        visible: false
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
