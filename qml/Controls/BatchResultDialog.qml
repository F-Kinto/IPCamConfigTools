import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import IPCam.Public 1.0

// 用法：
//   BatchResultDialog {
//       id: dialog
//       rows: panel.batchRows   // 与进度遮罩共用数据
//   }
//   ... 全部完成后：dialog.open()
AppContentDialog {
    id: root

    // 每设备一块：[{header, items: [{name, ok}]}]
    property var rows: []

    width: ScreenTools.scaleNum(440)
    height: ScreenTools.scaleNum(420)
    title: qsTr("设置结果详情")
    okText: qsTr("确定")
    cancelText: ""
    onOkClicked: root.accept()

    // 可滚动的结果列表
    ScrollView {
        id: scrollView
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true

        // 内容宽度绑定滚动区可视宽度：文本不折行也不被横向拉伸
        ColumnLayout {
            width: scrollView.availableWidth
            spacing: ScreenTools.scaleNum(12)

            Repeater {
                model: root.rows

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: ScreenTools.scaleNum(2)

                    Label {
                        Layout.fillWidth: true
                        text: modelData.header
                        font.family: "Microsoft YaHei"
                        font.pointSize: ScreenTools.scaleNum(10, true)
                        font.bold: true
                        color: "#333333"
                    }

                    Repeater {
                        model: modelData.items

                        Label {
                            Layout.fillWidth: true
                            Layout.leftMargin: ScreenTools.scaleNum(16)
                            text: "%1: %2".arg(modelData.name).arg(modelData.ok ? qsTr("成功") : qsTr("失败(已跳过)"))
                            font.family: "Microsoft YaHei"
                            font.pointSize: ScreenTools.scaleNum(10, true)
                            color: modelData.ok ? "#2E7D32" : "#C62828"
                        }

                    }

                }

            }

        }

    }

}
