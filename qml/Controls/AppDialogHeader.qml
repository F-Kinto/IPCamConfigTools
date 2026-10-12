// 弹窗自绘标题栏：屏蔽 Dialog 默认 header 后统一使用，避免每个弹窗各写一遍
// 1) 左侧标题（微软雅黑 12pt 加粗），右侧为统一的关闭按钮 AppCloseButton
// 2) 只负责外观与“关闭被点击”这件事，不替调用方决定关闭行为，不影响扩展性

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import IPCam.Public 1.0

// 用法（弹窗内）：
//     header: AppDialogHeader {
//         title: root.title
//         onClosed: root.reject()      // 也可 root.close() / 先校验再关
//     }
Item {
    id: control

    // 标题文本
    property string title: ""
    // 是否显示右侧关闭按钮（确认类弹窗可置 false）
    property bool showClose: true
    // 标题栏高度（系统配置/设定IP/OSD 为 44，消息框为 40）
    property int barHeight: ScreenTools.scaleNum(44)
    // 背景色与圆角（右上角/左上角与弹窗主体一致）
    property color barColor: "#F5F7FA"
    property real barRadius: ScreenTools.scaleNum(4)

    // 关闭按钮被点击；由调用方决定具体行为
    signal closed()

    implicitHeight: control.barHeight
    height: control.barHeight

    Rectangle {
        anchors.fill: parent
        color: control.barColor
        radius: control.barRadius
        border.width: 0
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: ScreenTools.scaleNum(16)
        anchors.rightMargin: ScreenTools.scaleNum(4)
        spacing: ScreenTools.scaleNum(8)

        Label {
            Layout.fillWidth: true
            Layout.preferredHeight: control.barHeight
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignLeft
            font.family: "Microsoft YaHei"
            font.bold: true
            font.pointSize: ScreenTools.scaleNum(12, true)
            color: "#000000"
            text: control.title
        }

        AppCloseButton {
            visible: control.showClose
            onClicked: control.closed()
        }

    }

}
