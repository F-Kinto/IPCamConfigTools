import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt.labs.qmlmodels 1.0
// 用别名导入：QtQuick.Dialogs 也提供名为 Dialog 的类型，
// 不加别名会覆盖 QtQuick.Controls 的 Dialog（导致 footer/header 赋值报错）
import QtQuick.Dialogs 1.3 as AppDialogs
import IPCam.Public 1.0
// 项目内封装的通用控件目录（AppButton / AppTextField / DeviceTable 等）
import "Controls"

ApplicationWindow {
    id: root

    // 表格列标题（共 8 列，默认可视区域只显示前 6 列，其余需拖动底部水平滚动条）
    property var tableTitles: [qsTr("IP地址"), qsTr("UID"), qsTr("状态信息"), qsTr("升级当前版本号"), qsTr("升级后版本号"), qsTr("OSD标题"), qsTr("物理地址"), qsTr("设备类型")]
    // 是否允许鼠标拖拽表头分割线调整列宽
    property bool tableResizable: true
    // 列宽模式
    property bool tableStretchToFill: false
    // 固定列宽（tableStretchToFill 为 false 时生效）
    property var tableFixedWidths: [ScreenTools.scaleNum(150), ScreenTools.scaleNum(190), ScreenTools.scaleNum(130), ScreenTools.scaleNum(193), ScreenTools.scaleNum(193), ScreenTools.scaleNum(130), ScreenTools.scaleNum(150), ScreenTools.scaleNum(120)]
    // 拉伸权重（tableStretchToFill 为 true 时生效）
    property var tableStretchFactors: [1.1, 1.6, 1.1, 1.3, 1.3, 1.1, 1.2, 1.1]
    // 统一控件高度
    readonly property int controlHeight: ScreenTools.scaleNum(30)
    // 统一字体
    readonly property font appFont: Qt.font({
        "family": "Microsoft YaHei",
        "pointSize": ScreenTools.scaleNum(10, true)
    })
    // 已勾选设备的行号（由“全选 / 反选”维护）
    property var selectedRows: []
    readonly property int selectedCount: selectedRows.length
    // 设备搜索中：按钮禁用、结束后由 DeviceScanner.searchFinished 复位
    property bool searching: false
    // 搜索时长（秒），与“系统配置 - 搜索时间(秒)”联动
    property int searchSeconds: 5
    // ===== 页签（设备列表 / 直播预览）=====
    // 直播预览页是否已打开（关闭后页签栏整体隐藏，设备列表填满）
    property bool previewOpen: false
    // 当前显示的页：0=设备列表，1=直播预览
    property int currentPage: 0
    // 直播中切回设备列表页：该页操作已全部锁定，弹 toast 告知
    onCurrentPageChanged: {
        if (root.currentPage === 0 && root.previewOpen)
            appToast.show(root.liveLockTip);
    }
    // 设备列表页：操作面板与升级模块折叠开关（true=已收起，设备列表占满整行）
    property bool sidePanelsHidden: false
    // 固件升级：已选择的升级文件（本地路径列表，*.bin，可多选）
    property var upgradeFiles: []
    // 上次打开“升级文件”选择框时所在的目录（由 ConfigureManager 持久化到 ini）
    readonly property string lastUpgradeDir: ConfigureManager.upgradeDir
    // 网卡信息列表（ScreenTools::getNetworkInterfaces() 的返回值，已过滤为 ipconfig 可见项）
    property var nicList: []
    // 网卡下拉框数据：第一项固定“所有网卡”，之后为各网卡
    // 显示格式 "[ip] [网卡名称]"（如 "192.168.5.100 Realtek PCIe GBE Family Controller"）：
    // 该项只用于展示，写入配置文件与启动时匹配都只用网卡名称（displayName）
    readonly property var nicModel: [{
        "display": qsTr("所有网卡")
    }].concat(root.nicList.map(function(nic) {
        var ips = nic["ipv4"] || [];
        var name = nic["displayName"] || "";
        // 网卡没有 IPv4 地址时只显示名称
        return {
            "display": (ips.length > 0 ? ("[" + ips[0] + "]") + " " : "") + ("[" + name + "]")
        };
    }))
    // ===== 页签：直播预览 =====
    // 直播模式开关（两套逻辑二选一）：
    // false = 多路模式：最多 maxLiveCount 路同时播放
    // true  = 单路模式
    property bool singleLiveMode: true
    // 主码流播放（顶部工具栏勾选状态，默认不勾选）：起流 URL 用 ch00_0（主码流）/ ch00_1（子码流）
    property bool mainStreamPlay: false
    // 直播中锁定设备列表页的提示文案（按钮/输入框/下拉框/勾选/双击全禁用时弹出）
    readonly property string liveLockTip: qsTr("直播过程中, 该页面禁止操作, 请关闭直播后再操作")
    // 多路模式下同时播放的最大路数（直播页面最多 4 个窗口；单路模式不使用）
    readonly property int maxLiveCount: 4

    // ===== 网卡相关 =====
    // 刷新网卡列表，并按配置文件里保存的网卡名自动选中（启动时调用一次）
    function refreshNics() {
        nicList = ScreenTools.getNetworkInterfaces();
        root.restoreNicSelection();
    }

    // 当前选中的网卡信息，选中“所有网卡”时为 null
    function currentNic() {
        // 下拉框第 0 项是“所有网卡”，真实网卡从下标 1 开始
        var idx = nicCombo.currentIndex - 1;
        if (idx < 0 || idx >= root.nicList.length)
            return null;

        return root.nicList[idx];
    }

    // 启动时把获取到的网卡信息整体打印一次，用 ********** 包裹，方便在日志里区分定位
    function logNicList() {
        root.logAction("********** 网卡信息开始 **********");
        for (var i = 0; i < root.nicList.length; i++) {
            var n = root.nicList[i];
            root.logAction("  [网卡 " + i + "] 名称=" + (n["displayName"] || "") + " | 可读名=" + (n["humanReadableName"] || "") + " | 描述=" + (n["description"] || "") + " | MAC=" + (n["hardwareAddress"] || "") + " | IPv4=" + ((n["ipv4"] || []).join(", ")) + " | 子网掩码=" + (n["netmask"] || "") + " | 网关=" + (n["gateway"] || "") + " | 已启用=" + (n["isUp"] ? "是" : "否"));
        }
        root.logAction("********** 网卡信息结束，共 " + root.nicList.length + " 张 **********");
        var cur = root.currentNic();
        root.logAction("当前使用的网卡: " + (cur ? cur["displayName"] : "所有网卡"));
    }

    // 按配置文件中保存的网卡名匹配；匹配不到（含“All netCard”）则选中第一项“所有网卡”
    function restoreNicSelection() {
        var saved = ConfigureManager.networkCard;
        var target = 0;
        for (var i = 0; i < root.nicList.length; i++) {
            if (root.nicList[i]["displayName"] === saved) {
                target = i + 1;
                break;
            }
        }
        nicCombo.currentIndex = target;
    }

    // 用户改动选择后写入本地配置文件：选中“所有网卡”时写入 "All netCard"
    function saveNicSelection() {
        var nic = root.currentNic();
        ConfigureManager.networkCard = nic ? (nic["displayName"] || ConfigureManager.defaultNetworkCard()) : ConfigureManager.defaultNetworkCard();
    }

    // ===== 勾选相关 =====
    function selectAll() {
        var list = [];
        for (var i = 0; i < deviceModel.rowCount; i++) list.push(i)
        selectedRows = list;
    }

    function invertSelection() {
        var list = [];
        for (var i = 0; i < deviceModel.rowCount; i++) {
            if (selectedRows.indexOf(i) < 0)
                list.push(i);

        }
        selectedRows = list;
    }

    // 表格排序后行号重排：按 DeviceTable 给出的“旧行号 -> 新行号”映射同步已选行
    function remapSelectedRows(indexMap) {
        var list = [];
        for (var i = 0; i < root.selectedRows.length; i++) {
            var newIndex = indexMap[root.selectedRows[i]];
            if (newIndex !== undefined)
                list.push(newIndex);

        }
        root.selectedRows = list;
    }

    // 表格里某一行的复选框勾选/取消：同步进 selectedRows，“已选数量”与“请先选择设备”的校验都读这份数据，自动保持一致
    function setRowChecked(row, checked) {
        // 直播中锁定勾选：关闭直播前不允许变更“已选设备”
        if (root.previewOpen) {
            appToast.show(root.liveLockTip);
            return ;
        }
        var list = root.selectedRows.slice();
        var idx = list.indexOf(row);
        if (checked && idx < 0)
            list.push(row);
        else if (!checked && idx >= 0)
            list.splice(idx, 1);
        selectedRows = list;
    }

    // ===== 选中设备的持久化（C++ 的 DeviceManager）=====
    // 勾选（可多选）的设备按 uid 存进 QMap<uid, DeviceInfo>，供批量操作直接取用。
    function syncCheckedDevices() {
        var list = [];
        for (var i = 0; i < root.selectedRows.length; i++) {
            var dev = deviceModel.rows[root.selectedRows[i]];
            if (dev !== undefined)
                list.push(dev);

        }
        DeviceManager.syncCheckedDevices(list);
    }

    // 批量设置网络成功后：设备已切到设置的 IP，设备列表 IP 栏与勾选数据同步更新
    // （keyOf 口径与“执行修改”一致：uid -> mac -> ip）
    function updateDeviceIp(deviceKey, newIp) {
        for (var i = 0; i < deviceModel.rowCount; i++) {
            var dev = deviceModel.getRow(i);
            if (DeviceManager.keyOf(dev) !== deviceKey)
                continue;
            dev.ip = newIp;
            deviceModel.setRow(i, dev); // 替换该行数据，触发列表 IP 栏刷新
            // 勾选集合里该设备的信息覆盖更新（uid 相同直接覆盖，勾选数不变）
            DeviceManager.setCheckedDevice(dev);
            return ;
        }
    }

    // 当前选中（浅蓝高亮）的那一条单独保存一份，供单台操作取用
    function syncCurrentDevice() {
        var row = deviceTable.currentRow;
        if (row >= 0 && row < deviceModel.rowCount)
            DeviceManager.setCurrentDevice(deviceModel.rows[row]);
        else
            DeviceManager.clearCurrentDevice();
    }

    // 合并两份播放列表：按设备唯一 key 去重，已在播的保持原顺序在前
    function mergeLiveDevices(playing, added) {
        var seen = ({
        });
        var list = [];
        var i = 0;
        for (i = 0; i < playing.length; i++) {
            var k1 = DeviceManager.keyOf(playing[i]);
            if (seen[k1] !== true) {
                seen[k1] = true;
                list.push(playing[i]);
            }
        }
        for (i = 0; i < added.length; i++) {
            var k2 = DeviceManager.keyOf(added[i]);
            if (seen[k2] !== true) {
                seen[k2] = true;
                list.push(added[i]);
            }
        }
        return list;
    }

    // 打开直播预览页：以已勾选设备为播放列表，切到“直播预览”页签。。
    function openLivePreview() {
        var checked = DeviceManager.checkedDevices();
        // 播放前把缓存的 RTSP 凭据合并进来（设备发现时已预取，第一次起流即带真实凭据）
        for (var i = 0; i < checked.length; i++)
            checked[i] = DeviceManager.mergeRtspCredential(checked[i]);
        // 单路模式：只播勾选的第一台
        if (root.singleLiveMode) {
            var curDev = root.previewOpen && livePreviewPage.devices.length > 0 ? livePreviewPage.devices[0] : null;
            root.previewOpen = true;
            root.currentPage = 1;
            if (checked.length > 0) {
                var firstDev = checked[0];
                if (curDev === null || DeviceManager.keyOf(firstDev) !== DeviceManager.keyOf(curDev)) {
                    livePreviewPage.devices = [firstDev];
                    root.logAction("单路模式播放: 关闭%1, 播放%2".arg(curDev !== null ? curDev["ip"] : "无").arg(firstDev["ip"]));
                } else {
                    root.logAction("单路模式播放: %1 已在播, 切到直播页".arg(firstDev["ip"]));
                }
            }
            return true;
        }
        // 页签已打开时，在现有播放列表基础上追加（重复勾选的不会重复开窗口）
        var playing = root.previewOpen ? livePreviewPage.devices : [];
        // 单次勾选就超过上限
        if (checked.length > root.maxLiveCount) {
            confirmBox.showTip(qsTr("温馨提示"), qsTr("最多同时播放%1台设备").arg(root.maxLiveCount));
            root.logAction("打开直播预览失败: 勾选%1台，超过上限%2台".arg(checked.length).arg(root.maxLiveCount));
            return false;
        }
        // 合并后仍超过上限：已播满，需先关闭空闲的直播通道
        var merged = root.mergeLiveDevices(playing, checked);
        if (merged.length > root.maxLiveCount) {
            confirmBox.showTip(qsTr("温馨提示"), qsTr("当前已播放%1台设备, 如要继续播放, 请先关闭空闲的直播通道").arg(playing.length));
            root.logAction("打开直播预览失败: 已播放%1台，再播%2台会超过上限%3台".arg(playing.length).arg(merged.length - playing.length).arg(root.maxLiveCount));
            return false;
        }
        root.previewOpen = true;
        root.currentPage = 1;
        livePreviewPage.devices = merged;
        root.logAction("打开直播预览: %1 台设备".arg(livePreviewPage.devices.length));
        return true;
    }

    // 双击表格某行：直接播放该行设备
    // 合并后超过“最多 4 路”上限时弹窗提示，播放列表保持原样
    function openLivePreviewOfRow(row) {
        if (row < 0 || row >= deviceModel.rowCount)
            return ;

        var dev = deviceModel.rows[row];
        if (dev === undefined)
            return ;

        // 播放前把缓存的 RTSP 凭据合并进来（设备发现时已预取，第一次起流即带真实凭据）
        dev = DeviceManager.mergeRtspCredential(dev);
        // 多路模式：直播中锁定设备列表，双击不再追加播放
        if (!root.singleLiveMode && root.previewOpen) {
            appToast.show(root.liveLockTip);
            root.logAction("双击播放被拦截: 直播中锁定设备列表");
            return ;
        }
        // 单路模式：直播中双击“当前在播的那台”是跳转查看（不改变直播状态，
        // 保留切页）；双击其他设备属于换台，需先关闭直播，弹 toast 禁止
        if (root.singleLiveMode) {
            var curDev = root.previewOpen && livePreviewPage.devices.length > 0 ? livePreviewPage.devices[0] : null;
            if (curDev !== null) {
                if (DeviceManager.keyOf(dev) === DeviceManager.keyOf(curDev)) {
                    root.currentPage = 1;
                    root.logAction("单路模式双击: %1 已在播, 切到直播页".arg(dev["ip"]));
                } else {
                    appToast.show(root.liveLockTip);
                }
                return ;
            }
            root.previewOpen = true;
            root.currentPage = 1;
            livePreviewPage.devices = [dev];
            return ;
        }
        var playing = root.previewOpen ? livePreviewPage.devices : [];
        var merged = root.mergeLiveDevices(playing, [dev]);
        if (merged.length > root.maxLiveCount) {
            confirmBox.showTip(qsTr("温馨提示"), qsTr("当前已播放%1台设备, 如要继续播放, 请先关闭空闲的直播通道").arg(playing.length));
            root.logAction("双击播放失败: 已播放%1台，超出上限%2台".arg(playing.length).arg(root.maxLiveCount));
            return ;
        }
        root.previewOpen = true;
        root.currentPage = 1;
        livePreviewPage.devices = merged;
        root.logAction("双击播放直播: %1".arg(dev["ip"]));
    }

    // 请求关闭直播预览页：有设备在播时先弹确认（防误关正在直播的画面），
    // 无直播或已确认则直接走 closeLivePreview
    function requestCloseLivePreview() {
        var count = livePreviewPage.devices.length;
        if (count > 0) {
            confirmBox.showConfirm("tab", qsTr("温馨提示"), qsTr("当前有%1台设备正在直播, 确定要关闭吗?").arg(count));
            root.logAction("关闭直播预览确认弹窗: %1 台在播".arg(count));
            return;
        }
        closeLivePreview();
    }

    // 关闭直播预览页：回到设备列表并清空播放列表（页签栏随之隐藏）。
    // 清空 devices 会逐路销毁直播 delegate → RtspVideoItem 析构 → stopAndDeleteLater 安全停流（等线程退出，不崩），即"逐个安全退出"
    function closeLivePreview() {
        // 关闭全屏画面（若正开着），再隐藏页签栏
        livePreviewPage.exitFullScreen();
        root.previewOpen = false;
        if (root.currentPage === 1)
            root.currentPage = 0;

        livePreviewPage.devices = [];
        root.logAction("关闭直播预览");
    }

    // 窗口关闭拦截：有设备在播时不直接关窗，先弹确认（同关页签逻辑）
    onClosing: {
        // 确认弹窗已开着：拦下本次关窗，等用户先处理弹窗
        // （不拦会绕过确认直接关掉程序）
        if (confirmBox.confirmAction !== "") {
            close.accepted = false;
            return;
        }
        var count = livePreviewPage.devices.length;
        if (count > 0) {
            close.accepted = false;
            confirmBox.showConfirm("window", qsTr("温馨提示"), qsTr("当前有%1台设备正在直播, 确定要关闭直播并退出程序吗?").arg(count));
        } else {
            // 无直播放行，但可能有刚关闭还在线程收尾的任务：
            // 快速等一下（通常 0ms）再放行，防拆进程撞上退出中线程
            DeviceManager.waitForLiveStreamsExit(3000);
        }
    }

    // ===== 操作日志 =====
    // 从调用栈里取“调用 logAction 的那一层”的位置（第 0 帧是 logAction 自身）
    function callerLocation() {
        var stack = "";
        try {
            stack = String(new Error().stack);
        } catch (e) {
            return {
                "file": "",
                "line": 0,
                "function": ""
            };
        }
        var frames = stack.split("\n");
        // 帧格式：函数名@文件:行号；跳过 callerLocation / logAction 自身，取真正的调用方
        var frame = "";
        for (var i = 0; i < frames.length; i++) {
            var name = frames[i];
            var sep = name.lastIndexOf("@");
            if (sep >= 0)
                name = name.substring(0, sep);

            name = name.trim();
            if (name !== "callerLocation" && name !== "logAction") {
                frame = frames[i];
                break;
            }
        }
        if (frame === "")
            return {"file": "", "line": 0, "function": ""};

        var at = frame.lastIndexOf("@");
        if (at < 0)
            return {"file": "", "line": 0, "function": frame.trim()};

        var func = frame.substring(0, at).trim();
        var fileLine = frame.substring(at + 1).trim();
        // 去掉协议与目录，只保留文件名；行号取最后一个冒号之后
        var fileName = fileLine.substring(fileLine.lastIndexOf("/") + 1);
        var colon = fileName.lastIndexOf(":");
        var line = 0;
        if (colon >= 0) {
            line = parseInt(fileName.substring(colon + 1));
            if (isNaN(line))
                line = 0;

            fileName = fileName.substring(0, colon);
        }
        return {
            "file": fileName,
            "line": line,
            "function": func
        };
    }

    // 按钮点击、网卡切换等操作统一走这里输出一行日志（写入 LogText.txt）
    function logAction(text) {
        var loc = root.callerLocation();
        AppLogger.write(loc["file"], loc["line"], loc["function"], text);
    }

    // ===== 设备搜索 =====
    function searchDevices() {
        if (root.searching)
            return ;

        // 选中“所有网卡”时为 null，传空串表示不限制网段
        var nic = root.currentNic();
        // WifiBroadcast 按“可读名 / 网卡名 / 网卡 IPv4”匹配网卡，优先传可读名
        var nicName = nic ? (nic["humanReadableName"] || nic["displayName"] || "") : "";
        var ips = nic ? (nic["ipv4"] || []) : [];
        var nicDesc = nic ? (nicName + "(" + (ips.length > 0 ? ips[0] : qsTr("无IP")) + ")") : qsTr("所有网卡");
        root.logAction("设备搜索开始: 网卡=%1, 时长=%2秒".arg(nicDesc).arg(root.searchSeconds));
        // 清空上一次的结果、勾选与选中行
        deviceModel.rows = [];
        root.selectedRows = [];
        deviceTable.currentRow = -1;
        DeviceManager.clearCheckedDevices();
        DeviceManager.clearCurrentDevice();
        root.searching = true;
        DeviceScanner.startSearch(nicName, root.searchSeconds);
    }

    // ===== 固件升级 =====
    function urlToLocalPath(url) {
        var s = String(url);
        if (s.indexOf("file:///") === 0)
            s = s.substring(8);

        return decodeURIComponent(s);
    }

    function pathFileName(path) {
        var i = Math.max(String(path).lastIndexOf("/"), String(path).lastIndexOf("\\"));
        return i >= 0 ? String(path).substring(i + 1) : String(path);
    }

    function pathDirName(path) {
        var s = String(path);
        var i = Math.max(s.lastIndexOf("/"), s.lastIndexOf("\\"));
        return i >= 0 ? s.substring(0, i) : s;
    }

    // 已选文件在“升级文件”输入框里的摘要（最多列 3 个，超出显示总数）
    function upgradeFileSummary() {
        var files = root.upgradeFiles;
        if (files.length === 0)
            return "";

        var names = [];
        for (var i = 0; i < files.length && i < 3; i++) names.push(root.pathFileName(files[i]))
        var text = names.join(", ");
        if (files.length > 3)
            text += qsTr(" 等 %1 个文件").arg(files.length);

        return text;
    }

    // “文件一键升级”：先校验升级文件，再校验设备，最后执行升级
    function startFileUpgrade() {
        if (root.upgradeFiles.length === 0) {
            confirmBox.showTip(qsTr("温馨提示"), qsTr("请先选择升级文件"));
            return ;
        }
        if (!commandPanel.ensureDeviceSelected())
            return ;

        root.logAction("开始升级: 文件 %1 个, 设备 %2 台".arg(root.upgradeFiles.length).arg(root.selectedCount));
    }

    // ===== 退出程序 =====
    property bool exitingProgram: false

    // 勾选的行号一变就同步一次（单个勾选 / 全选 / 反选 / 清空都走这里）
    onSelectedRowsChanged: root.syncCheckedDevices()
    width: ScreenTools.scaleNum(ScreenTools.screenWidth) * ScreenTools.rectWidthScale
    height: ScreenTools.scaleNum(ScreenTools.screenHeight) * ScreenTools.rectHeightScale
    minimumWidth: ScreenTools.scaleNum(600)
    minimumHeight: ScreenTools.scaleNum(450)
    visible: true
    title: qsTr("IPC BatchTool_V1.0.0.0")
    color: "transparent"
    font.family: "Microsoft YaHei"
    font.pointSize: ScreenTools.scaleNum(10, true)
    // 去掉系统默认标题栏，改用自绘 AppTitleBar；
    flags: Qt.Window | Qt.FramelessWindowHint | Qt.NoDropShadowWindowHint
    // ===== 跨屏拖动适配 =====
    property real initialWidth: -1
    property real initialHeight: -1
    property real lastScreenDpr: -1
    property real screenDpr: Screen.devicePixelRatio

    onScreenDprChanged: {
        if (screenDpr < 0)
            return;
        if (lastScreenDpr < 0) {
            // 首次求值：仅记录基准
            lastScreenDpr = screenDpr;
            return;
        }
        if (screenDpr > 0 && screenDpr !== lastScreenDpr
                && visibility !== Window.Maximized) {
            root.fitWindowToScreen();
            Qt.callLater(root.fitWindowToScreen);
        }
        lastScreenDpr = screenDpr;
    }

    // 跨屏后恢复启动逻辑尺寸（放不下则收缩到新屏可用区），并把窗口拉回屏内
    function fitWindowToScreen() {
        if (initialWidth <= 0 || visibility === Window.Maximized)
            return;
        var newWidth = Math.min(initialWidth, Screen.desktopAvailableWidth);
        var newHeight = Math.min(initialHeight, Screen.desktopAvailableHeight);
        // 以当前左上角为锚收缩/放大，超出新屏的部分拉回屏内
        var newX = Math.max(Screen.virtualX,
                            Math.min(x, Screen.virtualX + Screen.width - newWidth));
        var newY = Math.max(Screen.virtualY,
                            Math.min(y, Screen.virtualY + Screen.height - newHeight));
        x = newX;
        y = newY;
        width = newWidth;
        height = newHeight;
    }
    // 启动时拉取一次网卡列表（并按配置文件自动回显），随后把网卡信息打印到日志
    Component.onCompleted: {
        // 记录启动逻辑尺寸，作为跨屏恢复的基准
        if (initialWidth <= 0) {
            initialWidth = width;
            initialHeight = height;
        }
        root.refreshNics();
        root.logNicList();
        // 程序启动自动执行一次设备搜索；延后一个事件循环，等窗口与表格就绪
        Qt.callLater(root.searchDevices);
    }

    // 接收设备搜索结果
    Connections {
        function onDeviceFound(device) {
            // 设备一发现就异步预取 RTSP 凭据
            DeviceManager.fetchRtspCredential(device);
            deviceModel.appendRow(device);
        }

        function onSearchFinished(count) {
            root.searching = false;
            root.logAction("设备搜索结束: 共发现 %1 台设备".arg(count));
        }

        target: DeviceScanner
    }

    // RTSP 凭据兜底：设备发现时已预取，双击前通常已在缓存；若用户在凭据返回前
    // 就双击播放（设备已用默认凭据起流），凭据到达后替换已播列表中对应设备，
    // 触发 RtspVideoItem 用真实凭据重连
    Connections {
        function onRtspCredentialFetched(device) {
            if (!root.previewOpen)
                return;

            var key = DeviceManager.keyOf(device);
            var devices = livePreviewPage.devices;
            for (var i = 0; i < devices.length; i++) {
                if (DeviceManager.keyOf(devices[i]) === key) {
                    livePreviewPage.updateDevice(i, device);
                    break;
                }
            }
        }

        target: DeviceManager
    }

    // 当前选中行变化（点击表格任意位置 / 勾选时顺带选中）→ 同步 DeviceManager 里的“当前设备”
    Connections {
        function onCurrentRowChanged() {
            root.syncCurrentDevice();
        }
        target: deviceTable
    }

    // 直播窗口全部关闭（数量为 0）→ 自动收起“直播预览”页签
    Connections {
        function onDevicesChanged() {
            if (root.previewOpen && livePreviewPage.devices.length === 0)
                root.closeLivePreview();
        }

        target: livePreviewPage
    }

    // ===== 圆角窗口背景（窗口本体已透明，背景移到这里画） =====
    Rectangle {
        id: windowBg

        anchors.fill: parent
        z: 0
        // 最大化时直角，否则圆角处会透出桌面
        radius: (visibility === Window.Maximized) ? 0 : ScreenTools.scaleNum(4)
        color: "#f0f0f0"
    }

    // ===== 最外层 2px 浅灰描边 =====
    Rectangle {
        id: windowBorder

        anchors.fill: parent
        z: 200
        radius: (visibility === Window.Maximized) ? 0 : ScreenTools.scaleNum(4)
        color: "transparent"
        border.width: 2
        border.color: "#DCDCDC"
        // 最大化撑满屏幕时不需要圆角边框
        visible: visibility !== Window.Maximized
    }

    // ===== 自绘标题栏（替代系统默认标题栏） =====
    AppTitleBar {
        id: appTitleBar

        titleText: root.title
        win: root
        z: 100
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
    }

    ColumnLayout {
        anchors.top: appTitleBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: ScreenTools.scaleNum(12)
        spacing: ScreenTools.scaleNum(4)

        // ===== 顶部工具栏 =====
        RowLayout {
            Layout.fillWidth: true
            spacing: ScreenTools.scaleNum(16)
            // 只在设备列表页显示；直播中切回本页时保持显示但整行禁用
            visible: root.currentPage === 0
            enabled: !root.previewOpen

            AppButton {
                text: qsTr("全选")
                highlighted: true
                onClicked: {
                    root.logAction("我点击了%1按钮".arg(text));
                    root.selectAll();
                }
            }

            AppButton {
                text: qsTr("反选")
                onClicked: {
                    root.logAction("我点击了%1按钮".arg(text));
                    root.invertSelection();
                }
            }

            Label {
                Layout.preferredHeight: root.controlHeight
                Layout.minimumWidth: ScreenTools.scaleNum(120)
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                text: qsTr("搜索完成, 总数: %1    已选: %2").arg(deviceModel.rowCount).arg(root.selectedCount)
            }

            AppCheckBox {
                Layout.preferredHeight: root.controlHeight
                text: qsTr("主码流播放")
                checked: root.mainStreamPlay
                onToggled: {
                    root.mainStreamPlay = checked;
                    root.logAction("%1已%2".arg(text).arg(checked ? "勾选" : "取消勾选"));
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Label {
                Layout.preferredHeight: root.controlHeight
                verticalAlignment: Text.AlignVCenter
                text: qsTr("网卡")
            }

            AppComboBox {
                id: nicCombo

                Layout.minimumWidth: ScreenTools.scaleNum(360)
                Layout.maximumWidth: ScreenTools.scaleNum(440)
                Layout.preferredHeight: root.controlHeight
                Layout.fillWidth: true
                // 下拉框展示 "[ip] [网卡名称]"，取值/匹配仍用网卡名称
                textRole: "display"
                model: root.nicModel
                // 默认选中第一项“所有网卡”，启动时由 restoreNicSelection() 按配置文件覆盖
                currentIndex: 0
                // 只在用户主动选择时写配置文件（程序自动回显不写，避免网卡临时消失时丢失配置）
                onActivated: {
                    root.saveNicSelection();
                    var nic = root.currentNic();
                    root.logAction("网卡切换为'%1'".arg(nic ? nic["displayName"] : "所有网卡"));
                }
            }

            AppButton {
                Layout.preferredWidth: ScreenTools.scaleNum(90)
                Layout.preferredHeight: root.controlHeight
                Layout.fillWidth: false
                text: qsTr("系统配置")
                onClicked: {
                    root.logAction("我点击了%1按钮".arg(text));
                    systemConfigDialog.open();
                }
            }

        }

        // ===== 中部：左侧设备表格 3/4 + 右侧操作指令 1/4 =====
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: ScreenTools.scaleNum(200)

            Row {
                id: midRow

                anchors.fill: parent
                spacing: ScreenTools.scaleNum(6)

                // 设备信息表格
                Rectangle {
                    width: !collapseBtn.visible ? midRow.width : commandPanel.visible ? (midRow.width - midRow.spacing * 2 - collapseBtn.width) * 3 / 4 : midRow.width - midRow.spacing - collapseBtn.width
                    height: midRow.height
                    color: "white"
                    border.width: 1
                    border.color: "#DCDCDC"
                    clip: true

                    Column {
                        anchors.fill: parent

                        // ===== 页签栏 =====
                        Row {
                            id: tabBar

                            visible: root.previewOpen
                            leftPadding: ScreenTools.scaleNum(6)
                            topPadding: ScreenTools.scaleNum(4)
                            spacing: ScreenTools.scaleNum(6)

                            // “设备列表”页签：不可关闭。
                            Rectangle {
                                width: ScreenTools.scaleNum(160)
                                height: ScreenTools.scaleNum(30)
                                radius: ScreenTools.scaleNum(6)
                                color: root.currentPage === 0 ? "#EAF3FF" : "#F5F6F7"
                                border.width: 1
                                border.color: root.currentPage === 0 ? "#B7D8FF" : "#DCDCDC"

                                Label {
                                    anchors.left: parent.left
                                    anchors.leftMargin: ScreenTools.scaleNum(10)
                                    anchors.verticalCenter: parent.verticalCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font.family: "Microsoft YaHei"
                                    font.pointSize: ScreenTools.scaleNum(10, true)
                                    color: root.currentPage === 0 ? "#1F6FEB" : "#4A4F55"
                                    text: qsTr("设备列表")
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.currentPage = 0
                                }

                            }

                            // “直播预览”页签：打开“播放勾选设备”后出现
                            Rectangle {
                                width: ScreenTools.scaleNum(160)
                                height: ScreenTools.scaleNum(30)
                                radius: ScreenTools.scaleNum(6)
                                color: root.currentPage === 1 ? "#EAF3FF" : "#F5F6F7"
                                border.width: 1
                                border.color: root.currentPage === 1 ? "#B7D8FF" : "#DCDCDC"

                                Label {
                                    anchors.left: parent.left
                                    anchors.leftMargin: ScreenTools.scaleNum(10)
                                    anchors.right: closeGlyph.left
                                    anchors.rightMargin: ScreenTools.scaleNum(4)
                                    anchors.verticalCenter: parent.verticalCenter
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                    font.family: "Microsoft YaHei"
                                    font.pointSize: ScreenTools.scaleNum(10, true)
                                    color: root.currentPage === 1 ? "#1F6FEB" : "#4A4F55"
                                    text: qsTr("直播预览")
                                }

                                Item {
                                    id: closeGlyph

                                    width: ScreenTools.scaleNum(16)
                                    height: ScreenTools.scaleNum(16)
                                    anchors.right: parent.right
                                    anchors.rightMargin: ScreenTools.scaleNum(8)
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        anchors.centerIn: parent
                                        color: closeArea.containsMouse ? "#FFFFFF" : "#8A9099"
                                        font.pointSize: ScreenTools.scaleNum(10, true)
                                        text: "\u2715"
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: closeGlyph.height / 2
                                        color: closeArea.containsMouse ? "#FF4A4A" : "transparent"
                                        z: -1
                                    }

                                    MouseArea {
                                        id: closeArea

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        // 有直播时先弹确认，无直播直接关
                                        onClicked: root.requestCloseLivePreview()
                                    }

                                }

                                MouseArea {
                                    anchors.fill: parent
                                    // 关闭按钮区域单独处理，避免点 X 同时触发切页
                                    z: -1
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.currentPage = 1
                                }

                            }

                        }

                        // ===== 页面区 =====
                        Item {
                            width: parent.width
                            height: parent.height - (tabBar.visible ? tabBar.height : 0)

                            DeviceTable {
                                id: deviceTable

                                anchors.fill: parent
                                // 让出 2px 边框，表格内容显示在框内
                                anchors.margins: ScreenTools.scaleNum(2)
                                visible: root.currentPage === 0
                                titles: root.tableTitles
                                resizable: root.tableResizable
                                stretchToFill: root.tableStretchToFill
                                fixedWidths: root.tableFixedWidths
                                stretchFactors: root.tableStretchFactors
                                headerHeight: Math.round(root.controlHeight * 1.5)
                                rowHeight: root.controlHeight
                                labelFont: root.appFont
                                checkBoxColumn: 0
                                checkedRows: root.selectedRows
                                onRowChecked: root.setRowChecked(row, checked)
                                // 双击
                                onRowDoubleClicked: root.openLivePreviewOfRow(row)
                                // 排序所用字段名，与下方 TableModelColumn 的 display 一一对应
                                columnRoles: ["ip", "uid", "status", "currentVersion", "targetVersion", "osdTitle", "mac", "deviceType"]
                                // 排序会打乱行号：按“旧行号 -> 新行号”同步已勾选设备，
                                onRowsReordered: {
                                    root.remapSelectedRows(indexMap);
                                    root.syncCurrentDevice();
                                }

                                model: TableModel {
                                    id: deviceModel

                                    rows: []

                                    TableModelColumn {
                                        display: "ip"
                                    }

                                    TableModelColumn {
                                        display: "uid"
                                    }

                                    TableModelColumn {
                                        display: "status"
                                    }

                                    TableModelColumn {
                                        display: "currentVersion"
                                    }

                                    TableModelColumn {
                                        display: "targetVersion"
                                    }

                                    TableModelColumn {
                                        display: "osdTitle"
                                    }

                                    TableModelColumn {
                                        display: "mac"
                                    }

                                    TableModelColumn {
                                        display: "deviceType"
                                    }

                                }

                            }

                            // 直播预览页：播放勾选设备时显示
                            LivePreviewPage {
                                id: livePreviewPage

                                anchors.fill: parent
                                anchors.margins: ScreenTools.scaleNum(2)
                                // 主码流播放勾选状态透传：各直播窗口起流时选 ch00_0/ch00_1
                                mainStream: root.mainStreamPlay
                                visible: root.currentPage === 1
                            }

                        }

                    }

                }

                // 折叠/展开按钮
                Rectangle {
                    id: collapseBtn

                    visible: root.currentPage === 0
                    width: ScreenTools.scaleNum(12)
                    height: midRow.height
                    radius: ScreenTools.scaleNum(6)
                    color: collapseArea.containsMouse ? "#EAF3FF" : "#F5F6F7"
                    border.width: 1
                    border.color: collapseArea.containsMouse ? "#4DA3FF" : "#DCDCDC"

                    // 箭头指示面板去向：展开态向右收起（▶），折叠态向左展开（◀）
                    Text {
                        anchors.centerIn: parent
                        text: root.sidePanelsHidden ? "\u25C0" : "\u25B6"
                        color: collapseArea.containsMouse ? "#1F6FEB" : "#8A9099"
                        font.family: "Microsoft YaHei"
                        font.pointSize: ScreenTools.scaleNum(10, true)
                    }

                    MouseArea {
                        id: collapseArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.sidePanelsHidden = !root.sidePanelsHidden
                    }

                }

                // 操作指令面板（1/4）
                CommandPanel {
                    id: commandPanel
                    width: (midRow.width - midRow.spacing * 2 - collapseBtn.width) / 4
                    height: midRow.height
                    visible: root.currentPage === 0 && !root.sidePanelsHidden
                    // 直播中整面板禁用（搜索/播放/重启/修改IP/OSD 等按钮与输入全锁定）
                    enabled: !root.previewOpen
                    host: root
                    confirmBox: confirmBox
                    setIpDialog: setIpDialog
                    osdDialog: osdDialog
                    otherSettingsDialog: otherSettingsDialog
                    searching: root.searching
                    selectedCount: root.selectedCount
                    deviceCount: deviceModel.rowCount
                    onSearchRequested: root.searchDevices()
                    onLivePreviewRequested: root.openLivePreview()
                    // 批量下发其他参数全部完成：弹出结果详情弹窗
                    onBatchAllFinished: batchResultDialog.open()
                    // 网络设置成功后设备已切新 IP：更新设备列表 IP 栏并同步勾选数据
                    onDeviceIpChanged: root.updateDeviceIp(deviceKey, newIp)
                }

            }

        }

        // ===== 底部：固件升级 =====
        GroupBox {
            Layout.fillWidth: true
            Layout.preferredHeight: ScreenTools.scaleNum(120)
            title: qsTr("固件升级")
            visible: root.currentPage === 0 && !root.sidePanelsHidden
            // 直播中固件升级区禁用（浏览/一键升级不可点）
            enabled: !root.previewOpen

            GridLayout {
                columns: 4
                columnSpacing: ScreenTools.scaleNum(8)
                rowSpacing: ScreenTools.scaleNum(4)
                width: parent.width

                Label {
                    Layout.preferredHeight: root.controlHeight
                    verticalAlignment: Text.AlignVCenter
                    text: qsTr("升级文件")
                }

                AppTextField {
                    Layout.fillWidth: true
                    Layout.columnSpan: 2
                    Layout.minimumWidth: ScreenTools.scaleNum(60)
                    // 展示已选文件摘要；路径很长时末尾省略
                    text: root.upgradeFileSummary()
                    readOnly: true
                    placeholderText: qsTr("请选择 .bin 升级文件（可多选）")
                }

                RowLayout {
                    spacing: ScreenTools.scaleNum(6)

                    AppButton {
                        text: qsTr("浏览")
                        onClicked: {
                            root.logAction("我点击了%1按钮（升级文件）".arg(text));
                            upgradeFileDialog.open();
                        }
                    }

                    AppButton {
                        text: qsTr("文件一键升级")
                        onClicked: {
                            root.logAction("我点击了%1按钮".arg(text));
                            root.startFileUpgrade();
                        }
                    }

                }

                Label {
                    Layout.preferredHeight: root.controlHeight
                    verticalAlignment: Text.AlignVCenter
                    text: qsTr("升级目录")
                    visible: false
                }

                AppTextField {
                    Layout.fillWidth: true
                    Layout.columnSpan: 2
                    Layout.minimumWidth: ScreenTools.scaleNum(60)
                    visible: false
                }

                RowLayout {
                    spacing: ScreenTools.scaleNum(6)
                    visible: false

                    AppButton {
                        text: qsTr("浏览")
                        onClicked: root.logAction("我点击了%1按钮（升级目录）".arg(text))
                    }

                    AppButton {
                        text: qsTr("目录升级")
                        onClicked: root.logAction("我点击了%1按钮".arg(text))
                    }

                }

                AppComboBox {
                    Layout.minimumWidth: ScreenTools.scaleNum(110)
                    Layout.preferredHeight: root.controlHeight
                    model: [qsTr("上传音频文件"), qsTr("上传配置文件")]
                    visible: false
                    onActivated: root.logAction("上传类型切换为'%1'".arg(currentText))
                }

                AppTextField {
                    Layout.fillWidth: true
                    Layout.columnSpan: 2
                    Layout.minimumWidth: ScreenTools.scaleNum(60)
                    visible: false
                }

                RowLayout {
                    spacing: ScreenTools.scaleNum(6)
                    visible: false

                    AppButton {
                        text: qsTr("浏览")
                        onClicked: root.logAction("我点击了%1按钮（上传文件）".arg(text))
                    }

                    AppButton {
                        text: qsTr("开始上传")
                        onClicked: root.logAction("我点击了%1按钮".arg(text))
                    }

                }

            }

        }

    }

    // ===== 系统配置弹窗（外壳复用 AppContentDialog，中间表单内容在此声明）=====
    AppContentDialog {
        id: systemConfigDialog

        title: qsTr("系统配置")
        width: ScreenTools.scaleNum(420)
        okText: qsTr("保存")
        // 保存：更新搜索时间并弹“保存成功”提示（accept 触发 onAccepted）
        onOkClicked: {
            root.searchSeconds = searchTimeSpin.displayText
            root.logAction("我点击了%1按钮（系统配置）".arg(systemConfigDialog.okText))
            systemConfigDialog.accept()
        }
        // 取消：直接关闭
        onCancelClicked: {
            systemConfigDialog.reject()
        }
        // 点击“保存”后弹出提示
        onAccepted: confirmBox.showTip(qsTr("温馨提示"), qsTr("保存成功"))

        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: ScreenTools.scaleNum(10)
            rowSpacing: ScreenTools.scaleNum(10)

            Label {
                Layout.preferredHeight: root.controlHeight
                verticalAlignment: Text.AlignVCenter
                text: qsTr("搜索时间(秒)")
            }

            SpinBox {
                id: searchTimeSpin
                // “− / +”按钮为正方形，边长与控件高度一致
                readonly property int btnW: root.controlHeight
                Layout.fillWidth: true
                Layout.preferredHeight: root.controlHeight
                from: 5
                to: 120
                value: 5
                stepSize: 1
                editable: true
                hoverEnabled: true
                padding: 0
                leftPadding: btnW
                rightPadding: btnW
                font.family: "Microsoft YaHei"
                font.pointSize: ScreenTools.scaleNum(10, true)

                background: Rectangle {
                    radius: ScreenTools.scaleNum(4)
                    color: searchTimeSpin.enabled ? "white" : "#f0f0f0"
                    border.width: 1
                    border.color: (searchTimeSpin.activeFocus || searchTimeSpin.hovered) ? "#2f6fed" : "#DCDCDC"
                }

                // 数字区：在两个按钮之间居中显示
                contentItem: TextInput {
                    z: 2
                    text: searchTimeSpin.displayText
                    font: searchTimeSpin.font
                    color: searchTimeSpin.enabled ? "#1A1A1A" : "#a0a0a0"
                    horizontalAlignment: Qt.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    readOnly: !searchTimeSpin.editable
                    validator: searchTimeSpin.validator
                    selectByMouse: true
                }

                // “−”按钮（左）：数值减 1 秒。
                down.indicator: Rectangle {
                    x: 1
                    y: 1
                    width: searchTimeSpin.btnW - 2
                    height: searchTimeSpin.height - 2
                    radius: ScreenTools.scaleNum(3)
                    color: searchTimeSpin.down.pressed ? "#BBD4FF" : "#F5F7FA"

                    // 补齐内侧两个直角
                    Rectangle {
                        anchors.right: parent.right
                        width: parent.radius
                        height: parent.height
                        color: parent.color
                    }

                    // 与输入区的分隔线
                    Rectangle {
                        anchors.right: parent.right
                        width: 1
                        height: parent.height
                        color: "#D8DCE3"
                    }

                    Label {
                        anchors.centerIn: parent
                        text: "-"
                        font.bold: true
                        font.pointSize: ScreenTools.scaleNum(12, true)
                        color: searchTimeSpin.enabled ? "#1A1A1A" : "#a0a0a0"
                    }

                }

                // “+”按钮（右）：数值加 1 秒
                up.indicator: Rectangle {
                    x: searchTimeSpin.width - width - 1
                    y: 1
                    width: searchTimeSpin.btnW - 2
                    height: searchTimeSpin.height - 2
                    radius: ScreenTools.scaleNum(3)
                    color: searchTimeSpin.up.pressed ? "#BBD4FF" : "#F5F7FA"

                    // 补齐内侧两个直角
                    Rectangle {
                        anchors.left: parent.left
                        width: parent.radius
                        height: parent.height
                        color: parent.color
                    }

                    // 与输入区的分隔线
                    Rectangle {
                        anchors.left: parent.left
                        width: 1
                        height: parent.height
                        color: "#D8DCE3"
                    }

                    Label {
                        anchors.centerIn: parent
                        text: "+"
                        font.bold: true
                        font.pointSize: ScreenTools.scaleNum(12, true)
                        color: searchTimeSpin.enabled ? "#1A1A1A" : "#a0a0a0"
                    }

                }

            }

            Label {
                Layout.preferredHeight: root.controlHeight
                verticalAlignment: Text.AlignVCenter
                text: qsTr("(5~120秒)")
            }

            Label {
                Layout.preferredHeight: root.controlHeight
                verticalAlignment: Text.AlignVCenter
                text: qsTr("语言")
            }

            AppComboBox {
                Layout.fillWidth: true
                Layout.preferredHeight: root.controlHeight
                model: [qsTr("简体中文"), "English"]
            }

            Label {
                Layout.preferredHeight: root.controlHeight
                verticalAlignment: Text.AlignVCenter
                text: qsTr("(重启生效)")
            }

        }

    }

    // ===== 通用弹窗（全工程唯一 AppMessageBox 实例：单按钮提示 + 两按钮确认）=====
    // 用 confirmAction 字符串区分事件，onAccepted 按动作分发，不再
    // 每个场景单独实例一个 AppMessageBox。当前动作：
    //   "messageTip"    - 单按钮纯提示：点击无任何逻辑请求，仅关闭弹窗
    //   "setIpSelectAll" - 修改IP未勾选设备：是→全选并继续执行
    //   "reboot"         - 重启已勾选设备（真实下发协议待接入，当前记日志）
    //   "factoryReset"   - 恢复出厂设置已勾选设备（同上）
    //   "tab"            - 关闭直播预览页签（安全退出在播设备）
    //   "window"         - 退出程序
    // 全局轻提示 toast（非模态、自动消失）：直播锁定设备列表等场景使用
    AppToast {
        id: appToast
    }

    AppMessageBox {
        id: confirmBox

        // 待执行动作（showTip/showConfirm 前赋值，Accepted/Rejected 后清空）；
        // 非空表示弹窗已开，showConfirm 据此防重复弹出
        property string confirmAction: ""

        // 单按钮纯提示：只显示“确定”，点击仅关闭弹窗不触发任何逻辑
        function showTip(title, text) {
            confirmBox.confirmAction = "messageTip";
            confirmBox.twoButtons = false;
            confirmBox.okText = qsTr("确定");
            confirmBox.show(title, text);
        }

        // 两按钮确认：动作类型 + 标题/内容 + 可选按钮文本（缺省“取消|确定”）
        function showConfirm(action, title, text, ok, cancel) {
            if (confirmBox.confirmAction !== "")
                return; // 已开着（防重复弹出）
            confirmBox.confirmAction = action;
            confirmBox.twoButtons = true;
            confirmBox.okText = ok !== undefined ? ok : qsTr("确定");
            confirmBox.cancelButtonText = cancel !== undefined ? cancel : qsTr("取消");
            confirmBox.show(title, text);
        }

        onAccepted: {
            var action = confirmBox.confirmAction;
            confirmBox.confirmAction = "";
            switch (action) {
            case "messageTip":
                // 纯提示：无逻辑请求，仅关闭弹窗
                break;
            case "setIpSelectAll":
                root.selectAll();
                commandPanel.executeSetIpChecked();
                break;
            case "reboot":
                root.logAction("已确认重启设备: %1 台".arg(root.selectedCount));
                break;
            case "factoryReset":
                root.logAction("已确认恢复出厂设置: %1 台".arg(root.selectedCount));
                break;
            case "tab":
                root.closeLivePreview();
                break;
            case "window":
                root.closeLivePreview();
                root.exitingProgram = true;
                exitWaitTimer.restart();
                break;
            }
        }

        onRejected: {
            confirmBox.confirmAction = "";
        }
    }

    // ===== 升级文件选择框 =====
    // 1) 只筛 *.bin；2) 默认打开上次所在目录, 首次打开默认为“我的文档”
    // 3) selectMultiple 支持一次选多个文件
    AppDialogs.FileDialog {
        id: upgradeFileDialog

        title: qsTr("请选择升级文件")
        selectMultiple: true
        nameFilters: [qsTr("固件文件 (*.bin)"), qsTr("所有文件 (*)")]
        folder: root.lastUpgradeDir !== "" ? ("file:///" + root.lastUpgradeDir.replace(/\\/g, "/")) : shortcuts.home
        onAccepted: {
            var paths = [];
            for (var i = 0; i < upgradeFileDialog.fileUrls.length; i++) paths.push(root.urlToLocalPath(upgradeFileDialog.fileUrls[i]))
            root.upgradeFiles = paths;
            // 记住本次所在目录，下次打开时自动定位
            if (paths.length > 0)
                ConfigureManager.upgradeDir = root.pathDirName(paths[0]);

            root.logAction("已选择升级文件: %1".arg(root.upgradeFileSummary()));
        }
    }

    // ===== 设定IP弹窗 =====
    SetIpDialog {
        id: setIpDialog
    }

    // ===== 设定IP弹窗的探测遮罩 =====
    // 点“确定”后异步探测 IP 占用期间，盖住整个弹窗（含标题栏与关闭按钮）并吞掉鼠标事件。
    AppBusyMask {
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: setIpDialog.width
        height: setIpDialog.height
        z: 1000
        busy: setIpDialog.showMask && setIpDialog.visible
        text: qsTr("正在查询IP占用状态...")
    }

    // ===== 其它设置弹窗的探测遮罩 =====
    // 网络设置面板点“保存”后异步探测 IP 占用期间，盖住整个弹窗（含标题栏与关闭按钮）并吞掉鼠标事件。
    AppBusyMask {
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: otherSettingsDialog.width
        height: otherSettingsDialog.height
        z: 1000
        busy: otherSettingsDialog.showMask && otherSettingsDialog.visible
        text: qsTr("正在查询IP占用状态...")
    }

    // ===== OSD参数共享存储：“OSD修改”弹窗 与 “其它设置-OSD设置”页共用同一份已保存参数 =====
    QtObject {
        id: osdConfig

        property bool setTimeTitle: false
        property int osdDisplayIndex: 0
        property int timeFormatIndex: 0
        property bool showWeek: false
        property int titlePosIndex: 4
        property string titleContent: ""
        property bool saved: false
    }

    // ===== OSD修改弹窗 =====
    SetOsdDialog {
        id: osdDialog
        sharedOsd: osdConfig
    }

    // ===== 其它设置弹窗（由“配置其它参数”按钮触发） =====
    OtherSettingsDialog {
        id: otherSettingsDialog
        sharedOsd: osdConfig
        // 网络设置联动数据源：本机网卡列表 / 主界面选中网卡（null=所有网卡）/ 设备列表第一台设备 IP
        nicList: root.nicList
        selectedNic: root.currentNic()
        firstDeviceIp: deviceModel.rowCount > 0 ? (deviceModel.rows[0]["ip"] || "") : ""
    }

    // ===== 设备搜索遮罩 =====
    AppBusyMask {
        anchors.fill: parent
        z: 100
        busy: root.searching
        text: qsTr("设备搜索中...")
    }

    // ===== 执行多台修改（设定IP）的遮罩 =====
    AppBusyMask {
        anchors.fill: parent
        z: 100
        busy: commandPanel.ipAllocating
        text: qsTr("正在分配空闲IP...")
    }

    // ===== 批量下发其他参数进度遮罩（设备内串行、设备间并行）=====
    BatchProgressMask {
        anchors.fill: parent
        z: 100
        busy: commandPanel.batchRunning
        rows: commandPanel.batchRows
    }

    // ===== 批量下发其他参数结果详情弹窗（全部请求完成后弹出）=====
    BatchResultDialog {
        id: batchResultDialog
        rows: commandPanel.batchRows
    }

    // ===== 退出程序等待定时器 =====
    Timer {
        id: exitWaitTimer

        interval: 50

        onTriggered: {
            // 阻塞等所有拉流线程真实退出再退程序（不是固定延时盲等—Live555 慢退出时进程拆除线程仍在跑会崩）。无任务立即返回
            var ok = DeviceManager.waitForLiveStreamsExit(10 * 1000);
            root.logAction(ok ? "直播线程已全部退出，程序退出"
                              : "等待直播线程退出超时(10s)，兜底退出");
            Qt.quit();
        }
    }

    // ===== 退出程序等待遮罩 =====
    AppBusyMask {
        anchors.fill: parent
        z: 100
        busy: root.exitingProgram
        text: qsTr("正在退出...")
    }

}
