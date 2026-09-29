import QtQuick

Item {
    id: root

    property var timelineModel: null
    property real contentWidth: 3600

    readonly property color videoTrackBg: "#0E0E0E"
    readonly property color audioTrackBg: "#101010"
    readonly property color dividerColor: "#1E1E1E"

    // tie into totalTracksHeight property notifier so method lookups re-evaluate on any track height resize
    readonly property int metricsRevision: root.timelineModel ? root.timelineModel.totalTracksHeight : 0

    width: contentWidth
    height: root.metricsRevision

    Repeater {
        model: root.timelineModel ? root.timelineModel.trackCount : 0

        Rectangle {
            id: trackLane
            y: (root.metricsRevision >= 0 && root.timelineModel) ? root.timelineModel.getTrackY(index) : (index * 68)
            width: root.contentWidth
            height: (root.metricsRevision >= 0 && root.timelineModel) ? root.timelineModel.getTrackHeight(index) : 68
            color: (root.timelineModel && root.timelineModel.getTrackKind(index) === 1) ? root.audioTrackBg : root.videoTrackBg

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: root.dividerColor
            }
        }
    }
}
