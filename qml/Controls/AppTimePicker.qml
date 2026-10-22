import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import IPCam.Public 1.0

// 时间选择控件（维护时间等场景使用）：
// 1) 输入框只读，不可手动编辑，只能点击选择
// 2) 点击输入框后，在其正下方弹出“时 / 分 / 秒”三个独立选择器（不遮挡输入框本身）
Item {
    id: tpRoot

    // 当前时间（格式 H:MM:SS）
    property string time: "00:00:00"
    // 输入框宽度 / 控件高度
    property int fieldWidth: ScreenTools.scaleNum(150)
    property int ctrlHeight: ScreenTools.scaleNum(28)

    // 生成 [from, to] 的数字选项（补零显示，便于直接用作数值）
    function rangeModel(from, to) {
        var arr = [];
        for (var i = from; i <= to; i++) arr.push(pad(i))
        return arr;
    }

    function pad(v) {
        return ("0" + v).slice(-2);
    }

    // 把当前时间回填到三个选择器
    function syncFromTime() {
        var m = tpRoot.time.match(/^(\d{1,2}):(\d{1,2}):(\d{1,2})$/);
        var h = m ? parseInt(m[1]) : 0;
        var mi = m ? parseInt(m[2]) : 0;
        var s = m ? parseInt(m[3]) : 0;
        tpHourCombo.currentIndex = h;
        tpMinuteCombo.currentIndex = mi;
        tpSecondCombo.currentIndex = s;
    }

    implicitWidth: fieldWidth
    implicitHeight: ctrlHeight

    AppTextField {
        id: tpField

        anchors.fill: parent
        Layout.preferredWidth: tpRoot.fieldWidth
        Layout.preferredHeight: tpRoot.ctrlHeight
        readOnly: true
        selectByMouse: false
        text: tpRoot.time

        // 点击输入框弹出时间选择面板
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: tpPopup.open()
        }

    }

    Popup {
        id: tpPopup

        // 以输入框为定位父项：弹窗始终出现在输入框正下方，不遮挡输入框内容
        parent: tpField
        x: -(tpPopup.width - parent.width) / 2
        y: tpField.height + ScreenTools.scaleNum(4)
        modal: true
        dim: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: ScreenTools.scaleNum(14)
        // 打开时按当前时间初始化时/分/秒
        onOpened: tpRoot.syncFromTime()

        ColumnLayout {
            spacing: ScreenTools.scaleNum(12)

            RowLayout {
                spacing: ScreenTools.scaleNum(8)

                AppComboBox {
                    id: tpHourCombo

                    Layout.preferredWidth: ScreenTools.scaleNum(80)
                    Layout.preferredHeight: tpRoot.ctrlHeight
                    model: tpRoot.rangeModel(0, 23)
                }

                Label {
                    Layout.preferredHeight: tpRoot.ctrlHeight
                    verticalAlignment: Text.AlignVCenter
                    text: qsTr("时")
                }

                AppComboBox {
                    id: tpMinuteCombo

                    Layout.preferredWidth: ScreenTools.scaleNum(80)
                    Layout.preferredHeight: tpRoot.ctrlHeight
                    model: tpRoot.rangeModel(0, 59)
                }

                Label {
                    Layout.preferredHeight: tpRoot.ctrlHeight
                    verticalAlignment: Text.AlignVCenter
                    text: qsTr("分")
                }

                AppComboBox {
                    id: tpSecondCombo

                    Layout.preferredWidth: ScreenTools.scaleNum(80)
                    Layout.preferredHeight: tpRoot.ctrlHeight
                    model: tpRoot.rangeModel(0, 59)
                }

                Label {
                    Layout.preferredHeight: tpRoot.ctrlHeight
                    verticalAlignment: Text.AlignVCenter
                    text: qsTr("秒")
                }

            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: ScreenTools.scaleNum(8)

                AppButton {
                    Layout.preferredHeight: tpRoot.ctrlHeight
                    text: qsTr("取消")
                    onClicked: tpPopup.close()
                }

                AppButton {
                    Layout.preferredHeight: tpRoot.ctrlHeight
                    highlighted: true
                    text: qsTr("确定")
                    onClicked: {
                        tpRoot.time = tpRoot.pad(tpHourCombo.currentIndex) + ":" + tpRoot.pad(tpMinuteCombo.currentIndex) + ":" + tpRoot.pad(tpSecondCombo.currentIndex);
                        tpPopup.close();
                    }
                }

            }

        }

        background: Rectangle {
            radius: ScreenTools.scaleNum(4)
            color: "#FFFFFF"
            border.width: 1
            border.color: "#DCDCDC"
        }

    }

}
