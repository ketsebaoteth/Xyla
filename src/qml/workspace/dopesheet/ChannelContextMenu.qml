import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Popup {
    id: channelMenu
    parent: Overlay.overlay
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 6

    property var timelineModel: null
    property var controller: null
    property string clipId: ""
    property string propId: ""
    property bool isMuted: false
    property bool isLocked: false

    signal expandAllRequested
    signal collapseAllRequested

    background: Rectangle {
        color: "#181818"
        border.color: "#2a2a2a"
        border.width: 1
        radius: 8
    }

    contentItem: ColumnLayout {
        spacing: 2
        width: 190

        RowItem {
            text: channelMenu.isMuted ? "Unmute Channel(s)" : "Mute Channel(s)"
            onClicked: {
                channelMenu.close();
                if (channelMenu.controller)
                    channelMenu.controller.muteChannel(channelMenu.timelineModel, channelMenu.clipId, channelMenu.propId, !channelMenu.isMuted);
            }
        }

        RowItem {
            text: channelMenu.isLocked ? "Unlock Channel(s)" : "Lock Channel(s)"
            onClicked: {
                channelMenu.close();
                if (channelMenu.controller)
                    channelMenu.controller.lockChannel(channelMenu.timelineModel, channelMenu.clipId, channelMenu.propId, !channelMenu.isLocked);
            }
        }

        Separator {}

        SubmenuItem {
            text: "Extrapolation Mode"
            items: [
                {
                    text: "Constant",
                    action: () => channelMenu.controller.setExtrapolation(channelMenu.timelineModel, channelMenu.clipId, channelMenu.propId, 0)
                },
                {
                    text: "Linear",
                    action: () => channelMenu.controller.setExtrapolation(channelMenu.timelineModel, channelMenu.clipId, channelMenu.propId, 1)
                },
                {
                    text: "Cycle",
                    action: () => channelMenu.controller.setExtrapolation(channelMenu.timelineModel, channelMenu.clipId, channelMenu.propId, 2)
                },
                {
                    text: "Cycle with Offset",
                    action: () => channelMenu.controller.setExtrapolation(channelMenu.timelineModel, channelMenu.clipId, channelMenu.propId, 3)
                }
            ]
        }

        Separator {}

        RowItem {
            text: "Expand All"
            onClicked: {
                channelMenu.close();
                channelMenu.expandAllRequested();
            }
        }

        RowItem {
            text: "Collapse All"
            onClicked: {
                channelMenu.close();
                channelMenu.collapseAllRequested();
            }
        }
    }

    function openAt(screenX, screenY, cId, pId) {
        clipId = cId;
        propId = pId;
        x = Math.max(8, Math.min(screenX, Overlay.overlay.width - width - 8));
        y = Math.max(8, Math.min(screenY, Overlay.overlay.height - height - 8));
        open();
    }

    component RowItem: Rectangle {
        property string text: ""
        signal clicked

        Layout.fillWidth: true
        height: 24
        radius: 4
        color: m.containsMouse ? "#252525" : "transparent"

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: parent.text
            color: "#e0e0e0"
            font.pixelSize: 11
        }

        MouseArea {
            id: m
            anchors.fill: parent
            hoverEnabled: true
            onClicked: parent.clicked()
        }
    }

    component SubmenuItem: Rectangle {
        id: subR
        property string text: ""
        property var items: []

        Layout.fillWidth: true
        height: 24
        radius: 4
        color: (subM.containsMouse || fPop.visible) ? "#252525" : "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 6

            Text {
                Layout.fillWidth: true
                text: subR.text
                color: "#e0e0e0"
                font.pixelSize: 11
            }

            Text {
                text: "▸"
                color: "#777777"
                font.pixelSize: 10
            }
        }

        MouseArea {
            id: subM
            anchors.fill: parent
            hoverEnabled: true
            onEntered: fPop.open()
        }

        Popup {
            id: fPop
            x: subR.width + 4
            y: -4
            padding: 6
            background: Rectangle {
                color: "#181818"
                border.color: "#2a2a2a"
                border.width: 1
                radius: 8
            }
            contentItem: ColumnLayout {
                spacing: 2
                width: 140
                Repeater {
                    model: subR.items
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        height: 24
                        radius: 4
                        color: fM.containsMouse ? "#252525" : "transparent"

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.text
                            color: "#e0e0e0"
                            font.pixelSize: 11
                        }

                        MouseArea {
                            id: fM
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                fPop.close();
                                channelMenu.close();
                                modelData.action();
                            }
                        }
                    }
                }
            }
        }
    }

    component Separator: Rectangle {
        Layout.fillWidth: true
        height: 1
        color: "#242424"
    }
}
