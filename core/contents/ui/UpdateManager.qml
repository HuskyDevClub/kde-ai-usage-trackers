import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as PlasmaSupport

// Checks GitHub for a new release of the app and installs it. main.qml creates one,
// and UpdateNotice shows its state in the popup. Updating from any tracker's widget
// upgrades the whole app (see apply_update.sh).
Item {
    id: updater
    visible: false

    property bool updateAvailable: false
    // The running version, straight from metadata.json — available even when update checks are off
    readonly property string currentVersion: Plasmoid.metaData.version
    property string latestVersion: ""
    property string latestTag: ""
    property string releaseUrl: ""
    property string updateError: ""
    // idle | checking | installing | installed | failed
    property string updateState: "idle"
    readonly property bool busy: updateState === "checking" || updateState === "installing"

    // Transient feedback for a user-requested check ("up to date", or why it failed)
    property bool manualCheck: false
    property string updateNotice: ""
    property bool updateNoticeError: false

    // The GitHub update check
    ScriptRunner {
        id: updateChecker

        onSucceeded: function (result) {
            // A manual check reports back either way — an automatic one stays quiet unless there's an update
            var wasManual = finishCheck()

            if (result.error) {
                if (wasManual) showUpdateNotice(result.error, true)
                return
            }

            latestVersion = result.latestVersion || ""
            latestTag = result.latestTag || ""
            releaseUrl = result.releaseUrl || ""

            // Asking explicitly overrides an earlier "Skip" of this version
            updateAvailable = result.updateAvailable === true
                && (wasManual || latestVersion !== Plasmoid.configuration.dismissedUpdateVersion)

            if (wasManual) {
                if (updateAvailable) {
                    Plasmoid.configuration.dismissedUpdateVersion = ""
                } else {
                    showUpdateNotice(i18nc("@info", "You're up to date (version %1).", currentVersion), false)
                }
            }
        }

        onFailed: function (error) {
            if (finishCheck()) showUpdateNotice(error, true)
        }
    }

    // Leave the "checking" state, and say whether the check that just ended was a manual one
    function finishCheck() {
        var wasManual = manualCheck
        manualCheck = false
        if (updateState === "checking") {
            updateState = "idle"
        }
        return wasManual
    }

    // Installing an update
    ScriptRunner {
        id: updateInstaller

        onSucceeded: function (result) {
            if (result.success) {
                updateState = "installed"
                updateAvailable = false
                updateError = ""
            } else {
                updateState = "failed"
                updateError = result.error || "Update failed"
            }
        }

        onFailed: function (error) {
            updateState = "failed"
            updateError = error
        }
    }

    // DataSource for restarting plasmashell after an update
    PlasmaSupport.DataSource {
        id: plasmaRestarter
        engine: "executable"
        connectedSources: []

        onNewData: function (source, data) {
            disconnectSource(source)
        }

        function exec(cmd) {
            connectSource(cmd)
        }
    }

    // Check GitHub for a newer release. A manual check runs even with automatic checks turned off,
    // and always bypasses the script's 24h cache so "Check for Updates" really does check.
    function checkForUpdate(manual) {
        if (!manual && !Plasmoid.configuration.checkForUpdates) return
        runUpdateCheck(manual === true, manual === true)
    }

    // Re-read the result the settings page just cached — no network call, and no config gate,
    // since the user asking there is asking regardless of the automatic-check setting
    function refreshUpdateState() {
        runUpdateCheck(false, false)
    }

    function runUpdateCheck(force, manual) {
        // "installed" keeps the restart reminder up — checking again can't help until Plasma restarts
        if (busy || updateState === "installed") return

        manualCheck = manual
        updateNotice = ""
        updateState = "checking"
        updateChecker.run("python3", "check_update.py", force ? ["--force"] : [])
    }

    // Show transient feedback for a manual check
    function showUpdateNotice(text, isError) {
        updateNotice = text
        updateNoticeError = isError === true
        noticeTimer.restart()
    }

    Timer {
        id: noticeTimer
        interval: 10000
        onTriggered: updater.updateNotice = ""
    }

    // Download the latest release and run its installer, which upgrades every widget
    function installUpdate() {
        if (updateState === "installing" || latestTag === "") return

        // The tag comes from the GitHub API and ends up in a shell command — never pass through anything exotic
        if (!/^[A-Za-z0-9._-]+$/.test(latestTag)) {
            updateState = "failed"
            updateError = "Invalid release tag"
            return
        }

        updateState = "installing"
        updateError = ""
        updateInstaller.run("bash", "apply_update.sh", [latestTag])
    }

    // Hide the update notice until a newer version than this one is released
    function dismissUpdate() {
        Plasmoid.configuration.dismissedUpdateVersion = latestVersion
        updateAvailable = false
    }

    // Detached so the new shell survives the current one being replaced
    function restartPlasma() {
        plasmaRestarter.exec("setsid -f plasmashell --replace")
    }

    // Periodic update check — the script only hits GitHub once a day, this just re-reads its cache
    Timer {
        interval: 6 * 60 * 60 * 1000
        running: Plasmoid.configuration.checkForUpdates
        repeat: true
        onTriggered: updater.checkForUpdate(false)
    }

    Connections {
        target: Plasmoid.configuration

        // Check immediately when the user turns update checks back on
        function onCheckForUpdatesChanged() {
            if (Plasmoid.configuration.checkForUpdates) {
                updater.checkForUpdate(false)
            } else {
                updater.updateAvailable = false
            }
        }

        // The settings page ran a check — pick up its freshly cached result
        function onUpdateCheckedAtChanged() {
            updater.refreshUpdateState()
        }
    }

    Component.onCompleted: checkForUpdate(false)
}
