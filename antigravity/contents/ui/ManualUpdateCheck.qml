// Shared file: edit shared/contents/ui/ManualUpdateCheck.qml, then run `./sync-shared.sh`.
import QtQuick
import org.kde.plasma.plasma5support as PlasmaSupport

// "Check now" on a widget's settings page. Config pages can't call into the applet,
// so this runs check_update.py itself, then nudges the widget to re-read the cached result.
PlasmaSupport.DataSource {
    engine: "executable"
    connectedSources: []

    property string status: ""
    property bool busy: false
    property bool failed: false

    // Emitted for every config key this writes; the page copies the value into its matching
    // cfg_ property so that pressing Apply doesn't write back a stale value
    signal configWritten(string key, string value)

    onNewData: function (source, data) {
        disconnectSource(source)
        busy = false

        var result = null
        try {
            result = JSON.parse(data["stdout"] || "")
        } catch (e) {
            result = null
        }

        if (!result || result.error) {
            failed = true
            status = result && result.error
                ? result.error
                : i18nc("@info", "Update check failed")
            return
        }

        failed = false
        if (result.updateAvailable) {
            status = i18nc("@info", "Version %1 is available — open the widget to install it", result.latestVersion)
            // Checking by hand undoes an earlier "Skip" of this version
            writeConfig("dismissedUpdateVersion", "")
        } else {
            status = i18nc("@info", "You're up to date (version %1)", result.currentVersion)
        }

        // Nudge the widget to re-read the result this check just cached
        writeConfig("updateCheckedAt", String(new Date().getTime()))
    }

    // Written straight to the applet's config so it lands now, rather than waiting for the user to hit Apply
    function writeConfig(key, value) {
        plasmoid.configuration[key] = value
        configWritten(key, value)
    }

    function check() {
        busy = true
        failed = false
        status = i18nc("@info", "Checking…")

        var script = decodeURIComponent(Qt.resolvedUrl("../code/check_update.py").toString().replace(/^file:\/\//, ""))
        connectSource("python3 \"" + script + "\" --force")
    }
}
