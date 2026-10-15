import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import IPCam.Public 1.0
// 项目内封装的通用控件目录（AppButton / AppCheckBox 等）
import "Controls"

// 操作指令面板：设备列表页右侧 1/4 的批量操作指令集合。
ColumnLayout {
    id: panel

    // ===== 宿主注入的共享资源（QML id 不跨文件，实例化时传对象进来）=====
    // 主窗口：logAction 等宿主函数
    property var host
    // 全工程唯一确认/提示框（AppMessageBox 实例）
    property var confirmBox
    // 三个指令弹窗实例（由 main.qml 声明并注入）
    property var setIpDialog
    property var osdDialog
    property var otherSettingsDialog
    // 设备列表状态：搜索中 / 已勾选数 / 表格设备总数
    property bool searching: false
    property int selectedCount: 0
    property int deviceCount: 0
    // 统一控件高度（与 main.qml 的 controlHeight 同源）
    property int controlHeight: 30

    // ===== 上抛信号（面板入口，main.qml 连接实现）=====
    // “设备搜索”：搜索会清空表格/勾选并读“系统配置-搜索时间”，留在 main.qml
    signal searchRequested()
    // “播放勾选设备”：直播预览切换页签并合并播放列表，留在 main.qml
    signal livePreviewRequested()

    // ===== “执行修改（设定IP）”：按勾选数量给勾选设备下发新 IP =====
    property bool ipAllocating: false
    // 本次分配请求的起始 IP：响应靠它匹配，防止过期响应串扰
    property string ipAllocatingBaseIp: ""

    // 设备操作前置校验：列表为空或没勾选任何设备时提示，返回 false 表示中断
    function ensureDeviceSelected() {
        if (panel.deviceCount === 0 || panel.selectedCount === 0) {
            confirmBox.showTip(qsTr("温馨提示"), qsTr("请先选择设备"));
            return false;
        }
        return true;
    }

    // 下发修改 IP 请求：勾选设备（uid 升序，与 ips 下标一一配对）
    // TODO: 接入真实下发协议（当前先记日志记录配对结果，设备响应后由后续版本处理）
    function sendSetIpRequests(ips) {
        var devices = DeviceManager.checkedDevices();
        for (var i = 0; i < devices.length; i++) {
            var id = devices[i]["uid"] || devices[i]["cloudId"] || devices[i]["mac"] || devices[i]["ip"] || "";
            host.logAction("发送修改IP请求: 设备ID=%1, 新IP=%2".arg(id).arg(ips[i]));
        }
    }

    // “执行修改”点击入口：没设IP先提示；没勾选时列表为空直接提示，
    // 有设备则弹“是|否”确认是否全选（是→全选并继续）；已勾选直接执行。
    // 1 台直接下发弹窗保存的 IP；多台从该 IP 起凑等量空闲 IP（末段叠加
    // 到 .254，不足再递减到 .1）后逐台下发
    function executeSetIp() {
        if (setIpDialog.savedParams === null) {
            confirmBox.showTip(qsTr("温馨提示"), qsTr("请先在[设定IP]中设定IP地址"));
            return ;
        }
        // 列表为空没有可全选的设备，维持单按钮提示
        if (panel.deviceCount === 0) {
            confirmBox.showTip(qsTr("温馨提示"), qsTr("请先选择设备"));
            return ;
        }
        // 没勾选任何设备：询问是否全选（是|否），点是走全选后继续
        if (panel.selectedCount === 0) {
            confirmBox.showConfirm("setIpSelectAll", qsTr("温馨提示"), qsTr("请先选择设备, 是否选择所有设备?"), qsTr("是"), qsTr("否"));
            return ;
        }
        panel.executeSetIpChecked();
    }

    // 修改IP执行主体：勾选与 IP 均已就绪，按台数分流。
    // 供本面板“执行修改”与 main.qml 的“是→全选”确认框共用
    function executeSetIpChecked() {
        var baseIp = setIpDialog.savedParams["ip"];
        if (panel.selectedCount === 1) {
            // 单台：直接发送该设备 id 与设定IP里的地址
            sendSetIpRequests([baseIp]);
            confirmBox.showTip(qsTr("温馨提示"), qsTr("修改IP地址请求已发送, 请等待设备响应"));
        } else {
            // 多台：先开遮罩再异步凑空闲 IP，结果在下方 Connections 处理
            panel.ipAllocatingBaseIp = baseIp;
            panel.ipAllocating = true;
            ScreenTools.findFreeIpsAsync(baseIp, panel.selectedCount);
        }
    }

    // “执行修改（设定IP）”勾选多台时 findFreeIpsAsync 的结果：凑满等量空闲 IP 后逐台配对下发
    Connections {
        function onSignalFreeIpsFound(baseIp, wanted, freeIps) {
            if (!panel.ipAllocating || baseIp !== panel.ipAllocatingBaseIp)
                return ;

            panel.ipAllocating = false;
            panel.ipAllocatingBaseIp = "";
            if (freeIps.length < wanted) {
                // 网段内空闲 IP 不够：提示后中断，可换起始 IP 重试
                confirmBox.showTip(qsTr("温馨提示"), qsTr("网段内空闲IP不足(需%1个, 只找到%2个), 请调整起始IP").arg(wanted).arg(freeIps.length));
                return ;
            }
            panel.sendSetIpRequests(freeIps);
            confirmBox.showTip(qsTr("温馨提示"), qsTr("批量修改IP请求已发送, 请等待设备响应"));
        }

        target: ScreenTools
    }

    // ===== 面板 UI =====
    Label {
        Layout.preferredHeight: panel.controlHeight
        verticalAlignment: Text.AlignVCenter
        text: qsTr("操作指令")
    }

    AppButton {
        Layout.fillWidth: true
        text: panel.searching ? qsTr("搜索中...") : qsTr("设备搜索")
        enabled: !panel.searching
        onClicked: {
            host.logAction("我点击了%1按钮".arg("设备搜索"));
            panel.searchRequested();
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: ScreenTools.scaleNum(6)

        AppButton {
            Layout.fillWidth: true
            text: qsTr("设定IP")
            onClicked: {
                host.logAction("我点击了%1按钮".arg(text));
                setIpDialog.open();
            }
        }

        AppButton {
            Layout.fillWidth: true
            text: qsTr("执行修改")
            onClicked: {
                host.logAction("我点击了%1按钮（设定IP）".arg(text));
                panel.executeSetIp();
            }
        }

    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: ScreenTools.scaleNum(16)
    }

    AppButton {
        Layout.fillWidth: true
        text: qsTr("同步时间")
        onClicked: {
            host.logAction("我点击了%1按钮".arg(text));
            panel.ensureDeviceSelected();
        }
    }

    AppButton {
        Layout.fillWidth: true
        text: qsTr("重启设备")
        onClicked: {
            host.logAction("我点击了%1按钮".arg(text));
            if (!panel.ensureDeviceSelected())
                return ;
            confirmBox.showConfirm("reboot", qsTr("温馨提示"), qsTr("确定要重启已勾选的设备吗?"));
        }
    }

    AppButton {
        Layout.fillWidth: true
        text: qsTr("恢复出厂设置")
        onClicked: {
            host.logAction("我点击了%1按钮".arg(text));
            if (!panel.ensureDeviceSelected())
                return ;
            confirmBox.showConfirm("factoryReset", qsTr("温馨提示"), qsTr("恢复出厂设置后设备会重启且设备IP可能变更, 需要重新搜索设备, 确定要对已勾选的设备执行该操作吗?"));
        }
    }

    AppButton {
        Layout.fillWidth: true
        text: qsTr("播放勾选设备")
        onClicked: {
            host.logAction("我点击了%1按钮".arg(text));
            if (!panel.ensureDeviceSelected())
                return ;

            panel.livePreviewRequested();
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: ScreenTools.scaleNum(16)
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: ScreenTools.scaleNum(6)

        AppButton {
            Layout.fillWidth: true
            text: qsTr("设定OSD")
            onClicked: {
                host.logAction("我点击了%1按钮".arg(text));
                osdDialog.open();
            }
        }

        AppButton {
            Layout.fillWidth: true
            text: qsTr("执行修改")
            onClicked: {
                host.logAction("我点击了%1按钮（设定OSD）".arg(text));
                panel.ensureDeviceSelected();
            }
        }

    }

    AppCheckBox {
        Layout.preferredHeight: panel.controlHeight
        text: qsTr("锁定默认参数")
        onToggled: host.logAction("%1已%2".arg(text).arg(checked ? "勾选" : "取消勾选"))
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: ScreenTools.scaleNum(6)

        AppButton {
            Layout.fillWidth: true
            text: qsTr("配置其他参数")
            onClicked: {
                host.logAction("我点击了%1按钮".arg(text));
                otherSettingsDialog.open();
            }
        }

        AppButton {
            Layout.fillWidth: true
            text: qsTr("执行修改")
            onClicked: {
                host.logAction("我点击了%1按钮（配置其他参数）".arg(text));
                panel.ensureDeviceSelected();
            }
        }

    }

    Item {
        Layout.fillHeight: true
        Layout.minimumHeight: 0
    }

}
