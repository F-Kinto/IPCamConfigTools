import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import IPCam.Public 1.0

// 用法：
//   AppContentDialog {
//       id: dialog
//       title: qsTr("设置IP")            // 复用 Dialog 自带 title
//       okText: qsTr("确定")             // 主按钮（高亮，靠左）
//       cancelText: qsTr("取消")         // 空串时隐藏取消按钮（仅剩主按钮）
//       onOkClicked: { ... }             // 主按钮点击（不自动关，调用方择机 accept()）
//       onCancelClicked: dialog.reject()
//
//       RowLayout { ... }                // 中间内容区：子项直接声明在控件体内
//   }

Dialog {
    id: root

    // 主按钮（高亮）文本，位于取消按钮左侧
    property string okText: qsTr("确定")
    // 取消按钮文本；置空串时隐藏取消按钮（单按钮弹窗）
    property string cancelText: qsTr("取消")

    // 主按钮被点击：不自动关弹窗，由调用方决定 accept() 时机
    // （如设定IP需先异步探测占用，成功后才 accept）
    signal okClicked()
    // 取消按钮被点击：默认不动作，调用方自行 reject()
    signal cancelClicked()

    // 内容区条目：调用方声明在控件体内的子项自动注入这里，
    default property alias contentItems: formContent.data

    modal: true
    dim: true
    closePolicy: Popup.CloseOnEscape
    clip: true
    anchors.centerIn: Overlay.overlay
    // 四周外边距统一 16
    padding: ScreenTools.scaleNum(16)

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

    contentItem: Item {
        implicitHeight: contentLayout.implicitHeight
        implicitWidth: contentLayout.implicitWidth

        ColumnLayout {
            id: contentLayout

            anchors.fill: parent
            spacing: ScreenTools.scaleNum(12)

            // ===== 中间内容区（调用方经 default 属性注入）=====
            ColumnLayout {
                id: formContent
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: ScreenTools.scaleNum(12)
            }

            // ===== 底部：主按钮 / 取消（整体居右，主按钮在前）=====
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
                    Layout.preferredHeight: ScreenTools.scaleNum(28)
                    highlighted: true
                    text: root.okText
                    onClicked: root.okClicked()
                }

                AppButton {
                    Layout.preferredHeight: ScreenTools.scaleNum(28)
                    visible: root.cancelText !== ""
                    text: root.cancelText
                    onClicked: root.cancelClicked()
                }

                Item {
                    Layout.fillWidth: true
                }

            }

        }

    }
}
