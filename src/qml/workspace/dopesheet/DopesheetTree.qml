import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../components"

Rectangle {
    id: treeViewRoot

    property var treeRows: []
    property int headerWidth: 200
    property string activePropId: ""
    property string activeClipId: ""

    signal toggleRowExpansion(int rowIndex)
    signal trackSelected(string clipId, string propId)
    signal contextMenuRequested(real globalX, real globalY, string clipId, string propId, bool isMuted, bool isLocked)

    // ── Quick-Action Toggle Signals ──────────────────────────────
    signal toggleTrackVisibilityRequested(string clipId, string propId, bool isSolo, bool isEnableAll)
    signal toggleTrackMuteRequested(string clipId, string propId)
    signal toggleTrackLockRequested(string clipId, string propId)

    Layout.fillHeight: true
    Layout.preferredWidth: treeViewRoot.headerWidth
    color: "#131313"
    z: 300

    // 1px Border separator between tree and canvas
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: "#222222"
        z: 3
    }

    // ── Reusable Minimalist Quick-Action Icon Button ─────────────
    component TreeActionButton: Rectangle {
        id: actBtn
        property string iconSource: ""
        property bool isActive: false
        property color activeColor: "#FFFFFF"
        property color inactiveColor: "#888888"
        property string tooltipText: ""
        property string fallbackGlyph: ""
        signal clicked(var mouse)

        width: 18
        height: 18
        radius: 3
        color: btnMouse.containsMouse ? "#2A2A2A" : "transparent"

        Image {
            id: btnImg
            anchors.centerIn: parent
            width: 12
            height: 12
            source: actBtn.iconSource
            sourceSize: Qt.size(12, 12)
            opacity: 1.0
            visible: status === Image.Ready
        }

        Loader {
            anchors.fill: parent
            active: btnImg.status !== Image.Ready
            sourceComponent: Canvas {
                id: fallbackCanvas
                anchors.fill: parent
                renderTarget: Canvas.Image
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    var c = actBtn.isActive ? actBtn.activeColor : (btnMouse.containsMouse ? "#FFFFFF" : actBtn.inactiveColor);
                    ctx.strokeStyle = c;
                    ctx.fillStyle = c;
                    ctx.lineWidth = 1.3;
                    ctx.lineCap = "round";
                    ctx.lineJoin = "round";

                    if (actBtn.fallbackGlyph === "eye") {
                        ctx.beginPath();
                        ctx.arc(9, 9, 2.2, 0, 2 * Math.PI);
                        ctx.fill();
                        ctx.beginPath();
                        ctx.moveTo(3, 9);
                        ctx.bezierCurveTo(5.5, 5, 12.5, 5, 15, 9);
                        ctx.bezierCurveTo(12.5, 13, 5.5, 13, 3, 9);
                        ctx.stroke();
                    } else if (actBtn.fallbackGlyph === "eye-off") {
                        ctx.beginPath();
                        ctx.moveTo(3, 9);
                        ctx.bezierCurveTo(5.5, 5, 12.5, 5, 15, 9);
                        ctx.bezierCurveTo(12.5, 13, 5.5, 13, 3, 9);
                        ctx.stroke();
                        ctx.beginPath();
                        ctx.moveTo(4, 4);
                        ctx.lineTo(14, 14);
                        ctx.stroke();
                    } else if (actBtn.fallbackGlyph === "volume") {
                        ctx.beginPath();
                        ctx.moveTo(4, 7);
                        ctx.lineTo(6.5, 7);
                        ctx.lineTo(9.5, 4.5);
                        ctx.lineTo(9.5, 13.5);
                        ctx.lineTo(6.5, 11);
                        ctx.lineTo(4, 11);
                        ctx.closePath();
                        ctx.fill();
                        ctx.beginPath();
                        ctx.arc(9.5, 9, 4, -0.6, 0.6);
                        ctx.stroke();
                    } else if (actBtn.fallbackGlyph === "volume-off") {
                        ctx.beginPath();
                        ctx.moveTo(4, 7);
                        ctx.lineTo(6.5, 7);
                        ctx.lineTo(9.5, 4.5);
                        ctx.lineTo(9.5, 13.5);
                        ctx.lineTo(6.5, 11);
                        ctx.lineTo(4, 11);
                        ctx.closePath();
                        ctx.fill();
                        ctx.beginPath();
                        ctx.moveTo(12, 7);
                        ctx.lineTo(15, 11);
                        ctx.moveTo(15, 7);
                        ctx.lineTo(12, 11);
                        ctx.stroke();
                    } else if (actBtn.fallbackGlyph === "lock") {
                        ctx.strokeRect(5, 8, 8, 6.5);
                        ctx.beginPath();
                        ctx.arc(9, 8, 2.5, Math.PI, 0);
                        ctx.stroke();
                    } else if (actBtn.fallbackGlyph === "lock-open") {
                        ctx.strokeRect(5, 8, 8, 6.5);
                        ctx.beginPath();
                        ctx.arc(11, 6.5, 2.5, Math.PI, 0);
                        ctx.stroke();
                    }
                }
                Connections {
                    target: actBtn
                    function onIsActiveChanged() {
                        fallbackCanvas.requestPaint();
                    }
                }
            }
        }

        XylaToolTip {
            visible: btnMouse.containsMouse && !btnMouse.pressed && actBtn.tooltipText !== ""
            text: actBtn.tooltipText
            position: "top"
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton

            onPressed: function (mouse) {
                mouse.accepted = true;
            }
            onClicked: function (mouse) {
                mouse.accepted = true;
                actBtn.clicked(mouse);
            }
        }
    }

    Column {
        anchors.fill: parent
        anchors.rightMargin: 1

        Repeater {
            model: treeViewRoot.treeRows

            delegate: Rectangle {
                id: rowRect

                required property var modelData
                required property int index

                readonly property var treeOwner: {
                    if (typeof treeViewRoot !== "undefined" && treeViewRoot)
                        return treeViewRoot;
                    if (typeof root !== "undefined" && root)
                        return root;
                    return rowRect.parent.parent;
                }

                readonly property string rowClipId: (modelData && modelData.clipId) ? modelData.clipId : ""
                readonly property string rowPropId: (modelData && modelData.propId) ? modelData.propId : ""
                readonly property string rowType: (modelData && modelData.type) ? modelData.type : ""
                readonly property string rowName: (modelData && modelData.name) ? modelData.name : ""
                readonly property int rowIndent: (modelData && modelData.indent) ? modelData.indent : 0
                readonly property int rowKeyCount: (modelData && modelData.keyCount) ? modelData.keyCount : 0
                readonly property bool isChannel: rowType === "channel"
                readonly property bool isExpandable: !!(modelData && modelData.isExpandable)
                readonly property bool isExpanded: !!(modelData && modelData.expanded)

                readonly property bool isVisibleInGraph: modelData && modelData.isVisibleInGraph !== undefined ? !!modelData.isVisibleInGraph : true
                readonly property bool isMutedTrack: !!(modelData && modelData.isMuted)
                readonly property bool isLockedTrack: !!(modelData && modelData.isLocked)
                readonly property color trackColor: (modelData && modelData.color) ? modelData.color : "#3B82F6"
                readonly property bool isActiveTrack: isChannel && rowPropId === (treeOwner ? treeOwner.activePropId : "")

                width: (treeOwner ? treeOwner.headerWidth : 200) - 1
                height: 24

                color: {
                    var base = "#131313";
                    if (isActiveTrack)
                        base = "#202020";
                    else if (rowMouse.containsMouse)
                        base = "#181818";
                    else if (rowType === "clip")
                        base = "#161616";

                    if (rowRect.isChannel && !rowRect.isMutedTrack) {
                        return Qt.tint(base, Qt.rgba(rowRect.trackColor.r, rowRect.trackColor.g, rowRect.trackColor.b, isActiveTrack ? 0.12 : 0.07));
                    }
                    return base;
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 1
                    color: "#4A4A4A"
                    visible: rowRect.isActiveTrack
                    z: 2
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: "#4A4A4A"
                    visible: rowRect.isActiveTrack
                    z: 2
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 3
                    color: rowRect.isMutedTrack ? "#555555" : rowRect.trackColor
                    visible: rowRect.isChannel
                    z: 3
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: rowRect.isExpandable ? Qt.PointingHandCursor : Qt.ArrowCursor

                    onPressed: function (mouse) {
                        var target = rowRect.treeOwner;
                        if (!target)
                            return;

                        if (rowRect.isChannel) {
                            target.trackSelected(rowRect.rowClipId, rowRect.rowPropId);
                        }

                        if (mouse.button === Qt.RightButton) {
                            var pt = rowMouse.mapToItem(Overlay.overlay, mouse.x, mouse.y);
                            target.contextMenuRequested(pt.x, pt.y, rowRect.rowClipId, rowRect.rowPropId, rowRect.isMutedTrack, rowRect.isLockedTrack);
                        } else if (mouse.button === Qt.LeftButton && rowRect.isExpandable) {
                            target.toggleRowExpansion(rowRect.index);
                        }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8 + (rowRect.rowIndent * 12)
                    anchors.rightMargin: 6
                    spacing: 4
                    z: 5

                    Item {
                        width: 14
                        height: 14
                        visible: rowRect.isExpandable
                        Layout.alignment: Qt.AlignVCenter

                        Image {
                            anchors.centerIn: parent
                            width: 11
                            height: 11
                            source: "qrc:/assets/icons/chevron-down.svg"
                            sourceSize: Qt.size(11, 11)
                            opacity: 0.8
                            transformOrigin: Item.Center
                            rotation: rowRect.isExpanded ? 0 : -90

                            Behavior on rotation {
                                NumberAnimation {
                                    duration: 120
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: rowRect.isChannel
                        width: 6
                        height: 6
                        radius: 3
                        color: rowRect.isMutedTrack ? "#555555" : rowRect.trackColor
                        opacity: rowRect.isMutedTrack ? 0.4 : 1.0
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Text {
                        Layout.fillWidth: true
                        text: rowRect.rowName
                        color: {
                            if (rowRect.isMutedTrack)
                                return "#555555";
                            if (rowRect.isActiveTrack)
                                return "#FFFFFF";
                            if (rowRect.rowType === "clip")
                                return "#EDEDED";
                            if (rowRect.rowType === "group")
                                return "#AAAAAA";
                            return "#CCCCCC";
                        }
                        font.pixelSize: rowRect.rowType === "clip" ? 11 : 10
                        font.bold: rowRect.rowType === "clip" || rowRect.rowType === "group" || rowRect.isActiveTrack
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }

                    Rectangle {
                        visible: rowRect.rowKeyCount > 0
                        implicitHeight: 14
                        implicitWidth: keyCountText.implicitWidth + 8
                        radius: 7
                        color: rowRect.isActiveTrack ? "#2E2E2E" : "#1C1C1C"
                        Layout.alignment: Qt.AlignVCenter

                        Text {
                            id: keyCountText
                            anchors.centerIn: parent
                            text: "" + rowRect.rowKeyCount
                            color: rowRect.isMutedTrack ? "#444444" : (rowRect.isActiveTrack ? "#FFFFFF" : "#777777")
                            font.pixelSize: 9
                            font.family: "Monospace"
                        }
                    }

                    // ── RIGHT-SIDE ACTION BUTTONS (ALWAYS VISIBLE WITH PERMANENT WIDTH) ──
                    Row {
                        id: actionButtonsRow
                        spacing: 2
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: 60
                        Layout.preferredHeight: 18
                        visible: rowRect.isChannel

                        // 1. Visibility (Click: Toggle, Shift+Click: Solo, Alt+Click: Show All)
                        TreeActionButton {
                            isActive: rowRect.isVisibleInGraph
                            activeColor: "#38BDF8"
                            inactiveColor: "#666666"
                            iconSource: rowRect.isVisibleInGraph ? "qrc:/assets/icons/eye.svg" : "qrc:/assets/icons/eye-off.svg"
                            fallbackGlyph: rowRect.isVisibleInGraph ? "eye" : "eye-off"
                            tooltipText: "Curve Visibility (Shift+Click: Solo, Alt+Click: Show All)"
                            onClicked: function (mouse) {
                                if (rowRect.treeOwner) {
                                    var isShift = !!(mouse && (mouse.modifiers & Qt.ShiftModifier));
                                    var isAlt = !!(mouse && (mouse.modifiers & Qt.AltModifier));
                                    rowRect.treeOwner.toggleTrackVisibilityRequested(rowRect.rowClipId, rowRect.rowPropId, isShift, isAlt);
                                }
                            }
                        }

                        // 2. Mute Toggle (Volume)
                        TreeActionButton {
                            isActive: rowRect.isMutedTrack
                            activeColor: "#EF4444"
                            inactiveColor: "#888888"
                            iconSource: rowRect.isMutedTrack ? "qrc:/assets/icons/volume-off.svg" : "qrc:/assets/icons/volume.svg"
                            fallbackGlyph: rowRect.isMutedTrack ? "volume-off" : "volume"
                            tooltipText: rowRect.isMutedTrack ? "Unmute track" : "Mute track"
                            onClicked: function (mouse) {
                                if (rowRect.treeOwner)
                                    rowRect.treeOwner.toggleTrackMuteRequested(rowRect.rowClipId, rowRect.rowPropId);
                            }
                        }

                        // 3. Lock Toggle (Padlock)
                        TreeActionButton {
                            isActive: rowRect.isLockedTrack
                            activeColor: "#F59E0B"
                            inactiveColor: "#888888"
                            iconSource: rowRect.isLockedTrack ? "qrc:/assets/icons/lock.svg" : "qrc:/assets/icons/lock-open.svg"
                            fallbackGlyph: rowRect.isLockedTrack ? "lock" : "lock-open"
                            tooltipText: rowRect.isLockedTrack ? "Unlock track" : "Lock track"
                            onClicked: function (mouse) {
                                if (rowRect.treeOwner)
                                    rowRect.treeOwner.toggleTrackLockRequested(rowRect.rowClipId, rowRect.rowPropId);
                            }
                        }
                    }
                }
            }
        }
    }
}
