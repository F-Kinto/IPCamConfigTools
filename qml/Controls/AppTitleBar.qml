import QtQuick 2.15
import QtQuick.Window 2.15
import IPCam.Public 1.0

// 自绘标题栏：左侧 logo + 标题文本，右侧 最小化 / 最大化还原 / 关闭 按钮。
// 配合 main.qml 的 frameless 窗口与外层圆角描边使用。
Rectangle {
    id: root

    // 宿主窗口（main.qml 的 ApplicationWindow）
    property var win: null
    property string titleText: ""
    // 最大化状态由宿主窗口 visibility 推导
    readonly property bool isMaximized: win !== null
                                       && win.visibility === Window.Maximized

    height: ScreenTools.scaleNum(36)
    color: "#FFFFFF"
    // 圆角与外层窗口边框一致；最大化时直角，否则圆角处透出桌面
    radius: root.isMaximized ? 0 : ScreenTools.scaleNum(4)
    // 按钮贴角区域按圆角裁剪，避免 hover 色块顶出圆角
    clip: true

    // ===== 空白区域拖动窗口 / 双击切换最大化 =====
    DragHandler {
        target: null
        onActiveChanged: {
            if (active && root.win !== null)
                root.win.startSystemMove();
        }
    }
    TapHandler {
        onDoubleTapped: root.toggleMaximized()
    }

    function toggleMaximized() {
        if (win === null)
            return;
        if (win.visibility === Window.Maximized)
            win.showNormal();
        else
            win.showMaximized();
    }

    // ===== 左侧 logo + 标题 =====
    Image {
        id: logo

        anchors.left: parent.left
        anchors.leftMargin: ScreenTools.scaleNum(10)
        anchors.verticalCenter: parent.verticalCenter
        width: ScreenTools.scaleNum(16)
        height: ScreenTools.scaleNum(16)
        fillMode: Image.PreserveAspectFit
        source: "qrc:/qml/image/appIcon.png"
    }

    Text {
        anchors.left: logo.right
        anchors.leftMargin: ScreenTools.scaleNum(6)
        anchors.verticalCenter: parent.verticalCenter
        text: root.titleText
        color: "#333333"
        font.family: "Microsoft YaHei"
        font.pointSize: ScreenTools.scaleNum(10, true)
    }

    // ===== 右侧窗口控制按钮 =====
    Row {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        // 最小化（图标自绘：横线，防符号字体缺字形）
        Rectangle {
            width: ScreenTools.scaleNum(44)
            height: parent.height
            color: minMouse.containsMouse ? "#E9E9E9" : "transparent"

            Rectangle {
                anchors.centerIn: parent
                width: ScreenTools.scaleNum(10)
                height: ScreenTools.scaleNum(1)
                color: "#333333"
            }
            MouseArea {
                id: minMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.win !== null)
                        root.win.showMinimized();
                }
            }
        }

        // 最大化 / 还原（图标自绘：单框 / 双框叠放）
        Rectangle {
            width: ScreenTools.scaleNum(44)
            height: parent.height
            color: maxMouse.containsMouse ? "#E9E9E9" : "transparent"

            // 最大化：单框
            Rectangle {
                anchors.centerIn: parent
                width: ScreenTools.scaleNum(10)
                height: ScreenTools.scaleNum(10)
                visible: !root.isMaximized
                color: "transparent"
                border.width: 1
                border.color: "#333333"
            }
            // 还原：前层大框 + 后层小框
            Item {
                anchors.centerIn: parent
                width: ScreenTools.scaleNum(10)
                height: ScreenTools.scaleNum(10)
                visible: root.isMaximized

                Rectangle {
                    x: parent.width * 0.3
                    width: parent.width * 0.7
                    height: parent.height * 0.7
                    color: "transparent"
                    border.width: 1
                    border.color: "#333333"
                }
                Rectangle {
                    y: parent.height * 0.3
                    width: parent.width * 0.7
                    height: parent.height * 0.7
                    color: "#FFFFFF"
                    border.width: 1
                    border.color: "#333333"
                }
            }
            MouseArea {
                id: maxMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleMaximized()
            }
        }

        // 关闭（图标自绘：两条 45° 短线组成 ×；hover 红底白叉）
        Rectangle {
            width: ScreenTools.scaleNum(44)
            height: parent.height
            color: closeMouse.containsMouse ? "#E81123" : "transparent"

            Rectangle {
                anchors.centerIn: parent
                width: ScreenTools.scaleNum(12)
                height: ScreenTools.scaleNum(2)
                color: closeMouse.containsMouse ? "#FFFFFF" : "#000000"
                rotation: 45
            }
            Rectangle {
                anchors.centerIn: parent
                width: ScreenTools.scaleNum(12)
                height: ScreenTools.scaleNum(2)
                color: closeMouse.containsMouse ? "#FFFFFF" : "#000000"
                rotation: -45
            }
            MouseArea {
                id: closeMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // 走 win.close()：保留 onClosing 的播放确认拦截
                onClicked: {
                    if (root.win !== null)
                        root.win.close();
                }
            }
        }
    }

    // 底部补平：盖住标题栏底部两个圆角，使其与内容区平齐
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.radius
        color: "#FFFFFF"
    }

    // 底部分隔线，与内容区分界
    Rectangle {
        id: bottomLine

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: "#DCDCDC"
    }
}
