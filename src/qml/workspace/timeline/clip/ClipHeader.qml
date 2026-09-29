import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property string title: ""
    property bool isAudioClip: false
    property bool isTextClip: false
    property bool isLocked: false
    property bool isLinked: false

    height: 20

    // accent color matching clip category
    readonly property color accentColor: {
        if (root.isLocked)
            return "#262626";
        if (root.isAudioClip)
            return "#673AEE";
        if (root.isTextClip)
            return "#F59E0A";
        return "#1D3DFF";
    }

    // left badge tab holding clip title
    Rectangle {
        id: textBadge
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 1
        width: Math.min(parent.width - iconBadge.width - 8, titleText.implicitWidth + 16)
        color: root.accentColor
        topLeftRadius: 2
        bottomRightRadius: 8
        clip: true

        Text {
            id: titleText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            text: root.title
            color: root.isLocked ? "#a3a3a3" : "#ffffff"
            font.pixelSize: 10
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
    }

    // right badge tab displaying link and lock indicators
    Rectangle {
        id: iconBadge
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 1
        visible: root.isLinked || root.isLocked
        width: iconRow.implicitWidth + 12
        color: root.accentColor
        bottomLeftRadius: 8
        topRightRadius: 2

        RowLayout {
            id: iconRow
            anchors.centerIn: parent
            spacing: 4

            Image {
                visible: root.isLinked
                source: "qrc:/assets/icons/link.svg"
                sourceSize: Qt.size(10, 10)
                Layout.preferredWidth: 10
                Layout.preferredHeight: 10
                opacity: root.isLocked ? 0.45 : 0.85
                Layout.alignment: Qt.AlignVCenter
            }

            Image {
                visible: root.isLocked
                source: "qrc:/assets/icons/lock.svg"
                sourceSize: Qt.size(10, 10)
                Layout.preferredWidth: 10
                Layout.preferredHeight: 10
                opacity: 0.9
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }
}
