import QtQuick 2.15
import QtQuick.Controls 2.15
import IPCam.Public 1.0

// 通用忙碌遮罩：黑底 50% 半透明覆盖层 + 转圈等待动画 + 提示文本
// 覆盖并吞掉鼠标事件，避免忙碌期间误点底层按钮。
// 用法（覆盖调用处所在的整个区域）：
//   AppBusyMask {
//       anchors.fill: parent
//       z: 100               // 按场景抬高层级，盖住同层兄弟项
//       busy: root.searching // true = 显示遮罩并开始转圈；false = 隐藏且停转
//       text: qsTr("设备搜索中...") // 提示文本，默认为空（为空时只显示转圈）
//   }
Item {
    id: root

    // 提示文本：为空时文本不显示也不占位，只显示转圈动画
    property string text: ""
    // 是否处于忙碌状态：控制遮罩显隐与动画启停
    property bool busy: false

    visible: root.busy

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.5
    }

    // 吞掉鼠标事件：Label 不接收鼠标，点击会落到本层被拦截
    MouseArea {
        anchors.fill: parent
    }

    Column {
        anchors.centerIn: parent
        spacing: ScreenTools.scaleNum(12)

        // 转圈等待动画：蓝 -> 浅蓝渐变，顺时针匀速旋转
        Canvas {
            readonly property color cStart: "#2f6fed" // 蓝
            readonly property color cEnd: "#9ed0ff" // 浅蓝
            readonly property int segments: 24 // 分段数，越多渐变越平滑
            readonly property real sweepDeg: 300 // 留一段缺口更像转圈
            readonly property real lineWidth: ScreenTools.scaleNum(4)

            anchors.horizontalCenter: parent.horizontalCenter
            width: ScreenTools.scaleNum(48)
            height: ScreenTools.scaleNum(48)
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

            // 中等转速：1.2 秒一圈；busy 结束自动停转
            RotationAnimation on rotation {
                from: 0
                to: 360
                duration: 1200
                loops: Animation.Infinite
                running: root.busy
            }

        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.text !== ""
            text: root.text
            color: "white"
            font.family: "Microsoft YaHei"
            font.pointSize: ScreenTools.scaleNum(12, true)
        }

    }

}
