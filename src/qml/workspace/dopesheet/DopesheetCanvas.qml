import QtQuick
import QtQuick.Controls

Item {
    id: root

    property var activeTimelineModel: typeof timelineModel !== "undefined" ? timelineModel : null
    property var treeRows: []
    property real zoomFactor: 1.0
    property real horizontalOffset: 0.0
    property real contentWidthFrames: 5000
    property real rowHeight: 24
    property string activePropId: ""
    property string activeClipId: ""

    property var selectedKeyframes: []
    property bool isDraggingKeyframes: false
    property int dragDeltaFrames: 0

    property real contentY: 0
    readonly property alias contentX: root.horizontalOffset

    signal clearSelectionRequested
    signal trackSelected(string clipId, string propId)
    signal keyframeSingleSelected(string clipId, string propId, int frame)
    signal keyframeSelectionRequested(string clipId, string propId, int frame, bool toggle)
    signal selectionBatchUpdated(var newSelection)
    signal moveKeyframesCommitted(int deltaFrames)
    signal contextMenuRequested(real globalX, real globalY, string clipId, string propId, int frame, bool hasKey, bool isMuted, bool isLocked)

    clip: true

    readonly property real totalContentHeight: Math.max(root.height, root.treeRows.length * root.rowHeight)
    readonly property real totalContentWidth: root.contentWidthFrames * root.zoomFactor
    readonly property real activeAreaWidth: Math.max(root.totalContentWidth, root.width + Math.max(0, root.horizontalOffset) + 2000)
    readonly property real activeAreaHeight: Math.max(root.height + root.contentY + 500, root.totalContentHeight)

    Rectangle {
        anchors.fill: parent
        color: "#090909"
    }

    function frameToX(f) {
        return f * zoomFactor;
    }
    function xToFrame(xPx) {
        return Math.max(0, Math.round(xPx / zoomFactor));
    }

    function isSelected(clipId, propId, frame) {
        if (!selectedKeyframes)
            return false;
        var fRound = Math.round(frame);
        for (var i = 0; i < selectedKeyframes.length; ++i) {
            var k = selectedKeyframes[i];
            if (Math.round(k.frame) === fRound && k.propId === propId) {
                if (!clipId || !k.clipId || k.clipId === clipId)
                    return true;
            }
        }
        return false;
    }

    MouseArea {
        id: viewportMouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

        readonly property var canvasView: root

        property real startX: 0
        property real startY: 0
        property real lastPanX: 0
        property real lastPanY: 0
        property bool isMarquee: false

        onPressed: function (mouse) {
            if (canvasView.isDraggingKeyframes)
                return;

            var canvasX = mouse.x + canvasView.horizontalOffset;
            var f = canvasView.xToFrame(canvasX);
            var rowIdx = Math.floor((mouse.y + canvasView.contentY) / canvasView.rowHeight);
            var rClipId = "";
            var rPropId = "";
            var rMuted = false;
            var rLocked = false;

            if (rowIdx >= 0 && rowIdx < canvasView.treeRows.length) {
                var row = canvasView.treeRows[rowIdx];
                rClipId = row.clipId || "";
                rPropId = row.propId || "";
                rMuted = !!row.isMuted;
                rLocked = !!row.isLocked;

                if (row.type === "channel") {
                    canvasView.trackSelected(rClipId, rPropId);
                }
            }

            if (mouse.button === Qt.RightButton) {
                var gPt = mapToItem(Overlay.overlay, mouse.x, mouse.y);
                canvasView.contextMenuRequested(gPt.x, gPt.y, rClipId, rPropId, f, false, rMuted, rLocked);
                return;
            }

            if (mouse.button === Qt.MiddleButton) {
                lastPanX = mouse.x;
                lastPanY = mouse.y;
                return;
            }

            if (mouse.button === Qt.LeftButton) {
                startX = mouse.x;
                startY = mouse.y;
                isMarquee = false;
            }
        }

        onPositionChanged: function (mouse) {
            if (mouse.buttons & Qt.MiddleButton) {
                var dx = mouse.x - lastPanX;
                var dy = mouse.y - lastPanY;
                canvasView.horizontalOffset -= dx;
                canvasView.contentY = Math.max(0, Math.min(canvasView.totalContentHeight - canvasView.height, canvasView.contentY - dy));
                lastPanX = mouse.x;
                lastPanY = mouse.y;
                return;
            }

            if (mouse.buttons & Qt.LeftButton) {
                if (canvasView.isDraggingKeyframes)
                    return;

                var mdx = mouse.x - startX;
                var mdy = mouse.y - startY;

                if (!isMarquee && (Math.abs(mdx) > 3 || Math.abs(mdy) > 3)) {
                    isMarquee = true;
                    marqueeBox.visible = true;
                }

                if (isMarquee) {
                    marqueeBox.x = Math.min(startX, mouse.x);
                    marqueeBox.y = Math.min(startY, mouse.y);
                    marqueeBox.width = Math.abs(mdx);
                    marqueeBox.height = Math.abs(mdy);
                }
            }
        }

        onReleased: function (mouse) {
            if (isMarquee) {
                isMarquee = false;
                marqueeBox.visible = false;

                var minCanvasX = marqueeBox.x + canvasView.horizontalOffset;
                var maxCanvasX = marqueeBox.x + marqueeBox.width + canvasView.horizontalOffset;
                var minF = canvasView.xToFrame(minCanvasX);
                var maxF = canvasView.xToFrame(maxCanvasX);

                var minRow = Math.max(0, Math.floor((marqueeBox.y + canvasView.contentY) / canvasView.rowHeight));
                var maxRow = Math.min(canvasView.treeRows.length - 1, Math.floor((marqueeBox.y + marqueeBox.height + canvasView.contentY) / canvasView.rowHeight));

                var newSelection = (mouse.modifiers & Qt.ShiftModifier) ? canvasView.selectedKeyframes.slice() : [];

                for (var r = minRow; r <= maxRow; ++r) {
                    var row = canvasView.treeRows[r];
                    if (row && row.type === "channel") {
                        var kfs = row.keyframes || [];
                        for (var k = 0; k < kfs.length; ++k) {
                            var kf = Math.round(Number(kfs[k]));
                            if (kf >= minF && kf <= maxF) {
                                var alreadyIn = false;
                                for (var s = 0; s < newSelection.length; ++s) {
                                    if (newSelection[s].propId === row.propId && Math.round(newSelection[s].frame) === kf) {
                                        alreadyIn = true;
                                        break;
                                    }
                                }
                                if (!alreadyIn) {
                                    newSelection.push({
                                        clipId: row.clipId || canvasView.activeClipId,
                                        propId: row.propId,
                                        frame: kf
                                    });
                                }
                            }
                        }
                    }
                }

                canvasView.selectionBatchUpdated(newSelection);
            } else if (mouse.button === Qt.LeftButton && !canvasView.isDraggingKeyframes) {
                if (!(mouse.modifiers & Qt.ShiftModifier)) {
                    canvasView.clearSelectionRequested();
                    canvasView.trackSelected(canvasView.activeClipId, "");
                }
            }
        }

        onWheel: function (wheel) {
            if ((wheel.modifiers & Qt.ControlModifier) && !(wheel.modifiers & Qt.ShiftModifier)) {
                var mouseCanvasX = wheel.x + canvasView.horizontalOffset;
                var frameAtMouse = mouseCanvasX / canvasView.zoomFactor;
                var mult = wheel.angleDelta.y > 0 ? 1.15 : (1.0 / 1.15);
                var newZoom = Math.max(0.1, Math.min(50.0, canvasView.zoomFactor * mult));

                if (newZoom !== canvasView.zoomFactor) {
                    canvasView.zoomFactor = newZoom;
                    canvasView.horizontalOffset = (frameAtMouse * newZoom) - wheel.x;
                }
                return;
            }

            if ((wheel.modifiers & Qt.ControlModifier) && (wheel.modifiers & Qt.ShiftModifier)) {
                var vMult = wheel.angleDelta.y > 0 ? 1.15 : (1.0 / 1.15);
                canvasView.rowHeight = Math.max(16, Math.min(64, canvasView.rowHeight * vMult));
                return;
            }

            if (wheel.modifiers & Qt.ShiftModifier) {
                var deltaH = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
                canvasView.horizontalOffset -= deltaH;
                return;
            }

            canvasView.contentY = Math.max(0, Math.min(canvasView.totalContentHeight - canvasView.height, canvasView.contentY - wheel.angleDelta.y));
        }
    }

    Item {
        id: canvasContent
        x: -root.horizontalOffset
        y: -root.contentY
        width: root.activeAreaWidth
        height: root.activeAreaHeight

        Rectangle {
            anchors.fill: parent
            color: "#131313"

            Column {
                anchors.fill: parent
                Repeater {
                    model: Math.ceil(parent.height / root.rowHeight)
                    Rectangle {
                        width: parent.width
                        height: root.rowHeight
                        color: index % 2 === 0 ? "#141414" : "#121212"
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 1
                            color: "#1A1A1A"
                        }
                    }
                }
            }
        }

        Column {
            width: parent.width

            Repeater {
                id: laneRepeater
                model: root.treeRows

                delegate: Rectangle {
                    id: laneDelegate

                    required property var modelData
                    required property int index

                    // Direct resolution to root without relying on global scope IDs
                    readonly property var canvasView: root

                    readonly property string laneClipId: (modelData && modelData.clipId) ? modelData.clipId : ""
                    readonly property string lanePropId: (modelData && modelData.propId) ? modelData.propId : ""
                    readonly property string laneType: (modelData && modelData.type) ? modelData.type : ""
                    readonly property bool isLaneMuted: !!(modelData && modelData.isMuted)
                    readonly property bool isLaneLocked: !!(modelData && modelData.isLocked)
                    readonly property color laneColor: (modelData && modelData.color) ? modelData.color : "#3B82F6"
                    readonly property var laneKeyframes: (modelData && modelData.keyframes) ? modelData.keyframes : []
                    readonly property bool isLaneActive: laneType === "channel" && lanePropId === canvasView.activePropId

                    width: canvasContent.width
                    height: canvasView.rowHeight

                    color: {
                        var base = index % 2 === 0 ? "#141414" : "#121212";
                        if (isLaneActive)
                            base = "#202020";
                        else if (isLaneMuted)
                            base = "#0E0E0E";

                        if (laneType === "channel" && !isLaneMuted) {
                            return Qt.tint(base, Qt.rgba(laneColor.r, laneColor.g, laneColor.b, isLaneActive ? 0.10 : 0.05));
                        }
                        return base;
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 1
                        color: "#4A4A4A"
                        visible: laneDelegate.isLaneActive
                        z: 2
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: "#4A4A4A"
                        visible: laneDelegate.isLaneActive
                        z: 2
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: "#1A1A1A"
                        visible: !laneDelegate.isLaneActive
                    }

                    Repeater {
                        model: laneDelegate.laneKeyframes

                        delegate: Item {
                            id: kfDelegate

                            required property var modelData
                            required property int index

                            // Bound directly to parent lane and root view
                            readonly property var canvasView: laneDelegate.canvasView
                            readonly property string kfClipId: laneDelegate.laneClipId
                            readonly property string kfPropId: laneDelegate.lanePropId
                            readonly property bool kfIsMuted: laneDelegate.isLaneMuted
                            readonly property bool kfIsLocked: laneDelegate.isLaneLocked
                            readonly property color kfColor: laneDelegate.laneColor

                            readonly property int kfFrame: Math.round(Number(modelData))
                            readonly property bool isKeySelected: canvasView.isSelected(kfClipId, kfPropId, kfFrame)

                            x: canvasView.frameToX(kfFrame + (isKeySelected && canvasView.isDraggingKeyframes ? canvasView.dragDeltaFrames : 0)) - 6
                            y: (laneDelegate.height / 2) - 6
                            width: 12
                            height: 12

                            Rectangle {
                                anchors.centerIn: parent
                                width: kfDelegate.isKeySelected ? 9 : 8
                                height: kfDelegate.isKeySelected ? 9 : 8
                                rotation: 45

                                color: {
                                    if (kfDelegate.isKeySelected)
                                        return "#F59E0B";
                                    if (kfDelegate.kfIsMuted)
                                        return "#383838";
                                    return kfDelegate.kfColor;
                                }

                                border.color: {
                                    if (kfDelegate.isKeySelected)
                                        return "#FEF08A";
                                    if (kfDelegate.kfIsMuted)
                                        return "#5A5A5A";
                                    return Qt.lighter(kfDelegate.kfColor, 1.3);
                                }
                                border.width: 1
                                opacity: kfDelegate.kfIsMuted ? 0.45 : 1.0
                            }

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: kfDelegate.kfIsLocked ? Qt.ArrowCursor : Qt.SizeHorCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                preventStealing: true

                                property real startRootX: 0
                                property bool hasMoved: false

                                onPressed: function (mouse) {
                                    mouse.accepted = true;

                                    var cv = kfDelegate.canvasView;
                                    var cId = kfDelegate.kfClipId;
                                    var pId = kfDelegate.kfPropId;

                                    cv.trackSelected(cId, pId);

                                    if (mouse.button === Qt.RightButton) {
                                        if (!kfDelegate.isKeySelected) {
                                            cv.keyframeSingleSelected(cId, pId, kfDelegate.kfFrame);
                                        }
                                        var gPt = mapToItem(Overlay.overlay, mouse.x, mouse.y);
                                        cv.contextMenuRequested(gPt.x, gPt.y, cId, pId, kfDelegate.kfFrame, true, kfDelegate.kfIsMuted, kfDelegate.kfIsLocked);
                                        return;
                                    }

                                    if (kfDelegate.kfIsLocked)
                                        return;

                                    hasMoved = false;
                                    startRootX = mapToItem(cv, mouse.x, 0).x;

                                    if (mouse.modifiers & Qt.ShiftModifier) {
                                        cv.keyframeSelectionRequested(cId, pId, kfDelegate.kfFrame, true);
                                    } else if (!kfDelegate.isKeySelected) {
                                        cv.keyframeSingleSelected(cId, pId, kfDelegate.kfFrame);
                                    }
                                }

                                onPositionChanged: function (mouse) {
                                    if (kfDelegate.kfIsLocked || !pressed || !(mouse.buttons & Qt.LeftButton))
                                        return;

                                    var cv = kfDelegate.canvasView;
                                    var currentRootX = mapToItem(cv, mouse.x, 0).x;
                                    var delta = Math.round((currentRootX - startRootX) / cv.zoomFactor);

                                    if (kfDelegate.kfFrame + delta < 0) {
                                        delta = -kfDelegate.kfFrame;
                                    }

                                    if (!hasMoved && Math.abs(delta) >= 1) {
                                        hasMoved = true;
                                        cv.isDraggingKeyframes = true;
                                    }

                                    if (cv.isDraggingKeyframes) {
                                        cv.dragDeltaFrames = delta;
                                    }
                                }

                                onReleased: function (mouse) {
                                    var cv = kfDelegate.canvasView;
                                    if (cv.isDraggingKeyframes) {
                                        var finalDelta = cv.dragDeltaFrames;
                                        cv.isDraggingKeyframes = false;
                                        cv.dragDeltaFrames = 0;
                                        if (finalDelta !== 0)
                                            cv.moveKeyframesCommitted(finalDelta);
                                    }
                                    hasMoved = false;
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            readonly property real pFrame: root.activeTimelineModel && root.activeTimelineModel.currentFrame !== undefined ? root.activeTimelineModel.currentFrame : 0
            x: root.frameToX(pFrame)
            width: 1
            height: parent.height
            color: "#EF4444"
            z: 80
            visible: root.activeTimelineModel !== null
        }
    }

    Rectangle {
        x: -root.horizontalOffset
        width: 1
        height: root.height
        color: "#383838"
        z: 50
    }

    Rectangle {
        id: marqueeBox
        color: "#203B82F6"
        border.color: "#3B82F6"
        border.width: 1
        visible: false
        z: 99
    }
}
