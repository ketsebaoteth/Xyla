import QtQuick
import QtQuick.Controls

Item {
    id: root

    property var activeTimelineModel: typeof timelineModel !== "undefined" ? timelineModel : null
    property var treeRows: []
    property real zoomFactor: 1.0
    property real horizontalOffset: 0.0 // Correct timeline origin (Frame 0 = Pixel 0)
    property real contentWidthFrames: 5000
    property real rowHeight: 24

    property var selectedKeyframes: []
    property bool isDraggingKeyframes: false
    property int dragDeltaFrames: 0

    // Vertical scroll tracking
    property real contentY: 0

    // Compatibility property for parent panels expecting Flickable.contentX
    readonly property alias contentX: root.horizontalOffset

    signal clearSelectionRequested
    signal keyframeSingleSelected(string clipId, string propId, int frame)
    signal keyframeSelectionRequested(string clipId, string propId, int frame, bool toggle)
    signal moveKeyframesCommitted(int deltaFrames)
    signal contextMenuRequested(real globalX, real globalY, string clipId, string propId, int frame, bool hasKey)

    clip: true

    readonly property real totalContentHeight: Math.max(root.height, root.treeRows.length * root.rowHeight)
    readonly property real totalContentWidth: root.contentWidthFrames * root.zoomFactor

    // Width guaranteed to stretch past the right screen edge on any zoom level
    readonly property real activeAreaWidth: Math.max(root.totalContentWidth, root.width + Math.max(0, root.horizontalOffset) + 2000)
    readonly property real activeAreaHeight: Math.max(root.height + root.contentY + 500, root.totalContentHeight)

    // Base background: Dark Void (#090909) for time < 0
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
        for (var i = 0; i < selectedKeyframes.length; ++i) {
            var k = selectedKeyframes[i];
            if (k.clipId === clipId && k.propId === propId && Math.round(k.frame) === Math.round(frame))
                return true;
        }
        return false;
    }

    function findKeyDetail(clipId, propId, frame) {
        for (var r = 0; r < root.treeRows.length; ++r) {
            var row = root.treeRows[r];
            if (row.clipId === clipId && row.propId === propId && row.details) {
                for (var d = 0; d < row.details.length; ++d) {
                    var det = row.details[d];
                    if (Math.round(det.frame) === Math.round(frame))
                        return det;
                }
            }
        }
        return null;
    }

    function applyInterpolationToSelection(mode) {
        if (!root.activeTimelineModel || selectedKeyframes.length === 0)
            return;

        for (var i = 0; i < selectedKeyframes.length; ++i) {
            var k = selectedKeyframes[i];
            var det = findKeyDetail(k.clipId, k.propId, k.frame);
            var val = det ? det.value : 0.0;
            var inX = det && det.inX !== undefined ? det.inX : 0.666;
            var inY = det && det.inY !== undefined ? det.inY : 0.0;
            var outX = det && det.outX !== undefined ? det.outX : 0.333;
            var outY = det && det.outY !== undefined ? det.outY : 0.0;

            root.activeTimelineModel.updateKeyframe(k.clipId, k.propId, k.frame, k.frame, val, mode, inX, inY, outX, outY);
        }
    }

    function deleteSelectedKeyframes() {
        if (!root.activeTimelineModel || selectedKeyframes.length === 0)
            return;

        var list = [];
        for (var i = 0; i < selectedKeyframes.length; ++i) {
            var k = selectedKeyframes[i];
            list.push({
                clipId: k.clipId,
                propId: k.propId,
                frame: k.frame
            });
        }
        root.activeTimelineModel.removeKeyframes(list);
        root.clearSelectionRequested();
    }

    function selectAllInChannel(clipId, propId) {
        for (var r = 0; r < root.treeRows.length; ++r) {
            var row = root.treeRows[r];
            if (row.clipId === clipId && row.propId === propId && row.keyframes) {
                var newSel = [];
                for (var k = 0; k < row.keyframes.length; ++k) {
                    newSel.push({
                        clipId: clipId,
                        propId: propId,
                        frame: Math.round(row.keyframes[k])
                    });
                }
                root.selectedKeyframes = newSel;
                return;
            }
        }
    }

    function selectAllInClip(clipId) {
        var newSel = [];
        for (var r = 0; r < root.treeRows.length; ++r) {
            var row = root.treeRows[r];
            if (row.clipId === clipId && row.keyframes) {
                for (var k = 0; k < row.keyframes.length; ++k) {
                    newSel.push({
                        clipId: clipId,
                        propId: row.propId,
                        frame: Math.round(row.keyframes[k])
                    });
                }
            }
        }
        root.selectedKeyframes = newSel;
    }

    function clearAllInChannel(clipId, propId) {
        if (!root.activeTimelineModel)
            return;
        for (var r = 0; r < root.treeRows.length; ++r) {
            var row = root.treeRows[r];
            if (row.clipId === clipId && row.propId === propId && row.keyframes) {
                var list = [];
                for (var k = 0; k < row.keyframes.length; ++k) {
                    list.push({
                        clipId: clipId,
                        propId: propId,
                        frame: Math.round(row.keyframes[k])
                    });
                }
                root.activeTimelineModel.removeKeyframes(list);
                root.clearSelectionRequested();
                return;
            }
        }
    }

    function clearAllInClip(clipId) {
        if (!root.activeTimelineModel)
            return;
        var list = [];
        for (var r = 0; r < root.treeRows.length; ++r) {
            var row = root.treeRows[r];
            if (row.clipId === clipId && row.keyframes) {
                for (var k = 0; k < row.keyframes.length; ++k) {
                    list.push({
                        clipId: clipId,
                        propId: row.propId,
                        frame: Math.round(row.keyframes[k])
                    });
                }
            }
        }
        root.activeTimelineModel.removeKeyframes(list);
        root.clearSelectionRequested();
    }

    // Interactive Viewport Mouse Area
    MouseArea {
        id: viewportMouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

        property real startX: 0
        property real startY: 0
        property real lastPanX: 0
        property real lastPanY: 0
        property bool isMarquee: false

        onPressed: mouse => {
            if (root.isDraggingKeyframes)
                return;

            if (mouse.button === Qt.RightButton) {
                var canvasX = mouse.x + root.horizontalOffset;
                var f = root.xToFrame(canvasX);
                var rowIdx = Math.floor((mouse.y + root.contentY) / root.rowHeight);
                var rClipId = "";
                var rPropId = "";
                if (rowIdx >= 0 && rowIdx < root.treeRows.length && root.treeRows[rowIdx].type === "channel") {
                    rClipId = root.treeRows[rowIdx].clipId;
                    rPropId = root.treeRows[rowIdx].propId;
                }
                var gPt = mapToItem(Overlay.overlay, mouse.x, mouse.y);
                root.contextMenuRequested(gPt.x, gPt.y, rClipId, rPropId, f, false);
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

        onPositionChanged: mouse => {
            if (mouse.buttons & Qt.MiddleButton) {
                var dx = mouse.x - lastPanX;
                var dy = mouse.y - lastPanY;
                root.horizontalOffset -= dx;
                root.contentY = Math.max(0, Math.min(root.totalContentHeight - root.height, root.contentY - dy));
                lastPanX = mouse.x;
                lastPanY = mouse.y;
                return;
            }

            if (mouse.buttons & Qt.LeftButton) {
                if (root.isDraggingKeyframes)
                    return;

                var mdx = mouse.x - startX;
                var mdy = mouse.y - startY;

                if (!isMarquee && (Math.abs(mdx) > 4 || Math.abs(mdy) > 4)) {
                    isMarquee = true;
                    if (!(mouse.modifiers & Qt.ShiftModifier))
                        root.clearSelectionRequested();
                }

                if (isMarquee) {
                    marqueeBox.x = Math.min(startX, mouse.x);
                    marqueeBox.y = Math.min(startY, mouse.y);
                    marqueeBox.width = Math.abs(mdx);
                    marqueeBox.height = Math.abs(mdy);
                    marqueeBox.visible = true;
                }
            }
        }

        onReleased: mouse => {
            if (isMarquee) {
                isMarquee = false;
                marqueeBox.visible = false;

                var minCanvasX = marqueeBox.x + root.horizontalOffset;
                var maxCanvasX = marqueeBox.x + marqueeBox.width + root.horizontalOffset;
                var minF = root.xToFrame(minCanvasX);
                var maxF = root.xToFrame(maxCanvasX);

                var minRow = Math.floor((marqueeBox.y + root.contentY) / root.rowHeight);
                var maxRow = Math.floor((marqueeBox.y + marqueeBox.height + root.contentY) / root.rowHeight);

                for (var r = minRow; r <= maxRow && r < root.treeRows.length; ++r) {
                    var row = root.treeRows[r];
                    if (row.type === "channel") {
                        var kfs = row.keyframes || [];
                        for (var k = 0; k < kfs.length; ++k) {
                            var kf = Math.round(kfs[k]);
                            if (kf >= minF && kf <= maxF) {
                                root.keyframeSelectionRequested(row.clipId, row.propId, kf, true);
                            }
                        }
                    }
                }
            } else if (mouse.button === Qt.LeftButton && !root.isDraggingKeyframes) {
                if (!(mouse.modifiers & Qt.ShiftModifier))
                    root.clearSelectionRequested();
            }
        }

        onWheel: wheel => {
            if ((wheel.modifiers & Qt.ControlModifier) && !(wheel.modifiers & Qt.ShiftModifier)) {
                var mouseCanvasX = wheel.x + root.horizontalOffset;
                var frameAtMouse = mouseCanvasX / root.zoomFactor;
                var mult = wheel.angleDelta.y > 0 ? 1.15 : (1.0 / 1.15);
                var newZoom = Math.max(0.1, Math.min(50.0, root.zoomFactor * mult));

                if (newZoom !== root.zoomFactor) {
                    root.zoomFactor = newZoom;
                    root.horizontalOffset = (frameAtMouse * newZoom) - wheel.x;
                }
                return;
            }

            if ((wheel.modifiers & Qt.ControlModifier) && (wheel.modifiers & Qt.ShiftModifier)) {
                var vMult = wheel.angleDelta.y > 0 ? 1.15 : (1.0 / 1.15);
                root.rowHeight = Math.max(16, Math.min(64, root.rowHeight * vMult));
                return;
            }

            if (wheel.modifiers & Qt.ShiftModifier) {
                var deltaH = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
                root.horizontalOffset -= deltaH;
                return;
            }

            root.contentY = Math.max(0, Math.min(root.totalContentHeight - root.height, root.contentY - wheel.angleDelta.y));
        }
    }

    // Active Timeline Canvas (Origin Frame 0 is at x: 0)
    Item {
        id: canvasContent
        x: -root.horizontalOffset
        y: -root.contentY
        width: root.activeAreaWidth
        height: root.activeAreaHeight

        // Active Timeline Background (Fills right to edge and all the way down)
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
                            color: "#1c1c1c"
                        }
                    }
                }
            }
        }

        // Active Animated Rows & Keyframe Diamonds
        Column {
            width: parent.width

            Repeater {
                id: laneRepeater
                model: root.treeRows

                delegate: Rectangle {
                    id: lane
                    readonly property var laneData: modelData
                    width: canvasContent.width
                    height: root.rowHeight
                    color: index % 2 === 0 ? "#141414" : "#121212"

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: "#1c1c1c"
                    }

                    Repeater {
                        model: lane.laneData.keyframes || []

                        delegate: Item {
                            id: kfDelegate
                            readonly property int kfFrame: Math.round(Number(modelData))
                            readonly property bool isKeySelected: root.isSelected(lane.laneData.clipId, lane.laneData.propId, kfFrame)

                            x: root.frameToX(kfFrame + (isKeySelected && root.isDraggingKeyframes ? root.dragDeltaFrames : 0)) - 6
                            y: (lane.height / 2) - 6
                            width: 12
                            height: 12

                            Rectangle {
                                anchors.centerIn: parent
                                width: kfDelegate.isKeySelected ? 9 : 8
                                height: kfDelegate.isKeySelected ? 9 : 8
                                rotation: 45
                                color: kfDelegate.isKeySelected ? "#F59E0B" : (lane.laneData.type === "channel" ? (lane.laneData.color || "#3B82F6") : "transparent")
                                border.color: kfDelegate.isKeySelected ? "#FEF08A" : (lane.laneData.type === "channel" ? "#93C5FD" : "#FFFFFF")
                                border.width: lane.laneData.type === "channel" ? 1 : 1.5
                            }

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.SizeHorCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                preventStealing: true

                                property real startCanvasX: 0
                                property bool hasMoved: false

                                onPressed: mouse => {
                                    mouse.accepted = true;

                                    if (mouse.button === Qt.RightButton) {
                                        if (!kfDelegate.isKeySelected) {
                                            root.keyframeSingleSelected(lane.laneData.clipId, lane.laneData.propId, kfDelegate.kfFrame);
                                        }
                                        var gPt = mapToItem(Overlay.overlay, mouse.x, mouse.y);
                                        root.contextMenuRequested(gPt.x, gPt.y, lane.laneData.clipId, lane.laneData.propId, kfDelegate.kfFrame, true);
                                        return;
                                    }

                                    hasMoved = false;
                                    startCanvasX = kfDelegate.mapToItem(canvasContent, mouse.x, 0).x;

                                    if (mouse.modifiers & Qt.ShiftModifier) {
                                        root.keyframeSelectionRequested(lane.laneData.clipId, lane.laneData.propId, kfDelegate.kfFrame, true);
                                    } else if (!kfDelegate.isKeySelected) {
                                        root.keyframeSingleSelected(lane.laneData.clipId, lane.laneData.propId, kfDelegate.kfFrame);
                                    }
                                }

                                onPositionChanged: mouse => {
                                    if (!pressed || !(mouse.buttons & Qt.LeftButton))
                                        return;

                                    var currentCanvasX = kfDelegate.mapToItem(canvasContent, mouse.x, 0).x;
                                    var delta = Math.round((currentCanvasX - startCanvasX) / root.zoomFactor);

                                    if (kfDelegate.kfFrame + delta < 0) {
                                        delta = -kfDelegate.kfFrame;
                                    }

                                    if (!hasMoved && Math.abs(delta) >= 1) {
                                        hasMoved = true;
                                        root.isDraggingKeyframes = true;
                                    }

                                    if (root.isDraggingKeyframes) {
                                        root.dragDeltaFrames = delta;
                                    }
                                }

                                onReleased: mouse => {
                                    if (root.isDraggingKeyframes) {
                                        var finalDelta = root.dragDeltaFrames;
                                        root.isDraggingKeyframes = false;
                                        root.dragDeltaFrames = 0;
                                        if (finalDelta !== 0)
                                            root.moveKeyframesCommitted(finalDelta);
                                    }
                                    hasMoved = false;
                                }
                            }
                        }
                    }
                }
            }
        }

        // Live Playhead Indicator inside canvas
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

    // Frame 0 Boundary Line
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
}
