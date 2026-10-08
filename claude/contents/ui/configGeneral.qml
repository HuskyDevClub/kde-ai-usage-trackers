import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as PlasmaSupport

KCM.SimpleKCM {
    property alias cfg_refreshIntervalMinutes: refreshSpinBox.value
    property int cfg_refreshIntervalMinutesDefault: 5
    property alias cfg_showExtraUsage: showExtraUsageCheckBox.checked
    property bool cfg_showExtraUsageDefault: true
    property alias cfg_showRecentUsage: showRecentUsageCheckBox.checked
    property bool cfg_showRecentUsageDefault: false
    property alias cfg_checkForUpdates: checkForUpdatesCheckBox.checked
    property bool cfg_checkForUpdatesDefault: true
    // Not user-editable, but the config dialog binds a cfg_ property per config key —
    // declaring these keeps it from warning, and keeps Apply from writing back stale values
    property string cfg_dismissedUpdateVersion
    property string cfg_dismissedUpdateVersionDefault: ""
    property string cfg_updateCheckedAt
    property string cfg_updateCheckedAtDefault: ""
    property alias cfg_useCustomColors: useCustomColorsCheckBox.checked
    property bool cfg_useCustomColorsDefault: false
    property string cfg_normalColor
    property string cfg_normalColorDefault: "#27ae60"
    property string cfg_warningColor
    property string cfg_warningColorDefault: "#f39c12"
    property string cfg_criticalColor
    property string cfg_criticalColorDefault: "#e74c3c"

    // Manual update check state (config pages can't call into the applet, so this page checks for itself)
    property string updateCheckStatus: ""
    property bool updateCheckBusy: false
    property bool updateCheckFailed: false

    PlasmaSupport.DataSource {
        id: updateChecker
        engine: "executable"
        connectedSources: []

        onNewData: function (source, data) {
            disconnectSource(source)
            updateCheckBusy = false

            var result = null
            try {
                result = JSON.parse(data["stdout"] || "")
            } catch (e) {
                result = null
            }

            if (!result || result.error) {
                updateCheckFailed = true
                updateCheckStatus = result && result.error
                    ? result.error
                    : i18nc("@info", "Update check failed")
                return
            }

            updateCheckFailed = false
            if (result.updateAvailable) {
                updateCheckStatus = i18nc("@info", "Version %1 is available — open the widget to install it", result.latestVersion)
                // Checking by hand undoes an earlier "Skip" of this version
                cfg_dismissedUpdateVersion = ""
                plasmoid.configuration.dismissedUpdateVersion = ""
            } else {
                updateCheckStatus = i18nc("@info", "You're up to date (version %1)", result.currentVersion)
            }

            // Nudge the widget to re-read the result this check just cached. Written straight to the
            // applet's config so it lands now, rather than waiting for the user to hit Apply.
            var stamp = String(new Date().getTime())
            cfg_updateCheckedAt = stamp
            plasmoid.configuration.updateCheckedAt = stamp
        }

        function check() {
            updateCheckBusy = true
            updateCheckFailed = false
            updateCheckStatus = i18nc("@info", "Checking…")

            var script = decodeURIComponent(Qt.resolvedUrl("../code/check_update.py").toString().replace(/^file:\/\//, ""))
            connectSource("python3 \"" + script + "\" --force")
        }
    }

    // Accessibility color presets
    readonly property var colorPresets: [
        null,
        {normal: "#56B4E9", warning: "#E69F00", critical: "#CC3311"},
        {normal: "#009E73", warning: "#CC79A7", critical: "#D55E00"},
        {normal: "#00CC44", warning: "#FFAA00", critical: "#EE0000"}
    ]

    function applyPreset(index) {
        var preset = colorPresets[index]
        if (preset) {
            cfg_normalColor = preset.normal
            cfg_warningColor = preset.warning
            cfg_criticalColor = preset.critical
            useCustomColorsCheckBox.checked = true
            presetCombo.currentIndex = 0
        }
    }

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: refreshSpinBox
            Kirigami.FormData.label: i18nc("@label:spinbox", "Refresh interval (minutes):")
            // Keep the "from:" key — a bare value here is a QML syntax error that blanks the whole page
            from: 1
            to: 60
            stepSize: 1
        }

        QQC2.Label {
            text: i18ncp("@info", "Every %1 minute", "Every %1 minutes", refreshSpinBox.value)
            opacity: 0.7
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18nc("@title", "Display")
        }

        QQC2.CheckBox {
            id: showExtraUsageCheckBox
            Kirigami.FormData.label: i18nc("@label:checkbox", "Show extra usage:")
            text: i18nc("@option:check", "Show paid overage section")
        }

        QQC2.CheckBox {
            id: showRecentUsageCheckBox
            Kirigami.FormData.label: i18nc("@label:checkbox", "Show recent usage:")
            text: i18nc("@option:check", "Show daily usage chart")
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18nc("@title", "Updates")
        }

        QQC2.CheckBox {
            id: checkForUpdatesCheckBox
            Kirigami.FormData.label: i18nc("@label:checkbox", "Check for updates:")
            text: i18nc("@option:check", "Check automatically once a day")
        }

        QQC2.Button {
            Kirigami.FormData.label: i18nc("@label", "Manual check:")
            text: i18nc("@action:button", "Check now")
            icon.name: "system-software-update"
            enabled: !updateCheckBusy
            onClicked: updateChecker.check()
        }

        QQC2.Label {
            text: updateCheckStatus
            visible: updateCheckStatus !== ""
            color: updateCheckFailed ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            opacity: 0.9
            wrapMode: Text.WordWrap
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18nc("@title", "Colors")
        }

        QQC2.CheckBox {
            id: useCustomColorsCheckBox
            Kirigami.FormData.label: i18nc("@label:checkbox", "Custom colors:")
            text: i18nc("@option:check", "Use custom color scheme")
        }

        QQC2.ComboBox {
            id: presetCombo
            Kirigami.FormData.label: i18nc("@label", "Accessibility preset:")
            enabled: useCustomColorsCheckBox.checked

            model: [
                i18nc("@item:inlistbox", "Select a preset..."),
                i18nc("@item:inlistbox", "Deuteranopia / Protanopia"),
                i18nc("@item:inlistbox", "Tritanopia"),
                i18nc("@item:inlistbox", "High Contrast")
            ]

            onActivated: function (index) {
                applyPreset(index)
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18nc("@label", "Normal (< 75%):")
            enabled: useCustomColorsCheckBox.checked
            spacing: Kirigami.Units.smallSpacing

            Rectangle {
                width: Kirigami.Units.gridUnit * 2
                height: Kirigami.Units.gridUnit * 1.5
                radius: 4
                color: cfg_normalColor
                border.color: Qt.alpha(Kirigami.Theme.textColor, 0.4)
                border.width: 1
                opacity: parent.enabled ? 1.0 : 0.4

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: normalColorDialog.open()
                }
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18nc("@label", "Warning (75-90%):")
            enabled: useCustomColorsCheckBox.checked
            spacing: Kirigami.Units.smallSpacing

            Rectangle {
                width: Kirigami.Units.gridUnit * 2
                height: Kirigami.Units.gridUnit * 1.5
                radius: 4
                color: cfg_warningColor
                border.color: Qt.alpha(Kirigami.Theme.textColor, 0.4)
                border.width: 1
                opacity: parent.enabled ? 1.0 : 0.4

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: warningColorDialog.open()
                }
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18nc("@label", "Critical (> 90%):")
            enabled: useCustomColorsCheckBox.checked
            spacing: Kirigami.Units.smallSpacing

            Rectangle {
                width: Kirigami.Units.gridUnit * 2
                height: Kirigami.Units.gridUnit * 1.5
                radius: 4
                color: cfg_criticalColor
                border.color: Qt.alpha(Kirigami.Theme.textColor, 0.4)
                border.width: 1
                opacity: parent.enabled ? 1.0 : 0.4

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: criticalColorDialog.open()
                }
            }
        }

        QQC2.Button {
            text: i18nc("@action:button", "Reset to theme colors")
            icon.name: "edit-undo"
            onClicked: {
                useCustomColorsCheckBox.checked = false
                cfg_normalColor = cfg_normalColorDefault
                cfg_warningColor = cfg_warningColorDefault
                cfg_criticalColor = cfg_criticalColorDefault
                presetCombo.currentIndex = 0
            }
        }
    }

    ColorDialog {
        id: normalColorDialog
        selectedColor: cfg_normalColor
        onAccepted: cfg_normalColor = selectedColor
    }

    ColorDialog {
        id: warningColorDialog
        selectedColor: cfg_warningColor
        onAccepted: cfg_warningColor = selectedColor
    }

    ColorDialog {
        id: criticalColorDialog
        selectedColor: cfg_criticalColor
        onAccepted: cfg_criticalColor = selectedColor
    }
}
