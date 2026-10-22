import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import IPCam.Public 1.0
// 项目内封装的通用控件目录
import "Controls"

// OSD修改弹窗：内容为设定时间和标题开关 + OSD显示/时间显示格式/标题位置/标题内容
AppContentDialog {
    id: root

    // 统一控件高度
    readonly property int ctrlH: ScreenTools.scaleNum(28)
    // 左侧标签列宽（容纳“标题内容（多行用^分隔）”）
    readonly property int labelWidth: ScreenTools.scaleNum(150)
    // 与“其它设置-OSD设置”页共用的参数（由 main.qml 注入）
    property QtObject sharedOsd: null
    // OSD显示选择“禁用”时，除“OSD显示”本身外的所有项整体不可编辑
    readonly property bool osdParamsEnabled: osdDisplayCombo.currentIndex === 0

    function resetDefaults() {
        timeTitleCheck.checked = false;
        // OSD显示默认启用
        osdDisplayCombo.currentIndex = 0;
        // 时间显示格式默认 yyyy-mm-dd hh:mm:ss
        timeFormatCombo.currentIndex = 0;
        weekCheck.checked = false;
        // 位置默认右下角
        titlePosCombo.currentIndex = 4;
        // 标题内容默认为空
        titleInput.text = "";
    }

    // 从共享参数回填本弹窗（两个界面都有的项）
    function applyShared() {
        var s = root.sharedOsd;
        timeTitleCheck.checked = s.setTimeTitle;
        osdDisplayCombo.currentIndex = s.osdDisplayIndex;
        timeFormatCombo.currentIndex = s.timeFormatIndex;
        weekCheck.checked = s.showWeek;
        titlePosCombo.currentIndex = s.titlePosIndex;
        titleInput.text = s.titleContent;
    }

    // 保存时写回共享参数，供“其它设置-OSD设置”页读取
    function saveShared() {
        if (!root.sharedOsd)
            return ;

        var s = root.sharedOsd;
        s.setTimeTitle = timeTitleCheck.checked;
        s.osdDisplayIndex = osdDisplayCombo.currentIndex;
        s.timeFormatIndex = timeFormatCombo.currentIndex;
        s.showWeek = weekCheck.checked;
        s.titlePosIndex = titlePosCombo.currentIndex;
        s.titleContent = titleInput.text;
        s.saved = true;
    }

    // 汇总当前弹窗内容（后续对接设备指令时使用）
    function collectConfig() {
        return {
            "setTimeAndTitle": timeTitleCheck.checked,
            "osdDisplay": osdDisplayCombo.currentText,
            "timeFormat": timeFormatCombo.currentText,
            "showWeek": weekCheck.checked,
            "titlePosition": titlePosCombo.currentText,
            "titleContent": titleInput.text
        };
    }

    width: ScreenTools.scaleNum(520)
    title: qsTr("OSD修改")
    okText: qsTr("保存")
    cancelText: ""
    // 打开时：已保存过就用共享参数，否则恢复默认值
    onAboutToShow: {
        if (root.sharedOsd && root.sharedOsd.saved)
            root.applyShared();
        else
            root.resetDefaults();
    }

    // 保存按钮
    onOkClicked: {
        root.saveShared();
        // 通知其它设置弹窗把这份数据按协议格式写入 other_settings.json（重启后两边同步显示）
        if (root.sharedOsd)
            root.sharedOsd.osdSavedFromDialog();

        root.accept();
    }

    // ===== 设定时间和标题 =====
    AppCheckBox {
        id: timeTitleCheck
        text: qsTr("设定时间和标题")
        checked: false
        enabled: root.osdParamsEnabled
    }

    // ===== OSD显示 =====
    RowLayout {
        Layout.fillWidth: true
        spacing: ScreenTools.scaleNum(8)

        Label {
            Layout.preferredWidth: root.labelWidth
            Layout.preferredHeight: root.ctrlH
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignRight
            text: qsTr("OSD显示")
        }

        AppComboBox {
            id: osdDisplayCombo

            Layout.fillWidth: true
            Layout.preferredHeight: root.ctrlH
            model: [qsTr("启用"), qsTr("禁用")]
            currentIndex: 0
        }

    }

    // ===== 时间显示格式 + 显示星期 =====
    RowLayout {
        Layout.fillWidth: true
        spacing: ScreenTools.scaleNum(8)
        enabled: root.osdParamsEnabled

        Label {
            Layout.preferredWidth: root.labelWidth
            Layout.preferredHeight: root.ctrlH
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignRight
            text: qsTr("时间显示格式")
        }

        AppComboBox {
            id: timeFormatCombo

            Layout.fillWidth: true
            Layout.preferredHeight: root.ctrlH
            model: ["yyyy-mm-dd hh:mm:ss", "yyyy/mm/dd hh:mm:ss", "yy-mm-dd hh:mm:ss", "yy/mm/dd hh:mm:ss", "hh:mm:ss dd/mm/yyyy", "hh:mm:ss dd-mm-yyyy", "hh:mm:ss mm/dd/yyyy", "hh:mm:ss mm-dd-yyyy"]
            currentIndex: 0
        }

        AppCheckBox {
            id: weekCheck

            text: qsTr("显示星期")
            checked: false
        }

    }

    // ===== 标题位置 =====
    RowLayout {
        Layout.fillWidth: true
        spacing: ScreenTools.scaleNum(8)
        enabled: root.osdParamsEnabled

        Label {
            Layout.preferredWidth: root.labelWidth
            Layout.preferredHeight: root.ctrlH
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignRight
            text: qsTr("标题位置")
        }

        AppComboBox {
            id: titlePosCombo

            Layout.fillWidth: true
            Layout.preferredHeight: root.ctrlH
            model: [qsTr("不显示"), qsTr("左上角"), qsTr("右上角"), qsTr("左下角"), qsTr("右下角")]
            // 默认右下角
            currentIndex: 4
        }

    }

    // ===== 标题内容 =====
    RowLayout {
        Layout.fillWidth: true
        spacing: ScreenTools.scaleNum(8)
        enabled: root.osdParamsEnabled

        Label {
            Layout.preferredWidth: root.labelWidth
            Layout.preferredHeight: root.ctrlH
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignRight
            wrapMode: Text.Wrap
            text: qsTr("标题内容（多行用^分隔）")
        }

        AppTextField {
            id: titleInput
            Layout.fillWidth: true
            text: ""
        }

    }

}
