import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: barChart

    // Each day's peak usage, recorded by tracker_common.py: { day: "Mon", date: "2026-02-12", percent: 45.2 }
    property var dailyData: root.history || []

    UsageColorProvider {
        id: colors
    }

    spacing: Kirigami.Units.smallSpacing

    PlasmaComponents.Label {
        text: i18nc("@title", "Recent Usage")
        font.weight: Font.Medium
        Layout.fillWidth: true
    }

    // Bar chart area
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: Kirigami.Units.gridUnit * 3

        // Placeholder when no data
        PlasmaComponents.Label {
            anchors.centerIn: parent
            visible: dailyData.length === 0
            text: i18nc("@info", "Usage history builds over time")
            font: Kirigami.Theme.smallFont
            opacity: 0.5
        }

        // Bar chart
        Row {
            anchors.fill: parent
            anchors.bottomMargin: Kirigami.Units.gridUnit * 1.2
            spacing: 2
            visible: dailyData.length > 0

            Repeater {
                model: dailyData

                Item {
                    // At least a sliver, so a 0% day still shows a bar
                    readonly property real barHeight: Math.max(2, height * Math.min(modelData.percent, 100) / 100)

                    width: (parent.width - (dailyData.length - 1) * 2) / dailyData.length
                    height: parent.height

                    // Bar
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 4
                        height: parent.barHeight
                        radius: 2
                        color: colors.colorFor(modelData.percent)
                        opacity: 0.8

                        Behavior on height {
                            NumberAnimation {
                                duration: Constants.progressAnimationDuration; easing.type: Easing.OutQuad
                            }
                        }
                    }

                    // Percentage label on top of bar
                    PlasmaComponents.Label {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Math.min(parent.barHeight + 2, parent.height - implicitHeight)
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Math.round(modelData.percent) + "%"
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize * 0.9
                        opacity: 0.7
                        visible: modelData.percent > 0
                    }
                }
            }
        }

        // Day labels row
        Row {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 2
            visible: dailyData.length > 0

            Repeater {
                model: dailyData

                Item {
                    width: (parent.width - (dailyData.length - 1) * 2) / dailyData.length
                    height: Kirigami.Units.gridUnit

                    PlasmaComponents.Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        text: modelData.day
                        font: Kirigami.Theme.smallFont
                        opacity: 0.6
                    }
                }
            }
        }
    }
}
