import QtQuick

Item {
    id: root
    anchors.fill: parent

    property var modelSource: null
    readonly property var activeModel: modelSource ?? (typeof timelineModel !== "undefined" ? timelineModel : null)

    property string assetId: ""
    property real sourceInFrame: 0
    property real durationFrames: 0
    property double zoomFactor: 1.0
    property bool isSelected: false
    property bool isLocked: false
    property real visibleLeft: 0
    property real visibleWidth: width

    property var cachedPeaks: null
    property string peaksKey: ""

    function bucketPixelWidth(w) {
        return Math.max(1, Math.round(Math.max(1, Math.floor(w)) / 8) * 8);
    }

    function buildCacheKey(sFrame, durF, pixelW) {
        return assetId + "|" + Math.round(sFrame) + "|" + Math.round(durF) + "|" + bucketPixelWidth(pixelW);
    }

    function fetchPeaks(pixelW, sFrame, durF) {
        if (!activeModel) {
            console.log("[ClipWaveform] activeModel is null!");
            return null;
        }
        if (!assetId) {
            console.log("[ClipWaveform] assetId is empty!");
            return null;
        }
        if (pixelW < 2 || durF < 1) {
            return null;
        }

        const key = buildCacheKey(sFrame, durF, pixelW);
        if (key.length > 0 && key === peaksKey && cachedPeaks && cachedPeaks.length > 0) {
            return cachedPeaks;
        }

        var res = activeModel.getClipWaveformPeaks(assetId, Math.max(0, Math.floor(sFrame)), Math.max(1, Math.ceil(durF)), bucketPixelWidth(pixelW));
        console.log("[ClipWaveform] getClipWaveformPeaks for " + assetId + " returned: " + (res ? res.length : "null"));
        if (res && res.length > 0) {
            cachedPeaks = res;
            peaksKey = key;
        }
        return res;
    }

    function requestRedraw() {
        cachedPeaks = null;
        peaksKey = "";
        if (waveCanvas.available) {
            waveCanvas.requestPaint();
        }
    }

    onAssetIdChanged: requestRedraw()
    onSourceInFrameChanged: requestRedraw()
    onDurationFramesChanged: requestRedraw()
    onZoomFactorChanged: requestRedraw()

    Canvas {
        id: waveCanvas
        x: root.visibleLeft
        y: 0
        width: Math.max(2, root.visibleWidth)
        height: Math.max(10, root.height)
        visible: width >= 2 && height >= 10
        opacity: root.isLocked ? 0.35 : 0.88
        renderTarget: Canvas.Image

        onPaint: {
            if (width < 2 || height < 10)
                return;

            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            const frameOffset = root.visibleLeft / Math.max(0.001, root.zoomFactor);
            const visibleDurFrames = width / Math.max(0.001, root.zoomFactor);
            const sFrame = Math.max(0, root.sourceInFrame + frameOffset);
            const durF = Math.min(visibleDurFrames, Math.max(1, root.durationFrames - frameOffset));

            const peaks = root.fetchPeaks(width, sFrame, durF);

            const midY = height * 0.5;
            const amp = Math.max(1.0, midY - 2.0);

            // baseline
            ctx.strokeStyle = root.isSelected ? Qt.rgba(0.87, 0.84, 1.0, 0.4) : Qt.rgba(0.77, 0.71, 0.99, 0.3);
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.moveTo(0, midY);
            ctx.lineTo(width, midY);
            ctx.stroke();

            if (!peaks || peaks.length === 0)
                return;

            const n = peaks.length;
            const stepX = width / n;

            // vertical peak bars
            ctx.strokeStyle = root.isSelected ? "#DDD6FE" : "#C4B5FD";
            ctx.lineWidth = Math.max(1, Math.min(3, Math.floor(stepX)));
            ctx.beginPath();

            for (var i = 0; i < n; ++i) {
                var p = peaks[i];
                if (!p)
                    continue;

                var xPos = Math.floor(i * stepX) + 0.5;
                var yTop = midY - (p.max !== undefined ? p.max : 0) * amp;
                var yBottom = midY - (p.min !== undefined ? p.min : 0) * amp;

                if (Math.abs(yBottom - yTop) < 1.5) {
                    yTop = midY - 0.75;
                    yBottom = midY + 0.75;
                }
                ctx.moveTo(xPos, yTop);
                ctx.lineTo(xPos, yBottom);
            }
            ctx.stroke();
        }

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onXChanged: requestPaint()
        onAvailableChanged: {
            if (available) {
                requestPaint();
            }
        }
        Component.onCompleted: {
            if (available) {
                requestPaint();
            }
        }
    }
}
