import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

Item {
    id: compactRoot

    Kirigami.Theme.colorSet: Kirigami.Theme.Header
    Kirigami.Theme.inherit: false

    Layout.minimumWidth: Kirigami.Units.iconSizes.small
    Layout.minimumHeight: Kirigami.Units.iconSizes.small
    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
    Layout.preferredHeight: Kirigami.Units.iconSizes.medium

    // Show session usage, fall back to weekly if session is 0
    property real percent: root.sessionPercent > 0 ? root.sessionPercent : root.weeklyPercent
    UsageColorProvider {
        id: colors
    }

    property color usageColor: percent >= Constants.usageCriticalThreshold ? colors.criticalColor
        : percent >= Constants.usageWarningThreshold ? colors.warningColor
            : colors.normalColor
    onUsageColorChanged: canvas.requestPaint()
    property bool hasError: root.errorMessage !== ""

    MouseArea {
        anchors.fill: parent
        onClicked: root.expanded = !root.expanded
        hoverEnabled: true

        // Donut chart visualization
        Canvas {
            id: canvas
            anchors.fill: parent
            anchors.margins: Constants.donutCanvasMargin

            onPaint: {
                var ctx = getContext("2d")
                var centerX = width / 2
                var centerY = height / 2
                var radius = Math.min(width, height) / 2
                var innerRadius = radius * Constants.donutInnerRadiusRatio
                var lineWidth = radius - innerRadius
                var arcRadius = (radius + innerRadius) / 2

                ctx.reset()
                ctx.lineCap = "butt"
                ctx.lineWidth = lineWidth

                // Background track ring
                ctx.beginPath()
                ctx.arc(centerX, centerY, arcRadius, 0, 2 * Math.PI)
                ctx.strokeStyle = Qt.alpha(Kirigami.Theme.textColor, 0.15)
                ctx.stroke()

                if (hasError) {
                    // Full red ring for error state
                    ctx.beginPath()
                    ctx.arc(centerX, centerY, arcRadius, 0, 2 * Math.PI)
                    ctx.strokeStyle = Qt.alpha(Kirigami.Theme.negativeTextColor, 0.4)
                    ctx.stroke()
                } else if (percent > 0) {
                    // Usage arc
                    ctx.beginPath()
                    var startAngle = -Math.PI / 2
                    var endAngle = startAngle + (Math.min(percent, 100) / 100) * 2 * Math.PI
                    ctx.arc(centerX, centerY, arcRadius, startAngle, endAngle)
                    ctx.strokeStyle = usageColor
                    ctx.stroke()
                }
            }

            Connections {
                target: root

                function onSessionPercentChanged() {
                    canvas.requestPaint()
                }

                function onWeeklyPercentChanged() {
                    canvas.requestPaint()
                }

                function onErrorMessageChanged() {
                    canvas.requestPaint()
                }
            }

            Connections {
                target: Kirigami.Theme

                function onTextColorChanged() {
                    canvas.requestPaint()
                }

                function onPositiveTextColorChanged() {
                    canvas.requestPaint()
                }

                function onNegativeTextColorChanged() {
                    canvas.requestPaint()
                }

                function onNeutralTextColorChanged() {
                    canvas.requestPaint()
                }
            }

            Component.onCompleted: requestPaint()
        }

        // Percentage text in center
        PlasmaComponents.Label {
            anchors.centerIn: parent
            text: {
                if (root.isLoading) return "..."
                if (hasError) return "!"
                if (percent >= 100) return "!"
                return Math.round(percent)
            }
            color: hasError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            font.pixelSize: parent.height * Constants.donutTextSizeRatio
            font.bold: true
        }

        // Loading indicator
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: Kirigami.Theme.highlightColor
            border.width: 1
            radius: width / 2
            visible: root.isLoading
            opacity: 0.5

            SequentialAnimation on opacity {
                running: root.isLoading
                loops: Animation.Infinite
                NumberAnimation {
                    to: 0.2; duration: Constants.loadingAnimationDuration
                }
                NumberAnimation {
                    to: 0.8; duration: Constants.loadingAnimationDuration
                }
            }
        }
    }
}
