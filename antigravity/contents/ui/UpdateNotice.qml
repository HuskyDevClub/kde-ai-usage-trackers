// Shared file: edit shared/contents/ui/UpdateNotice.qml, then run `./sync-shared.sh`.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// The update banner at the top of a widget's popup, showing an UpdateManager's state
Kirigami.InlineMessage {
    required property UpdateManager updater

    Layout.fillWidth: true
    Layout.topMargin: Kirigami.Units.smallSpacing
    visible: updater.updateAvailable
        || updater.updateNotice !== ""
        || updater.updateState === "installing"
        || updater.updateState === "installed"
        || updater.updateState === "failed"

    type: {
        if (updater.updateState === "failed") return Kirigami.MessageType.Error
        if (updater.updateNotice !== "") return updater.updateNoticeError
            ? Kirigami.MessageType.Error : Kirigami.MessageType.Positive
        if (updater.updateState === "installed") return Kirigami.MessageType.Positive
        return Kirigami.MessageType.Information
    }

    text: {
        if (updater.updateState === "installing")
            return i18nc("@info", "Installing version %1…", updater.latestVersion)
        if (updater.updateState === "installed")
            return i18nc("@info", "Version %1 installed. Restart Plasma to apply it.", updater.latestVersion)
        if (updater.updateState === "failed")
            return i18nc("@info", "Update failed: %1", updater.updateError)
        if (updater.updateNotice !== "")
            return updater.updateNotice
        return i18nc("@info", "Version %1 is available (you have %2).", updater.latestVersion, updater.currentVersion)
    }

    actions: [
        Kirigami.Action {
            text: i18nc("@action:button", "Update now")
            icon.name: "system-software-update"
            visible: updater.updateAvailable && updater.updateState !== "installing"
            onTriggered: updater.installUpdate()
        },
        Kirigami.Action {
            text: i18nc("@action:button", "Restart Plasma")
            icon.name: "system-reboot"
            visible: updater.updateState === "installed"
            onTriggered: updater.restartPlasma()
        },
        Kirigami.Action {
            text: i18nc("@action:button", "Retry")
            icon.name: "view-refresh"
            visible: updater.updateState === "failed"
            onTriggered: updater.installUpdate()
        },
        Kirigami.Action {
            text: i18nc("@action:button", "Release notes")
            icon.name: "internet-web-browser"
            visible: updater.releaseUrl !== ""
                && (updater.updateAvailable || updater.updateState === "failed")
            onTriggered: Qt.openUrlExternally(updater.releaseUrl)
        },
        Kirigami.Action {
            text: i18nc("@action:button", "Skip")
            icon.name: "dialog-close"
            visible: updater.updateAvailable && updater.updateState === "idle"
            onTriggered: updater.dismissUpdate()
        }
    ]
}
