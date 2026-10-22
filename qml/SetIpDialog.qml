import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import IPCam.Public 1.0
// 项目内封装的通用控件目录
import "Controls"

// 设定IP弹窗
AppContentDialog {
    id: root

    // 统一控件高度
    readonly property int ctrlH: ScreenTools.scaleNum(28)
    // 左侧标签列宽（保证各行的输入框左对齐）
    readonly property int labelWidth: ScreenTools.scaleNum(80)
    // 网卡信息列表（ScreenTools::getNetworkInterfaces() 的返回值）
    property var nicList: []
    // 遮罩显隐（供使用处 main.qml 里挂在 Overlay 层的 AppBusyMask 绑定）
    property bool showMask: false
    // 正在异步探测占用的 IP：请求/响应用它匹配，防止过期响应串扰
    property string pendingIp: ""
    // 上次成功应用（发送修改请求）时填写的参数：{nic, ip, netmask, gateway}
    // null = 从未成功应用过；再次打开且网卡未变时恢复该值，切换网卡则强制带出网卡地址。
    // 仅成功分支保存：IP 被占用时不保存，下次打开显示更早成功的值或网卡默认值
    property var savedParams: null

    function refreshNics() {
        nicList = ScreenTools.getNetworkInterfaces();
    }

    function currentNic() {
        if (nicCombo.currentIndex < 0 || nicCombo.currentIndex >= nicList.length)
            return null;

        return nicList[nicCombo.currentIndex];
    }

    // 把选中网卡的 IP / 掩码 / 网关填入输入框
    function applyNic() {
        var nic = currentNic();
        if (!nic) {
            ipInput.value = "";
            maskInput.value = "";
            gwInput.value = "0.0.0.0";
            return ;
        }
        var ipv4 = nic["ipv4"] || [];
        // 网关获取不到时显示默认值
        var gw = nic["gateway"] || "";
        ipInput.value = ipv4.length > 0 ? ipv4[0] : "";
        maskInput.value = nic["netmask"] || "";
        gwInput.value = gw.length > 0 ? gw : "0.0.0.0";
    }

    width: ScreenTools.scaleNum(460)
    title: qsTr("设置IP")
    okText: qsTr("确定")
    // 每次打开时刷新网卡列表；上次成功应用过且网卡还在时恢复上次填写的值
    // （IP 被占用/取消则不保存新值，恢复的是更早成功的值），否则带出网卡地址
    onAboutToShow: {
        refreshNics();
        var restored = false;
        if (root.savedParams !== null) {
            // 按网卡名找上次应用时的网卡：找不到（网卡已拔掉等）则回退网卡默认值
            for (var i = 0; i < nicList.length; i++) {
                if (nicList[i]["displayName"] === root.savedParams["nic"]) {
                    // 先选中该网卡（可能触发 applyNic 带出网卡值），再覆盖为保存的值
                    nicCombo.currentIndex = i;
                    ipInput.value = root.savedParams["ip"];
                    maskInput.value = root.savedParams["netmask"];
                    gwInput.value = root.savedParams["gateway"];
                    restored = true;
                    break;
                }
            }
        }
        if (!restored)
            applyNic();
        // 复位上次可能残留的探测状态（过期响应由 pendingIp 匹配兜底）
        root.pendingIp = "";
        root.showMask = false;
    }

    // 确定按钮：先开遮罩再异步探测
    onOkClicked: {
        root.pendingIp = ipInput.text();
        root.showMask = true;
        ScreenTools.checkIpOccupiedAsync(root.pendingIp);
    }

    // 取消按钮：直接关闭
    onCancelClicked: root.reject()

    // IP 占用提示弹窗
    AppMessageBox {
        id: tipBox
    }

    // 4 段式 IP 输入框（如 192.168.5.205），交互细节见 AppIpInput.qml
    component IpInput: AppIpInput {
        ctrlHeight: root.ctrlH
    }

    // ===== 顶部：修改IP起始地址 / 批量修改设定IP =====
    RowLayout {
        Layout.fillWidth: true
        spacing: ScreenTools.scaleNum(24)

        AppCheckBox {
            id: startAddrCheck

            text: qsTr("修改IP起始地址")
            checked: false
            // 与“批量修改设定IP”互斥：勾选本项时取消另一项（两者可同时不勾选）
            onCheckedChanged: {
                if (checked) {
                    batchCheck.checked = false;
                }
            }
        }

        Item {
            Layout.fillWidth: true
        }

        AppCheckBox {
            id: batchCheck

            text: qsTr("批量修改设定IP")
            checked: false
            visible: false
            // 与“修改IP起始地址”互斥：勾选本项时取消另一项（两者可同时不勾选）
            onCheckedChanged: {
                if (checked) {
                    startAddrCheck.checked = false;
                }
            }
        }

    }

    // ===== 网卡 =====
    RowLayout {
        Layout.fillWidth: true
        spacing: ScreenTools.scaleNum(8)

        Label {
            Layout.preferredWidth: root.labelWidth
            Layout.preferredHeight: root.ctrlH
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignLeft
            text: qsTr("网卡")
        }

        AppComboBox {
            id: nicCombo

            Layout.fillWidth: true
            Layout.preferredHeight: root.ctrlH
            textRole: "displayName"
            model: root.nicList
            displayText: currentIndex >= 0 ? currentText : qsTr("未检测到网卡")
            onCurrentIndexChanged: root.applyNic()
        }

    }

    // ===== IP =====
    RowLayout {
        Layout.fillWidth: true
        spacing: ScreenTools.scaleNum(8)

        Label {
            Layout.preferredWidth: root.labelWidth
            Layout.preferredHeight: root.ctrlH
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignLeft
            text: "IP"
        }

        IpInput {
            id: ipInput

            Layout.fillWidth: true
        }

    }

    // ===== 子网掩码 =====
    RowLayout {
        Layout.fillWidth: true
        spacing: ScreenTools.scaleNum(8)

        Label {
            Layout.preferredWidth: root.labelWidth
            Layout.preferredHeight: root.ctrlH
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignLeft
            text: qsTr("子网掩码")
        }

        IpInput {
            id: maskInput

            Layout.fillWidth: true
        }

    }

    // ===== 网关 =====
    RowLayout {
        Layout.fillWidth: true
        spacing: ScreenTools.scaleNum(8)

        Label {
            Layout.preferredWidth: root.labelWidth
            Layout.preferredHeight: root.ctrlH
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignLeft
            text: qsTr("网关")
        }

        IpInput {
            id: gwInput

            Layout.fillWidth: true
        }

    }

    // 探测期间的遮罩（AppBusyMask）声明在使用处 main.qml

    // ===== 异步探测 IP 占用的结果处理 =====
    // 后台线程探测完成后经 ScreenTools.signalIpOccupied 回到这里；
    // 用 pendingIp 匹配本次请求，弹窗已关闭（用户取消）时忽略过期响应
    Connections {
        target: ScreenTools

        function onSignalIpOccupied(ip, occupied) {
            if (!root.visible || ip !== root.pendingIp)
                return ;

            root.showMask = false;
            root.pendingIp = "";
            if (occupied) {
                // 目标 IP 已被占用：弹窗提示后留在本弹窗继续修改
                tipBox.show(qsTr("温馨提示"), qsTr("目标IP地址已被占用, 请输入处于空闲状态的IP地址"));
            } else {
                // 请求将发送：先记住本次填写的参数（含网卡名），下次打开且未换网卡时恢复
                var nic = root.currentNic();
                root.savedParams = {
                    "nic": nic ? nic["displayName"] : "",
                    "ip": ipInput.text(),
                    "netmask": maskInput.text(),
                    "gateway": gwInput.text()
                };
                tipBox.show(qsTr("温馨提示"), qsTr("设备IP设置成功, 执行修改后生效"));

                // 参数已保存（供主界面“执行修改”下发），关闭窗口
                root.accept()
            }
        }

    }

}
