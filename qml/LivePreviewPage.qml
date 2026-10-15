/*********************************************************************
File : LivePreviewPage.qml
Module : 页面
date : 2026/10/14
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
    // 主码流播放（main.qml 顶部工具栏勾选状态透传，默认不勾选）：true=ch00_0 主码流，false=ch00_1 子码流
    property bool mainStream: false
    // 内部把 deviceModel 回写到 devices 时置位：跳过 onDevicesChanged 回灌
    property bool _syncing: false
    // 最多同时显示的直播窗口数（main.qml 里点击播放时会先拦截，这里是兜底）
    readonly property int maxDevices: 4
    // 每行列数：1 台时单格，2 台及以上每行 2 格（4 台时 2x2）
    readonly property int columns: Math.max(1, Math.min(2, deviceModel.count))
    // 行数：按设备数与列数推算（1/2 台 → 1 行，3/4 台 → 2 行）。
    // 用于把视口高度均分给各行：格子高 = 行高，铺满不留白
    readonly property int rows: Math.ceil(Math.max(1, deviceModel.count) / Math.max(1, columns))
    // 页内放大的那一路序号（双击切换），-1 表示网格布局
    property int zoomIndex: -1
    // 整页是否处于全屏窗口中（右键菜单“全屏”，整个网格一起进全屏窗）
    property bool pageFullScreen: false
    // 全屏窗口当前是否可见（对外只读，用于外部查询全屏状态）
    readonly property bool fullScreenVisible: fullScreenWin.visible
    // 当前显示标题栏的那一路序号（-1 = 全部隐藏）。按格子驱动：
    // 碰哪一路顶部就只显示哪一路的标题栏，其余路不受影响
    property int headerIndex: -1

    // 页内放大：该路铺满直播页区域，其余路隐藏但拉流不中断
    function enterPageZoom(index) {
        root.zoomIndex = index;
        root.pokeHeader(index);
    }

    // 还原网格布局
    function exitPageZoom() {
        root.zoomIndex = -1;
    }

    // 整页进入全屏窗口：整个网格一起重父级，各路拉流不中断
    function enterFullScreen() {
        root.pageFullScreen = true;
    }

    // 退出整页全屏：网格归还回直播页
    function exitFullScreen() {
        root.pageFullScreen = false;
    }

    // 关闭一路直播：从播放列表移除该设备。
    // 全部关完后由 main.qml 监听 devices 变化自动收起“直播预览”页签
    function closeDevice(index) {
        if (index < 0 || index >= deviceModel.count)
            return ;

        deviceModel.remove(index);
        // 整页全屏/页内放大状态下关闭一路：网格仍在原容器内增量更新，
        // 仅需修正放大路序号，无需退出全屏或还原放大
        if (root.zoomIndex > index)
            root.zoomIndex--;
        else if (root.zoomIndex === index)
            root.zoomIndex = -1;
        root.syncDevicesFromModel();
        if (root.visible)
            root.pokeHeader(deviceModel.count > 0 ? 0 : -1);
    }

    // 单点更新某一路的设备数据（如 RTSP 凭据晚到替换设备信息）：只刷新
    // 该行，对应 RtspVideoItem 按新数据重连，其余路不受影响
    function updateDevice(index, device) {
        if (index < 0 || index >= deviceModel.count)
            return ;

        deviceModel.setProperty(index, "device", device);
        var list = root.devices.slice();
        if (index < list.length) {
            list[index] = device;
            root._syncing = true;
            root.devices = list;
            root._syncing = false;
        }
    }

    // 把 deviceModel 当前内容回写到 devices，置 _syncing 防止 onDevicesChanged 回灌重建
    function syncDevicesFromModel() {
        var list = [];
        for (var i = 0; i < deviceModel.count; i++)
            list.push(deviceModel.get(i).device);
        root._syncing = true;
        root.devices = list;
        root._syncing = false;
    }

    // 显示某一路的标题栏并重置 1s 隐藏计时（index = -1 表示全部隐藏）
    function pokeHeader(index) {
        root.headerIndex = (index === undefined) ? -1 : index;
        headerHideTimer.restart();
    }

    // 鼠标停留在标题栏区域：停止计时（停留期间不隐藏）
    function holdHeader() {
        headerHideTimer.stop();
    }

    // 鼠标离开标题栏区域：重新计时，1s 无停留自动隐藏
    function releaseHeader() {
        headerHideTimer.restart();
    }

    // 播放列表变了：退出全屏避免停留在已失效画面上，并重新展示标题栏 1s。
    onDevicesChanged: {
        if (root._syncing)
            return ;
        var list = root.devices;
        if (list.length > root.maxDevices) {
            root._syncing = true;
            root.devices = list.slice(0, root.maxDevices);
            root._syncing = false;
            list = root.devices;
        }
        root.syncModelToList(list);
        root.exitFullScreen();
        if (list.length > 1 && root.zoomIndex >= 0)
            root.zoomIndex = -1;
        if (root.visible)
            root.pokeHeader(list.length > 0 ? 0 : -1);

    }

    // 按设备 key 对齐做增量同步：中间差异段删除后按新列表逐行插入
    function syncModelToList(list) {
        var prefix = 0;
        while (prefix < deviceModel.count && prefix < list.length && DeviceManager.keyOf(deviceModel.get(prefix).device) === DeviceManager.keyOf(list[prefix]))
            prefix++;
        var suffix = 0;
        while (suffix < deviceModel.count - prefix && suffix < list.length - prefix && DeviceManager.keyOf(deviceModel.get(deviceModel.count - 1 - suffix).device) === DeviceManager.keyOf(list[list.length - 1 - suffix]))
            suffix++;
        var removeCount = deviceModel.count - prefix - suffix;
        for (var i = 0; i < removeCount; i++)
            deviceModel.remove(prefix);
        var insertCount = list.length - prefix - suffix;
        for (var j = 0; j < insertCount; j++)
            deviceModel.insert(prefix + j, {device: list[prefix + j]});
    }

    onPageFullScreenChanged: {
        if (root.pageFullScreen) {
            if (flick.parent !== fsVideoArea) {
                flick.parent = fsVideoArea;
                flick.anchors.fill = fsVideoArea;
                flick.anchors.margins = 0;
            }
            fullScreenWin.showFullScreen();
            root.pokeHeader(0);
        } else {
            fullScreenWin.hide();
            if (flick.parent !== root) {
                flick.parent = root;
                flick.anchors.fill = root;
                flick.anchors.margins = ScreenTools.scaleNum(4);
            }
        }
    }

    // 直播设备渲染模型
    ListModel {
        id: deviceModel
    }

    // 标题栏自动隐藏计时：1s 内鼠标没有停留在标题栏区域就隐藏
    Timer {
        id: headerHideTimer

        interval: 1000
        onTriggered: root.headerIndex = -1
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
            text: root.pageFullScreen ? qsTr("退出全屏") : qsTr("全屏")
            onTriggered: {
                if (root.pageFullScreen)
                    root.exitFullScreen();
                else
                    root.enterFullScreen();
            }
        }

    }

    // 没有播放设备时的空状态
    Label {
        anchors.centerIn: parent
        visible: deviceModel.count === 0
        color: "#8A9099"
        font.family: "Microsoft YaHei"
        font.pointSize: ScreenTools.scaleNum(12, true)
        text: qsTr("暂无播放设备")
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: ScreenTools.scaleNum(4)
        clip: true
        contentWidth: width
        contentHeight: Math.max(height, cellFlow.implicitHeight)

        Flow {
            id: cellFlow

            width: parent.width
            spacing: ScreenTools.scaleNum(4)

            Repeater {
                id: cellRepeater

                model: deviceModel
                delegate: Rectangle {
                    id: liveCell
                    property bool isZoomed: root.zoomIndex === index || deviceModel.count === 1
                    property bool hoverGrow: (cellMouse.containsMouse || topHover.containsMouse) && !isZoomed
                    visible: root.zoomIndex < 0 || root.zoomIndex === index
                    width: isZoomed ? cellFlow.width : (cellFlow.width - cellFlow.spacing * (root.columns - 1)) / root.columns
                    height: isZoomed ? flick.height : (flick.height - cellFlow.spacing * (root.rows - 1)) / root.rows
                    color: "#101418"
                    // 悬停格提到相邻格之上
                    z: hoverGrow ? 10 : 0
                    // 供全屏切换逻辑访问本窗口的渲染组件
                    property alias videoComp: cellVideo
                    // 断流状态机：
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
                        // 起流时按勾选状态取主/子码流（ch00_0/ch00_1）
                        mainStream: root.mainStream
                        device: model.device

                        // 画面区：VideoOutput 消费 yuvProvider 的 YUV 帧。
                        VideoOutput {
                            anchors.fill: parent
                            source: cellVideo.yuvProvider
                            fillMode: VideoOutput.PreserveAspectFit
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

                    // 双击切换页内放大 / 右键弹菜单。
                    MouseArea {
                        id: cellMouse

                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onDoubleClicked: {
                            // 仅此一路：已默认铺满预览页，双击直接进出整页全屏
                            if (deviceModel.count === 1) {
                                if (root.pageFullScreen)
                                    root.exitFullScreen();
                                else
                                    root.enterFullScreen();
                            } else if (root.zoomIndex === index) {
                                root.exitPageZoom();
                            } else {
                                root.enterPageZoom(index);
                            }
                        }
                        onClicked: {
                            if (mouse.button === Qt.RightButton) {
                                // 整页全屏时格子已随 Flickable 挂进全屏窗，
                                // 右键需弹全屏窗自己的菜单
                                if (root.pageFullScreen) {
                                    fsMenu.targetIndex = index;
                                    fsMenu.popup();
                                } else {
                                    cellMenu.targetIndex = index;
                                    cellMenu.popup();
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: topHover

                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: ScreenTools.scaleNum(26)
                        acceptedButtons: Qt.NoButton
                        hoverEnabled: true
                        onContainsMouseChanged: {
                            if (containsMouse)
                                root.pokeHeader(index);
                        }
                    }

                    // 标题栏浮层（自动显隐）。z:2 压过画面层 z:1
                    LiveTitleBar {
                        z: 2
                        dev: model.device
                        targetIndex: index
                    }

                    Rectangle {
                        z: 3
                        anchors.fill: parent
                        color: "transparent"
                        border.color: hoverGrow ? "#4DA3FF" : "#DCDCDC"
                        border.width: hoverGrow ? 2 : 1
                    }

                }

            }

        }

        // 只允许竖向滚动查看超出窗口的格子，不提供横向滚动
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

    }

    // 全屏
    AppWin.Window {
        id: fullScreenWin
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
                text: qsTr("退出全屏")
                onTriggered: root.exitFullScreen()
            }

        }

        // 画面容器：整页全屏时整个 Flickable（网格 + 全部拉流组件）被重父级到这里
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
            z: 2
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: ScreenTools.scaleNum(16)
            color: "#5A6672"
            font.family: "Microsoft YaHei"
            font.pointSize: ScreenTools.scaleNum(10, true)
            text: deviceModel.count === 1 ? qsTr("双击画面退出全屏，右键画面打开菜单") : qsTr("双击画面放大单路，右键画面打开菜单，Esc 退出全屏")
        }

        // Esc 退出全屏
        Shortcut {
            sequence: "Escape"
            context: Qt.WindowShortcut
            enabled: fullScreenWin.visible
            onActivated: root.exitFullScreen()
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
        visible: root.headerIndex === titleBar.targetIndex
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
