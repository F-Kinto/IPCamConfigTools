import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import IPCam.Public 1.0

// 设备命令结果弹窗：顶部汇总行 + 逐台结果明细（ListView），文本左对齐、垂直居中
// 每条明细：uid [蓝色ip]: <绿色/红色>动作结果</>
// 条目间灰色 Rectangle 分隔线（与顶部汇总分隔线等宽）
// 用法：
//   DeviceCmdResultBox { id: cmdResultBox }
//   cmdResultBox.showResult("设备重启", "总共2台设备, 成功1台, 失败1台", [{uid,ip,ok,actionName}, ...])
AppContentDialog {
    id: root

    property string summaryText: ""
    property var resultRows: []

    width: ScreenTools.scaleNum(460)
    height: Math.max(implicitHeight, ScreenTools.scaleNum(220))
    okText: qsTr("确定")
    cancelText: ""

    function showResult(title, summary, rows) {
        root.title = title;
        root.summaryText = summary;
        root.resultRows = rows;
        root.open();
    }

    onOkClicked: root.accept()

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: ScreenTools.scaleNum(8)

        // 顶部汇总行
        Label {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignLeft
            font.family: "Microsoft YaHei"
            font.bold: true
            font.pointSize: ScreenTools.scaleNum(10, true)
            color: "#333333"
            wrapMode: Text.WrapAnywhere
            text: root.summaryText
        }

        // 分隔线
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: "#E0E0E0"
        }

        // 逐台结果明细（最多显示6条，超出可滚动）
        ListView {
            id: detailList
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: Math.min(contentHeight, _maxVisibleHeight)
            Layout.maximumHeight: _maxVisibleHeight
            clip: true
            interactive: contentHeight > _maxVisibleHeight
            spacing: ScreenTools.scaleNum(10)
            model: root.resultRows

            // 6 条结果的可视高度
            readonly property real _maxVisibleHeight: ScreenTools.scaleNum(6) * ScreenTools.scaleNum(35)

            ScrollBar.vertical: ScrollBar {
                policy: detailList.contentHeight > detailList._maxVisibleHeight ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            }

            delegate: Column {
                width: detailList.width
                spacing: ScreenTools.scaleNum(10)

                // 结果行（RichText：IP 蓝色、动作结果绿色/红色）
                Label {
                    width: parent.width
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignLeft
                    font.family: "Microsoft YaHei"
                    font.bold: false
                    font.pointSize: ScreenTools.scaleNum(10, true)
                    color: "#333333"
                    wrapMode: Text.WrapAnywhere
                    textFormat: Text.RichText
                    text: {
                        var r = modelData;
                        var lineColor = r.ok ? "#27AE60" : "#E74C3C";
                        var tag = r.ok ? qsTr("成功") : qsTr("失败");
                        return r.uid + " <font color=\"#2F80ED\">[" + r.ip + "]</font>: <font color=\"" + lineColor + "\">" + r.actionName + tag + "</font>";
                    }
                }

                // 灰色分隔线（最后一条不显示）
                Rectangle {
                    width: parent.width
                    height: 1
                    color: "#E0E0E0"
                    visible: index < detailList.count - 1
                }
            }
        }
    }
}
