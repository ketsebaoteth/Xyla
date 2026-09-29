import QtQuick

Rectangle {
    id: root

    property bool isAudioClip: false
    property bool isTextClip: false
    property bool isLocked: false
    property bool isSelected: false
    property bool isDragging: false
    property bool isTrimming: false
    property real visibleLeft: 0
    property real visibleWidth: width

    // surface fill color based on track kind and locked state
    color: {
        if (root.isLocked)
            return "#262626";
        if (root.isAudioClip)
            return "#30673AEE";
        if (root.isTextClip)
            return "#30F59E0A";
        return "#301D3DFF";
    }

    // border highlight based on selection and active drag or trim
    border.color: {
        const active = root.isSelected || root.isDragging || root.isTrimming;
        if (active) {
            if (root.isAudioClip)
                return "#A78BFA";
            if (root.isTextClip)
                return "#FBBF24";
            return "#3B82F6";
        }
        if (root.isLocked)
            return "#383838";
        if (root.isAudioClip)
            return Qt.rgba(0.486, 0.227, 0.929, 0.55);
        if (root.isTextClip)
            return Qt.rgba(0.96, 0.62, 0.04, 0.55);
        return Qt.rgba(0.114, 0.365, 0.859, 0.5);
    }
    border.width: (root.isSelected || root.isDragging || root.isTrimming) ? 1.5 : 1.0
    radius: 2
    clip: true

    // locked diagonal stripe pattern constrained to visible viewport window
    Canvas {
        id: lockCanvas
        x: root.visibleLeft
        y: 0
        width: Math.max(2, root.visibleWidth)
        height: root.height
        visible: root.isLocked && width >= 2
        opacity: 0.18
        renderTarget: Canvas.Image

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            ctx.strokeStyle = "#ffffff";
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            var step = 14;
            for (var xPos = -height; xPos < width + height; xPos += step) {
                ctx.moveTo(xPos, height);
                ctx.lineTo(xPos + height, 0);
            }
            ctx.stroke();
        }

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onVisibleChanged: if (visible)
            requestPaint()
    }
}
