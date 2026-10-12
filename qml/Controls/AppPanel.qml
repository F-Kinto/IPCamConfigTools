// 通用参数面板骨架（整合各设置页重复的三段式结构）：
//   1) 顶部“设置XXX”开关（勾选状态由调用方双向同步，见 switchChecked / switchToggled）
//   2) 中部浅色边框 + 可滚动的参数区（调用方直接把内容写在 AppPanel 内部即可）
//   3) 底部“保存”按钮（点击只发 saveClicked 信号，具体保存/日志由调用方决定）
// 用法：
//   AppPanel {
//       id: panel
//       switchText: qsTr("设置移动侦测告警")
//       Binding { target: panel; property: "switchChecked"; value: root.isChecked("motionDetect") }
//       onSwitchToggled: root.setChecked("motionDetect", checked)
//       onSaveClicked: { root.saveCurrentPanel(); console.log(...) }

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import IPCam.Public 1.0

//       // 以下内容进入中部参数区
//       RowLayout { ... }
//   }
ColumnLayout {
    id: panel

    // 顶部开关文案（为空时不显示开关）
    property string switchText: ""
    // 顶部开关勾选状态：调用方用 Binding 写入，用户点击时通过 switchToggled 回传
    property bool switchChecked: false
    // 底部保存按钮文案
    property string saveText: qsTr("保存")
    // 统一控件高度（各弹窗可覆盖）
    property int ctrlH: ScreenTools.scaleNum(28)
    // 中部参数区内容：写在 AppPanel 内部的子项自动进到这里
    default property alias content: contentColumn.data

    // 用户点击顶部开关（checked 为最新状态）
    signal switchToggled(bool checked)
    // 点击底部保存按钮
    signal saveClicked()

    anchors.fill: parent
    spacing: ScreenTools.scaleNum(10)

    // ===== 1) 顶部开关 =====
    AppCheckBox {
        id: setCheck

        visible: panel.switchText !== ""
        text: panel.switchText
        onCheckedChanged: {
            panel.switchChecked = checked;
            panel.switchToggled(checked);
        }
    }

    // 用 Binding 而不是直接赋值：用户点击直接改 checked 后，外部状态变化仍能同步回来
    Binding {
        target: setCheck
        property: "checked"
        value: panel.switchChecked
    }

    // ===== 2) 中部：可设置项区域（浅色边框框起来） =====
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: "transparent"
        border.width: 1
        border.color: "#DCDCDC"
        radius: ScreenTools.scaleNum(4)
        clip: true

        ScrollView {
            id: fieldScroll

            anchors.fill: parent
            anchors.margins: ScreenTools.scaleNum(10)
            clip: true
            background: null

            ColumnLayout {
                id: contentColumn

                width: fieldScroll.availableWidth
                spacing: ScreenTools.scaleNum(10)
            }

        }

    }

    // ===== 3) 底部：保存按钮 =====
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: ScreenTools.scaleNum(14)
        spacing: ScreenTools.scaleNum(8)

        Item {
            Layout.fillWidth: true
        }

        AppButton {
            Layout.preferredHeight: panel.ctrlH
            highlighted: true
            text: panel.saveText
            onClicked: panel.saveClicked()
        }

    }

}
