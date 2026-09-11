import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../components"

Rectangle {
    id: root

    height: 40
    Layout.fillWidth: true
    color: "#181818"

    property int activeViewMode: 0 // 0: Dopesheet, 1: Graph Editor

    signal viewModeChanged(int mode)

    signal selectAllRequested
    signal selectNoneRequested
    signal invertSelectionRequested
    signal selectBeforePlayheadRequested
    signal selectAfterPlayheadRequested

    signal deleteSelectedRequested
    signal snapToPlayheadRequested
    signal setInterpolationRequested(int interpType)

    signal expandAllRequested
    signal collapseAllRequested

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: "#242424"
    }

    component DopesheetMenuButton: Rectangle {
        id: btnRoot

        property string label: ""
        property Menu targetMenu: null
        readonly property bool isOpen: targetMenu ? targetMenu.visible : false
        readonly property bool isHovered: btnMouse.containsMouse

        implicitHeight: 24
        implicitWidth: btnText.implicitWidth + 16
        radius: 4
        color: (btnRoot.isOpen || btnRoot.isHovered) ? "#262626" : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: 60
            }
        }

        Text {
            id: btnText
            anchors.centerIn: parent
            text: btnRoot.label
            color: (btnRoot.isOpen || btnRoot.isHovered) ? "#ffffff" : "#aaaaaa"
            font.pixelSize: 11
            font.weight: (btnRoot.isOpen || btnRoot.isHovered) ? Font.Medium : Font.Normal

            Behavior on color {
                ColorAnimation {
                    duration: 60
                }
            }
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (btnRoot.targetMenu) {
                    if (btnRoot.targetMenu.visible) {
                        btnRoot.targetMenu.close();
                    } else {
                        btnRoot.targetMenu.open();
                    }
                }
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 4

        // 1. VIEW TRIGGER
        DopesheetMenuButton {
            label: "View"
            targetMenu: viewMenu

            XylaMenu {
                id: viewMenu
                y: parent.height + 3

                XylaMenuItem {
                    text: "Expand All"
                    onTriggered: root.expandAllRequested()
                }
                XylaMenuItem {
                    text: "Collapse All"
                    onTriggered: root.collapseAllRequested()
                }
            }
        }

        // 2. SELECT TRIGGER
        DopesheetMenuButton {
            label: "Select"
            targetMenu: selectMenu

            XylaMenu {
                id: selectMenu
                y: parent.height + 3

                XylaMenuItem {
                    text: "All"
                    itemShortcut: "A"
                    onTriggered: root.selectAllRequested()
                }
                XylaMenuItem {
                    text: "None"
                    itemShortcut: "Alt+A"
                    onTriggered: root.selectNoneRequested()
                }
                XylaMenuItem {
                    text: "Invert"
                    itemShortcut: "Ctrl+I"
                    onTriggered: root.invertSelectionRequested()
                }
                XylaMenuSeparator {}
                XylaMenuItem {
                    text: "Before Current Frame"
                    itemShortcut: "["
                    onTriggered: root.selectBeforePlayheadRequested()
                }
                XylaMenuItem {
                    text: "After Current Frame"
                    itemShortcut: "]"
                    onTriggered: root.selectAfterPlayheadRequested()
                }
            }
        }

        // 3. KEY TRIGGER
        DopesheetMenuButton {
            label: "Key"
            targetMenu: keyMenu

            XylaMenu {
                id: keyMenu
                y: parent.height + 3

                XylaMenuItem {
                    text: "Delete Selected"
                    itemShortcut: "Del"
                    onTriggered: root.deleteSelectedRequested()
                }
                XylaMenuItem {
                    text: "Snap to Playhead"
                    itemShortcut: "Shift+S"
                    onTriggered: root.snapToPlayheadRequested()
                }
                XylaMenuSeparator {}
                XylaMenuItem {
                    text: "Interpolation: Constant"
                    onTriggered: root.setInterpolationRequested(0)
                }
                XylaMenuItem {
                    text: "Interpolation: Linear"
                    onTriggered: root.setInterpolationRequested(1)
                }
                XylaMenuItem {
                    text: "Interpolation: Bezier"
                    onTriggered: root.setInterpolationRequested(2)
                }
            }
        }

        Item {
            Layout.fillWidth: true
        }

        // 4. ANIMATED SEGMENTED SLIDER (DOPESHEET <-> GRAPH)
        Item {
            id: modeControl
            property var options: [
                {
                    label: "Dopesheet",
                    value: 0
                },
                {
                    label: "Graph",
                    value: 1
                }
            ]
            property int currentIndex: root.activeViewMode
            property int itemWidth: 76
            property int itemPadding: 2

            implicitHeight: 30
            implicitWidth: (itemWidth * options.length) + (itemPadding * 2)

            Rectangle {
                anchors.fill: parent
                color: "#0d0d0d"
                radius: 7

                // Apple-Style Sliding Indicator Pill
                Rectangle {
                    id: indicator
                    width: modeControl.itemWidth
                    height: parent.height - (modeControl.itemPadding * 2)
                    y: modeControl.itemPadding
                    radius: 5
                    color: "#11389F"

                    x: modeControl.itemPadding + (modeControl.currentIndex * modeControl.itemWidth)

                    Behavior on x {
                        NumberAnimation {
                            duration: 220
                            easing.type: Easing.OutQuint
                        }
                    }
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: modeControl.itemPadding

                    Repeater {
                        model: modeControl.options

                        Item {
                            id: optionItem
                            width: modeControl.itemWidth
                            height: parent.height

                            readonly property bool isSelected: index === modeControl.currentIndex
                            readonly property bool isHovered: optMouse.containsMouse

                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                font.pixelSize: 11
                                font.weight: optionItem.isSelected ? Font.Medium : Font.Normal
                                color: optionItem.isSelected ? "#ffffff" : (optionItem.isHovered ? "#dddddd" : "#888888")

                                Behavior on color {
                                    ColorAnimation {
                                        duration: 120
                                    }
                                }
                            }

                            MouseArea {
                                id: optMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    modeControl.currentIndex = index;
                                    root.activeViewMode = modelData.value;
                                    root.viewModeChanged(modelData.value);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
