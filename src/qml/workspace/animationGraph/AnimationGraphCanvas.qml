import QtQuick
import QtQuick.Controls

Item {
    id: root

    readonly property var canvasRoot: root
    readonly property var canvasViewport: graphViewport

    property var activeTimelineModel: typeof timelineModel !== "undefined" ? timelineModel : null
    property var treeRows: []
    property real zoomFactor: 1.0
    property real horizontalOffset: 0.0
    property real contentWidthFrames: 5000

    property real verticalScale: 80.0
    property real verticalOffset: 0.0

    property var selectedKeyframes: []
    property string activeChannelId: ""

    property var hiddenCurves: ({})
    property int visibilityRevision: 0
    onHiddenCurvesChanged: {
        visibilityRevision++;
        curveCanvas.requestPaint();
    }

    // ── Professional Animation Graph Normalization ───────────────
    property bool normalizeEnabled: false
    onNormalizeEnabledChanged: {
        gridCanvas.requestPaint();
        curveCanvas.requestPaint();
    }

    function getChannelRange(row) {
        if (!row || !row.details || row.details.length === 0)
            return {
                min: 0,
                max: 0,
                center: 0,
                halfSpan: 1,
                isFlat: true
            };

        var minV = Infinity;
        var maxV = -Infinity;
        for (var i = 0; i < row.details.length; ++i) {
            var v = Number(row.details[i].value !== undefined ? row.details[i].value : 0);
            if (v < minV)
                minV = v;
            if (v > maxV)
                maxV = v;
        }
        if (minV === Infinity)
            return {
                min: 0,
                max: 0,
                center: 0,
                halfSpan: 1,
                isFlat: true
            };

        if (Math.abs(maxV - minV) < 1e-6)
            return {
                min: minV,
                max: maxV,
                center: minV,
                halfSpan: 1,
                isFlat: true
            };

        var c = (minV + maxV) / 2.0;
        var span = (maxV - minV) / 2.0;
        return {
            min: minV,
            max: maxV,
            center: c,
            halfSpan: span,
            isFlat: false
        };
    }

    function normalizeValue(row, rawVal) {
        if (!root.normalizeEnabled)
            return Number(rawVal);
        var rng = root.getChannelRange(row);
        if (rng.isFlat)
            return 0.0;
        return (Number(rawVal) - rng.center) / rng.halfSpan;
    }

    property var activeDrag: null
    property string activeLockAxis: ""

    signal trackSelected(string clipId, string propId)
    signal contextMenuRequested(real globalX, real globalY, string clipId, string propId, int frame, bool hasKey)
    signal selectionChanged(var newSelection)

    clip: true
    focus: true

    function frameToX(f) {
        return f * zoomFactor;
    }
    function xToFrame(xPx) {
        return Math.max(0, Math.round(xPx / zoomFactor));
    }
    function valueToY(val) {
        var vp = graphViewport;
        var h = vp ? vp.height : height;
        var centerY = h / 2 + verticalOffset;
        return centerY - (Number(val) * verticalScale);
    }
    function yToValue(yPx) {
        var vp = graphViewport;
        var h = vp ? vp.height : height;
        var centerY = h / 2 + verticalOffset;
        return (centerY - yPx) / verticalScale;
    }

    function isTrackVisible(row) {
        if (!row)
            return false;

        if (row.isVisibleInGraph !== undefined)
            return (row.isVisibleInGraph === true);

        var prop = row.propId || row.id || "";
        var clip = row.clipId || "";
        var key = (clip !== "") ? (clip + "|" + prop) : prop;

        if (root.hiddenCurves) {
            if (root.hiddenCurves[prop] === true || root.hiddenCurves[key] === true)
                return false;
        }

        return true;
    }

    function isChannelActive(row) {
        if (!row)
            return false;
        if (!root.activeChannelId || root.activeChannelId === "")
            return true;

        var prop = row.propId || row.id || "";
        if (prop === root.activeChannelId)
            return true;

        var baseProp = prop.replace(/\.[xyzrgba]$/i, "").replace(/[xyz]$/i, "");
        var baseActive = root.activeChannelId.replace(/\.[xyzrgba]$/i, "").replace(/[xyz]$/i, "");
        if (baseProp !== "" && baseProp === baseActive)
            return true;

        return false;
    }

    function isKeySelected(clipId, propId, frame) {
        if (!selectedKeyframes)
            return false;
        var fRound = Math.round(frame);
        for (var i = 0; i < selectedKeyframes.length; ++i) {
            var k = selectedKeyframes[i];
            if (k.propId === propId && Math.round(k.frame) === fRound) {
                if (!clipId || !k.clipId || k.clipId === clipId)
                    return true;
            }
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

    function deleteSelectedKeyframes() {
        if (!root.activeTimelineModel || selectedKeyframes.length === 0)
            return;
        root.activeTimelineModel.removeKeyframes(selectedKeyframes);
        root.selectedKeyframes = [];
        root.selectionChanged([]);
    }

    Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Escape) {
            root.activeLockAxis = "";
            root.activeDrag = null;
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_1 || event.key === Qt.Key_L) {
            root.setSelectedInterpolation(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_2 || event.key === Qt.Key_B) {
            root.setSelectedInterpolation(2);
            event.accepted = true;
        } else if (event.key === Qt.Key_0 || event.key === Qt.Key_H) {
            root.setSelectedInterpolation(0);
            event.accepted = true;
        } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
            root.deleteSelectedKeyframes();
            event.accepted = true;
        }
    }

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

    Item {
        id: graphViewport
        readonly property var canvasView: root

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: valueRuler.right
        anchors.right: parent.right
        clip: true

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

            onPressed: function (mouse) {
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

            onPositionChanged: function (mouse) {
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
                        if (!(mouse.modifiers & Qt.ShiftModifier)) {
                            root.selectedKeyframes = [];
                            root.selectionChanged([]);
                        }
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

            onReleased: function (mouse) {
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

                        if (!root.isTrackVisible(row))
                            continue;

                        for (var k = 0; k < row.details.length; ++k) {
                            var kf = row.details[k];
                            var testV = root.normalizeValue(row, kf.value);
                            if (kf.frame >= minF && kf.frame <= maxF && testV >= minV && testV <= maxV) {
                                var alreadyIn = false;
                                for (var s = 0; s < newSelection.length; ++s) {
                                    if (newSelection[s].propId === row.propId && Math.round(newSelection[s].frame) === Math.round(kf.frame)) {
                                        alreadyIn = true;
                                        break;
                                    }
                                }
                                if (!alreadyIn) {
                                    newSelection.push({
                                        clipId: row.clipId,
                                        propId: row.propId,
                                        frame: kf.frame
                                    });
                                }
                            }
                        }
                    }
                    root.selectedKeyframes = newSelection;
                    root.selectionChanged(newSelection);
                } else if (mouse.button === Qt.LeftButton) {
                    if (!(mouse.modifiers & Qt.ShiftModifier)) {
                        root.selectedKeyframes = [];
                        root.selectionChanged([]);
                        root.activeChannelId = "";
                        root.trackSelected("", "");
                    }
                }
            }

            onWheel: function (wheel) {
                // Horizontal Zoom: Ctrl + Wheel
                if ((wheel.modifiers & Qt.ControlModifier) && !(wheel.modifiers & Qt.ShiftModifier) && !(wheel.modifiers & Qt.AltModifier)) {
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

                // Vertical Zoom: Alt + Wheel OR Ctrl + Shift + Wheel
                if ((wheel.modifiers & Qt.AltModifier) || ((wheel.modifiers & Qt.ControlModifier) && (wheel.modifiers & Qt.ShiftModifier))) {
                    var valAtMouse = root.yToValue(wheel.y);
                    var vMult = wheel.angleDelta.y > 0 ? 1.15 : (1.0 / 1.15);
                    var newVScale = Math.max(10.0, Math.min(3000.0, root.verticalScale * vMult));

                    if (newVScale !== root.verticalScale) {
                        root.verticalScale = newVScale;
                        root.verticalOffset = wheel.y - (graphViewport.height / 2) + (valAtMouse * newVScale);
                    }
                    return;
                }

                // Horizontal Pan: Shift + Wheel
                if (wheel.modifiers & Qt.ShiftModifier) {
                    var deltaH = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
                    root.horizontalOffset -= deltaH;
                    return;
                }

                // Vertical Pan: Regular Wheel
                root.verticalOffset += wheel.angleDelta.y;
            }
        }

        Rectangle {
            id: graphMarqueeBox
            color: "#203B82F6"
            border.color: "#3B82F6"
            border.width: 1
            visible: false
            z: 90
        }

        Canvas {
            id: gridCanvas
            anchors.fill: parent

            onVisibleChanged: {
                if (visible)
                    requestPaint();
            }
            Component.onCompleted: {
                requestPaint();
            }

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

                    ctx.strokeStyle = isZero ? "#303030" : "#171717";
                    ctx.lineWidth = isZero ? 1.5 : 1.0;
                    ctx.beginPath();
                    ctx.moveTo(Math.max(0, frame0ScreenX), y);
                    ctx.lineTo(width, y);
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
                function onWidthChanged() {
                    gridCanvas.requestPaint();
                }
            }
        }

        Canvas {
            id: curveCanvas
            anchors.fill: parent

            onVisibleChanged: {
                if (visible)
                    requestPaint();
            }
            Component.onCompleted: {
                requestPaint();
            }

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

                    if (!root.isTrackVisible(row))
                        continue;

                    var rng = root.getChannelRange(row);

                    var keys = [];
                    for (var kIdx = 0; kIdx < row.details.length; ++kIdx) {
                        var kObj = Object.assign({}, row.details[kIdx]);
                        if (root.activeDrag && root.activeDrag.type === "keys") {
                            for (var dk = 0; dk < root.activeDrag.keys.length; ++dk) {
                                var dEntry = root.activeDrag.keys[dk];
                                if (dEntry.propId === row.propId && dEntry.origFrame === kObj.frame) {
                                    kObj.frame = Math.max(0, dEntry.origFrame + root.activeDrag.deltaFrame);
                                    kObj.value = dEntry.origValue + root.activeDrag.deltaValue;
                                    break;
                                }
                            }
                        } else if (root.activeDrag && root.activeDrag.propId === row.propId && root.activeDrag.origFrame === kObj.frame) {
                            if (root.activeDrag.type === "handle_out") {
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
                    var isFocused = root.isChannelActive(row);

                    ctx.strokeStyle = strokeCol;
                    ctx.lineWidth = isFocused ? 1.75 : 1.0;
                    ctx.globalAlpha = isFocused ? 1.0 : 0.4;
                    ctx.beginPath();

                    var firstVal = root.normalizeValue(row, keys[0].value);
                    var firstX = root.frameToX(keys[0].frame);
                    var firstY = root.valueToY(firstVal);
                    var leadInLeft = Math.min(viewLeft, 0);
                    ctx.moveTo(leadInLeft, firstY);
                    ctx.lineTo(firstX, firstY);

                    for (var i = 0; i < keys.length - 1; ++i) {
                        var k0 = keys[i];
                        var k1 = keys[i + 1];

                        var val0Norm = root.normalizeValue(row, k0.value);
                        var val1Norm = root.normalizeValue(row, k1.value);

                        var x0 = root.frameToX(k0.frame);
                        var y0 = root.valueToY(val0Norm);
                        var x1 = root.frameToX(k1.frame);
                        var y1 = root.valueToY(val1Norm);

                        if (x1 < viewLeft - 100 || x0 > viewRight + 100) {
                            ctx.moveTo(x1, y1);
                            continue;
                        }

                        var k0Interp = Number(k0.interp !== undefined ? k0.interp : 1);
                        var k1Interp = Number(k1.interp !== undefined ? k1.interp : 1);
                        var isBezier = (k0Interp === 2) || (k1Interp === 2);

                        if (!isBezier && k0Interp === 0) {
                            ctx.lineTo(x1, y0);
                            ctx.lineTo(x1, y1);
                        } else if (!isBezier) {
                            ctx.lineTo(x1, y1);
                        } else {
                            var oX = Math.max(0.001, Math.min(0.999, (k0.outX !== undefined ? k0.outX : 0.333)));
                            var iX = Math.max(0.001, Math.min(0.999, (k1.inX !== undefined ? k1.inX : 0.666)));
                            var oY = (k0.outY !== undefined ? k0.outY : 0.0);
                            var iY = (k1.inY !== undefined ? k1.inY : 0.0);

                            if (root.normalizeEnabled && !rng.isFlat) {
                                oY = oY / rng.halfSpan;
                                iY = iY / rng.halfSpan;
                            }

                            var dx = x1 - x0;
                            var dyVal = val1Norm - val0Norm;

                            var p1y = (Math.abs(dyVal) > 1e-5) ? (oY / dyVal) : 0.0;
                            var p2y = (Math.abs(dyVal) > 1e-5) ? (1.0 + (iY / dyVal)) : 1.0;

                            var steps = Math.min(64, Math.max(16, Math.round(dx / 5)));
                            for (var s = 1; s <= steps; ++s) {
                                var xNorm = s / steps;
                                var t = curveCanvas.solveT(xNorm, oX, iX);
                                var yFactor = curveCanvas.evalY(t, p1y, p2y);

                                var curX = x0 + (dx * xNorm);
                                var curY = (Math.abs(dyVal) > 1e-5) ? root.valueToY(val0Norm + (dyVal * yFactor)) : (y0 - ((oY * (1.0 - xNorm) + iY * xNorm) * root.verticalScale));

                                ctx.lineTo(curX, curY);
                            }
                        }
                    }

                    var lastKey = keys[keys.length - 1];
                    var lastValNorm = root.normalizeValue(row, lastKey.value);
                    var lastX = root.frameToX(lastKey.frame);
                    var lastY = root.valueToY(lastValNorm);
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
                function onVisibilityRevisionChanged() {
                    curveCanvas.requestPaint();
                }
                function onWidthChanged() {
                    curveCanvas.requestPaint();
                }
                function onHeightChanged() {
                    curveCanvas.requestPaint();
                }
            }
        }

        Item {
            id: axisGuideLine
            anchors.fill: parent
            visible: root.activeDrag !== null && root.activeLockAxis !== ""
            enabled: false
            z: 5

            Rectangle {
                visible: root.activeLockAxis === "x" && root.activeDrag !== null
                x: 0
                y: {
                    if (!root.activeDrag)
                        return 0;
                    if ((root.activeDrag.type === "handle_in" || root.activeDrag.type === "handle_out") && root.activeDrag.anchorHandleRelY !== undefined) {
                        return Math.round(root.valueToY(root.activeDrag.anchorValue) + root.activeDrag.anchorHandleRelY);
                    }
                    return Math.round(root.valueToY(root.activeDrag.anchorValue !== undefined ? root.activeDrag.anchorValue : 0.0));
                }
                width: parent.width
                height: 1
                color: "#EF4444"
                opacity: 0.85
            }

            Rectangle {
                visible: root.activeLockAxis === "y" && root.activeDrag !== null
                x: {
                    if (!root.activeDrag)
                        return 0;
                    if ((root.activeDrag.type === "handle_in" || root.activeDrag.type === "handle_out") && root.activeDrag.anchorHandleRelX !== undefined) {
                        return Math.round(root.frameToX(root.activeDrag.anchorFrame) - root.horizontalOffset + root.activeDrag.anchorHandleRelX);
                    }
                    return Math.round(root.frameToX(root.activeDrag.anchorFrame !== undefined ? root.activeDrag.anchorFrame : 0) - root.horizontalOffset);
                }
                y: 0
                width: 1
                height: parent.height
                color: "#22C55E"
                opacity: 0.85
            }
        }

        Item {
            id: graphContent
            readonly property var canvasRoot: root
            readonly property var canvasViewport: graphViewport

            x: -root.horizontalOffset
            width: root.contentWidthFrames * root.zoomFactor
            height: graphViewport.height
            z: 100

            Repeater {
                model: root.treeRows

                delegate: Item {
                    id: channelLayerItem

                    readonly property var canvasRoot: graphContent.canvasRoot
                    readonly property var canvasViewport: graphContent.canvasViewport

                    required property var modelData
                    required property int index

                    readonly property string channelClipId: (modelData && modelData.clipId) ? modelData.clipId : ""
                    readonly property string channelPropId: (modelData && modelData.propId) ? modelData.propId : ""
                    readonly property color channelColor: (modelData && modelData.color) ? modelData.color : "#3B82F6"
                    readonly property bool isChannel: (modelData && modelData.type === "channel")
                    readonly property bool isFocused: isChannel && root.isChannelActive(modelData)
                    readonly property var channelRange: root.getChannelRange(modelData)

                    readonly property bool isTrackVisible: {
                        if (modelData && modelData.isVisibleInGraph !== undefined)
                            return (modelData.isVisibleInGraph === true);
                        return root.isTrackVisible(modelData);
                    }

                    visible: isChannel && isTrackVisible
                    anchors.fill: parent

                    readonly property var rawKeys: (modelData && modelData.details) ? modelData.details.slice().sort(function (a, b) {
                        return a.frame - b.frame;
                    }) : []

                    Repeater {
                        model: channelLayerItem.rawKeys

                        delegate: Item {
                            id: kfItem

                            readonly property var canvasRoot: channelLayerItem.canvasRoot
                            readonly property var canvasViewport: channelLayerItem.canvasViewport

                            required property var modelData
                            required property int index

                            readonly property string kfClipId: channelLayerItem.channelClipId
                            readonly property string kfPropId: channelLayerItem.channelPropId
                            readonly property color kfColor: channelLayerItem.channelColor

                            readonly property var kData: modelData
                            readonly property real kfFrame: (modelData && modelData.frame !== undefined) ? Number(modelData.frame) : 0
                            readonly property real kfValue: (modelData && modelData.value !== undefined) ? Number(modelData.value) : 0

                            readonly property bool isKeyInMultiDrag: canvasRoot.activeDrag && canvasRoot.activeDrag.type === "keys" && canvasRoot.isKeySelected(kfClipId, kfPropId, kfFrame)

                            readonly property real liveFrame: isKeyInMultiDrag ? Math.max(0, kfFrame + canvasRoot.activeDrag.deltaFrame) : kfFrame
                            readonly property real liveValue: isKeyInMultiDrag ? (kfValue + canvasRoot.activeDrag.deltaValue) : kfValue

                            readonly property real liveDisplayValue: canvasRoot.normalizeValue(channelLayerItem.modelData, liveValue)

                            x: canvasRoot.frameToX(liveFrame)
                            y: canvasRoot.valueToY(liveDisplayValue)
                            z: isSelected ? 10 : 1

                            readonly property bool isSelected: canvasRoot.isKeySelected(kfClipId, kfPropId, kfFrame)
                            readonly property int currentInterp: Number(modelData && modelData.interp !== undefined ? modelData.interp : 1)

                            readonly property real prevDx: index > 0 ? Math.max(20, canvasRoot.frameToX(kfFrame - channelLayerItem.rawKeys[index - 1].frame)) : 80
                            readonly property real nextDx: index < channelLayerItem.rawKeys.length - 1 ? Math.max(20, canvasRoot.frameToX(channelLayerItem.rawKeys[index + 1].frame - kfFrame)) : 80

                            // Tangent Handle: Incoming (Left)
                            Item {
                                visible: kfItem.isSelected && (kfItem.currentInterp === 2 || (index > 0 && Number(channelLayerItem.rawKeys[index - 1].interp) === 2))

                                readonly property bool isHandleDragged: canvasRoot.activeDrag && canvasRoot.activeDrag.propId === kfItem.kfPropId && canvasRoot.activeDrag.origFrame === kfItem.kfFrame && canvasRoot.activeDrag.type === "handle_in"
                                readonly property real liveInX: isHandleDragged ? canvasRoot.activeDrag.inX : (kData.inX !== undefined ? kData.inX : 0.666)
                                readonly property real liveInY: isHandleDragged ? canvasRoot.activeDrag.inY : (kData.inY !== undefined ? kData.inY : 0.0)

                                readonly property real scaledInY: (canvasRoot.normalizeEnabled && !channelLayerItem.channelRange.isFlat) ? (liveInY / channelLayerItem.channelRange.halfSpan) : liveInY

                                readonly property real hRelX: -kfItem.prevDx * (1.0 - liveInX)
                                readonly property real hRelY: -(scaledInY * canvasRoot.verticalScale)

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

                                        property real startViewportX: 0
                                        property real startViewportY: 0

                                        onPressed: function (mouse) {
                                            mouse.accepted = true;
                                            canvasRoot.forceActiveFocus();

                                            var vPt = mapToItem(kfItem.canvasViewport, mouse.x, mouse.y);
                                            startViewportX = vPt.x;
                                            startViewportY = vPt.y;

                                            canvasRoot.activeDrag = {
                                                type: "handle_in",
                                                clipId: kfItem.kfClipId,
                                                propId: kfItem.kfPropId,
                                                origFrame: kfItem.kfFrame,
                                                origValue: kfItem.kfValue,
                                                anchorFrame: kfItem.kfFrame,
                                                anchorValue: kfItem.kfValue,
                                                anchorHandleRelX: parent.parent.hRelX,
                                                anchorHandleRelY: parent.parent.hRelY,
                                                inX: parent.parent.liveInX,
                                                inY: parent.parent.liveInY,
                                                origInX: kData.inX !== undefined ? kData.inX : 0.666,
                                                origInY: kData.inY !== undefined ? kData.inY : 0.0,
                                                outX: kData.outX !== undefined ? kData.outX : 0.333,
                                                outY: kData.outY !== undefined ? kData.outY : 0.0
                                            };
                                        }

                                        onPositionChanged: function (mouse) {
                                            if (!pressed || !canvasRoot.activeDrag)
                                                return;

                                            var currentV = mapToItem(kfItem.canvasViewport, mouse.x, mouse.y);
                                            var kPtViewportX = canvasRoot.frameToX(kfItem.liveFrame) - canvasRoot.horizontalOffset;
                                            var kPtViewportY = canvasRoot.valueToY(kfItem.liveDisplayValue);

                                            var maxDist = Math.max(20, kfItem.prevDx * 0.999);
                                            var distPx = Math.max(2, Math.min(maxDist, currentV.x - kPtViewportX));
                                            var ratio = distPx / kfItem.prevDx;

                                            var normInX = Math.max(0.001, Math.min(0.999, 1.0 - ratio));
                                            var normInY = (kPtViewportY - currentV.y) / canvasRoot.verticalScale;

                                            if (canvasRoot.normalizeEnabled && !channelLayerItem.channelRange.isFlat)
                                                normInY = normInY * channelLayerItem.channelRange.halfSpan;

                                            var isShift = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                                            if (isShift) {
                                                var deltaPxX = currentV.x - startViewportX;
                                                var deltaPxY = currentV.y - startViewportY;

                                                if (Math.abs(deltaPxX) >= Math.abs(deltaPxY)) {
                                                    canvasRoot.activeLockAxis = "x";
                                                    normInY = canvasRoot.activeDrag.origInY !== undefined ? canvasRoot.activeDrag.origInY : 0.0;
                                                } else {
                                                    canvasRoot.activeLockAxis = "y";
                                                    normInX = canvasRoot.activeDrag.origInX !== undefined ? canvasRoot.activeDrag.origInX : 0.666;
                                                }
                                            } else {
                                                canvasRoot.activeLockAxis = "";
                                            }

                                            canvasRoot.activeDrag = Object.assign({}, canvasRoot.activeDrag, {
                                                inX: normInX,
                                                inY: normInY
                                            });
                                        }

                                        onReleased: function (mouse) {
                                            canvasRoot.activeLockAxis = "";
                                            if (canvasRoot.activeDrag && canvasRoot.activeTimelineModel) {
                                                var d = canvasRoot.activeDrag;
                                                canvasRoot.activeDrag = null;
                                                canvasRoot.activeTimelineModel.updateKeyframe(d.clipId, d.propId, d.origFrame, d.origFrame, d.origValue, 2, d.inX, d.inY, d.outX, d.outY);
                                            } else {
                                                canvasRoot.activeDrag = null;
                                            }
                                        }

                                        onCanceled: function () {
                                            canvasRoot.activeLockAxis = "";
                                            canvasRoot.activeDrag = null;
                                        }
                                    }
                                }
                            }

                            // Tangent Handle: Outgoing (Right)
                            Item {
                                visible: kfItem.isSelected && (kfItem.currentInterp === 2 || (index < channelLayerItem.rawKeys.length - 1 && Number(channelLayerItem.rawKeys[index + 1].interp) === 2))

                                readonly property bool isHandleDragged: canvasRoot.activeDrag && canvasRoot.activeDrag.propId === kfItem.kfPropId && canvasRoot.activeDrag.origFrame === kfItem.kfFrame && canvasRoot.activeDrag.type === "handle_out"
                                readonly property real liveOutX: isHandleDragged ? canvasRoot.activeDrag.outX : (kData.outX !== undefined ? kData.outX : 0.333)
                                readonly property real liveOutY: isHandleDragged ? canvasRoot.activeDrag.outY : (kData.outY !== undefined ? kData.outY : 0.0)

                                readonly property real scaledOutY: (canvasRoot.normalizeEnabled && !channelLayerItem.channelRange.isFlat) ? (liveOutY / channelLayerItem.channelRange.halfSpan) : liveOutY

                                readonly property real hRelX: kfItem.nextDx * liveOutX
                                readonly property real hRelY: -(scaledOutY * canvasRoot.verticalScale)

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

                                        property real startViewportX: 0
                                        property real startViewportY: 0

                                        onPressed: function (mouse) {
                                            mouse.accepted = true;
                                            canvasRoot.forceActiveFocus();

                                            var vPt = mapToItem(kfItem.canvasViewport, mouse.x, mouse.y);
                                            startViewportX = vPt.x;
                                            startViewportY = vPt.y;

                                            canvasRoot.activeDrag = {
                                                type: "handle_out",
                                                clipId: kfItem.kfClipId,
                                                propId: kfItem.kfPropId,
                                                origFrame: kfItem.kfFrame,
                                                origValue: kfItem.kfValue,
                                                anchorFrame: kfItem.kfFrame,
                                                anchorValue: kfItem.kfValue,
                                                anchorHandleRelX: parent.parent.hRelX,
                                                anchorHandleRelY: parent.parent.hRelY,
                                                inX: kData.inX !== undefined ? kData.inX : 0.666,
                                                inY: kData.inY !== undefined ? kData.inY : 0.0,
                                                outX: parent.parent.liveOutX,
                                                outY: parent.parent.liveOutY,
                                                origOutX: kData.outX !== undefined ? kData.outX : 0.333,
                                                origOutY: kData.outY !== undefined ? kData.outY : 0.0
                                            };
                                        }

                                        onPositionChanged: function (mouse) {
                                            if (!pressed || !canvasRoot.activeDrag)
                                                return;

                                            var currentV = mapToItem(kfItem.canvasViewport, mouse.x, mouse.y);
                                            var kPtViewportX = canvasRoot.frameToX(kfItem.liveFrame) - canvasRoot.horizontalOffset;
                                            var kPtViewportY = canvasRoot.valueToY(kfItem.liveDisplayValue);

                                            var maxDist = Math.max(20, kfItem.nextDx * 0.999);
                                            var distPx = Math.max(2, Math.min(maxDist, currentV.x - kPtViewportX));

                                            var normOutX = Math.max(0.001, Math.min(0.999, distPx / kfItem.nextDx));
                                            var normOutY = (kPtViewportY - currentV.y) / canvasRoot.verticalScale;

                                            if (canvasRoot.normalizeEnabled && !channelLayerItem.channelRange.isFlat)
                                                normOutY = normOutY * channelLayerItem.channelRange.halfSpan;

                                            var isShift = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                                            if (isShift) {
                                                var deltaPxX = currentV.x - startViewportX;
                                                var deltaPxY = currentV.y - startViewportY;

                                                if (Math.abs(deltaPxX) >= Math.abs(deltaPxY)) {
                                                    canvasRoot.activeLockAxis = "x";
                                                    normOutY = canvasRoot.activeDrag.origOutY !== undefined ? canvasRoot.activeDrag.origOutY : 0.0;
                                                } else {
                                                    canvasRoot.activeLockAxis = "y";
                                                    normOutX = canvasRoot.activeDrag.origOutX !== undefined ? canvasRoot.activeDrag.origOutX : 0.333;
                                                }
                                            } else {
                                                canvasRoot.activeLockAxis = "";
                                            }

                                            canvasRoot.activeDrag = Object.assign({}, canvasRoot.activeDrag, {
                                                outX: normOutX,
                                                outY: normOutY
                                            });
                                        }

                                        onReleased: function (mouse) {
                                            canvasRoot.activeLockAxis = "";
                                            if (canvasRoot.activeDrag && canvasRoot.activeTimelineModel) {
                                                var d = canvasRoot.activeDrag;
                                                canvasRoot.activeDrag = null;
                                                canvasRoot.activeTimelineModel.updateKeyframe(d.clipId, d.propId, d.origFrame, d.origFrame, d.origValue, 2, d.inX, d.inY, d.outX, d.outY);
                                            } else {
                                                canvasRoot.activeDrag = null;
                                            }
                                        }

                                        onCanceled: function () {
                                            canvasRoot.activeLockAxis = "";
                                            canvasRoot.activeDrag = null;
                                        }
                                    }
                                }
                            }

                            // Keyframe Knob
                            Rectangle {
                                x: -4.5
                                y: -4.5
                                width: 9
                                height: 9
                                radius: 4.5
                                color: kfItem.isSelected ? "#F59E0B" : kfItem.kfColor
                                border.color: kfItem.isSelected ? "#FFFFFF" : "#1a1a1a"
                                border.width: 1.5

                                MouseArea {
                                    id: knobMouse
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    cursorShape: Qt.SizeAllCursor
                                    preventStealing: true

                                    property real startViewportX: 0
                                    property real startViewportY: 0
                                    property bool hasDragged: false

                                    onPressed: function (mouse) {
                                        mouse.accepted = true;
                                        canvasRoot.forceActiveFocus();
                                        canvasRoot.activeChannelId = kfItem.kfPropId;
                                        canvasRoot.trackSelected(kfItem.kfClipId, kfItem.kfPropId);

                                        var vPt = mapToItem(kfItem.canvasViewport, mouse.x, mouse.y);
                                        startViewportX = vPt.x;
                                        startViewportY = vPt.y;
                                        hasDragged = false;

                                        var alreadySelected = canvasRoot.isKeySelected(kfItem.kfClipId, kfItem.kfPropId, kfItem.kfFrame);

                                        if (mouse.modifiers & Qt.ShiftModifier) {
                                            var copy = canvasRoot.selectedKeyframes.slice();
                                            if (alreadySelected) {
                                                for (var i = copy.length - 1; i >= 0; --i) {
                                                    if (copy[i].propId === kfItem.kfPropId && Math.round(copy[i].frame) === Math.round(kfItem.kfFrame)) {
                                                        copy.splice(i, 1);
                                                        break;
                                                    }
                                                }
                                            } else {
                                                copy.push({
                                                    clipId: kfItem.kfClipId,
                                                    propId: kfItem.kfPropId,
                                                    frame: kfItem.kfFrame
                                                });
                                            }
                                            canvasRoot.selectedKeyframes = copy;
                                            canvasRoot.selectionChanged(copy);
                                        } else if (!alreadySelected) {
                                            var single = [
                                                {
                                                    clipId: kfItem.kfClipId,
                                                    propId: kfItem.kfPropId,
                                                    frame: kfItem.kfFrame
                                                }
                                            ];
                                            canvasRoot.selectedKeyframes = single;
                                            canvasRoot.selectionChanged(single);
                                        }

                                        var dragKeys = [];
                                        for (var s = 0; s < canvasRoot.selectedKeyframes.length; ++s) {
                                            var sk = canvasRoot.selectedKeyframes[s];
                                            for (var r = 0; r < canvasRoot.treeRows.length; ++r) {
                                                var row = canvasRoot.treeRows[r];
                                                if (row.type !== "channel" || !row.details)
                                                    continue;
                                                if (row.propId === sk.propId) {
                                                    for (var kd = 0; kd < row.details.length; ++kd) {
                                                        var dItem = row.details[kd];
                                                        if (Math.round(dItem.frame) === Math.round(sk.frame)) {
                                                            dragKeys.push({
                                                                clipId: row.clipId,
                                                                propId: row.propId,
                                                                origFrame: dItem.frame,
                                                                origValue: dItem.value,
                                                                interp: Number(dItem.interp !== undefined ? dItem.interp : 1),
                                                                inX: dItem.inX !== undefined ? dItem.inX : 0.666,
                                                                inY: dItem.inY !== undefined ? dItem.inY : 0.0,
                                                                outX: dItem.outX !== undefined ? dItem.outX : 0.333,
                                                                outY: dItem.outY !== undefined ? dItem.outY : 0.0
                                                            });
                                                            break;
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        canvasRoot.activeDrag = {
                                            type: "keys",
                                            deltaFrame: 0,
                                            deltaValue: 0,
                                            anchorFrame: kfItem.kfFrame,
                                            anchorValue: kfItem.kfValue,
                                            keys: dragKeys
                                        };
                                    }

                                    onPositionChanged: function (mouse) {
                                        if (!pressed || !canvasRoot.activeDrag)
                                            return;

                                        var vPt = mapToItem(kfItem.canvasViewport, mouse.x, mouse.y);
                                        var deltaPxX = vPt.x - startViewportX;
                                        var deltaPxY = vPt.y - startViewportY;

                                        if (!hasDragged && Math.hypot(deltaPxX, deltaPxY) > 3) {
                                            hasDragged = true;
                                        }

                                        if (hasDragged && canvasRoot.activeDrag.type === "keys") {
                                            var isShift = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                                            var deltaF = 0;
                                            var deltaV = 0.0;

                                            if (isShift) {
                                                if (Math.abs(deltaPxX) >= Math.abs(deltaPxY)) {
                                                    canvasRoot.activeLockAxis = "x";
                                                    deltaF = Math.round(deltaPxX / canvasRoot.zoomFactor);
                                                    deltaV = 0.0;
                                                } else {
                                                    canvasRoot.activeLockAxis = "y";
                                                    deltaF = 0;
                                                    deltaV = (-deltaPxY / canvasRoot.verticalScale);
                                                    if (canvasRoot.normalizeEnabled && !channelLayerItem.channelRange.isFlat)
                                                        deltaV = deltaV * channelLayerItem.channelRange.halfSpan;
                                                }
                                            } else {
                                                canvasRoot.activeLockAxis = "";
                                                deltaF = Math.round(deltaPxX / canvasRoot.zoomFactor);
                                                deltaV = (-deltaPxY / canvasRoot.verticalScale);
                                                if (canvasRoot.normalizeEnabled && !channelLayerItem.channelRange.isFlat)
                                                    deltaV = deltaV * channelLayerItem.channelRange.halfSpan;
                                            }

                                            for (var k = 0; k < canvasRoot.activeDrag.keys.length; ++k) {
                                                if (canvasRoot.activeDrag.keys[k].origFrame + deltaF < 0) {
                                                    deltaF = -canvasRoot.activeDrag.keys[k].origFrame;
                                                }
                                            }

                                            canvasRoot.activeDrag = Object.assign({}, canvasRoot.activeDrag, {
                                                deltaFrame: deltaF,
                                                deltaValue: deltaV
                                            });
                                        }
                                    }

                                    onReleased: function (mouse) {
                                        canvasRoot.activeLockAxis = "";

                                        if (hasDragged && canvasRoot.activeDrag && canvasRoot.activeDrag.type === "keys" && canvasRoot.activeTimelineModel) {
                                            var d = canvasRoot.activeDrag;
                                            canvasRoot.activeDrag = null;

                                            var updatedSel = [];
                                            for (var i = 0; i < d.keys.length; ++i) {
                                                var item = d.keys[i];
                                                var newF = Math.max(0, item.origFrame + d.deltaFrame);
                                                var newV = item.origValue + d.deltaValue;

                                                canvasRoot.activeTimelineModel.updateKeyframe(item.clipId, item.propId, item.origFrame, newF, newV, item.interp, item.inX, item.inY, item.outX, item.outY);

                                                updatedSel.push({
                                                    clipId: item.clipId,
                                                    propId: item.propId,
                                                    frame: newF
                                                });
                                            }

                                            canvasRoot.selectedKeyframes = updatedSel;
                                            canvasRoot.selectionChanged(updatedSel);
                                        } else {
                                            canvasRoot.activeDrag = null;
                                            if (!hasDragged && !(mouse.modifiers & Qt.ShiftModifier)) {
                                                var singleKey = [
                                                    {
                                                        clipId: kfItem.kfClipId,
                                                        propId: kfItem.kfPropId,
                                                        frame: kfItem.kfFrame
                                                    }
                                                ];
                                                canvasRoot.selectedKeyframes = singleKey;
                                                canvasRoot.selectionChanged(singleKey);
                                            }
                                        }
                                        hasDragged = false;
                                    }

                                    onCanceled: function () {
                                        canvasRoot.activeLockAxis = "";
                                        canvasRoot.activeDrag = null;
                                        hasDragged = false;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
