import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Popup {
    id: root
    parent: Overlay.overlay
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 8

    property var timelineModel: typeof timelineModel !== "undefined" ? timelineModel : null
    property var dopesheetRoot: null
    property var controller: null
    property int activeViewMode: 0   // 0: Dopesheet, 1: Graph Editor
    property int playheadFrame: 0

    property string activeClipId: ""
    property string activePropertyId: ""
    property int clickedFrame: 0
    property bool hasKeyframeClicked: false

    readonly property bool hasSelection: dopesheetRoot ? (dopesheetRoot.selectedKeyframes && dopesheetRoot.selectedKeyframes.length > 0) : hasKeyframeClicked

    signal deleteKeyframeRequested(string clipId, string propId, int frame)
    signal clearAllKeyframesRequested(string clipId)

    onClosed: {
        pasteSpecialSubmenu.close();
        handleTypeSubmenu.close();
        interpolationSubmenu.close();
        easingSubmenu.close();
    }

    background: Rectangle {
        id: popupSurface
        anchors.fill: parent
        color: "#181818"
        border.color: "#303030"
        border.width: 1
        radius: 12

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#90000000"
            shadowBlur: 0.65
            shadowVerticalOffset: 6
            shadowHorizontalOffset: 0
        }
    }

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0.0
            to: 1.0
            duration: 150
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            property: "scale"
            from: 0.95
            to: 1.0
            duration: 180
            easing.type: Easing.OutCubic
        }
    }
    exit: Transition {
        NumberAnimation {
            property: "opacity"
            from: 1.0
            to: 0.0
            duration: 120
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            property: "scale"
            from: 1.0
            to: 0.95
            duration: 120
            easing.type: Easing.OutCubic
        }
    }

    contentItem: ColumnLayout {
        id: contentLayout
        spacing: 3
        implicitWidth: 220
        Layout.preferredWidth: 220

        // ── 1. Copy / Paste ──────────────────────────────────────────
        MenuRow {
            text: "Copy"
            shortcutText: "Ctrl+C"
            enabled_: root.hasSelection
            onClicked: {
                root.close();
                if (root.controller && root.dopesheetRoot)
                    root.controller.copy(root.timelineModel, root.dopesheetRoot.selectedKeyframes);
            }
        }

        MenuRow {
            text: "Paste"
            shortcutText: "Ctrl+V"
            enabled_: root.controller ? root.controller.hasClipboard : true
            onClicked: {
                root.close();
                if (root.controller)
                    root.controller.paste(root.timelineModel, root.playheadFrame);
            }
        }

        MenuRow {
            id: pasteSpecialRow
            text: "Paste Special"
            showArrow: true
            enabled_: root.controller ? root.controller.hasClipboard : true
            onHoveredChanged: isHovered => {
                if (isHovered)
                    openSubmenu(pasteSpecialSubmenu, pasteSpecialRow);
            }
            onClicked: openSubmenu(pasteSpecialSubmenu, pasteSpecialRow)
        }

        MenuSeparator {}

        // ── 2. Handle / Interpolation / Easing ───────────────────────
        MenuRow {
            id: handleTypeRow
            text: "Handle Type"
            showArrow: true
            enabled_: root.hasSelection
            onHoveredChanged: isHovered => {
                if (isHovered)
                    openSubmenu(handleTypeSubmenu, handleTypeRow);
            }
            onClicked: openSubmenu(handleTypeSubmenu, handleTypeRow)
        }

        MenuRow {
            id: interpolationRow
            text: "Interpolation Mode"
            showArrow: true
            enabled_: root.hasSelection
            onHoveredChanged: isHovered => {
                if (isHovered)
                    openSubmenu(interpolationSubmenu, interpolationRow);
            }
            onClicked: openSubmenu(interpolationSubmenu, interpolationRow)
        }

        MenuRow {
            id: easingRow
            text: "Easing Type"
            showArrow: true
            visible: root.activeViewMode === 1
            enabled_: root.hasSelection
            onHoveredChanged: isHovered => {
                if (isHovered)
                    openSubmenu(easingSubmenu, easingRow);
            }
            onClicked: openSubmenu(easingSubmenu, easingRow)
        }

        MenuSeparator {}

        // ── 3. Clean / Sample / Bake ─────────────────────────────────
        MenuRow {
            text: "Clean Keys"
            enabled_: root.hasSelection
            onClicked: {
                root.close();
                if (root.controller && root.dopesheetRoot)
                    root.controller.cleanKeys(root.timelineModel, root.dopesheetRoot.selectedKeyframes);
            }
        }

        MenuRow {
            text: "Sample Keys"
            enabled_: root.hasSelection
            onClicked: {
                root.close();
                if (root.controller && root.dopesheetRoot)
                    root.controller.sampleKeys(root.timelineModel, root.dopesheetRoot.selectedKeyframes);
            }
        }

        MenuRow {
            text: "Bake Curve"
            enabled_: root.activeClipId !== ""
            onClicked: {
                root.close();
                if (root.controller && root.dopesheetRoot)
                    root.controller.bakeCurve(root.timelineModel, root.dopesheetRoot.activeClipId, root.activePropertyId);
            }
        }

        MenuSeparator {}

        // ── 4. Delete ────────────────────────────────────────────────
        MenuRow {
            text: "Delete Keys"
            shortcutText: "Del"
            destructive: true
            enabled_: root.hasSelection
            onClicked: {
                root.close();
                if (root.controller && root.dopesheetRoot) {
                    root.controller.deleteKeys(root.timelineModel, root.dopesheetRoot.selectedKeyframes);
                } else {
                    root.deleteKeyframeRequested(root.activeClipId, root.activePropertyId, root.clickedFrame);
                }
            }
        }
    }

    Popup {
        id: pasteSpecialSubmenu
        parent: Overlay.overlay
        modal: false
        focus: true
        padding: 6
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color: "#181818"
            border.color: "#303030"
            border.width: 1
            radius: 10
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#90000000"
                shadowBlur: 0.65
                shadowVerticalOffset: 6
            }
        }

        contentItem: ColumnLayout {
            spacing: 2
            implicitWidth: 180

            MenuRow {
                text: "Paste (No Offset)"
                onClicked: {
                    pasteSpecialSubmenu.close();
                    root.close();
                    if (root.controller)
                        root.controller.pasteNoOffset(root.timelineModel);
                }
            }
            MenuRow {
                text: "Overwrite Range"
                onClicked: {
                    pasteSpecialSubmenu.close();
                    root.close();
                    if (root.controller)
                        root.controller.pasteOverwriteRange(root.timelineModel, root.playheadFrame);
                }
            }
            MenuRow {
                text: "Overwrite All"
                onClicked: {
                    pasteSpecialSubmenu.close();
                    root.close();
                    if (root.controller)
                        root.controller.pasteOverwriteAll(root.timelineModel, root.playheadFrame);
                }
            }
        }

        function openAt(tx, ty) {
            if (!Overlay.overlay)
                return;
            if (tx + width > Overlay.overlay.width - 8)
                tx = root.x - width + 4;
            x = Math.max(8, Math.min(tx, Overlay.overlay.width - width - 8));
            y = Math.max(8, Math.min(ty, Overlay.overlay.height - height - 8));
            open();
        }
    }

    Popup {
        id: handleTypeSubmenu
        parent: Overlay.overlay
        modal: false
        focus: true
        padding: 6
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color: "#181818"
            border.color: "#303030"
            border.width: 1
            radius: 10
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#90000000"
                shadowBlur: 0.65
                shadowVerticalOffset: 6
            }
        }

        contentItem: ColumnLayout {
            spacing: 2
            implicitWidth: 160

            MenuRow {
                text: "Free"
                onClicked: {
                    handleTypeSubmenu.close();
                    root.close();
                    if (root.controller && root.dopesheetRoot)
                        root.controller.setHandleType(root.timelineModel, root.dopesheetRoot.selectedKeyframes, 0);
                }
            }
            MenuRow {
                text: "Vector"
                onClicked: {
                    handleTypeSubmenu.close();
                    root.close();
                    if (root.controller && root.dopesheetRoot)
                        root.controller.setHandleType(root.timelineModel, root.dopesheetRoot.selectedKeyframes, 1);
                }
            }
            MenuRow {
                text: "Aligned"
                onClicked: {
                    handleTypeSubmenu.close();
                    root.close();
                    if (root.controller && root.dopesheetRoot)
                        root.controller.setHandleType(root.timelineModel, root.dopesheetRoot.selectedKeyframes, 2);
                }
            }
            MenuRow {
                text: "Auto"
                onClicked: {
                    handleTypeSubmenu.close();
                    root.close();
                    if (root.controller && root.dopesheetRoot)
                        root.controller.setHandleType(root.timelineModel, root.dopesheetRoot.selectedKeyframes, 3);
                }
            }
            MenuRow {
                text: "Auto Clamped"
                onClicked: {
                    handleTypeSubmenu.close();
                    root.close();
                    if (root.controller && root.dopesheetRoot)
                        root.controller.setHandleType(root.timelineModel, root.dopesheetRoot.selectedKeyframes, 4);
                }
            }
        }

        function openAt(tx, ty) {
            if (!Overlay.overlay)
                return;
            if (tx + width > Overlay.overlay.width - 8)
                tx = root.x - width + 4;
            x = Math.max(8, Math.min(tx, Overlay.overlay.width - width - 8));
            y = Math.max(8, Math.min(ty, Overlay.overlay.height - height - 8));
            open();
        }
    }

    Popup {
        id: interpolationSubmenu
        parent: Overlay.overlay
        modal: false
        focus: true
        padding: 6
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color: "#181818"
            border.color: "#303030"
            border.width: 1
            radius: 10
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#90000000"
                shadowBlur: 0.65
                shadowVerticalOffset: 6
            }
        }

        contentItem: ColumnLayout {
            spacing: 2
            implicitWidth: 170

            MenuRow {
                text: "Constant (Hold)"
                onClicked: {
                    interpolationSubmenu.close();
                    root.close();
                    if (root.controller && root.dopesheetRoot)
                        root.controller.setInterpolation(root.timelineModel, root.dopesheetRoot.selectedKeyframes, 0);
                }
            }
            MenuRow {
                text: "Linear"
                onClicked: {
                    interpolationSubmenu.close();
                    root.close();
                    if (root.controller && root.dopesheetRoot)
                        root.controller.setInterpolation(root.timelineModel, root.dopesheetRoot.selectedKeyframes, 1);
                }
            }
            MenuRow {
                text: "Bezier"
                onClicked: {
                    interpolationSubmenu.close();
                    root.close();
                    if (root.controller && root.dopesheetRoot)
                        root.controller.setInterpolation(root.timelineModel, root.dopesheetRoot.selectedKeyframes, 2);
                }
            }
        }

        function openAt(tx, ty) {
            if (!Overlay.overlay)
                return;
            if (tx + width > Overlay.overlay.width - 8)
                tx = root.x - width + 4;
            x = Math.max(8, Math.min(tx, Overlay.overlay.width - width - 8));
            y = Math.max(8, Math.min(ty, Overlay.overlay.height - height - 8));
            open();
        }
    }

    Popup {
        id: easingSubmenu
        parent: Overlay.overlay
        modal: false
        focus: true
        padding: 6
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color: "#181818"
            border.color: "#303030"
            border.width: 1
            radius: 10
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#90000000"
                shadowBlur: 0.65
                shadowVerticalOffset: 6
            }
        }

        contentItem: ColumnLayout {
            spacing: 2
            implicitWidth: 150

            MenuRow {
                text: "Linear"
                onClicked: {
                    easingSubmenu.close();
                    root.close();
                    if (root.controller && root.dopesheetRoot)
                        root.controller.setEasing(root.timelineModel, root.dopesheetRoot.selectedKeyframes, 0);
                }
            }
            MenuRow {
                text: "Ease In"
                onClicked: {
                    easingSubmenu.close();
                    root.close();
                    if (root.controller && root.dopesheetRoot)
                        root.controller.setEasing(root.timelineModel, root.dopesheetRoot.selectedKeyframes, 1);
                }
            }
            MenuRow {
                text: "Ease Out"
                onClicked: {
                    easingSubmenu.close();
                    root.close();
                    if (root.controller && root.dopesheetRoot)
                        root.controller.setEasing(root.timelineModel, root.dopesheetRoot.selectedKeyframes, 2);
                }
            }
            MenuRow {
                text: "Ease In / Out"
                onClicked: {
                    easingSubmenu.close();
                    root.close();
                    if (root.controller && root.dopesheetRoot)
                        root.controller.setEasing(root.timelineModel, root.dopesheetRoot.selectedKeyframes, 3);
                }
            }
        }

        function openAt(tx, ty) {
            if (!Overlay.overlay)
                return;
            if (tx + width > Overlay.overlay.width - 8)
                tx = root.x - width + 4;
            x = Math.max(8, Math.min(tx, Overlay.overlay.width - width - 8));
            y = Math.max(8, Math.min(ty, Overlay.overlay.height - height - 8));
            open();
        }
    }

    // ── Helpers ──────────────────────────────────────────────────
    function openSubmenu(submenu, rowItem) {
        if (submenu !== pasteSpecialSubmenu)
            pasteSpecialSubmenu.close();
        if (submenu !== handleTypeSubmenu)
            handleTypeSubmenu.close();
        if (submenu !== interpolationSubmenu)
            interpolationSubmenu.close();
        if (submenu !== easingSubmenu)
            easingSubmenu.close();

        var globalPt = rowItem.mapToItem(Overlay.overlay, rowItem.width, 0);
        submenu.openAt(globalPt.x - 4, globalPt.y - 4);
    }

    function openAt(screenX, screenY, clipId, propId, frame, hasKey) {
        activeClipId = clipId || "";
        activePropertyId = propId || "";
        clickedFrame = frame !== undefined ? frame : 0;
        hasKeyframeClicked = hasKey !== undefined ? Boolean(hasKey) : false;

        if (Overlay.overlay) {
            x = Math.max(8, Math.min(screenX, Overlay.overlay.width - implicitWidth - 8));
            y = Math.max(8, Math.min(screenY, Overlay.overlay.height - implicitHeight - 8));
        }
        open();
    }

    component MenuRow: Rectangle {
        id: row
        property string text: ""
        property string shortcutText: ""
        property bool destructive: false
        property bool showArrow: false
        property bool enabled_: true
        readonly property bool isHovered: rowMouse.containsMouse

        signal hoveredChanged(bool isHovered)
        signal clicked

        Layout.fillWidth: true
        implicitWidth: rowContent.implicitWidth + 20
        implicitHeight: 28
        radius: 7
        color: rowMouse.containsMouse && row.enabled_ ? "#252525" : "transparent"
        opacity: row.enabled_ ? 1.0 : 0.38

        RowLayout {
            id: rowContent
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: row.text
                color: row.destructive ? "#e06b6b" : "#ffffff"
                font.pixelSize: 12
                elide: Text.ElideRight
            }

            Text {
                visible: row.showArrow
                text: "›"
                color: "#888888"
                font.pixelSize: 16
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                visible: !row.showArrow && row.shortcutText.length > 0
                text: row.shortcutText
                color: "#777777"
                font.pixelSize: 11
                font.family: "Monospace"
                Layout.alignment: Qt.AlignVCenter
            }
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: row.enabled_
            cursorShape: Qt.PointingHandCursor
            onEntered: row.hoveredChanged(true)
            onExited: row.hoveredChanged(false)
            onClicked: row.clicked()
        }
    }

    component MenuSeparator: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 7
        color: "transparent"
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 1
            color: "#2d2d2d"
        }
    }
}
