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

    header: PlasmaExtras.PlasmoidHeading {
        RowLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            PlasmaExtras.Heading {
                Layout.fillWidth: true
                level: 2
                text: i18nc("@title", "Antigravity Usage")
            }

            // Plan / Tier badge
            Rectangle {
                visible: root.tier !== "" && root.tier !== "unknown"
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
                    text: root.tier
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.highlightColor
                }
            }

            PlasmaComponents.ToolButton {
                icon.name: "view-refresh"
                onClicked: root.refresh()
                enabled: !root.isLoading

                PlasmaComponents.ToolTip {
                    text: i18nc("@action:button", "Refresh now")
                }
            }

            PlasmaComponents.ToolButton {
                icon.name: "configure"
                onClicked: Plasmoid.internalAction("configure").trigger()

                PlasmaComponents.ToolTip {
                    text: i18nc("@action:button", "Configure")
                }
            }

            PlasmaComponents.ToolButton {
                visible: root.compactRepresentationItem !== null
                icon.name: "window-pin"
                onClicked: root.pinned = !root.pinned
                checkable: true
                checked: root.pinned

                PlasmaComponents.ToolTip {
                    text: root.pinned ? i18nc("@action:button", "Unpin popup") : i18nc("@action:button", "Keep open")
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
                UpdateNotice {
                    updater: root.updater
                }

                // Login reminder
                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    visible: root.errorMessage !== "" && root.notLoggedIn
                    type: Kirigami.MessageType.Information
                    text: i18nc("@info", "You are not logged into Antigravity.\nRun 'agy' in your terminal to set up credentials.")
                }

                // Error message
                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    level: 4
                    text: root.errorMessage
                    color: Kirigami.Theme.negativeTextColor
                    wrapMode: Text.WordWrap
                    visible: root.errorMessage !== "" && !root.notLoggedIn
                    horizontalAlignment: Text.AlignHCenter
                }

                // Loading indicator
                PlasmaComponents.BusyIndicator {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.isLoading
                    running: root.isLoading
                }

                // Model groups
                Repeater {
                    model: root.groups

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Separator {
                            Layout.fillWidth: true
                            visible: index > 0
                            Layout.topMargin: Kirigami.Units.smallSpacing
                            Layout.bottomMargin: Kirigami.Units.smallSpacing
                        }

                        // Group Title
                        PlasmaComponents.Label {
                            text: modelData.name
                            font.weight: Font.DemiBold
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.05
                            Layout.fillWidth: true
                        }

                        // Group Description
                        PlasmaComponents.Label {
                            text: modelData.description
                            font: Kirigami.Theme.smallFont
                            opacity: 0.65
                            wrapMode: Text.WordWrap
                            visible: modelData.description !== ""
                            Layout.fillWidth: true
                        }

                        // Buckets in this group
                        Repeater {
                            model: modelData.buckets

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                UsageBar {
                                    Layout.fillWidth: true
                                    title: modelData.title
                                    percent: modelData.used
                                    resetsAt: modelData.resetsAt || ""
                                }

                                // Notice if this bucket is disabled / limit reached
                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    visible: modelData.disabled === true
                                    text: modelData.description || i18nc("@info", "Limit reached")
                                    font: Kirigami.Theme.smallFont
                                    color: Kirigami.Theme.neutralTextColor
                                    opacity: 0.75
                                    wrapMode: Text.WordWrap
                                    Layout.leftMargin: Kirigami.Units.smallSpacing
                                }
                            }
                        }
                    }
                }

                // Empty state
                PlasmaComponents.Label {
                    visible: !root.isLoading && root.errorMessage === "" && (!root.groups || root.groups.length === 0)
                    text: i18nc("@info", "No Antigravity quota data available")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.5
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
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
