import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import IPCam.Public 1.0

// 统一密码输入框样式（单行，支持密文显示）：
// 1) 默认以圆点掩码显示；需要明文时可设 echoMode: TextInput.Normal
// 2) 外观与 AppTextField 完全一致：白底、1px 边框、4px 圆角，聚焦时边框与主色一致
// 3) 放在布局中时最小高度 30
TextField {
    id: control

    Layout.minimumHeight: ScreenTools.scaleNum(30)
    Layout.preferredHeight: ScreenTools.scaleNum(30)
    topPadding: 0
    bottomPadding: 0
    leftPadding: ScreenTools.scaleNum(8)
    rightPadding: ScreenTools.scaleNum(8)
    horizontalAlignment: Text.AlignLeft
    verticalAlignment: Text.AlignVCenter
    selectByMouse: true
    echoMode: TextInput.Password
    font.family: "Microsoft YaHei"
    font.pointSize: ScreenTools.scaleNum(10, true)
    background: Rectangle {
        radius: ScreenTools.scaleNum(4)
        color: control.enabled ? "white" : "#f0f0f0"
        border.width: 1
        border.color: control.activeFocus ? "#2f6fed" : "#767676"
    }
}
