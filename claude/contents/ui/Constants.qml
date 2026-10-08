pragma Singleton
import QtQuick

QtObject {
    id: constants

    // Usage threshold percentages for color coding
    readonly property int usageCriticalThreshold: 90
    readonly property int usageWarningThreshold: 75

    // Donut chart geometry
    readonly property real donutInnerRadiusRatio: 0.6
    readonly property int donutCanvasMargin: 2
    readonly property real donutTextSizeRatio: 0.3

    // Error handling
    readonly property int errorMessageMaxLength: 50

    // Animation durations
    readonly property int progressAnimationDuration: 300
    readonly property int loadingAnimationDuration: 500
}
