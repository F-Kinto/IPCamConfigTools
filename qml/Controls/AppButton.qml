import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import IPCam.Public 1.0

// 统一按钮样式：
// 1) 文本水平+垂直居中
// 2) 宽度不足时按字符自动换行（Text.WrapAnywhere），不做省略号截断
// 3) 高度随行数自动增高，最小为统一控件高度 30
// 4) 浅灰边框 + 4px 圆角，hover/按下/聚焦时边框与主色一致（蓝色）
Button {
    id: control

    // 是否显示边框（关闭按钮等场景可设为 false）
    property bool showBorder: true

    hoverEnabled: true

    // 放在布局中时：最小高度 30（文本换行后自动增高），最小宽度 80
    Layout.minimumHeight: ScreenTools.scaleNum(30)
    Layout.minimumWidth: ScreenTools.scaleNum(80)
    // 不在布局中时同样保证最小宽度 80
    implicitWidth: Math.max(ScreenTools.scaleNum(80), btnLabel.implicitWidth + control.leftPadding + control.rightPadding)
    Layout.preferredHeight: Math.max(ScreenTools.scaleNum(30), btnLabel.implicitHeight + control.topPadding + control.bottomPadding)
    topPadding: ScreenTools.scaleNum(4)
    bottomPadding: ScreenTools.scaleNum(4)
    leftPadding: ScreenTools.scaleNum(6)
    rightPadding: ScreenTools.scaleNum(6)
    font.family: "Microsoft YaHei"
    font.pointSize: ScreenTools.scaleNum(10, true)

    contentItem: Text {
        id: btnLabel

        text: control.text
        font: control.font
        // 高亮按钮底色为蓝色，文字用白色；普通按钮用黑色
        color: !control.enabled ? "#a0a0a0" : (control.highlighted ? "#FFFFFF" : "#000000")
        // 显示不全时按字符换行，而不是省略号截断
        wrapMode: Text.WrapAnywhere
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        // 换行的情况极少，出现时行距收紧一点，避免按钮过高
        lineHeight: 1.15
    }

    background: Rectangle {
        radius: ScreenTools.scaleNum(4)
        // 高亮按钮保持蓝底；普通按钮白底，hover/按下时浅蓝底
        color: control.highlighted ? (control.down ? "#003CB8" : "#004EEB") : (control.down ? "#DCE7FB" : (control.hovered ? "#F2F6FE" : "#FFFFFF"))
        border.width: control.showBorder ? 1 : 0
        // 浅灰边框；hover / 按下 / 键盘聚焦时变为蓝色
        border.color: (control.hovered || control.down) ? "#004EEB" : "#C4C8D0"
    }
}
