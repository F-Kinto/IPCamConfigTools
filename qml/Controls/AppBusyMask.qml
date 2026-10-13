import QtQuick 2.15
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

    // 转圈 + 提示文本（转圈样式与文本样式统一收在 AppSpinner）
    AppSpinner {
        anchors.centerIn: parent
        spacing: ScreenTools.scaleNum(12)
        running: root.busy
        text: root.text
    }

}
