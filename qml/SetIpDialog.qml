import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import IPCam.Public 1.0
// 项目内封装的通用控件目录
import "Controls"

// 设定IP弹窗：网卡下拉框 + IP/子网掩码/网关（4 段式输入）+ 确定/取消
// 选中网卡后自动带出该网卡的 IP / 子网掩码 / 网关，可手动修改后确定
Dialog {
    id: root

    // 统一控件高度
    readonly property int ctrlH: ScreenTools.scaleNum(28)
    // 左侧标签列宽（保证各行的输入框左对齐）
    readonly property int labelWidth: ScreenTools.scaleNum(80)
    // 网卡信息列表（ScreenTools::getNetworkInterfaces() 的返回值）
    property var nicList: []

    function refreshNics() {
        nicList = ScreenTools.getNetworkInterfaces();
    }

    function currentNic() {
        if (nicCombo.currentIndex < 0 || nicCombo.currentIndex >= nicList.length)
            return null;

        return nicList[nicCombo.currentIndex];
    }

    // 把选中网卡的 IP / 掩码 / 网关填入输入框
    function applyNic() {
        var nic = currentNic();
        if (!nic) {
            ipInput.value = "";
            maskInput.value = "";
            gwInput.value = "0.0.0.0";
            return ;
        }
        var ipv4 = nic["ipv4"] || [];
        // 网关获取不到时显示默认值
        var gw = nic["gateway"] || "";
        ipInput.value = ipv4.length > 0 ? ipv4[0] : "";
        maskInput.value = nic["netmask"] || "";
        gwInput.value = gw.length > 0 ? gw : "0.0.0.0";
    }

    width: ScreenTools.scaleNum(460)
    height: ScreenTools.scaleNum(320)
    modal: true
    dim: true
    closePolicy: Popup.CloseOnEscape
    clip: true
    anchors.centerIn: Overlay.overlay
    title: qsTr("设置IP")
    // 每次打开时刷新网卡列表并带出当前网卡的地址
    onAboutToShow: {
        refreshNics();
        applyNic();
    }
    padding: ScreenTools.scaleNum(16)
    // 高度由内容区的隐式高度决定，避免底部按钮被压缩/截断
    contentHeight: contentLayout.implicitHeight

    background: Rectangle {
        radius: ScreenTools.scaleNum(4)
        color: "#FFFFFF"
        border.width: 1
        border.color: "#DCDCDC"
    }

    // 屏蔽 Dialog 默认标题栏，改用统一封装的标题栏（含关闭按钮）
    header: AppDialogHeader {
        title: root.title
        onClosed: root.reject()
    }

    footer: Item {
        height: 0
    }
    // 四周外边距统一 16

    // 4 段式 IP 输入框（如 192.168.5.205），交互细节见 AppIpInput.qml
    component IpInput: AppIpInput {
        ctrlHeight: root.ctrlH
    }

    contentItem: ColumnLayout {
        id: contentLayout

        // 不使用 anchors.fill：高度交给隐式高度，宽度铺满可视内容区
        width: root.availableWidth
        spacing: ScreenTools.scaleNum(12)

        // ===== 顶部：修改IP起始地址 / 批量修改设定IP =====
        RowLayout {
            Layout.fillWidth: true
            spacing: ScreenTools.scaleNum(24)

            AppCheckBox {
                id: startAddrCheck

                text: qsTr("修改IP起始地址")
                checked: false
                // 与“批量修改设定IP”互斥：勾选本项时取消另一项（两者可同时不勾选）
                onCheckedChanged: {
                    if (checked) {
                        batchCheck.checked = false;
                        console.log(qsTr("设定IP-勾选修改IP起始地址, 已取消批量修改设定IP"));
                    }
                }
            }

            Item {
                Layout.fillWidth: true
            }

            AppCheckBox {
                id: batchCheck

                text: qsTr("批量修改设定IP")
                checked: false
                visible: false
                // 与“修改IP起始地址”互斥：勾选本项时取消另一项（两者可同时不勾选）
                onCheckedChanged: {
                    if (checked) {
                        startAddrCheck.checked = false;
                        console.log(qsTr("设定IP-勾选批量修改设定IP, 已取消修改IP起始地址"));
                    }
                }
            }

        }

        // ===== 网卡 =====
        RowLayout {
            Layout.fillWidth: true
            spacing: ScreenTools.scaleNum(8)

            Label {
                Layout.preferredWidth: root.labelWidth
                Layout.preferredHeight: root.ctrlH
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignLeft
                text: qsTr("网卡")
            }

            AppComboBox {
                id: nicCombo

                Layout.fillWidth: true
                Layout.preferredHeight: root.ctrlH
                textRole: "displayName"
                model: root.nicList
                displayText: currentIndex >= 0 ? currentText : qsTr("未检测到网卡")
                onCurrentIndexChanged: root.applyNic()
            }

        }

        // ===== IP =====
        RowLayout {
            Layout.fillWidth: true
            spacing: ScreenTools.scaleNum(8)

            Label {
                Layout.preferredWidth: root.labelWidth
                Layout.preferredHeight: root.ctrlH
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignLeft
                text: qsTr("IP")
            }

            IpInput {
                id: ipInput

                Layout.fillWidth: true
            }

        }

        // ===== 子网掩码 =====
        RowLayout {
            Layout.fillWidth: true
            spacing: ScreenTools.scaleNum(8)

            Label {
                Layout.preferredWidth: root.labelWidth
                Layout.preferredHeight: root.ctrlH
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignLeft
                text: qsTr("子网掩码")
            }

            IpInput {
                id: maskInput

                Layout.fillWidth: true
            }

        }

        // ===== 网关 =====
        RowLayout {
            Layout.fillWidth: true
            spacing: ScreenTools.scaleNum(8)

            Label {
                Layout.preferredWidth: root.labelWidth
                Layout.preferredHeight: root.ctrlH
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignLeft
                text: qsTr("网关")
            }

            IpInput {
                id: gwInput

                Layout.fillWidth: true
            }

        }

        // ===== 底部：确定 / 取消 =====
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: ScreenTools.scaleNum(36)
            // 保证这一行不会被布局压缩掉
            Layout.minimumHeight: ScreenTools.scaleNum(36)
            Layout.topMargin: ScreenTools.scaleNum(4)
            spacing: ScreenTools.scaleNum(16)

            Item {
                Layout.fillWidth: true
            }

            AppButton {
                Layout.preferredHeight: root.ctrlH
                highlighted: true
                text: qsTr("确定")
                onClicked: root.accept()
            }

            AppButton {
                Layout.preferredHeight: root.ctrlH
                text: qsTr("取消")
                onClicked: root.reject()
            }

            Item {
                Layout.fillWidth: true
            }

        }

    }

}
