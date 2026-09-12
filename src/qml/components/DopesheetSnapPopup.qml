import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Popup {
    id: control

    width: 290
    padding: 12
    clip: false
    margins: 8 // Instructs Qt's positioning engine to enforce window boundaries

    property bool snapToFrames: true
    property bool snapToOtherKeys: true
    property bool snapToPlayhead: true

    signal snapModesChanged(bool frames, bool otherKeys, bool playhead)

    background: Rectangle {
        anchors.fill: parent
        color: "#181818"
        border.color: "#282828"
        border.width: 1
        radius: 12

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#90000000"
            shadowBlur: 0.65
            shadowVerticalOffset: 6
            shadowHorizontalOffset: 0
        }
    }

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0.0
            to: 1.0
            duration: 150
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            property: "scale"
            from: 0.95
            to: 1.0
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    exit: Transition {
        NumberAnimation {
            property: "opacity"
            from: 1.0
            to: 0.0
            duration: 120
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            property: "scale"
            from: 1.0
            to: 0.95
            duration: 120
            easing.type: Easing.OutCubic
        }
    }

    contentItem: ColumnLayout {
        spacing: 10

        Text {
            text: "Active Snap Targets"
            color: "#888888"
            font.pixelSize: 11
            font.weight: Font.Medium
        }

        // Multi-Select Toggle Chips Row
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            // 1. Frame Chip
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: 6
                color: control.snapToFrames ? (frameMouse.containsMouse ? "#1645BF" : "#11389F") : (frameMouse.containsMouse ? "#1c1c1c" : "#141414")
                border.color: control.snapToFrames ? "#2555D3" : (frameMouse.containsMouse ? "#383838" : "#262626")
                border.width: 1

                Behavior on color {
                    ColorAnimation {
                        duration: 120
                    }
                }
                Behavior on border.color {
                    ColorAnimation {
                        duration: 120
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "Frame"
                    font.pixelSize: 11
                    font.weight: control.snapToFrames ? Font.Medium : Font.Normal
                    color: control.snapToFrames ? "#ffffff" : (frameMouse.containsMouse ? "#cccccc" : "#777777")
                }

                MouseArea {
                    id: frameMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        control.snapToFrames = !control.snapToFrames;
                        control.snapModesChanged(control.snapToFrames, control.snapToOtherKeys, control.snapToPlayhead);
                    }
                }
            }

            // 2. Other Keys Chip
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: 6
                color: control.snapToOtherKeys ? (keysMouse.containsMouse ? "#1645BF" : "#11389F") : (keysMouse.containsMouse ? "#1c1c1c" : "#141414")
                border.color: control.snapToOtherKeys ? "#2555D3" : (keysMouse.containsMouse ? "#383838" : "#262626")
                border.width: 1

                Behavior on color {
                    ColorAnimation {
                        duration: 120
                    }
                }
                Behavior on border.color {
                    ColorAnimation {
                        duration: 120
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "Other Keys"
                    font.pixelSize: 11
                    font.weight: control.snapToOtherKeys ? Font.Medium : Font.Normal
                    color: control.snapToOtherKeys ? "#ffffff" : (keysMouse.containsMouse ? "#cccccc" : "#777777")
                }

                MouseArea {
                    id: keysMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        control.snapToOtherKeys = !control.snapToOtherKeys;
                        control.snapModesChanged(control.snapToFrames, control.snapToOtherKeys, control.snapToPlayhead);
                    }
                }
            }

            // 3. Playhead Chip
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: 6
                color: control.snapToPlayhead ? (playheadMouse.containsMouse ? "#1645BF" : "#11389F") : (playheadMouse.containsMouse ? "#1c1c1c" : "#141414")
                border.color: control.snapToPlayhead ? "#2555D3" : (playheadMouse.containsMouse ? "#383838" : "#262626")
                border.width: 1

                Behavior on color {
                    ColorAnimation {
                        duration: 120
                    }
                }
                Behavior on border.color {
                    ColorAnimation {
                        duration: 120
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "Playhead"
                    font.pixelSize: 11
                    font.weight: control.snapToPlayhead ? Font.Medium : Font.Normal
                    color: control.snapToPlayhead ? "#ffffff" : (playheadMouse.containsMouse ? "#cccccc" : "#777777")
                }

                MouseArea {
                    id: playheadMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        control.snapToPlayhead = !control.snapToPlayhead;
                        control.snapModesChanged(control.snapToFrames, control.snapToOtherKeys, control.snapToPlayhead);
                    }
                }
            }
        }
    }
}
