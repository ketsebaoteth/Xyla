import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../components"

Rectangle {
    id: root

    height: 40
    Layout.fillWidth: true
    color: "#181818"

    property int activeViewMode: 0   // 0: Dopesheet, 1: Graph Editor
    property int activeToolIndex: 0  // 0: pointer, 1: scale, 2: color-picker, 3: pencil-minus

    // ── Multi-Target Snapping Flags ──────────────────────────────
    property bool snappingEnabled: true
    property bool snapToFrames: true
    property bool snapToOtherKeys: true
    property bool snapToPlayhead: true

    // ── Graph View Normalization Flag ───────────────────────────
    property bool normalizeEnabled: false

    // ── Selected Keyframe Stats Readouts ────────────────────────
    property bool hasSelectedKey: false
    property real selectedKeyTime: 0.0
    property real selectedKeyValue: 0.0
    property int selectedKeyInterp: -1 // 0: Stepped, 1: Linear, 2: Spline, 3: Flat, 4: Plateau, 5: Ease

    // ── Signals ──────────────────────────────────────────────────
    signal viewModeChanged(int mode)
    signal toolChanged(string toolId)
    signal snappingToggled(bool enabled)
    signal snapModesChanged(bool frames, bool otherKeys, bool playhead)
    signal normalizeToggled(bool enabled)

    signal keyTimeCommitted(real newFrame)
    signal keyValueCommitted(real newValue)

    signal expandAllRequested
    signal collapseAllRequested

    signal selectAllRequested
    signal selectNoneRequested
    signal invertSelectionRequested
    signal selectBeforePlayheadRequested
    signal selectAfterPlayheadRequested

    signal deleteSelectedRequested
    signal snapToPlayheadRequested
    signal setInterpolationRequested(var interpType)

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: "#242424"
    }

    component DopesheetMenuButton: Rectangle {
        id: btnRoot

        property string label: ""
        property string tooltipText: ""
        property Menu targetMenu: null
        readonly property bool isOpen: targetMenu ? targetMenu.visible : false
        readonly property bool isHovered: btnMouse.containsMouse

        implicitHeight: 24
        implicitWidth: btnText.implicitWidth + 16
        radius: 4
        color: (btnRoot.isOpen || btnRoot.isHovered) ? "#262626" : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: 60
            }
        }

        Text {
            id: btnText
            anchors.centerIn: parent
            text: btnRoot.label
            color: (btnRoot.isOpen || btnRoot.isHovered) ? "#ffffff" : "#aaaaaa"
            font.pixelSize: 11
            font.weight: (btnRoot.isOpen || btnRoot.isHovered) ? Font.Medium : Font.Normal

            Behavior on color {
                ColorAnimation {
                    duration: 60
                }
            }
        }

        XylaToolTip {
            visible: btnMouse.containsMouse && !btnRoot.isOpen && btnRoot.tooltipText !== ""
            text: btnRoot.tooltipText
            position: "bottom"
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (btnRoot.targetMenu) {
                    if (btnRoot.targetMenu.visible)
                        btnRoot.targetMenu.close();
                    else
                        btnRoot.targetMenu.open();
                }
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 6

        // 1. VIEW MENU
        DopesheetMenuButton {
            label: "View"
            tooltipText: "View options & layout"
            targetMenu: viewMenu

            XylaMenu {
                id: viewMenu
                y: parent.height + 3

                XylaMenuItem {
                    text: "Expand All"
                    onTriggered: root.expandAllRequested()
                }
                XylaMenuItem {
                    text: "Collapse All"
                    onTriggered: root.collapseAllRequested()
                }
            }
        }

        // 2. SELECT MENU
        DopesheetMenuButton {
            label: "Select"
            tooltipText: "Selection options & shortcuts"
            targetMenu: selectMenu

            XylaMenu {
                id: selectMenu
                y: parent.height + 3

                XylaMenuItem {
                    text: "All"
                    itemShortcut: "A"
                    onTriggered: root.selectAllRequested()
                }
                XylaMenuItem {
                    text: "None"
                    itemShortcut: "Alt+A"
                    onTriggered: root.selectNoneRequested()
                }
                XylaMenuItem {
                    text: "Invert"
                    itemShortcut: "Ctrl+I"
                    onTriggered: root.invertSelectionRequested()
                }
                XylaMenuSeparator {}
                XylaMenuItem {
                    text: "Before Current Frame"
                    itemShortcut: "["
                    onTriggered: root.selectBeforePlayheadRequested()
                }
                XylaMenuItem {
                    text: "After Current Frame"
                    itemShortcut: "]"
                    onTriggered: root.selectAfterPlayheadRequested()
                }
            }
        }

        // 3. KEY MENU
        DopesheetMenuButton {
            label: "Key"
            tooltipText: "Keyframe operations & interpolation"
            targetMenu: keyMenu

            XylaMenu {
                id: keyMenu
                y: parent.height + 3

                XylaMenuItem {
                    text: "Delete Selected"
                    itemShortcut: "Del"
                    onTriggered: root.deleteSelectedRequested()
                }
                XylaMenuItem {
                    text: "Snap to Playhead"
                    itemShortcut: "Shift+S"
                    onTriggered: root.snapToPlayheadRequested()
                }
                XylaMenuSeparator {}
                XylaMenuItem {
                    text: "Interpolation: Constant"
                    onTriggered: root.setInterpolationRequested(0)
                }
                XylaMenuItem {
                    text: "Interpolation: Linear"
                    onTriggered: root.setInterpolationRequested(1)
                }
                XylaMenuItem {
                    text: "Interpolation: Bezier"
                    onTriggered: root.setInterpolationRequested(2)
                }
            }
        }

        // Divider after Menus
        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: 16
            Layout.alignment: Qt.AlignVCenter
            color: "#262626"
        }

        // ── NORMALIZE TOGGLE BUTTON ──────────────────────────────────
        Rectangle {
            id: normalizeComboButton
            implicitHeight: 28
            implicitWidth: normText.implicitWidth + 20
            radius: 6
            color: "transparent"
            border.color: "#282828"
            border.width: 1

            Rectangle {
                id: normBtn
                anchors.fill: parent
                anchors.margins: 2
                radius: 4
                color: {
                    if (root.normalizeEnabled)
                        return normMouse.containsMouse ? "#1645BF" : "#11389F";
                    return normMouse.containsMouse ? "#222222" : "transparent";
                }
                border.color: root.normalizeEnabled ? "#2555D3" : "transparent"
                border.width: root.normalizeEnabled ? 1 : 0

                Behavior on color {
                    ColorAnimation {
                        duration: 120
                    }
                }
                Behavior on border.color {
                    ColorAnimation {
                        duration: 120
                    }
                }

                Text {
                    id: normText
                    anchors.centerIn: parent
                    text: "Normalize"
                    font.pixelSize: 11
                    font.weight: root.normalizeEnabled ? Font.Medium : Font.Normal
                    color: root.normalizeEnabled ? "#FFFFFF" : (normMouse.containsMouse ? "#DDDDDD" : "#AAAAAA")

                    Behavior on color {
                        ColorAnimation {
                            duration: 120
                        }
                    }
                }
            }

            XylaToolTip {
                visible: normMouse.containsMouse
                text: root.normalizeEnabled ? "Normalized view active (Click to disable)" : "Normalize curves to unified [-1.0, 1.0] range"
                position: "bottom"
            }

            MouseArea {
                id: normMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.normalizeEnabled = !root.normalizeEnabled;
                    root.normalizeToggled(root.normalizeEnabled);
                }
            }
        }

        // Divider
        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: 16
            Layout.alignment: Qt.AlignVCenter
            color: "#262626"
        }

        // ── MAYA-STYLE STATS FIELDS (TIME & VALUE VIA XYLAFLOATINPUT) ──
        Rectangle {
            id: statsGroup
            implicitHeight: 28
            implicitWidth: statsRow.implicitWidth + 8
            radius: 6
            color: "#111111"
            border.color: "#282828"
            border.width: 1

            RowLayout {
                id: statsRow
                anchors.fill: parent
                anchors.leftMargin: 4
                anchors.rightMargin: 4
                spacing: 4

                // Time (Frame) Input
                Item {
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 22
                    opacity: root.hasSelectedKey ? 1.0 : 0.4

                    XylaFloatInput {
                        id: timeField
                        anchors.fill: parent
                        enabled: root.hasSelectedKey
                        label: "T"
                        decimals: 0
                        stepSize: 1.0
                        minValue: 0.0
                        maxValue: 999999.0
                        value: root.hasSelectedKey ? root.selectedKeyTime : 0.0

                        onValueCommitted: function (newVal) {
                            root.keyTimeCommitted(Math.round(newVal));
                        }
                    }

                    XylaToolTip {
                        visible: timeHoverArea.containsMouse
                        text: "Selected Key Time (Frame)"
                        position: "bottom"
                    }

                    MouseArea {
                        id: timeHoverArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }
                }

                // Divider between Time and Value
                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 14
                    Layout.alignment: Qt.AlignVCenter
                    color: "#222222"
                }

                // Value Input
                Item {
                    Layout.preferredWidth: 72
                    Layout.preferredHeight: 22
                    opacity: root.hasSelectedKey ? 1.0 : 0.4

                    XylaFloatInput {
                        id: valField
                        anchors.fill: parent
                        enabled: root.hasSelectedKey
                        label: "V"
                        decimals: 3
                        stepSize: 0.1
                        minValue: -999999.0
                        maxValue: 999999.0
                        value: root.hasSelectedKey ? root.selectedKeyValue : 0.0

                        onValueCommitted: function (newVal) {
                            root.keyValueCommitted(newVal);
                        }
                    }

                    XylaToolTip {
                        visible: valHoverArea.containsMouse
                        text: "Selected Key Value"
                        position: "bottom"
                    }

                    MouseArea {
                        id: valHoverArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }
                }
            }
        }

        // Divider
        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: 16
            Layout.alignment: Qt.AlignVCenter
            color: "#262626"
        }

        // ── TANGENT / INTERPOLATION TYPE CLUSTER (6 ONE-CLICK BUTTONS) ──
        Rectangle {
            id: tangentCluster
            implicitHeight: 28
            implicitWidth: tangentRow.implicitWidth + 4
            radius: 6
            color: "#111111"
            border.color: "#282828"
            border.width: 1

            property var tangentTypes: [
                {
                    id: 2,
                    name: "Spline",
                    tooltip: "Spline (Smooth Bezier)",
                    icon: "qrc:/assets/icons/vector-bezier.svg",
                    glyph: "spline"
                },
                {
                    id: 1,
                    name: "Linear",
                    tooltip: "Linear Interpolation",
                    icon: "qrc:/assets/icons/chart-line.svg",
                    glyph: "linear"
                },
                {
                    id: 3,
                    name: "Flat",
                    tooltip: "Flat Tangents (0 Slope)",
                    icon: "qrc:/assets/icons/minus.svg",
                    glyph: "flat"
                },
                {
                    id: 0,
                    name: "Stepped",
                    tooltip: "Stepped (Constant Hold)",
                    icon: "qrc:/assets/icons/stairs.svg",
                    glyph: "stepped"
                },
                {
                    id: 4,
                    name: "Plateau",
                    tooltip: "Plateau (Clamped Extrema)",
                    icon: "qrc:/assets/icons/fold.svg",
                    glyph: "plateau"
                },
                {
                    id: 5,
                    name: "Ease",
                    tooltip: "Ease In/Out (Fast/Slow)",
                    icon: "qrc:/assets/icons/activity.svg",
                    glyph: "ease"
                }
            ]

            Row {
                id: tangentRow
                anchors.centerIn: parent
                spacing: 2

                Repeater {
                    model: tangentCluster.tangentTypes

                    Rectangle {
                        id: tangentBtn
                        width: 22
                        height: 22
                        radius: 4

                        readonly property bool isSelected: root.hasSelectedKey && root.selectedKeyInterp === modelData.id
                        readonly property bool isHovered: tangentMouse.containsMouse

                        color: {
                            if (tangentBtn.isSelected)
                                return "#11389F";
                            if (tangentBtn.isHovered)
                                return "#262626";
                            return "transparent";
                        }
                        border.color: tangentBtn.isSelected ? "#2555D3" : "transparent"
                        border.width: tangentBtn.isSelected ? 1 : 0

                        Behavior on color {
                            ColorAnimation {
                                duration: 100
                            }
                        }

                        Image {
                            id: tIconImg
                            anchors.centerIn: parent
                            width: 12
                            height: 12
                            source: modelData.icon
                            sourceSize: Qt.size(12, 12)
                            opacity: tangentBtn.isSelected ? 1.0 : (tangentBtn.isHovered ? 0.9 : 0.6)
                            visible: status === Image.Ready
                        }

                        Loader {
                            anchors.fill: parent
                            active: tIconImg.status !== Image.Ready
                            sourceComponent: Canvas {
                                id: tCanvas
                                anchors.fill: parent
                                renderTarget: Canvas.Image
                                onPaint: {
                                    var ctx = getContext("2d");
                                    ctx.reset();
                                    var c = tangentBtn.isSelected ? "#FFFFFF" : (tangentBtn.isHovered ? "#DDDDDD" : "#888888");
                                    ctx.strokeStyle = c;
                                    ctx.fillStyle = c;
                                    ctx.lineWidth = 1.3;
                                    ctx.lineCap = "round";
                                    ctx.lineJoin = "round";

                                    if (modelData.glyph === "spline") {
                                        ctx.beginPath();
                                        ctx.moveTo(3, 16);
                                        ctx.bezierCurveTo(7, 16, 8, 6, 19, 6);
                                        ctx.stroke();
                                    } else if (modelData.glyph === "linear") {
                                        ctx.beginPath();
                                        ctx.moveTo(4, 17);
                                        ctx.lineTo(18, 5);
                                        ctx.stroke();
                                    } else if (modelData.glyph === "flat") {
                                        ctx.beginPath();
                                        ctx.moveTo(4, 11);
                                        ctx.lineTo(18, 11);
                                        ctx.stroke();
                                        ctx.beginPath();
                                        ctx.arc(11, 11, 2, 0, 2 * Math.PI);
                                        ctx.fill();
                                    } else if (modelData.glyph === "stepped") {
                                        ctx.beginPath();
                                        ctx.moveTo(3, 16);
                                        ctx.lineTo(11, 16);
                                        ctx.lineTo(11, 6);
                                        ctx.lineTo(19, 6);
                                        ctx.stroke();
                                    } else if (modelData.glyph === "plateau") {
                                        ctx.beginPath();
                                        ctx.moveTo(3, 16);
                                        ctx.lineTo(8, 7);
                                        ctx.lineTo(14, 7);
                                        ctx.lineTo(19, 16);
                                        ctx.stroke();
                                    } else if (modelData.glyph === "ease") {
                                        ctx.beginPath();
                                        ctx.moveTo(3, 16);
                                        ctx.bezierCurveTo(10, 16, 12, 6, 19, 6);
                                        ctx.stroke();
                                    }
                                }
                                Connections {
                                    target: tangentBtn
                                    function onIsSelectedChanged() {
                                        tCanvas.requestPaint();
                                    }
                                    function onIsHoveredChanged() {
                                        tCanvas.requestPaint();
                                    }
                                }
                            }
                        }

                        XylaToolTip {
                            visible: tangentMouse.containsMouse
                            text: modelData.tooltip
                            position: "bottom"
                        }

                        MouseArea {
                            id: tangentMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.setInterpolationRequested(modelData.id);
                            }
                        }
                    }
                }
            }
        }

        // Spacer pushing right-side controls to the right
        Item {
            Layout.fillWidth: true
        }

        // ── 5. ANIMATED SEGMENTED TOOL SELECTOR ──────────────────────
        Item {
            id: toolControl
            property var options: [
                {
                    id: "pointer",
                    label: "Select (Pointer)",
                    icon: "qrc:/assets/icons/pointer.svg"
                },
                {
                    id: "scale",
                    label: "Scale",
                    icon: "qrc:/assets/icons/arrows-horizontal.svg"
                },
                {
                    id: "color-picker",
                    label: "Color Picker",
                    icon: "qrc:/assets/icons/color-picker.svg"
                },
                {
                    id: "pencil-minus",
                    label: "Paint Remove Keyframes",
                    icon: "qrc:/assets/icons/pencil-minus.svg"
                }
            ]
            property int currentIndex: root.activeToolIndex
            property int itemWidth: 30
            property int itemPadding: 2
            property int pillMargin: 2

            implicitHeight: 30
            implicitWidth: (itemWidth * options.length) + (itemPadding * 2)

            Rectangle {
                anchors.fill: parent
                color: "#0d0d0d"
                radius: 7
                border.color: "#202020"
                border.width: 1

                Rectangle {
                    id: toolIndicator
                    width: toolControl.itemWidth - (toolControl.pillMargin * 2)
                    height: parent.height - (toolControl.itemPadding * 2) - (toolControl.pillMargin * 2)
                    y: toolControl.itemPadding + toolControl.pillMargin
                    radius: 4
                    color: "#11389F"
                    border.color: "#2555D3"
                    border.width: 1

                    x: toolControl.itemPadding + (toolControl.currentIndex * toolControl.itemWidth) + toolControl.pillMargin

                    Behavior on x {
                        NumberAnimation {
                            duration: 220
                            easing.type: Easing.OutQuint
                        }
                    }
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: toolControl.itemPadding

                    Repeater {
                        model: toolControl.options

                        Item {
                            id: toolItem
                            width: toolControl.itemWidth
                            height: parent.height

                            readonly property bool isSelected: index === toolControl.currentIndex
                            readonly property bool isHovered: toolMouse.containsMouse

                            Item {
                                anchors.centerIn: parent
                                width: 14
                                height: 14

                                Image {
                                    id: toolIconImg
                                    anchors.fill: parent
                                    source: modelData.icon
                                    sourceSize: Qt.size(14, 14)
                                    opacity: toolItem.isSelected ? 1.0 : (toolItem.isHovered ? 0.85 : 0.45)
                                    visible: status === Image.Ready

                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: 120
                                        }
                                    }
                                }

                                Loader {
                                    id: toolLoader
                                    anchors.fill: parent
                                    active: toolIconImg.status !== Image.Ready
                                    sourceComponent: Canvas {
                                        id: fallbackToolCanvas
                                        anchors.fill: parent
                                        renderTarget: Canvas.Image
                                        onPaint: {
                                            var ctx = getContext("2d");
                                            ctx.reset();
                                            var c = toolItem.isSelected ? "#ffffff" : (toolItem.isHovered ? "#cccccc" : "#777777");
                                            ctx.strokeStyle = c;
                                            ctx.fillStyle = c;
                                            ctx.lineWidth = 1.3;
                                            ctx.lineCap = "round";
                                            ctx.lineJoin = "round";

                                            if (modelData.id === "pointer") {
                                                ctx.beginPath();
                                                ctx.moveTo(2, 2);
                                                ctx.lineTo(2, 12);
                                                ctx.lineTo(5.5, 9);
                                                ctx.lineTo(8.5, 13);
                                                ctx.lineTo(10.5, 11.5);
                                                ctx.lineTo(7.5, 7.5);
                                                ctx.lineTo(11.5, 7.5);
                                                ctx.closePath();
                                                ctx.fill();
                                            } else if (modelData.id === "scale") {
                                                ctx.beginPath();
                                                ctx.moveTo(4.5, 4.5);
                                                ctx.lineTo(2, 7);
                                                ctx.lineTo(4.5, 9.5);
                                                ctx.moveTo(2, 7);
                                                ctx.lineTo(12, 7);
                                                ctx.moveTo(9.5, 4.5);
                                                ctx.lineTo(12, 7);
                                                ctx.lineTo(9.5, 9.5);
                                                ctx.stroke();
                                            } else if (modelData.id === "color-picker") {
                                                ctx.beginPath();
                                                ctx.moveTo(10, 2);
                                                ctx.lineTo(12, 4);
                                                ctx.lineTo(7, 9);
                                                ctx.lineTo(4, 9);
                                                ctx.lineTo(2, 12);
                                                ctx.lineTo(2, 10);
                                                ctx.lineTo(5, 7);
                                                ctx.closePath();
                                                ctx.stroke();
                                            } else if (modelData.id === "pencil-minus") {
                                                ctx.beginPath();
                                                ctx.moveTo(2, 11.5);
                                                ctx.lineTo(4.5, 11.5);
                                                ctx.lineTo(10.5, 5.5);
                                                ctx.lineTo(8, 3);
                                                ctx.lineTo(2, 9);
                                                ctx.closePath();
                                                ctx.stroke();

                                                ctx.beginPath();
                                                ctx.moveTo(8.5, 11.5);
                                                ctx.lineTo(12.5, 11.5);
                                                ctx.lineWidth = 1.4;
                                                ctx.stroke();
                                            }
                                        }
                                        Connections {
                                            target: toolItem
                                            function onIsSelectedChanged() {
                                                fallbackToolCanvas.requestPaint();
                                            }
                                            function onIsHoveredChanged() {
                                                fallbackToolCanvas.requestPaint();
                                            }
                                        }
                                    }
                                }
                            }

                            XylaToolTip {
                                visible: toolMouse.containsMouse
                                text: modelData.label
                                position: "bottom"
                            }

                            MouseArea {
                                id: toolMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    toolControl.currentIndex = index;
                                    root.activeToolIndex = index;
                                    root.toolChanged(modelData.id);
                                }
                            }
                        }
                    }
                }
            }
        }

        // Divider
        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: 16
            Layout.alignment: Qt.AlignVCenter
            color: "#262626"
        }

        // ── 6. UNIFIED SNAPPING DUAL-ACTION BUTTON ──────────────────
        Rectangle {
            id: snapComboButton
            implicitHeight: 28
            implicitWidth: 62
            radius: 6
            color: "transparent"
            border.color: "#282828"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.margins: 2
                spacing: 2

                Rectangle {
                    id: magnetBtn
                    Layout.fillHeight: true
                    Layout.preferredWidth: 30
                    radius: 4
                    color: {
                        if (root.snappingEnabled)
                            return magnetMouse.containsMouse ? "#1645BF" : "#11389F";
                        return magnetMouse.containsMouse ? "#222222" : "transparent";
                    }
                    border.color: root.snappingEnabled ? "#2555D3" : "transparent"
                    border.width: root.snappingEnabled ? 1 : 0

                    Behavior on color {
                        ColorAnimation {
                            duration: 120
                        }
                    }
                    Behavior on border.color {
                        ColorAnimation {
                            duration: 120
                        }
                    }

                    Image {
                        anchors.centerIn: parent
                        width: 14
                        height: 14
                        source: "qrc:/assets/icons/magnet.svg"
                        sourceSize: Qt.size(14, 14)
                        opacity: root.snappingEnabled ? 1.0 : (magnetMouse.containsMouse ? 0.75 : 0.45)

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 120
                            }
                        }
                    }

                    XylaToolTip {
                        visible: magnetMouse.containsMouse
                        text: root.snappingEnabled ? "Snapping enabled (Click to toggle)" : "Snapping disabled (Click to toggle)"
                        position: "bottom"
                    }

                    MouseArea {
                        id: magnetMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.snappingEnabled = !root.snappingEnabled;
                            root.snappingToggled(root.snappingEnabled);
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 14
                    Layout.alignment: Qt.AlignVCenter
                    color: "#282828"
                }

                Rectangle {
                    id: chevronBtn
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    radius: 4
                    color: (chevronMouse.containsMouse || snapPopup.visible) ? "#202020" : "transparent"

                    Behavior on color {
                        ColorAnimation {
                            duration: 100
                        }
                    }

                    Image {
                        anchors.centerIn: parent
                        width: 12
                        height: 12
                        source: "qrc:/assets/icons/chevron-down.svg"
                        sourceSize: Qt.size(12, 12)
                        opacity: (chevronMouse.containsMouse || snapPopup.visible) ? 0.9 : 0.45
                        rotation: snapPopup.visible ? 180 : 0

                        Behavior on rotation {
                            NumberAnimation {
                                duration: 150
                            }
                        }
                        Behavior on opacity {
                            NumberAnimation {
                                duration: 100
                            }
                        }
                    }

                    XylaToolTip {
                        visible: chevronMouse.containsMouse && !snapPopup.visible
                        text: "Snap targets and options"
                        position: "bottom"
                    }

                    MouseArea {
                        id: chevronMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (snapPopup.visible)
                                snapPopup.close();
                            else
                                snapPopup.open();
                        }
                    }
                }
            }

            DopesheetSnapPopup {
                id: snapPopup

                x: {
                    var win = snapComboButton.Window.window;
                    if (!win)
                        return snapComboButton.width - width;

                    var btnWinPos = snapComboButton.mapToItem(null, 0, 0);
                    var winW = win.width;
                    var margin = 8;
                    var prefRelX = (btnWinPos.x + snapComboButton.width / 2 > winW / 2) ? (snapComboButton.width - width) : 0;
                    var targetWinX = btnWinPos.x + prefRelX;

                    if (targetWinX + width > winW - margin)
                        return (winW - margin - width) - btnWinPos.x;
                    if (targetWinX < margin)
                        return margin - btnWinPos.x;

                    return prefRelX;
                }

                y: {
                    var win = snapComboButton.Window.window;
                    if (!win)
                        return snapComboButton.height + 4;

                    var btnWinPos = snapComboButton.mapToItem(null, 0, 0);
                    var spaceBelow = win.height - (btnWinPos.y + snapComboButton.height + 4);

                    if (spaceBelow < height && btnWinPos.y > height)
                        return -height - 4;
                    return snapComboButton.height + 4;
                }

                transformOrigin: {
                    var isAbove = (y < 0);
                    var isRightAligned = (x < 0);
                    if (isAbove)
                        return isRightAligned ? Item.BottomRight : Item.BottomLeft;
                    return isRightAligned ? Item.TopRight : Item.TopLeft;
                }

                snapToFrames: root.snapToFrames
                snapToOtherKeys: root.snapToOtherKeys
                snapToPlayhead: root.snapToPlayhead

                onSnapModesChanged: function (frames, otherKeys, playhead) {
                    root.snapToFrames = frames;
                    root.snapToOtherKeys = otherKeys;
                    root.snapToPlayhead = playhead;
                    root.snapModesChanged(frames, otherKeys, playhead);
                }
            }
        }

        // Divider
        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: 16
            Layout.alignment: Qt.AlignVCenter
            color: "#262626"
        }

        // ── 7. ANIMATED SEGMENTED SLIDER (DOPESHEET <-> GRAPH) ──────
        Item {
            id: modeControl
            property var options: [
                {
                    label: "Dopesheet",
                    value: 0
                },
                {
                    label: "Graph",
                    value: 1
                }
            ]
            property int currentIndex: root.activeViewMode
            property int itemWidth: 76
            property int itemPadding: 2

            implicitHeight: 30
            implicitWidth: (itemWidth * options.length) + (itemPadding * 2)

            Rectangle {
                anchors.fill: parent
                color: "#0d0d0d"
                radius: 7
                border.color: "#202020"
                border.width: 1

                Rectangle {
                    id: indicator
                    width: modeControl.itemWidth
                    height: parent.height - (modeControl.itemPadding * 2)
                    y: modeControl.itemPadding
                    radius: 5
                    color: "#11389F"
                    border.color: "#2555D3"
                    border.width: 1

                    x: modeControl.itemPadding + (modeControl.currentIndex * modeControl.itemWidth)

                    Behavior on x {
                        NumberAnimation {
                            duration: 220
                            easing.type: Easing.OutQuint
                        }
                    }
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: modeControl.itemPadding

                    Repeater {
                        model: modeControl.options

                        Item {
                            id: optionItem
                            width: modeControl.itemWidth
                            height: parent.height

                            readonly property bool isSelected: index === modeControl.currentIndex
                            readonly property bool isHovered: optMouse.containsMouse

                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                font.pixelSize: 11
                                font.weight: optionItem.isSelected ? Font.Medium : Font.Normal
                                color: optionItem.isSelected ? "#ffffff" : (optionItem.isHovered ? "#dddddd" : "#888888")

                                Behavior on color {
                                    ColorAnimation {
                                        duration: 120
                                    }
                                }
                            }

                            XylaToolTip {
                                visible: optMouse.containsMouse
                                text: modelData.value === 0 ? "Switch to Dopesheet View" : "Switch to Graph Editor View"
                                position: "bottom"
                            }

                            MouseArea {
                                id: optMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    modeControl.currentIndex = index;
                                    root.activeViewMode = modelData.value;
                                    root.viewModeChanged(modelData.value);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
