import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: usageBar

    property string title: "Usage"
    property real percent: 0
    property string resetsAt: ""

    UsageColorProvider {
        id: colors
    }

    property color barColor: percent >= Constants.usageCriticalThreshold ? colors.criticalColor
        : percent >= Constants.usageWarningThreshold ? colors.warningColor
            : colors.normalColor

    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            text: title
            Layout.fillWidth: true
            font.weight: Font.Medium
        }

        PlasmaComponents.Label {
            text: percent.toFixed(1) + "%"
            color: barColor
            font.bold: true
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
        }
    }

    Rectangle {
        Layout.fillWidth: true
        height: Kirigami.Units.gridUnit * 0.5
        radius: height / 2
        color: Kirigami.Theme.backgroundColor
        border.color: Qt.alpha(Kirigami.Theme.textColor, 0.2)
        border.width: 1

        Rectangle {
            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
            }
            width: parent.width * Math.min(percent, 100) / 100
            radius: parent.radius
            color: barColor

            Behavior on width {
                NumberAnimation {
                    duration: Constants.progressAnimationDuration; easing.type: Easing.OutQuad
                }
            }

            Behavior on color {
                ColorAnimation {
                    duration: Constants.progressAnimationDuration
                }
            }
        }
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        visible: resetsAt !== ""
        text: { void root.resetTimeTick; return TimeFormatter.formatResetTime(resetsAt) }
        font: Kirigami.Theme.smallFont
        opacity: 0.6
    }
}
