import QtQuick
import QtQuick.Controls

Item {
    id: root

    property var activeTimelineModel: typeof timelineModel !== "undefined" ? timelineModel : null
    property var treeRows: []
    property real zoomFactor: 1.0
    property real horizontalOffset: 0.0 // Correct timeline origin (Frame 0 = Pixel 0)
    property real contentWidthFrames: 5000

    property real verticalScale: 200.0
    property real verticalOffset: 0.0

    property var selectedKeyframes: []
    property string activeChannelId: ""

    // Live preview state during active drag only
    property var activeDrag: null

    signal contextMenuRequested(real globalX, real globalY, string clipId, string propId, int frame, bool hasKey)

    clip: true
    focus: true

    function frameToX(f) {
        return f * zoomFactor;
    }
    function xToFrame(xPx) {
        return Math.max(0, Math.round(xPx / zoomFactor));
    }
    function valueToY(val) {
        var centerY = graphViewport.height / 2 + verticalOffset;
        return centerY - (val * verticalScale);
    }
    function yToValue(yPx) {
        var centerY = graphViewport.height / 2 + verticalOffset;
        return (centerY - yPx) / verticalScale;
    }

    function isKeySelected(clipId, propId, frame) {
        for (var i = 0; i < selectedKeyframes.length; ++i) {
            var k = selectedKeyframes[i];
            if (k.clipId === clipId && k.propId === propId && Math.round(k.frame) === Math.round(frame))
                return true;
        }
        return false;
    }

    function setSelectedInterpolation(newInterp) {
        if (!root.activeTimelineModel || selectedKeyframes.length === 0)
            return;

        for (var r = 0; r < root.treeRows.length; ++r) {
            var row = root.treeRows[r];
            if (row.type !== "channel" || !row.details)
                continue;

            for (var k = 0; k < row.details.length; ++k) {
                var kf = row.details[k];
                if (root.isKeySelected(row.clipId, row.propId, kf.frame)) {
                    root.activeTimelineModel.updateKeyframe(row.clipId, row.propId, kf.frame, kf.frame, kf.value, newInterp, kf.inX !== undefined ? kf.inX : 0.666, kf.inY !== undefined ? kf.inY : 0.0, kf.outX !== undefined ? kf.outX : 0.333, kf.outY !== undefined ? kf.outY : 0.0);
                }
            }
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_1 || event.key === Qt.Key_L) {
            root.setSelectedInterpolation(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_2 || event.key === Qt.Key_B) {
            root.setSelectedInterpolation(2);
            event.accepted = true;
        } else if (event.key === Qt.Key_0 || event.key === Qt.Key_H) {
            root.setSelectedInterpolation(0);
            event.accepted = true;
        }
    }

    // 1. Vertical Value Ruler (Pinned Left)
    AnimationGraphValueRuler {
        id: valueRuler
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        verticalScale: root.verticalScale
        verticalOffset: root.verticalOffset
        z: 30

        onVerticalOffsetChangedByRuler: val => root.verticalOffset = val
        onVerticalScaleChangedByRuler: val => root.verticalScale = val
    }

    // 2. Main Graph Viewport
    Item {
        id: graphViewport
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: valueRuler.right
        anchors.right: parent.right
        clip: true

        // Dark void background for time < 0
        Rectangle {
            anchors.fill: parent
            color: "#0a0a0a"
        }

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
                root.forceActiveFocus();

                if (mouse.button === Qt.RightButton) {
                    var f = root.xToFrame(mouse.x + root.horizontalOffset);
                    var gPt = mapToItem(Overlay.overlay, mouse.x, mouse.y);
                    root.contextMenuRequested(gPt.x, gPt.y, "", "", f, false);
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
                    root.verticalOffset += dy;
                    lastPanX = mouse.x;
                    lastPanY = mouse.y;
                    return;
                }

                if (mouse.buttons & Qt.LeftButton) {
                    var mdx = mouse.x - startX;
                    var mdy = mouse.y - startY;

                    if (!isMarquee && (Math.abs(mdx) > 4 || Math.abs(mdy) > 4)) {
                        isMarquee = true;
                        if (!(mouse.modifiers & Qt.ShiftModifier))
                            root.selectedKeyframes = [];
                    }

                    if (isMarquee) {
                        graphMarqueeBox.x = Math.min(startX, mouse.x);
                        graphMarqueeBox.y = Math.min(startY, mouse.y);
                        graphMarqueeBox.width = Math.abs(mdx);
                        graphMarqueeBox.height = Math.abs(mdy);
                        graphMarqueeBox.visible = true;
                    }
                }
            }

            onReleased: mouse => {
                if (isMarquee) {
                    isMarquee = false;
                    graphMarqueeBox.visible = false;

                    var minCanvasX = graphMarqueeBox.x + root.horizontalOffset;
                    var maxCanvasX = graphMarqueeBox.x + graphMarqueeBox.width + root.horizontalOffset;
                    var minF = root.xToFrame(minCanvasX);
                    var maxF = root.xToFrame(maxCanvasX);

                    var maxV = root.yToValue(graphMarqueeBox.y);
                    var minV = root.yToValue(graphMarqueeBox.y + graphMarqueeBox.height);

                    var newSelection = (mouse.modifiers & Qt.ShiftModifier) ? root.selectedKeyframes.slice() : [];

                    for (var r = 0; r < root.treeRows.length; ++r) {
                        var row = root.treeRows[r];
                        if (row.type !== "channel" || !row.details)
                            continue;
                        if (root.activeChannelId !== "" && root.activeChannelId !== row.propId)
                            continue;

                        for (var k = 0; k < row.details.length; ++k) {
                            var kf = row.details[k];
                            if (kf.frame >= minF && kf.frame <= maxF && kf.value >= minV && kf.value <= maxV) {
                                newSelection.push({
                                    clipId: row.clipId,
                                    propId: row.propId,
                                    frame: kf.frame
                                });
                            }
                        }
                    }
                    root.selectedKeyframes = newSelection;
                } else if (mouse.button === Qt.LeftButton) {
                    if (!(mouse.modifiers & Qt.ShiftModifier))
                        root.selectedKeyframes = [];
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
                    var valAtMouse = root.yToValue(wheel.y);
                    var vMult = wheel.angleDelta.y > 0 ? 1.15 : (1.0 / 1.15);
                    var newVScale = Math.max(0.5, Math.min(5000.0, root.verticalScale * vMult));

                    if (newVScale !== root.verticalScale) {
                        root.verticalScale = newVScale;
                        root.verticalOffset = wheel.y - (graphViewport.height / 2) + (valAtMouse * newVScale);
                    }
                    return;
                }

                if (wheel.modifiers & Qt.ShiftModifier) {
                    var deltaH = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
                    root.horizontalOffset -= deltaH;
                    return;
                }

                root.verticalOffset += wheel.angleDelta.y;
            }
        }

        // Marquee Selection Box
        Rectangle {
            id: graphMarqueeBox
            color: "#203B82F6"
            border.color: "#3B82F6"
            border.width: 1
            visible: false
            z: 99
        }

        // Viewport Grid Canvas
        Canvas {
            id: gridCanvas
            anchors.fill: parent

            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);

                var frame0ScreenX = -root.horizontalOffset;
                if (frame0ScreenX < width) {
                    ctx.fillStyle = "#121212";
                    ctx.fillRect(Math.max(0, frame0ScreenX), 0, width - Math.max(0, frame0ScreenX), height);
                }

                var centerY = Math.round(height / 2 + root.verticalOffset);
                var targetPixelSpacing = 40;
                var step = valueRuler.calculateNiceStep(targetPixelSpacing / root.verticalScale);

                var topVal = (centerY - 0) / root.verticalScale;
                var bottomVal = (centerY - height) / root.verticalScale;
                var startVal = Math.floor(Math.min(topVal, bottomVal) / step) * step;
                var endVal = Math.ceil(Math.max(topVal, bottomVal) / step) * step;

                for (var val = startVal; val <= endVal; val += step) {
                    var y = Math.round(centerY - (val * root.verticalScale)) + 0.5;
                    var isZero = Math.abs(val) < (step * 0.001);

                    ctx.strokeStyle = isZero ? "#2b2b2b" : "#171717";
                    ctx.lineWidth = 1.0;
                    ctx.beginPath();
                    ctx.moveTo(Math.max(0, frame0ScreenX), y);
                    ctx.lineTo(width, y);
                    ctx.stroke();
                }

                if (frame0ScreenX >= 0 && frame0ScreenX <= width) {
                    ctx.strokeStyle = "#383838";
                    ctx.lineWidth = 1.0;
                    ctx.beginPath();
                    ctx.moveTo(frame0ScreenX + 0.5, 0);
                    ctx.lineTo(frame0ScreenX + 0.5, height);
                    ctx.stroke();
                }
            }

            Connections {
                target: root
                function onVerticalScaleChanged() {
                    gridCanvas.requestPaint();
                }
                function onVerticalOffsetChanged() {
                    gridCanvas.requestPaint();
                }
                function onHorizontalOffsetChanged() {
                    gridCanvas.requestPaint();
                }
                function onHeightChanged() {
                    gridCanvas.requestPaint();
                }
            }
        }

        // Real-Time Spline Canvas
        Canvas {
            id: curveCanvas
            anchors.fill: parent

            function solveT(xNorm, p1x, p2x) {
                var t = xNorm;
                for (var iter = 0; iter < 8; ++iter) {
                    var u = 1.0 - t;
                    var tt = t * t;
                    var uu = u * u;
                    var current = (3.0 * uu * t * p1x) + (3.0 * u * tt * p2x) + (tt * t);
                    var derivative = (3.0 * uu * p1x) + (6.0 * u * t * (p2x - p1x)) + (3.0 * tt * (1.0 - p2x));

                    if (Math.abs(current - xNorm) < 1e-5)
                        return t;
                    if (Math.abs(derivative) < 1e-4)
                        break;
                    t -= (current - xNorm) / derivative;
                }

                var t0 = 0.0, t1 = 1.0;
                t = xNorm;
                for (var j = 0; j < 16; ++j) {
                    var uB = 1.0 - t;
                    var curB = (3.0 * uB * uB * t * p1x) + (3.0 * uB * t * t * p2x) + (t * t * t);
                    if (Math.abs(curB - xNorm) < 1e-5)
                        return t;
                    if (xNorm > curB)
                        t0 = t;
                    else
                        t1 = t;
                    t = (t0 + t1) * 0.5;
                }
                return Math.max(0.0, Math.min(1.0, t));
            }

            function evalY(t, p1y, p2y) {
                var u = 1.0 - t;
                var tt = t * t;
                var uu = u * u;
                return (3.0 * uu * t * p1y) + (3.0 * u * tt * p2y) + (tt * t);
            }

            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);

                ctx.save();
                ctx.translate(-root.horizontalOffset, 0);

                var viewLeft = root.horizontalOffset;
                var viewRight = root.horizontalOffset + width;

                for (var r = 0; r < root.treeRows.length; ++r) {
                    var row = root.treeRows[r];
                    if (row.type !== "channel" || !row.details || row.details.length === 0)
                        continue;

                    var keys = [];
                    for (var kIdx = 0; kIdx < row.details.length; ++kIdx) {
                        var kObj = Object.assign({}, row.details[kIdx]);
                        if (root.activeDrag && root.activeDrag.propId === row.propId && root.activeDrag.origFrame === kObj.frame) {
                            if (root.activeDrag.type === "key") {
                                kObj.frame = root.activeDrag.currentFrame;
                                kObj.value = root.activeDrag.currentValue;
                            } else if (root.activeDrag.type === "handle_out") {
                                kObj.outX = root.activeDrag.outX;
                                kObj.outY = root.activeDrag.outY;
                                kObj.interp = 2;
                            } else if (root.activeDrag.type === "handle_in") {
                                kObj.inX = root.activeDrag.inX;
                                kObj.inY = root.activeDrag.inY;
                                kObj.interp = 2;
                            }
                        }
                        keys.push(kObj);
                    }

                    keys.sort(function (a, b) {
                        return a.frame - b.frame;
                    });

                    var strokeCol = row.color || "#3B82F6";
                    var isFocused = (root.activeChannelId === "" || root.activeChannelId === row.propId);

                    ctx.strokeStyle = strokeCol;
                    ctx.lineWidth = isFocused ? 1.75 : 1.0;
                    ctx.globalAlpha = isFocused ? 1.0 : 0.35;
                    ctx.beginPath();

                    var firstX = root.frameToX(keys[0].frame);
                    var firstY = root.valueToY(keys[0].value);
                    var leadInLeft = Math.min(viewLeft, 0);
                    ctx.moveTo(leadInLeft, firstY);
                    ctx.lineTo(firstX, firstY);

                    for (var i = 0; i < keys.length - 1; ++i) {
                        var k0 = keys[i];
                        var k1 = keys[i + 1];

                        var x0 = root.frameToX(k0.frame);
                        var y0 = root.valueToY(k0.value);
                        var x1 = root.frameToX(k1.frame);
                        var y1 = root.valueToY(k1.value);

                        if (x1 < viewLeft - 100 || x0 > viewRight + 100) {
                            ctx.moveTo(x1, y1);
                            continue;
                        }

                        var isDraggingThisSegment = root.activeDrag && root.activeDrag.propId === row.propId && (root.activeDrag.origFrame === k0.frame || root.activeDrag.origFrame === k1.frame);

                        var k0Interp = Number(k0.interp !== undefined ? k0.interp : 1);
                        var k1Interp = Number(k1.interp !== undefined ? k1.interp : 1);

                        var isBezier = (k0Interp === 2) || (k1Interp === 2) || (isDraggingThisSegment && root.activeDrag.type !== "key");

                        if (!isBezier && k0Interp === 0) { // Hold
                            ctx.lineTo(x1, y0);
                            ctx.lineTo(x1, y1);
                        } else if (!isBezier) { // Linear
                            ctx.lineTo(x1, y1);
                        } else { // Bezier Spline
                            var oX = Math.max(0.001, Math.min(0.999, (k0.outX !== undefined ? k0.outX : 0.333)));
                            var iX = Math.max(0.001, Math.min(0.999, (k1.inX !== undefined ? k1.inX : 0.666)));
                            var oY = (k0.outY !== undefined ? k0.outY : 0.0);
                            var iY = (k1.inY !== undefined ? k1.inY : 0.0);

                            var dx = x1 - x0;
                            var dyVal = k1.value - k0.value;

                            var p1y = (Math.abs(dyVal) > 1e-5) ? (oY / dyVal) : 0.0;
                            var p2y = (Math.abs(dyVal) > 1e-5) ? (1.0 + (iY / dyVal)) : 1.0;

                            var steps = Math.min(64, Math.max(16, Math.round(dx / 5)));
                            for (var s = 1; s <= steps; ++s) {
                                var xNorm = s / steps;
                                var t = curveCanvas.solveT(xNorm, oX, iX);
                                var yFactor = curveCanvas.evalY(t, p1y, p2y);

                                var curX = x0 + (dx * xNorm);
                                var curY = (Math.abs(dyVal) > 1e-5) ? root.valueToY(k0.value + (dyVal * yFactor)) : (y0 - ((oY * (1.0 - xNorm) + iY * xNorm) * root.verticalScale));

                                ctx.lineTo(curX, curY);
                            }
                        }
                    }

                    var lastKey = keys[keys.length - 1];
                    var lastX = root.frameToX(lastKey.frame);
                    var lastY = root.valueToY(lastKey.value);
                    ctx.lineTo(Math.max(viewRight, root.frameToX(root.contentWidthFrames)), lastY);

                    ctx.stroke();
                    ctx.globalAlpha = 1.0;
                }

                ctx.restore();
            }

            Connections {
                target: root
                function onTreeRowsChanged() {
                    curveCanvas.requestPaint();
                }
                function onVerticalScaleChanged() {
                    curveCanvas.requestPaint();
                }
                function onVerticalOffsetChanged() {
                    curveCanvas.requestPaint();
                }
                function onZoomFactorChanged() {
                    curveCanvas.requestPaint();
                }
                function onHorizontalOffsetChanged() {
                    curveCanvas.requestPaint();
                }
                function onActiveChannelIdChanged() {
                    curveCanvas.requestPaint();
                }
                function onActiveDragChanged() {
                    curveCanvas.requestPaint();
                }
            }
        }

        // Active Interactive Layer
        Item {
            id: graphContent
            x: -root.horizontalOffset
            width: root.contentWidthFrames * root.zoomFactor
            height: graphViewport.height

            Repeater {
                model: root.treeRows

                Item {
                    id: channelLayerItem
                    readonly property var channelRow: modelData
                    visible: channelRow.type === "channel" && (root.activeChannelId === "" || root.activeChannelId === channelRow.propId)
                    anchors.fill: parent

                    readonly property var rawKeys: (channelRow.details || []).slice().sort(function (a, b) {
                        return a.frame - b.frame;
                    })

                    Repeater {
                        model: channelLayerItem.rawKeys

                        Item {
                            id: kfItem
                            readonly property int kIndex: index
                            readonly property var kData: modelData
                            readonly property bool isBeingDragged: root.activeDrag && root.activeDrag.propId === channelLayerItem.channelRow.propId && root.activeDrag.origFrame === kData.frame && root.activeDrag.type === "key"

                            readonly property real liveFrame: isBeingDragged ? root.activeDrag.currentFrame : kData.frame
                            readonly property real liveValue: isBeingDragged ? root.activeDrag.currentValue : kData.value

                            x: root.frameToX(liveFrame)
                            y: root.valueToY(liveValue)
                            z: isSelected ? 10 : 1

                            readonly property bool isSelected: root.isKeySelected(channelLayerItem.channelRow.clipId, channelLayerItem.channelRow.propId, kData.frame)
                            readonly property int currentInterp: Number(kData.interp !== undefined ? kData.interp : 1)

                            readonly property real prevDx: kIndex > 0 ? Math.max(20, root.frameToX(kData.frame - channelLayerItem.rawKeys[kIndex - 1].frame)) : 80
                            readonly property real nextDx: kIndex < channelLayerItem.rawKeys.length - 1 ? Math.max(20, root.frameToX(channelLayerItem.rawKeys[kIndex + 1].frame - kData.frame)) : 80

                            // ── Tangent Handle: Incoming (Left) ──
                            Item {
                                visible: kfItem.isSelected && (kfItem.currentInterp === 2 || (kIndex > 0 && Number(channelLayerItem.rawKeys[kIndex - 1].interp) === 2))

                                readonly property bool isHandleDragged: root.activeDrag && root.activeDrag.propId === channelLayerItem.channelRow.propId && root.activeDrag.origFrame === kData.frame && root.activeDrag.type === "handle_in"
                                readonly property real liveInX: isHandleDragged ? root.activeDrag.inX : (kData.inX !== undefined ? kData.inX : 0.666)
                                readonly property real liveInY: isHandleDragged ? root.activeDrag.inY : (kData.inY !== undefined ? kData.inY : 0.0)

                                readonly property real hRelX: -kfItem.prevDx * (1.0 - liveInX)
                                readonly property real hRelY: -(liveInY * root.verticalScale)

                                Rectangle {
                                    width: Math.hypot(parent.hRelX, parent.hRelY)
                                    height: 1
                                    color: "#666666"
                                    transformOrigin: Item.Left
                                    rotation: Math.atan2(parent.hRelY, parent.hRelX) * 180 / Math.PI
                                }

                                Rectangle {
                                    x: parent.hRelX - 3.5
                                    y: parent.hRelY - 3.5
                                    width: 7
                                    height: 7
                                    radius: 3.5
                                    color: inHandleMouse.containsMouse || parent.isHandleDragged ? "#FFFFFF" : "#A0A0A0"
                                    border.color: "#181818"
                                    border.width: 1

                                    MouseArea {
                                        id: inHandleMouse
                                        anchors.fill: parent
                                        anchors.margins: -6
                                        cursorShape: Qt.PointingHandCursor
                                        preventStealing: true

                                        onPressed: mouse => {
                                            mouse.accepted = true;
                                            root.activeDrag = {
                                                type: "handle_in",
                                                clipId: channelLayerItem.channelRow.clipId,
                                                propId: channelLayerItem.channelRow.propId,
                                                origFrame: kData.frame,
                                                origValue: kData.value,
                                                inX: parent.parent.liveInX,
                                                inY: parent.parent.liveInY,
                                                outX: kData.outX !== undefined ? kData.outX : 0.333,
                                                outY: kData.outY !== undefined ? kData.outY : 0.0
                                            };
                                        }

                                        onPositionChanged: mouse => {
                                            if (!pressed || !root.activeDrag)
                                                return;
                                            var gPt = mapToItem(graphContent, mouse.x, mouse.y);
                                            var kPtX = root.frameToX(kfItem.liveFrame);
                                            var kPtY = root.valueToY(kfItem.liveValue);

                                            var maxDist = Math.max(20, kfItem.prevDx * 0.999);
                                            var distPx = Math.max(2, Math.min(maxDist, kPtX - gPt.x));
                                            var ratio = distPx / kfItem.prevDx;

                                            var normInX = Math.max(0.001, Math.min(0.999, 1.0 - ratio));
                                            var normInY = (kPtY - gPt.y) / root.verticalScale;

                                            root.activeDrag = Object.assign({}, root.activeDrag, {
                                                inX: normInX,
                                                inY: normInY
                                            });
                                        }

                                        onReleased: mouse => {
                                            if (root.activeDrag && root.activeTimelineModel) {
                                                var d = root.activeDrag;
                                                root.activeDrag = null;
                                                root.activeTimelineModel.updateKeyframe(d.clipId, d.propId, d.origFrame, d.origFrame, d.origValue, 2, d.inX, d.inY, d.outX, d.outY);
                                            } else {
                                                root.activeDrag = null;
                                            }
                                        }
                                    }
                                }
                            }

                            // ── Tangent Handle: Outgoing (Right) ──
                            Item {
                                visible: kfItem.isSelected && (kfItem.currentInterp === 2 || (kIndex < channelLayerItem.rawKeys.length - 1 && Number(channelLayerItem.rawKeys[kIndex + 1].interp) === 2))

                                readonly property bool isHandleDragged: root.activeDrag && root.activeDrag.propId === channelLayerItem.channelRow.propId && root.activeDrag.origFrame === kData.frame && root.activeDrag.type === "handle_out"
                                readonly property real liveOutX: isHandleDragged ? root.activeDrag.outX : (kData.outX !== undefined ? kData.outX : 0.333)
                                readonly property real liveOutY: isHandleDragged ? root.activeDrag.outY : (kData.outY !== undefined ? kData.outY : 0.0)

                                readonly property real hRelX: kfItem.nextDx * liveOutX
                                readonly property real hRelY: -(liveOutY * root.verticalScale)

                                Rectangle {
                                    width: Math.hypot(parent.hRelX, parent.hRelY)
                                    height: 1
                                    color: "#666666"
                                    transformOrigin: Item.Left
                                    rotation: Math.atan2(parent.hRelY, parent.hRelX) * 180 / Math.PI
                                }

                                Rectangle {
                                    x: parent.hRelX - 3.5
                                    y: parent.hRelY - 3.5
                                    width: 7
                                    height: 7
                                    radius: 3.5
                                    color: outHandleMouse.containsMouse || parent.isHandleDragged ? "#FFFFFF" : "#A0A0A0"
                                    border.color: "#181818"
                                    border.width: 1

                                    MouseArea {
                                        id: outHandleMouse
                                        anchors.fill: parent
                                        anchors.margins: -6
                                        cursorShape: Qt.PointingHandCursor
                                        preventStealing: true

                                        onPressed: mouse => {
                                            mouse.accepted = true;
                                            root.activeDrag = {
                                                type: "handle_out",
                                                clipId: channelLayerItem.channelRow.clipId,
                                                propId: channelLayerItem.channelRow.propId,
                                                origFrame: kData.frame,
                                                origValue: kData.value,
                                                inX: kData.inX !== undefined ? kData.inX : 0.666,
                                                inY: kData.inY !== undefined ? kData.inY : 0.0,
                                                outX: parent.parent.liveOutX,
                                                outY: parent.parent.liveOutY
                                            };
                                        }

                                        onPositionChanged: mouse => {
                                            if (!pressed || !root.activeDrag)
                                                return;
                                            var gPt = mapToItem(graphContent, mouse.x, mouse.y);
                                            var kPtX = root.frameToX(kfItem.liveFrame);
                                            var kPtY = root.valueToY(kfItem.liveValue);

                                            var maxDist = Math.max(20, kfItem.nextDx * 0.999);
                                            var distPx = Math.max(2, Math.min(maxDist, gPt.x - kPtX));

                                            var normOutX = Math.max(0.001, Math.min(0.999, distPx / kfItem.nextDx));
                                            var normOutY = (kPtY - gPt.y) / root.verticalScale;

                                            root.activeDrag = Object.assign({}, root.activeDrag, {
                                                outX: normOutX,
                                                outY: normOutY
                                            });
                                        }

                                        onReleased: mouse => {
                                            if (root.activeDrag && root.activeTimelineModel) {
                                                var d = root.activeDrag;
                                                root.activeDrag = null;
                                                root.activeTimelineModel.updateKeyframe(d.clipId, d.propId, d.origFrame, d.origFrame, d.origValue, 2, d.inX, d.inY, d.outX, d.outY);
                                            } else {
                                                root.activeDrag = null;
                                            }
                                        }
                                    }
                                }
                            }

                            // ── Keyframe Center Knob ──
                            Rectangle {
                                x: -4.5
                                y: -4.5
                                width: 9
                                height: 9
                                radius: 4.5
                                color: kfItem.isSelected ? "#F59E0B" : (channelLayerItem.channelRow.color || "#3B82F6")
                                border.color: kfItem.isSelected ? "#FFFFFF" : "#1a1a1a"
                                border.width: 1.5

                                MouseArea {
                                    id: knobMouse
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    cursorShape: Qt.SizeAllCursor
                                    preventStealing: true

                                    property real startCanvasX: 0
                                    property real startCanvasY: 0
                                    property real startFrame: 0
                                    property real startValue: 0
                                    property bool hasDragged: false

                                    onPressed: mouse => {
                                        mouse.accepted = true;
                                        root.forceActiveFocus();
                                        root.activeChannelId = channelLayerItem.channelRow.propId;

                                        var gPt = mapToItem(graphContent, mouse.x, mouse.y);
                                        startCanvasX = gPt.x;
                                        startCanvasY = gPt.y;
                                        startFrame = kData.frame;
                                        startValue = kData.value;
                                        hasDragged = false;

                                        if (mouse.modifiers & Qt.ShiftModifier) {
                                            var copy = root.selectedKeyframes.slice();
                                            copy.push({
                                                clipId: channelLayerItem.channelRow.clipId,
                                                propId: channelLayerItem.channelRow.propId,
                                                frame: kData.frame
                                            });
                                            root.selectedKeyframes = copy;
                                        } else {
                                            root.selectedKeyframes = [
                                                {
                                                    clipId: channelLayerItem.channelRow.clipId,
                                                    propId: channelLayerItem.channelRow.propId,
                                                    frame: kData.frame
                                                }
                                            ];
                                        }
                                    }

                                    onPositionChanged: mouse => {
                                        if (!pressed)
                                            return;

                                        var gPt = mapToItem(graphContent, mouse.x, mouse.y);
                                        var deltaPxX = gPt.x - startCanvasX;
                                        var deltaPxY = gPt.y - startCanvasY;

                                        if (!hasDragged && Math.hypot(deltaPxX, deltaPxY) > 3) {
                                            hasDragged = true;
                                            root.activeDrag = {
                                                type: "key",
                                                clipId: channelLayerItem.channelRow.clipId,
                                                propId: channelLayerItem.channelRow.propId,
                                                origFrame: startFrame,
                                                origValue: startValue,
                                                currentFrame: startFrame,
                                                currentValue: startValue,
                                                interp: kfItem.currentInterp,
                                                inX: kData.inX !== undefined ? kData.inX : 0.666,
                                                inY: kData.inY !== undefined ? kData.inY : 0.0,
                                                outX: kData.outX !== undefined ? kData.outX : 0.333,
                                                outY: kData.outY !== undefined ? kData.outY : 0.0
                                            };
                                        }

                                        if (hasDragged && root.activeDrag) {
                                            var deltaF = Math.round(deltaPxX / root.zoomFactor);
                                            var deltaV = -deltaPxY / root.verticalScale;

                                            var clampedF = Math.max(0, startFrame + deltaF);

                                            root.activeDrag = Object.assign({}, root.activeDrag, {
                                                currentFrame: clampedF,
                                                currentValue: startValue + deltaV
                                            });
                                        }
                                    }

                                    onReleased: mouse => {
                                        if (hasDragged && root.activeDrag && root.activeTimelineModel) {
                                            var d = root.activeDrag;
                                            root.activeDrag = null;
                                            root.activeTimelineModel.updateKeyframe(d.clipId, d.propId, d.origFrame, d.currentFrame, d.currentValue, d.interp, d.inX, d.inY, d.outX, d.outY);
                                        } else {
                                            root.activeDrag = null;
                                        }
                                        hasDragged = false;
                                    }
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
            x: root.frameToX(pFrame) - root.horizontalOffset
            width: 1
            height: parent.height
            color: "#EF4444"
            z: 80
            visible: root.activeTimelineModel !== null
        }
    }
}
