import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt.labs.qmlmodels 1.0
// 用命名空间导入：避免与 QtQuick.Controls 的 Menu / Dialog 等类型重名
import Qt.labs.platform 1.1 as Platform
import IPCam.Public 1.0
// 项目内封装的通用控件目录
import "Controls"

ApplicationWindow {
    id: root

    // 表格列标题（共 10 列，默认可视区域只显示前 6 列，其余需拖动底部水平滚动条）
    property var tableTitles: [qsTr("IP地址"), qsTr("云ID"), qsTr("全网通"), qsTr("状态信息"), qsTr("升级当前版本号"), qsTr("升级后版本号"), qsTr("OSD标题"), qsTr("物理地址"), qsTr("序列号"), qsTr("设备类型")]
    // 是否允许鼠标拖拽表头分割线调整列宽
    property bool tableResizable: true
    // 列宽模式：false = 固定列宽（前 6 列合计约等于默认可视宽度，第 7~10 列需横向滚动查看）
    //           true  = 按 tableStretchFactors 权重拉伸，10 列全部压缩进可视区
    property bool tableStretchToFill: false
    // 固定列宽（tableStretchToFill 为 false 时生效）
    property var tableFixedWidths: [ScreenTools.scaleNum(150), ScreenTools.scaleNum(120), ScreenTools.scaleNum(100), ScreenTools.scaleNum(130), ScreenTools.scaleNum(193), ScreenTools.scaleNum(193), ScreenTools.scaleNum(130), ScreenTools.scaleNum(150), ScreenTools.scaleNum(150), ScreenTools.scaleNum(120)]
    // 拉伸权重（tableStretchToFill 为 true 时生效）
    property var tableStretchFactors: [1.1, 1, 0.9, 1.1, 1.3, 1.3, 1.1, 1.2, 1.2, 1.1]
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
    // 固件升级：上一次打开固件文件所在目录（没选过时用系统默认目录）
    property url lastFirmwareDir: ""
    // 固件升级：已选择的升级文件本地路径列表（支持多选）
    property var fwFilePaths: []

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

    // 启动时拉取一次网卡列表（并按配置文件自动回显），随后把网卡信息打印到日志
    Component.onCompleted: {
        root.refreshNics();
        root.logNicList();
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

                        model: TableModel {
                            id: deviceModel

                            TableModelColumn {
                                display: "ip"
                            }
                            TableModelColumn {
                                display: "cloudId"
                            }
                            TableModelColumn {
                                display: "allNetcom"
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
                                display: "serialNo"
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
                        text: qsTr("设备搜索")
                        onClicked: root.logAction(qsTr("我点击了%1按钮").arg(text))
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
                    id: fwFilePathInput
                    Layout.fillWidth: true
                    Layout.columnSpan: 2
                    Layout.minimumWidth: ScreenTools.scaleNum(60)
                    // 手动粘贴/输入路径时也同步记住目录（多个文件以 “;” 分隔）
                    onEditingFinished: {
                        if (text.length === 0) {
                            root.fwFilePaths = [];
                            return;
                        }
                        var arr = text.split(";");
                        var list = [];
                        for (var i = 0; i < arr.length; i++) {
                            var one = arr[i].trim();
                            if (one.length > 0)
                                list.push(one);
                        }
                        root.fwFilePaths = list;
                        if (list.length > 0) {
                            var p = list[list.length - 1].replace(/\\/g, "/");
                            var idx = p.lastIndexOf("/");
                            if (idx > 0)
                                root.lastFirmwareDir = "file:///" + p.substring(0, idx);
                        }
                    }
                }
                RowLayout {
                    spacing: ScreenTools.scaleNum(6)

                    AppButton {
                        text: qsTr("浏览")
                        onClicked: {
                            root.logAction(qsTr("我点击了%1按钮（升级文件）").arg(text));
                            fwFileDialog.open();
                        }
                    }
                    AppButton {
                        text: qsTr("文件一键升级")
                        onClicked: {
                            // 未选择升级文件时只提示，不执行升级
                            if (root.fwFilePaths.length === 0 || fwFilePathInput.text.trim() === "") {
                                tipBox.show(qsTr("温馨提示"), qsTr("请先选择升级文件"));
                                console.log(qsTr("固件升级-一键升级失败: 未选择升级文件"));
                                return;
                            }
                            root.logAction(qsTr("我点击了%1按钮").arg(text));
                            console.log(qsTr("固件升级-开始一键升级, 共%1个文件").arg(root.fwFilePaths.length));
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

    // ===== 固件升级：升级文件选择（只筛选 *.bin，默认打开上次所在目录） =====
    Platform.FileDialog {
        id: fwFileDialog
        title: qsTr("选择固件升级文件")
        // 多选已存在的固件文件（可 Ctrl / Shift 多选）
        fileMode: Platform.FileDialog.OpenFiles
        // 只筛选 .bin 结尾的固件文件
        nameFilters: [qsTr("固件文件 (*.bin)"), qsTr("所有文件 (*)")]
        // 默认打开上次所在目录（没选过则用系统默认目录）
        folder: root.lastFirmwareDir
        onAccepted: {
            var urls = fwFileDialog.files;
            var paths = [];
            for (var i = 0; i < urls.length; i++) {
                var s = urls[i].toString();
                paths.push(s.replace(/^file:\/{3}/, ""));
            }
            root.fwFilePaths = paths;
            // 多个文件用 “;” 分隔显示
            fwFilePathInput.text = paths.join("; ");
            // 记住本次所在目录（取最后一个文件所在目录），下次打开时默认进入
            if (paths.length > 0) {
                var last = urls[urls.length - 1].toString();
                root.lastFirmwareDir = last.substring(0, last.lastIndexOf("/"));
            }
            console.log(qsTr("固件升级-选择升级文件(%1个): ").arg(paths.length) + paths.join(" | "));
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
}
