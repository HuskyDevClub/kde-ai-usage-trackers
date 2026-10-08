import QtQuick
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

// The colors for each usage level: the theme's, or the user's custom ones
QtObject {
    id: colorProvider

    readonly property color normalColor: Plasmoid.configuration.useCustomColors
        ? (Plasmoid.configuration.normalColor || "#27ae60")
        : Kirigami.Theme.positiveTextColor

    readonly property color warningColor: Plasmoid.configuration.useCustomColors
        ? (Plasmoid.configuration.warningColor || "#f39c12")
        : Kirigami.Theme.neutralTextColor

    readonly property color criticalColor: Plasmoid.configuration.useCustomColors
        ? (Plasmoid.configuration.criticalColor || "#e74c3c")
        : Kirigami.Theme.negativeTextColor

    function colorFor(percent) {
        return percent >= Constants.usageCriticalThreshold ? criticalColor
            : percent >= Constants.usageWarningThreshold ? warningColor
                : normalColor
    }
}
