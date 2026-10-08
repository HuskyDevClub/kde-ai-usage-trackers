import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: modelRow

    property string modelName: ""
    property real percent: 0
    property string resetsAt: ""
    property int tick: 0

    UsageColorProvider {
        id: colors
    }

    Layout.fillWidth: true
    visible: percent > 0
    spacing: 2

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            text: modelName
            Layout.fillWidth: true
        }

        PlasmaComponents.Label {
            text: percent.toFixed(1) + "%"
            Layout.preferredWidth: Kirigami.Units.gridUnit * 5
            horizontalAlignment: Text.AlignRight
            color: percent >= Constants.usageCriticalThreshold ? colors.criticalColor
                : percent >= Constants.usageWarningThreshold ? colors.warningColor
                    : colors.normalColor
            font.bold: true
        }
    }

    // Mini progress bar
    Rectangle {
        Layout.fillWidth: true
        height: 3
        radius: height / 2
        color: Qt.alpha(Kirigami.Theme.textColor, 0.1)

        Rectangle {
            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
            }
            width: parent.width * Math.min(percent, 100) / 100
            radius: parent.radius
            color: percent >= Constants.usageCriticalThreshold ? colors.criticalColor
                : percent >= Constants.usageWarningThreshold ? colors.warningColor
                    : colors.normalColor

            Behavior on width {
                NumberAnimation {
                    duration: Constants.progressAnimationDuration; easing.type: Easing.OutQuad
                }
            }
        }
    }

    PlasmaComponents.Label {
        visible: resetsAt !== ""
        text: { void tick; return TimeFormatter.formatResetTime(resetsAt) }
        font: Kirigami.Theme.smallFont
        opacity: 0.5
    }
}
