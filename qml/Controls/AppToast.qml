import QtQuick 2.15
import QtQuick.Controls 2.15
import IPCam.Public 1.0

// 轻提示 toast：非模态、窗口顶部居中、到时自动消失。
// 用法与 AppMessageBox 同款（id + show 函数）：在 main.qml 声明一次，需要处调用 show(text)。
// 与 AppMessageBox 的分工：需要用户确认/知晓的用弹窗，纯状态告知用 toast。
Popup {
    id: toast

    // 提示文案
    property string message: ""
    // 停留时长（毫秒），超时自动收起
    property int duration: 2500

    // 显示提示并（重）启动自动收起计时
    function show(text) {
        toast.message = text;
        toast.open();
        dismissTimer.restart();
    }

    // 顶部居中（Popup 声明在 ApplicationWindow 下，parent 即为窗口 overlay）
    x: (parent.width - width) / 2
    y: ScreenTools.scaleNum(24)
    height: ScreenTools.scaleNum(36)
    padding: 0
    modal: false
    // 只由计时器收起，点击界面不提前关闭
    closePolicy: Popup.NoAutoClose

    background: Rectangle {
        radius: height / 2
        color: "#E6203030"
    }

    contentItem: Label {
        id: toastLabel

        leftPadding: ScreenTools.scaleNum(24)
        rightPadding: ScreenTools.scaleNum(24)
        verticalAlignment: Text.AlignVCenter
        text: toast.message
        color: "#FFFFFF"
        font.family: "Microsoft YaHei"
        font.pointSize: ScreenTools.scaleNum(10, true)
    }

    // 宽度随文案自适应
    width: toastLabel.implicitWidth + toastLabel.leftPadding + toastLabel.rightPadding

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
    }

    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 150 }
    }

    // 到时自动收起
    Timer {
        id: dismissTimer

        interval: toast.duration
        onTriggered: toast.close()
    }
}
