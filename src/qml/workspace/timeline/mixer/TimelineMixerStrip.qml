import QtQuick
import QtQuick.Effects
import Xyla 1.0

Item {
    id: root

    property var mixerModel: null

    width: 90
    z: 20

    // background surface with drop shadow casting over canvas
    Rectangle {
        id: bgRect
        anchors.fill: parent
        color: "#181818"

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#99000000"
            shadowBlur: 16
            shadowHorizontalOffset: -8
            shadowVerticalOffset: 0
        }
    }

    // left shadow fallback gradient
    Rectangle {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.left
        width: 8
        z: 100
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.0
                color: "#00000000"
            }
            GradientStop {
                position: 1.0
                color: "#66000000"
            }
        }
    }

    // direct binding to master peak meter without dummy delegates
    Item {
        anchors.fill: parent
        anchors.topMargin: 18
        anchors.rightMargin: 20
        anchors.bottomMargin: 18

        XylaPeakMeter {
            id: masterPeakMeter
            anchors.fill: parent
            itemWidth: 14
            peakLeft: root.mixerModel ? (root.mixerModel.masterPeakL || 0.0) : 0.0
            peakRight: root.mixerModel ? (root.mixerModel.masterPeakR || 0.0) : 0.0
            doNotShowNumbers: true
        }
    }
}
