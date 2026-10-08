import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: barChart

    // Daily usage data from root.dailyHistory (populated by fetch_usage.py)
    // Each entry: { day: "Mon", date: "2026-02-12", percent: 45.2 }
    property var dailyData: root.dailyHistory || []

    UsageColorProvider {
        id: colors
    }

    spacing: Kirigami.Units.smallSpacing

    PlasmaComponents.Label {
        text: "Recent Usage"
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
            visible: !dailyData || dailyData.length === 0
            text: "Usage history builds over time"
            font: Kirigami.Theme.smallFont
            opacity: 0.5
        }

        // Bar chart
        Row {
            anchors.fill: parent
            anchors.bottomMargin: Kirigami.Units.gridUnit * 1.2
            spacing: 2
            visible: dailyData && dailyData.length > 0

            Repeater {
                model: dailyData || []

                Item {
                    width: (parent.width - (dailyData.length - 1) * 2) / dailyData.length
                    height: parent.height

                    // Bar
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 4
                        height: Math.max(2, parent.height * Math.min(modelData.percent, 100) / 100)
                        radius: 2
                        color: modelData.percent >= Constants.usageCriticalThreshold ? colors.criticalColor
                            : modelData.percent >= Constants.usageWarningThreshold ? colors.warningColor
                                : colors.normalColor
                        opacity: 0.8

                        Behavior on height {
                            NumberAnimation {
                                duration: Constants.progressAnimationDuration; easing.type: Easing.OutQuad
                            }
                        }
                    }

                    // Percentage label on top of bar
                    PlasmaComponents.Label {
                        id: percentLabel
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Math.min(
                            Math.max(2, parent.height * Math.min(modelData.percent, 100) / 100) + 2,
                            parent.height - implicitHeight
                        )
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
            visible: dailyData && dailyData.length > 0

            Repeater {
                model: dailyData || []

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
