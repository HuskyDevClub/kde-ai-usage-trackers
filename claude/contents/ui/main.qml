import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as PlasmaSupport
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Usage data properties
    property real sessionUsed: 0
    property real weeklyUsed: 0
    property real sonnetUsed: 0
    property real opusUsed: 0
    property string sessionResetsAt: ""
    property string weeklyResetsAt: ""
    property string sonnetResetsAt: ""
    property string opusResetsAt: ""
    property string subscriptionType: ""
    property string lastUpdated: ""
    property string errorMessage: ""
    property bool isLoading: false
    property bool pinned: false

    // Extra usage (paid overage)
    property real extraUsed: 0
    property real extraLimit: 0
    property real extraUtilization: 0
    property bool hasExtra: false

    // Daily usage history for chart
    property var dailyHistory: []

    // Update check state
    property bool updateAvailable: false
    // The running version, straight from metadata.json — available even when update checks are off
    property string currentVersion: Plasmoid.metaData.version
    property string latestVersion: ""
    property string latestTag: ""
    property string releaseUrl: ""
    property string updateError: ""
    // idle | checking | installing | installed | failed
    property string updateState: "idle"

    // Transient feedback for a user-requested check ("up to date", or why it failed)
    property bool manualCheck: false
    property string updateNotice: ""
    property bool updateNoticeError: false

    hideOnWindowDeactivate: !pinned

    // Right-click menu entry, so a manual check is reachable without opening the popup
    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18nc("@action", "Check for Updates")
            icon.name
    :
    "system-software-update"
    enabled: root.updateState !== "checking" && root.updateState !== "installing"
    onTriggered: {
        root.expanded = true  // the result shows up in the popup
        root.checkForUpdate(true)
    }
}
]

// Refresh control
property var lastFetchTime: null
property int refreshMinutes: Math.max(1, Plasmoid.configuration.refreshIntervalMinutes)
property int backoffMultiplier: 1
property int maxBackoffMultiplier: 8

// Computed percentages
property real sessionPercent: sessionUsed
property real weeklyPercent: weeklyUsed
property real sonnetPercent: sonnetUsed
property real opusPercent: opusUsed
property real maxPercent: Math.max(sessionPercent, weeklyPercent, sonnetPercent, opusPercent)

switchWidth: Kirigami.Units.gridUnit * 14
switchHeight: Kirigami.Units.gridUnit * 12

toolTipMainText: "Claude Usage Tracker"
toolTipSubText: errorMessage !== "" ? errorMessage :
    "Session: " + sessionPercent.toFixed(1) + "% | Weekly: " + weeklyPercent.toFixed(1) + "%"

compactRepresentation: CompactRepresentation {
}
fullRepresentation: FullRepresentation {
}

// Watch for expanded state changes
Connections {
    target: root

    function onExpandedChanged() {
        if (root.expanded && isCacheStale()) {
            fetchUsage()
        }
    }
}

function isCacheStale() {
    if (!lastFetchTime) return true
    var now = new Date()
    var diffMinutes = (now - lastFetchTime) / (1000 * 60)
    return diffMinutes >= (refreshMinutes * backoffMultiplier)
}

// Helper function to handle command output
function handleCommandOutput(data, onSuccess, onError) {
    var stdout = data["stdout"] || ""
    var stderr = data["stderr"] || ""
    var exitCode = data["exit code"] || 0

    if (exitCode === 0 && stdout) {
        try {
            var result = JSON.parse(stdout)
            onSuccess(result)
        } catch (e) {
            if (onError) onError("Parse error")
        }
    } else if (stderr && onError) {
        var truncatedError = stderr.length > Constants.errorMessageMaxLength
            ? stderr.substring(0, Constants.errorMessageMaxLength - 3) + "..."
            : stderr
        onError(truncatedError)
    } else if (onError) {
        onError("Fetch failed")
    }
}

// DataSource for running the fetch script
PlasmaSupport.DataSource {
    id: executable
    engine: "executable"
    connectedSources: []

    onNewData: function (source, data) {
        disconnectSource(source)
        isLoading = false

        handleCommandOutput(data,
                function (result) {
                parseUsageData(result)
                lastFetchTime = new Date()
                var timeStr = lastFetchTime.toLocaleTimeString(Qt.locale(), "HH:mm:ss")
                lastUpdated = result.rateLimited ? timeStr + " (cached)" : timeStr
            },
                function (error) {
                errorMessage = error
            }
        )
    }

    function exec(cmd) {
        connectSource(cmd)
    }
}

// DataSource for loading cached data at startup
PlasmaSupport.DataSource {
    id: cacheLoader
    engine: "executable"
    connectedSources: []

    onNewData: function (source, data) {
        disconnectSource(source)

        handleCommandOutput(data,
                function (result) {
                parseUsageData(result)
                lastUpdated = "cached"
            },
            null  // Silently ignore cache errors
        )

        // Fetch fresh data after cache is loaded (avoids race condition)
        fetchUsage()
    }

    function loadCache() {
        connectSource("cat \"$HOME/.local/share/claude-usage-tracker/usage.json\" 2>/dev/null")
    }
}

// DataSource for the GitHub update check
PlasmaSupport.DataSource {
    id: updateChecker
    engine: "executable"
    connectedSources: []

    onNewData: function (source, data) {
        disconnectSource(source)

        // A manual check reports back either way — an automatic one stays quiet unless there's an update
        var wasManual = manualCheck
        manualCheck = false

        if (updateState === "checking") {
            updateState = "idle"
        }

        handleCommandOutput(data,
                function (result) {
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
            },
                function (error) {
                if (wasManual) showUpdateNotice(error, true)
            }
        )
    }

    function exec(cmd) {
        connectSource(cmd)
    }
}

// DataSource for installing an update
PlasmaSupport.DataSource {
    id: updateInstaller
    engine: "executable"
    connectedSources: []

    onNewData: function (source, data) {
        disconnectSource(source)

        handleCommandOutput(data,
                function (result) {
                if (result.success) {
                    updateState = "installed"
                    updateAvailable = false
                    updateError = ""
                } else {
                    updateState = "failed"
                    updateError = result.error || "Update failed"
                }
            },
                function (error) {
                updateState = "failed"
                updateError = error
            }
        )
    }

    function exec(cmd) {
        connectSource(cmd)
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

// Absolute path to a helper script shipped with the widget
function codePath(fileName) {
    return decodeURIComponent(Qt.resolvedUrl("../code/" + fileName).toString().replace(/^file:\/\//, ""))
}

// Fetch usage via Python script
function fetchUsage() {
    if (isLoading) return

    isLoading = true

    executable.exec("python3 \"" + codePath("fetch_usage.py") + "\"")
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
    if (updateState === "checking" || updateState === "installing" || updateState === "installed") return

    manualCheck = manual
    updateNotice = ""
    updateState = "checking"
    updateChecker.exec("python3 \"" + codePath("check_update.py") + "\"" + (force ? " --force" : ""))
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
    onTriggered: root.updateNotice = ""
}

// Download and install the latest release
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
    updateInstaller.exec("bash \"" + codePath("apply_update.sh") + "\" \"" + latestTag + "\"")
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

// Parse API response with validation
function parseUsageData(data) {
    if (!data || typeof data !== "object") {
        errorMessage = "Invalid response format"
        return
    }

    // Handle rate limiting with exponential backoff
    if (data.rateLimited) {
        backoffMultiplier = Math.min(backoffMultiplier * 2, maxBackoffMultiplier)
        // Continue parsing cached data below (rateLimited responses carry cached data)
    } else {
        // Successful fetch — reset backoff
        backoffMultiplier = 1
    }

    if (data.error) {
        errorMessage = data.error
        return
    }

    // Session (5h window)
    if (data.session && typeof data.session === "object") {
        sessionUsed = data.session.used || 0
        sessionResetsAt = data.session.resetsAt || ""
    }

    // Weekly
    if (data.weekly && typeof data.weekly === "object") {
        weeklyUsed = data.weekly.used || 0
        weeklyResetsAt = data.weekly.resetsAt || ""
    }

    // Sonnet
    if (data.sonnet && typeof data.sonnet === "object") {
        sonnetUsed = data.sonnet.used || 0
        sonnetResetsAt = data.sonnet.resetsAt || ""
    }

    // Opus
    if (data.opus && typeof data.opus === "object") {
        opusUsed = data.opus.used || 0
        opusResetsAt = data.opus.resetsAt || ""
    }

    // Extra usage
    if (data.extra && typeof data.extra === "object") {
        extraUsed = data.extra.used || 0
        extraLimit = data.extra.limit || 0
        extraUtilization = data.extra.utilization || 0
        hasExtra = true
    } else {
        hasExtra = false
    }

    // Subscription type
    if (data.subscriptionType) {
        subscriptionType = data.subscriptionType
    }

    // Daily history
    if (data.dailyHistory && Array.isArray(data.dailyHistory)) {
        dailyHistory = data.dailyHistory
    }

    errorMessage = ""
}

// Manual refresh (force fetch)
function refresh() {
    lastFetchTime = null
    fetchUsage()
}

// Global tick counter for reset time updates (shared by UsageBar and ModelBreakdownTable)
property int resetTimeTick: 0
Timer {
    interval: 30000
    running: sessionResetsAt !== "" || weeklyResetsAt !== "" || sonnetResetsAt !== "" || opusResetsAt !== ""
    repeat: true
    onTriggered: root.resetTimeTick++
}

// Auto-refresh timer
Timer {
    id: refreshTimer
    interval: refreshMinutes * 60 * 1000 * backoffMultiplier
    running: true
    repeat: true
    onTriggered: fetchUsage()
}

// Periodic update check — the script only hits GitHub once a day, this just re-reads its cache
Timer {
    interval: 6 * 60 * 60 * 1000
    running: Plasmoid.configuration.checkForUpdates
    repeat: true
    onTriggered: checkForUpdate(false)
}

// Check immediately when the user turns update checks back on
Connections {
    target: Plasmoid.configuration

    function onCheckForUpdatesChanged() {
        if (Plasmoid.configuration.checkForUpdates) {
            checkForUpdate(false)
        } else {
            updateAvailable = false
        }
    }

    // The settings page ran a check — pick up its freshly cached result
    function onUpdateCheckedAtChanged() {
        refreshUpdateState()
    }
}

// Initial load: show cached data first, then fetch fresh data (triggered by cacheLoader.onNewData)
Component.onCompleted: {
    cacheLoader.loadCache()
    checkForUpdate(false)
}
}
