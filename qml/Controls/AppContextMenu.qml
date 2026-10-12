// 通用右键菜单：白底、圆角 4px、菜单项高 32px、只保留文本（不带图标）。
// 菜单项悬浮时浅蓝底 + 蓝字（与主界面页签选中色一致）。
// 注意 1：字体必须设在 Menu 控件自身（而不是只设在 contentItem 上）——
// QtQuick.Controls 会把控件的 font 覆盖到 contentItem 上，只设 contentItem
// 会被宿主窗口字体顶掉（实测：同一个控件挂在普通 Window 里会变 SimSun/9pt）。
// 注意 2：菜单项必须用配套的 AppMenuItem 声明。Menu.delegate 只对
// addItem()/Instantiator 产生的项生效，内联声明的 MenuItem 不走 delegate
// （实测会退回默认样式），所以内联项一律写 AppMenuItem。

import QtQuick 2.15
import QtQuick.Controls 2.15
import IPCam.Public 1.0

// 用法：
//   AppContextMenu {
//       id: ctxMenu
//       property int targetIndex: -1
//       AppMenuItem { text: qsTr("关闭直播"); onTriggered: doClose(ctxMenu.targetIndex) }
//       AppMenuItem { text: qsTr("全屏");     onTriggered: doFull(ctxMenu.targetIndex)  }
//   }
//   弹出：ctxMenu.targetIndex = xxx; ctxMenu.popup()
Menu {
    id: control

    // 字体设在控件上：向下传递到菜单项，不受宿主窗口字体影响
    font.family: "Microsoft YaHei"
    font.pointSize: ScreenTools.scaleNum(10, true)
    // 宽度取“最长菜单项 + 左右内边距”，最窄 120px，避免文字被压缩
    width: {
        var w = ScreenTools.scaleNum(120);
        for (var i = 0; i < control.count; ++i) {
            var it = control.itemAt(i);
            if (!it)
                continue;

            var itemW = it.contentItem.implicitWidth + it.leftPadding + it.rightPadding;
            if (itemW > w)
                w = itemW;

        }
        return w;
    }
    // 四周留 4px 空隙，菜单项与圆角背景之间不顶边
    padding: ScreenTools.scaleNum(4)
    topPadding: padding
    bottomPadding: padding

    background: Rectangle {
        radius: ScreenTools.scaleNum(4)
        color: "#FFFFFF"
        border.color: "#DCDCDC"
        border.width: 1
    }

    // 供 addItem()/Instantiator 创建的项使用；内联声明的项请直接写 AppMenuItem
    delegate: AppMenuItem {
    }

}
