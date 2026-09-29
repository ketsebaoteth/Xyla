import QtQuick
import QtQuick.Effects
import "../"

Item {
    id: root

    property var timelineModel: null
    property real verticalScrollOffset: 0.0
    property int headerWidth: 220
    property int minHeaderWidth: 200
    property int maxHeaderWidth: 500
    property int rulerHeight: 32

    signal scrollVerticalRequested(real delta)
    signal headerWidthAdjusted(int newWidth)

    width: headerWidth
    z: 20

    Rectangle {
        anchors.fill: parent
        color: "#121212"

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#99000000"
            shadowBlur: 16
            shadowHorizontalOffset: 8
            shadowVerticalOffset: 0
        }
    }

    Rectangle {
        id: rulerSpacer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.rulerHeight
        color: "#141414"
        z: 10

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: "#1E1E1E"
        }
    }

    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: rulerSpacer.bottom
        anchors.bottom: parent.bottom
        clip: true

        WheelHandler {
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: function (event) {
                var delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y;
                root.scrollVerticalRequested(-delta);
            }
        }

        Item {
            id: trackHeaderContainer
            width: parent.width
            y: -root.verticalScrollOffset
            height: root.timelineModel ? root.timelineModel.totalTracksHeight : 0

            Column {
                id: trackHeaderColumn
                width: parent.width
                spacing: 0

                Repeater {
                    model: root.timelineModel

                    TimelineTrackHeader {
                        width: root.headerWidth
                        trackIndex: index
                        trackId: model.trackId || ""
                        trackName: model.trackName || ""
                        trackKind: model.trackKind !== undefined ? model.trackKind : 0
                        isSelected: model.isTrackSelected !== undefined ? model.isTrackSelected : false
                        expandedHeight: (model.trackHeight !== undefined && model.trackHeight > 0) ? model.trackHeight : 68

                        onLockToggled: {
                            if (root.timelineModel) {
                                root.timelineModel.toggleTrackLock(trackIndex);
                            }
                        }

                        // update C++ model track metrics when header is dragged or toggled
                        onTrackHeightChanged: function (newH) {
                            if (root.timelineModel) {
                                root.timelineModel.setTrackHeight(trackIndex, newH);
                            }
                        }
                    }
                }
            }
        }
    }

    Item {
        id: splitter
        width: 8
        anchors.right: parent.right
        anchors.rightMargin: -4
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        z: 350

        Rectangle {
            anchors.centerIn: parent
            width: splitterMouse.containsMouse || splitterMouse.pressed ? 2 : 0
            height: parent.height
            color: "#2555D3"
        }

        MouseArea {
            id: splitterMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.SizeHorCursor
            preventStealing: true

            property int startX: 0
            property int startW: 0

            onPressed: function (mouse) {
                var pt = mapToItem(root.parent, mouse.x, mouse.y);
                startX = pt.x;
                startW = root.headerWidth;
            }

            onPositionChanged: function (mouse) {
                if (pressed) {
                    var pt = mapToItem(root.parent, mouse.x, mouse.y);
                    var newW = Math.max(root.minHeaderWidth, Math.min(root.maxHeaderWidth, startW + (pt.x - startX)));
                    root.headerWidthAdjusted(newW);
                }
            }
        }
    }
}
