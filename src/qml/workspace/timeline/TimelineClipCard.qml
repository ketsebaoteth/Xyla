import QtQuick
import QtQuick.Controls

import "./clip"

Item {
    id: root

    property var timelineRoot: null
    property var clipData: null
    property double zoomFactor: 1.0

    readonly property string clipId: clipData?.clipId ?? ""
    readonly property int trackIndex: clipData?.trackIndex ?? 0
    readonly property string clipType: String(clipData?.clipType ?? "")
    readonly property bool isAudioClip: (clipData?.isAudio === true) || (clipType === "Audio")
    readonly property bool isTextClip: (clipData?.isText === true) || (clipType === "Text")
    readonly property bool isLocked: (clipData?.isLocked === true) || (timelineModel ? timelineModel.isTrackLocked(root.trackIndex) : false)
    readonly property bool isSelected: timelineModel ? (timelineModel.selectedClipIds.indexOf(root.clipId) !== -1) : false

    readonly property string activeTool: timelineRoot?.activeTool ?? "pointer"
    readonly property bool isSlipTool: activeTool === "slip"

    // model baseline coordinates
    readonly property real modelStartFrame: Number(clipData?.startFrame ?? 0)
    readonly property real modelDurationFrames: Number(clipData?.durationFrames ?? 30)
    readonly property real modelSourceInFrame: Number(clipData?.sourceInFrame ?? 0)

    // interactive local coordinates updated on every pixel
    property real localStartFrame: modelStartFrame
    property real localDurationFrames: modelDurationFrames
    property real localSourceInFrame: modelSourceInFrame
    property int localTrackIndex: trackIndex

    property bool isLocalDragging: false
    property bool isTrimmingLeft: false
    property bool isTrimmingRight: false
    property bool isSlipping: false

    property real dragStartCanvasX: 0
    property int dragOriginFrame: 0
    property int dragOriginTrack: 0
    property int lastValidFrame: 0
    property int lastValidTrack: 0
    property real slipDeltaFrames: 0

    readonly property int assetDuration: timelineModel && clipData?.assetId ? timelineModel.getAssetDuration(clipData.assetId) : 0

    // bind directly to reactive properties so projected changes update linked clips in real time
    readonly property real displayStartFrame: localStartFrame
    readonly property int displayTrackIndex: localTrackIndex
    readonly property real displayDurationFrames: localDurationFrames

    // gather clip id along with all linked partners for unified movement
    function getMovingClipIds() {
        var idMap = {};
        var baseList = (timelineModel && timelineModel.selectedClipIds.length > 0 && timelineModel.selectedClipIds.indexOf(root.clipId) !== -1) ? timelineModel.selectedClipIds : [root.clipId];
        for (var i = 0; i < baseList.length; ++i) {
            var cid = baseList[i];
            idMap[cid] = true;
            if (timelineModel) {
                var linked = timelineModel.getLinkedClipIds(cid);
                for (var j = 0; j < linked.length; ++j) {
                    idMap[linked[j]] = true;
                }
            }
        }
        return Object.keys(idMap);
    }

    Connections {
        target: timelineModel
        ignoreUnknownSignals: true
        function onVisualFrameInvalidated() {
            if (!root.isLocalDragging && !root.isTrimmingLeft && !root.isTrimmingRight && !root.isSlipping) {
                root.localStartFrame = timelineModel.getProjectedStart(root.clipId);
                root.localTrackIndex = timelineModel.getProjectedTrack(root.clipId);
                root.localDurationFrames = timelineModel.getProjectedDuration(root.clipId);
                root.localSourceInFrame = timelineModel.getProjectedSourceIn(root.clipId);
            }
        }
    }

    // safe track bounds check prevents crashes on invalid track indices
    x: root.displayStartFrame * root.zoomFactor
    y: (timelineModel && root.displayTrackIndex >= 0 && root.displayTrackIndex < timelineModel.trackCount) ? (timelineModel.getTrackY(root.displayTrackIndex) + 4) : ((Math.max(0, root.displayTrackIndex) * 68) + 4)
    width: Math.max(16, root.displayDurationFrames * root.zoomFactor)
    height: (timelineModel && root.displayTrackIndex >= 0 && root.displayTrackIndex < timelineModel.trackCount) ? Math.max(16, timelineModel.getTrackHeight(root.displayTrackIndex) - 8) : 60

    // viewport culling calculations
    readonly property real vpLeft: timelineRoot ? Number(timelineRoot.horizontalOffset || 0) : 0
    readonly property real vpWidth: timelineRoot ? Number(timelineRoot.width || 1920) : 1920
    readonly property bool isInView: (root.x + root.width >= root.vpLeft - 100) && (root.x <= root.vpLeft + root.vpWidth + 100)
    visible: isInView

    readonly property real visibleClipLeft: Math.max(0, root.vpLeft - root.x)
    readonly property real visibleClipWidth: Math.max(0, Math.min(root.width, root.vpLeft + root.vpWidth - root.x) - visibleClipLeft)

    onClipDataChanged: {
        if (!isLocalDragging && !isTrimmingLeft && !isTrimmingRight && !isSlipping) {
            localStartFrame = modelStartFrame;
            localDurationFrames = modelDurationFrames;
            localSourceInFrame = modelSourceInFrame;
            localTrackIndex = trackIndex;
        }
    }

    ClipBody {
        id: cardBody
        anchors.fill: parent
        isAudioClip: root.isAudioClip
        isTextClip: root.isTextClip
        isLocked: root.isLocked
        isSelected: root.isSelected
        isDragging: root.isLocalDragging
        isTrimming: root.isTrimmingLeft || root.isTrimmingRight
        visibleLeft: root.visibleClipLeft
        visibleWidth: root.visibleClipWidth
    }

    ClipHeader {
        id: cardHeader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        title: clipData?.name ?? (root.isTextClip ? "Title" : "Clip")
        isAudioClip: root.isAudioClip
        isTextClip: root.isTextClip
        isLocked: root.isLocked
        isLinked: timelineModel ? (timelineModel.getLinkedClipIds(root.clipId).length > 1) : false
    }

    Loader {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: cardHeader.bottom
        anchors.bottom: parent.bottom
        active: root.isAudioClip && root.isInView && (timelineRoot?.showAudioWaveforms ?? true)
        sourceComponent: Component {
            ClipWaveform {
                modelSource: timelineModel
                assetId: root.clipData?.assetId ?? ""
                sourceInFrame: root.localSourceInFrame
                durationFrames: root.localDurationFrames
                zoomFactor: root.zoomFactor
                isSelected: root.isSelected
                isLocked: root.isLocked
                visibleLeft: root.visibleClipLeft
                visibleWidth: root.visibleClipWidth
            }
        }
    }

    Loader {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: cardHeader.bottom
        anchors.bottom: parent.bottom
        active: !root.isAudioClip && !root.isTextClip && root.isInView && root.height >= 32
        sourceComponent: Component {
            ClipThumbnails {
                assetId: root.clipData?.assetId ?? ""
                sourceInFrame: root.localSourceInFrame
                durationFrames: root.localDurationFrames
                thumbnailMode: timelineRoot?.thumbnailMode ?? 1
                isLocked: root.isLocked
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: root.isSlipping && root.assetDuration > 0
        sourceComponent: Component {
            ClipSlipOverlay {
                sourceInFrame: root.localSourceInFrame
                durationFrames: root.localDurationFrames
                totalSourceDuration: root.assetDuration
                slipDeltaFrames: root.slipDeltaFrames
                zoomFactor: root.zoomFactor
                isAudioClip: root.isAudioClip
            }
        }
    }

    ClipTrimHandle {
        edge: "left"
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        activeTool: root.activeTool
        isLocked: root.isLocked
        isAudioClip: root.isAudioClip
        isTextClip: root.isTextClip

        onTrimPressed: function (mouseX) {
            root.dragStartCanvasX = mouseX;
            root.isTrimmingLeft = true;
            root.dragOriginFrame = root.modelStartFrame;
            root.localDurationFrames = root.modelDurationFrames;
            root.localSourceInFrame = root.modelSourceInFrame;
            if (timelineModel) {
                timelineModel.beginInteraction(root.clipId, root.activeTool === "roll" ? 3 : 1);
            }
        }
        onTrimMoved: function (mouseX) {
            var deltaFrames = Math.round((mouseX - root.dragStartCanvasX) / root.zoomFactor);
            if (root.activeTool === "roll") {
                var adjId = timelineModel.getAdjacentClipId(root.clipId, true);
                if (adjId.length > 0) {
                    timelineModel.rollEdit(adjId, root.clipId, root.dragOriginFrame + deltaFrames);
                }
            } else {
                var maxDelta = root.modelDurationFrames - 1;
                var boundedDelta = Math.min(deltaFrames, maxDelta);
                root.localStartFrame = Math.max(0, root.dragOriginFrame + boundedDelta);
                root.localDurationFrames = Math.max(1, root.modelDurationFrames - boundedDelta);
                root.localSourceInFrame = Math.max(0, root.modelSourceInFrame + boundedDelta);
                if (timelineModel)
                    timelineModel.updateInteraction(boundedDelta, 0);
            }
        }
        onTrimReleased: {
            root.isTrimmingLeft = false;
            if (timelineModel) {
                timelineModel.endInteraction(false);
                if (root.activeTool !== "roll") {
                    timelineModel.trimClip(root.clipId, root.trackIndex, Math.round(root.localStartFrame), Math.round(root.localDurationFrames), Math.round(root.localSourceInFrame), false);
                }
            }
        }
    }

    ClipTrimHandle {
        edge: "right"
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        activeTool: root.activeTool
        isLocked: root.isLocked
        isAudioClip: root.isAudioClip
        isTextClip: root.isTextClip

        onTrimPressed: function (mouseX) {
            root.dragStartCanvasX = mouseX;
            root.isTrimmingRight = true;
            root.localDurationFrames = root.modelDurationFrames;
            if (timelineModel) {
                timelineModel.beginInteraction(root.clipId, root.activeTool === "roll" ? 3 : 2);
            }
        }
        onTrimMoved: function (mouseX) {
            var deltaFrames = Math.round((mouseX - root.dragStartCanvasX) / root.zoomFactor);
            if (root.activeTool === "roll") {
                var adjId = timelineModel.getAdjacentClipId(root.clipId, false);
                if (adjId.length > 0) {
                    timelineModel.rollEdit(root.clipId, adjId, root.modelStartFrame + root.modelDurationFrames + deltaFrames);
                }
            } else {
                root.localDurationFrames = Math.max(1, root.modelDurationFrames + deltaFrames);
                if (timelineModel)
                    timelineModel.updateInteraction(deltaFrames, 0);
            }
        }
        onTrimReleased: {
            root.isTrimmingRight = false;
            if (timelineModel) {
                timelineModel.endInteraction(false);
                if (root.activeTool !== "roll") {
                    timelineModel.trimClip(root.clipId, root.trackIndex, Math.round(root.modelStartFrame), Math.round(root.localDurationFrames), Math.round(root.modelSourceInFrame), false);
                }
            }
        }
    }

    MouseArea {
        id: clipMouse
        anchors.fill: parent
        hoverEnabled: !root.isLocked
        cursorShape: root.isLocked ? Qt.ArrowCursor : (root.isSlipTool ? Qt.SizeHorCursor : (pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor))
        preventStealing: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onPressed: function (mouse) {
            if (root.isLocked)
                return;

            if (mouse.button === Qt.RightButton) {
                var overlayPt = mapToItem(Overlay.overlay, mouse.x, mouse.y);
                if (root.timelineRoot && root.timelineRoot.openContextMenu) {
                    root.timelineRoot.openContextMenu(overlayPt.x, overlayPt.y, root.localStartFrame, root.trackIndex, root.clipData);
                }
                return;
            }

            var toggle = (mouse.modifiers & Qt.ControlModifier) !== 0 || (mouse.modifiers & Qt.MetaModifier) !== 0;
            var range = (mouse.modifiers & Qt.ShiftModifier) !== 0;

            if (timelineModel && (!root.isSelected || toggle || range)) {
                timelineModel.selectClip(root.clipId, toggle, range);
                // select linked partners so interaction session contains all moving items
                if (!toggle && !range) {
                    var linked = timelineModel.getLinkedClipIds(root.clipId);
                    for (var i = 0; i < linked.length; ++i) {
                        if (linked[i] !== root.clipId) {
                            timelineModel.selectClip(linked[i], true, false);
                        }
                    }
                }
            }

            var pt = mapToItem(root.parent, mouse.x, mouse.y);
            root.dragStartCanvasX = pt.x;
            root.dragOriginFrame = root.modelStartFrame;
            root.dragOriginTrack = root.trackIndex;
            root.lastValidFrame = root.modelStartFrame;
            root.lastValidTrack = root.trackIndex;
            root.localStartFrame = root.modelStartFrame;
            root.localTrackIndex = root.trackIndex;

            if (root.isSlipTool) {
                root.isSlipping = true;
                root.slipDeltaFrames = 0;
                return;
            }

            root.isLocalDragging = true;
            if (timelineModel) {
                timelineModel.beginInteraction(root.clipId, 0);
            }
        }

        onPositionChanged: function (mouse) {
            if (!pressed || root.isLocked)
                return;
            var pt = mapToItem(root.parent, mouse.x, mouse.y);
            var deltaFrames = Math.round((pt.x - root.dragStartCanvasX) / root.zoomFactor);

            if (root.isSlipping) {
                root.slipDeltaFrames = deltaFrames;
                if (timelineModel) {
                    timelineModel.slipClip(root.clipId, root.modelSourceInFrame - deltaFrames);
                }
                return;
            }

            if (!root.isLocalDragging)
                return;

            var targetTrack = timelineModel ? timelineModel.getTrackAtY(pt.y) : root.trackIndex;
            var movingIds = root.getMovingClipIds();

            var placement = timelineModel.resolvePlacement(movingIds, root.dragOriginFrame + deltaFrames, targetTrack, root.dragOriginFrame, root.dragOriginTrack, root.lastValidFrame, root.lastValidTrack);

            if (placement.valid) {
                root.lastValidFrame = Math.round(placement.frame);
                root.lastValidTrack = placement.track;
                root.localStartFrame = root.lastValidFrame;
                root.localTrackIndex = root.lastValidTrack;
                timelineModel.updateInteraction(root.lastValidFrame - root.dragOriginFrame, root.lastValidTrack - root.dragOriginTrack);
            }
        }

        onReleased: function (mouse) {
            if (mouse.button !== Qt.LeftButton)
                return;

            if (root.isSlipping) {
                root.isSlipping = false;
                root.slipDeltaFrames = 0;
                return;
            }

            if (!root.isLocalDragging)
                return;
            root.isLocalDragging = false;

            if (timelineModel) {
                timelineModel.endInteraction(false);
                var deltaF = root.lastValidFrame - root.dragOriginFrame;
                var deltaT = root.lastValidTrack - root.dragOriginTrack;

                if (deltaF !== 0 || deltaT !== 0) {
                    var movingIds = root.getMovingClipIds();
                    timelineModel.moveClips(movingIds, deltaF, deltaT);
                } else {
                    // restore coordinates if no displacement occurred
                    root.localStartFrame = root.modelStartFrame;
                    root.localTrackIndex = root.trackIndex;
                }
            }
        }
    }
}
