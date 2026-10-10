import QtQuick 2.15
import QtQuick.Controls 2.15
import IPCam.Public 1.0

// IP 地址输入框：外观是一个整体的 TextField（单个边框），内部为 4 段数字 + 分隔点
// 1) 每段只能输入 0-255 的数字，输入的最终数值大于 255 时强制改为 255
// 2) 输满 3 位数字时自动跳到下一段（并全选）
// 3) 一位/两位数字时，可通过左右方向键在段之间跳转，跳转后全选当前段内容
// 4) 失焦时留空的段补 0
Rectangle {
    id: root

    // 点分十进制字符串，外部赋值即可填充 4 个输入框
    property string value: ""
    // 统一控件高度
    property int ctrlHeight: ScreenTools.scaleNum(30)

    implicitWidth: ScreenTools.scaleNum(220)
    implicitHeight: ctrlHeight
    color: root.enabled ? "#FFFFFF" : "#f0f0f0"
    radius: ScreenTools.scaleNum(4)
    // 整体只有这一个边框，视觉上与普通文本框一致
    border.width: 1
    border.color: e0.activeFocus || e1.activeFocus || e2.activeFocus || e3.activeFocus ? "#2f6fed" : "#767676"

    // 取点分字符串：空段按 0 处理
    function text() {
        var parts = [e0.text, e1.text, e2.text, e3.text];
        for (var i = 0; i < 4; i++) {
            if (parts[i] === "")
                parts[i] = "0";
        }
        return parts.join(".");
    }

    // 按序号取段输入框
    function fieldAt(index) {
        var fields = [e0, e1, e2, e3];
        return (index >= 0 && index < 4) ? fields[index] : null;
    }

    onValueChanged: {
        var parts = value.split(".");
        e0.text = parts.length > 0 ? parts[0] : "";
        e1.text = parts.length > 1 ? parts[1] : "";
        e2.text = parts.length > 2 ? parts[2] : "";
        e3.text = parts.length > 3 ? parts[3] : "";
    }

    // 单段输入框
    component SegField: TextField {
        id: seg

        // 本段序号（0-3）
        property int segIndex: 0

        // 宽度由外层 Row 统一四等分赋值（见下方 segWidth），高度铺满整框
        padding: 0
        // 段内文本水平 + 垂直居中
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        selectByMouse: true
        maximumLength: 3
        font.family: "Microsoft YaHei"
        font.pointSize: ScreenTools.scaleNum(10, true)
        // 只允许数字，最多 3 位；大于 255 的处理在 onTextEdited 中强制改写
        validator: RegularExpressionValidator {
            regularExpression: /[0-9]{0,3}/
        }
        // 段输入框自身不带边框，整体外观由外层 Rectangle 提供
        background: Item {
        }

        function jumpTo(offset) {
            var target = root.fieldAt(seg.segIndex + offset);
            if (target) {
                target.forceActiveFocus();
                // 跳转后全选当前段内容，直接输入即可覆盖
                target.selectAll();
            }
        }

        onTextEdited: {
            // 最终输入的数值大于 255 时强制改成 255
            if (text !== "" && parseInt(text, 10) > 255) {
                text = "255";
                cursorPosition = text.length;
            }
            // 满 3 位自动跳到下一段
            if (text.length === 3)
                jumpTo(1);
        }
        Keys.onLeftPressed: {
            // 光标在段首时向左跳到上一段
            if (cursorPosition === 0) {
                jumpTo(-1);
                event.accepted = true;
            }
        }
        Keys.onRightPressed: {
            // 光标在段尾时向右跳到下一段（一位/两位数字即可跳转）
            if (cursorPosition === text.length) {
                jumpTo(1);
                event.accepted = true;
            }
        }
        // 注意：不能用 Keys.onBackspacePressed，Qt 5.15.2 下该信号处理器会在
        // QML 加载时触发 QVector<T>::at "index out of range" 断言崩溃，
        // 需改用通用 onPressed 自行判断键值
        Keys.onPressed: {
            // 段内为空时退格跳到上一段（全选，可直接覆盖输入）
            if (event.key === Qt.Key_Backspace && text === "") {
                jumpTo(-1);
                event.accepted = true;
            }
        }
        onActiveFocusChanged: {
            // 离开时留空的段补 0
            if (!activeFocus && text === "")
                text = "0";
        }
    }

    Row {
        id: segRow

        anchors.fill: parent
        anchors.leftMargin: ScreenTools.scaleNum(8)
        anchors.rightMargin: ScreenTools.scaleNum(8)
        spacing: 0

        // 分隔点宽度
        readonly property int dotWidth: ScreenTools.scaleNum(8)
        // 4 段等宽：可用宽度减去 3 个分隔点后四等分（不依赖布局引擎的分配策略）
        readonly property int segWidth: Math.max(ScreenTools.scaleNum(20), (segRow.width - 3 * segRow.dotWidth) / 4)

        SegField {
            id: e0
            width: segRow.segWidth
            height: segRow.height
            segIndex: 0
        }
        Label {
            width: segRow.dotWidth
            height: segRow.height
            text: "."
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.family: "Microsoft YaHei"
            font.pointSize: ScreenTools.scaleNum(10, true)
        }
        SegField {
            id: e1
            width: segRow.segWidth
            height: segRow.height
            segIndex: 1
        }
        Label {
            width: segRow.dotWidth
            height: segRow.height
            text: "."
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.family: "Microsoft YaHei"
            font.pointSize: ScreenTools.scaleNum(10, true)
        }
        SegField {
            id: e2
            width: segRow.segWidth
            height: segRow.height
            segIndex: 2
        }
        Label {
            width: segRow.dotWidth
            height: segRow.height
            text: "."
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.family: "Microsoft YaHei"
            font.pointSize: ScreenTools.scaleNum(10, true)
        }
        SegField {
            id: e3
            width: segRow.segWidth
            height: segRow.height
            segIndex: 3
        }
    }
}
