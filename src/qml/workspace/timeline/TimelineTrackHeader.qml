import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../components"

Item {
    id: root

    property int trackIndex: -1
    property string trackId: ""
    property string trackName: ""
    property int trackKind: 0
    property bool isVideo: trackKind === 0
    property bool isSelected: false

    implicitWidth: 90
    property int expandedHeight: 68
    property int collapsedHeight: 36
    property int minHeight: 36
    property int maxHeight: 500
    property bool isCollapsed: false

    implicitHeight: isCollapsed ? collapsedHeight : expandedHeight

    property bool isLocked: false
    property bool isVideoDisabled: false
    property bool isAudioDisabled: false
    property bool isFxDisabled: false

    property var timelineRoot: null
    property var activeTimelineModel: (timelineRoot && timelineRoot.activeTimelineModel) ? timelineRoot.activeTimelineModel : (typeof timelineModel !== "undefined" ? timelineModel : null)
    property var activePlaybackManager: (timelineRoot && timelineRoot.activePlaybackManager) ? timelineRoot.activePlaybackManager : (typeof playbackManager !== "undefined" ? playbackManager : null)
    property int currentPlayheadFrame: activePlaybackManager ? activePlaybackManager.currentFrame : (timelineRoot ? timelineRoot.playheadFrame : 0)

    property bool isHighlighted: {
        if (timelineRoot && typeof timelineRoot.isPlayheadOnClipInTrack === "function") {
            var _triggerFrame = root.currentPlayheadFrame;
            return timelineRoot.isPlayheadOnClipInTrack(root.trackIndex);
        }
        if (root.activeTimelineModel && root.trackIndex >= 0) {
            var pf = root.currentPlayheadFrame;
            var clips = root.activeTimelineModel.getClipsForTrack ? root.activeTimelineModel.getClipsForTrack(root.trackIndex) : [];
            for (var i = 0; i < clips.length; ++i) {
                var c = clips[i];
                var startF = Number(c.startFrame);
                var endF = startF + Number(c.durationFrames);
                if (pf >= startF && pf < endF)
                    return true;
            }
        }
        return false;
    }

    signal trackRenamed(string newName)
    signal lockToggled(bool locked)
    signal trackHeightChanged(int newHeight)
    signal trackSelected(int index)

    // notify parent model whenever collapse state or manual resizing alters implicit height
    onImplicitHeightChanged: {
        root.trackHeightChanged(root.implicitHeight);
    }

    Behavior on implicitHeight {
        enabled: !resizeMouse.pressed
        NumberAnimation {
            duration: 160
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.isSelected ? "#202026" : (root.isLocked ? "#141414" : "#181818")

        Behavior on color {
            ColorAnimation {
                duration: 120
            }
        }

        MouseArea {
            anchors.fill: parent
            z: 0
            onClicked: {
                if (typeof timelineModel !== "undefined" && timelineModel) {
                    if (root.trackIndex >= 0) {
                        timelineModel.selectTrack(root.trackIndex);
                    } else if (root.trackId !== "") {
                        timelineModel.selectTrackById(root.trackId);
                    }
                }
                root.trackSelected(root.trackIndex);
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: "#1E1E1E"
            z: 5
        }

        Rectangle {
            id: rightBorder
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: "transparent"
            z: 5
        }

        Rectangle {
            id: accentStrip
            width: root.isSelected ? 4 : 3
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            color: root.isLocked ? "#3a3a3a" : (root.isSelected ? (root.isVideo ? "#38bdf8" : "#22c55e") : (root.isVideo ? "#0284c7" : "#15803d"))
            z: 2

            Behavior on width {
                NumberAnimation {
                    duration: 100
                }
            }
        }

        Item {
            id: paletteStripContainer
            anchors.right: rightBorder.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 8
            z: 6

            Rectangle {
                id: paletteIndicator
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 4
                height: Math.max(8, parent.height - 24)
                topLeftRadius: 2
                bottomLeftRadius: 2
                opacity: 0.4
                color: root.isHighlighted ? (root.isVideo ? "#3b82f6" : "#22c55e") : "#222222"

                Behavior on color {
                    ColorAnimation {
                        duration: 120
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: root.isVideo ? "#3b82f6" : "#22c55e"
                    opacity: root.isHighlighted ? 0.6 : 0.0
                    z: -1

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 120
                        }
                    }
                }
            }
        }

        RowLayout {
            anchors.left: parent.left
            anchors.right: paletteStripContainer.left
            anchors.top: parent.top
            anchors.topMargin: Math.max(2, (root.collapsedHeight - height) / 2)
            anchors.leftMargin: 8
            anchors.rightMargin: 4
            height: 28
            spacing: 6
            z: 2

            Item {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18

                Image {
                    anchors.centerIn: parent
                    source: "qrc:/assets/icons/chevron-down.svg"
                    sourceSize.width: 12
                    sourceSize.height: 12
                    opacity: root.isLocked ? 0.4 : 0.8
                    rotation: root.isCollapsed ? -90 : 0

                    Behavior on rotation {
                        NumberAnimation {
                            duration: 160
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.isCollapsed = !root.isCollapsed
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 24

                Text {
                    id: nameText
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: root.trackName
                    color: root.isLocked ? "#555555" : (root.isSelected ? "#ffffff" : "#d0d0d5")
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    visible: !nameInputWrapper.visible
                }

                Rectangle {
                    id: nameInputWrapper
                    anchors.fill: parent
                    color: "#121212"
                    border.color: "#2555D3"
                    border.width: 1
                    radius: 3
                    visible: false

                    TextInput {
                        id: nameInput
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        verticalAlignment: Text.AlignVCenter
                        text: root.trackName
                        color: "#ffffff"
                        font.pixelSize: 12
                        font.bold: true
                        selectByMouse: true

                        onAccepted: submitRename()
                        onEditingFinished: submitRename()

                        function submitRename() {
                            if (!nameInputWrapper.visible)
                                return;
                            nameInputWrapper.visible = false;
                            var trimmed = text.trim();
                            if (trimmed.length > 0) {
                                root.trackName = trimmed;
                                root.trackRenamed(trimmed);
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !root.isLocked && !nameInputWrapper.visible
                    cursorShape: Qt.IBeamCursor
                    onDoubleClicked: {
                        nameInput.text = root.trackName;
                        nameInputWrapper.visible = true;
                        nameInput.forceActiveFocus();
                        nameInput.selectAll();
                    }
                }
            }

            RowLayout {
                spacing: 4
                opacity: root.isLocked ? 0.35 : 1.0

                XylaIconButton {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    iconWidth: 13
                    iconHeight: 13
                    enabled: !root.isLocked
                    iconSource: "qrc:/assets/icons/sparkles.svg"
                    primary: !root.isFxDisabled
                    ghost: root.isFxDisabled
                    onClicked: root.isFxDisabled = !root.isFxDisabled
                }

                XylaIconButton {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    iconWidth: 13
                    iconHeight: 13
                    visible: root.isVideo
                    enabled: !root.isLocked
                    iconSource: root.isVideoDisabled ? "qrc:/assets/icons/eye-off.svg" : "qrc:/assets/icons/eye.svg"
                    primary: !root.isVideoDisabled
                    ghost: root.isVideoDisabled
                    onClicked: root.isVideoDisabled = !root.isVideoDisabled
                }

                XylaIconButton {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    iconWidth: 13
                    iconHeight: 13
                    visible: !root.isVideo
                    enabled: !root.isLocked
                    iconSource: root.isAudioDisabled ? "qrc:/assets/icons/volume-off.svg" : "qrc:/assets/icons/volume.svg"
                    primary: !root.isAudioDisabled
                    ghost: root.isAudioDisabled
                    onClicked: root.isAudioDisabled = !root.isAudioDisabled
                }

                XylaIconButton {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    iconWidth: 13
                    iconHeight: 13
                    iconSource: root.isLocked ? "qrc:/assets/icons/lock.svg" : "qrc:/assets/icons/lock-open.svg"
                    primary: root.isLocked
                    ghost: !root.isLocked
                    onClicked: {
                        root.isLocked = !root.isLocked;
                        root.lockToggled(root.isLocked);
                    }
                }
            }
        }

        // bottom edge resize grip
        Item {
            height: 8
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.bottom
            z: 10
            visible: !root.isCollapsed

            Rectangle {
                height: 2
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                color: resizeMouse.containsMouse || resizeMouse.pressed ? "#2555D3" : "transparent"
            }

            MouseArea {
                id: resizeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.SizeVerCursor
                preventStealing: true

                property int startMouseY: 0
                property int startHeight: 0

                onPressed: function (mouse) {
                    var pt = mapToItem(root, mouse.x, mouse.y);
                    startMouseY = pt.y;
                    startHeight = root.expandedHeight;
                }

                onPositionChanged: function (mouse) {
                    if (pressed && !root.isCollapsed) {
                        var pt = mapToItem(root, mouse.x, mouse.y);
                        var deltaY = pt.y - startMouseY;
                        var newH = Math.max(root.minHeight, Math.min(root.maxHeight, startHeight + deltaY));
                        root.expandedHeight = newH;
                    }
                }
            }
        }
    }
}
