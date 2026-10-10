import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import IPCam.Public 1.0

// 统一下拉框样式：
// 1) 边框 4px 圆角，聚焦/hover/展开时边框与主色（蓝色）一致
// 2) 下拉列表中当前选中项：蓝字 + 浅蓝底（悬停时加深），其余项仅鼠标悬停时高亮
ComboBox {
    id: control

    // 放在布局中时保证最小高度与其他控件一致
    Layout.minimumHeight: ScreenTools.scaleNum(30)
    hoverEnabled: true
    // 当前文本距左边界 8px；右侧同样留 8px，再叠加下拉箭头占位（箭头位于内容区之外）
    leftPadding: ScreenTools.scaleNum(8)
    rightPadding: ScreenTools.scaleNum(8) + (control.indicator ? control.indicator.width + control.spacing : 0)
    font.family: "Microsoft YaHei"
    font.pointSize: ScreenTools.scaleNum(10, true)

    contentItem: Text {
        text: control.displayText
        font: control.font
        color: control.enabled ? "#1A1A1A" : "#a0a0a0"
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignLeft
        elide: Text.ElideRight
    }

    background: Rectangle {
        radius: ScreenTools.scaleNum(4)
        color: control.enabled ? "white" : "#f0f0f0"
        border.width: 1
        border.color: (control.activeFocus || control.hovered || control.down) ? "#2f6fed" : "#767676"
    }

    popup: Popup {
        y: control.height
        width: control.width
        // 最多显示 10 项（每项 24px），超出部分由滚动条滚动显示
        height: Math.min(contentItem.implicitHeight + topPadding + bottomPadding,
                         ScreenTools.scaleNum(24) * 10 + ScreenTools.scaleNum(8))
        padding: ScreenTools.scaleNum(2)
        topMargin: ScreenTools.scaleNum(6)
        bottomMargin: ScreenTools.scaleNum(6)

        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.delegateModel
            currentIndex: control.highlightedIndex
            highlightMoveDuration: 0
            ScrollIndicator.vertical: ScrollIndicator { }
        }

        background: Rectangle {
            radius: ScreenTools.scaleNum(4)
            color: "#FFFFFF"
            border.width: 1
            border.color: "#D8DCE3"
            clip: true
        }
    }

    // 下拉列表：每项固定 24px 高；可见区域最多 10 项，超出滚动；外框 4px 圆角
    delegate: ItemDelegate {
        width: control.width
        implicitHeight: ScreenTools.scaleNum(24)
        // ItemDelegate 默认 padding 为 12（上下合计 24），会把 24px 的行高全占掉导致文本被挤没，这里清零
        padding: 0
        highlighted: control.highlightedIndex === index
        // 列表项文本距左右边界各 8px
        leftPadding: ScreenTools.scaleNum(8)
        rightPadding: ScreenTools.scaleNum(8)
        contentItem: Label {
            font: control.font
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignLeft
            elide: Text.ElideRight
            text: control.textRole ? (Array.isArray(control.model) ? modelData[control.textRole] : model[control.textRole]) : modelData
            color: {
                if (control.currentIndex === index)
                    return "#2f6fed";
                // 悬停项沿用系统高亮（深蓝底 + 白字）
                return control.highlightedIndex === index ? "#FFFFFF" : "#1A1A1A";
            }
        }
        background: Rectangle {
            color: {
                if (control.currentIndex === index)
                    return control.highlightedIndex === index ? "#BBD4FF" : "#D6E4FF";

                return control.highlightedIndex === index ? control.palette.highlight : "transparent";
            }
        }
    }
}
