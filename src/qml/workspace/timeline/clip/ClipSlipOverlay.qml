import QtQuick

Item {
    id: root

    property real sourceInFrame: 0
    property real durationFrames: 30
    property real totalSourceDuration: 0
    property real slipDeltaFrames: 0
    property double zoomFactor: 1.0
    property bool isAudioClip: false

    z: 200
    x: -Number(root.sourceInFrame) * root.zoomFactor
    y: 0
    width: Number(root.totalSourceDuration) * root.zoomFactor
    height: parent.height

    // master source boundary bounding rectangle
    Rectangle {
        anchors.fill: parent
        color: root.isAudioClip ? Qt.rgba(0.486, 0.227, 0.929, 0.1) : Qt.rgba(0.114, 0.365, 0.859, 0.1)
        border.color: "#38bdf8"
        border.width: 1
        opacity: 0.85
        radius: 4

        // header strip showing total asset length
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 14
            color: root.isAudioClip ? Qt.rgba(0.486, 0.227, 0.929, 0.3) : Qt.rgba(0.114, 0.365, 0.859, 0.3)

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: "Master Source: " + Math.round(root.totalSourceDuration) + "f"
                color: "#93c5fd"
                font.pixelSize: 9
            }
        }

        // head boundary collision marker
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: 4
            anchors.bottomMargin: 4
            width: 2
            color: root.sourceInFrame <= 0 ? "#ef4444" : "#38bdf8"
        }

        // tail boundary collision marker
        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: 4
            anchors.bottomMargin: 4
            width: 2
            color: (root.sourceInFrame + root.durationFrames >= root.totalSourceDuration) ? "#ef4444" : "#38bdf8"
        }
    }

    // active cut window frame with slip delta badge
    Rectangle {
        x: Number(root.sourceInFrame) * root.zoomFactor
        y: 0
        width: Number(root.durationFrames) * root.zoomFactor
        height: parent.height
        color: "transparent"
        border.color: "#38bdf8"
        border.width: 2

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4
            width: deltaText.implicitWidth + 12
            height: 16
            radius: 6
            color: "#121212"

            Text {
                id: deltaText
                anchors.centerIn: parent
                text: "Slip: " + (root.slipDeltaFrames >= 0 ? "+" : "") + Math.round(root.slipDeltaFrames) + "f"
                color: "#FFFFFF"
                font.pixelSize: 10
            }
        }
    }
}
