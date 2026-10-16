import QtQuick 2.15
import QtQuick.Controls 2.15
import IPCam.Public 1.0

// 用法：
//   BatchProgressMask {
//       anchors.fill: parent
//       z: 100                    // 盖住全界面（含按钮）
//       busy: panel.batchRunning  // true = 显示遮罩并开始转圈
//       rows: panel.batchRows     // [{header, status, ...}]
//   }
Item {
    id: root

    // 是否处于下发状态：控制遮罩显隐与转圈启停
    property bool busy: false
    // 每设备进度块：[{header, status, ...}]（与结果详情弹窗共用 CommandPanel.batchRows）
    property var rows: []

    visible: root.busy

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.5
    }

    // 吞掉鼠标事件：防下发期间误点底层按钮
    MouseArea {
        anchors.fill: parent
    }

    Rectangle {
        anchors.centerIn: parent
        width: ScreenTools.scaleNum(420)
        height: contentCol.implicitHeight + ScreenTools.scaleNum(36) + ScreenTools.scaleNum(36)
        radius: ScreenTools.scaleNum(6)
        color: "#FFFFFF"

        Column {
            id: contentCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: ScreenTools.scaleNum(24)
            anchors.rightMargin: ScreenTools.scaleNum(24)
            anchors.topMargin: ScreenTools.scaleNum(36)
            spacing: ScreenTools.scaleNum(14)

            // 转圈：下发进行中（文本为空只显示转圈）
            AppSpinner {
                anchors.horizontalCenter: parent.horizontalCenter
                running: root.busy
                text: ""
            }

            // 每设备一块：标识行（UID[ip]:）+ 缩进状态行（正在设置XX.../设置XX成功/...）
            Repeater {
                model: root.rows

                Column {
                    spacing: ScreenTools.scaleNum(4)

                    Label {
                        text: modelData.header
                        font.family: "Microsoft YaHei"
                        font.pointSize: ScreenTools.scaleNum(10, true)
                        font.bold: true
                        color: "#333333"
                    }

                    Label {
                        x: ScreenTools.scaleNum(16)
                        text: modelData.status
                        font.family: "Microsoft YaHei"
                        font.pointSize: ScreenTools.scaleNum(10, true)
                        color: "#666666"
                    }

                }

            }

        }

    }

}
