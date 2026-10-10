import QtQuick 2.15
import QtQuick.Controls 2.15
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

    // 外框由外层 Rectangle 提供，此处不再画边框，避免重复描边
    border.width: 0
    color: "white"
    clip: true

    QtObject {
        id: internal

        property var widths: []
    }

    onTitlesChanged: computeWidths()
    onStretchToFillChanged: computeWidths()
    onFixedWidthsChanged: computeWidths()
    onStretchFactorsChanged: computeWidths()
    onMinColumnWidthChanged: computeWidths()
    // 用户手动拖拽过之后，窗口缩放不再覆盖手动列宽
    onWidthChanged: {
        if (!userResized) {
            computeWidths();
        }
    }
    Component.onCompleted: computeWidths()

    // 是否已经手动拖拽调整过列宽
    property bool userResized: false

    // 根据当前模式重新计算列宽
    function computeWidths() {
        var n = root.titles.length;
        var result = [];
        var i = 0;
        if (!root.stretchToFill) {
            for (i = 0; i < n; ++i) {
                result.push(Math.max(root.minColumnWidth, root.fixedWidths[i] !== undefined ? root.fixedWidths[i] : ScreenTools.scaleNum(100)));
            }
        } else {
            var total = 0;
            for (i = 0; i < n; ++i) {
                total += (root.stretchFactors[i] !== undefined ? root.stretchFactors[i] : 1);
            }
            if (total <= 0) {
                total = 1;
            }
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
        if (!root.resizable) {
            return;
        }
        var w = internal.widths.slice();
        var next = index + 1;
        if (index < 0 || next >= w.length) {
            return;
        }
        var maxDelta = w[next] - root.minColumnWidth;
        var minDelta = root.minColumnWidth - w[index];
        var applied = Math.min(maxDelta, Math.max(minDelta, delta));
        w[index] += applied;
        w[next] -= applied;
        userResized = true;
        internal.widths = w;
        tableView.forceLayout();
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
                            font: root.labelFont
                            text: modelData
                        }
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
                        enabled: root.resizable && index < root.titles.length - 1
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        width: ScreenTools.scaleNum(6)
                        cursorShape: Qt.SplitHCursor

                        property real startX: 0

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

        ScrollBar.horizontal: ScrollBar {
            policy: ScrollBar.AlwaysOn
            interactive: true
            active: true
            height: ScreenTools.scaleNum(14)
            z: 2
        }

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
            color: (typeof row !== "undefined" && row % 2 === 0) ? root.oddRowColor : root.evenRowColor

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

            Label {
                anchors.fill: parent
                anchors.margins: ScreenTools.scaleNum(4)
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                font: root.labelFont
                text: display !== undefined ? display : ""
            }
        }
    }

}
