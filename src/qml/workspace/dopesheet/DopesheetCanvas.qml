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

    // ── Active Tool Mode ─────────────────────────────────────────
    // "pointer" | "scale" | "color-picker" | "pencil-minus"
    property string activeTool: "pointer"

    // ── Tool 2: Scale State (No visual overlays) ─────────────────
    property bool isScalingKeyframes: false
    property string scaleAnchor: "left" // "left" or "right"
    property real scaleAnchorFrame: 0
    property real scaleBaseSpan: 1
    property real currentScaleRatio: 1.0
    property real scaleStartMouseX: 0

    // ── Tool 4: Eraser Cursor State ──────────────────────────────
    property bool isErasing: false
    property real mouseCanvasX: 0
    property real mouseCanvasY: 0

    property var selectedKeyframes: []
    property bool isDraggingKeyframes: false
    property int dragDeltaFrames: 0

    // ── Multi-Target Snapping ────────────────────────────────────
    property bool snappingEnabled: true
    property bool snapToFrames: true
    property bool snapToOtherKeys: true
    property bool snapToPlayhead: true
    property real snapGuideFrame: -1
    property bool snapGuideVisible: false

    property real contentY: 0
    readonly property alias contentX: root.horizontalOffset

    // ── Signals ──────────────────────────────────────────────────
    signal clearSelectionRequested
    signal trackSelected(string clipId, string propId)
    signal keyframeSingleSelected(string clipId, string propId, int frame)
    signal keyframeSelectionRequested(string clipId, string propId, int frame, bool toggle)
    signal selectionBatchUpdated(var newSelection)
    signal moveKeyframesCommitted(int deltaFrames)
    signal contextMenuRequested(real globalX, real globalY, string clipId, string propId, int frame, bool hasKey, bool isMuted, bool isLocked)

    // Tool Signals
    signal deleteKeyframesBatchRequested(var keysToDelete)
    signal scaleKeyframesCommitted(var scaledKeyframes)
    signal applyKeyframeValueRequested(string clipId, string propId, int frame, var clonedData)

    clip: true

    readonly property real totalContentHeight: Math.max(root.height, root.treeRows.length * root.rowHeight)
    readonly property real totalContentWidth: root.contentWidthFrames * root.zoomFactor
    readonly property real activeAreaWidth: Math.max(root.totalContentWidth, root.width + Math.max(0, root.horizontalOffset) + 2000)
    readonly property real activeAreaHeight: Math.max(root.height + root.contentY + 500, root.totalContentHeight)

    readonly property var selectionBounds: {
        if (!selectedKeyframes || selectedKeyframes.length === 0)
            return {
                min: 0,
                max: 0,
                count: 0
            };

        var minF = Infinity;
        var maxF = -Infinity;
        for (var i = 0; i < selectedKeyframes.length; ++i) {
            var f = Math.round(selectedKeyframes[i].frame);
            if (f < minF)
                minF = f;
            if (f > maxF)
                maxF = f;
        }
        return {
            min: minF,
            max: maxF,
            count: selectedKeyframes.length
        };
    }

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

    // ── Snapping Calculation ─────────────────────────────────────
    function calculateSnappedDelta(rawDelta, draggedClipId, draggedPropId, draggedFrame) {
        if (!root.snappingEnabled) {
            root.snapGuideVisible = false;
            return Math.round(rawDelta);
        }

        var candidateDelta = root.snapToFrames ? Math.round(rawDelta) : rawDelta;
        var targetFrame = draggedFrame + candidateDelta;
        var thresholdPx = 8;
        var thresholdFrames = Math.max(1, Math.round(thresholdPx / root.zoomFactor));

        var bestSnapFrame = -1;
        var minDistance = thresholdFrames + 1;

        if (root.snapToPlayhead && root.activeTimelineModel) {
            var playheadFrame = root.activeTimelineModel.currentFrame !== undefined ? root.activeTimelineModel.currentFrame : 0;
            var pDist = Math.abs(targetFrame - playheadFrame);
            if (pDist <= thresholdFrames && pDist < minDistance) {
                minDistance = pDist;
                bestSnapFrame = playheadFrame;
            }
        }

        if (root.snapToOtherKeys) {
            for (var r = 0; r < root.treeRows.length; ++r) {
                var row = root.treeRows[r];
                if (!row || row.type !== "channel" || row.propId === draggedPropId)
                    continue;

                var kfs = row.keyframes || [];
                for (var k = 0; k < kfs.length; ++k) {
                    var otherKeyFrame = Math.round(Number(kfs[k]));
                    var kDist = Math.abs(targetFrame - otherKeyFrame);
                    if (kDist <= thresholdFrames && kDist < minDistance) {
                        minDistance = kDist;
                        bestSnapFrame = otherKeyFrame;
                    }
                }
            }
        }

        if (bestSnapFrame !== -1) {
            root.snapGuideFrame = bestSnapFrame;
            root.snapGuideVisible = true;
            return bestSnapFrame - draggedFrame;
        }

        root.snapGuideVisible = false;
        return root.snapToFrames ? Math.round(candidateDelta) : candidateDelta;
    }

    // ── Paint Delete (Eraser) Sweep Engine ───────────────────────
    function executeEraserAt(canvasX, canvasY) {
        var toDelete = [];
        var rPx = 14;

        for (var r = 0; r < root.treeRows.length; ++r) {
            var row = root.treeRows[r];
            if (!row || row.type !== "channel" || row.isLocked)
                continue;

            var rowTop = r * root.rowHeight;
            var rowBottom = rowTop + root.rowHeight;
            var rowCenterY = rowTop + (root.rowHeight / 2);

            if (canvasY + rPx < rowTop || canvasY - rPx > rowBottom)
                continue;

            var kfs = row.keyframes || [];
            for (var k = 0; k < kfs.length; ++k) {
                var kfFrame = Math.round(Number(kfs[k]));
                var kfX = root.frameToX(kfFrame);
                var kfY = rowCenterY;

                var dx = canvasX - kfX;
                var dy = canvasY - kfY;
                if ((dx * dx) + (dy * dy) <= (rPx * rPx)) {
                    toDelete.push({
                        clipId: row.clipId || root.activeClipId,
                        propId: row.propId,
                        frame: kfFrame
                    });
                }
            }
        }

        if (toDelete.length > 0) {
            root.deleteKeyframesBatchRequested(toDelete);
        }
    }

    // ── Tool 3: Apply Sampled Keyframe to Entire Active Selection ─
    function applySampleToSelection(sampleDetail, sampleClipId, samplePropId) {
        if (!selectedKeyframes || selectedKeyframes.length === 0)
            return;

        var val = sampleDetail ? sampleDetail.value : 0;
        var sampleData = {
            value: val,
            interp: sampleDetail ? sampleDetail.interpolation : 1,
            inX: sampleDetail ? sampleDetail.inX : 0.666,
            inY: sampleDetail ? sampleDetail.inY : 0.0,
            outX: sampleDetail ? sampleDetail.outX : 0.333,
            outY: sampleDetail ? sampleDetail.outY : 0.0
        };

        for (var i = 0; i < selectedKeyframes.length; ++i) {
            var k = selectedKeyframes[i];
            root.applyKeyframeValueRequested(k.clipId, k.propId, Math.round(k.frame), sampleData);
        }
    }

    // ── Viewport Mouse Area ───────────────────────────────────────
    MouseArea {
        id: viewportMouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        hoverEnabled: true

        readonly property var canvasView: root

        property real startX: 0
        property real startY: 0
        property real lastPanX: 0
        property real lastPanY: 0
        property bool isMarquee: false

        cursorShape: {
            if (canvasView.activeTool === "pencil-minus")
                return Qt.BlankCursor;
            if (canvasView.activeTool === "scale")
                return Qt.SizeHorCursor;
            if (canvasView.activeTool === "color-picker")
                return Qt.PointingHandCursor;
            return Qt.ArrowCursor;
        }

        onPressed: function (mouse) {
            var canvasX = mouse.x + canvasView.horizontalOffset;
            var canvasY = mouse.y + canvasView.contentY;
            var f = canvasView.xToFrame(canvasX);
            var rowIdx = Math.floor(canvasY / canvasView.rowHeight);
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

                // Eraser tool
                if (canvasView.activeTool === "pencil-minus") {
                    canvasView.isErasing = true;
                    canvasView.executeEraserAt(canvasX, canvasY);
                    return;
                }

                // Scale tool: Click & drag to scale existing selection
                if (canvasView.activeTool === "scale" && canvasView.selectionBounds.count >= 2) {
                    canvasView.isScalingKeyframes = true;
                    canvasView.scaleStartMouseX = mouse.x;
                    var midF = (canvasView.selectionBounds.min + canvasView.selectionBounds.max) / 2;
                    var clickF = canvasView.xToFrame(canvasX);

                    // Anchor to the far side of where the user started dragging
                    if (clickF >= midF) {
                        canvasView.scaleAnchor = "left";
                        canvasView.scaleAnchorFrame = canvasView.selectionBounds.min;
                    } else {
                        canvasView.scaleAnchor = "right";
                        canvasView.scaleAnchorFrame = canvasView.selectionBounds.max;
                    }

                    canvasView.scaleBaseSpan = Math.max(1, canvasView.selectionBounds.max - canvasView.selectionBounds.min);
                    canvasView.currentScaleRatio = 1.0;
                    return;
                }

                if (canvasView.activeTool === "color-picker") {
                    return;
                }

                isMarquee = false;
            }
        }

        onPositionChanged: function (mouse) {
            root.mouseCanvasX = mouse.x;
            root.mouseCanvasY = mouse.y;

            if (mouse.buttons & Qt.MiddleButton) {
                var dx = mouse.x - lastPanX;
                var dy = mouse.y - lastPanY;
                canvasView.horizontalOffset -= dx;
                canvasView.contentY = Math.max(0, Math.min(canvasView.totalContentHeight - canvasView.height, canvasView.contentY - dy));
                lastPanX = mouse.x;
                lastPanY = mouse.y;
                return;
            }

            // Eraser dragging
            if ((mouse.buttons & Qt.LeftButton) && canvasView.activeTool === "pencil-minus" && canvasView.isErasing) {
                canvasView.executeEraserAt(mouse.x + canvasView.horizontalOffset, mouse.y + canvasView.contentY);
                return;
            }

            // Scale dragging (Pure cursor drag, zero visual boxes)
            if ((mouse.buttons & Qt.LeftButton) && canvasView.activeTool === "scale" && canvasView.isScalingKeyframes) {
                var deltaPx = mouse.x - canvasView.scaleStartMouseX;
                var deltaFrames = deltaPx / canvasView.zoomFactor;

                if (canvasView.scaleAnchor === "left") {
                    var newSpanLeft = canvasView.scaleBaseSpan + deltaFrames;
                    canvasView.currentScaleRatio = Math.max(0.01, newSpanLeft / canvasView.scaleBaseSpan);
                } else {
                    var newSpanRight = canvasView.scaleBaseSpan - deltaFrames;
                    canvasView.currentScaleRatio = Math.max(0.01, newSpanRight / canvasView.scaleBaseSpan);
                }
                return;
            }

            // Marquee box selection (Pointer or Scale when not scaling)
            if (mouse.buttons & Qt.LeftButton) {
                if (canvasView.isDraggingKeyframes || canvasView.isScalingKeyframes)
                    return;
                if (canvasView.activeTool === "color-picker" || canvasView.activeTool === "pencil-minus")
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
            if (canvasView.isErasing) {
                canvasView.isErasing = false;
            }

            if (canvasView.isScalingKeyframes) {
                var scaledList = [];
                for (var i = 0; i < canvasView.selectedKeyframes.length; ++i) {
                    var k = canvasView.selectedKeyframes[i];
                    var origF = Math.round(k.frame);
                    var newF = origF;

                    if (canvasView.scaleAnchor === "left") {
                        newF = Math.round(canvasView.scaleAnchorFrame + (origF - canvasView.scaleAnchorFrame) * canvasView.currentScaleRatio);
                    } else {
                        newF = Math.round(canvasView.scaleAnchorFrame - (canvasView.scaleAnchorFrame - origF) * canvasView.currentScaleRatio);
                    }

                    scaledList.push({
                        clipId: k.clipId,
                        propId: k.propId,
                        oldFrame: origF,
                        newFrame: Math.max(0, newF)
                    });
                }
                canvasView.isScalingKeyframes = false;
                canvasView.currentScaleRatio = 1.0;
                canvasView.scaleKeyframesCommitted(scaledList);
                return;
            }

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
            } else if (mouse.button === Qt.LeftButton && !canvasView.isDraggingKeyframes && !canvasView.isScalingKeyframes) {
                if (canvasView.activeTool === "pointer") {
                    if (!(mouse.modifiers & Qt.ShiftModifier)) {
                        canvasView.clearSelectionRequested();
                        canvasView.trackSelected(canvasView.activeClipId, "");
                    }
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

    // ── Main Canvas View Content ─────────────────────────────────
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

                    readonly property var canvasView: root
                    readonly property string laneClipId: (modelData && modelData.clipId) ? modelData.clipId : ""
                    readonly property string lanePropId: (modelData && modelData.propId) ? modelData.propId : ""
                    readonly property string laneType: (modelData && modelData.type) ? modelData.type : ""
                    readonly property bool isLaneMuted: !!(modelData && modelData.isMuted)
                    readonly property bool isLaneLocked: !!(modelData && modelData.isLocked)
                    readonly property color laneColor: (modelData && modelData.color) ? modelData.color : "#3B82F6"
                    readonly property var laneKeyframes: (modelData && modelData.keyframes) ? modelData.keyframes : []
                    readonly property var laneDetails: (modelData && modelData.details) ? modelData.details : []
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

                            readonly property var canvasView: laneDelegate.canvasView
                            readonly property string kfClipId: laneDelegate.laneClipId
                            readonly property string kfPropId: laneDelegate.lanePropId
                            readonly property bool kfIsMuted: laneDelegate.isLaneMuted
                            readonly property bool kfIsLocked: laneDelegate.isLaneLocked
                            readonly property color kfColor: laneDelegate.laneColor

                            readonly property int kfFrame: Math.round(Number(modelData))
                            readonly property bool isKeySelected: canvasView.isSelected(kfClipId, kfPropId, kfFrame)

                            readonly property real displayFrame: {
                                if (!isKeySelected)
                                    return kfFrame;
                                if (canvasView.isDraggingKeyframes)
                                    return kfFrame + canvasView.dragDeltaFrames;
                                if (canvasView.isScalingKeyframes) {
                                    if (canvasView.scaleAnchor === "left") {
                                        return Math.round(canvasView.scaleAnchorFrame + (kfFrame - canvasView.scaleAnchorFrame) * canvasView.currentScaleRatio);
                                    } else {
                                        return Math.round(canvasView.scaleAnchorFrame - (canvasView.scaleAnchorFrame - kfFrame) * canvasView.currentScaleRatio);
                                    }
                                }
                                return kfFrame;
                            }

                            x: canvasView.frameToX(displayFrame) - 6
                            y: (laneDelegate.height / 2) - 6
                            width: 12
                            height: 12

                            SequentialAnimation {
                                id: updateFlashAnim
                                PropertyAnimation {
                                    target: kfDiamond
                                    property: "scale"
                                    to: 1.5
                                    duration: 80
                                }
                                PropertyAnimation {
                                    target: kfDiamond
                                    property: "scale"
                                    to: 1.0
                                    duration: 120
                                }
                            }

                            Rectangle {
                                id: kfDiamond
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
                                id: kfMouse
                                anchors.fill: parent
                                anchors.margins: -4
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                preventStealing: true

                                cursorShape: {
                                    if (kfDelegate.kfIsLocked)
                                        return Qt.ArrowCursor;
                                    if (canvasView.activeTool === "pencil-minus")
                                        return Qt.BlankCursor;
                                    if (canvasView.activeTool === "scale")
                                        return Qt.SizeHorCursor;
                                    if (canvasView.activeTool === "color-picker")
                                        return Qt.PointingHandCursor;
                                    return Qt.SizeHorCursor;
                                }

                                property real startRootX: 0
                                property bool hasMoved: false

                                onPressed: function (mouse) {
                                    mouse.accepted = true;

                                    var cv = kfDelegate.canvasView;
                                    var cId = kfDelegate.kfClipId;
                                    var pId = kfDelegate.kfPropId;
                                    var f = kfDelegate.kfFrame;

                                    cv.trackSelected(cId, pId);

                                    if (mouse.button === Qt.RightButton) {
                                        if (!kfDelegate.isKeySelected) {
                                            cv.keyframeSingleSelected(cId, pId, f);
                                        }
                                        var gPt = mapToItem(Overlay.overlay, mouse.x, mouse.y);
                                        cv.contextMenuRequested(gPt.x, gPt.y, cId, pId, f, true, kfDelegate.kfIsMuted, kfDelegate.kfIsLocked);
                                        return;
                                    }

                                    if (kfDelegate.kfIsLocked)
                                        return;

                                    // Tool 4: Eraser click
                                    if (cv.activeTool === "pencil-minus") {
                                        cv.deleteKeyframesBatchRequested([
                                            {
                                                clipId: cId,
                                                propId: pId,
                                                frame: f
                                            }
                                        ]);
                                        return;
                                    }

                                    // Tool 3: Value Picker: Sample clicked keyframe and apply to selection
                                    if (cv.activeTool === "color-picker") {
                                        var details = laneDelegate.laneDetails || [];
                                        var kfDetail = null;
                                        for (var d = 0; d < details.length; ++d) {
                                            if (Math.round(details[d].frame) === f) {
                                                kfDetail = details[d];
                                                break;
                                            }
                                        }
                                        updateFlashAnim.restart();
                                        cv.applySampleToSelection(kfDetail, cId, pId);
                                        return;
                                    }

                                    // Tool 2: Scale click on keyframe starts scaling
                                    if (cv.activeTool === "scale" && cv.selectionBounds.count >= 2) {
                                        cv.isScalingKeyframes = true;
                                        cv.scaleStartMouseX = mapToItem(cv, mouse.x, 0).x;
                                        var midPoint = (cv.selectionBounds.min + cv.selectionBounds.max) / 2;
                                        if (f >= midPoint) {
                                            cv.scaleAnchor = "left";
                                            cv.scaleAnchorFrame = cv.selectionBounds.min;
                                        } else {
                                            cv.scaleAnchor = "right";
                                            cv.scaleAnchorFrame = cv.selectionBounds.max;
                                        }
                                        cv.scaleBaseSpan = Math.max(1, cv.selectionBounds.max - cv.selectionBounds.min);
                                        cv.currentScaleRatio = 1.0;
                                        return;
                                    }

                                    // Tool 1: Pointer drag
                                    hasMoved = false;
                                    startRootX = mapToItem(cv, mouse.x, 0).x;

                                    if (mouse.modifiers & Qt.ShiftModifier) {
                                        cv.keyframeSelectionRequested(cId, pId, f, true);
                                    } else if (!kfDelegate.isKeySelected) {
                                        cv.keyframeSingleSelected(cId, pId, f);
                                    }
                                }

                                onPositionChanged: function (mouse) {
                                    if (kfDelegate.kfIsLocked || !pressed || !(mouse.buttons & Qt.LeftButton))
                                        return;

                                    var cv = kfDelegate.canvasView;
                                    if (cv.activeTool === "pencil-minus" || cv.activeTool === "color-picker")
                                        return;

                                    if (cv.activeTool === "scale" && cv.isScalingKeyframes) {
                                        var curX = mapToItem(cv, mouse.x, 0).x;
                                        var deltaPx = curX - cv.scaleStartMouseX;
                                        var deltaFrames = deltaPx / cv.zoomFactor;

                                        if (cv.scaleAnchor === "left") {
                                            cv.currentScaleRatio = Math.max(0.01, (cv.scaleBaseSpan + deltaFrames) / cv.scaleBaseSpan);
                                        } else {
                                            cv.currentScaleRatio = Math.max(0.01, (cv.scaleBaseSpan - deltaFrames) / cv.scaleBaseSpan);
                                        }
                                        return;
                                    }

                                    var currentRootX = mapToItem(cv, mouse.x, 0).x;
                                    var rawDelta = (currentRootX - startRootX) / cv.zoomFactor;
                                    var delta = cv.calculateSnappedDelta(rawDelta, kfDelegate.kfClipId, kfDelegate.kfPropId, kfDelegate.kfFrame);

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
                                    cv.snapGuideVisible = false;

                                    if (cv.isScalingKeyframes) {
                                        var scaledList = [];
                                        for (var i = 0; i < cv.selectedKeyframes.length; ++i) {
                                            var k = cv.selectedKeyframes[i];
                                            var origF = Math.round(k.frame);
                                            var newF = origF;
                                            if (cv.scaleAnchor === "left") {
                                                newF = Math.round(cv.scaleAnchorFrame + (origF - cv.scaleAnchorFrame) * cv.currentScaleRatio);
                                            } else {
                                                newF = Math.round(cv.scaleAnchorFrame - (canvasView.scaleAnchorFrame - origF) * cv.currentScaleRatio);
                                            }
                                            scaledList.push({
                                                clipId: k.clipId,
                                                propId: k.propId,
                                                oldFrame: origF,
                                                newFrame: Math.max(0, newF)
                                            });
                                        }
                                        cv.isScalingKeyframes = false;
                                        cv.currentScaleRatio = 1.0;
                                        cv.scaleKeyframesCommitted(scaledList);
                                        return;
                                    }

                                    if (cv.isDraggingKeyframes) {
                                        var finalDelta = cv.dragDeltaFrames;
                                        cv.isDraggingKeyframes = false;
                                        cv.dragDeltaFrames = 0;
                                        if (finalDelta !== 0)
                                            cv.moveKeyframesCommitted(finalDelta);
                                    }
                                    hasMoved = false;
                                }

                                onCanceled: function () {
                                    var cv = kfDelegate.canvasView;
                                    cv.snapGuideVisible = false;
                                    cv.isDraggingKeyframes = false;
                                    cv.isScalingKeyframes = false;
                                    cv.dragDeltaFrames = 0;
                                    hasMoved = false;
                                }
                            }
                        }
                    }
                }
            }
        }

        // Magnetic Snap Guide Line
        Rectangle {
            x: root.frameToX(root.snapGuideFrame)
            width: 1
            height: parent.height
            color: "#38BDF8"
            z: 85
            visible: root.snapGuideVisible && root.isDraggingKeyframes
        }

        // Playhead Indicator Line
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

    // Origin Line
    Rectangle {
        x: -root.horizontalOffset
        width: 1
        height: root.height
        color: "#383838"
        z: 50
    }

    // Marquee Selection Box
    Rectangle {
        id: marqueeBox
        color: "#203B82F6"
        border.color: "#3B82F6"
        border.width: 1
        visible: false
        z: 99
    }

    // ── TOOL 4: CLEAN ERASER CURSOR REPLACEMENT ──────────────────
    Item {
        id: customEraserCursor
        anchors.fill: parent
        z: 999
        visible: root.activeTool === "pencil-minus" && viewportMouse.containsMouse

        Image {
            id: eraserImg
            width: 16
            height: 16
            // Hotspot at eraser tip bottom-left
            x: root.mouseCanvasX - 2
            y: root.mouseCanvasY - 14
            source: "qrc:/assets/icons/eraser.svg"
            sourceSize: Qt.size(16, 16)
            visible: status === Image.Ready
        }

        // Crisp vector fallback if eraser.svg isn't bundled
        Loader {
            active: eraserImg.status !== Image.Ready
            x: root.mouseCanvasX - 2
            y: root.mouseCanvasY - 14
            width: 16
            height: 16
            sourceComponent: Canvas {
                anchors.fill: parent
                renderTarget: Canvas.Image
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    ctx.strokeStyle = "#FFFFFF";
                    ctx.lineWidth = 1.3;
                    ctx.lineCap = "round";
                    ctx.lineJoin = "round";

                    // Tabler eraser path
                    ctx.beginPath();
                    ctx.moveTo(14, 15);
                    ctx.lineTo(6.5, 15);
                    ctx.lineTo(2.5, 11);
                    ctx.lineTo(10.5, 3);
                    ctx.lineTo(14.5, 7);
                    ctx.lineTo(6.5, 15);
                    ctx.stroke();

                    ctx.beginPath();
                    ctx.moveTo(13, 8.5);
                    ctx.lineTo(8.5, 4);
                    ctx.stroke();
                }
            }
        }
    }
}
