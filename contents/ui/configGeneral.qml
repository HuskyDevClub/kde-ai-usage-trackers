import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_refreshIntervalMinutes: refreshSpinBox.value
    property int cfg_refreshIntervalMinutesDefault: 5
    property alias cfg_useCustomColors: useCustomColorsCheckBox.checked
    property bool cfg_useCustomColorsDefault: false
    property string cfg_normalColor
    property string cfg_normalColorDefault: "#27ae60"
    property string cfg_warningColor
    property string cfg_warningColorDefault: "#f39c12"
    property string cfg_criticalColor
    property string cfg_criticalColorDefault: "#e74c3c"

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
