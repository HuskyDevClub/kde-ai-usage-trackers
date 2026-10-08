import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// Paid usage beyond the plan, for trackers whose data includes "extra"
ColumnLayout {
    // {used, limit, utilization}; a limit of 0 means no monthly cap is set
    property var extra: null

    readonly property real used: extra ? extra.used || 0 : 0
    readonly property real limit: extra ? extra.limit || 0 : 0
    readonly property real utilization: extra ? extra.utilization || 0 : 0

    spacing: Kirigami.Units.smallSpacing

    UsageColorProvider {
        id: colors
    }

    Kirigami.Separator {
        Layout.fillWidth: true
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            text: i18nc("@title", "Extra Usage")
            Layout.fillWidth: true
            font.weight: Font.Medium
        }

        PlasmaComponents.Label {
            text: "$" + used.toFixed(2) + (limit > 0 ? " / $" + limit.toFixed(2) : "")
            font: Kirigami.Theme.smallFont
            opacity: 0.8
        }
    }

    // Without a cap there is nothing to fill, so the bar only shows with one
    Rectangle {
        Layout.fillWidth: true
        height: 3
        radius: height / 2
        visible: limit > 0
        color: Qt.alpha(Kirigami.Theme.textColor, 0.1)

        Rectangle {
            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
            }
            width: parent.width * Math.min(utilization, 100) / 100
            radius: parent.radius
            color: colors.colorFor(utilization)

            Behavior on width {
                NumberAnimation {
                    duration: Constants.progressAnimationDuration; easing.type: Easing.OutQuad
                }
            }
        }
    }
}
