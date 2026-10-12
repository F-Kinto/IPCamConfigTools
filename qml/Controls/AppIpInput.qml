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

    // 外部把焦点定位到指定段（0-3）并全选该段内容
    function focusField(index) {
        var f = fieldAt(index);
        if (f) {
            f.forceActiveFocus();
            f.selectAll();
        }
    }

    implicitWidth: ScreenTools.scaleNum(220)
    implicitHeight: ctrlHeight
    color: root.enabled ? "#FFFFFF" : "#f0f0f0"
    radius: ScreenTools.scaleNum(4)
    // 整体只有这一个边框，视觉上与普通文本框一致
    border.width: 1
    border.color: e0.activeFocus || e1.activeFocus || e2.activeFocus || e3.activeFocus ? "#2f6fed" : "#DCDCDC"
    onValueChanged: {
        var parts = value.split(".");
        e0.text = parts.length > 0 ? parts[0] : "";
        e1.text = parts.length > 1 ? parts[1] : "";
        e2.text = parts.length > 2 ? parts[2] : "";
        e3.text = parts.length > 3 ? parts[3] : "";
    }

    Row {
        id: segRow

        // 分隔点宽度
        readonly property int dotWidth: ScreenTools.scaleNum(8)
        // 4 段等宽：可用宽度减去 3 个分隔点后四等分（不依赖布局引擎的分配策略）
        readonly property int segWidth: Math.max(ScreenTools.scaleNum(20), (segRow.width - 3 * segRow.dotWidth) / 4)

        anchors.fill: parent
        anchors.leftMargin: ScreenTools.scaleNum(8)
        anchors.rightMargin: ScreenTools.scaleNum(8)
        spacing: 0

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

    // 单段输入框
    component SegField: TextField {
        id: seg

        // 本段序号（0-3）
        property int segIndex: 0

        function jumpTo(offset) {
            var target = root.fieldAt(seg.segIndex + offset);
            if (target) {
                target.forceActiveFocus();
                // 跳转后全选当前段内容，直接输入即可覆盖
                target.selectAll();
            }
        }

        // Up/Down 方向键调整当前段数值（0-255，越界夹紧）
        function adjustValue(delta) {
            var v = (seg.text === "") ? 0 : parseInt(seg.text, 10);
            if (isNaN(v))
                v = 0;

            v = Math.min(255, Math.max(0, v + delta));
            seg.text = String(v);
            // 改完后全选，便于直接输入覆盖
            seg.selectAll();
        }

        // 宽度由外层 Row 统一四等分赋值（见下方 segWidth），高度铺满整框
        padding: 0
        // 段内文本水平 + 垂直居中
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        selectByMouse: true
        maximumLength: 3
        font.family: "Microsoft YaHei"
        font.pointSize: ScreenTools.scaleNum(10, true)
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
        // 按键统一在 onPressed 里处理。
        // 注意：QKeyEvent 默认 accepted=true，挂在 Keys 上的处理器若不显式放行
        // （event.accepted = false），事件就被 Keys 附加属性拦下，TextField 原生的
        // 方向键/编辑行为（段内移动光标、取消全选、退格删除）会全部失效
        Keys.onPressed: {
            switch (event.key) {
            case Qt.Key_Left:
                // 段首（且无选中）向左跳到上一段
                if (seg.selectionStart === seg.selectionEnd && seg.cursorPosition === 0) {
                    jumpTo(-1);
                    event.accepted = true;
                } else {
                    event.accepted = false; // 交给原生：段内移动 / 取消全选
                }
                break;
            case Qt.Key_Right:
                // 段尾（且无选中）向右跳到下一段
                if (seg.selectionStart === seg.selectionEnd && seg.cursorPosition === seg.text.length) {
                    jumpTo(1);
                    event.accepted = true;
                } else {
                    event.accepted = false; // 交给原生：段内移动 / 取消全选
                }
                break;
            case Qt.Key_Up:
                adjustValue(1);
                event.accepted = true;
                break;
            case Qt.Key_Down:
                adjustValue(-1);
                event.accepted = true;
                break;
            case Qt.Key_Backspace:
                // 段内为空时退格跳到上一段（全选，可直接覆盖输入）
                // 注意：不能用 Keys.onBackspacePressed，Qt 5.15.2 下会触发断言崩溃
                if (seg.text === "") {
                    jumpTo(-1);
                    event.accepted = true;
                } else {
                    event.accepted = false; // 交给原生删除
                }
                break;
            default:
                event.accepted = false; // 其余按键全部交还 TextField 原生处理
                break;
            }
        }
        onActiveFocusChanged: {
            // 离开时留空的段补 0
            if (!activeFocus && text === "")
                text = "0";

        }

        // 只允许数字，最多 3 位；大于 255 的处理在 onTextEdited 中强制改写
        validator: RegularExpressionValidator {
            regularExpression: /[0-9]{0,3}/
        }

        // 段输入框自身不带边框，整体外观由外层 Rectangle 提供
        background: Item {
        }

    }

}
