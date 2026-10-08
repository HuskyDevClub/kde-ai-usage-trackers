import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

PlasmaExtras.Representation {
    id: fullRoot

    Kirigami.Theme.colorSet: Kirigami.Theme.View
    Kirigami.Theme.inherit: false

    implicitWidth: Kirigami.Units.gridUnit * 22
    implicitHeight: Kirigami.Units.gridUnit * 20

    // Usage data model for the main bars
    property var usageModel: [
        {title: "Current Session", percent: root.sessionPercent, resetsAt: root.sessionResetsAt},
        {title: "Weekly Limits", percent: root.weeklyPercent, resetsAt: root.weeklyResetsAt}
    ]

    header: PlasmaExtras.PlasmoidHeading
    {
        RowLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            PlasmaExtras.Heading {
                Layout.fillWidth: true
                level: 2
                text: "Claude Usage"
            }

            // Plan badge
            Rectangle {
                visible: root.subscriptionType !== "" && root.subscriptionType !== "unknown"
                Layout.alignment: Qt.AlignVCenter
                width: badgeText.implicitWidth + Kirigami.Units.smallSpacing * 2
                height: badgeText.implicitHeight + Kirigami.Units.smallSpacing
                radius: height / 2
                color: Qt.alpha(Kirigami.Theme.highlightColor, 0.2)
                border.color: Kirigami.Theme.highlightColor
                border.width: 1

                PlasmaComponents.Label {
                    id: badgeText
                    anchors.centerIn: parent
                    text: root.subscriptionType.charAt(0).toUpperCase() + root.subscriptionType.slice(1)
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.highlightColor
                }
            }

            PlasmaComponents.ToolButton {
                icon.name: "view-refresh"
                onClicked: root.refresh()
                enabled: !root.isLoading

                PlasmaComponents.ToolTip {
                    text: "Refresh now"
                }
            }

            PlasmaComponents.ToolButton {
                icon.name: "configure"
                onClicked: Plasmoid.internalAction("configure").trigger()

                PlasmaComponents.ToolTip {
                    text: "Configure"
                }
            }

            PlasmaComponents.ToolButton {
                visible: root.compactRepresentationItem !== null
                icon.name: "window-pin"
                onClicked: root.pinned = !root.pinned
                checkable: true
                checked: root.pinned

                PlasmaComponents.ToolTip {
                    text: root.pinned ? "Unpin popup" : "Keep open"
                }
            }
        }
    }

    PlasmaComponents.ScrollView {
        anchors.fill: parent

        contentItem: Flickable {
            contentHeight: contentLayout.implicitHeight + Kirigami.Units.largeSpacing * 2
            clip: true

            ColumnLayout {
                id: contentLayout
                width: parent.width
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    leftMargin: Kirigami.Units.largeSpacing
                    rightMargin: Kirigami.Units.largeSpacing
                    topMargin: Kirigami.Units.mediumSpacing
                }
                spacing: Kirigami.Units.mediumSpacing

                // Update notice
                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    visible: root.updateAvailable
                        || root.updateNotice !== ""
                        || root.updateState === "installing"
                        || root.updateState === "installed"
                        || root.updateState === "failed"

                    type: {
                        if (root.updateState === "failed") return Kirigami.MessageType.Error
                        if (root.updateNotice !== "") return root.updateNoticeError
                            ? Kirigami.MessageType.Error : Kirigami.MessageType.Positive
                        if (root.updateState === "installed") return Kirigami.MessageType.Positive
                        return Kirigami.MessageType.Information
                    }

                    text: {
                        if (root.updateState === "installing")
                            return i18nc("@info", "Installing version %1…", root.latestVersion)
                        if (root.updateState === "installed")
                            return i18nc("@info", "Version %1 installed. Restart Plasma to apply it.", root.latestVersion)
                        if (root.updateState === "failed")
                            return i18nc("@info", "Update failed: %1", root.updateError)
                        if (root.updateNotice !== "")
                            return root.updateNotice
                        return i18nc("@info", "Version %1 is available (you have %2).", root.latestVersion, root.currentVersion)
                    }

                    actions: [
                        Kirigami.Action {
                            text: i18nc("@action:button", "Update now")
                            icon.name
                    :
                    "system-software-update"
                    visible: root.updateAvailable && root.updateState !== "installing"
                    onTriggered: root.installUpdate()
                }
                ,
                Kirigami.Action {
                    text: i18nc("@action:button", "Restart Plasma")
                    icon.name: "system-reboot"
                    visible: root.updateState === "installed"
                    onTriggered: root.restartPlasma()
                }
                ,
                Kirigami.Action {
                    text: i18nc("@action:button", "Retry")
                    icon.name: "view-refresh"
                    visible: root.updateState === "failed"
                    onTriggered: root.installUpdate()
                }
                ,
                Kirigami.Action {
                    text: i18nc("@action:button", "Release notes")
                    icon.name: "internet-web-browser"
                    visible: root.releaseUrl !== ""
                        && (root.updateAvailable || root.updateState === "failed")
                    onTriggered: Qt.openUrlExternally(root.releaseUrl)
                }
                ,
                Kirigami.Action {
                    text: i18nc("@action:button", "Skip")
                    icon.name: "dialog-close"
                    visible: root.updateAvailable && root.updateState === "idle"
                    onTriggered: root.dismissUpdate()
                }
                ]
            }

            // Error message
            PlasmaExtras.Heading {
                Layout.fillWidth: true
                level: 4
                text: root.errorMessage
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.WordWrap
                visible: root.errorMessage !== ""
                horizontalAlignment: Text.AlignHCenter
            }

            // Loading indicator
            PlasmaComponents.BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                visible: root.isLoading
                running: root.isLoading
            }

            // Main usage bars (Session + Weekly)
            Repeater {
                model: usageModel

                UsageBar {
                    Layout.fillWidth: true
                    title: modelData.title
                    percent: modelData.percent
                    resetsAt: modelData.resetsAt
                }
            }

            // Separator before model breakdown
            Kirigami.Separator {
                Layout.fillWidth: true
                visible: root.sonnetPercent > 0 || root.opusPercent > 0
            }

            // Per-model breakdown table
            ModelBreakdownTable {
                Layout.fillWidth: true
                visible: root.sonnetPercent > 0 || root.opusPercent > 0
                sonnetPercent: root.sonnetPercent
                sonnetResetsAt: root.sonnetResetsAt
                opusPercent: root.opusPercent
                opusResetsAt: root.opusResetsAt
            }

            // Extra usage section (paid overage)
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.hasExtra && Plasmoid.configuration.showExtraUsage
                spacing: Kirigami.Units.smallSpacing

                UsageColorProvider {
                    id: extraColors
                }

                Kirigami.Separator {
                    Layout.fillWidth: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents.Label {
                        text: "Extra Usage"
                        Layout.fillWidth: true
                        font.weight: Font.Medium
                    }

                    PlasmaComponents.Label {
                        // A limit of 0 means no monthly cap is set on the account
                        text: root.extraLimit > 0
                            ? "$" + root.extraUsed.toFixed(2) + " / $" + root.extraLimit.toFixed(2)
                            : "$" + root.extraUsed.toFixed(2)
                        font: Kirigami.Theme.smallFont
                        opacity: 0.8
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 3
                    radius: height / 2
                    visible: root.extraLimit > 0
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.1)

                    Rectangle {
                        anchors {
                            left: parent.left
                            top: parent.top
                            bottom: parent.bottom
                        }
                        width: parent.width * Math.min(root.extraUtilization, 100) / 100
                        radius: parent.radius
                        color: root.extraUtilization >= Constants.usageCriticalThreshold ? extraColors.criticalColor
                            : root.extraUtilization >= Constants.usageWarningThreshold ? extraColors.warningColor
                                : extraColors.normalColor

                        Behavior on width {
                            NumberAnimation {
                                duration: Constants.progressAnimationDuration; easing.type: Easing.OutQuad
                            }
                        }
                    }
                }
            }

            // Separator before chart
            Kirigami.Separator {
                Layout.fillWidth: true
                visible: Plasmoid.configuration.showRecentUsage
            }

            // Daily usage chart
            UsageBarChart {
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 5
                visible: Plasmoid.configuration.showRecentUsage
            }

            // Last updated
            PlasmaComponents.Label {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                horizontalAlignment: Text.AlignHCenter
                text: {
                    var status = root.lastUpdated ? "Updated: " + root.lastUpdated : "Not yet updated"
                    return root.currentVersion !== "" ? status + " · v" + root.currentVersion : status
                }
                opacity: 0.6
                font: Kirigami.Theme.smallFont
            }
        }
    }
}
}
