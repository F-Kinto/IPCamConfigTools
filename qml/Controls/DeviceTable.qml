import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import IPCam.Public 1.0

// 设备信息表格：表头列宽通过属性控制，支持「拉伸」与「固定长度」两种模式。
Rectangle {
    id: root

    // true : 允许鼠标拖拽表头分割线调整列宽
    // false: 禁止拖拽调整
    property bool resizable: true
    // true : 列宽按可用宽度与 stretchFactors 权重自动分配，所有列压缩进可视区
    // false: 使用 fixedWidths 指定的固定列宽，超出可视区域时表格横向滚动
    property bool stretchToFill: false
    // true : 固定列宽模式下最后一列弹性伸缩——可视区有富余时吃掉剩余宽度（表格铺满，无右侧余白），
    //        空间不足时保持设计固定宽（内容显示完全，由横向滚动条负责查看）；
    //        窗口尺寸变化时只重算最后一列，其余列保持固定/手动拖拽的宽度
    property bool lastColumnFills: false
    // 列标题
    property var titles: []
    // resizable 为 false 时使用的固定列宽
    property var fixedWidths: [ScreenTools.scaleNum(130), ScreenTools.scaleNum(110), ScreenTools.scaleNum(90), ScreenTools.scaleNum(120), ScreenTools.scaleNum(171), ScreenTools.scaleNum(171), ScreenTools.scaleNum(120), ScreenTools.scaleNum(140), ScreenTools.scaleNum(140), ScreenTools.scaleNum(110)]
    // resizable 为 true 时使用的拉伸权重
    property var stretchFactors: [1.1, 1, 0.9, 1.1, 1.3, 1.3, 1.1, 1.2, 1.2, 1.1]
    // 单列最小宽度，拖拽与自动分配时都会遵守
    property real minColumnWidth: ScreenTools.scaleNum(60)
    property int headerHeight: ScreenTools.scaleNum(45)
    property int rowHeight: ScreenTools.scaleNum(30)
    property color lineColor: "#d0d0d0"
    property color headerColor: "#f5f5f5"
    // 单数行背景色（第 1、3、5... 行）
    property color oddRowColor: "white"
    // 双数行背景色（第 2、4、6... 行）
    property color evenRowColor: "#f2f2f2"
    // 无数据时是否在可视区域铺满空行
    property bool showEmptyRows: true
    // 当前是否无数据
    readonly property bool tableEmpty: (typeof tableView.rows === "number") ? tableView.rows === 0 : true
    // 统一字体（微软雅黑 10pt）
    property font labelFont: Qt.font({
        "family": "Microsoft YaHei",
        "pointSize": ScreenTools.scaleNum(10, true)
    })
    // 表头字体（微软雅黑 10pt 加粗）
    property font headerFont: Qt.font({
        "family": "Microsoft YaHei",
        "pointSize": ScreenTools.scaleNum(10, true),
        "bold": true
    })
    // ===== 行选中（单选）=====
    // 当前选中的行号，-1 表示没有选中。
    // 注意：与“复选框勾选（checkedRows，可多选）”是两套独立状态 ——
    // 勾选决定要对哪些设备执行操作，选中只是高亮当前这一条
    property int currentRow: -1
    // 选中行的背景色（浅蓝）
    property color currentRowColor: "#D6EAFF"
    // ===== 排序 =====
    // 是否允许点击表头排序
    property bool sortEnabled: true
    // 排序所用字段名数组，顺序与 titles 对应（与调用方 TableModelColumn 的 display 一致）
    // 为空则不参与排序
    property var columnRoles: []
    // 当前排序列 / 方向（-1 表示未排序）
    property int sortColumn: -1
    property bool sortAscending: true
    // 当前处于选中状态的单元格（TextEdit，用于长按拖选 / 单击取消选中）
    property var selectedCell: null
    // 需要显示“复选框 + 文本”的列号（默认 -1 表示不显示）；设备列表传 0，即 IP 列
    property int checkBoxColumn: -1
    // 已勾选的行号列表：由调用方维护（与主界面“已选数量”是同一份数据）
    property var checkedRows: []
    property alias model: tableView.model
    // 当前实际列宽（表头与单元格共用，保证对齐）
    readonly property alias columnWidths: internal.widths
    readonly property real totalWidth: {
        var sum = 0;
        for (var i = 0; i < internal.widths.length; ++i) {
            sum += internal.widths[i];
        }
        return sum;
    }
    // 是否已经手动拖拽调整过列宽
    property bool userResized: false

    // 排序后行号发生变化：indexMap[旧行号] = 新行号，供调用方同步“已选行”
    signal rowsReordered(var indexMap)
    // 行勾选状态变化（参数：行号、是否勾选）
    signal rowChecked(int row, bool checked)
    // 行被双击（参数：行号）—— 行为由调用方定义（如打开该行设备的直播）
    signal rowDoubleClicked(int row)

    // 指定行是否为当前选中行（空数据占位行时 row 未定义，故需防一手）
    function isCurrentRow(row) {
        return typeof row !== "undefined" && row === root.currentRow;
    }

    // 选中某一行：单条数据场景下重复点击同一行保持选中
    function selectRow(row) {
        if (typeof row === "undefined" || row < 0)
            return ;

        root.currentRow = row;
    }

    // 按字符 ASCII 码比较两个字符串（逐字符比较 charCodeAt，纯 ASCII 场景与字典序一致）
    function compareAscii(a, b) {
        var sa = (a === undefined || a === null) ? "" : String(a);
        var sb = (b === undefined || b === null) ? "" : String(b);
        var n = Math.min(sa.length, sb.length);
        for (var i = 0; i < n; i++) {
            if (sa.charCodeAt(i) !== sb.charCodeAt(i))
                return sa.charCodeAt(i) - sb.charCodeAt(i);

        }
        return sa.length - sb.length;
    }

    // 点击表头排序：同一列再次点击切换升/降序，换列则重新升序
    function sortByColumn(col) {
        if (!root.sortEnabled)
            return ;

        var model = tableView.model;
        if (!model || model.rows === undefined || !model.rows || model.rows.length === 0)
            return ;

        var role = root.columnRoles[col];
        if (role === undefined || role === "")
            return ;

        var asc = (root.sortColumn === col) ? !root.sortAscending : true;
        // 带上原行号一起排序，排完后得到“旧行号 -> 新行号”的映射
        var decorated = [];
        for (var i = 0; i < model.rows.length; i++) decorated.push({
            "oldIndex": i,
            "data": model.rows[i]
        })
        decorated.sort(function(x, y) {
            return asc ? root.compareAscii(x.data[role], y.data[role]) : root.compareAscii(y.data[role], x.data[role]);
        });
        var newRows = [];
        var indexMap = {
        };
        for (var j = 0; j < decorated.length; j++) {
            newRows.push(decorated[j].data);
            indexMap[decorated[j].oldIndex] = j;
        }
        root.sortColumn = col;
        root.sortAscending = asc;
        // 行序变了，先取消单元格选中（旧单元格对象会被 TableView 回收）
        root.deselectAll();
        // 先把新数据写回模型，再换算选中行号：
        // 顺序反了会让外部按“新行号”去读“旧数据”，取到别的设备
        model.rows = newRows;
        tableView.forceLayout();
        // 选中行跟着设备走：按映射换算成新行号
        if (root.currentRow >= 0 && indexMap[root.currentRow] !== undefined)
            root.currentRow = indexMap[root.currentRow];

        // 最后再通知外部同步（此时数据与选中行号都已是最新的）
        root.rowsReordered(indexMap);
    }

    // 长按拖选：登记当前选中单元格并聚焦（选中范围由单元格 MouseArea 按拖动逐字符驱动）
    function selectCell(cell) {
        if (root.selectedCell && root.selectedCell !== cell)
            root.selectedCell.deselect();

        root.selectedCell = cell;
        cell.forceActiveFocus();
    }

    // 取消选中（单击其它位置 / 排序 / 数据变化时调用）
    function deselectAll() {
        if (root.selectedCell) {
            root.selectedCell.deselect();
            root.selectedCell = null;
        }
    }

    // 指定列是否为“复选框列”（表格为空占位行时 column 未定义，故需防一手）
    function isCheckBoxColumn(col) {
        return typeof col !== "undefined" && col === root.checkBoxColumn;
    }

    // 根据当前模式重新计算列宽
    function computeWidths() {
        var n = root.titles.length;
        var result = [];
        var i = 0;
        if (!root.stretchToFill) {
            for (i = 0; i < n; ++i) {
                result.push(Math.max(root.minColumnWidth, root.fixedWidths[i] !== undefined ? root.fixedWidths[i] : ScreenTools.scaleNum(100)));
            }
            // 末列弹性模式：可视区有富余时最后一列吃掉剩余宽度铺满；
            // 空间不足时保持设计固定宽（result[n-1] 已含 fixedWidths 下限），内容显示完全，
            // 前面各列按固定宽度保持、由横向滚动条查看
            if (root.lastColumnFills && n > 1) {
                var fixedSum = 0;
                for (i = 0; i < n - 1; ++i)
                    fixedSum += result[i];

                result[n - 1] = Math.max(result[n - 1], root.width - fixedSum);
            }
        } else {
            var total = 0;
            for (i = 0; i < n; ++i) {
                total += (root.stretchFactors[i] !== undefined ? root.stretchFactors[i] : 1);
            }
            if (total <= 0)
                total = 1;

            for (i = 0; i < n; ++i) {
                var factor = root.stretchFactors[i] !== undefined ? root.stretchFactors[i] : 1;
                result.push(Math.max(root.minColumnWidth, root.width * factor / total));
            }
        }
        userResized = false;
        internal.widths = result;
        // 列宽变化后让表格重新布局，并刷新横向滚动范围
        tableView.forceLayout();
    }

    // 拖拽调整相邻两列宽度：index 列加 delta，index+1 列减 delta，两列都不小于 minColumnWidth
    function resizeColumn(index, delta) {
        if (!root.resizable)
            return ;

        var w = internal.widths.slice();
        var next = index + 1;
        if (index < 0 || next >= w.length)
            return ;

        var maxDelta = w[next] - root.minColumnWidth;
        var minDelta = root.minColumnWidth - w[index];
        var applied = Math.min(maxDelta, Math.max(minDelta, delta));
        w[index] += applied;
        w[next] -= applied;
        userResized = true;
        internal.widths = w;
        tableView.forceLayout();
    }

    // 外框由外层 Rectangle 提供，此处不再画边框，避免重复描边
    border.width: 0
    color: "white"
    clip: true
    onTitlesChanged: computeWidths()
    onStretchToFillChanged: computeWidths()
    onFixedWidthsChanged: computeWidths()
    onStretchFactorsChanged: computeWidths()
    onMinColumnWidthChanged: computeWidths()
    // 用户手动拖拽过之后，窗口缩放不再覆盖手动列宽；
    // 末列弹性模式例外：窗口尺寸变化时只重算最后一列（可视区有富余则伸展铺满，
    // 空间不足则回落到设计固定宽保证内容显示完全），保留其余列的手动列宽
    onWidthChanged: {
        if (root.lastColumnFills && !root.stretchToFill && internal.widths.length > 1) {
            var w = internal.widths.slice();
            var fixedSum = 0;
            for (var i = 0; i < w.length - 1; ++i)
                fixedSum += w[i];

            // 末列下限：设计固定宽（fixedWidths 末项，缺省 fallback 与 computeWidths 一致）
            var lastIdx = w.length - 1;
            var lastMin = root.fixedWidths[lastIdx] !== undefined ? root.fixedWidths[lastIdx] : ScreenTools.scaleNum(100);
            w[lastIdx] = Math.max(Math.max(root.minColumnWidth, lastMin), root.width - fixedSum);
            internal.widths = w;
            tableView.forceLayout();
        } else if (!userResized) {
            computeWidths();
        }
    }
    Component.onCompleted: computeWidths()

    QtObject {
        id: internal

        property var widths: []
    }

    // ===== 表头 =====
    Item {
        id: headerClip

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.headerHeight
        clip: true

        Row {
            height: root.headerHeight
            // 跟随横向滚动：空数据时跟随占位区，有数据时跟随表格
            x: -(root.showEmptyRows && root.tableEmpty ? emptyHolder.contentX : tableView.contentX)

            Repeater {
                model: root.titles

                Item {
                    width: root.columnWidths[index] !== undefined ? root.columnWidths[index] : ScreenTools.scaleNum(100)
                    height: root.headerHeight

                    Rectangle {
                        anchors.fill: parent
                        color: root.headerColor

                        Label {
                            anchors.fill: parent
                            anchors.leftMargin: ScreenTools.scaleNum(6)
                            anchors.rightMargin: ScreenTools.scaleNum(6)
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            font: root.headerFont
                            // 当前排序列后面加升序/降序箭头
                            text: modelData + (root.sortColumn === index ? (root.sortAscending ? " \u25b2" : " \u25bc") : "")
                        }

                    }

                    // 点击表头排序（升序/降序切换）；与右侧拖拽把手互不干扰
                    MouseArea {
                        anchors.fill: parent
                        anchors.rightMargin: root.resizable && index < root.titles.length - 1 ? ScreenTools.scaleNum(6) : 0
                        enabled: root.sortEnabled
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.sortByColumn(index)
                    }

                    // 单元格分割线：只画右边和下边，避免相邻单元格边框叠加成 2px
                    Rectangle {
                        anchors.right: parent.right
                        width: 1
                        height: parent.height
                        color: root.lineColor
                    }

                    // 第一列补画左边框
                    Rectangle {
                        anchors.left: parent.left
                        width: 1
                        height: parent.height
                        color: root.lineColor
                        visible: index === 0
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: root.lineColor
                    }

                    // 拖拽把手（仅拉伸模式可用）
                    MouseArea {
                        property real startX: 0

                        enabled: root.resizable && index < root.titles.length - 1
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        width: ScreenTools.scaleNum(6)
                        cursorShape: Qt.SplitHCursor
                        onPressed: {
                            startX = mouseX;
                        }
                        onPositionChanged: {
                            root.resizeColumn(index, mouseX - startX);
                        }
                    }

                }

            }

        }

    }

    // ===== 空数据占位行：铺满可视区域，单数行白色、双数行浅灰 =====
    // 独立 Flickable：空数据时 TableView 没有行、contentWidth 无法按列宽计算，
    // 这里自行提供 contentWidth，保证第 7~10 列可横向滚动查看
    Flickable {
        id: emptyHolder

        anchors.top: headerClip.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        visible: root.showEmptyRows && root.tableEmpty
        // 置于 TableView 之上，保证滚动条可点击
        z: 1
        contentWidth: root.totalWidth
        contentHeight: emptyColumn.height
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick

        Column {
            id: emptyColumn

            Repeater {
                model: Math.max(0, Math.floor(emptyHolder.height / root.rowHeight))

                Row {
                    // 行号：外层 Repeater 的 index，供单元格判断奇偶行背景色
                    property int rowIndex: index

                    height: root.rowHeight

                    Repeater {
                        model: root.titles

                        Rectangle {
                            width: root.columnWidths[index] !== undefined ? root.columnWidths[index] : ScreenTools.scaleNum(100)
                            height: root.rowHeight
                            color: (rowIndex % 2 === 0) ? root.oddRowColor : root.evenRowColor

                            // 单元格分割线：只画右边和下边，避免叠加成 2px
                            Rectangle {
                                anchors.right: parent.right
                                width: 1
                                height: parent.height
                                color: root.lineColor
                            }

                            // 第一列补画左边框
                            Rectangle {
                                anchors.left: parent.left
                                width: 1
                                height: parent.height
                                color: root.lineColor
                                visible: index === 0
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 1
                                color: root.lineColor
                            }

                        }

                    }

                }

            }

        }

        ScrollBar.horizontal: ScrollBar {
            policy: ScrollBar.AlwaysOn
            interactive: true
            active: true
            height: ScreenTools.scaleNum(14)
            z: 2
        }

    }

    // ===== 表格内容 =====
    TableView {
        id: tableView

        anchors.top: headerClip.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        // 空数据时禁用，避免它盖在占位区之上吞掉滚动条的鼠标事件
        enabled: !(root.showEmptyRows && root.tableEmpty)
        columnSpacing: 0
        rowSpacing: 0
        boundsBehavior: Flickable.StopAtBounds
        // 由列宽属性统一提供宽度，保证 contentWidth 正确（无数据时也能横向滚动）
        columnWidthProvider: function(column) {
            return root.columnWidths[column] !== undefined ? root.columnWidths[column] : ScreenTools.scaleNum(100);
        }
        rowHeightProvider: function(row) {
            return root.rowHeight;
        }

        // 空数据时由 emptyHolder 的滚动条接管，避免滑块被拉满无法拖动
        ScrollBar.horizontal: ScrollBar {
            policy: (root.showEmptyRows && root.tableEmpty) ? ScrollBar.AlwaysOff : ScrollBar.AlwaysOn
            interactive: true
            active: true
            height: ScreenTools.scaleNum(14)
        }

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        delegate: Rectangle {
            implicitWidth: typeof column !== "undefined" && root.columnWidths[column] !== undefined ? root.columnWidths[column] : ScreenTools.scaleNum(100)
            implicitHeight: root.rowHeight
            // 选中行优先用浅蓝底色，未选中时按奇偶行交替色
            color: root.isCurrentRow(row) ? root.currentRowColor : ((typeof row !== "undefined" && row % 2 === 0) ? root.oddRowColor : root.evenRowColor)

            // 单元格分割线：只画右边和下边，避免叠加成 2px
            Rectangle {
                anchors.right: parent.right
                width: 1
                height: parent.height
                color: root.lineColor
            }

            // 第一列补画左边框
            Rectangle {
                anchors.left: parent.left
                width: 1
                height: parent.height
                color: root.lineColor
                visible: typeof column !== "undefined" ? column === 0 : true
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: root.lineColor
            }

            // 勾选列（由 checkBoxColumn 指定，默认关闭）：复选框 + 文本，整体靠左、间距 8px
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: ScreenTools.scaleNum(8)
                anchors.rightMargin: ScreenTools.scaleNum(4)
                spacing: ScreenTools.scaleNum(8)
                visible: root.isCheckBoxColumn(column)

                AppCheckBox {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: ScreenTools.scaleNum(16)
                    Layout.preferredHeight: ScreenTools.scaleNum(16)
                    // 直接读调用方维护的已选行号，保证与“已选数量”始终一致
                    checked: typeof row !== "undefined" ? root.checkedRows.indexOf(row) >= 0 : false
                    onToggled: {
                        // 勾选/取消勾选的同时把这一行设为选中行（勾选可多选，选中只有一条）
                        root.selectRow(row);
                        root.rowChecked(row, checked);
                    }
                }

                TextEdit {
                    id: checkCellText

                    Layout.fillWidth: true
                    Layout.preferredHeight: root.rowHeight
                    readOnly: true
                    // 不支持鼠标直接拖选；长按左键后拖动逐字符选中
                    selectByMouse: false
                    // 失去焦点即取消选中，符合“点其它地方就取消”
                    persistentSelection: false
                    wrapMode: TextEdit.NoWrap
                    clip: true
                    verticalAlignment: TextEdit.AlignVCenter
                    font: root.labelFont
                    color: "#1A1A1A"
                    text: display !== undefined ? display : ""
                    Keys.onPressed: {
                        if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
                            checkCellText.copy();
                            event.accepted = true;
                        }
                    }
                    onActiveFocusChanged: {
                        if (!activeFocus && root.selectedCell === checkCellText)
                            root.selectedCell = null;

                    }

                    MouseArea {
                        id: checkArea

                        anchors.fill: parent
                        // 右键只吞掉事件，不弹出菜单
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.IBeamCursor
                        // 拖动事件不许被 TableView 抢走：按住单元格拖动只用于逐字符选中文本，
                        // 不再横向拖动表格（查看后面的列请用底部横向滚动条）
                        preventStealing: true
                        // 长按选择状态：是否已进入拖选模式、按住时起始字符位置
                        property bool holding: false
                        property int selectStartPos: 0

                        // 长按自实现（600ms）：到时进入拖选模式，从按下的字符处建立选择锚点
                        Timer {
                            id: checkHoldTimer

                            interval: 600
                            onTriggered: {
                                checkArea.holding = true;
                                root.selectRow(row);
                                root.selectCell(checkCellText);
                                checkCellText.select(checkArea.selectStartPos, checkArea.selectStartPos);
                            }
                        }

                        onPressed: {
                            checkArea.holding = false;
                            if (mouse.button === Qt.LeftButton) {
                                checkArea.selectStartPos = checkCellText.positionAt(mouse.x, mouse.y);
                                checkHoldTimer.start();
                            }
                        }
                        // 长按生效后：鼠标经过哪个字符就选到哪里，随拖动逐字符覆盖
                        onPositionChanged: {
                            if (!checkArea.holding)
                                return ;

                            var pos = checkCellText.positionAt(mouse.x, mouse.y);
                            checkCellText.select(Math.min(checkArea.selectStartPos, pos), Math.max(checkArea.selectStartPos, pos));
                        }
                        onReleased: checkHoldTimer.stop()
                        onCanceled: checkHoldTimer.stop()
                        onDoubleClicked: {
                            checkHoldTimer.stop();
                            root.selectRow(row);
                            root.rowDoubleClicked(row);
                        }
                        onClicked: {
                            // 长按松开补发的 click 不处理，避免刚选中的文本被取消
                            if (checkArea.holding)
                                return ;

                            // 单击选中该行，同时取消单元格文本选中
                            root.selectRow(row);
                            root.deselectAll();
                        }
                    }
                    // 只允许 Ctrl+C 复制

                }

            }

            // 其它列：只读文本，同样支持长按拖选 + Ctrl+C
            TextEdit {
                id: cellText

                anchors.fill: parent
                anchors.margins: ScreenTools.scaleNum(4)
                readOnly: true
                selectByMouse: false
                persistentSelection: false
                wrapMode: TextEdit.NoWrap
                clip: true
                verticalAlignment: TextEdit.AlignVCenter
                font: root.labelFont
                color: "#1A1A1A"
                text: display !== undefined ? display : ""
                visible: !root.isCheckBoxColumn(column)
                Keys.onPressed: {
                    if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
                        cellText.copy();
                        event.accepted = true;
                    }
                }
                onActiveFocusChanged: {
                    if (!activeFocus && root.selectedCell === cellText)
                        root.selectedCell = null;

                }

                MouseArea {
                    id: cellArea

                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.IBeamCursor
                    // 拖动事件不许被 TableView 抢走：按住单元格拖动只用于逐字符选中文本，
                    // 不再横向拖动表格（查看后面的列请用底部横向滚动条）
                    preventStealing: true
                    // 长按选择状态：是否已进入拖选模式、按住时起始字符位置
                    property bool holding: false
                    property int selectStartPos: 0

                    // 长按自实现（300ms）：到时进入拖选模式，从按下的字符处建立选择锚点
                    Timer {
                        id: cellHoldTimer

                        interval: 300
                        onTriggered: {
                            cellArea.holding = true;
                            root.selectRow(row);
                            root.selectCell(cellText);
                            cellText.select(cellArea.selectStartPos, cellArea.selectStartPos);
                        }
                    }

                    onPressed: {
                        cellArea.holding = false;
                        if (mouse.button === Qt.LeftButton) {
                            cellArea.selectStartPos = cellText.positionAt(mouse.x, mouse.y);
                            cellHoldTimer.start();
                        }
                    }
                    // 长按生效后：鼠标经过哪个字符就选到哪里，随拖动逐字符覆盖
                    onPositionChanged: {
                        if (!cellArea.holding)
                            return ;

                        var pos = cellText.positionAt(mouse.x, mouse.y);
                        cellText.select(Math.min(cellArea.selectStartPos, pos), Math.max(cellArea.selectStartPos, pos));
                    }
                    onReleased: cellHoldTimer.stop()
                    onCanceled: cellHoldTimer.stop()
                    onDoubleClicked: {
                        cellHoldTimer.stop();
                        root.selectRow(row);
                        root.rowDoubleClicked(row);
                    }
                    onClicked: {
                        // 长按松开补发的 click 不处理，避免刚选中的文本被取消
                        if (cellArea.holding)
                            return ;

                        // 单击选中该行，同时取消单元格文本选中
                        root.selectRow(row);
                        root.deselectAll();
                    }
                }

            }

        }

    }

}
