import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt.labs.qmlmodels 1.0
// 用别名导入：QtQuick.Dialogs 也提供名为 Dialog 的类型，
// 不加别名会覆盖 QtQuick.Controls 的 Dialog（导致 footer/header 赋值报错）
import QtQuick.Dialogs 1.3 as AppDialogs
import IPCam.Public 1.0
// 项目内封装的通用控件目录（AppButton / AppTextField / DeviceTable 等）
import "Controls"

ApplicationWindow {
    id: root

    // 表格列标题（共 8 列，默认可视区域只显示前 6 列，其余需拖动底部水平滚动条）
    // 顺序与下方 TableModelColumn 一一对应；设备ID（UID）填在“云ID”列
    property var tableTitles: [qsTr("IP地址"), qsTr("云ID"), qsTr("状态信息"), qsTr("升级当前版本号"), qsTr("升级后版本号"), qsTr("OSD标题"), qsTr("物理地址"), qsTr("设备类型")]
    // 是否允许鼠标拖拽表头分割线调整列宽
    property bool tableResizable: true
    // 列宽模式：false = 固定列宽（前 6 列合计约等于默认可视宽度，第 7~8 列需横向滚动查看）
    //           true  = 按 tableStretchFactors 权重拉伸，8 列全部压缩进可视区
    property bool tableStretchToFill: false
    // 固定列宽（tableStretchToFill 为 false 时生效）
    property var tableFixedWidths: [ScreenTools.scaleNum(150), ScreenTools.scaleNum(190), ScreenTools.scaleNum(130), ScreenTools.scaleNum(193), ScreenTools.scaleNum(193), ScreenTools.scaleNum(130), ScreenTools.scaleNum(150), ScreenTools.scaleNum(120)]
    // 拉伸权重（tableStretchToFill 为 true 时生效）
    property var tableStretchFactors: [1.1, 1.6, 1.1, 1.3, 1.3, 1.1, 1.2, 1.1]
    // 统一控件高度
    readonly property int controlHeight: ScreenTools.scaleNum(30)
    // 统一字体
    readonly property font appFont: Qt.font({
        "family": "Microsoft YaHei",
        "pointSize": ScreenTools.scaleNum(10, true)
    })
    // 已勾选设备的行号（由“全选 / 反选”维护）
    property var selectedRows: []
    readonly property int selectedCount: selectedRows.length
    // 设备搜索中：按钮禁用、结束后由 DeviceScanner.searchFinished 复位
    property bool searching: false
    // 搜索时长（秒），与“系统配置 - 搜索时间(秒)”联动
    property int searchSeconds: 5
    // 固件升级：已选择的升级文件（本地路径列表，*.bin，可多选）
    property var upgradeFiles: []
    // 上次打开“升级文件”选择框时所在的目录（由 ConfigureManager 持久化到 ini）
    readonly property string lastUpgradeDir: ConfigureManager.upgradeDir
    // 网卡信息列表（ScreenTools::getNetworkInterfaces() 的返回值，已过滤为 ipconfig 可见项）
    property var nicList: []
    // 网卡下拉框数据：第一项固定“所有网卡”，之后为各网卡
    // 显示格式 "[ip] [网卡名称]"（如 "192.168.5.100 Realtek PCIe GBE Family Controller"）：
    // 该项只用于展示，写入配置文件与启动时匹配都只用网卡名称（displayName）
    readonly property var nicModel: [{
        "display": qsTr("所有网卡")
    }].concat(root.nicList.map(function (nic) {
        var ips = nic["ipv4"] || [];
        var name = nic["displayName"] || "";
        // 网卡没有 IPv4 地址时只显示名称
        return {
            "display": (ips.length > 0 ? ("[" + ips[0] + "]") + " " : "") + ("[" + name + "]")
        };
    }))

    // ===== 网卡相关 =====
    // 刷新网卡列表，并按配置文件里保存的网卡名自动选中（启动时调用一次）
    function refreshNics() {
        nicList = ScreenTools.getNetworkInterfaces();
        root.restoreNicSelection();
    }

    // 当前选中的网卡信息，选中“所有网卡”时为 null
    function currentNic() {
        // 下拉框第 0 项是“所有网卡”，真实网卡从下标 1 开始
        var idx = nicCombo.currentIndex - 1;
        if (idx < 0 || idx >= root.nicList.length)
            return null;

        return root.nicList[idx];
    }

    // 启动时把获取到的网卡信息整体打印一次，用 ********** 包裹，方便在日志里区分定位
    function logNicList() {
        root.logAction("********** 网卡信息开始 **********");
        for (var i = 0; i < root.nicList.length; i++) {
            var n = root.nicList[i];
            root.logAction("  [网卡 " + i + "] 名称=" + (n["displayName"] || "")
                + " | 可读名=" + (n["humanReadableName"] || "")
                + " | 描述=" + (n["description"] || "")
                + " | MAC=" + (n["hardwareAddress"] || "")
                + " | IPv4=" + ((n["ipv4"] || []).join(", "))
                + " | 子网掩码=" + (n["netmask"] || "")
                + " | 网关=" + (n["gateway"] || "")
                + " | 已启用=" + (n["isUp"] ? "是" : "否"));
        }
        root.logAction("********** 网卡信息结束，共 " + root.nicList.length + " 张 **********");
        var cur = root.currentNic();
        root.logAction("当前使用的网卡: " + (cur ? cur["displayName"] : qsTr("所有网卡")));
    }

    // 按配置文件中保存的网卡名匹配；匹配不到（含“All netCard”）则选中第一项“所有网卡”
    function restoreNicSelection() {
        var saved = ConfigureManager.networkCard;
        var target = 0;
        for (var i = 0; i < root.nicList.length; i++) {
            if (root.nicList[i]["displayName"] === saved) {
                target = i + 1;
                break;
            }
        }
        nicCombo.currentIndex = target;
    }

    // 用户改动选择后写入本地配置文件：选中“所有网卡”时写入 "All netCard"
    function saveNicSelection() {
        var nic = root.currentNic();
        ConfigureManager.networkCard = nic ? (nic["displayName"] || ConfigureManager.defaultNetworkCard()) : ConfigureManager.defaultNetworkCard();
    }

    // ===== 勾选相关 =====
    function selectAll() {
        var list = [];
        for (var i = 0; i < deviceModel.rowCount; i++) list.push(i);
        selectedRows = list;
    }

    function invertSelection() {
        var list = [];
        for (var i = 0; i < deviceModel.rowCount; i++) {
            if (selectedRows.indexOf(i) < 0)
                list.push(i);

        }
        selectedRows = list;
    }

    // 表格排序后行号重排：按 DeviceTable 给出的“旧行号 -> 新行号”映射同步已选行
    function remapSelectedRows(indexMap) {
        var list = [];
        for (var i = 0; i < root.selectedRows.length; i++) {
            var newIndex = indexMap[root.selectedRows[i]];
            if (newIndex !== undefined)
                list.push(newIndex);

        }
        root.selectedRows = list;
    }

    // 表格里某一行的复选框勾选/取消：同步进 selectedRows，
    // “已选数量”与“请先选择设备”的校验都读这份数据，自动保持一致
    function setRowChecked(row, checked) {
        var list = root.selectedRows.slice();
        var idx = list.indexOf(row);
        if (checked && idx < 0) {
            list.push(row);
        } else if (!checked && idx >= 0) {
            list.splice(idx, 1);
        }
        selectedRows = list;
    }

    // ===== 选中设备的持久化（交给 C++ 的 DeviceManager）=====
    // 勾选（可多选）的设备按 uid 存进 QMap<uid, DeviceInfo>，供批量操作直接取用。
    // 行号会随排序 / 重新搜索变化，所以这里只同步“设备本身”，不存行号
    function syncCheckedDevices() {
        var list = [];
        for (var i = 0; i < root.selectedRows.length; i++) {
            var dev = deviceModel.rows[root.selectedRows[i]];
            if (dev !== undefined)
                list.push(dev);

        }
        DeviceManager.syncCheckedDevices(list);
    }

    // 勾选的行号一变就同步一次（单个勾选 / 全选 / 反选 / 清空都走这里）
    onSelectedRowsChanged: root.syncCheckedDevices()

    // 当前选中（浅蓝高亮）的那一条单独保存一份，供单台操作取用
    function syncCurrentDevice() {
        var row = deviceTable.currentRow;
        if (row >= 0 && row < deviceModel.rowCount)
            DeviceManager.setCurrentDevice(deviceModel.rows[row]);
        else
            DeviceManager.clearCurrentDevice();

    }

    // ===== 操作日志 =====
    // 从调用栈里取“调用 logAction 的那一层”的位置（第 0 帧是 logAction 自身）
    // 返回 {file, line, function}，解析失败时返回空串/0
    function callerLocation() {
        var stack = "";
        try {
            stack = String(new Error().stack);
        } catch (e) {
            return {
                "file": "",
                "line": 0,
                "function": ""
            };
        }
        var frames = stack.split("\n");
        // 帧格式：函数名@文件:行号；跳过 callerLocation / logAction 自身，取真正的调用方
        var frame = "";
        for (var i = 0; i < frames.length; i++) {
            var name = frames[i];
            var sep = name.lastIndexOf("@");
            if (sep >= 0)
                name = name.substring(0, sep);

            name = name.trim();
            if (name !== "callerLocation" && name !== "logAction") {
                frame = frames[i];
                break;
            }
        }
        if (frame === "")
            return {
                "file": "",
                "line": 0,
                "function": ""
            };

        var at = frame.lastIndexOf("@");
        if (at < 0)
            return {
                "file": "",
                "line": 0,
                "function": frame.trim()
            };

        var func = frame.substring(0, at).trim();
        var fileLine = frame.substring(at + 1).trim();
        // 去掉协议与目录，只保留文件名；行号取最后一个冒号之后
        var fileName = fileLine.substring(fileLine.lastIndexOf("/") + 1);
        var colon = fileName.lastIndexOf(":");
        var line = 0;
        if (colon >= 0) {
            line = parseInt(fileName.substring(colon + 1));
            if (isNaN(line))
                line = 0;

            fileName = fileName.substring(0, colon);
        }
        return {
            "file": fileName,
            "line": line,
            "function": func
        };
    }

    // 按钮点击、网卡切换等操作统一走这里输出一行日志（写入 LogText.txt）
    function logAction(text) {
        var loc = root.callerLocation();
        AppLogger.write(loc["file"], loc["line"], loc["function"], text);
    }

    // ===== 设备搜索 =====
    // 触发一次广播搜索：网段 = 主界面所选网卡对应的网段（选“所有网卡”则不限制），
    // 时长 = “系统配置 - 搜索时间(秒)”；结果由下方 Connections 逐台追加进列表
    function searchDevices() {
        if (root.searching)
            return;

        // 选中“所有网卡”时为 null，传空串表示不限制网段
        var nic = root.currentNic();
        // WifiBroadcast 按“可读名 / 网卡名 / 网卡 IPv4”匹配网卡，优先传可读名
        var nicName = nic ? (nic["humanReadableName"] || nic["displayName"] || "") : "";
        var ips = nic ? (nic["ipv4"] || []) : [];
        var nicDesc = nic ? (nicName + "(" + (ips.length > 0 ? ips[0] : qsTr("无IP")) + ")") : qsTr("所有网卡");

        root.logAction(qsTr("设备搜索开始: 网卡=%1, 时长=%2秒").arg(nicDesc).arg(root.searchSeconds));

        // 清空上一次的结果、勾选与选中行
        // （selectedRows / currentRow 归零会触发同步；这里再显式清一次，
        //  避免“本来就是 0 / -1 不触发变化信号”导致 C++ 侧残留上一轮的设备）
        deviceModel.rows = [];
        root.selectedRows = [];
        deviceTable.currentRow = -1;
        DeviceManager.clearCheckedDevices();
        DeviceManager.clearCurrentDevice();
        root.searching = true;
        DeviceScanner.startSearch(nicName, root.searchSeconds);
    }

    // ===== 固件升级 =====
    // file:/// 开头的 url 转本地路径（如 "file:///C:/a/b.bin" -> "C:/a/b.bin"）
    function urlToLocalPath(url) {
        var s = String(url);
        if (s.indexOf("file:///") === 0)
            s = s.substring(8);
        return decodeURIComponent(s);
    }

    // 取本地路径里的文件名（如 "C:/a/b.bin" -> "b.bin"）
    function pathFileName(path) {
        var i = Math.max(String(path).lastIndexOf("/"), String(path).lastIndexOf("\\"));
        return i >= 0 ? String(path).substring(i + 1) : String(path);
    }

    // 取本地路径里的目录（如 "C:/a/b.bin" -> "C:/a"）
    function pathDirName(path) {
        var s = String(path);
        var i = Math.max(s.lastIndexOf("/"), s.lastIndexOf("\\"));
        return i >= 0 ? s.substring(0, i) : s;
    }

    // 已选文件在“升级文件”输入框里的摘要（最多列 3 个，超出显示总数）
    function upgradeFileSummary() {
        var files = root.upgradeFiles;
        if (files.length === 0)
            return "";

        var names = [];
        for (var i = 0; i < files.length && i < 3; i++)
            names.push(root.pathFileName(files[i]));

        var text = names.join(", ");
        if (files.length > 3)
            text += qsTr(" 等 %1 个文件").arg(files.length);
        return text;
    }

    // “文件一键升级”：先校验升级文件，再校验设备，最后执行升级
    function startFileUpgrade() {
        if (root.upgradeFiles.length === 0) {
            tipBox.show(qsTr("温馨提示"), qsTr("请先选择升级文件"));
            return;
        }
        if (!root.ensureDeviceSelected())
            return;

        root.logAction(qsTr("开始升级: 文件 %1 个, 设备 %2 台").arg(root.upgradeFiles.length).arg(root.selectedCount));
    }

    // 设备操作前置校验：列表为空或没勾选任何设备时提示，返回 false 表示中断
    function ensureDeviceSelected() {
        if (deviceModel.rowCount === 0 || root.selectedCount === 0) {
            tipBox.show(qsTr("温馨提示"), qsTr("请先选择设备"));
            return false;
        }
        return true;
    }

    width: ScreenTools.scaleNum(1200)
    height: ScreenTools.scaleNum(740)
    minimumWidth: ScreenTools.scaleNum(900)
    minimumHeight: ScreenTools.scaleNum(560)
    visible: true
    title: qsTr("IPC BatchTool_V1.0.0.0")
    color: "#f0f0f0"
    font.family: "Microsoft YaHei"
    font.pointSize: ScreenTools.scaleNum(10, true)

    // 接收设备搜索结果：每发现一台追加一行，搜索结束复位按钮状态
    Connections {
        target: DeviceScanner

        // 用显式函数写法（Qt 5.15 对隐式 onFoo 写法会告警）
        function onDeviceFound(device) {
            deviceModel.appendRow(device);
        }
        function onSearchFinished(count) {
            root.searching = false;
            root.logAction(qsTr("设备搜索结束: 共发现 %1 台设备").arg(count));
        }
    }

    // 当前选中行变化（点击表格任意位置 / 勾选时顺带选中）→ 同步 DeviceManager 里的“当前设备”
    Connections {
        target: deviceTable
        function onCurrentRowChanged() {
            root.syncCurrentDevice();
        }
    }

    // 启动时拉取一次网卡列表（并按配置文件自动回显），随后把网卡信息打印到日志
    Component.onCompleted: {
        root.refreshNics();
        root.logNicList();
        // 程序启动自动执行一次设备搜索；延后一个事件循环，等窗口与表格就绪
        Qt.callLater(root.searchDevices);
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: ScreenTools.scaleNum(12)
        spacing: ScreenTools.scaleNum(4)

        // ===== 顶部工具栏 =====
        RowLayout {
            Layout.fillWidth: true
            spacing: ScreenTools.scaleNum(16)

            AppButton {
                text: qsTr("全选")
                highlighted: true
                onClicked: {
                    root.logAction(qsTr("我点击了%1按钮").arg(text));
                    root.selectAll();
                }
            }
            AppButton {
                text: qsTr("反选")
                onClicked: {
                    root.logAction(qsTr("我点击了%1按钮").arg(text));
                    root.invertSelection();
                }
            }
            Label {
                Layout.preferredHeight: root.controlHeight
                Layout.minimumWidth: ScreenTools.scaleNum(120)
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                text: qsTr("搜索完成, 总数: %1    已选: %2").arg(deviceModel.rowCount).arg(root.selectedCount)
            }
            AppCheckBox {
                Layout.preferredHeight: root.controlHeight
                text: qsTr("主码流播放")
                onToggled: root.logAction(qsTr("%1已%2").arg(text).arg(checked ? qsTr("勾选") : qsTr("取消勾选")))
            }
            Item {
                Layout.fillWidth: true
            }
            Label {
                Layout.preferredHeight: root.controlHeight
                verticalAlignment: Text.AlignVCenter
                text: qsTr("网卡")
            }
            AppComboBox {
                id: nicCombo
                Layout.minimumWidth: ScreenTools.scaleNum(360)
                Layout.maximumWidth: ScreenTools.scaleNum(440)
                Layout.preferredHeight: root.controlHeight
                Layout.fillWidth: true
                // 下拉框展示 "[ip] [网卡名称]"，取值/匹配仍用网卡名称
                textRole: "display"
                model: root.nicModel
                // 默认选中第一项“所有网卡”，启动时由 restoreNicSelection() 按配置文件覆盖
                currentIndex: 0
                // 只在用户主动选择时写配置文件（程序自动回显不写，避免网卡临时消失时丢失配置）
                onActivated: {
                    root.saveNicSelection();
                    var nic = root.currentNic();
                    root.logAction(qsTr("网卡切换为'%1'").arg(nic ? nic["displayName"] : qsTr("所有网卡")));
                }
            }
            AppButton {
                Layout.preferredWidth: ScreenTools.scaleNum(90)
                Layout.preferredHeight: root.controlHeight
                Layout.fillWidth: false
                text: qsTr("系统配置")
                onClicked: {
                    root.logAction(qsTr("我点击了%1按钮").arg(text));
                    systemConfigDialog.open();
                }
            }
        }

        // ===== 中部：左侧设备表格 3/4 + 右侧操作指令 1/4 =====
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: ScreenTools.scaleNum(200)

            Row {
                id: midRow

                anchors.fill: parent
                spacing: ScreenTools.scaleNum(6)

                // 设备信息表格（3/4）：外层 2px 深灰边框，表格显示在框内
                Rectangle {
                    width: (midRow.width - midRow.spacing) * 3 / 4
                    height: midRow.height
                    color: "white"
                    border.width: 1
                    border.color: "#333333"

                    DeviceTable {
                        id: deviceTable

                        anchors.fill: parent
                        // 让出 2px 边框，表格内容显示在框内
                        anchors.margins: ScreenTools.scaleNum(2)
                        titles: root.tableTitles
                        resizable: root.tableResizable
                        stretchToFill: root.tableStretchToFill
                        fixedWidths: root.tableFixedWidths
                        stretchFactors: root.tableStretchFactors
                        headerHeight: Math.round(root.controlHeight * 1.5)
                        rowHeight: root.controlHeight
                        labelFont: root.appFont
                        // IP 列（第 0 列）显示“复选框 + IP”，勾选状态与“已选数量”联动
                        checkBoxColumn: 0
                        checkedRows: root.selectedRows
                        onRowChecked: root.setRowChecked(row, checked)
                        // 排序所用字段名，与下方 TableModelColumn 的 display 一一对应
                        columnRoles: ["ip", "cloudId", "status", "currentVersion", "targetVersion", "osdTitle", "mac", "deviceType"]
                        // 排序会打乱行号：按“旧行号 -> 新行号”同步已勾选设备，
                        // 并按新的行号重新保存“当前选中设备”（数据此时已是最新的）
                        onRowsReordered: {
                            root.remapSelectedRows(indexMap);
                            root.syncCurrentDevice();
                        }

                        model: TableModel {
                            id: deviceModel

                            TableModelColumn {
                                display: "ip"
                            }
                            TableModelColumn {
                                display: "cloudId"
                            }
                            TableModelColumn {
                                display: "status"
                            }
                            TableModelColumn {
                                display: "currentVersion"
                            }
                            TableModelColumn {
                                display: "targetVersion"
                            }
                            TableModelColumn {
                                display: "osdTitle"
                            }
                            TableModelColumn {
                                display: "mac"
                            }
                            TableModelColumn {
                                display: "deviceType"
                            }

                            rows: []
                        }
                    }
                }

                // 操作指令面板（1/4）
                ColumnLayout {
                    width: (midRow.width - midRow.spacing) / 4
                    height: midRow.height
                    spacing: ScreenTools.scaleNum(8)

                    Label {
                        Layout.preferredHeight: root.controlHeight
                        verticalAlignment: Text.AlignVCenter
                        text: qsTr("操作指令")
                    }
                    AppButton {
                        Layout.fillWidth: true
                        // 搜索中改变文案并禁用，避免重复触发
                        text: root.searching ? qsTr("搜索中...") : qsTr("设备搜索")
                        enabled: !root.searching
                        onClicked: {
                            root.logAction(qsTr("我点击了%1按钮").arg(qsTr("设备搜索")));
                            root.searchDevices();
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ScreenTools.scaleNum(6)

                        AppButton {
                            Layout.fillWidth: true
                            text: qsTr("设定IP")
                            onClicked: {
                                root.logAction(qsTr("我点击了%1按钮").arg(text));
                                setIpDialog.open();
                            }
                        }
                        AppButton {
                            Layout.fillWidth: true
                            text: qsTr("执行修改")
                            onClicked: {
                                root.logAction(qsTr("我点击了%1按钮（设定IP）").arg(text));
                                root.ensureDeviceSelected();
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
                            root.logAction(qsTr("我点击了%1按钮").arg(text));
                            root.ensureDeviceSelected();
                        }
                    }
                    AppButton {
                        Layout.fillWidth: true
                        text: qsTr("重启设备")
                        onClicked: {
                            root.logAction(qsTr("我点击了%1按钮").arg(text));
                            root.ensureDeviceSelected();
                        }
                    }
                    AppButton {
                        Layout.fillWidth: true
                        text: qsTr("恢复出厂设置")
                        onClicked: {
                            root.logAction(qsTr("我点击了%1按钮").arg(text));
                            root.ensureDeviceSelected();
                        }
                    }
                    AppButton {
                        Layout.fillWidth: true
                        text: qsTr("播放勾选设备")
                        onClicked: {
                            root.logAction(qsTr("我点击了%1按钮").arg(text));
                            root.ensureDeviceSelected();
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
                                root.logAction(qsTr("我点击了%1按钮").arg(text));
                                osdDialog.open();
                            }
                        }
                        AppButton {
                            Layout.fillWidth: true
                            text: qsTr("执行修改")
                            onClicked: {
                                root.logAction(qsTr("我点击了%1按钮（设定OSD）").arg(text));
                                root.ensureDeviceSelected();
                            }
                        }
                    }

                    AppCheckBox {
                        Layout.preferredHeight: root.controlHeight
                        text: qsTr("锁定默认参数")
                        onToggled: root.logAction(qsTr("%1已%2").arg(text).arg(checked ? qsTr("勾选") : qsTr("取消勾选")))
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ScreenTools.scaleNum(6)

                        AppButton {
                            Layout.fillWidth: true
                            text: qsTr("配置其他参数")
                            onClicked: {
                                root.logAction(qsTr("我点击了%1按钮").arg(text));
                                otherSettingsDialog.open();
                            }
                        }
                        AppButton {
                            Layout.fillWidth: true
                            text: qsTr("执行修改")
                            onClicked: {
                                root.logAction(qsTr("我点击了%1按钮（配置其他参数）").arg(text));
                                root.ensureDeviceSelected();
                            }
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                        Layout.minimumHeight: 0
                    }
                }
            }
        }

        // ===== 底部：固件升级 =====
        GroupBox {
            Layout.fillWidth: true
            Layout.preferredHeight: ScreenTools.scaleNum(120)
            title: qsTr("固件升级")

            GridLayout {
                columns: 4
                columnSpacing: ScreenTools.scaleNum(8)
                rowSpacing: ScreenTools.scaleNum(4)
                width: parent.width

                Label {
                    Layout.preferredHeight: root.controlHeight
                    verticalAlignment: Text.AlignVCenter
                    text: qsTr("升级文件")
                }
                AppTextField {
                    id: upgradeFileInput

                    Layout.fillWidth: true
                    Layout.columnSpan: 2
                    Layout.minimumWidth: ScreenTools.scaleNum(60)
                    // 展示已选文件摘要；路径很长时末尾省略
                    text: root.upgradeFileSummary()
                    readOnly: true
                    placeholderText: qsTr("请选择 .bin 升级文件（可多选）")
                }
                RowLayout {
                    spacing: ScreenTools.scaleNum(6)

                    AppButton {
                        text: qsTr("浏览")
                        onClicked: {
                            root.logAction(qsTr("我点击了%1按钮（升级文件）").arg(text));
                            upgradeFileDialog.open();
                        }
                    }
                    AppButton {
                        text: qsTr("文件一键升级")
                        onClicked: {
                            root.logAction(qsTr("我点击了%1按钮").arg(text));
                            root.startFileUpgrade();
                        }
                    }
                }

                Label {
                    Layout.preferredHeight: root.controlHeight
                    verticalAlignment: Text.AlignVCenter
                    text: qsTr("升级目录")
                    visible: false
                }
                AppTextField {
                    Layout.fillWidth: true
                    Layout.columnSpan: 2
                    Layout.minimumWidth: ScreenTools.scaleNum(60)
                    visible: false
                }
                RowLayout {
                    spacing: ScreenTools.scaleNum(6)
                    visible: false

                    AppButton {
                        text: qsTr("浏览")
                        onClicked: root.logAction(qsTr("我点击了%1按钮（升级目录）").arg(text))
                    }
                    AppButton {
                        text: qsTr("目录升级")
                        onClicked: root.logAction(qsTr("我点击了%1按钮").arg(text))
                    }
                }

                AppComboBox {
                    Layout.minimumWidth: ScreenTools.scaleNum(110)
                    Layout.preferredHeight: root.controlHeight
                    model: [qsTr("上传音频文件"), qsTr("上传配置文件")]
                    visible: false
                    onActivated: root.logAction(qsTr("上传类型切换为'%1'").arg(currentText))
                }
                AppTextField {
                    Layout.fillWidth: true
                    Layout.columnSpan: 2
                    Layout.minimumWidth: ScreenTools.scaleNum(60)
                    visible: false
                }
                RowLayout {
                    spacing: ScreenTools.scaleNum(6)
                    visible: false

                    AppButton {
                        text: qsTr("浏览")
                        onClicked: root.logAction(qsTr("我点击了%1按钮（上传文件）").arg(text))
                    }
                    AppButton {
                        text: qsTr("开始上传")
                        onClicked: root.logAction(qsTr("我点击了%1按钮").arg(text))
                    }
                }
            }
        }

        // 底部提示
        Label {
            Layout.fillWidth: true
            Layout.preferredHeight: root.controlHeight
            verticalAlignment: Text.AlignVCenter
            color: "#333333"
            elide: Text.ElideRight
            visible: false
            text: qsTr("右键可选择打开浏览器、查看下载设备二维码、远程配置操作!")
        }
    }

    // ===== 系统配置弹窗 =====
    Dialog {
        id: systemConfigDialog

        title: qsTr("系统配置")
        modal: true
        dim: true
        width: ScreenTools.scaleNum(420)
        anchors.centerIn: Overlay.overlay

        // 底部按钮：自定义文案，沿用 AppButton（文本居中、超长自动换行）
        footer: DialogButtonBox {
            alignment: Qt.AlignRight
            spacing: ScreenTools.scaleNum(16)

            AppButton {
                text: qsTr("取消")
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                onClicked: root.logAction(qsTr("我点击了%1按钮（系统配置）").arg(text))
            }
            AppButton {
                text: qsTr("保存")
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                highlighted: true
                onClicked: root.logAction(qsTr("我点击了%1按钮（系统配置）").arg(text))
            }
        }

        // 点击“保存”后弹出提示
        onAccepted: tipBox.show(qsTr("温馨提示"), qsTr("保存成功"))

        GridLayout {
            columns: 3
            columnSpacing: ScreenTools.scaleNum(10)
            rowSpacing: ScreenTools.scaleNum(10)
            width: systemConfigDialog.availableWidth

            Label {
                Layout.preferredHeight: root.controlHeight
                verticalAlignment: Text.AlignVCenter
                text: qsTr("搜索时间(秒)")
            }
            SpinBox {
                id: searchTimeSpin

                // “− / +”按钮为正方形，边长与控件高度一致
                readonly property int btnW: root.controlHeight

                Layout.fillWidth: true
                Layout.preferredHeight: root.controlHeight
                from: 5
                to: 120
                value: 5
                stepSize: 1
                editable: true
                hoverEnabled: true
                // 注意：左右内边距必须同时为“− / +”按钮留出位置。
                // 只改 leftPadding 会让输入框（contentItem，z=2）盖住左侧的“−”按钮，导致点击无效
                padding: 0
                leftPadding: btnW
                rightPadding: btnW
                font.family: "Microsoft YaHei"
                font.pointSize: ScreenTools.scaleNum(10, true)

                background: Rectangle {
                    radius: ScreenTools.scaleNum(4)
                    color: searchTimeSpin.enabled ? "white" : "#f0f0f0"
                    border.width: 1
                    border.color: (searchTimeSpin.activeFocus || searchTimeSpin.hovered) ? "#2f6fed" : "#767676"
                }

                // 数字区：在两个按钮之间居中显示
                contentItem: TextInput {
                    z: 2
                    text: searchTimeSpin.displayText
                    font: searchTimeSpin.font
                    color: searchTimeSpin.enabled ? "#1A1A1A" : "#a0a0a0"
                    horizontalAlignment: Qt.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    readOnly: !searchTimeSpin.editable
                    validator: searchTimeSpin.validator
                    selectByMouse: true
                }

                // “−”按钮（左）：数值减 1 秒。
                // 四周内缩 1px，避免盖住外层边框；只圆外侧两个角（Rectangle 只支持统一圆角，
                // 内侧用同色小方块补成直角）
                down.indicator: Rectangle {
                    x: 1
                    y: 1
                    width: searchTimeSpin.btnW - 2
                    height: searchTimeSpin.height - 2
                    radius: ScreenTools.scaleNum(3)
                    color: searchTimeSpin.down.pressed ? "#BBD4FF" : "#F5F7FA"

                    // 补齐内侧两个直角
                    Rectangle {
                        anchors.right: parent.right
                        width: parent.radius
                        height: parent.height
                        color: parent.color
                    }
                    // 与输入区的分隔线
                    Rectangle {
                        anchors.right: parent.right
                        width: 1
                        height: parent.height
                        color: "#D8DCE3"
                    }

                    Label {
                        anchors.centerIn: parent
                        text: "-"
                        font.bold: true
                        font.pointSize: ScreenTools.scaleNum(12, true)
                        color: searchTimeSpin.enabled ? "#1A1A1A" : "#a0a0a0"
                    }
                }

                // “+”按钮（右）：数值加 1 秒
                up.indicator: Rectangle {
                    x: searchTimeSpin.width - width - 1
                    y: 1
                    width: searchTimeSpin.btnW - 2
                    height: searchTimeSpin.height - 2
                    radius: ScreenTools.scaleNum(3)
                    color: searchTimeSpin.up.pressed ? "#BBD4FF" : "#F5F7FA"

                    // 补齐内侧两个直角
                    Rectangle {
                        anchors.left: parent.left
                        width: parent.radius
                        height: parent.height
                        color: parent.color
                    }
                    // 与输入区的分隔线
                    Rectangle {
                        anchors.left: parent.left
                        width: 1
                        height: parent.height
                        color: "#D8DCE3"
                    }

                    Label {
                        anchors.centerIn: parent
                        text: "+"
                        font.bold: true
                        font.pointSize: ScreenTools.scaleNum(12, true)
                        color: searchTimeSpin.enabled ? "#1A1A1A" : "#a0a0a0"
                    }
                }
            }
            Label {
                Layout.preferredHeight: root.controlHeight
                verticalAlignment: Text.AlignVCenter
                text: qsTr("(5~120秒)")
            }

            Label {
                Layout.preferredHeight: root.controlHeight
                verticalAlignment: Text.AlignVCenter
                text: qsTr("语言")
            }
            AppComboBox {
                Layout.fillWidth: true
                Layout.preferredHeight: root.controlHeight
                model: [qsTr("简体中文"), "English"]
            }
            Label {
                Layout.preferredHeight: root.controlHeight
                verticalAlignment: Text.AlignVCenter
                text: qsTr("(重启生效)")
            }

            Label {
                Layout.preferredHeight: root.controlHeight
                verticalAlignment: Text.AlignVCenter
                text: qsTr("日志级别")
                visible: false
            }
            AppComboBox {
                Layout.fillWidth: true
                Layout.preferredHeight: root.controlHeight
                model: [qsTr("错误"), qsTr("警告"), qsTr("信息"), qsTr("调试")]
                visible: false
            }
        }
    }

    // ===== 通用提示弹窗 =====
    AppMessageBox {
        id: tipBox
    }

    // ===== 升级文件选择框 =====
    // 1) 只筛 *.bin；2) 默认打开上次所在目录（ConfigureManager 持久化），没记录时用“我的文档”
    // 3) selectMultiple 支持一次选多个文件
    AppDialogs.FileDialog {
        id: upgradeFileDialog

        title: qsTr("请选择升级文件")
        selectMultiple: true
        nameFilters: [qsTr("固件文件 (*.bin)"), qsTr("所有文件 (*)")]
        folder: root.lastUpgradeDir !== "" ? ("file:///" + root.lastUpgradeDir.replace(/\\/g, "/")) : shortcuts.home

        onAccepted: {
            var paths = [];
            for (var i = 0; i < upgradeFileDialog.fileUrls.length; i++)
                paths.push(root.urlToLocalPath(upgradeFileDialog.fileUrls[i]));

            root.upgradeFiles = paths;
            // 记住本次所在目录，下次打开时自动定位
            if (paths.length > 0)
                ConfigureManager.upgradeDir = root.pathDirName(paths[0]);

            root.logAction(qsTr("已选择升级文件: %1").arg(root.upgradeFileSummary()));
        }
    }

    // ===== 设定IP弹窗 =====
    SetIpDialog {
        id: setIpDialog
    }

    // ===== OSD参数共享存储：“OSD修改”弹窗 与 “其它设置-OSD设置”页共用同一份已保存参数 =====
    // 只存两个界面都有的项；saved 表示是否被保存过（未保存过时两侧各用默认值）
    QtObject {
        id: osdConfig

        property bool setTimeTitle: false
        property int osdDisplayIndex: 0
        property int timeFormatIndex: 0
        property bool showWeek: false
        property int titlePosIndex: 4
        property string titleContent: ""
        property bool saved: false
    }

    // ===== OSD修改弹窗 =====
    SetOsdDialog {
        id: osdDialog
        sharedOsd: osdConfig
    }

    // ===== 其它设置弹窗（由“配置其它参数”按钮触发） =====
    OtherSettingsDialog {
        id: otherSettingsDialog
        sharedOsd: osdConfig
    }

    // ===== 设备搜索遮罩 =====
    // 搜索期间覆盖整个窗口（黑底 50% 透明），并吞掉鼠标事件避免误点其它按钮；
    // 搜索结束（DeviceScanner.searchFinished -> root.searching = false）后自动消失
    Item {
        anchors.fill: parent
        z: 100
        visible: root.searching

        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: 0.5
        }

        // 吞掉鼠标事件：Label 不接收鼠标，点击会落到本层被拦截
        MouseArea {
            anchors.fill: parent
        }

        Column {
            anchors.centerIn: parent
            spacing: ScreenTools.scaleNum(12)

            // 转圈等待动画：蓝 -> 浅蓝渐变，顺时针匀速旋转
            Canvas {
                anchors.horizontalCenter: parent.horizontalCenter
                width: ScreenTools.scaleNum(48)
                height: ScreenTools.scaleNum(48)
                antialiasing: true

                readonly property color cStart: "#2f6fed" // 蓝
                readonly property color cEnd: "#9ed0ff" // 浅蓝
                readonly property int segments: 24 // 分段数，越多渐变越平滑
                readonly property real sweepDeg: 300 // 留一段缺口更像转圈
                readonly property real lineWidth: ScreenTools.scaleNum(4)

                // 逐段画圆弧并按序号插值上色，形成沿弧线的渐变
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    ctx.lineWidth = lineWidth;
                    ctx.lineCap = "round";
                    var cx = width / 2;
                    var cy = height / 2;
                    var r = (Math.min(width, height) - lineWidth) / 2;
                    var step = (sweepDeg / segments) * Math.PI / 180;
                    var from = -Math.PI / 2; // 12 点方向起笔
                    for (var i = 0; i < segments; i++) {
                        var t = i / (segments - 1);
                        ctx.strokeStyle = Qt.rgba(cStart.r + (cEnd.r - cStart.r) * t, cStart.g + (cEnd.g - cStart.g) * t, cStart.b + (cEnd.b - cStart.b) * t, 1).toString();
                        ctx.beginPath();
                        ctx.arc(cx, cy, r, from + i * step, from + (i + 1) * step);
                        ctx.stroke();
                    }
                }
                Component.onCompleted: requestPaint()

                // 中等转速：1.2 秒一圈；搜索结束自动停转
                RotationAnimation on rotation {
                    from: 0
                    to: 360
                    duration: 1200
                    loops: Animation.Infinite
                    running: root.searching
                }
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("设备搜索中...")
                color: "white"
                font.family: "Microsoft YaHei"
                font.pointSize: ScreenTools.scaleNum(12, true)
            }
        }
    }
}
