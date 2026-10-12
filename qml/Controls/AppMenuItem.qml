// 通用右键菜单项：与 AppContextMenu 配套使用。
// 样式：高 32px、只显示文本（无图标）、悬浮时浅蓝底 + 蓝字。

import QtQuick 2.15
import QtQuick.Controls 2.15
import IPCam.Public 1.0

// 说明：样式必须放在“菜单项类型”里，不能只放在 AppContextMenu 的 delegate 上——
// QtQuick.Controls 的 Menu.delegate 只对 addItem()/Instantiator 创建的项生效，
// 内联声明的菜单项不会走 delegate（实测：内联项会退回默认样式 #f6f6f6 / #26282a）。
// 所以这里把样式固化成类型，内联声明时直接写 AppMenuItem { text: ...; onTriggered: ... }。
MenuItem {
    id: control

    height: ScreenTools.scaleNum(32)
    leftPadding: ScreenTools.scaleNum(12)
    rightPadding: ScreenTools.scaleNum(12)
    // 字体设在控件上：向下传递给 contentItem，不受宿主窗口字体影响
    font.family: "Microsoft YaHei"
    font.pointSize: ScreenTools.scaleNum(10, true)

    background: Rectangle {
        radius: ScreenTools.scaleNum(2)
        color: control.highlighted ? "#EAF3FF" : "transparent"
    }

    // 只保留文本，去掉图标区
    contentItem: Text {
        text: control.text
        font: control.font
        color: control.highlighted ? "#1F6FEB" : "#333333"
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

}
