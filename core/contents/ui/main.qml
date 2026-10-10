import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

// The widget for one tracker. Nothing here is tracker-specific: the tracker's
// metadata.json names it, and its fetch_usage.py supplies the usage data in the
// shape described in tracker_common.py.
PlasmoidItem {
    id: root

    // The tracker's display name, e.g. "Claude"
    readonly property string trackerName: Plasmoid.metaData.rawData["X-Tracker-Name"] || Plasmoid.metaData.name

    // Latest usage from fetch_usage.py
    property string plan: ""
    property var groups: []
    property real panelPercent: 0
    property var extra: null
    property var history: []
    property string lastUpdated: ""
    property string errorMessage: ""
    property bool notLoggedIn: false
    property bool isLoading: false

    property bool pinned: false
    hideOnWindowDeactivate: !pinned

    // GitHub release check and one-click update, shown by UpdateNotice in the popup
    UpdateManager {
        id: updateManager
    }
    property alias updater: updateManager

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
    readonly property int maxBackoffMultiplier: 8

    switchWidth: Kirigami.Units.gridUnit * 14
    switchHeight: Kirigami.Units.gridUnit * 12

    toolTipMainText: i18nc("@info:tooltip", "%1 Usage", trackerName)
    toolTipSubText: {
        if (errorMessage !== "") return errorMessage

        // A named group is summarised by its busiest limit; an unnamed one lists each limit
        var lines = []
        for (var group of groups) {
            var buckets = group.buckets || []
            if (group.name) {
                var peak = Math.max(0, ...buckets.map(b => b.used || 0))
                lines.push(group.name + ": " + peak.toFixed(1) + "%")
            } else {
                for (var bucket of buckets) {
                    lines.push(bucket.title + ": " + (bucket.used || 0).toFixed(1) + "%")
                }
            }
        }
        return lines.join("\n")
    }

    compactRepresentation: CompactRepresentation {
    }
    fullRepresentation: FullRepresentation {
    }

    // Opening the popup refreshes data that is older than the refresh interval
    onExpandedChanged: function (expanded) {
        if (expanded && isCacheStale()) {
            fetchUsage()
        }
    }

    function isCacheStale() {
        if (!lastFetchTime) return true
        var diffMinutes = (new Date() - lastFetchTime) / (1000 * 60)
        return diffMinutes >= (refreshMinutes * backoffMultiplier)
    }

    ScriptRunner {
        id: usageFetcher

        onSucceeded: function (result) {
            isLoading = false
            applyUsage(result)
            lastFetchTime = new Date()
            var timeStr = lastFetchTime.toLocaleTimeString(Qt.locale(), "HH:mm:ss")
            lastUpdated = result.rateLimited ? timeStr + " (cached)" : timeStr
        }

        onFailed: function (error) {
            isLoading = false
            errorMessage = error
        }
    }

    // Shows the last cached result at startup, then fetches fresh data
    ScriptRunner {
        id: cacheLoader

        onSucceeded: function (result) {
            applyUsage(result)
            lastUpdated = "cached"
            fetchUsage()
        }

        // No cache yet
        onFailed: fetchUsage()
    }

    function fetchUsage() {
        if (isLoading) return
        isLoading = true
        usageFetcher.run("python3", "fetch_usage.py")
    }

    // Manual refresh (force fetch)
    function refresh() {
        lastFetchTime = null
        fetchUsage()
    }

    // Take in fetch_usage.py output. On an error, the last good data stays on screen.
    function applyUsage(data) {
        if (!data || typeof data !== "object") {
            errorMessage = "Invalid response format"
            return
        }

        // Back off exponentially while rate limited; the script serves cached data meanwhile
        backoffMultiplier = data.rateLimited ? Math.min(backoffMultiplier * 2, maxBackoffMultiplier) : 1

        if (data.error) {
            errorMessage = data.error
            notLoggedIn = data.notLoggedIn === true
            return
        }

        plan = data.plan || ""
        groups = Array.isArray(data.groups) ? data.groups : []
        panelPercent = data.panelPercent || 0
        extra = data.extra || null
        if (Array.isArray(data.history)) history = data.history
        notLoggedIn = false
        errorMessage = ""
    }

    // Ticks while any limit has a reset time, so the "resets in" countdowns stay current
    property int resetTimeTick: 0
    Timer {
        interval: 30000
        running: root.groups.some(group => (group.buckets || []).some(bucket => bucket.resetsAt))
        repeat: true
        onTriggered: root.resetTimeTick++
    }

    // Auto-refresh timer
    Timer {
        interval: refreshMinutes * 60 * 1000 * backoffMultiplier
        running: true
        repeat: true
        onTriggered: fetchUsage()
    }

    Component.onCompleted: cacheLoader.run("python3", "fetch_usage.py", ["--cached"])
}
