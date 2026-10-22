import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import IPCam.Public 1.0

// 用法：
//   BatchResultDialog {
//       id: dialog
//       rows: panel.batchRows
//   }
AppContentDialog {
    id: root

    // 每设备一块：[{uid, ip, header, items: [{name, ok}]}]
    property var rows: []

    width: ScreenTools.scaleNum(440)
    // 动态高度：内容自适应，最低200，最高460（超出可滚动）
    height: Math.min(Math.max(contentCol.implicitHeight + _chromeHeight, 200), 460)
    // 弹窗 chrome：标题栏 + 按钮行 + 内外边距
    readonly property real _chromeHeight: ScreenTools.scaleNum(44) + ScreenTools.scaleNum(16) * 2 + ScreenTools.scaleNum(36) + ScreenTools.scaleNum(4) + ScreenTools.scaleNum(12)

    title: qsTr("设置结果详情")
    okText: qsTr("确定")
    cancelText: ""
    onOkClicked: root.accept()

    // 可滚动的结果列表
    ScrollView {
        id: scrollView
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true

        ScrollBar.vertical: ScrollBar {
            policy: scrollView.contentHeight > scrollView.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        }

        ColumnLayout {
            id: contentCol
            width: scrollView.availableWidth
            spacing: ScreenTools.scaleNum(8)

            Repeater {
                model: root.rows

                ColumnLayout {
                    id: deviceBlock
                    Layout.fillWidth: true
                    spacing: ScreenTools.scaleNum(8)

                    // 展开 model：交错排列 item 和 separator
                    // Flow 逐个放置，item 放不下时整项换行，sep 已留在上一行
                    property var flowModel: {
                        var arr = [];
                        var items = modelData.items;
                        for (var i = 0; i < items.length; i++) {
                            arr.push({"isSep": false, "name": items[i].name, "ok": items[i].ok});
                            if (i < items.length - 1)
                                arr.push({"isSep": true});
                        }
                        return arr;
                    }

                    Label {
                        Layout.fillWidth: true
                        font.family: "Microsoft YaHei"
                        font.pointSize: ScreenTools.scaleNum(10, true)
                        font.bold: true
                        color: "#333333"
                        textFormat: Text.RichText
                        text: (modelData.uid || modelData.header) + " <font color=\"#2F80ED\">[" + (modelData.ip || "") + "]</font>:"
                    }

                    // 结果汇总
                    Flow {
                        Layout.fillWidth: true
                        spacing: ScreenTools.scaleNum(4)

                        Repeater {
                            model: deviceBlock.flowModel

                            Label {
                                font.family: "Microsoft YaHei"
                                font.pointSize: ScreenTools.scaleNum(10, true)
                                color: modelData.isSep ? "#999999" : "#333333"
                                textFormat: modelData.isSep ? Text.PlainText : Text.RichText
                                text: modelData.isSep ? "  |  " : _itemText(modelData)

                                function _itemText(d) {
                                    var c = d.ok ? "#2E7D32" : "#C62828";
                                    var t = d.ok ? qsTr("成功") : qsTr("失败(已跳过)");
                                    return d.name + ": <font color=\"" + c + "\">" + t + "</font>";
                                }
                            }
                        }
                    }

                    // 设备块间灰色分隔线（最后一块不显示）
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: "#E0E0E0"
                        visible: index < root.rows.length - 1
                    }
                }
            }
        }
    }
}
