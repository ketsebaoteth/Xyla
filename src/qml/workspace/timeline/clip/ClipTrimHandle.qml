import QtQuick

Item {
    id: root

    property string edge: "left"
    property string activeTool: "pointer"
    property bool isLocked: false
    property bool isAudioClip: false
    property bool isTextClip: false

    signal trimPressed(real mouseX)
    signal trimMoved(real mouseX)
    signal trimReleased

    readonly property bool isLeft: edge === "left"
    readonly property bool isRoll: activeTool === "roll"
    readonly property bool isRipple: activeTool === "ripple"

    width: (isRoll || isRipple) ? 16 : 6
    z: 50

    // badge handle for roll tool
    Rectangle {
        id: rollBadge
        visible: root.isRoll && !root.isLocked
        anchors.centerIn: parent
        width: 16
        height: Math.min(22, Math.max(14, parent.height - 4))
        radius: 4
        color: (handleMouse.containsMouse || handleMouse.pressed) ? "#06B6D4" : "#0891B2"
        border.color: "#67E8F9"
        border.width: 1

        Image {
            anchors.centerIn: parent
            source: "qrc:/assets/icons/grip-vertical.svg"
            sourceSize: Qt.size(10, 14)
            width: 10
            height: 14
            fillMode: Image.PreserveAspectFit
            opacity: 0.95
        }
    }

    // badge handle for ripple tool
    Rectangle {
        id: rippleBadge
        visible: root.isRipple && !root.isRoll && !root.isLocked
        anchors.centerIn: parent
        width: 16
        height: Math.min(22, Math.max(14, parent.height - 4))
        radius: 4
        color: (handleMouse.containsMouse || handleMouse.pressed) ? "#3B82F6" : "#1D3DFF"
        border.color: "#60A5FA"
        border.width: 1

        Image {
            anchors.centerIn: parent
            source: "qrc:/assets/icons/grip-vertical.svg"
            sourceSize: Qt.size(10, 14)
            width: 10
            height: 14
            fillMode: Image.PreserveAspectFit
            opacity: 0.95
        }
    }

    // standard trim border line for pointer tool
    Rectangle {
        id: standardTrimLine
        visible: !root.isRoll && !root.isRipple && !root.isLocked
        anchors.centerIn: parent
        width: 1.5
        height: parent.height - 6
        color: {
            if (handleMouse.containsMouse || handleMouse.pressed) {
                if (root.isAudioClip)
                    return "#C4B5FD";
                if (root.isTextClip)
                    return "#FCD34D";
                return "#60A5FA";
            }
            if (root.isAudioClip)
                return "#7C3AED";
            if (root.isTextClip)
                return "#D97706";
            return "#1D5DDB";
        }
    }

    MouseArea {
        id: handleMouse
        anchors.fill: parent
        anchors.margins: -4
        hoverEnabled: !root.isLocked
        cursorShape: root.isLocked ? Qt.ArrowCursor : Qt.SizeHorCursor
        preventStealing: true

        onPressed: function (mouse) {
            if (mouse.button === Qt.LeftButton && !root.isLocked) {
                var pt = mapToItem(root.parent, mouse.x, mouse.y);
                root.trimPressed(pt.x);
            }
        }

        onPositionChanged: function (mouse) {
            if (pressed && !root.isLocked) {
                var pt = mapToItem(root.parent, mouse.x, mouse.y);
                root.trimMoved(pt.x);
            }
        }

        onReleased: function (mouse) {
            if (mouse.button === Qt.LeftButton && !root.isLocked) {
                root.trimReleased();
            }
        }
    }
}
