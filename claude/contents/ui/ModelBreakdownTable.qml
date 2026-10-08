import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: modelTable

    property real sonnetPercent: 0
    property string sonnetResetsAt: ""
    property real opusPercent: 0
    property string opusResetsAt: ""

    spacing: Kirigami.Units.smallSpacing

    PlasmaComponents.Label {
        text: "Per-Model Usage"
        font.weight: Font.Medium
        Layout.fillWidth: true
    }

    // Header row
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            text: "Model"
            Layout.fillWidth: true
            font: Kirigami.Theme.smallFont
            opacity: 0.6
        }

        PlasmaComponents.Label {
            text: "Utilization"
            Layout.preferredWidth: Kirigami.Units.gridUnit * 5
            horizontalAlignment: Text.AlignRight
            font: Kirigami.Theme.smallFont
            opacity: 0.6
        }
    }

    // Model rows
    Repeater {
        model: [
            {name: "Sonnet", pct: sonnetPercent, resets: sonnetResetsAt},
            {name: "Opus", pct: opusPercent, resets: opusResetsAt}
        ]

        ModelRow {
            Layout.fillWidth: true
            modelName: modelData.name
            percent: modelData.pct
            resetsAt: modelData.resets
            tick: root.resetTimeTick
        }
    }

    // Empty state
    PlasmaComponents.Label {
        visible: sonnetPercent <= 0 && opusPercent <= 0
        text: "No per-model data available"
        font: Kirigami.Theme.smallFont
        opacity: 0.5
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
    }
}
