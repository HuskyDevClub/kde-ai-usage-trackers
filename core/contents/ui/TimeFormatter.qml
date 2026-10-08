pragma Singleton
import QtQuick

QtObject {
    id: timeFormatter

    readonly property var locale: Qt.locale()

    // e.g. "Resets tomorrow 9:00 AM (in 14h 5m)", or "" once the time has passed
    function formatResetTime(resetsAt) {
        if (!resetsAt) return ""

        var resetDate = new Date(resetsAt)
        var now = new Date()
        if (resetDate <= now) return ""

        var time = resetDate.toLocaleTimeString(locale, Locale.ShortFormat)
        var days = calendarDaysBetween(now, resetDate)
        var when = days === 0 ? "today " + time
            : days === 1 ? "tomorrow " + time
                : formatDateShort(resetDate) + ", " + time
        return "Resets " + when + " (in " + formatRemainingTime(resetDate, now) + ")"
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

    // Calendar days from one date to another, e.g. 1 for any time tomorrow
    function calendarDaysBetween(from, to) {
        var fromDay = new Date(from.getFullYear(), from.getMonth(), from.getDate())
        var toDay = new Date(to.getFullYear(), to.getMonth(), to.getDate())
        // Rounded, since a day that starts or ends daylight saving time isn't 24 hours long
        return Math.round((toDay - fromDay) / (1000 * 60 * 60 * 24))
    }

    function formatDateShort(date) {
        var monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return monthNames[date.getMonth()] + " " + date.getDate()
    }
}
