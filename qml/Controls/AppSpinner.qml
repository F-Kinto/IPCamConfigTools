import QtQuick 2.15
import QtQuick.Controls 2.15
import IPCam.Public 1.0

/*********************************************************************
File : AppSpinner.qml
Module : 通用控件
date : 2026/10/13
Ver : 1.1.0
History:
1.0.0 从 AppBusyMask 的转圈动画抽出为通用组件：蓝 -> 浅蓝渐变弧线
      （300° 缺口），顺时针匀速旋转。直播"连接中"与设备搜索遮罩共用，
      保证两处样式一致。尺寸由调用方指定，线宽 / 分段数 / 转速固定
1.1.0 文本并入组件：新增 text / textPointSize 属性，转圈下方带提示文字
      （白字 80% 透明度）。圈圈可见性内部绑定 running，文本始终显示，
      修复直播超时态"连接超时"文本被一并隐藏的问题
********************************************************************/
Column {
    id: root

    // 是否转动：false 时圈圈隐藏并停转（文本不受影响，显隐由调用方控制）
    property bool running: false

    // 提示文本：为空时文本不显示也不占位，只显示转圈
    property string text: ""

    // 提示文本字号（point，未缩放基准值，内部经 ScreenTools 缩放）
    property real textPointSize: ScreenTools.scaleNum(12, true)

    spacing: ScreenTools.scaleNum(12)

    // 转圈等待动画：蓝 -> 浅蓝渐变，顺时针匀速旋转
    Canvas {
        id: spinnerCanvas

        readonly property color cStart: "#2f6fed" // 蓝
        readonly property color cEnd: "#9ed0ff" // 浅蓝
        readonly property int segments: 24 // 分段数，越多渐变越平滑
        readonly property real sweepDeg: 300 // 留一段缺口更像转圈
        readonly property real lineWidth: ScreenTools.scaleNum(4)

        anchors.horizontalCenter: parent.horizontalCenter
        width: ScreenTools.scaleNum(48)
        height: ScreenTools.scaleNum(48)
        visible: root.running
        antialiasing: true
        // 逐段画圆弧并按序号插值上色，形成沿弧线的渐变
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.lineWidth = lineWidth;
            ctx.lineCap = "round";
            var cx = width / 2;
            var cy = height / 2;
            var r = (Math.min(width, height) - lineWidth) / 2;
            var step = (sweepDeg / segments) * Math.PI / 180;
            var from = -Math.PI / 2; // 12 点方向起笔
            for (var i = 0; i < segments; i++) {
                var t = i / (segments - 1);
                ctx.strokeStyle = Qt.rgba(cStart.r + (cEnd.r - cStart.r) * t, cStart.g + (cEnd.g - cStart.g) * t, cStart.b + (cEnd.b - cStart.b) * t, 1).toString();
                ctx.beginPath();
                ctx.arc(cx, cy, r, from + i * step, from + (i + 1) * step);
                ctx.stroke();
            }
        }
        Component.onCompleted: requestPaint()
        // 调用方改尺寸后重画（渐变弧线按当前宽高绘制）
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        // 中等转速：1.2 秒一圈；running 为 false 自动停转
        RotationAnimation on rotation {
            from: 0
            to: 360
            duration: 1200
            loops: Animation.Infinite
            running: root.running
        }

    }

    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.text !== "" && root.running
        text: root.text
        color: "#FFFFFF"
        opacity: 0.8
        font.family: "Microsoft YaHei"
        font.pointSize: root.textPointSize
    }

}
