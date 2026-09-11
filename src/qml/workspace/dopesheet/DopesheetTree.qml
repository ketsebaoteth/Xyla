import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: treeViewRoot

    property var treeRows: []
    property int headerWidth: 200
    property string activePropId: ""
    property string activeClipId: ""

    signal toggleRowExpansion(int rowIndex)
    signal trackSelected(string clipId, string propId)
    signal contextMenuRequested(real globalX, real globalY, string clipId, string propId, bool isMuted, bool isLocked)

    Layout.fillHeight: true
    Layout.preferredWidth: treeViewRoot.headerWidth
    color: "#131313"

    // 1px Border separator between tree and canvas
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: "#222222"
        z: 3
    }

    Column {
        anchors.fill: parent
        anchors.rightMargin: 1

        Repeater {
            model: treeViewRoot.treeRows

            delegate: Rectangle {
                id: rowRect

                required property var modelData
                required property int index

                // Fallback resolver for root control reference
                readonly property var treeOwner: {
                    if (typeof treeViewRoot !== "undefined" && treeViewRoot)
                        return treeViewRoot;
                    if (typeof root !== "undefined" && root)
                        return root;
                    if (typeof control !== "undefined" && control)
                        return control;
                    return rowRect.parent.parent;
                }

                readonly property string rowClipId: (modelData && modelData.clipId) ? modelData.clipId : ""
                readonly property string rowPropId: (modelData && modelData.propId) ? modelData.propId : ""
                readonly property string rowType: (modelData && modelData.type) ? modelData.type : ""
                readonly property string rowName: (modelData && modelData.name) ? modelData.name : ""
                readonly property int rowIndent: (modelData && modelData.indent) ? modelData.indent : 0
                readonly property int rowKeyCount: (modelData && modelData.keyCount) ? modelData.keyCount : 0
                readonly property bool isChannel: rowType === "channel"
                readonly property bool isExpandable: !!(modelData && modelData.isExpandable)
                readonly property bool isExpanded: !!(modelData && modelData.expanded)
                readonly property bool isMutedTrack: !!(modelData && modelData.isMuted)
                readonly property bool isLockedTrack: !!modelData.isLocked
                readonly property color trackColor: (modelData && modelData.color) ? modelData.color : "#3B82F6"
                readonly property bool isActiveTrack: isChannel && rowPropId === (treeOwner ? treeOwner.activePropId : "")

                width: (treeOwner ? treeOwner.headerWidth : 200) - 1
                height: 24

                // Base color with track color tint
                color: {
                    var base = "#131313";
                    if (isActiveTrack)
                        base = "#202020";
                    else if (rowMouse.containsMouse)
                        base = "#181818";
                    else if (rowType === "clip")
                        base = "#161616";

                    if (rowRect.isChannel && !rowRect.isMutedTrack) {
                        return Qt.tint(base, Qt.rgba(rowRect.trackColor.r, rowRect.trackColor.g, rowRect.trackColor.b, isActiveTrack ? 0.12 : 0.07));
                    }
                    return base;
                }

                // Active top border: light gray
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 1
                    color: "#4A4A4A"
                    visible: rowRect.isActiveTrack
                    z: 2
                }

                // Active bottom border: light gray
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: "#4A4A4A"
                    visible: rowRect.isActiveTrack
                    z: 2
                }

                // Left color strip for channel identification
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 3
                    color: rowRect.isMutedTrack ? "#555555" : rowRect.trackColor
                    visible: rowRect.isChannel
                    z: 3
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: rowRect.isExpandable ? Qt.PointingHandCursor : Qt.ArrowCursor

                    onPressed: function (mouse) {
                        var target = rowRect.treeOwner;
                        if (!target)
                            return;

                        if (rowRect.isChannel) {
                            target.trackSelected(rowRect.rowClipId, rowRect.rowPropId);
                        }

                        if (mouse.button === Qt.RightButton) {
                            var pt = rowMouse.mapToItem(Overlay.overlay, mouse.x, mouse.y);
                            target.contextMenuRequested(pt.x, pt.y, rowRect.rowClipId, rowRect.rowPropId, rowRect.isMutedTrack, rowRect.isLockedTrack);
                        } else if (mouse.button === Qt.LeftButton && rowRect.isExpandable) {
                            target.toggleRowExpansion(rowRect.index);
                        }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8 + (rowRect.rowIndent * 12)
                    anchors.rightMargin: 8
                    spacing: 6

                    // Chevron rotation animation only
                    Item {
                        width: 14
                        height: 14
                        visible: rowRect.isExpandable
                        Layout.alignment: Qt.AlignVCenter

                        Image {
                            anchors.centerIn: parent
                            width: 11
                            height: 11
                            source: "qrc:/assets/icons/chevron-down.svg"
                            sourceSize: Qt.size(11, 11)
                            opacity: rowMouse.containsMouse ? 0.95 : 0.6
                            transformOrigin: Item.Center
                            rotation: rowRect.isExpanded ? 0 : -90

                            Behavior on rotation {
                                NumberAnimation {
                                    duration: 120
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }

                    // Property Color Indicator
                    Rectangle {
                        visible: rowRect.isChannel
                        width: 6
                        height: 6
                        radius: 3
                        color: rowRect.isMutedTrack ? "#555555" : rowRect.trackColor
                        opacity: rowRect.isMutedTrack ? 0.4 : 1.0
                        Layout.alignment: Qt.AlignVCenter
                    }

                    // Track Label
                    Text {
                        Layout.fillWidth: true
                        text: rowRect.rowName
                        color: {
                            if (rowRect.isMutedTrack)
                                return "#555555";
                            if (rowRect.isActiveTrack)
                                return "#FFFFFF";
                            if (rowRect.rowType === "clip")
                                return "#EDEDED";
                            if (rowRect.rowType === "group")
                                return "#AAAAAA";
                            return "#CCCCCC";
                        }
                        font.pixelSize: rowRect.rowType === "clip" ? 11 : 10
                        font.bold: rowRect.rowType === "clip" || rowRect.rowType === "group" || rowRect.isActiveTrack
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }

                    // Lock Status Icon
                    Image {
                        visible: rowRect.isLockedTrack
                        source: "qrc:/assets/icons/lock.svg"
                        sourceSize: Qt.size(11, 11)
                        Layout.preferredWidth: 11
                        Layout.preferredHeight: 11
                        opacity: 0.7
                        Layout.alignment: Qt.AlignVCenter
                    }

                    // Mute Status Icon
                    Image {
                        visible: rowRect.isMutedTrack
                        source: "qrc:/assets/icons/volume-off.svg"
                        sourceSize: Qt.size(11, 11)
                        Layout.preferredWidth: 11
                        Layout.preferredHeight: 11
                        opacity: 0.5
                        Layout.alignment: Qt.AlignVCenter
                    }

                    // Key count badge
                    Rectangle {
                        visible: rowRect.rowKeyCount > 0
                        implicitHeight: 14
                        implicitWidth: keyCountText.implicitWidth + 8
                        radius: 7
                        color: rowRect.isActiveTrack ? "#2E2E2E" : "#1C1C1C"
                        Layout.alignment: Qt.AlignVCenter

                        Text {
                            id: keyCountText
                            anchors.centerIn: parent
                            text: "" + rowRect.rowKeyCount
                            color: rowRect.isMutedTrack ? "#444444" : (rowRect.isActiveTrack ? "#FFFFFF" : "#777777")
                            font.pixelSize: 9
                            font.family: "Monospace"
                        }
                    }
                }
            }
        }
    }
}
