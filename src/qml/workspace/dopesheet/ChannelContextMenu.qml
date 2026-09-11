import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: channelMenu
    parent: Overlay.overlay
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 5
    implicitWidth: 204

    property var timelineModel: null
    property var controller: null
    property var treeRows: []

    property string clipId: ""
    property string propId: ""
    property bool isMuted: false
    property bool isLocked: false

    // Tracks whichever submenu popup is currently open
    property var activeSubmenuPopup: null

    signal expandAllRequested
    signal collapseAllRequested
    signal selectAllInTrackRequested(string clipId, string propId)
    signal changeTrackColorRequested(string clipId, string propId, string colorHex)
    signal channelStateChanged

    // Closes any open child submenu
    function closeSubmenus() {
        if (activeSubmenuPopup && activeSubmenuPopup.visible) {
            activeSubmenuPopup.close();
        }
        activeSubmenuPopup = null;
    }

    onAboutToHide: closeSubmenus()
    onClosed: closeSubmenus()

    background: Rectangle {
        color: "#181818"
        border.color: "#2C2C2C"
        border.width: 1
        radius: 6

        Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            z: -1
            radius: 7
            color: "transparent"
            border.color: "#0B0B0B"
            border.width: 1
            opacity: 0.8
        }
    }

    contentItem: ColumnLayout {
        spacing: 1
        implicitWidth: 194

        // 1. Toggle Mute / Unmute
        RowItem {
            text: channelMenu.isMuted ? "Unmute Channel" : "Mute Channel"
            iconSource: channelMenu.isMuted ? "qrc:/assets/icons/volume.svg" : "qrc:/assets/icons/volume-off.svg"
            onClicked: {
                var newState = !channelMenu.isMuted;
                channelMenu.close();
                if (channelMenu.controller) {
                    channelMenu.controller.muteChannel(channelMenu.timelineModel, channelMenu.clipId, channelMenu.propId, newState);
                    channelMenu.channelStateChanged();
                }
            }
        }

        // 2. Toggle Lock / Unlock
        RowItem {
            text: channelMenu.isLocked ? "Unlock Channel" : "Lock Channel"
            iconSource: channelMenu.isLocked ? "qrc:/assets/icons/lock-open.svg" : "qrc:/assets/icons/lock.svg"
            onClicked: {
                var newState = !channelMenu.isLocked;
                channelMenu.close();
                if (channelMenu.controller) {
                    channelMenu.controller.lockChannel(channelMenu.timelineModel, channelMenu.clipId, channelMenu.propId, newState);
                    channelMenu.channelStateChanged();
                }
            }
        }

        Separator {}

        // 3. Select All In Track
        RowItem {
            text: "Select All Keys in Track"
            iconSource: "qrc:/assets/icons/copy.svg"
            onClicked: {
                channelMenu.close();
                channelMenu.selectAllInTrackRequested(channelMenu.clipId, channelMenu.propId);
            }
        }

        // 4. Track Color Submenu
        SubmenuItem {
            text: "Track Color"
            iconSource: "qrc:/assets/icons/palette.svg"
            isColorMenu: true
            items: [
                {
                    text: "Ocean Blue",
                    colorHex: "#3B82F6"
                },
                {
                    text: "Electric Violet",
                    colorHex: "#8B5CF6"
                },
                {
                    text: "Fuchsia Pink",
                    colorHex: "#EC4899"
                },
                {
                    text: "Emerald Green",
                    colorHex: "#10B981"
                },
                {
                    text: "Amber Orange",
                    colorHex: "#F59E0B"
                },
                {
                    text: "Crimson Red",
                    colorHex: "#EF4444"
                },
                {
                    text: "Cyan Wave",
                    colorHex: "#06B6D4"
                },
                {
                    text: "Slate Gray",
                    colorHex: "#64748B"
                }
            ]
        }

        Separator {}

        // 5. Extrapolation Submenu
        SubmenuItem {
            text: "Extrapolation"
            iconSource: "qrc:/assets/icons/arrow-right.svg"
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

        // 6. Expand All
        RowItem {
            text: "Expand All"
            iconSource: "qrc:/assets/icons/chevron-down.svg"
            onClicked: {
                channelMenu.close();
                channelMenu.expandAllRequested();
            }
        }

        // 7. Collapse All
        RowItem {
            text: "Collapse All"
            iconSource: "qrc:/assets/icons/chevron-up.svg"
            onClicked: {
                channelMenu.close();
                channelMenu.collapseAllRequested();
            }
        }
    }

    function openAt(screenX, screenY, cId, pId, muted, locked) {
        closeSubmenus();

        clipId = cId;
        propId = pId;

        // Dynamic State Lookup from treeRows
        var resolvedMuted = !!muted;
        var resolvedLocked = !!locked;

        if (treeRows && treeRows.length > 0) {
            for (var i = 0; i < treeRows.length; ++i) {
                if (treeRows[i].propId === pId && (cId === "" || treeRows[i].clipId === cId)) {
                    resolvedMuted = !!treeRows[i].isMuted;
                    resolvedLocked = !!treeRows[i].isLocked;
                    break;
                }
            }
        }

        isMuted = resolvedMuted;
        isLocked = resolvedLocked;

        x = Math.max(8, Math.min(screenX, Overlay.overlay.width - width - 8));
        y = Math.max(8, Math.min(screenY, Overlay.overlay.height - height - 8));
        open();
    }

    component RowItem: Rectangle {
        id: itemRoot
        property string text: ""
        property string iconSource: ""
        signal clicked

        Layout.fillWidth: true
        implicitHeight: 24
        height: 24
        radius: 4
        color: m.containsMouse ? "#262626" : "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            Image {
                visible: itemRoot.iconSource !== ""
                source: itemRoot.iconSource
                sourceSize: Qt.size(13, 13)
                Layout.preferredWidth: 13
                Layout.preferredHeight: 13
                Layout.alignment: Qt.AlignVCenter
                opacity: m.containsMouse ? 0.95 : 0.65
            }

            Text {
                Layout.fillWidth: true
                text: itemRoot.text
                color: m.containsMouse ? "#FFFFFF" : "#CCCCCC"
                font.pixelSize: 11
                verticalAlignment: Text.AlignVCenter
            }
        }

        MouseArea {
            id: m
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            // Hovering any standard item closes any open submenu
            onEntered: function () {
                channelMenu.closeSubmenus();
            }

            onClicked: function () {
                channelMenu.closeSubmenus();
                itemRoot.clicked();
            }
        }
    }

    component SubmenuItem: Rectangle {
        id: subR
        property string text: ""
        property string iconSource: ""
        property var items: []
        property bool isColorMenu: false

        Layout.fillWidth: true
        implicitHeight: 24
        height: 24
        radius: 4
        color: (subM.containsMouse || fPop.visible) ? "#262626" : "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            Image {
                visible: subR.iconSource !== ""
                source: subR.iconSource
                sourceSize: Qt.size(13, 13)
                Layout.preferredWidth: 13
                Layout.preferredHeight: 13
                Layout.alignment: Qt.AlignVCenter
                opacity: (subM.containsMouse || fPop.visible) ? 0.95 : 0.65
            }

            Text {
                Layout.fillWidth: true
                text: subR.text
                color: (subM.containsMouse || fPop.visible) ? "#FFFFFF" : "#CCCCCC"
                font.pixelSize: 11
                verticalAlignment: Text.AlignVCenter
            }

            Image {
                source: "qrc:/assets/icons/chevron-right.svg"
                sourceSize: Qt.size(10, 10)
                Layout.preferredWidth: 10
                Layout.preferredHeight: 10
                Layout.alignment: Qt.AlignVCenter
                opacity: 0.45
            }
        }

        MouseArea {
            id: subM
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            // Entering this item closes sibling submenus and opens this one
            onEntered: function () {
                if (channelMenu.activeSubmenuPopup !== fPop) {
                    channelMenu.closeSubmenus();
                    fPop.open();
                    channelMenu.activeSubmenuPopup = fPop;
                }
            }
        }

        Popup {
            id: fPop
            // Overlap by 2px to prevent pointer fall-through
            x: subR.width - 2
            y: -4
            padding: 5
            implicitWidth: subR.isColorMenu ? 150 : 160
            closePolicy: Popup.CloseOnEscape

            background: Rectangle {
                color: "#181818"
                border.color: "#2C2C2C"
                border.width: 1
                radius: 6

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -1
                    z: -1
                    radius: 7
                    color: "transparent"
                    border.color: "#0B0B0B"
                    border.width: 1
                    opacity: 0.8
                }
            }

            contentItem: ColumnLayout {
                spacing: 1
                implicitWidth: parent.implicitWidth - 10

                Repeater {
                    model: subR.items
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 24
                        height: 24
                        radius: 4
                        color: fM.containsMouse ? "#262626" : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Rectangle {
                                visible: subR.isColorMenu && modelData.colorHex !== undefined
                                width: 8
                                height: 8
                                radius: 4
                                color: modelData.colorHex || "transparent"
                                Layout.alignment: Qt.AlignVCenter
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modelData.text
                                color: fM.containsMouse ? "#FFFFFF" : "#CCCCCC"
                                font.pixelSize: 11
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        MouseArea {
                            id: fM
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: function () {
                                fPop.close();
                                channelMenu.close();
                                if (subR.isColorMenu && modelData.colorHex) {
                                    channelMenu.changeTrackColorRequested(channelMenu.clipId, channelMenu.propId, modelData.colorHex);
                                } else if (modelData.action) {
                                    modelData.action();
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    component Separator: Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 2
        Layout.bottomMargin: 2
        implicitHeight: 1
        height: 1
        color: "#222222"
    }
}
