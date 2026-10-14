import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import IPCam.Public 1.0

// 用法：
//   AppMessageBox { id: tipBox }
//   tipBox.show(qsTr("温馨提示"), qsTr("保存成功"))   // twoButtons=false：仅确定按钮
//   tipBox.twoButtons = true                         // 显示取消按钮，变两按钮确认框
//   onAccepted: ...   onRejected: ...                // 确定=accept，取消/X/ESC=reject
// 按钮文本经 okText / cancelButtonText 自定义；
// 取消按钮显隐由 twoButtons 驱动（false 时自动隐藏，勿直接赋 cancelText）。
AppContentDialog {
    id: root

    // 窗口标题
    property string tipTitle: qsTr("温馨提示")
    // 提示内容
    property string message: qsTr("保存成功")
    // 取消按钮文本（twoButtons 为 true 时显示）
    property string cancelButtonText: qsTr("取消")
    // 中间提示图片，默认为空（不显示）
    property url iconSource: ""
    // 图标尺寸（默认 32x32，图标为空时不占位）
    property int iconSize: ScreenTools.scaleNum(32)
    // 显示两个按钮（确定|取消）或者一个按钮（确定）
    property bool twoButtons: false

    width: ScreenTools.scaleNum(400)
    // 高度：内容不足时撑到最小 220，超出时随内容自适应
    height: Math.max(implicitHeight, ScreenTools.scaleNum(200))
    title: root.tipTitle
    cancelText: root.twoButtons ? root.cancelButtonText : ""

    // 主按钮（确定）点击 = 接受
    onOkClicked: root.accept()
    // 取消按钮点击 = 拒绝
    onCancelClicked: root.reject()

    // 便捷接口：设置标题/内容/图标后直接打开（按钮布局由 twoButtons 决定）
    function show(title, text, icon) {
        if (title !== undefined)
            root.tipTitle = title;

        if (text !== undefined)
            root.message = text;

        if (icon !== undefined)
            root.iconSource = icon;

        root.open();
    }

    // ===== 中间内容区：提示图片 + 提示内容（10pt、自动换行、水平居中）=====
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
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
            Layout.alignment: Qt.AlignVCenter
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            font.family: "Microsoft YaHei"
            font.bold: false
            font.pointSize: ScreenTools.scaleNum(10, true)
            Layout.fillHeight: true
            color: "#333333"
            wrapMode: Text.WrapAnywhere
            text: root.message
        }

    }

}
