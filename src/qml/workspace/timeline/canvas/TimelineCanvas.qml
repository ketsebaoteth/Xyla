import QtQuick
import QtQuick.Controls

import "../"
import "../guides"
import "./"

Item {
    id: root

    property var timelineRoot: null
    property var timelineModel: null
    property var playbackManager: null
    property var mediaPool: null

    property double zoomFactor: 1.0
    property real horizontalOffset: 0.0
    property real verticalScrollOffset: 0.0
    property real contentWidth: 3600
    property string activeTool: "pointer"
    property int rulerHeight: 32

    property real snapGuideFrame: -1
    property bool isSnapLineVisible: false
    property var activeSpacingGaps: []

    property int razorHoverFrame: -1
    property int razorHoverTrack: -1
    property bool isRazorHovering: false

    signal scrollVerticalRequested(real delta)
    signal zoomRequested(real factor, real cursorCanvasX)
    signal horizontalOffsetAdjusted(real newOffset)

    clip: true

    XylaTimelineRuler {
        id: timelineRuler
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.rulerHeight
        headerWidth: 0
        zoomFactor: root.zoomFactor
        horizontalOffset: root.horizontalOffset
        contentWidth: root.contentWidth
        fps: 30.0
        z: 200

        MouseArea {
            anchors.fill: parent
            enabled: root.activeTool === "razor"
            cursorShape: Qt.CrossCursor
            hoverEnabled: true

            onPositionChanged: function (mouse) {
                root.isRazorHovering = true;
                root.razorHoverFrame = Math.round((mouse.x + root.horizontalOffset) / root.zoomFactor);
                root.razorHoverTrack = -1;
            }
            onExited: {
                root.isRazorHovering = false;
                root.razorHoverFrame = -1;
            }
            onClicked: function (mouse) {
                var cutF = Math.round((mouse.x + root.horizontalOffset) / root.zoomFactor);
                if (root.timelineModel) {
                    root.timelineModel.razorCut(cutF, -1);
                }
            }
        }
    }

    Flickable {
        id: canvasFlickable
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: timelineRuler.bottom
        anchors.bottom: parent.bottom
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: false
        contentWidth: root.contentWidth
        contentHeight: root.timelineModel ? root.timelineModel.totalTracksHeight : 0
        contentX: root.horizontalOffset
        contentY: root.verticalScrollOffset

        DragHandler {
            id: panHandler
            target: null
            acceptedButtons: Qt.MiddleButton

            property real startHoriz: 0
            property real startVert: 0

            onActiveChanged: {
                if (active) {
                    startHoriz = root.horizontalOffset;
                    startVert = root.verticalScrollOffset;
                }
            }

            onTranslationChanged: {
                if (active) {
                    var maxH = Math.max(0, root.contentWidth - root.width);
                    root.horizontalOffsetAdjusted(Math.max(0, Math.min(maxH, startHoriz - translation.x)));
                    root.scrollVerticalRequested(-translation.y);
                }
            }
        }

        WheelHandler {
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

            onWheel: function (event) {
                if (event.modifiers & Qt.ControlModifier) {
                    var delta = event.angleDelta.y;
                    if (delta !== 0) {
                        var rawPos = (event.point && event.point.position) ? event.point.position : Qt.point(width / 2, height / 2);
                        var pt = canvasFlickable.mapToItem(root, rawPos.x, rawPos.y);
                        var cursorX = pt ? pt.x : (root.width / 2);
                        root.zoomRequested(Math.pow(1.001, delta), cursorX);
                    }
                    return;
                }

                var pxX = event.pixelDelta.x !== 0 ? event.pixelDelta.x : event.angleDelta.x;
                var pxY = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y;

                if (Math.abs(pxX) > Math.abs(pxY) || (event.modifiers & Qt.ShiftModifier)) {
                    var dX = pxX !== 0 ? -pxX : -pxY;
                    var maxOffset = Math.max(0, root.contentWidth - root.width);
                    root.horizontalOffsetAdjusted(Math.max(0, Math.min(maxOffset, root.horizontalOffset + dX)));
                } else {
                    root.scrollVerticalRequested(-pxY);
                }
            }
        }

        TimelineCanvasTracks {
            id: trackLanes
            timelineModel: root.timelineModel
            contentWidth: root.contentWidth
        }

        Item {
            id: clipsLayer
            anchors.fill: parent
            z: 10

            Repeater {
                id: clipRepeater
                model: root.timelineModel ? root.timelineModel.getAllClips() : []

                TimelineClipCard {
                    timelineRoot: root.timelineRoot
                    clipData: modelData
                    zoomFactor: root.zoomFactor
                }
            }

            Connections {
                target: root.timelineModel
                ignoreUnknownSignals: true
                // refresh clip list on track count or clip model modifications
                function onTrackCountChanged() {
                    clipRepeater.model = root.timelineModel ? root.timelineModel.getAllClips() : [];
                }
                function onClipsChanged() {
                    clipRepeater.model = root.timelineModel ? root.timelineModel.getAllClips() : [];
                }
                function onDataChanged() {
                    clipRepeater.model = root.timelineModel ? root.timelineModel.getAllClips() : [];
                }
                function onModelReset() {
                    clipRepeater.model = root.timelineModel ? root.timelineModel.getAllClips() : [];
                }
                function onLayoutChanged() {
                    clipRepeater.model = root.timelineModel ? root.timelineModel.getAllClips() : [];
                }
                function onTimelineReset() {
                    clipRepeater.model = root.timelineModel ? root.timelineModel.getAllClips() : [];
                }
            }
        }

        TimelineGuidesLayer {
            id: guidesLayer
            zoomFactor: root.zoomFactor
            snapGuideFrame: root.snapGuideFrame
            isSnapLineVisible: root.isSnapLineVisible
            activeSpacingGaps: root.activeSpacingGaps
        }

        MouseArea {
            id: canvasMouse
            anchors.fill: parent
            cursorShape: root.activeTool === "razor" ? Qt.CrossCursor : Qt.ArrowCursor
            hoverEnabled: root.activeTool === "razor"
            acceptedButtons: Qt.LeftButton | Qt.RightButton

            property real startX: 0
            property real startY: 0
            property bool isMarquee: false

            onPositionChanged: function (mouse) {
                if (root.activeTool === "razor") {
                    root.isRazorHovering = true;
                    root.razorHoverFrame = Math.round(mouse.x / root.zoomFactor);
                    root.razorHoverTrack = root.timelineModel ? root.timelineModel.getTrackAtY(mouse.y) : 0;
                    return;
                }

                if (pressed && (mouse.buttons & Qt.LeftButton)) {
                    var dx = mouse.x - startX;
                    var dy = mouse.y - startY;

                    if (!isMarquee && (Math.abs(dx) > 4 || Math.abs(dy) > 4)) {
                        isMarquee = true;
                    }

                    if (isMarquee) {
                        marqueeBox.x = Math.min(startX, mouse.x);
                        marqueeBox.y = Math.min(startY, mouse.y);
                        marqueeBox.width = Math.abs(dx);
                        marqueeBox.height = Math.abs(dy);
                        marqueeBox.visible = true;

                        var sFrame = Math.round(marqueeBox.x / root.zoomFactor);
                        var eFrame = Math.round((marqueeBox.x + marqueeBox.width) / root.zoomFactor);
                        var sTrack = root.timelineModel ? root.timelineModel.getTrackAtY(marqueeBox.y) : 0;
                        var eTrack = root.timelineModel ? root.timelineModel.getTrackAtY(marqueeBox.y + marqueeBox.height) : 0;
                        var toggle = (mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier | Qt.MetaModifier)) !== 0;

                        if (root.timelineModel) {
                            root.timelineModel.selectBox(sFrame, eFrame, sTrack, eTrack, toggle);
                        }
                    }
                }
            }

            onPressed: function (mouse) {
                if (mouse.button === Qt.RightButton)
                    return;

                if (root.activeTool === "razor") {
                    var cutF = Math.round(mouse.x / root.zoomFactor);
                    var cutT = root.timelineModel ? root.timelineModel.getTrackAtY(mouse.y) : 0;
                    if (root.timelineModel) {
                        root.timelineModel.razorCut(cutF, cutT);
                    }
                    return;
                }

                startX = mouse.x;
                startY = mouse.y;
                isMarquee = false;
            }

            onReleased: function (mouse) {
                if (mouse.button === Qt.RightButton) {
                    var overlayPt = mapToItem(Overlay.overlay, mouse.x, mouse.y);
                    if (root.timelineRoot && root.timelineRoot.openContextMenu) {
                        var f = Math.round(mouse.x / root.zoomFactor);
                        var t = root.timelineModel ? root.timelineModel.getTrackAtY(mouse.y) : 0;
                        root.timelineRoot.openContextMenu(overlayPt.x, overlayPt.y, f, t, null);
                    }
                    return;
                }

                if (isMarquee) {
                    isMarquee = false;
                    marqueeBox.visible = false;
                } else if (root.activeTool !== "razor" && root.timelineModel) {
                    root.timelineModel.clearSelection();
                }
            }
        }

        Rectangle {
            id: marqueeBox
            color: "#253B82F6"
            border.color: "#3B82F6"
            border.width: 1
            visible: false
            z: 100
        }

        DropArea {
            anchors.fill: parent
            keys: ["xyla/media-asset", "text/uri-list", "text/plain"]
            z: 2

            onDropped: function (drop) {
                drop.accept(Qt.CopyAction);
                if (!root.timelineModel)
                    return;

                var raw = "";
                if (drop.formats && drop.formats.indexOf("xyla/media-asset") !== -1) {
                    raw = drop.getDataAsString("xyla/media-asset").trim();
                } else if (drop.hasText && drop.text) {
                    raw = drop.text.trim();
                } else if (drop.hasUrls && drop.urls && drop.urls.length > 0) {
                    raw = drop.urls[0].toString();
                }

                if (!raw)
                    return;

                var assetId = root.mediaPool ? root.mediaPool.getAssetId(raw) : raw;
                if (!assetId)
                    assetId = raw;

                var dur = root.mediaPool ? root.mediaPool.getAssetDurationFrames(assetId, 30.0) : 90;
                var slash = raw.lastIndexOf("/");
                var name = slash >= 0 ? raw.substring(slash + 1) : "Clip";

                var dropFrame = Math.round(drop.x / root.zoomFactor);
                var dropTrack = root.timelineModel.getTrackAtY(drop.y);

                root.timelineModel.addClip(assetId, name, dropTrack, dropFrame, dur, 0);
            }
        }
    }

    XylaPlayhead {
        id: playhead
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        timelineRoot: root.timelineRoot
        activeTimelineModel: root.timelineModel
        currentFrame: root.playbackManager ? root.playbackManager.currentFrame : 0
        zoomFactor: root.zoomFactor
        horizontalOffset: root.horizontalOffset
        playheadMargin: 0
        rulerHeight: root.rulerHeight
        headerWidth: 0
        z: 1000
    }

    RazorLine {
        id: razorGuide
        z: 800
        frame: (root.activeTool === "razor" && root.isRazorHovering) ? root.razorHoverFrame : -1
        zoomFactor: root.zoomFactor
        horizontalOffset: root.horizontalOffset
        playheadMargin: 0
        lineColor: "#ff50f0"
        lineWidth: 1
    }
}
