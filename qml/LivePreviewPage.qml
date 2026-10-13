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
1.2.0 直播页面最多 4 个窗口：超出时由 main.qml 拦截并弹窗提示，本页再做
      一次截断兜底（4 台时按 2x2 排布）
1.3.0 接入 RTSP 实时取流渲染（同步自 VmsTools RtspDecodeTask 链路）：
      每个窗口一个 RtspVideoItem（内部 Live555 拉流 + FFmpeg 解码），
      双击设备列表即固定走 RTSP；全屏时把渲染组件重父级到全屏窗
      （拉流不中断），退出全屏归还给原窗口
********************************************************************/
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtMultimedia 5.15
import QtQuick.Window 2.15 as AppWin
import IPCam.Public 1.0
import IPCam.Rtsp 1.0
import "Controls"

/**
 * 直播预览页：点击「播放勾选设备」后以「直播预览」页签打开。
 *
 * 设备端取流已接入：每个窗口内嵌一个 RtspVideoItem（Live555 拉流 + FFmpeg 解码）
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
    onFullScreenIndexChanged: {
        if (root.fullScreenIndex >= 0) {
            var cell = cellRepeater.itemAt(root.fullScreenIndex);
            if (cell && cell.videoComp && cell.videoComp.parent !== fsVideoArea) {
                cell.videoComp.parent = fsVideoArea;
                cell.videoComp.anchors.fill = fsVideoArea;
            }
            fullScreenWin.showMaximized();
            root.pokeHeader();
        } else {
            fullScreenWin.hide();
            // 归还被借走的渲染组件（正常只可能有一路挂在全屏窗）
            for (var i = 0; i < cellRepeater.count; i++) {
                var c = cellRepeater.itemAt(i);
                if (c && c.videoComp && c.videoComp.parent === fsVideoArea) {
                    c.videoComp.parent = c;
                    c.videoComp.anchors.fill = c;
                }
            }
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
                id: cellRepeater

                model: root.devices

                // 单路直播窗口：整格即画面区，标题栏为顶部浮层
                delegate: Rectangle {
                    id: liveCell

                    width: (cellFlow.width - cellFlow.spacing * (root.columns - 1)) / root.columns
                    height: width * 9 / 16
                    color: "#101418"
                    border.color: "#DCDCDC"
                    border.width: 1

                    // 供全屏切换逻辑访问本窗口的渲染组件
                    property alias videoComp: cellVideo

                    // 断流状态机：
                    // everPlayed  出过流（区别"首连"与"偶断流"两种遮罩观感）
                    // dead        持续 60s 无流（宽限期耗尽），转错误态等用户重连
                    property bool everPlayed: false
                    property bool dead: false

                    // 无流 60s 计时：首连起即计；断流重计；出流即停并复活
                    Timer {
                        id: noVideoTimer

                        interval: 60 * 1000
                        onTriggered: liveCell.dead = true
                    }
                    Component.onCompleted: noVideoTimer.start()
                    Connections {
                        target: cellVideo

                        function onHasVideoDataChanged() {
                            if (cellVideo.hasVideoData) {
                                liveCell.everPlayed = true;
                                liveCell.dead = false;
                                noVideoTimer.stop();
                            } else if (!liveCell.dead) {
                                noVideoTimer.restart();
                            }
                        }
                    }

                    // 全屏期间本窗口的渲染组件被借到全屏窗，delegate 若此时
                    // 销毁（设备被移除）需先断流再脱离父子树，避免流泄漏
                    Component.onDestruction: {
                        if (cellVideo.parent !== liveCell) {
                            cellVideo.device = ({});
                            cellVideo.parent = null;
                        }
                    }

                    // RTSP 拉流渲染组件：device 赋值即自动起流（拉流+解码），
                    // 全屏重父级不影响其内部任务与帧渲染
                    // z:1 抬到输入 MouseArea 之上：遮罩自身无输入项不拦截
                    // 双击/右键穿透，仅"重新连接"按钮（dead 态出现）需要抢占点击
                    RtspVideoItem {
                        id: cellVideo

                        z: 1
                        anchors.fill: parent
                        device: modelData

                        // 画面区：VideoOutput 消费 yuvProvider 的 YUV 帧
                        VideoOutput {
                            anchors.fill: parent
                            source: cellVideo.yuvProvider
                            fillMode: VideoOutput.Stretch
                        }

                        // 无流遮罩（出流即隐藏），三态：
                        // 1 首连（未出过流）      灰底 + 连接中...（转圈）
                        // 2 偶断流（60s 宽限期内）冻结画面上 0.2 黑 + 连接中...（转圈）
                        // 3 宽限期耗尽（dead）    灰底 + 视频加载错误 + 重新连接按钮
                        Item {
                            id: streamMask

                            anchors.fill: parent
                            visible: !cellVideo.hasVideoData

                            Rectangle {
                                anchors.fill: parent
                                // 断流宽限期：原画面（冻结帧）叠 0.2 黑；
                                // 首连 / 错误态：实灰底
                                color: liveCell.everPlayed && !liveCell.dead ? "#33000000" : "#6D7682"
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: ScreenTools.scaleNum(10)

                                AppSpinner {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    visible: !liveCell.dead
                                    // 无流即转（首连或断流等待），出流后遮罩隐藏自动停
                                    running: !liveCell.dead
                                    text: qsTr("连接中...")
                                    textPointSize: ScreenTools.scaleNum(10, true)
                                }

                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    visible: liveCell.dead
                                    color: "#FFFFFF"
                                    opacity: 0.9
                                    font.family: "Microsoft YaHei"
                                    font.pointSize: ScreenTools.scaleNum(10, true)
                                    text: qsTr("视频加载错误, 请重新连接")
                                }

                                AppButton {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    visible: liveCell.dead
                                    highlighted: true
                                    text: qsTr("重新连接")
                                    showBorder: false
                                    onClicked: {
                                        // 复位为首连观感并重启 60s 计时
                                        liveCell.dead = false;
                                        liveCell.everPlayed = false;
                                        noVideoTimer.restart();
                                        cellVideo.reconnect();
                                    }
                                }

                            }
                        }

                    }

                    // 双击全屏 / 右键菜单（铺满整格）。
                    // z 低于 cellVideo：遮罩内"重新连接"按钮优先吃到点击
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

                    // 标题栏浮层（自动显隐）。z:2 压过画面层 z:1
                    LiveTitleBar {
                        z: 2
                        dev: modelData
                        targetIndex: index
                    }

                }

            }

        }

        // 只允许竖向滚动查看超出窗口的格子，不提供横向滚动
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

    }

    // 全屏（铺满工作区、保留任务栏）的那一路
    AppWin.Window {
        id: fullScreenWin
        // 无边框 + 最大化 = 覆盖除任务栏外的整个屏幕；
        flags: Qt.Window | Qt.FramelessWindowHint
        title: qsTr("直播预览 - 全屏")
        color: "#000000"
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

        // 标题栏浮层（自动显隐，与网格页共用一套状态）。z:2 压过画面层 z:1
        LiveTitleBar {
            z: 2
            dev: root.fullScreenDevice
            targetIndex: root.fullScreenIndex
        }

        // 画面容器：进入全屏时网格页对应窗口的 RtspVideoItem 会被重父级到这里（拉流不中断），退出时归还
        Item {
            id: fsVideoArea

            z: 1
            anchors.fill: parent
        }

        // 无画面时兜底提示（重父级失败/流中断）
        Column {
            anchors.centerIn: parent
            spacing: ScreenTools.scaleNum(12)
            visible: fsVideoArea.children.length === 0

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#5A6672"
                font.family: "Microsoft YaHei"
                font.pointSize: ScreenTools.scaleNum(14, true)
                text: qsTr("无直播画面")
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
    // 网格页与全屏窗共用
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
