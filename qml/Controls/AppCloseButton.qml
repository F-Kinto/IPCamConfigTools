import QtQuick 2.15
import QtQuick.Layouts 1.15
import IPCam.Public 1.0

// 通用关闭按钮：弹窗标题栏右上角的 ✕
// 1) 固定 32x32、无边框、默认透明，鼠标悬浮/按下时红色底
// 2) 只负责外观与尺寸，点击行为由调用方决定（onClicked: root.reject() 等），不影响扩展性
// 用法：AppCloseButton { onClicked: root.reject() }
AppButton {
    id: control

    Layout.preferredWidth: ScreenTools.scaleNum(32)
    Layout.minimumWidth: ScreenTools.scaleNum(32)
    Layout.maximumWidth: ScreenTools.scaleNum(32)
    Layout.preferredHeight: ScreenTools.scaleNum(32)
    Layout.minimumHeight: ScreenTools.scaleNum(32)
    Layout.maximumHeight: ScreenTools.scaleNum(32)
    showBorder: false
    flat: true
    font.bold: true
    text: "✕"
    font.pointSize: ScreenTools.scaleNum(14, true)
    background: Rectangle {
        radius: ScreenTools.scaleNum(4)
        color: (control.hovered || control.down) ? "#FF4A4A" : "transparent"
    }
}
