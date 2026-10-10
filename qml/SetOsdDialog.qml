import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import IPCam.Public 1.0
// 项目内封装的通用控件目录
import "Controls"

// OSD修改弹窗：样式与设定IP弹窗保持一致（自绘标题栏 + 白底圆角 + 右下角保存）
// 内容：设定时间和标题开关 + OSD显示/叠加附加信息/时间未知/时间显示格式/标题位置/标题内容
Dialog {
    id: root

    // 统一控件高度
    readonly property int ctrlH: ScreenTools.scaleNum(28)
    // 左侧标签列宽（容纳“标题内容（多行用^分隔）”）
    readonly property int labelWidth: ScreenTools.scaleNum(150)

    width: ScreenTools.scaleNum(560)
    // 两行下拉框（叠加附加信息 / 时间位置）加入后需同步增高，否则内容被 clip 裁掉
    height: ScreenTools.scaleNum(400)
    modal: true
    dim: true
    closePolicy: Popup.CloseOnEscape
    clip: true
    anchors.centerIn: Overlay.overlay
    title: qsTr("OSD修改")
    background: Rectangle {
        radius: ScreenTools.scaleNum(4)
        color: "#FFFFFF"
        border.width: 1
        border.color: "#D8DCE3"
    }

    // 与“其它设置-OSD设置”页共用的参数（由 main.qml 注入）
    property QtObject sharedOsd: null

    // OSD显示选择“禁用”时，除“OSD显示”本身外的所有项整体不可编辑
    readonly property bool osdParamsEnabled: osdDisplayCombo.currentIndex === 0

    // 打开时：已保存过就用共享参数，否则恢复默认值
    onAboutToShow: {
        if (root.sharedOsd && root.sharedOsd.saved)
            root.applyShared();
        else
            root.resetDefaults();
    }

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
            return;
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

    // 屏蔽 Dialog 默认标题栏，使用与设定IP弹窗一致的样式
    header: Item {
        height: ScreenTools.scaleNum(44)
        Rectangle {
            anchors.fill: parent
            color: "#F5F7FA"
            border.width: 0
            radius: ScreenTools.scaleNum(4)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: ScreenTools.scaleNum(16)
            anchors.rightMargin: ScreenTools.scaleNum(4)

            Label {
                Layout.fillWidth: true
                Layout.preferredHeight: ScreenTools.scaleNum(44)
                verticalAlignment: Text.AlignVCenter
                font.bold: true
                font.pointSize: ScreenTools.scaleNum(12, true)
                text: root.title
            }
            AppCloseButton {
                onClicked: root.reject()
            }
        }
    }
    footer: Item {
        height: 0
    }
    // 四周外边距统一 16
    padding: ScreenTools.scaleNum(16)
    // 高度由内容区的隐式高度决定，避免底部按钮被压缩/截断
    contentHeight: contentLayout.implicitHeight

    contentItem: ColumnLayout {
        id: contentLayout

        width: root.availableWidth
        spacing: ScreenTools.scaleNum(12)

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
            // OSD显示“禁用”时整行不可编辑（子控件自动继承 enabled）
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
                model: ["yyyy-mm-dd hh:mm:ss", "yyyy/mm/dd hh:mm:ss", "yy-mm-dd hh:mm:ss", "yy/mm/dd hh:mm:ss",
                        "hh:mm:ss dd/mm/yyyy", "hh:mm:ss dd-mm-yyyy", "hh:mm:ss mm/dd/yyyy", "hh:mm:ss mm-dd-yyyy"]
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
                text: qsTr("标题内容（多行用^分隔）")
            }
            AppTextField {
                id: titleInput
                Layout.fillWidth: true
                // 标题内容默认为空
                text: ""
            }
        }

        // ===== 底部：保存 =====
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: ScreenTools.scaleNum(36)
            // 保证这一行不会被布局压缩掉
            Layout.minimumHeight: ScreenTools.scaleNum(36)
            Layout.topMargin: ScreenTools.scaleNum(4)
            spacing: ScreenTools.scaleNum(16)

            Item {
                Layout.fillWidth: true
            }
            AppButton {
                Layout.preferredHeight: root.ctrlH
                highlighted: true
                text: qsTr("保存")
                onClicked: {
                    // 先同步到共享参数，再关闭，最后打印日志：避免日志/取值出错时把弹窗卡住关不掉
                    root.saveShared();
                    root.accept();
                    // 打印一条带位置信息的日志（console.log 会经由 AppLogger 写入 LogText.txt）
                    console.log(qsTr("OSD修改-保存: ") + JSON.stringify(root.collectConfig()));
                }
            }
            Item {
                Layout.fillWidth: true
            }
        }
    }
}
