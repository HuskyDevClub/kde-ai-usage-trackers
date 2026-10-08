pragma Singleton
import QtQuick

QtObject {
    id: timeFormatter

    readonly property var locale: Qt.locale()

    function formatResetTime(resetsAt) {
        if (!resetsAt) return ""

        var resetDate = new Date(resetsAt)
        var now = new Date()

        if (resetDate <= now) return ""

        var timeStr = resetDate.toLocaleTimeString(locale, Locale.ShortFormat)
        var remainingStr = formatRemainingTime(resetDate, now)
        var dayLabel = getDayLabel(resetDate, now)

        if (dayLabel === "today") {
            return "Resets today " + timeStr + " (in " + remainingStr + ")"
        } else if (dayLabel === "tomorrow") {
            return "Resets tomorrow " + timeStr + " (in " + remainingStr + ")"
        } else {
            var dateStr = formatDateShort(resetDate)
            return "Resets " + dateStr + ", " + timeStr + " (in " + remainingStr + ")"
        }
    }

    function formatRemainingTime(resetDate, now) {
        var diffMs = resetDate - now
        var diffMins = Math.floor(diffMs / (1000 * 60))
        var hours = Math.floor(diffMins / 60)
        var mins = diffMins % 60

        if (hours >= 24) {
            var days = Math.floor(hours / 24)
            var remHours = hours % 24
            return days + "d " + remHours + "h"
        }
        if (hours > 0) {
            return hours + "h " + mins + "m"
        }
        return mins + "m"
    }

    function getDayLabel(resetDate, now) {
        var today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        var resetDay = new Date(resetDate.getFullYear(), resetDate.getMonth(), resetDate.getDate())
        var diffDays = Math.floor((resetDay - today) / (1000 * 60 * 60 * 24))

        if (diffDays === 0) return "today"
        if (diffDays === 1) return "tomorrow"
        return "later"
    }

    function formatDateShort(date) {
        var monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return monthNames[date.getMonth()] + " " + date.getDate()
    }
}
