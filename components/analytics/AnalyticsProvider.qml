import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  visible: false

  property bool ready: false
  property bool loading: false
  property var payload: null

  readonly property var summary: payload ? payload.summary : null
  readonly property var period: payload ? payload.period : null
  readonly property var byAgent: payload ? payload.byAgent : null
  readonly property var byModel: payload ? (payload.byModel || []) : []
  readonly property var daily: payload ? (payload.daily || []) : []
  readonly property var heatmap: payload ? (payload.heatmap || []) : []

  property int selectedDayIndex: -1
  readonly property var selectedDay: {
    if (!daily || daily.length === 0) return null
    if (selectedDayIndex >= 0 && selectedDayIndex < daily.length) {
      return daily[selectedDayIndex]
    }
    // Default to the most recent day (last in array)
    return daily[daily.length - 1]
  }

  property int days: 30
  property string viewMode: "30" // "30" | "60" | "90" | "custom"
  property string customStart: ""
  property string customEnd: ""

  readonly property string scriptPath: pathFromUrl(Qt.resolvedUrl("../../scripts/monthly_analytics.py"))

  function pathFromUrl(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0)
      return decodeURIComponent(value.substring(7))
    return value
  }

  function setDays(n) {
    viewMode = String(n)
    days = n
    selectedDayIndex = -1
    refresh(false)
  }

  function setCustomRange(start, end) {
    viewMode = "custom"
    customStart = start
    customEnd = end
    selectedDayIndex = -1
    refresh(false)
  }

  function refresh(force) {
    if (loading) return
    loading = true
    var args = ["python3", scriptPath]
    if (viewMode === "custom" && customStart) {
      args.push("--start", customStart)
      if (customEnd) {
        args.push("--end", customEnd)
      }
    } else {
      args.push("--days", String(days || 30))
    }
    if (force === true) {
      args.push("--force")
    }
    console.log("agent-hub/analytics starting refresh with args:", args.join(" "))
    proc.command = args
    proc.running = true
  }

  function selectDayByDate(dateStr) {
    if (!daily) return
    for (var i = 0; i < daily.length; i++) {
      if (daily[i].date === dateStr) {
        selectedDayIndex = i
        return
      }
    }
  }

  function formatNumber(n) {
    if (n === undefined || n === null) return "0"
    var num = Number(n)
    if (num >= 1e9) return (num / 1e9).toFixed(2) + "B"
    if (num >= 1e6) return (num / 1e6).toFixed(1) + "M"
    if (num >= 1e3) return (num / 1e3).toFixed(1) + "K"
    return String(num)
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

  Process {
    id: proc
    running: false
    command: []

    stdout: StdioCollector {
      id: stdoutCollector
      waitForEnd: true
      onStreamFinished: {
        root.loading = false
        var out = stdoutCollector.text
        console.log("agent-hub/analytics stdout received length:", out ? out.length : 0)
        if (!out || out.trim() === "") return
        try {
          var parsed = JSON.parse(out)
          if (parsed && parsed.schemaVersion === 1) {
            root.payload = parsed
            root.ready = true
            console.log("agent-hub/analytics parsed successfully! Daily items:", parsed.daily ? parsed.daily.length : 0)
            if (root.selectedDayIndex === -1 && parsed.daily && parsed.daily.length > 0) {
              root.selectedDayIndex = parsed.daily.length - 1
            }
          }
        } catch (e) {
          console.warn("agent-hub/analytics JSON parse error:", e)
        }
      }
    }

    stderr: StdioCollector {
      id: stderrCollector
      waitForEnd: true
      onStreamFinished: {
        var err = stderrCollector.text
        if (err && err.trim() !== "") {
          console.warn("agent-hub/analytics stderr:", err.trim())
        }
      }
    }

    onExited: function(exitCode, exitStatus) {
      root.loading = false
      if (exitCode !== 0) {
        console.warn("agent-hub/analytics process exited with code:", exitCode)
      }
    }
  }

  Component.onCompleted: {
    refresh(false)
  }
}
