import QtQuick

Item {
    id: root

    property string assetId: ""
    property real sourceInFrame: 0
    property real durationFrames: 30
    property int thumbnailMode: 1
    property bool isLocked: false

    // mode 1: head and tail thumbnails
    Item {
        anchors.fill: parent
        visible: root.thumbnailMode === 1

        Image {
            id: headThumb
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 2
            width: Math.min(height * 1.77, (parent.width - 8) / 2)
            fillMode: Image.PreserveAspectCrop
            visible: width > 15
            opacity: root.isLocked ? 0.4 : 1.0
            source: (visible && root.assetId) ? ("image://thumbnails/" + root.assetId + "?time=" + (root.sourceInFrame / 30.0) + "&width=160") : ""
            asynchronous: true
            cache: true
            onStatusChanged: if (headThumb.status === Image.Error)
                source = ""
        }

        Image {
            id: tailThumb
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 2
            width: Math.min(height * 1.77, (parent.width - 8) / 2)
            fillMode: Image.PreserveAspectCrop
            visible: width > 15 && parent.width > (width * 2 + 10)
            opacity: root.isLocked ? 0.4 : 1.0
            source: (visible && root.assetId) ? ("image://thumbnails/" + root.assetId + "?time=" + ((root.sourceInFrame + root.durationFrames) / 30.0) + "&width=160") : ""
            asynchronous: true
            cache: true
            onStatusChanged: if (tailThumb.status === Image.Error)
                source = ""
        }
    }

    // mode 2: continuous filmstrip repeater
    Row {
        anchors.fill: parent
        anchors.margins: 2
        spacing: 1
        visible: root.thumbnailMode === 2
        clip: true

        readonly property real thumbW: Math.max(16, parent.height * 1.77)
        readonly property int count: Math.ceil(parent.width / (thumbW + spacing))

        Repeater {
            model: parent.visible ? parent.count : 0

            Image {
                width: parent.thumbW
                height: root.height - 4
                fillMode: Image.PreserveAspectCrop
                opacity: root.isLocked ? 0.4 : 1.0
                source: root.assetId ? ("image://thumbnails/" + root.assetId + "?time=" + ((root.sourceInFrame + (index * (root.durationFrames / Math.max(1, parent.count)))) / 30.0) + "&width=160") : ""
                asynchronous: true
                cache: true
            }
        }
    }
}
