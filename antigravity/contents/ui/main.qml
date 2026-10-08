import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as PlasmaSupport
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Antigravity usage properties
    property string tier: ""
    property var groups: []
    property real maxPercent: 0
    property string lastUpdated: ""
    property string errorMessage: ""
    property bool isLoading: false
    property bool notLoggedIn: false
    property bool pinned: false

    property string currentVersion: Plasmoid.metaData.version

    hideOnWindowDeactivate: !pinned

    // Refresh control
    property var lastFetchTime: null
    property int refreshMinutes: Math.max(1, Plasmoid.configuration.refreshIntervalMinutes)
    property int backoffMultiplier: 1
    property int maxBackoffMultiplier: 8

    switchWidth: Kirigami.Units.gridUnit * 14
    switchHeight: Kirigami.Units.gridUnit * 12

    toolTipMainText: "Antigravity Usage Tracker"
    toolTipSubText: {
        if (errorMessage !== "") {
            return errorMessage
        }
        if (groups && groups.length > 0) {
            var parts = []
            for (var i = 0; i < groups.length; i++) {
                var g = groups[i]
                var maxB = 0
                for (var j = 0; j < (g.buckets || []).length; j++) {
                    if (g.buckets[j].used > maxB) maxB = g.buckets[j].used
                }
                parts.push(g.name + ": " + maxB.toFixed(1) + "%")
            }
            return parts.join("\n")
        }
        return "Peak Usage: " + maxPercent.toFixed(1) + "%"
    }

    compactRepresentation: CompactRepresentation {
    }
    fullRepresentation: FullRepresentation {
    }

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

            // Fetch fresh data after cache is loaded
            fetchUsage()
        }

        function loadCache() {
            connectSource("cat \"$HOME/.local/share/antigravity-usage-tracker/usage.json\" 2>/dev/null")
        }
    }

    function codePath(fileName) {
        return decodeURIComponent(Qt.resolvedUrl("../code/" + fileName).toString().replace(/^file:\/\//, ""))
    }

    function fetchUsage() {
        if (isLoading) return
        isLoading = true
        executable.exec("python3 \"" + codePath("fetch_usage.py") + "\"")
    }

    function parseUsageData(data) {
        if (!data || typeof data !== "object") {
            errorMessage = "Invalid response format"
            return
        }

        if (data.rateLimited) {
            backoffMultiplier = Math.min(backoffMultiplier * 2, maxBackoffMultiplier)
        } else {
            backoffMultiplier = 1
        }

        if (data.error) {
            errorMessage = data.error
            notLoggedIn = data.notLoggedIn === true
            return
        }

        tier = data.tier || ""
        groups = data.groups || []
        maxPercent = data.maxPercent || 0
        notLoggedIn = false
        errorMessage = ""
    }

    function refresh() {
        lastFetchTime = null
        fetchUsage()
    }

    // Global tick counter for reset countdown updates
    property int resetTimeTick: 0
    Timer {
        interval: 30000
        running: true
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

    Component.onCompleted: {
        cacheLoader.loadCache()
    }
}
