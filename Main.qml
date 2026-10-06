import QtQuick
import Quickshell
import "providers"

Item {
    id: root
    visible: false

    property var settings: ({})

    HubProvider {
        id: hubProvider
        enabled: true
        settings: root.settings
    }

    property var provider: hubProvider
    property bool refreshing: hubProvider ? hubProvider.refreshing : false
    property int refreshIntervalSec: Math.max(10, Number(root.setting("refreshIntervalSec", 60)))

    Timer {
        id: autoRefreshTimer
        interval: (hubProvider && hubProvider.hasActiveSession) ? 10000 : (root.refreshIntervalSec * 1000)
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshAll()
    }

    Connections {
        target: hubProvider
        function onHasActiveSessionChanged() {
            autoRefreshTimer.restart()
        }
    }

    function setting(name, fallback) {
        var value = settings ? settings[name] : undefined
        return value === undefined || value === null ? fallback : value
    }

    function refreshAll(force) {
        hubProvider.refresh(force === true)
    }

    function formatNumber(n) {
        if (n === undefined || n === null) return "0"
        if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
        if (n >= 1e3) return (n / 1e3).toFixed(1) + "K"
        return String(n)
    }

    function formatCost(val) {
        if (val === undefined || val === null || isNaN(val)) return "$0.00"
        var n = Number(val)
        if (n <= 0) return "$0.00"
        if (n < 0.01) return "<$0.01"
        if (n >= 1000) return "$" + (n / 1000).toFixed(1) + "k"
        return "$" + n.toFixed(2)
    }

    function formatDateShort(dateStr) {
        if (!dateStr) return ""
        var parts = dateStr.split("-")
        if (parts.length === 3) {
            return parts[1] + "/" + parts[2]
        }
        return dateStr
    }

    function formatRelativeTime(timestamp) {
        if (!timestamp) return ""
        try {
            var ms = typeof timestamp === "number" ? timestamp : Date.parse(timestamp)
            if (isNaN(ms)) return ""
            var diff = Math.floor((Date.now() - ms) / 1000)
            if (diff < 60) return "just now"
            if (diff < 3600) return Math.floor(diff / 60) + "m ago"
            if (diff < 86400) return Math.floor(diff / 3600) + "h ago"
            return Math.floor(diff / 86400) + "d ago"
        } catch (e) {
            return ""
        }
    }
}
