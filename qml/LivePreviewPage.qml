/*********************************************************************
File : LivePreviewPage.qml
Module : 页面
date : 2026/10/12
Ver : 1.3.0
History:
1.0.0 build this module
1.1.0 直播窗口顶部改为标题栏（左 IP / 右关闭按钮）；右键菜单（关闭直播、
      全屏/退出全屏）；“全屏”改为铺满工作区、保留任务栏；全部直播关闭后
      自动收起“直播预览”页签（由 main.qml 监听 devices 变化处理）
1.2.0 标题栏浮层化并自动显隐：开启直播时显示 1s 后隐藏，鼠标触碰窗口顶部
      重新显示，停留在标题栏内不隐藏；全屏窗口同样支持；右键菜单改用
      通用控件 AppContextMenu（白底圆角、项高 32、纯文本）
1.2.1 右键菜单项改用 AppMenuItem：修复全屏菜单字体与非全屏不一致的问题
      （全屏是无字体的独立 Window，Controls 会用控件字体覆盖 contentItem 字体），
      同时修复内联菜单项不走 Menu.delegate 导致悬浮样式失效的问题；
      全屏状态下关闭直播默认退出全屏
1.3.0 直播页面最多 4 个窗口：超出时由 main.qml 拦截并弹窗提示，本页再做
      一次截断兜底（4 台时按 2x2 排布）
********************************************************************/
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15 as AppWin
import IPCam.Public 1.0
import "Controls"

/**
 * 直播预览页：点击「播放勾选设备」后以「直播预览」页签打开。
 *
 * 每个勾选设备一个“直播窗口”：画面区 16:9，顶部标题栏（左：IP，右：关闭按钮，
 * 可扩展）为浮层，自动显隐——开启直播显示 1s 后隐藏；鼠标触碰窗口顶部重新
 * 显示；鼠标在标题栏内不隐藏，离开 1s 后隐藏。全屏窗口同样遵循该逻辑。
 * 右键画面弹菜单（关闭直播 / 全屏/退出全屏），双击画面切换全屏；
 * 全屏为独立无边框窗口，铺满所在显示器的工作区（保留任务栏）。
 *
 * 设备端取流协议尚未对接，画面区当前为占位内容，后续在 cell 内部接入
 * 解码渲染（VideoOutput 等）即可，对外的 devices 接口保持不变。
 */
Item {
    id: root

    // 要播放的设备列表（QVariantMap 数组，来自 DeviceManager.checkedDevices()）
    property var devices: []
    // 最多同时显示的直播窗口数（main.qml 里点击播放时会先拦截，这里是兜底）
    readonly property int maxDevices: 4
    // 每行列数：1 台时单格，2 台及以上每行 2 格（4 台时 2x2）
    readonly property int columns: Math.max(1, Math.min(2, devices.length))
    // 正在全屏显示的那一台的序号，-1 表示没有全屏
    property int fullScreenIndex: -1
    // 全屏窗口当前是否可见（对外只读，用于外部查询全屏状态）
    readonly property bool fullScreenVisible: fullScreenWin.visible
    // 全屏窗口当前显示的设备（可能为空对象，取值一律防空）
    readonly property var fullScreenDevice: (root.fullScreenIndex >= 0 && root.fullScreenIndex < root.devices.length) ? root.devices[root.fullScreenIndex] : ({
    })
    // 标题栏浮层是否显示（网格页与全屏窗共用一套显隐状态）
    property bool headerShown: false

    // 进入全屏：独占整个工作区（保留任务栏）
    function enterFullScreen(index) {
        root.fullScreenIndex = index;
    }

    // 退出全屏，恢复网格
    function exitFullScreen() {
        root.fullScreenIndex = -1;
    }

    // 关闭一路直播：从播放列表移除该设备。
    // 全部关完后由 main.qml 监听 devices 变化自动收起“直播预览”页签
    function closeDevice(index) {
        if (index < 0 || index >= root.devices.length)
            return ;

        // 正在全屏的就是这一路：先退全屏；其它情况序号前移一位
        if (root.fullScreenIndex === index)
            root.exitFullScreen();
        else if (root.fullScreenIndex > index)
            root.fullScreenIndex--;
        var list = root.devices.slice();
        list.splice(index, 1);
        root.devices = list;
    }

    // 显示标题栏并重置 1s 隐藏计时
    function pokeHeader() {
        root.headerShown = true;
        headerHideTimer.restart();
    }

    // 鼠标进入标题栏区域：停止计时（停留期间不隐藏）
    function holdHeader() {
        headerHideTimer.stop();
    }

    // 鼠标离开标题栏区域：重新计时，1s 无停留自动隐藏
    function releaseHeader() {
        headerHideTimer.restart();
    }

    // 播放列表变了：退出全屏避免停留在已失效画面上，并重新展示标题栏 1s。
    // 注意 1：property var 的初始值赋值也会触发本信号（程序启动时），
    //         用 visible 守卫，避免页签没打开时标题栏白闪一次
    // 注意 2：超过 4 路直接截断（截断赋值会再触发一次本信号，走到正常分支）
    onDevicesChanged: {
        if (root.devices.length > root.maxDevices) {
            root.devices = root.devices.slice(0, root.maxDevices);
            return ;
        }
        root.exitFullScreen();
        if (root.visible)
            root.pokeHeader();

    }
    // 全屏/还原的实际切换：由 fullScreenIndex 驱动。
    // visible 与 visibility 不能同时绑定（Qt 会报 conflicting properties），
    // 且对未显示的窗口设 visibility 也不生效，所以走命令式接口
    onFullScreenIndexChanged: {
        if (root.fullScreenIndex >= 0) {
            fullScreenWin.showMaximized();
            root.pokeHeader();
        } else {
            fullScreenWin.hide();
        }
    }

    // 标题栏自动隐藏计时：1s 内鼠标没有停留在标题栏区域就隐藏
    Timer {
        id: headerHideTimer

        interval: 1000
        onTriggered: root.headerShown = false
    }

    // 右键菜单（网格页与全屏窗各挂一份，动作一致）
    AppContextMenu {
        id: cellMenu

        property int targetIndex: -1

        AppMenuItem {
            text: qsTr("关闭直播")
            onTriggered: root.closeDevice(cellMenu.targetIndex)
        }

        AppMenuItem {
            text: root.fullScreenIndex >= 0 ? qsTr("退出全屏") : qsTr("全屏")
            onTriggered: {
                if (root.fullScreenIndex >= 0)
                    root.exitFullScreen();
                else
                    root.enterFullScreen(cellMenu.targetIndex);
            }
        }

    }

    // 没有播放设备时的空状态
    Label {
        anchors.centerIn: parent
        visible: root.devices.length === 0
        color: "#8A9099"
        font.family: "Microsoft YaHei"
        font.pointSize: ScreenTools.scaleNum(12, true)
        text: qsTr("暂无播放设备")
    }

    Flickable {
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: Math.max(height, cellFlow.implicitHeight)

        Flow {
            id: cellFlow

            width: parent.width
            spacing: ScreenTools.scaleNum(4)

            Repeater {
                model: root.devices

                // 单路直播窗口：整格即画面区，标题栏为顶部浮层
                delegate: Rectangle {
                    width: (cellFlow.width - cellFlow.spacing * (root.columns - 1)) / root.columns
                    height: width * 9 / 16
                    color: "#101418"
                    border.color: "#DCDCDC"
                    border.width: 1

                    // 双击全屏 / 右键菜单（铺满整格）
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onDoubleClicked: root.enterFullScreen(index)
                        onClicked: {
                            if (mouse.button === Qt.RightButton) {
                                cellMenu.targetIndex = index;
                                cellMenu.popup();
                            }
                        }
                    }

                    // 顶部热区：鼠标触碰窗口顶部唤出标题栏（不拦截点击）
                    MouseArea {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: ScreenTools.scaleNum(26)
                        acceptedButtons: Qt.NoButton
                        hoverEnabled: true
                        onContainsMouseChanged: {
                            if (containsMouse)
                                root.pokeHeader();

                        }
                    }

                    // 标题栏浮层（自动显隐）
                    LiveTitleBar {
                        dev: modelData
                        targetIndex: index
                    }

                    // 居中占位内容（接通取流后替换为真实画面）
                    Column {
                        anchors.centerIn: parent
                        spacing: ScreenTools.scaleNum(6)

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: ScreenTools.scaleNum(36)
                            height: ScreenTools.scaleNum(24)
                            radius: ScreenTools.scaleNum(5)
                            color: "transparent"
                            border.color: "#DCDCDC"
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                color: "#5A6672"
                                font.pointSize: ScreenTools.scaleNum(10, true)
                                text: "\u25B6"
                            }

                        }

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: "#7A828A"
                            font.family: "Microsoft YaHei"
                            font.pointSize: ScreenTools.scaleNum(10, true)
                            text: qsTr("预览占位（取流未接入）")
                        }

                    }

                }

            }

        }

        // 只允许竖向滚动查看超出窗口的格子，不提供横向滚动
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

    }

    // 全屏（铺满工作区、保留任务栏）的那一路，做成独立无边框窗口
    AppWin.Window {
        id: fullScreenWin

        // 无边框 + 最大化 = 覆盖除任务栏外的整个屏幕；
        // 用 showFullScreen() 会连任务栏一起盖掉，不符合需求
        flags: Qt.Window | Qt.FramelessWindowHint
        title: qsTr("直播预览 - 全屏")
        color: "#000000"
        // 注意：QtQuick.Window 的 Window 没有 font 属性（只有 ApplicationWindow 有），
        // 且独立窗口不会继承主窗口字体，所以窗口内的文字各自显式指定字体
        // 跟随主窗口所在的显示器（多屏时不跳到主屏）
        screen: AppWin.Screen

        AppContextMenu {
            id: fsMenu

            property int targetIndex: -1

            AppMenuItem {
                text: qsTr("关闭直播")
                onTriggered: root.closeDevice(fsMenu.targetIndex)
            }

            AppMenuItem {
                text: root.fullScreenIndex >= 0 ? qsTr("退出全屏") : qsTr("全屏")
                onTriggered: {
                    if (root.fullScreenIndex >= 0)
                        root.exitFullScreen();
                    else
                        root.enterFullScreen(fsMenu.targetIndex);
                }
            }

        }

        // 顶部热区：鼠标触碰窗口顶部唤出标题栏（不拦截点击）
        MouseArea {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: ScreenTools.scaleNum(26)
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            onContainsMouseChanged: {
                if (containsMouse)
                    root.pokeHeader();

            }
        }

        // 标题栏浮层（自动显隐，与网格页共用一套状态）
        LiveTitleBar {
            dev: root.fullScreenDevice
            targetIndex: root.fullScreenIndex
        }

        // 居中占位内容（接通取流后整体替换）
        Column {
            anchors.centerIn: parent
            spacing: ScreenTools.scaleNum(12)

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: ScreenTools.scaleNum(96)
                height: ScreenTools.scaleNum(64)
                radius: ScreenTools.scaleNum(8)
                color: "transparent"
                border.color: "#DCDCDC"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    color: "#5A6672"
                    font.family: "Microsoft YaHei"
                    font.pointSize: ScreenTools.scaleNum(26, true)
                    text: "\u25B6"
                }

            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#7A828A"
                font.family: "Microsoft YaHei"
                font.pointSize: ScreenTools.scaleNum(14, true)
                text: qsTr("预览占位（取流未接入）")
            }

        }

        Label {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: ScreenTools.scaleNum(16)
            color: "#5A6672"
            font.family: "Microsoft YaHei"
            font.pointSize: ScreenTools.scaleNum(10, true)
            text: qsTr("双击画面退出全屏，右键画面打开菜单")
        }

        // 再次双击还原；右键弹菜单
        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.exitFullScreen()

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onDoubleClicked: root.exitFullScreen()
                onClicked: {
                    if (mouse.button === Qt.RightButton) {
                        fsMenu.targetIndex = root.fullScreenIndex;
                        fsMenu.popup();
                    }
                }
            }

        }

    }

    // 标题栏浮层：左 IP，右关闭按钮（Row 内可继续追加别的功能按钮）。
    // 网格页与全屏窗共用，dev 为该路设备，targetIndex 为 closeDevice 的序号
    component LiveTitleBar: Rectangle {
        id: titleBar

        property var dev: ({
        })
        property int targetIndex: -1

        anchors.top: parent ? parent.top : undefined
        anchors.left: parent ? parent.left : undefined
        anchors.right: parent ? parent.right : undefined
        height: ScreenTools.scaleNum(36)
        color: "#232B33"
        visible: root.headerShown
        z: 10

        // 鼠标停在标题栏内不隐藏，离开后重新计时
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            onContainsMouseChanged: root.holdHeader()
            onExited: root.releaseHeader()
        }

        Label {
            anchors.left: parent.left
            anchors.leftMargin: ScreenTools.scaleNum(8)
            anchors.right: btnRow.left
            anchors.rightMargin: ScreenTools.scaleNum(6)
            anchors.verticalCenter: parent.verticalCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            color: "#E8EAED"
            font.family: "Microsoft YaHei"
            font.pointSize: ScreenTools.scaleNum(9, true)
            text: titleBar.dev.ip || ""
        }

        Row {
            id: btnRow

            anchors.right: parent.right
            anchors.rightMargin: ScreenTools.scaleNum(6)
            anchors.verticalCenter: parent.verticalCenter
            spacing: ScreenTools.scaleNum(4)

            // 关闭按钮：关闭这一路直播，窗口消失
            Item {
                width: ScreenTools.scaleNum(20)
                height: ScreenTools.scaleNum(20)

                Text {
                    anchors.centerIn: parent
                    color: cellCloseArea.containsMouse ? "#FFFFFF" : "#9AA1A9"
                    font.pointSize: ScreenTools.scaleNum(10, true)
                    text: "\u2715"
                }

                Rectangle {
                    anchors.fill: parent
                    radius: ScreenTools.scaleNum(3)
                    color: cellCloseArea.containsMouse ? "#FF4A4A" : "transparent"
                    z: -1
                }

                MouseArea {
                    id: cellCloseArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closeDevice(titleBar.targetIndex)
                }

            }

        }

    }

}
