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
    readonly property int treeWidth: ScreenTools.scaleNum(200)
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
    // 与“OSD修改”弹窗共用的 OSD 参数（由 main.qml 注入），OSD设置页不走下面的面板内存储
    property QtObject sharedOsd: null
    // ===== 参数持久化：只有点面板上的“保存”才提交；关闭窗口/切换页面丢弃未保存的修改 =====
    // 结构：savedPanelValues[面板 key][控件在面板内的路径] = { k: 类型, v: 值 }
    property var savedPanelValues: ({
    })

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

    // 识别需要持久化的控件类型，返回 "" 表示不持久化
    //   time -> AppTimePicker；checked -> AppCheckBox；currentIndex -> AppComboBox
    //   ip -> AppIpInput；text -> AppTextField
    function persistedKind(obj) {
        // 密码框不持久化
        if (obj.echoMode !== undefined && obj.echoMode === TextInput.Password)
            return "";

        if (obj.time !== undefined && typeof obj.time === "string")
            return "time";

        if (obj.checkState !== undefined)
            return "checked";

        if (obj.currentIndex !== undefined && obj.popup !== undefined)
            return "currentIndex";

        if (typeof obj.text === "function" && typeof obj.value === "string")
            return "ip";

        // 只读的计算结果（如随编码方式联动的码率）不参与持久化
        if ((obj instanceof TextArea || obj instanceof TextField) && obj.readOnly !== true)
            return "text";

        return "";
    }

    // 这些对象及其内部不遍历：避免误改下拉项 delegate、按钮文本等
    function isSkipped(obj) {
        return obj instanceof Popup || obj instanceof ListView || obj instanceof Menu || obj instanceof ItemDelegate || obj instanceof AbstractButton || obj instanceof ScrollBar || obj instanceof ScrollIndicator || obj instanceof Tumbler || obj instanceof Repeater;
    }

    // 取子对象列表：ScrollView/Flickable/Control 等控件的声明式子项在 contentData/contentItem 中，
    // 不在 data 中，这里合并三者，保证表单能被完整遍历到
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

    // 遍历面板，收集所有可持久化控件的当前值
    function collectValues(obj, path, out) {
        var kind = root.persistedKind(obj);
        if (kind !== "") {
            if (kind === "time")
                out[path] = {"k": kind, "v": obj.time};
            else if (kind === "checked")
                out[path] = {"k": kind, "v": obj.checked};
            else if (kind === "currentIndex")
                out[path] = {"k": kind, "v": obj.currentIndex};
            else if (kind === "ip")
                out[path] = {"k": kind, "v": obj.text()};
            else
                out[path] = {"k": kind, "v": obj.text};
            return ;
        }
        if (root.isSkipped(obj))
            return ;

        var kids = root.childList(obj);
        for (var i = 0; i < kids.length; i++) root.collectValues(kids[i], path + "/" + i, out)
    }

    // 用已保存的值回填面板控件
    function applyValues(obj, path, store) {
        var kind = root.persistedKind(obj);
        if (kind !== "") {
            var rec = store[path];
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
        root.collectValues(panelLoader.item, "0", values);
        var m = {
        };
        for (var k in root.savedPanelValues) m[k] = root.savedPanelValues[k]
        m[root.selectedKey] = values;
        root.savedPanelValues = m;
        // OSD设置页额外写入与“OSD修改”弹窗共用的参数（同步函数定义在面板内部，通过 item 调用）
        if (root.selectedKey === "timeTitle" && panelLoader.item.writeShared)
            panelLoader.item.writeShared(root.sharedOsd);

        root.markSaved(root.selectedKey);
        saveTipBox.show(qsTr("温馨提示"), qsTr("保存成功"));
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

                                Layout.preferredWidth: ScreenTools.scaleNum(220)
                                value: "192.168.0.123"
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

                                Layout.preferredWidth: ScreenTools.scaleNum(220)
                                value: "255.255.255.0"
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

                                Layout.preferredWidth: ScreenTools.scaleNum(220)
                                value: "192.168.0.1"
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
                                text: qsTr("DNS1")
                            }

                            IpInput {
                                id: dns1Input

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
                                text: qsTr("DNS2")
                            }

                            IpInput {
                                id: dns2Input

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
                                text: qsTr("DHCP")
                            }

                            AppComboBox {
                                id: dhcpCombo

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
                                text: qsTr("MTU")
                            }

                            AppTextField {
                                id: mtuInput

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
                        // 先关闭，再打印日志：避免日志/取值出错时把弹窗卡住关不掉
                        console.log(qsTr("其它设置-网络设置保存: ") + JSON.stringify({
                            "setEthernet": ethCheck.checked,
                            "ip": ipAddrInput.text(),
                            "netmask": maskInput.text(),
                            "gateway": gwInput.text(),
                            "dns1": dns1Input.text(),
                            "dns2": dns2Input.text(),
                            "netUnion": netUnionCombo.currentText,
                            "dhcp": dhcpCombo.currentText,
                            "mtu": mtuInput.text
                        }));
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
            readonly property int osdLabelWidth: ScreenTools.scaleNum(170)

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

                osdSetCheck.checked = s.setTimeTitle;
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

                                Layout.preferredWidth: ScreenTools.scaleNum(220)
                                Layout.preferredHeight: root.ctrlH
                                model: ["yyyy-mm-dd hh:mm:ss", "yyyy/mm/dd hh:mm:ss", "yy-mm-dd hh:mm:ss", "yy/mm/dd hh:mm:ss", "hh:mm:ss dd/mm/yyyy", "hh:mm:ss dd-mm-yyyy", "hh:mm:ss mm/dd/yyyy", "hh:mm:ss mm-dd-yyyy"]
                            }

                            AppCheckBox {
                                id: osdShowWeekCheck

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
                        console.log(qsTr("其它设置-OSD设置保存: ") + JSON.stringify({
                            "setOsd": osdSetCheck.checked,
                            "osdEnable": osdEnableCombo.currentText,
                            "overlayInfo": osdOverlayCombo.currentText,
                            "timePosition": osdTimePosCombo.currentText,
                            "timeFormat": osdTimeFormatCombo.currentText,
                            "showWeek": osdShowWeekCheck.checked,
                            "timeDisplayPosition": osdTimeShowPosCombo.currentText,
                            "titleContent": osdTitleInput.text
                        }));
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
                text: qsTr("该设置页待接入")
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
                                    text: qsTr("最大心跳超时次数")
                                }

                                AppTextField {
                                    id: heartbeatTimeoutInput

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
                        console.log(qsTr("其它设置-28181接入1设置保存: ") + JSON.stringify({
                            "setGb28181": gbSetCheck.checked,
                            "enable": gbEnableCombo.currentText,
                            "localSipPort": localSipPortInput.text,
                            "sipServerId": sipServerIdInput.text,
                            "sipServerDomain": sipServerDomainInput.text,
                            "sipServerIp": sipServerIpInput.text(),
                            "sipServerPort": sipServerPortInput.text,
                            "sipUser": sipUserInput.text,
                            "sipAuthId": sipAuthIdInput.text,
                            "password": passwordInput.text,
                            "confirmPassword": confirmPasswordInput.text,
                            "registerExpire": registerExpireInput.text,
                            "heartbeat": heartbeatInput.text,
                            "heartbeatTimeout": heartbeatTimeoutInput.text,
                            "streamIndex": streamIndexCombo.currentText,
                            "alarmId": alarmIdInput.text
                        }));
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
                                text: qsTr("亮度(0-255)")
                            }

                            AppTextField {
                                id: vcBrightnessInput

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
                                text: qsTr("饱和度(0-255)")
                            }

                            AppTextField {
                                id: vcSaturationInput

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
                                text: qsTr("锐度(0-255)")
                            }

                            AppTextField {
                                id: vcSharpnessInput

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
                                text: qsTr("对比度(0-255)")
                            }

                            AppTextField {
                                id: vcContrastInput

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
                        console.log(qsTr("其它设置-视频采集设置保存: ") + JSON.stringify({
                            "setVideoCapture": vcSetCheck.checked,
                            "brightness": vcBrightnessInput.text,
                            "saturation": vcSaturationInput.text,
                            "sharpness": vcSharpnessInput.text,
                            "contrast": vcContrastInput.text,
                            "whiteBalance": vcWhiteBalanceCombo.currentText,
                            "hFlip": vcHFlipCombo.currentText,
                            "vFlip": vcVFlipCombo.currentText,
                            "wdr": vcWdrCombo.currentText
                        }));
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
            readonly property int veLabelWidth: ScreenTools.scaleNum(150)
            readonly property int veFieldWidth: ScreenTools.scaleNum(180)

            anchors.fill: parent
            spacing: ScreenTools.scaleNum(10)

            AppCheckBox {
                id: veSetCheck

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

                                Layout.preferredWidth: veRoot.veFieldWidth
                                Layout.preferredHeight: root.ctrlH
                                model: [qsTr("H265"), qsTr("H264")]
                            }

                            AppComboBox {
                                id: veSubCodecCombo

                                Layout.preferredWidth: veRoot.veFieldWidth
                                Layout.preferredHeight: root.ctrlH
                                model: [qsTr("H265"), qsTr("H264")]
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

                                Layout.preferredWidth: veRoot.veFieldWidth
                                Layout.preferredHeight: root.ctrlH
                                model: ["2560×1440", "2304×1296", "1920×1080", "1280×960", "1280×720"]
                                currentIndex: 1
                            }

                            AppComboBox {
                                id: veSubResCombo

                                Layout.preferredWidth: veRoot.veFieldWidth
                                Layout.preferredHeight: root.ctrlH
                                model: [qsTr("D1(720×576)"), "800×448", "704×576", "640×480", "640×360", "352×288"]
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

                                Layout.preferredWidth: veRoot.veFieldWidth
                                Layout.preferredHeight: root.ctrlH
                                model: ["VBR", "CBR", "CBVR"]
                            }

                            AppComboBox {
                                id: veSubRateCtlCombo

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
                                text: qsTr("帧间隔(s 1-200)")
                            }

                            AppTextField {
                                id: veMainGopInput

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
                                text: qsTr("比特率(kbps 500-8000)")
                            }

                            AppTextField {
                                id: veMainBitrateInput

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
                                        text: qsTr("BaseProfile")
                                    }

                                    AppComboBox {
                                        id: veBaseProfileCombo

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
                        console.log(qsTr("其它设置-视频编码保存: ") + JSON.stringify({
                            "setVideoEncode": veSetCheck.checked,
                            "mainCodec": veMainCodecCombo.currentText,
                            "mainResolution": veMainResCombo.currentText,
                            "mainRateControl": veMainRateCtlCombo.currentText,
                            "mainGop": veMainGopInput.text,
                            "mainBitrate": veMainBitrateInput.text,
                            "mainFps": veMainFpsCombo.currentText,
                            "subCodec": veSubCodecCombo.currentText,
                            "subResolution": veSubResCombo.currentText,
                            "subRateControl": veSubRateCtlCombo.currentText,
                            "subGop": veSubGopInput.text,
                            "subBitrate": veSubBitrateInput.text,
                            "subFps": veSubFpsCombo.currentText,
                            "baseProfile": veBaseProfileCombo.currentText,
                            "wdrMode": veWdrModeCombo.currentText,
                            "privateData": vePrivateDataCombo.currentText
                        }));
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

                                Layout.preferredWidth: ScreenTools.scaleNum(180)
                                Layout.preferredHeight: root.ctrlH
                                model: [qsTr("G711"), qsTr("AAC")]
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
                        console.log(qsTr("其它设置-音频编码保存: ") + JSON.stringify({
                            "setAudioEncode": aeSetCheck.checked,
                            "enable": aeEnableCombo.currentText,
                            "audioType": aeTypeCombo.currentText,
                            "sampleRate": aeSampleCombo.currentText,
                            "bitrate": aeBitrateInput.text
                        }));
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
                                text: qsTr("采集音量(1-100)")
                            }

                            AppTextField {
                                id: arCaptureInput

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
                                text: qsTr("播放音量(1-100)")
                            }

                            AppTextField {
                                id: arPlayInput

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
                        console.log(qsTr("其它设置-音量配置保存: ") + JSON.stringify({
                            "setAudioReconfig": arSetCheck.checked,
                            "captureVolume": arCaptureInput.text,
                            "playVolume": arPlayInput.text
                        }));
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
                console.log(qsTr("其它设置-移动侦测保存: ") + JSON.stringify({
                    "setMotionDetect": mdPanel.switchChecked,
                    "enable": mdEnableCombo.currentText
                }));
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

                Label {
                    Layout.preferredWidth: root.panelLabelWidth
                    Layout.preferredHeight: root.ctrlH
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignRight
                    text: qsTr("设置移动侦测告警")
                }

                AppComboBox {
                    id: mdEnableCombo

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
                console.log(qsTr("其它设置-声音侦测保存: ") + JSON.stringify({
                    "setAudioDetect": adPanel.switchChecked,
                    "enable": adEnableCombo.currentText
                }));
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

                Label {
                    Layout.preferredWidth: root.panelLabelWidth
                    Layout.preferredHeight: root.ctrlH
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignRight
                    text: qsTr("设置声音侦测告警")
                }

                AppComboBox {
                    id: adEnableCombo

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
                            console.log(qsTr("其它设置-账户管理保存失败: 两次输入的密码不一致"));
                            return ;
                        }
                        root.saveCurrentPanel();
                        console.log(qsTr("其它设置-账户管理保存: ") + JSON.stringify({
                            "modifyAdminPassword": accSetCheck.checked,
                            "newPassword": accNewPwdInput.text
                        }));
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
                        console.log(qsTr("其它设置-定期维护保存: ") + JSON.stringify({
                            "setMaintenance": mtSetCheck.checked,
                            "enable": mtEnableCombo.currentText,
                            "day": mtDayCombo.currentText,
                            "time": mtTimeInput.time
                        }));
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

                                Layout.preferredWidth: ScreenTools.scaleNum(250)
                                Layout.preferredHeight: root.ctrlH
                                model: [qsTr("简体中文"), qsTr("繁体中文"), qsTr("English")]
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
                        console.log(qsTr("其它设置-设备语言保存: ") + JSON.stringify({
                            "setLanguage": langSetCheck.checked,
                            "language": langCombo.currentText
                        }));
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
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("更新方式")
                            }

                            AppComboBox {
                                id: ckModeCombo

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
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("时区")
                            }

                            AppComboBox {
                                id: ckZoneCombo

                                Layout.preferredWidth: ScreenTools.scaleNum(360)
                                Layout.preferredHeight: root.ctrlH
                                model: ["(GMT-12:00)国际日期变更线西", "(GMT-11:00)中途岛，萨摩亚", "(GMT-10:00)夏威夷", "(GMT-09:00)阿拉斯加", "(GMT-08:00)太平洋时间（美国和加拿大）", "(GMT-07:00)山地时间（美国和加拿大）", "(GMT-06:00)中部时间（美国和加拿大），墨西哥城", "(GMT-05:00)东部时间（美国和加拿大），波哥大", "(GMT-04:00)大西洋时间（加拿大），加拉加斯", "(GMT-03:00)巴西利亚，乔治敦", "(GMT-02:00)中大西洋", "(GMT-01:00)亚速尔群岛，佛得角群岛", "(GMT+00:00)都柏林，伦敦，里斯本", "(GMT+01:00)巴黎，柏林，罗马，马德里", "(GMT+02:00)雅典，开罗，赫尔辛基", "(GMT+03:00)莫斯科，圣彼得堡，内罗毕", "(GMT+04:00)巴库，第比利斯，叶里温", "(GMT+05:00)伊斯兰堡，卡拉奇，塔什干", "(GMT+06:00)达卡，阿拉木图", "(GMT+07:00)曼谷，河内，雅加达", "(GMT+08:00)北京，重庆，乌鲁木齐，香港特别行政区", "(GMT+09:00)东京，大阪，首尔", "(GMT+10:00)悉尼，墨尔本，关岛", "(GMT+11:00)所罗门群岛，新喀里多尼亚", "(GMT+12:00)奥克兰，惠灵顿，斐济"]
                                currentIndex: 20
                            }

                        }

                        // ===== 仅 NTP 模式显示 =====
                        RowLayout {
                            visible: ckModeCombo.currentIndex === 1
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("NTP服务器IP")
                            }

                            AppTextField {
                                id: ckNtpIpInput

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
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("NTP端口(1-65535)")
                            }

                            AppTextField {
                                id: ckNtpPortInput

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
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("刷新间隔(60-999999)")
                            }

                            AppTextField {
                                id: ckRefreshInput

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
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("时间")
                            }

                            AppTextField {
                                id: ckTimeInput

                                Layout.preferredWidth: ScreenTools.scaleNum(200)
                                Layout.preferredHeight: root.ctrlH
                                // 默认填充当前电脑本地时间
                                text: Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm:ss")
                            }

                            AppCheckBox {
                                id: ckSetTimeCheck

                                text: qsTr("设置时间")
                                checked: false
                            }

                        }

                        // 启用夏令时
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ScreenTools.scaleNum(8)

                            Label {
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("启用夏令时")
                            }

                            AppComboBox {
                                id: ckDstEnableCombo

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
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("夏令时开始时间")
                            }

                            AppComboBox {
                                id: ckDstStartMonthCombo

                                Layout.preferredWidth: ScreenTools.scaleNum(110)
                                Layout.preferredHeight: root.ctrlH
                                model: ckMonthModel
                            }

                            AppComboBox {
                                id: ckDstStartWeekSeqCombo

                                Layout.preferredWidth: ScreenTools.scaleNum(140)
                                Layout.preferredHeight: root.ctrlH
                                model: ckWeekSeqModel
                                currentIndex: 4
                            }

                            AppComboBox {
                                id: ckDstStartWeekDayCombo

                                Layout.preferredWidth: ScreenTools.scaleNum(100)
                                Layout.preferredHeight: root.ctrlH
                                model: ckWeekDayModel
                                currentIndex: 6
                            }

                            AppTimePicker {
                                id: ckDstStartTimePicker

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
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("夏令时结束时间")
                            }

                            AppComboBox {
                                id: ckDstEndMonthCombo

                                Layout.preferredWidth: ScreenTools.scaleNum(110)
                                Layout.preferredHeight: root.ctrlH
                                model: ckMonthModel
                            }

                            AppComboBox {
                                id: ckDstEndWeekSeqCombo

                                Layout.preferredWidth: ScreenTools.scaleNum(140)
                                Layout.preferredHeight: root.ctrlH
                                model: ckWeekSeqModel
                            }

                            AppComboBox {
                                id: ckDstEndWeekDayCombo

                                Layout.preferredWidth: ScreenTools.scaleNum(100)
                                Layout.preferredHeight: root.ctrlH
                                model: ckWeekDayModel
                                currentIndex: 6
                            }

                            AppTimePicker {
                                id: ckDstEndTimePicker

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
                                Layout.preferredWidth: root.panelLabelWidth
                                Layout.preferredHeight: root.ctrlH
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: qsTr("夏令时偏移时间")
                            }

                            AppComboBox {
                                id: ckDstOffsetCombo

                                Layout.preferredWidth: ScreenTools.scaleNum(150)
                                Layout.preferredHeight: root.ctrlH
                                model: [qsTr("30分钟"), qsTr("60分钟"), qsTr("90分钟"), qsTr("120分钟")]
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
                        console.log(qsTr("其它设置-时钟设置保存: ") + JSON.stringify({
                            "setClock": ckSetCheck.checked,
                            "mode": ckModeCombo.currentText,
                            "timeZone": ckZoneCombo.currentText,
                            "ntpServerIp": ckNtpIpInput.text,
                            "ntpPort": ckNtpPortInput.text,
                            "refreshInterval": ckRefreshInput.text,
                            "manualTime": ckTimeInput.text,
                            "setTime": ckSetTimeCheck.checked,
                            "dstEnable": ckDstEnableCombo.currentText,
                            "dstStart": {
                                "month": ckDstStartMonthCombo.currentText,
                                "weekSeq": ckDstStartWeekSeqCombo.currentText,
                                "weekDay": ckDstStartWeekDayCombo.currentText,
                                "time": ckDstStartTimePicker.time
                            },
                            "dstEnd": {
                                "month": ckDstEndMonthCombo.currentText,
                                "weekSeq": ckDstEndWeekSeqCombo.currentText,
                                "weekDay": ckDstEndWeekDayCombo.currentText,
                                "time": ckDstEndTimePicker.time
                            },
                            "dstOffset": ckDstOffsetCombo.currentText
                        }));
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
    // （AppTextField 基于 TextArea，不支持 echoMode 掩码，密码输入用 TextField 实现）
    component PwdInput: AppPasswordField {
        Layout.minimumHeight: root.ctrlH
        Layout.preferredHeight: root.ctrlH
    }

    // 屏蔽 Dialog 默认标题栏，改用统一封装的标题栏（含关闭按钮）
    header: AppDialogHeader {
        title: root.title
        onClosed: root.reject()

        // 保存成功提示弹窗：放在标题栏容器内，避免进入内容区的布局被 RowLayout 排版
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
