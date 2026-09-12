import QtQuick
import QtQuick.Controls

Rectangle {
    id: rulerRoot

    width: 44
    color: "#131313"
    z: 300

    // Default 200px per 1.0 value unit (perfect for 0.0 - 1.0 Vulkan/normalized coordinates)
    property real verticalScale: 200.0
    property real verticalOffset: 0.0

    signal verticalOffsetChangedByRuler(real newOffset)
    signal verticalScaleChangedByRuler(real newScale)

    // Subtle right border separating ruler from canvas
    Rectangle {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: 1
        color: "#202020"
    }

    function calculateNiceStep(rawStep) {
        if (rawStep <= 0)
            return 0.1;
        var exp = Math.floor(Math.log10(rawStep));
        var frac = rawStep / Math.pow(10, exp);
        var niceFrac;

        if (frac < 1.5)
            niceFrac = 1.0;
        else if (frac < 3.0)
            niceFrac = 2.0;
        else if (frac < 7.0)
            niceFrac = 5.0;
        else
            niceFrac = 10.0;

        return niceFrac * Math.pow(10, exp);
    }

    function formatValue(val, step) {
        if (Math.abs(val) < (step * 0.001))
            return "0";
        if (step >= 10.0)
            return val.toFixed(0);
        if (step >= 1.0)
            return val.toFixed(0);
        if (step >= 0.1)
            return val.toFixed(1);
        if (step >= 0.01)
            return val.toFixed(2);
        return val.toFixed(3);
    }

    Canvas {
        id: rulerCanvas
        anchors.fill: parent

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            var centerY = rulerRoot.height / 2 + rulerRoot.verticalOffset;
            var targetPixelSpacing = 40;
            var rawValueStep = targetPixelSpacing / rulerRoot.verticalScale;
            var step = rulerRoot.calculateNiceStep(rawValueStep);
            var stepPx = step * rulerRoot.verticalScale;

            if (stepPx <= 4)
                return;

            var topValue = (centerY - 0) / rulerRoot.verticalScale;
            var bottomValue = (centerY - height) / rulerRoot.verticalScale;

            var startVal = Math.floor(Math.min(topValue, bottomValue) / step) * step;
            var endVal = Math.ceil(Math.max(topValue, bottomValue) / step) * step;

            ctx.font = "9px 'SF Pro Text', -apple-system, 'Segoe UI', monospace";
            ctx.textAlign = "right";
            ctx.textBaseline = "middle";

            for (var val = startVal; val <= endVal; val += step) {
                var y = Math.round(centerY - (val * rulerRoot.verticalScale));
                if (y < -10 || y > height + 10)
                    continue;

                var isZero = Math.abs(val) < (step * 0.001);

                // Subtle ticks (Apple dark aesthetic)
                ctx.strokeStyle = isZero ? "#383838" : "#242424";
                ctx.lineWidth = 1.0;
                ctx.beginPath();
                ctx.moveTo(width - (isZero ? 8 : 4), y + 0.5);
                ctx.lineTo(width, y + 0.5);
                ctx.stroke();

                // Typography
                ctx.fillStyle = isZero ? "#9a9a9a" : "#5a5a5a";
                ctx.fillText(rulerRoot.formatValue(val, step), width - 10, y);
            }
        }

        Connections {
            target: rulerRoot
            function onVerticalScaleChanged() {
                rulerCanvas.requestPaint();
            }
            function onVerticalOffsetChanged() {
                rulerCanvas.requestPaint();
            }
            function onHeightChanged() {
                rulerCanvas.requestPaint();
            }
        }
    }

    // Ruler drag & zoom interaction
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.SizeVerCursor

        property real startMouseY: 0
        property real startOffset: 0

        onPressed: mouse => {
            startMouseY = mouse.y;
            startOffset = rulerRoot.verticalOffset;
        }

        onPositionChanged: mouse => {
            if (pressed) {
                var dy = mouse.y - startMouseY;
                rulerRoot.verticalOffsetChangedByRuler(startOffset + dy);
            }
        }

        onWheel: wheel => {
            var factor = wheel.angleDelta.y > 0 ? 1.15 : 0.85;
            var newScale = Math.max(0.5, Math.min(2000.0, rulerRoot.verticalScale * factor));
            rulerRoot.verticalScaleChangedByRuler(newScale);
        }
    }
}
