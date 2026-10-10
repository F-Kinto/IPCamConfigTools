import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import IPCam.Public 1.0

// 统一文本框样式（多行文本域，兼容单行输入用法）：
// 1) 文本左对齐
// 2) 宽度不足时按字符自动换行（Text.WrapAnywhere），完整显示内容
// 3) 高度随行数自动增高，最小为统一控件高度 30
TextArea {
    id: control

    // 放在布局中时：最小高度 30，内容换行后自动增高
    Layout.minimumHeight: ScreenTools.scaleNum(30)
    Layout.preferredHeight: Math.max(ScreenTools.scaleNum(30), control.contentHeight + control.topPadding + control.bottomPadding)
    topPadding: ScreenTools.scaleNum(5)
    bottomPadding: ScreenTools.scaleNum(5)
    leftPadding: ScreenTools.scaleNum(8)
    rightPadding: ScreenTools.scaleNum(8)
    // 文本左对齐（超出一行时垂直居中，单行时视觉与 TextField 一致）
    horizontalAlignment: Text.AlignLeft
    verticalAlignment: Text.AlignVCenter
    // 显示不全时按字符换行
    wrapMode: Text.WrapAnywhere
    selectByMouse: true
    font.family: "Microsoft YaHei"
    font.pointSize: ScreenTools.scaleNum(10, true)
    hoverEnabled: true
    background: Rectangle {
        radius: ScreenTools.scaleNum(4)
        color: control.enabled ? "white" : "#f0f0f0"
        border.width: 1
        border.color: (control.activeFocus || control.hovered) ? "#2f6fed" : "#767676"
    }
}
