import QtQuick 2.15
import QtQuick.Controls 2.15
import IPCam.Public 1.0

// 统一复选样式：勾选框固定 16x16，勾选图标按比例绘制、严格居中；字体微软雅黑 10pt，控件高度与其他输入控件一致
CheckBox {
    id: control

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: ScreenTools.scaleNum(30)
    leftPadding: 0
    spacing: ScreenTools.scaleNum(8)
    font.family: "Microsoft YaHei"
    font.pointSize: ScreenTools.scaleNum(10, true)

    indicator: Rectangle {
        implicitWidth: ScreenTools.scaleNum(16)
        implicitHeight: ScreenTools.scaleNum(16)
        x: control.leftPadding
        // 垂直方向严格居中于控件
        y: control.topPadding + (control.availableHeight - height) / 2
        radius: ScreenTools.scaleNum(2)
        color: control.enabled ? (control.down ? "#e6e6e6" : "white") : "#f0f0f0"
        border.width: 1
        border.color: control.enabled ? (control.activeFocus ? "#2f6fed" : "#767676") : "#c8ccd2"

        // 勾选图标：按盒子比例取点绘制，任意尺寸下都保持居中
        Canvas {
            anchors.fill: parent
            anchors.margins: ScreenTools.scaleNum(1)
            visible: control.checked || control.checkState === Qt.PartiallyChecked
            onVisibleChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                var w = width;
                var h = height;
                ctx.lineWidth = Math.max(ScreenTools.scaleNum(2), w * 0.14);
                ctx.lineCap = "round";
                ctx.lineJoin = "round";
                ctx.strokeStyle = control.enabled ? "#2f6fed" : "#a0a0a0";
                if (control.checkState === Qt.PartiallyChecked) {
                    // 半选：中间横线
                    ctx.beginPath();
                    ctx.moveTo(w * 0.2, h * 0.5);
                    ctx.lineTo(w * 0.8, h * 0.5);
                    ctx.stroke();
                } else {
                    ctx.beginPath();
                    ctx.moveTo(w * 0.2, h * 0.52);
                    ctx.lineTo(w * 0.4, h * 0.74);
                    ctx.lineTo(w * 0.82, h * 0.24);
                    ctx.stroke();
                }
            }
        }
    }

    contentItem: Label {
        leftPadding: control.indicator ? control.indicator.width + control.spacing : 0
        rightPadding: control.rightPadding
        // 禁用时文字同步置灰，与文本框/下拉框的禁用态保持一致
        color: control.enabled ? "#1A1A1A" : "#a0a0a0"
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignLeft
        elide: Text.ElideRight
        font: control.font
        text: control.text
    }
}
