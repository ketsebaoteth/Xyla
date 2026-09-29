import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import "./timeline"
import "./timeline/canvas"
import "./timeline/tracks"
import "./timeline/mixer"

Item {
    id: root

    Component.onCompleted: {
        if (!timelineModel) {
            console.error("Timeline: 'timelineModel' is not injected into root context.");
        }
        if (!playbackManager) {
            console.error("Timeline: 'playbackManager' is not injected into root context.");
        }
    }
    HoverHandler {
        onHoveredChanged: {
            if (hovered && typeof layoutController !== "undefined" && layoutController)
                layoutController.setActiveDockId("TimelinePanel");
        }
    }

    readonly property var activeTimelineModel: (typeof timelineModel !== "undefined") ? timelineModel : null
    readonly property var activePlaybackManager: (typeof playbackManager !== "undefined") ? playbackManager : null
    readonly property var activeMediaPool: (typeof mediaPool !== "undefined") ? mediaPool : null
    readonly property var activeMixerModel: (typeof mixerModel !== "undefined") ? mixerModel : null

    property string activeTool: "pointer"
    property int activeToolIndex: 0

    // Configurable zoom anchor: "cursor" (default), "center", or "playhead"
    property string zoomAnchor: "cursor"

    property double zoomFactor: activeTimelineModel ? activeTimelineModel.zoomFactor : 1.0
    property real horizontalOffset: activeTimelineModel ? activeTimelineModel.horizontalOffset : 0.0
    property real verticalScrollOffset: 0.0
    property int headerWidth: 220
    property int rulerHeight: 32
    property real contentWidth: Math.max(3600, ((activeTimelineModel ? activeTimelineModel.getDurationFrames() : 0) * zoomFactor) + 1500)

    property bool showAudioWaveforms: true
    property int thumbnailMode: 1

    function scrollVertical(delta) {
        if (!activeTimelineModel)
            return;
        var maxOffset = Math.max(0, activeTimelineModel.totalTracksHeight - canvasView.height);
        root.verticalScrollOffset = Math.max(0, Math.min(maxOffset, root.verticalScrollOffset + delta));
    }

    function applyZoom(factor, cursorCanvasX) {
        if (!activeTimelineModel)
            return;

        var anchorViewportX = (cursorCanvasX !== undefined && cursorCanvasX >= 0) ? cursorCanvasX : (canvasView.width / 2);

        if (root.zoomAnchor === "center") {
            anchorViewportX = canvasView.width / 2;
        } else if (root.zoomAnchor === "playhead" && activePlaybackManager) {
            var playheadCanvasX = (activePlaybackManager.currentFrame * root.zoomFactor) - root.horizontalOffset;
            anchorViewportX = Math.max(0, Math.min(canvasView.width, playheadCanvasX));
        } else {
            // Default: "cursor"
            anchorViewportX = Math.max(0, Math.min(canvasView.width, anchorViewportX));
        }

        var frameAtAnchor = (anchorViewportX + root.horizontalOffset) / root.zoomFactor;
        var newZoom = Math.max(0.1, Math.min(10.0, root.zoomFactor * factor));
        var newOffset = Math.max(0, (frameAtAnchor * newZoom) - anchorViewportX);

        activeTimelineModel.zoomFactor = newZoom;
        activeTimelineModel.horizontalOffset = newOffset;
    }

    function openContextMenu(screenX, screenY, frame, track, clipData) {
        timelineMenu.openAt(screenX, screenY, frame, track, clipData);
    }

    Rectangle {
        anchors.fill: parent
        color: "#121212"
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        TimelineToolBar {
            id: toolBar
            Layout.fillWidth: true
            playbackManager: root.activePlaybackManager
            timelineModel: root.activeTimelineModel
            showAudioWaveforms: root.showAudioWaveforms
            thumbnailMode: root.thumbnailMode
            activeToolIndex: root.activeToolIndex

            onToolChanged: function (toolId, toolIndex) {
                root.activeTool = toolId;
                root.activeToolIndex = toolIndex;
            }
            onShowAudioWaveformsChanged: root.showAudioWaveforms = showAudioWaveforms
            onThumbnailModeChanged: root.thumbnailMode = thumbnailMode
            onAddVideoTrackRequested: addTrackModal.openWithKind(0)
            onAddAudioTrackRequested: addTrackModal.openWithKind(1)
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Item {
                id: emptyView
                anchors.fill: parent
                visible: !root.activeTimelineModel || root.activeTimelineModel.trackCount === 0

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 12

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "No Tracks in Timeline"
                        color: "#ffffff"
                        font.pixelSize: 15
                        font.bold: true
                    }

                    Button {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Create Default Tracks"
                        onClicked: {
                            if (root.activeTimelineModel) {
                                root.activeTimelineModel.createDefaultTracks(2, 2);
                            }
                        }
                    }
                }
            }

            RowLayout {
                anchors.fill: parent
                spacing: 0
                visible: root.activeTimelineModel && root.activeTimelineModel.trackCount > 0

                TimelineTrackList {
                    id: trackSidebar
                    Layout.fillHeight: true
                    timelineModel: root.activeTimelineModel
                    verticalScrollOffset: root.verticalScrollOffset
                    headerWidth: root.headerWidth
                    rulerHeight: root.rulerHeight

                    onScrollVerticalRequested: function (delta) {
                        root.scrollVertical(delta);
                    }
                    onHeaderWidthAdjusted: function (newW) {
                        root.headerWidth = newW;
                    }
                }

                TimelineCanvas {
                    id: canvasView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    timelineRoot: root
                    timelineModel: root.activeTimelineModel
                    playbackManager: root.activePlaybackManager
                    mediaPool: root.activeMediaPool
                    zoomFactor: root.zoomFactor
                    horizontalOffset: root.horizontalOffset
                    verticalScrollOffset: root.verticalScrollOffset
                    contentWidth: root.contentWidth
                    activeTool: root.activeTool

                    onScrollVerticalRequested: function (delta) {
                        root.scrollVertical(delta);
                    }
                    onZoomRequested: function (factor, cursorX) {
                        root.applyZoom(factor, cursorX);
                    }
                    onHorizontalOffsetAdjusted: function (offset) {
                        if (root.activeTimelineModel) {
                            root.activeTimelineModel.horizontalOffset = offset;
                        }
                    }
                }

                TimelineMixerStrip {
                    id: mixerStrip
                    Layout.fillHeight: true
                    mixerModel: root.activeMixerModel
                }
            }
        }
    }

    TimelineContextMenu {
        id: timelineMenu
        timelineRoot: root
        timelineModel: root.activeTimelineModel
        playbackManager: root.activePlaybackManager

        onDeleteRequested: if (root.activeTimelineModel)
            root.activeTimelineModel.deleteSelectedClips(false)
        onRippleDeleteRequested: if (root.activeTimelineModel)
            root.activeTimelineModel.deleteSelectedClips(true)
        onSplitRequested: function (frame, track) {
            if (root.activeTimelineModel)
                root.activeTimelineModel.cutAtPlayhead(frame);
        }
        onSelectAllRequested: if (root.activeTimelineModel)
            root.activeTimelineModel.selectAll()
    }

    TimelineAddTrackModal {
        id: addTrackModal
        function openWithKind(kind) {
            pendingKind = kind;
            open();
        }
        onConfirmed: function (kind) {
            if (!root.activeTimelineModel)
                return;
            if (kind === 0)
                root.activeTimelineModel.addVideoTrack();
            else
                root.activeTimelineModel.addAudioTrack();
        }
    }

    TimelineCreateTracksModal {
        id: createTracksModal
        onConfirmed: function (vCount, aCount) {
            if (root.activeTimelineModel) {
                root.activeTimelineModel.createDefaultTracks(vCount, aCount);
            }
        }
    }
}
