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

    // The running version, straight from metadata.json — available even when update checks are off
    property string currentVersion: Plasmoid.metaData.version

    // GitHub release check and one-click update, shown by UpdateNotice in the popup
    UpdateManager {
        id: updateManager
    }
    property alias updater: updateManager

    hideOnWindowDeactivate: !pinned

    // Right-click menu entry, so a manual check is reachable without opening the popup
    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18nc("@action", "Check for Updates")
            icon.name: "system-software-update"
            enabled: !root.updater.busy
            onTriggered: {
                root.expanded = true  // the result shows up in the popup
                root.updater.checkForUpdate(true)
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

// Initial load: show cached data first, then fetch fresh data (triggered by cacheLoader.onNewData)
Component.onCompleted: {
    cacheLoader.loadCache()
}
}
