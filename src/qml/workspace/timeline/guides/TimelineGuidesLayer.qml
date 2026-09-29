import QtQuick

Item {
    id: root

    property double zoomFactor: 1.0
    property real snapGuideFrame: -1
    property bool isSnapLineVisible: false
    property var activeSpacingGaps: []

    anchors.fill: parent
    z: 500

    // magnetic snap vertical line
    Rectangle {
        id: snapLine
        visible: root.isSnapLineVisible && root.snapGuideFrame >= 0
        x: Math.round(root.snapGuideFrame * root.zoomFactor)
        width: 1
        height: parent.height
        color: "#2563eb"
        opacity: 0.85
        z: 150

        Rectangle {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: 5
            height: 5
            radius: 2.5
            color: "#3b82f6"
        }
    }

    // gap frame duration badges
    Repeater {
        model: root.activeSpacingGaps

        Rectangle {
            readonly property bool isActive: modelData.isActive === true

            x: Math.round(Number(modelData.start) * root.zoomFactor)
            width: Math.max(1, Math.round((Number(modelData.end) - Number(modelData.start)) * root.zoomFactor))
            height: parent.height
            color: isActive ? Qt.rgba(0.145, 0.388, 0.922, 0.18) : Qt.rgba(0.145, 0.388, 0.922, 0.10)
            border.color: isActive ? "#3b82f6" : "#2563eb"
            border.width: 1

            Rectangle {
                anchors.centerIn: parent
                width: gapBadgeText.implicitWidth + 10
                height: 18
                color: parent.isActive ? "#2563eb" : "#1d4ed8"
                radius: 4
                border.color: parent.isActive ? "#60a5fa" : "#3b82f6"
                border.width: 1

                Text {
                    id: gapBadgeText
                    anchors.centerIn: parent
                    text: (modelData.gapFrames !== undefined ? modelData.gapFrames : "") + "f"
                    color: "#ffffff"
                    font.pixelSize: 10
                    font.bold: true
                }
            }
        }
    }
}
