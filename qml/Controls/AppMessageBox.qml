import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import IPCam.Public 1.0

// 通用提示弹窗：400x220，圆角 4px
// 布局（从上往下，四周外边距统一 16）：
//   1) 标题 + 关闭按钮（高 48，标题加粗 12pt）
//   2) 提示图片 + 提示内容（自适应剩余高度，内容 10pt、自动换行）
//   3) 取消 + 确定（高 36，10pt）
// 用法：
//   AppMessageBox { id: tipBox }
//   tipBox.showTip(qsTr("保存成功"))            // 仅改提示内容
//   tipBox.show(qsTr("警告"), qsTr("确定删除？")) // 改标题+内容
//   onAccepted: ...   onRejected: ...
Dialog {
    id: root

    // 窗口标题
    property string tipTitle: qsTr("温馨提示")
    // 提示内容
    property string message: qsTr("保存成功")
    // 底部按钮文本
    property string cancelText: qsTr("取消")
    property string okText: qsTr("确定")
    // 中间提示图片，默认为空（不显示）
    property url iconSource: ""
    // 图标尺寸（默认 32x32，图标为空时不占位）
    property int iconSize: ScreenTools.scaleNum(32)
    // 显示两个按钮或者一个按钮
    property bool twoButtons: false

    // 便捷接口：设置标题/内容/图标后直接打开
    function show(title, text, icon) {
        if (title !== undefined)
            root.tipTitle = title;

        if (text !== undefined)
            root.message = text;

        if (icon !== undefined)
            root.iconSource = icon;

        root.open();
    }

    width: ScreenTools.scaleNum(400)
    height: ScreenTools.scaleNum(220)
    modal: true
    dim: true
    closePolicy: Popup.CloseOnEscape
    // 圆角 4px，并裁掉超出圆角的子项
    clip: true
    anchors.centerIn: Overlay.overlay
    padding: 0
    topPadding: 0
    bottomPadding: 0
    leftPadding: 0
    rightPadding: 0

    background: Rectangle {
        radius: ScreenTools.scaleNum(4)
        color: "#FFFFFF"
        border.width: 1
        border.color: "#DCDCDC"
    }

    // 屏蔽 Dialog 自带的默认标题栏/按钮栏，全部由 contentItem 统一布局
    header: Item {
        height: 0
    }

    footer: Item {
        height: 0
    }

    contentItem: ColumnLayout {
        anchors.fill: parent
        anchors.bottomMargin: ScreenTools.scaleNum(16)

        // ===== 1) 标题 + 关闭按钮：与其它弹窗共用同一个标题栏控件 =====
        AppDialogHeader {
            Layout.fillWidth: true
            barHeight: ScreenTools.scaleNum(40)
            title: root.tipTitle
            onClosed: root.reject()
        }

        // ===== 2) 提示图片 + 提示内容（高度自适应）=====
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: ScreenTools.scaleNum(16)
            Layout.rightMargin: ScreenTools.scaleNum(16)
            spacing: ScreenTools.scaleNum(12)

            Image {
                Layout.preferredWidth: root.iconSource.toString() === "" ? 0 : root.iconSize
                Layout.preferredHeight: root.iconSize
                Layout.alignment: Qt.AlignVCenter
                visible: root.iconSource.toString() !== ""
                source: root.iconSource
                fillMode: Image.PreserveAspectFit
            }

            Label {
                Layout.fillWidth: true
                Layout.fillHeight: true
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                font.family: "Microsoft YaHei"
                font.bold: false
                font.pointSize: ScreenTools.scaleNum(12, true)
                color: "#333333"
                wrapMode: Text.WrapAnywhere
                text: root.message
            }

        }

        // ===== 3) 取消 + 确定（高度 36，右对齐）=====
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: ScreenTools.scaleNum(36)
            spacing: ScreenTools.scaleNum(16)

            Item {
                Layout.fillWidth: true
            }

            AppButton {
                Layout.preferredHeight: ScreenTools.scaleNum(36)
                font.bold: false
                text: root.cancelText
                onClicked: root.reject()
                visible: twoButtons
            }

            AppButton {
                Layout.preferredHeight: ScreenTools.scaleNum(36)
                highlighted: true
                font.bold: false
                text: root.okText
                onClicked: root.accept()
            }

            Item {
                Layout.fillWidth: true
            }

        }

    }

}
