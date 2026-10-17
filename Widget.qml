import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "boeycorp.agent-hub"

  property bool popupOpen: false
  property bool analyticsOpen: false
  property bool settingsMode: false
  property string currentTab: "overview" // "overview" | "claude" | "antigravity" | "codex" | "spend"
  property var draftSettings: ({})
  property string settingsStatusText: ""
  property bool refreshFlash: false
  property double nowMs: Date.now()
  onPopupOpenChanged: {
    if (popupOpen) {
      root.nowMs = Date.now()
    }
  }

  onAnalyticsOpenChanged: {
    if (analyticsOpen) {
      root.close()
    }
  }

  function openAnalytics() {
    root.close()
    analyticsOpen = true
  }

  function closeAnalytics() {
    analyticsOpen = false
  }

  function toggleAnalytics() {
    if (!analyticsOpen) {
      root.close()
    }
    analyticsOpen = !analyticsOpen
  }

  readonly property color foreground: (bar && bar.barForeground) ? bar.barForeground : ((bar && bar.foreground) ? bar.foreground : (Color.foreground || "#D8DEE9"))
  readonly property color background: (Color.popups && Color.popups.background) ? Color.popups.background : "#1E1E2E"
  readonly property color border: (Color.popups && Color.popups.border) ? Color.popups.border : "#313244"
  readonly property color urgent: (bar && bar.urgent) ? bar.urgent : (Color.urgent || "#F38BA8")
  readonly property color accent: (bar && bar.accent) ? bar.accent : (Color.accent || "#89B4FA")

  readonly property bool isLightTheme: {
    var bg = (bar && bar.background) ? bar.background : (Color.background || "#1E1E2E")
    var bgLum = (bg.r * 0.299 + bg.g * 0.587 + bg.b * 0.114)
    var fgLum = (foreground.r * 0.299 + foreground.g * 0.587 + foreground.b * 0.114)
    return bgLum > 0.5 || fgLum < 0.5
  }

  readonly property color dim: isLightTheme
    ? Qt.rgba(foreground.r * 0.58 + background.r * 0.42,
              foreground.g * 0.58 + background.g * 0.42,
              foreground.b * 0.58 + background.b * 0.42, 1.0)
    : Qt.darker(foreground, 1.45)
  readonly property color card: Qt.rgba(foreground.r, foreground.g, foreground.b, isLightTheme ? 0.04 : 0.055)
  readonly property color cardHover: Qt.rgba(foreground.r, foreground.g, foreground.b, isLightTheme ? 0.08 : 0.085)
  readonly property color outline: Qt.rgba(foreground.r, foreground.g, foreground.b, isLightTheme ? 0.14 : 0.18)
  readonly property color track: Qt.rgba(foreground.r, foreground.g, foreground.b, isLightTheme ? 0.12 : 0.24)
  readonly property string fontFamily: bar ? bar.fontFamily : "JetBrainsMono Nerd Font"

  readonly property var provider: usageMain.provider
  readonly property bool hasActiveSession: provider ? provider.hasActiveSession : false
  readonly property string activeStatus: provider ? provider.activeStatus : "Idle"
  readonly property bool isWorking: provider && provider.activeStatus === "Working"
  readonly property bool isWaiting: provider && (provider.activeStatus === "Waiting" || (provider.hasActiveSession && !isWorking))

  function close() {
    popupOpen = false
    settingsMode = false
  }

  function triggerPress(button) {
    if (button === Qt.RightButton) {
      openSettings()
      return
    }
    if (button === Qt.MiddleButton) {
      triggerRefresh(true)
      return
    }

    if (popupOpen) {
      popupOpen = false
    } else {
      popupOpen = true
      triggerRefresh(false)
    }
  }

  function triggerRefresh(force) {
    refreshFlash = true
    refreshFlashTimer.restart()
    usageMain.refreshAll(force === true)
  }

  // Split a command string into argv with POSIX-shell-like quoting rules.
  // No shell runs: no expansion, no globbing, no substitution.
  // Returns null if the quoting is malformed (open quote or trailing backslash).
  function splitCommandLine(text) {
    var out = []
    var cur = ""
    var hasToken = false
    var quote = ""
    var s = String(text || "")
    for (var i = 0; i < s.length; i++) {
      var c = s.charAt(i)
      if (quote === "'") {
        if (c === "'") quote = ""
        else cur += c
      } else if (quote === "\"") {
        if (c === "\"") {
          quote = ""
        } else if (c === "\\" && i + 1 < s.length && "\"\\$`".indexOf(s.charAt(i + 1)) !== -1) {
          cur += s.charAt(++i)
        } else {
          cur += c
        }
      } else if (c === "'" || c === "\"") {
        quote = c
        hasToken = true
      } else if (c === "\\") {
        if (i + 1 >= s.length) return null
        cur += s.charAt(++i)
        hasToken = true
      } else if (/\s/.test(c)) {
        if (hasToken || cur.length > 0) {
          out.push(cur)
          cur = ""
          hasToken = false
        }
      } else {
        cur += c
        hasToken = true
      }
    }
    if (quote !== "") return null
    if (hasToken || cur.length > 0) out.push(cur)
    return out
  }

  function getTerminalArgs(cmdArgs, workspacePath) {
    var termSetting = (root.settings && root.settings.terminalCommand) ? String(root.settings.terminalCommand).trim() : ""
    var ws = workspacePath || ""
    if (ws.indexOf("file://") === 0) ws = decodeURIComponent(ws.substring(7))

    if (!termSetting) {
      var args = ["xdg-terminal-exec"]
      if (ws) args.push("--dir=" + ws)
      args.push("--")
      return args.concat(cmdArgs)
    }

    var parts = splitCommandLine(termSetting)
    if (parts === null) console.warn("terminalCommand has malformed quoting; using xdg-terminal-exec")
    if (parts === null || parts.length === 0) {
      var args = ["xdg-terminal-exec"]
      if (ws) args.push("--dir=" + ws)
      args.push("--")
      return args.concat(cmdArgs)
    }

    var bin = parts[0].split("/").pop()
    if (bin === "xdg-terminal-exec") {
      if (ws) parts.push("--dir=" + ws)
      parts.push("--")
      return parts.concat(cmdArgs)
    } else if (bin === "foot") {
      if (ws) parts.push("-D", ws)
      return parts.concat(cmdArgs)
    } else if (bin === "kitty") {
      if (ws) parts.push("-d", ws)
      return parts.concat(cmdArgs)
    } else if (bin === "ghostty") {
      if (ws) parts.push("--working-directory=" + ws)
      if (parts.indexOf("-e") === -1) parts.push("-e")
      return parts.concat(cmdArgs)
    } else if (bin === "alacritty") {
      if (ws) parts.push("--working-directory", ws)
      if (parts.indexOf("-e") === -1) parts.push("-e")
      return parts.concat(cmdArgs)
    } else {
      if (parts.indexOf("-e") !== -1 || parts.indexOf("--") !== -1) {
        return parts.concat(cmdArgs)
      }
      return parts.concat(["-e"]).concat(cmdArgs)
    }
  }

  function pathFromUrl(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0)
      return decodeURIComponent(value.substring(7))
    return value
  }

  readonly property string focusScriptPath: pathFromUrl(Qt.resolvedUrl("scripts/hub_focus_or_resume.py"))

  function resumeSession(agentId, conversationId, workspacePath, title, pid) {
    if (!conversationId) return
    var innerCmd = (agentId === "antigravity")
      ? ["agy", "--conversation", conversationId]
      : (agentId === "codex")
        ? ["codex", "resume", conversationId]
        : ["claude", "--resume", conversationId]

    var termArgs = getTerminalArgs(innerCmd, workspacePath)
    var cmd = ["python3", root.focusScriptPath, "--cid", conversationId]
    if (title) cmd = cmd.concat(["--title", title])
    if (pid) cmd = cmd.concat(["--pid", String(pid)])
    cmd = cmd.concat(["--"]).concat(termArgs)

    try {
      Quickshell.execDetached(cmd)
    } catch (e) {
      console.warn("resumeSession focus fallback", e)
      try {
        Quickshell.execDetached(["uwsm-app", "--"].concat(termArgs))
      } catch (e2) {
        Quickshell.execDetached(termArgs)
      }
    }
    root.close()
  }

  function newSession(agentId) {
    var chosenAgent = agentId || (currentTab === "antigravity" ? "antigravity" : (currentTab === "codex" ? "codex" : "claude"))
    var cmd = (chosenAgent === "antigravity") ? ["agy"] : (chosenAgent === "codex" ? ["codex"] : ["claude"])
    var args = getTerminalArgs(cmd, "")
    try {
      Quickshell.execDetached(["uwsm-app", "--"].concat(args))
    } catch (e) {
      Quickshell.execDetached(args)
    }
    root.close()
  }

  function killSession(agentId, conversationId) {
    if (!conversationId) return
    var scannerPath = root.provider ? root.provider.scannerScriptPath : ""
    if (scannerPath) {
      try {
        var target = (agentId || "claude") + ":" + conversationId
        Quickshell.execDetached(["python3", scannerPath, "--kill", target])
        root.triggerRefresh(false)
        killRefreshTimer.restart()
      } catch (e) {
        console.warn("agent-hub/kill", e)
      }
    }
  }

  function formatExactResetTime(resetsAt) {
    if (!resetsAt) return ""
    try {
      var d = new Date(resetsAt)
      if (isNaN(d.getTime())) return ""
      return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
    } catch (e) { return "" }
  }

  function formatCountdown(resetsAt) {
    if (!resetsAt) return ""
    var ms = new Date(resetsAt).getTime()
    if (!isFinite(ms)) return ""
    var diff = ms - root.nowMs
    if (diff <= 0) return "Resets now"
    var minutes = Math.floor(diff / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return "Resets in " + days + "d " + (hours % 24) + "h"
    if (hours > 0) return "Resets in " + hours + "h " + (minutes % 60) + "m"
    return "Resets in " + Math.max(1, minutes) + "m"
  }

  function formatResetText(resetsAt) {
    if (!resetsAt) return ""
    var cd = root.formatCountdown(resetsAt)
    var exact = root.formatExactResetTime(resetsAt)
    if (cd && exact) return cd + " - " + exact
    if (cd) return cd
    if (exact) return "Resets " + exact
    return ""
  }

  function alpha(c, a) {
    try {
      var col = Qt.color(c)
      return Qt.rgba(col.r, col.g, col.b, a)
    } catch (e) {
      return c
    }
  }

  function agentColor(agentId) {
    if (agentId === "antigravity") return isLightTheme ? "#0284C7" : "#38BDF8"
    if (agentId === "codex") return isLightTheme ? "#059669" : "#10A37F"
    return isLightTheme ? "#C2410C" : "#D97757"
  }

  function adaptColorForTheme(c) {
    if (!c) return root.accent
    if (!root.isLightTheme) return c
    var str = String(c).toUpperCase()
    if (str === "#38BDF8") return "#0284C7"
    if (str === "#10A37F" || str === "#10B981") return "#059669"
    if (str === "#D97757" || str === "#CC785C") return "#C2410C"
    return c
  }

  function cloneObject(value, fallback) {
    if (value === undefined || value === null) return fallback
    try { return JSON.parse(JSON.stringify(value)) }
    catch (e) { return fallback }
  }

  function defaultSettings() {
    return {
      refreshIntervalSec: 60,
      badgeMode: "active",
      showBadge: true,
      enableQuotaAlerts: true,
      quotaWarnThreshold: 25,
      quotaCritThreshold: 10,
      notifyOnReplenish: true,
      limitDisplay: "left",
      enableMultiDot: true,
      multiDotMode: "active",
      enableQuotaChips: false,
      chipWindow: "tightest",
      chipSecondLimit: false,
      chipShowReset: false,
      chipHideUsedUp: false,
      chipMax: 3,
      chipProviderColors: true,
      terminalCommand: "",
      recentSessionsLimit: 6,
      defaultTab: "overview",
      enableClaude: true,
      enableAntigravity: true,
      enableCodex: true
    }
  }

  function normalizedSettings(source) {
    var res = defaultSettings()
    if (source) {
      for (var k in source) {
        if (source[k] !== undefined && source[k] !== null) {
          res[k] = source[k]
        }
      }
    }
    return res
  }

  function showUsage() {
    settingsMode = false
    popupOpen = true
    if (flick) flick.contentY = 0
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function openSettings() {
    draftSettings = normalizedSettings(root.settings)
    settingsStatusText = ""
    settingsMode = true
    popupOpen = true
    if (root.provider) root.provider.checkHooks()
    if (flick) flick.contentY = 0
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function saveSettings() {
    persistSettings(draftSettings)
    usageMain.refreshAll(true)
  }

  // Settings that change what the scanner does (not just how it is drawn).
  readonly property var scannerSettingKeys: [
    "enableClaude", "enableAntigravity", "enableCodex",
    "enableQuotaAlerts", "quotaWarnThreshold", "quotaCritThreshold", "notifyOnReplenish"
  ]

  function setting(name, fallback) {
    var value = root.settings ? root.settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }


  // ---- Limits: used/left display, thresholds, bar chips, sign-in -------------
  readonly property string limitDisplay: (root.settings && root.settings.limitDisplay === "used") ? "used" : "left"
  readonly property real warnPct: Number(root.setting("quotaWarnThreshold", 25))
  readonly property real critPct: Math.min(Number(root.setting("quotaCritThreshold", 10)), warnPct)
  property bool awaitingSignIn: false

  function leftPct(b) {
    if (!b) return 100
    if (b.remainingPercent !== undefined && b.remainingPercent !== null) return Number(b.remainingPercent)
    if (b.remainingFraction !== undefined && b.remainingFraction !== null) return Math.round(Number(b.remainingFraction) * 100)
    return 100
  }

  function shownPct(b) {
    var l = leftPct(b)
    return root.limitDisplay === "used" ? 100 - l : l
  }

  function shownSuffix() {
    return root.limitDisplay === "used" ? "% used" : "% left"
  }

  // Thresholds are always percent *left*, whichever way limits are displayed.
  function severityForLeft(l) {
    return l <= root.critPct ? "critical" : (l <= root.warnPct ? "warning" : "ok")
  }

  // Alert color comes from the theme; there is no hard-coded red/amber.
  function severityColor(sev, base) {
    return sev === "ok" ? base : root.urgent
  }

  function paceColor(b) {
    var sev = b ? b.paceSeverity : "ok"
    if (sev === "critical") return root.urgent
    if (sev === "warning") return root.alpha(root.urgent, 0.75)
    return root.dim
  }

  function agentData(agentId) {
    if (!provider) return null
    return agentId === "claude" ? provider.claudeData
         : (agentId === "antigravity" ? provider.antigravityData : provider.codexData)
  }

  function agentBuckets(agentId) {
    var d = root.agentData(agentId)
    var out = []
    var groups = (d && d.quotaGroups) ? d.quotaGroups : []
    for (var i = 0; i < groups.length; i++) {
      var bs = groups[i].buckets || []
      for (var j = 0; j < bs.length; j++) out.push(bs[j])
    }
    return out
  }

  function agentQuotaStatus(agentId) {
    var st = (provider && provider.quotaStatus) ? provider.quotaStatus[agentId] : null
    return st || { state: "ok", reason: "", message: "", command: [], commandText: "", stale: false }
  }

  readonly property bool needsSignIn: {
    var ids = ["claude", "antigravity", "codex"]
    for (var i = 0; i < ids.length; i++) {
      if (!root.setting("enable" + (ids[i] === "claude" ? "Claude" : (ids[i] === "antigravity" ? "Antigravity" : "Codex")), true)) continue
      var st = root.agentQuotaStatus(ids[i]).state
      if (st === "signin" || st === "expired") return true
    }
    return false
  }

  onNeedsSignInChanged: if (!needsSignIn) awaitingSignIn = false

  function signIn(agentId) {
    var st = root.agentQuotaStatus(agentId)
    if (!st.command || st.command.length === 0) return
    var args = root.getTerminalArgs(st.command, "")
    try {
      Quickshell.execDetached(["uwsm-app", "--"].concat(args))
    } catch (e) {
      Quickshell.execDetached(args)
    }
    root.awaitingSignIn = true
  }

  // While a sign-in is outstanding, keep re-checking so the panel updates the moment it lands.
  Timer {
    interval: 10000
    repeat: true
    running: root.needsSignIn && (root.popupOpen || root.awaitingSignIn)
    onTriggered: usageMain.refreshAll(true)
  }

  function tagForBucket(b) {
    var k = b ? b.windowKind : ""
    return (k === "5h" || k === "7d" || k === "30d") ? k : ""
  }

  function pickBucket(buckets, mode, excludeId) {
    var want = mode === "5h" ? "5h" : (mode === "7d" ? "7d" : (mode === "monthly" ? "30d" : ""))
    var best = null
    for (var i = 0; i < buckets.length; i++) {
      var b = buckets[i]
      if (excludeId !== null && b.id === excludeId) continue
      if (want && b.windowKind !== want) continue
      if (!best || root.leftPct(b) < root.leftPct(best)) best = b
    }
    if (!best && want) return root.pickBucket(buckets, "tightest", excludeId)
    return best
  }

  function chipResetText(resetsAt) {
    if (!resetsAt) return ""
    var ms = new Date(resetsAt).getTime()
    if (!isFinite(ms)) return ""
    var d = new Date(ms)
    if (ms - Date.now() <= 24 * 3600 * 1000) return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
    return d.toLocaleDateString([], { month: "short", day: "numeric" })
  }

  // Every line is tagged with the period of the limit behind it (e.g. "7d 91%").
  function chipLine(b) {
    var tag = root.tagForBucket(b)
    var text = (tag ? tag + " " : "") + root.shownPct(b) + "%"
    if (root.setting("chipShowReset", false)) {
      var r = root.chipResetText(b.resetTime || b.resetsAt)
      if (r) text += " · " + r
    }
    var left = root.leftPct(b)
    return { text: text, left: left, severity: root.severityForLeft(left) }
  }

  function worseSeverity(a, b) {
    var rank = { ok: 0, warning: 1, critical: 2 }
    return rank[b] > rank[a] ? b : a
  }

  function hasUsedUpLongLimit(buckets) {
    for (var i = 0; i < buckets.length; i++) {
      var k = buckets[i].windowKind
      if ((k === "7d" || k === "30d") && root.leftPct(buckets[i]) <= 0) return true
    }
    return false
  }

  // Builds the quota chips for the bar: { chips: [...], overflow: [...] }
  function chipModels() {
    var result = { chips: [], overflow: [] }
    if (!provider) return result
    var defs = [
      { id: "claude", name: "Claude Code", enabled: root.setting("enableClaude", true) },
      { id: "antigravity", name: "Google Antigravity", enabled: root.setting("enableAntigravity", true) },
      { id: "codex", name: "OpenAI Codex", enabled: root.setting("enableCodex", true) }
    ]
    var mode = root.setting("chipWindow", "tightest")
    var all = []
    for (var i = 0; i < defs.length; i++) {
      var def = defs[i]
      if (!def.enabled) continue
      var st = root.agentQuotaStatus(def.id)
      var buckets = root.agentBuckets(def.id)
      var first = root.pickBucket(buckets, mode, null)
      var model = {
        id: def.id, name: def.name, color: root.agentColor(def.id),
        lines: [], severity: "ok", minLeft: 100, usedUp: false, reason: "", status: st.state
      }
      if (!first) {
        if (st.state === "ok") continue
        model.reason = st.reason
        model.minLeft = 0
        model.severity = (st.state === "signin" || st.state === "expired") ? "critical" : "warning"
        all.push(model)
        continue
      }
      var l1 = root.chipLine(first)
      model.lines.push(l1)
      model.severity = l1.severity
      model.minLeft = l1.left
      if (root.setting("chipSecondLimit", false)) {
        var second = root.pickBucket(buckets, "tightest", first.id)
        if (second) {
          var l2 = root.chipLine(second)
          model.lines.push(l2)
          model.severity = root.worseSeverity(model.severity, l2.severity)
          model.minLeft = Math.min(model.minLeft, l2.left)
        }
      }
      model.usedUp = root.hasUsedUpLongLimit(buckets)
      if (st.state !== "ok") model.reason = st.reason
      all.push(model)
    }

    if (root.setting("chipHideUsedUp", false)) {
      all = all.filter(function(m) { return !m.usedUp })
    }

    var cap = Math.max(1, Number(root.setting("chipMax", 3)))
    if (all.length > cap) {
      // Keep the providers closest to a limit, in their usual order; fold the rest into "+N".
      var ranked = all.slice().sort(function(a, b) { return a.minLeft - b.minLeft })
      var keepIds = {}
      for (var k = 0; k < cap; k++) keepIds[ranked[k].id] = true
      for (var m = 0; m < all.length; m++) {
        if (keepIds[all[m].id]) result.chips.push(all[m])
        else result.overflow.push(all[m])
      }
    } else {
      result.chips = all
    }
    return result
  }

  function minLeftPct() {
    var groups = provider ? (provider.quotaGroups || []) : []
    var min = -1
    for (var i = 0; i < groups.length; i++) {
      var buckets = groups[i].buckets || []
      for (var j = 0; j < buckets.length; j++) {
        var l = root.leftPct(buckets[j])
        if (min < 0 || l < min) min = l
      }
    }
    return min
  }

  function quotaTooltipLines() {
    var lines = []
    var defs = [["claude", "Claude"], ["antigravity", "Antigravity"], ["codex", "Codex"]]
    for (var i = 0; i < defs.length; i++) {
      if (!root.setting("enable" + (defs[i][0] === "claude" ? "Claude" : (defs[i][0] === "antigravity" ? "Antigravity" : "Codex")), true)) continue
      var st = root.agentQuotaStatus(defs[i][0])
      var b = root.pickBucket(root.agentBuckets(defs[i][0]), "tightest", null)
      if (b) {
        var line = defs[i][1] + ": " + root.chipLine(b).text.replace(/ · .*/, "") + root.shownSuffix().replace("%", "")
        if (b.paceText) line += " — " + b.paceText.replace(/ · pace .*/, "")
        lines.push(line)
      } else if (st.state !== "ok") {
        lines.push(defs[i][1] + ": " + st.reason)
      }
    }
    return lines.length > 0 ? ("\n" + lines.join("\n")) : ""
  }

  function getAgentState(agentId) {
    if (provider && provider.agentStates && provider.agentStates[agentId]) {
      return provider.agentStates[agentId]
    }
    var provData = (agentId === "claude" ? (provider ? provider.claudeData : null)
                  : (agentId === "antigravity" ? (provider ? provider.antigravityData : null)
                  : (provider ? provider.codexData : null)))
    var hasAct = Boolean(provData && provData.hasActiveSession)
    var isWork = Boolean(provData && provData.activeStatus === "Working")
    var cnt = (provider && provider.activeAgentCounts) ? (provider.activeAgentCounts[agentId] || 0) : (hasAct ? 1 : 0)
    return {
      active: hasAct,
      working: isWork,
      waiting: hasAct && !isWork,
      status: provData ? (provData.activeStatus || "Idle") : "Idle",
      count: cnt,
      color: root.agentColor(agentId),
      name: agentId === "claude" ? "Claude Code" : (agentId === "antigravity" ? "Google Antigravity" : "OpenAI Codex")
    }
  }

  function draftValue(name, fallback) {
    var value = draftSettings ? draftSettings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function setDraftOnly(name, value) {
    var next = normalizedSettings(draftSettings)
    next[name] = value
    draftSettings = next
  }

  function setDraftValue(name, value) {
    updateSetting(name, value)
  }

  function updateSetting(name, value) {
    var next = normalizedSettings(draftSettings)
    next[name] = value
    draftSettings = next
    persistSettings(next)
    settingsStatusText = "Applied"
    settingsStatusTimer.restart()
    if (scannerSettingKeys.indexOf(name) !== -1) usageMain.refreshAll(false)
  }

  function persistSettings(payload) {
    var clean = normalizedSettings(payload)
    if (typeof root.writeSettings === "function") {
      root.writeSettings(clean)
    } else if (root.settings !== undefined) {
      root.settings = clean
    }
  }

  Timer {
    id: settingsStatusTimer
    interval: 1600
    repeat: false
    onTriggered: root.settingsStatusText = ""
  }

  Main {
    id: usageMain
    settings: root.settings
  }

  Timer {
    id: refreshFlashTimer
    interval: 400
    repeat: false
    onTriggered: root.refreshFlash = false
  }

  Timer {
    id: killRefreshTimer
    interval: 800
    repeat: false
    onTriggered: root.triggerRefresh(false)
  }

  Timer {
    interval: 1000
    running: root.popupOpen
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }


  readonly property url iconSource: Qt.resolvedUrl("assets/agent-hub.svg")

  function getBadgeText() {
    if (!root.settings || root.settings.showBadge === false) return ""
    var mode = root.settings.badgeMode || "active"
    if (mode === "off") return ""
    if (!provider) return ""

    if (mode === "prompts") {
      return provider.todayPrompts > 0 ? usageMain.formatNumber(provider.todayPrompts) : ""
    } else if (mode === "tokens") {
      return provider.todayTotalTokens > 0 ? usageMain.formatNumber(provider.todayTotalTokens) : ""
    } else if (mode === "cost") {
      return provider.todayTokenCost > 0 ? usageMain.formatCost(provider.todayTokenCost) : ""
    } else if (mode === "quota") {
      // Tightest limit across every quota bucket, shown as used or left per the display setting
      var minLeft = root.minLeftPct()
      if (minLeft < 0) return ""
      return (root.limitDisplay === "used" ? (100 - minLeft) : minLeft) + "%"
    }

    // Default 'active'
    var count = provider.activeSessions ? provider.activeSessions.length : (provider.hasActiveSession ? 1 : 0)
    return count > 0 ? String(count) : ""
  }

  function tooltipText() {
    if (!provider) return "Agent Hub"
    var count = provider.activeSessions ? provider.activeSessions.length : (provider.hasActiveSession ? 1 : 0)
    var status = provider.hasActiveSession ? " (" + count + " active)" : " (Idle)"
    var tokensFmt = usageMain.formatNumber(provider.todayTotalTokens || 0)
    var refMs = (provider && provider.lastFullRefreshMs > 0) ? provider.lastFullRefreshMs : (provider ? provider.lastUpdatedMs : 0)
    var ageSec = refMs > 0 ? Math.max(0, Math.floor((root.nowMs - refMs) / 1000)) : -1
    var refText = ""
    if (ageSec >= 0) {
      if (ageSec < 10) refText = " • Refreshed just now"
      else if (ageSec < 60) refText = " • Refreshed " + ageSec + "s ago"
      else if (ageSec < 3600) refText = " • Refreshed " + Math.floor(ageSec / 60) + "m ago"
      else refText = " • Refreshed " + Math.floor(ageSec / 3600) + "h ago"
    }

    var agentLines = []
    var cSt = root.getAgentState("claude")
    var aSt = root.getAgentState("antigravity")
    var xSt = root.getAgentState("codex")
    if (cSt.active) agentLines.push("Claude: " + cSt.status + " (" + cSt.count + ")")
    if (aSt.active) agentLines.push("Antigravity: " + aSt.status + " (" + aSt.count + ")")
    if (xSt.active) agentLines.push("Codex: " + xSt.status + " (" + xSt.count + ")")
    var agentSummary = agentLines.length > 0 ? ("\n" + agentLines.join(" • ")) : ""

    return "Agent Hub" + status + "\n" +
           (provider.todayPrompts || 0) + " prompts today • " + tokensFmt + " tokens" + refText +
           agentSummary +
           root.quotaTooltipLines() + "\n" +
           "Claude Code, Google Antigravity & OpenAI Codex"
  }

  width: button.implicitWidth
  height: button.implicitHeight
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: "boeycorp.agent-hub"
    function open(): string { root.showUsage(); root.popupOpen = true; return "ok" }
    function close(): string { root.close(); return "ok" }
    function toggle(): string {
      if (root.popupOpen) root.close()
      else { root.showUsage(); root.popupOpen = true }
      return "ok"
    }
    function refresh(): string { root.triggerRefresh(true); return "ok" }
    function settings(): string { root.openSettings(); return "ok" }
    function openSettings(): string { root.openSettings(); return "ok" }
    function openAnalytics(): string { root.openAnalytics(); return "ok" }
    function closeAnalytics(): string { root.closeAnalytics(); return "ok" }
    function toggleAnalytics(): string { root.toggleAnalytics(); return "ok" }
    function setAnalyticsDays(days: int): string {
      if (analyticsWindowLoader.item && analyticsWindowLoader.item.provider) {
        analyticsWindowLoader.item.provider.setDays(days)
        return "ok"
      }
      return "not loaded"
    }
    function toggleAnalyticsDateRange(): string {
      if (analyticsWindowLoader.item) {
        analyticsWindowLoader.item.showDateRangePicker = !analyticsWindowLoader.item.showDateRangePicker
        return "ok"
      }
      return "not loaded"
    }
    function setAnalyticsCustomRange(start: string, end: string): string {
      if (analyticsWindowLoader.item && analyticsWindowLoader.item.provider) {
        analyticsWindowLoader.item.provider.setCustomRange(start, end)
        return "ok"
      }
      return "not loaded"
    }
    function setBadgeMode(mode: string): string { root.updateSetting("badgeMode", mode); return "ok" }
    function setMultiDot(enabled: bool): string { root.updateSetting("enableMultiDot", enabled); return "ok" }
    function setLimitDisplay(mode: string): string {
      if (mode !== "left" && mode !== "used") return "invalid mode"
      root.updateSetting("limitDisplay", mode)
      return "ok"
    }
    function setQuotaChips(enabled: bool): string { root.updateSetting("enableQuotaChips", enabled); return "ok" }
    function setTab(tabName: string): string {
      if (tabName === "overview" || tabName === "claude" || tabName === "antigravity" || tabName === "codex" || tabName === "spend") {
        root.showUsage()
        root.currentTab = tabName
        return "ok"
      }
      return "invalid tab"
    }
    function scroll(dy: int): string {
      flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + dy))
      return "ok"
    }
  }

  component UsageChip: Item {
    id: chip

    readonly property bool tooltipHovered: mouseArea.containsMouse
    readonly property string badgeTextValue: root.getBadgeText()
    readonly property bool hasBadge: badgeTextValue.length > 0
    readonly property bool multiDotEnabled: root.setting("enableMultiDot", true)
    readonly property bool chipsEnabled: root.setting("enableQuotaChips", false)
    readonly property var chipData: chipsEnabled ? root.chipModels() : ({ chips: [], overflow: [] })
    readonly property bool chipColors: root.setting("chipProviderColors", true)
    readonly property string multiDotMode: root.setting("multiDotMode", "active") // "active" | "all"

    readonly property var agentList: [
      { id: "claude", name: "Claude Code", color: root.agentColor("claude"), enabled: root.setting("enableClaude", true) },
      { id: "antigravity", name: "Google Antigravity", color: root.agentColor("antigravity"), enabled: root.setting("enableAntigravity", true) },
      { id: "codex", name: "OpenAI Codex", color: root.agentColor("codex"), enabled: root.setting("enableCodex", true) }
    ]

    readonly property bool hasDots: {
      if (!multiDotEnabled) return false
      for (var i = 0; i < agentList.length; i++) {
        var ag = agentList[i]
        if (!ag.enabled) continue
        if (multiDotMode === "all") return true
        var st = root.getAgentState(ag.id)
        if (st && st.active) return true
      }
      return false
    }

    width: Math.max(root.barSize, chipLayout.implicitWidth + 10)
    height: root.barSize

    RowLayout {
      id: chipLayout
      anchors.centerIn: parent
      spacing: 4

      Item {
        id: iconBox
        width: 14
        height: 14

        Image {
          id: barIconImage
          source: root.iconSource
          width: 13
          height: 13
          sourceSize.width: Math.round(13 * (Screen.devicePixelRatio || 1))
          sourceSize.height: Math.round(13 * (Screen.devicePixelRatio || 1))
          fillMode: Image.PreserveAspectFit
          anchors.centerIn: parent
          visible: false
          layer.enabled: true
        }

        MultiEffect {
          anchors.fill: barIconImage
          source: barIconImage
          colorization: 1.0
          colorizationColor: root.foreground
        }

        // Active pulse glow (legacy fallback when multi-dot is disabled)
        Rectangle {
          width: 4
          height: 4
          radius: 2
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: -1
          color: root.isWorking ? (root.isLightTheme ? "#059669" : "#10B981") : (root.isWaiting ? (root.isLightTheme ? "#0284C7" : "#38BDF8") : "transparent")
          visible: !chip.multiDotEnabled && root.hasActiveSession

          SequentialAnimation on opacity {
            running: !chip.multiDotEnabled && root.isWorking
            loops: Animation.Infinite
            NumberAnimation { from: 0.3; to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 1.0; to: 0.3; duration: 600; easing.type: Easing.InOutQuad }
          }
        }
      }

      // Per-Agent Multi-Dot Indicator Cluster
      RowLayout {
        id: multiDotRow
        visible: chip.multiDotEnabled && chip.hasDots
        spacing: 2
        Layout.alignment: Qt.AlignVCenter

        Repeater {
          model: chip.agentList
          delegate: Item {
            id: dotDelegate
            required property var modelData
            readonly property var st: root.getAgentState(modelData.id)
            readonly property bool dotVisible: modelData.enabled && (chip.multiDotMode === "all" || (st && st.active))

            visible: dotVisible
            implicitWidth: dotVisible ? 8 : 0
            implicitHeight: 14
            width: implicitWidth
            height: implicitHeight
            Layout.preferredWidth: implicitWidth
            Layout.preferredHeight: implicitHeight
            Layout.alignment: Qt.AlignVCenter

            // Pulsing halo aura behind actively working agent dot
            Rectangle {
              anchors.centerIn: parent
              width: 8
              height: 8
              radius: 4
              color: modelData.color
              opacity: (st && st.working) ? 0.35 : 0.0
              visible: Boolean(st && st.working)

              SequentialAnimation on opacity {
                running: Boolean(st && st.working)
                loops: Animation.Infinite
                NumberAnimation { from: 0.15; to: 0.45; duration: 600; easing.type: Easing.InOutQuad }
                NumberAnimation { from: 0.45; to: 0.15; duration: 600; easing.type: Easing.InOutQuad }
              }
            }

            // Core status dot
            Rectangle {
              id: dotCore
              anchors.centerIn: parent
              width: 5
              height: 5
              radius: 2.5
              color: (st && st.active) ? modelData.color : root.track
              opacity: (st && st.active) ? 1.0 : 0.35

              SequentialAnimation on opacity {
                running: Boolean(st && st.working)
                loops: Animation.Infinite
                NumberAnimation { from: 0.4; to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
                NumberAnimation { from: 1.0; to: 0.4; duration: 600; easing.type: Easing.InOutQuad }
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: {
                if (root.bar) {
                  var tip = modelData.name + ": " + (st ? (st.working ? "Working" : (st.waiting ? "Waiting (" + st.count + " active)" : "Idle")) : "Idle")
                  root.bar.showTooltip(dotDelegate, tip)
                }
              }
              onExited: {
                if (root.bar) root.bar.hideTooltip(dotDelegate)
              }
              onClicked: function(mouse) {
                mouse.accepted = true
                root.showUsage()
                root.currentTab = modelData.id
                root.popupOpen = true
              }
            }
          }
        }
      }

      Text {
        id: badgeText
        visible: chip.hasBadge
        textFormat: Text.PlainText
        text: chip.badgeTextValue
        color: {
          var mode = root.settings ? root.settings.badgeMode : "active"
          if (mode === "quota") {
            var minLeft = root.minLeftPct()
            if (minLeft < 0) return root.accent
            return root.severityColor(root.severityForLeft(minLeft), root.accent)
          }
          if (mode === "cost") return root.accent
          return root.isWorking ? (root.isLightTheme ? "#059669" : "#10B981") : (root.isWaiting ? (root.isLightTheme ? "#0284C7" : "#38BDF8") : root.dim)
        }
        font.family: root.fontFamily
        font.pixelSize: 9
        font.bold: true
        Layout.alignment: Qt.AlignVCenter
      }

      // Per-agent quota chips (a brand dot keeps the provider identifiable even while the
      // text is in the theme's alert color).
      Repeater {
        model: chip.chipData.chips
        delegate: Item {
          id: quotaChip
          required property var modelData
          readonly property string tipText: {
            var parts = [modelData.name]
            if (modelData.lines.length === 0) parts.push(modelData.reason)
            var b = root.pickBucket(root.agentBuckets(modelData.id), root.setting("chipWindow", "tightest"), null)
            if (b && b.paceText) parts.push(b.paceText)
            if (modelData.reason && modelData.lines.length > 0) parts.push(modelData.reason)
            return parts.join("\n")
          }
          readonly property color textColor: root.severityColor(modelData.severity, chip.chipColors ? modelData.color : root.foreground)

          implicitWidth: chipRow.implicitWidth
          implicitHeight: 14
          Layout.alignment: Qt.AlignVCenter

          RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: 3

            Rectangle {
              visible: chip.chipColors
              width: 4
              height: 4
              radius: 2
              color: modelData.color
              Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
              spacing: -1
              Layout.alignment: Qt.AlignVCenter

              Repeater {
                model: modelData.lines.length > 0 ? modelData.lines : [{ text: modelData.reason, severity: modelData.severity }]
                delegate: Text {
                  required property var modelData
                  textFormat: Text.PlainText
                  text: modelData.text
                  color: quotaChip.textColor
                  font.family: root.fontFamily
                  font.pixelSize: quotaChip.modelData.lines.length > 1 ? 8 : 9
                  font.bold: true
                }
              }
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: if (root.bar) root.bar.showTooltip(quotaChip, quotaChip.tipText)
            onExited: if (root.bar) root.bar.hideTooltip(quotaChip)
            onClicked: function(mouse) {
              mouse.accepted = true
              root.showUsage()
              root.currentTab = quotaChip.modelData.id
              root.popupOpen = true
            }
          }
        }
      }

      Text {
        id: overflowChip
        visible: chip.chipData.overflow.length > 0
        textFormat: Text.PlainText
        text: "+" + chip.chipData.overflow.length
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: 9
        font.bold: true
        Layout.alignment: Qt.AlignVCenter

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onEntered: {
            if (!root.bar) return
            var names = chip.chipData.overflow.map(function(m) { return m.name })
            root.bar.showTooltip(overflowChip, names.join(", "))
          }
          onExited: if (root.bar) root.bar.hideTooltip(overflowChip)
          onClicked: function(mouse) { mouse.accepted = true; root.showUsage(); root.currentTab = "overview"; root.popupOpen = true }
        }
      }
    }

    property var registeredBar: null

    function triggerPress(button) { root.triggerPress(button) }

    function syncClickRegistration() {
      if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(chip)
      registeredBar = root.bar
      if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(chip)
    }

    Component.onCompleted: syncClickRegistration()
    Component.onDestruction: if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(chip)

    Connections {
      target: root
      function onBarChanged() { chip.syncClickRegistration() }
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (root.bar) root.bar.showTooltip(chip, root.tooltipText())
      onExited: if (root.bar) root.bar.hideTooltip(chip)
      onClicked: function(mouse) { root.triggerPress(mouse.button) }
    }
  }

  Item {
    id: button
    anchors.fill: parent
    implicitWidth: usageChip.width
    implicitHeight: root.barSize

    UsageChip {
      id: usageChip
      anchors.centerIn: parent
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.popupOpen
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(450))
    contentHeight: {
      var headerH = (root.settingsMode ? settingsHeader.implicitHeight : statsHeader.implicitHeight) + 16
      var navH = root.settingsMode ? 0 : 36
      var needed = headerH + navH + contentColumn.implicitHeight + Style.space(24)
      return panel.fittedContentHeight(needed, Style.space(1050))
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dy !== 0) flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + dy * 56))
      }
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.triggerRefresh(true)
        else if (t === "s" || t === "S") root.settingsMode ? root.showUsage() : root.openSettings()
        else if (t === "a" || t === "A" || t === "m" || t === "M") root.toggleAnalytics()
        else if (t === "n" || t === "N") { if (!root.settingsMode) root.newSession() }
        else if (t === "q" || t === "Q") root.close()
        else if (t === "1") root.currentTab = "overview"
        else if (t === "2") root.currentTab = "claude"
        else if (t === "3") root.currentTab = "antigravity"
        else if (t === "4") root.currentTab = "codex"
        else if (t === "5") root.currentTab = "spend"
        else if (!root.settingsMode && t >= "6" && t <= "9") {
          var idx = parseInt(t) - 1
          var list = root.provider ? (root.provider.recentSessions || []) : []
          if (idx >= 0 && idx < list.length) {
            var s = list[idx]
            root.resumeSession(s.agentId, s.conversationId, s.workspace, s.preview || s.title, s.pid)
          }
        }
      }

      ColumnLayout {
        id: panelMainColumn
        anchors.fill: parent
        spacing: 8

        // Header Card
        Header {
          id: statsHeader
          visible: !root.settingsMode && !!root.provider
          Layout.fillWidth: true
          title: "Agent Hub"
          subtitle: root.provider ? root.provider.usageStatusText : "Idle"
          refreshing: usageMain.refreshing || root.refreshFlash
          onRefreshClicked: root.triggerRefresh(true)
          onSettingsClicked: root.openSettings()
          onNewSessionClicked: root.newSession()
          onAnalyticsClicked: root.openAnalytics()
        }

        // Settings Header
        Header {
          id: settingsHeader
          visible: root.settingsMode
          Layout.fillWidth: true
          title: "Agent Hub Settings"
          subtitle: root.settingsStatusText.length > 0 ? ("✓ " + root.settingsStatusText) : "Changes apply as you make them"
          refreshing: usageMain.refreshing
          showActionButtons: false
          onRefreshClicked: root.triggerRefresh(true)
          onSettingsClicked: root.showUsage()
          onNewSessionClicked: root.newSession()
        }

        // Tab Navigation Bar (Overview | Claude Code | Antigravity | Codex | Spend)
        Rectangle {
          id: tabNav
          visible: !root.settingsMode
          Layout.fillWidth: true
          Layout.preferredHeight: 28
          implicitHeight: 28
          color: root.track
          radius: 4
          border.color: root.outline
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.margins: 2
            spacing: 2

            Repeater {
              model: [
                { id: "overview", label: "Overview", icon: "assets/agent-hub.svg" },
                { id: "claude", label: "Claude Code", icon: "assets/claude.svg" },
                { id: "antigravity", label: "Antigravity", icon: "assets/antigravity.svg" },
                { id: "codex", label: "Codex", icon: "assets/codex.svg" },
                { id: "spend", label: "Spend", icon: "assets/spend.svg" }
              ]
              delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 3
                readonly property bool isSelected: root.currentTab === modelData.id
                color: isSelected ? root.accent : (tabMouse.containsMouse ? root.cardHover : "transparent")

                Behavior on color { ColorAnimation { duration: 120 } }

                RowLayout {
                  anchors.centerIn: parent
                  spacing: 4

                  Text {
                    textFormat: Text.PlainText
                    text: modelData.label
                    color: isSelected ? "#FFFFFF" : (tabMouse.containsMouse ? root.foreground : root.dim)
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.bold: isSelected
                  }
                }

                MouseArea {
                  id: tabMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.currentTab = modelData.id
                }
              }
            }
          }
        }

        // Scrollable Body
        Flickable {
          id: flick
          Layout.fillWidth: true
          Layout.fillHeight: true
          contentWidth: width
          contentHeight: contentColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          ScrollBar.vertical: ScrollBar {
            policy: flick.contentHeight > (flick.height + 2) ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
          }

          ColumnLayout {
            id: contentColumn
            width: flick.width
            spacing: 8

            // --- SETTINGS VIEW ---
            SettingsContent {
              visible: root.settingsMode
              Layout.fillWidth: true
            }

            // --- OVERVIEW TAB ---
            OverviewContent {
              visible: !root.settingsMode && root.currentTab === "overview"
              Layout.fillWidth: true
              provider: root.provider
            }

            // --- CLAUDE TAB ---
            ProviderDetailContent {
              visible: !root.settingsMode && root.currentTab === "claude"
              Layout.fillWidth: true
              agentId: "claude"
              agentName: "Claude Code"
              agentColor: root.agentColor("claude")
              dataPayload: root.provider ? root.provider.claudeData : ({})
            }

            // --- ANTIGRAVITY TAB ---
            ProviderDetailContent {
              visible: !root.settingsMode && root.currentTab === "antigravity"
              Layout.fillWidth: true
              agentId: "antigravity"
              agentName: "Antigravity"
              agentColor: root.agentColor("antigravity")
              dataPayload: root.provider ? root.provider.antigravityData : ({})
            }

            // --- CODEX TAB ---
            ProviderDetailContent {
              visible: !root.settingsMode && root.currentTab === "codex"
              Layout.fillWidth: true
              agentId: "codex"
              agentName: "Codex"
              agentColor: root.agentColor("codex")
              dataPayload: root.provider ? root.provider.codexData : ({})
            }

            // --- SPEND TAB ---
            SpendContent {
              visible: !root.settingsMode && root.currentTab === "spend"
              Layout.fillWidth: true
              provider: root.provider
            }
          }
        }
      }
    }
  }

  // --- SUB-COMPONENTS ---

  component Header: BorderSurface {
    id: hdr
    property string title: ""
    property string subtitle: ""
    property bool refreshing: false
    property bool showActionButtons: true
    signal refreshClicked()
    signal settingsClicked()
    signal newSessionClicked()
    signal analyticsClicked()

    readonly property double refMs: (root.provider && root.provider.lastFullRefreshMs > 0) ? root.provider.lastFullRefreshMs : (root.provider ? root.provider.lastUpdatedMs : 0)
    readonly property int ageSec: refMs > 0 ? Math.max(0, Math.floor((root.nowMs - refMs) / 1000)) : -1

    Layout.fillWidth: true
    color: root.card
    borderSpec: Border.flat(root.isLightTheme ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05), 1)
    padding: 8
    radius: Style.cornerRadius
    implicitHeight: headerRow.implicitHeight + contentTopInset + contentBottomInset

    RowLayout {
      id: headerRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: hdr.contentTopInset
      anchors.rightMargin: hdr.contentRightInset
      anchors.bottomMargin: hdr.contentBottomInset
      anchors.leftMargin: hdr.contentLeftInset
      spacing: 6

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 1

        Text {
          textFormat: Text.PlainText
          text: hdr.title
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: 13
          font.bold: true
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: 4

          Text {
            textFormat: Text.PlainText
            text: hdr.subtitle
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: 9
            elide: Text.ElideRight
            Layout.fillWidth: true
          }

          RowLayout {
            spacing: 3
            visible: !hdr.refreshing && hdr.ageSec >= 0

            Text {
              textFormat: Text.PlainText
              text: ""
              color: hdr.ageSec > 300 ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: 8
              opacity: 0.7
            }

            Text {
              textFormat: Text.PlainText
              text: {
                var a = hdr.ageSec
                if (a < 0) return ""
                if (a < 10) return "Refreshed just now"
                if (a < 60) return "Refreshed " + a + "s ago"
                if (a < 3600) return "Refreshed " + Math.floor(a / 60) + "m ago"
                return "Refreshed " + Math.floor(a / 3600) + "h " + Math.floor((a % 3600) / 60) + "m ago"
              }
              color: hdr.ageSec > 300 ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: 9
              opacity: 0.8
            }
          }

          RowLayout {
            spacing: 3
            visible: hdr.refreshing

            Text {
              textFormat: Text.PlainText
              text: ""
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: 8
              transformOrigin: Item.Center

              RotationAnimation on rotation {
                running: hdr.refreshing
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 800
              }
            }

            Text {
              textFormat: Text.PlainText
              text: "Refreshing…"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: 9
              opacity: 0.9
            }
          }
        }
      }

      RowLayout {
        spacing: 4

        Rectangle {
          visible: hdr.showActionButtons
          radius: 3
          color: chartMouse.containsMouse ? root.cardHover : root.track
          Layout.preferredHeight: 22
          Layout.preferredWidth: 22

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 11
          }

          MouseArea {
            id: chartMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: hdr.analyticsClicked()
          }
        }

        Rectangle {
          visible: hdr.showActionButtons
          radius: 3
          color: newMouse.containsMouse ? root.cardHover : root.track
          Layout.preferredHeight: 22
          Layout.preferredWidth: 22

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 11
          }

          MouseArea {
            id: newMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: hdr.newSessionClicked()
          }
        }

        Rectangle {
          radius: 3
          color: refMouse.containsMouse ? root.cardHover : root.track
          Layout.preferredHeight: 22
          Layout.preferredWidth: 22

          Text {
            id: refBtnIcon
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: ""
            color: hdr.refreshing ? root.accent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: 11
            transformOrigin: Item.Center

            RotationAnimation on rotation {
              running: hdr.refreshing
              loops: Animation.Infinite
              from: 0
              to: 360
              duration: 800
            }
          }

          MouseArea {
            id: refMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: hdr.refreshClicked()
          }
        }

        Rectangle {
          radius: 3
          color: setMouse.containsMouse ? root.cardHover : root.track
          Layout.preferredHeight: 22
          Layout.preferredWidth: 22

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.settingsMode ? "" : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 11
          }

          MouseArea {
            id: setMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: hdr.settingsClicked()
          }
        }
      }
    }

    // Animated progress glow during refresh
    Rectangle {
      id: refreshProgressBar
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 1
      height: 2
      color: "transparent"
      clip: true
      visible: hdr.refreshing

      Rectangle {
        id: glowPill
        anchors.verticalCenter: parent.verticalCenter
        height: 2
        width: Math.max(50, parent.width * 0.35)
        radius: 1
        color: root.accent

        NumberAnimation on x {
          running: hdr.refreshing && root.popupOpen
          loops: Animation.Infinite
          from: -glowPill.width
          to: refreshProgressBar.width
          duration: 800
          easing.type: Easing.InOutQuad
        }
      }
    }
  }

  component SectionCard: BorderSurface {
    id: section
    property string title: ""
    property string subtitle: ""
    property color titleColor: root.foreground
    property string icon: ""
    property string badgeText: ""
    property color badgeColor: root.accent
    property color badgeTextColor: badgeColor
    property Component headerAccessory: null
    default property alias content: body.data

    Layout.fillWidth: true
    Layout.minimumWidth: 0
    color: root.card
    borderSpec: Border.flat(root.isLightTheme ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05), 1)
    padding: 10
    radius: Style.cornerRadius
    implicitHeight: body.implicitHeight + contentTopInset + contentBottomInset
    clip: true

    ColumnLayout {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: section.contentTopInset
      anchors.rightMargin: section.contentRightInset
      anchors.bottomMargin: section.contentBottomInset
      anchors.leftMargin: section.contentLeftInset
      spacing: 6

      RowLayout {
        visible: section.title !== "" || section.headerAccessory !== null || section.icon !== "" || section.badgeText !== ""
        Layout.fillWidth: true
        Layout.minimumHeight: 18
        spacing: 6

        Item {
          id: sectionIconContainer
          visible: section.icon !== ""
          width: 14
          height: 14
          Layout.preferredWidth: 14
          Layout.preferredHeight: 14
          Layout.alignment: Qt.AlignVCenter

          Image {
            id: sectionIconImage
            anchors.fill: parent
            source: section.icon !== "" ? Qt.resolvedUrl(section.icon) : ""
            sourceSize.width: Math.round(14 * (Screen.devicePixelRatio || 1))
            sourceSize.height: Math.round(14 * (Screen.devicePixelRatio || 1))
            fillMode: Image.PreserveAspectFit
            visible: false
            layer.enabled: true
          }

          MultiEffect {
            anchors.fill: sectionIconImage
            source: sectionIconImage
            colorization: 1.0
            colorizationColor: section.titleColor ? section.titleColor : root.foreground
          }
        }

        Text {
          visible: section.title !== ""
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
          textFormat: Text.PlainText
          text: section.title
          color: section.titleColor
          font.family: root.fontFamily
          font.pixelSize: 11
          font.bold: true
          elide: Text.ElideRight
        }

        Rectangle {
          visible: section.badgeText !== ""
          radius: 3
          color: root.alpha(section.badgeColor, 0.15)
          border.color: root.alpha(section.badgeColor, 0.35)
          border.width: 1
          implicitHeight: 18
          implicitWidth: badgeLabel.implicitWidth + 10
          Layout.alignment: Qt.AlignVCenter | Qt.AlignRight

          Text {
            id: badgeLabel
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: section.badgeText
            color: section.badgeTextColor
            font.family: root.fontFamily
            font.pixelSize: 8
            font.bold: true
          }
        }

        Loader {
          sourceComponent: section.headerAccessory
          visible: !!section.headerAccessory
          Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: section.subtitle !== ""
        Layout.fillWidth: true
        text: section.subtitle
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: 9
        maximumLineCount: 1
        elide: Text.ElideRight
      }
    }
  }

  component StatBlock: Rectangle {
    property string label: ""
    property string value: ""
    property color valColor: root.foreground

    Layout.fillWidth: true
    Layout.preferredWidth: 1
    Layout.minimumWidth: 0
    implicitHeight: 46
    radius: 4
    color: root.track
    clip: true

    ColumnLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: 4
      anchors.rightMargin: 4
      spacing: 2

      Text {
        textFormat: Text.PlainText
        text: value
        color: valColor
        font.family: root.fontFamily
        font.pixelSize: 13
        font.bold: true
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        text: label
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: 8
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }
    }
  }

  component SessionItem: Rectangle {
    id: sItem
    property var sessionData: null
    property color tagColor: (sessionData && sessionData.agentColor) ? root.adaptColorForTheme(sessionData.agentColor) : (sessionData && sessionData.agentId ? root.agentColor(sessionData.agentId) : root.accent)
    property string tagLabel: (sessionData && sessionData.agentId === "antigravity") ? "AGY" : ((sessionData && sessionData.agentId === "codex") ? "CODEX" : ((sessionData && sessionData.agentId === "claude") ? "CLAUDE" : ""))

    Layout.fillWidth: true
    Layout.leftMargin: (sessionData && sessionData.indent ? 16 : 0)
    implicitHeight: rowCol.implicitHeight + 8
    radius: 3
    color: sMouse.containsMouse ? root.cardHover : "transparent"

    MouseArea {
      id: sMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        if (sItem.sessionData) {
          root.resumeSession(sItem.sessionData.agentId, sItem.sessionData.conversationId, sItem.sessionData.workspace, sItem.sessionData.preview || sItem.sessionData.title, sItem.sessionData.pid)
        }
      }
    }

    ColumnLayout {
      id: rowCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 4
      spacing: 2

      RowLayout {
        Layout.fillWidth: true
        spacing: 4

        Text {
          visible: Boolean(sItem.sessionData && sItem.sessionData.isSubagent)
          textFormat: Text.PlainText
          text: "└─"
          color: sItem.tagColor
          font.family: root.fontFamily
          font.pixelSize: 10
          font.bold: true
        }

        Rectangle {
          visible: sItem.tagLabel !== ""
          radius: 2
          color: sItem.tagColor
          Layout.preferredHeight: 12
          Layout.preferredWidth: aTagText.implicitWidth + 6

          Text {
            id: aTagText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: sItem.tagLabel
            color: "#FFFFFF"
            font.family: root.fontFamily
            font.pixelSize: 7
            font.bold: true
          }
        }

        Text {
          textFormat: Text.PlainText
          text: sItem.sessionData ? (sItem.sessionData.preview || sItem.sessionData.title || "Session") : "Session"
          color: sMouse.containsMouse ? root.accent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: 10
          font.bold: true
          elide: Text.ElideRight
          Layout.fillWidth: true
        }

        // Active badge, Subagent badge & Kill button
        RowLayout {
          spacing: 4

          Rectangle {
            visible: Boolean(sItem.sessionData && sItem.sessionData.isSubagent)
            color: Qt.rgba(sItem.tagColor.r, sItem.tagColor.g, sItem.tagColor.b, 0.15)
            border.color: Qt.rgba(sItem.tagColor.r, sItem.tagColor.g, sItem.tagColor.b, 0.3)
            border.width: 1
            radius: 2
            Layout.preferredHeight: 12
            Layout.preferredWidth: subagentBadgeText.implicitWidth + 6

            Text {
              id: subagentBadgeText
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: (sItem.sessionData && sItem.sessionData.agentName && sItem.sessionData.agentName !== "Claude Code" && sItem.sessionData.agentName !== "Antigravity") ? sItem.sessionData.agentName.toUpperCase() : "SUBAGENT"
              color: sItem.tagColor
              font.family: root.fontFamily
              font.pixelSize: 7
              font.bold: true
            }
          }

          Rectangle {
            visible: Boolean(sItem.sessionData && sItem.sessionData.isActive)
            radius: 2
            color: kMouse.containsMouse ? root.urgent : root.track
            Layout.preferredHeight: 12
            Layout.preferredWidth: 12

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: ""
              color: "#FFFFFF"
              font.family: root.fontFamily
              font.pixelSize: 7
            }

            MouseArea {
              id: kMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: function(mouse) {
                mouse.accepted = true
                if (sItem.sessionData) {
                  root.killSession(sItem.sessionData.agentId, sItem.sessionData.conversationId)
                }
              }
            }
          }

          Rectangle {
            radius: 2
            color: (sItem.sessionData && sItem.sessionData.isActive) ? (root.isLightTheme ? "#059669" : "#10B981") : root.track
            Layout.preferredHeight: 12
            Layout.preferredWidth: sTagText.implicitWidth + 6

            Text {
              id: sTagText
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: (sItem.sessionData && sItem.sessionData.isActive) ? "ACTIVE" : "IDLE"
              color: (sItem.sessionData && sItem.sessionData.isActive) ? "#FFFFFF" : root.dim
              font.family: root.fontFamily
              font.pixelSize: 7
              font.bold: true
            }
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 4

        Text {
          textFormat: Text.PlainText
          text: " " + (sItem.sessionData ? (sItem.sessionData.workspaceName || "Workspace") : "Workspace")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: 8
          elide: Text.ElideRight
          Layout.fillWidth: true
        }

        Text { textFormat: Text.PlainText; text: "·"; color: root.dim; font.pixelSize: 8 }

        Text {
          textFormat: Text.PlainText
          text: (sItem.sessionData ? (sItem.sessionData.stepCount || 0) : 0) + " steps"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: 8
        }
      }
    }
  }

  // Shown when a provider's limits can't be read (signed out, expired, rate limited, offline).
  component QuotaStatusNotice: Rectangle {
    id: notice
    property string agentId: ""
    readonly property var st: root.agentQuotaStatus(agentId)
    readonly property bool fixable: Boolean(st.command && st.command.length > 0)

    visible: st.state !== "ok"
    Layout.fillWidth: true
    implicitHeight: noticeRow.implicitHeight + 12
    radius: 4
    color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.08)
    border.color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.35)
    border.width: 1

    RowLayout {
      id: noticeRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: 6
      spacing: 8

      Text {
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        text: notice.st.message
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: 9
        Layout.fillWidth: true
      }

      Button {
        visible: notice.fixable
        text: root.awaitingSignIn ? "Waiting…" : "Sign in"
        fontFamily: root.fontFamily
        fontSize: 10
        onClicked: root.signIn(notice.agentId)
      }
    }
  }

  component QuotaGroupView: ColumnLayout {
    id: qGroupView
    property var quotaGroups: []
    Layout.fillWidth: true
    spacing: 6

    Repeater {
      model: qGroupView.quotaGroups || []
      delegate: ColumnLayout {
        required property var modelData
        Layout.fillWidth: true
        spacing: 3

        Text {
          visible: Boolean(modelData.name && modelData.name.length > 0)
          textFormat: Text.PlainText
          text: modelData.name || "Quota Group"
          color: root.adaptColorForTheme(modelData.color || root.foreground)
          font.family: root.fontFamily
          font.pixelSize: 9
          font.bold: true
        }

        Repeater {
          model: modelData.buckets || []
          delegate: ColumnLayout {
            id: bucketCard
            required property var modelData
            readonly property real leftValue: root.leftPct(modelData)
            readonly property string severity: root.severityForLeft(leftValue)
            readonly property bool usedMode: root.limitDisplay === "used"
            readonly property bool hasPace: modelData.paceMarker !== undefined && modelData.paceMarker !== null
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
              Layout.fillWidth: true
              spacing: 4

              Text {
                textFormat: Text.PlainText
                text: modelData.label || modelData.name || "Limit"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: 10
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                elide: Text.ElideRight
              }

              Text {
                visible: Boolean(modelData.burnRateText && modelData.burnRateText.length > 0)
                textFormat: Text.PlainText
                text: "🔥 " + modelData.burnRateText
                color: root.paceColor(modelData)
                font.family: root.fontFamily
                font.pixelSize: 8
                font.bold: true
                Layout.alignment: Qt.AlignVCenter
              }

              Text {
                textFormat: Text.PlainText
                text: root.shownPct(modelData) + root.shownSuffix()
                color: root.severityColor(bucketCard.severity, root.foreground)
                font.family: root.fontFamily
                font.pixelSize: 9
                font.bold: true
                Layout.alignment: Qt.AlignVCenter
              }
            }

            // Meter + pace tick. The tick marks where even use would be by now, so the filled
            // part past it is use ahead of pace. Both follow the used/left setting.
            Item {
              Layout.fillWidth: true
              Layout.preferredHeight: 9

              Rectangle {
                id: meterTrack
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 5
                radius: 2
                color: root.track
                clip: true

                Rectangle {
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  width: parent.width * Math.max(0.0, Math.min(1.0, (bucketCard.usedMode ? (100 - bucketCard.leftValue) : bucketCard.leftValue) / 100.0))
                  radius: 2
                  color: root.severityColor(bucketCard.severity, root.adaptColorForTheme(modelData.color || root.accent))
                }
              }

              Rectangle {
                visible: bucketCard.hasPace
                width: 2
                height: 9
                radius: 1
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(0, Math.min(parent.width - width, parent.width * (bucketCard.usedMode ? Number(modelData.paceMarker || 0) : (1.0 - Number(modelData.paceMarker || 0))) - width / 2))
                color: modelData.paceAhead ? root.urgent : root.foreground
                opacity: 0.9
              }
            }

            // Sub-info: pace/projection and reset
            RowLayout {
              Layout.fillWidth: true
              spacing: 4

              Text {
                textFormat: Text.PlainText
                text: modelData.paceText || modelData.forecastText || ""
                color: modelData.paceText ? root.paceColor(modelData) : root.dim
                font.family: root.fontFamily
                font.pixelSize: 8
                elide: Text.ElideRight
                Layout.fillWidth: true
              }

              Text {
                visible: Boolean((modelData.resetTime || modelData.resetsAt || modelData.reset_time) && String(modelData.resetTime || modelData.resetsAt || modelData.reset_time).length > 0)
                textFormat: Text.PlainText
                text: root.formatResetText(modelData.resetTime || modelData.resetsAt || modelData.reset_time)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: 8
              }
            }
          }
        }
      }
    }
  }

  // --- OVERVIEW TAB CONTENT ---
  component OverviewContent: ColumnLayout {
    property var provider: null
    Layout.fillWidth: true
    spacing: 8

    // Combined Today & Totals Card
    SectionCard {
      title: "Today & Cross-Agent Totals"
      titleColor: root.accent
      icon: "assets/agent-hub.svg"
      badgeText: "All Agents"
      badgeColor: root.accent
      subtitle: "Combined metrics across Claude Code, Antigravity & Codex"

      ColumnLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: 6

        RowLayout {
          Layout.fillWidth: true
          Layout.minimumWidth: 0
          spacing: 6

          StatBlock {
            value: provider ? usageMain.formatNumber(provider.todayPrompts) : "0"
            label: "prompts today"
          }
          StatBlock {
            value: provider ? usageMain.formatNumber(provider.todaySteps) : "0"
            label: "steps today"
          }
          StatBlock {
            value: provider ? usageMain.formatNumber(provider.todayTotalTokens) : "0"
            label: "tokens today"
          }
          StatBlock {
            value: provider ? String(provider.activeSessions ? provider.activeSessions.length : 0) : "0"
            label: "active sessions"
            valColor: (provider && provider.activeSessions && provider.activeSessions.length > 0) ? (root.isLightTheme ? "#059669" : "#10B981") : root.foreground
          }
        }

        // Sub-breakdown row
        RowLayout {
          Layout.fillWidth: true
          Layout.minimumWidth: 0
          spacing: 5

          Text {
            textFormat: Text.PlainText
            text: "Claude: " + usageMain.formatNumber(provider ? (provider.todayTokensByAgent ? provider.todayTokensByAgent.claude : 0) : 0)
            color: root.agentColor("claude")
            font.family: root.fontFamily
            font.pixelSize: 9
            font.bold: true
            Layout.alignment: Qt.AlignVCenter
          }

          Text {
            textFormat: Text.PlainText
            text: "·"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: 9
            Layout.alignment: Qt.AlignVCenter
          }

          Text {
            textFormat: Text.PlainText
            text: "Antigravity: " + usageMain.formatNumber(provider ? (provider.todayTokensByAgent ? provider.todayTokensByAgent.antigravity : 0) : 0)
            color: root.agentColor("antigravity")
            font.family: root.fontFamily
            font.pixelSize: 9
            font.bold: true
            Layout.alignment: Qt.AlignVCenter
          }

          Text {
            textFormat: Text.PlainText
            text: "·"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: 9
            Layout.alignment: Qt.AlignVCenter
          }

          Text {
            textFormat: Text.PlainText
            text: "Codex: " + usageMain.formatNumber(provider ? (provider.todayTokensByAgent ? provider.todayTokensByAgent.codex : 0) : 0)
            color: root.agentColor("codex")
            font.family: root.fontFamily
            font.pixelSize: 9
            font.bold: true
            Layout.alignment: Qt.AlignVCenter
          }

          Text {
            textFormat: Text.PlainText
            text: "Total: " + usageMain.formatNumber(provider ? provider.totalPrompts : 0) + " prompts"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: 9
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.alignment: Qt.AlignVCenter
          }
        }

        // Prompt Cache Efficiency Pill
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 22
          implicitHeight: 22
          radius: 4
          color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.08)
          border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 6

            Text {
              textFormat: Text.PlainText
              text: "⚡ Prompt Cache:"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: 9
              font.bold: true
              Layout.alignment: Qt.AlignVCenter
            }

            Text {
              textFormat: Text.PlainText
              text: (provider ? (provider.todayCacheHitRate || 0) : 0) + "% hit rate"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 9
              font.bold: true
              Layout.alignment: Qt.AlignVCenter
            }

            Text {
              textFormat: Text.PlainText
              text: "·"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: 9
              Layout.alignment: Qt.AlignVCenter
            }

            Text {
              textFormat: Text.PlainText
              text: "Saved " + usageMain.formatNumber(provider ? (provider.todayCacheReadTokens || 0) : 0) + " cached tokens"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: 9
              Layout.fillWidth: true
              Layout.minimumWidth: 0
              Layout.alignment: Qt.AlignVCenter
              elide: Text.ElideRight
            }
          }
        }
      }
    }

    // --- CLAUDE CODE DEDICATED SECTION ---
    SectionCard {
      title: "Claude Code"
      titleColor: root.agentColor("claude")
      icon: "assets/claude.svg"
      badgeText: (provider && provider.claudeData && provider.claudeData.currentModel) ? provider.claudeData.currentModel : "Claude"
      badgeColor: root.agentColor("claude")
      subtitle: {
        var c = provider ? provider.claudeData : null
        var activeN = (provider && provider.activeAgentCounts) ? (provider.activeAgentCounts.claude || 0) : 0
        if (activeN > 0) {
          return "Active (" + activeN + " session" + (activeN > 1 ? "s" : "") + " running) • Anthropic Claude Code"
        }
        return "Anthropic Claude Code CLI"
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 8

        QuotaStatusNotice { agentId: "claude" }

        Text {
          visible: !((provider && provider.claudeData && provider.claudeData.quotaGroups && provider.claudeData.quotaGroups.length > 0)) && root.agentQuotaStatus("claude").state === "ok"
          textFormat: Text.PlainText
          text: "No active quota limits configured"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: 9
        }

        // Claude Quotas
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 4
          visible: Boolean(provider && provider.claudeData && provider.claudeData.quotaGroups && provider.claudeData.quotaGroups.length > 0)

          Text {
            textFormat: Text.PlainText
            text: "Quota Limits & Reset Forecasting"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: 8
            font.bold: true
          }

          QuotaGroupView {
            quotaGroups: (provider && provider.claudeData) ? (provider.claudeData.quotaGroups || []) : []
          }
        }
      }
    }

    // --- GOOGLE ANTIGRAVITY (AGY) DEDICATED SECTION ---
    SectionCard {
      title: "Google Antigravity"
      titleColor: root.agentColor("antigravity")
      icon: "assets/antigravity.svg"
      badgeText: (provider && provider.antigravityData && provider.antigravityData.currentModel) ? provider.antigravityData.currentModel : "Gemini"
      badgeColor: root.agentColor("antigravity")
      subtitle: {
        var a = provider ? provider.antigravityData : null
        var activeN = (provider && provider.activeAgentCounts) ? (provider.activeAgentCounts.antigravity || 0) : 0
        if (activeN > 0) {
          return "Active (" + activeN + " session" + (activeN > 1 ? "s" : "") + " running) • Google Antigravity"
        }
        return "Google Antigravity Agentic Assistant"
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 8

        QuotaStatusNotice { agentId: "antigravity" }

        Text {
          visible: !((provider && provider.antigravityData && provider.antigravityData.quotaGroups && provider.antigravityData.quotaGroups.length > 0)) && root.agentQuotaStatus("antigravity").state === "ok"
          textFormat: Text.PlainText
          text: "No active quota limits configured"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: 9
        }

        // AGY Quotas
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 4
          visible: Boolean(provider && provider.antigravityData && provider.antigravityData.quotaGroups && provider.antigravityData.quotaGroups.length > 0)

          Text {
            textFormat: Text.PlainText
            text: "Quota Limits & Reset Forecasting"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: 8
            font.bold: true
          }

          QuotaGroupView {
            quotaGroups: (provider && provider.antigravityData) ? (provider.antigravityData.quotaGroups || []) : []
          }
        }
      }
    }

    // --- OPENAI CODEX DEDICATED SECTION ---
    SectionCard {
      title: "OpenAI Codex"
      titleColor: root.agentColor("codex")
      icon: "assets/codex.svg"
      badgeText: (provider && provider.codexData && provider.codexData.currentModel) ? provider.codexData.currentModel : "Codex"
      badgeColor: root.agentColor("codex")
      subtitle: {
        var x = provider ? provider.codexData : null
        var activeN = (provider && provider.activeAgentCounts) ? (provider.activeAgentCounts.codex || 0) : 0
        if (activeN > 0) {
          return "Active (" + activeN + " session" + (activeN > 1 ? "s" : "") + " running) • OpenAI Codex"
        }
        return "OpenAI Codex CLI"
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 8

        QuotaStatusNotice { agentId: "codex" }

        Text {
          visible: !((provider && provider.codexData && provider.codexData.quotaGroups && provider.codexData.quotaGroups.length > 0)) && root.agentQuotaStatus("codex").state === "ok"
          textFormat: Text.PlainText
          text: "No active quota limits configured"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: 9
        }

        // Codex Quotas
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 4
          visible: Boolean(provider && provider.codexData && provider.codexData.quotaGroups && provider.codexData.quotaGroups.length > 0)

          Text {
            textFormat: Text.PlainText
            text: "Quota Limits & Reset Forecasting"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: 8
            font.bold: true
          }

          QuotaGroupView {
            quotaGroups: (provider && provider.codexData) ? (provider.codexData.quotaGroups || []) : []
          }
        }
      }
    }

    // --- CROSS-AGENT TOOL EXECUTIONS ---
    SectionCard {
      title: "Cross-Agent Tool Executions"
      subtitle: "Combined operations across all active agents"
      visible: Boolean(provider && provider.toolUsage && Object.keys(provider.toolUsage).length > 0)

      GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 10
        rowSpacing: 4

        Repeater {
          model: {
            var res = []
            if (provider && provider.toolUsage) {
              for (var k in provider.toolUsage) {
                res.push({ name: k, count: provider.toolUsage[k] })
              }
            }
            return res.slice(0, 8)
          }

          delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 4

            Text {
              textFormat: Text.PlainText
              text: modelData.name
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: 9
              elide: Text.ElideRight
              Layout.fillWidth: true
            }

            Text {
              textFormat: Text.PlainText
              text: String(modelData.count)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 9
              font.bold: true
            }
          }
        }
      }
    }

    // --- COMBINED 7-DAY ACTIVITY ---
    SectionCard {
      id: weekCard
      title: "Last 7 Days Cross-Agent Activity"
      subtitle: "Daily prompt volume over the past week"
      visible: Boolean(provider && provider.recentDays && provider.recentDays.length > 0)

      readonly property real maxCount: {
        var days = provider ? (provider.recentDays || []) : []
        var m = 1
        for (var i = 0; i < days.length; i++) {
          var val = Number(days[i].prompts || 0)
          if (val > m) m = val
        }
        return m
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Repeater {
          model: provider ? provider.recentDays : []
          delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 6
            readonly property real count: Number(modelData ? modelData.prompts : 0)

            Text {
              textFormat: Text.PlainText
              text: {
                var d = modelData ? modelData.date : ""
                if (!d) return ""
                var dt = new Date(d + "T00:00:00")
                var names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                return names[dt.getDay()] + " " + String(dt.getMonth() + 1).padStart(2, "0") + "/" + String(dt.getDate()).padStart(2, "0")
              }
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: 9
              Layout.preferredWidth: 46
            }

            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 6
              radius: 2
              color: root.track
              clip: true

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * (count / weekCard.maxCount)
                radius: 2
                color: root.alpha(root.foreground, 0.75)
              }
            }

            Text {
              textFormat: Text.PlainText
              text: count + " prompts"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 9
              font.bold: true
              horizontalAlignment: Text.AlignRight
              Layout.preferredWidth: 58
            }
          }
        }
      }
    }
  }

  // --- DEDICATED PROVIDER DETAIL CONTENT (CLAUDE / ANTIGRAVITY / CODEX) ---
  component ProviderDetailContent: ColumnLayout {
    id: providerDetail
    property string agentId: ""
    property string agentName: ""
    property color agentColor: root.accent
    property var dataPayload: ({})
    Layout.fillWidth: true
    spacing: 8

    SectionCard {
      title: agentName + " Overview"
      titleColor: agentColor
      icon: agentId === "antigravity" ? "assets/antigravity.svg" : (agentId === "codex" ? "assets/codex.svg" : "assets/claude.svg")
      badgeText: dataPayload.currentModel || (agentId === "antigravity" ? "Gemini" : (agentId === "codex" ? "Codex" : "Claude"))
      badgeColor: agentColor
      subtitle: agentId === "antigravity" ? "Google Antigravity Agentic Assistant • Gemini & 3rd-Party Models" : (agentId === "codex" ? "OpenAI Codex CLI • ChatGPT & OpenAI Models" : "Anthropic Claude Code CLI • Claude Models")

      ColumnLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: 6

        RowLayout {
          Layout.fillWidth: true
          Layout.minimumWidth: 0
          spacing: 6

          StatBlock {
            value: usageMain.formatNumber(dataPayload.todayPrompts || 0)
            label: "prompts today"
          }
          StatBlock {
            value: usageMain.formatNumber(dataPayload.todaySteps || 0)
            label: "steps today"
          }
          StatBlock {
            value: usageMain.formatNumber(dataPayload.todayTotalTokens || 0)
            label: "tokens today"
            valColor: agentColor
          }
          StatBlock {
            value: {
              var cost = dataPayload ? dataPayload.todayTokenCost : undefined
              if (cost !== undefined && cost !== null && Number(cost) > 0) {
                return usageMain.formatCost(cost)
              }
              var tok = Number((dataPayload ? dataPayload.todayTotalTokens : 0) || 0)
              if (tok > 0) {
                var m = String((dataPayload ? dataPayload.currentModel : "") || "").toLowerCase()
                var rate = (agentId === "claude" ? (m.indexOf("opus") !== -1 ? 0.0000043 : 0.0000015)
                          : (agentId === "codex" ? 0.0000015
                          : (m.indexOf("pro") !== -1 ? 0.0000015 : 0.000000025)))
                return usageMain.formatCost(tok * rate)
              }
              return "$0.00"
            }
            label: "token cost today"
            valColor: agentColor
          }
        }

        // Prompt Cache Efficiency Pill
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 22
          implicitHeight: 22
          radius: 4
          color: Qt.rgba(agentColor.r, agentColor.g, agentColor.b, 0.08)
          border.color: Qt.rgba(agentColor.r, agentColor.g, agentColor.b, 0.22)
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 6

            Text {
              textFormat: Text.PlainText
              text: "⚡ Prompt Cache:"
              color: agentColor
              font.family: root.fontFamily
              font.pixelSize: 9
              font.bold: true
              Layout.alignment: Qt.AlignVCenter
            }

            Text {
              textFormat: Text.PlainText
              text: (dataPayload ? (dataPayload.todayCacheHitRate || 0) : 0) + "% hit rate"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 9
              font.bold: true
              Layout.alignment: Qt.AlignVCenter
            }

            Text {
              textFormat: Text.PlainText
              text: "·"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: 9
              Layout.alignment: Qt.AlignVCenter
            }

            Text {
              textFormat: Text.PlainText
              text: "Saved " + usageMain.formatNumber(dataPayload ? (dataPayload.todayCacheReadTokens || 0) : 0) + " cached tokens"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: 9
              Layout.fillWidth: true
              Layout.minimumWidth: 0
              Layout.alignment: Qt.AlignVCenter
              elide: Text.ElideRight
            }
          }
        }
      }
    }

    // Provider Quota Groups (matching Overview page QuotaGroupView)
    SectionCard {
      title: "Quota Limits & Reset Forecasting"
      subtitle: "Active rate limit windows and reset pace projections"
      visible: Boolean(dataPayload && dataPayload.quotaGroups && dataPayload.quotaGroups.length > 0) || root.agentQuotaStatus(agentId).state !== "ok"

      QuotaStatusNotice { agentId: providerDetail.agentId }

      QuotaGroupView {
        quotaGroups: dataPayload.quotaGroups || []
      }
    }

    // Model Usage Breakdown
    SectionCard {
      title: "Model Usage Breakdown"
      subtitle: "Prompt and step volume by model"
      visible: Boolean(dataPayload && dataPayload.modelList && dataPayload.modelList.length > 0)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
          model: dataPayload.modelList || []
          delegate: ColumnLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
              Layout.fillWidth: true
              spacing: 6

              Text {
                textFormat: Text.PlainText
                text: modelData.name || "Model"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: 10
                font.bold: true
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
              }

              Text {
                textFormat: Text.PlainText
                text: (modelData.todayPrompts || 0) + " today" + (modelData.todayTokens ? " · " + usageMain.formatNumber(modelData.todayTokens) + " tok" : "") + " · " + (modelData.prompts || 0) + " total"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: 9
                Layout.alignment: Qt.AlignVCenter
              }
            }

            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 5
              height: 5
              radius: 2
              color: root.track
              clip: true

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * Math.min(1.0, Math.max(0.0, Number(modelData.shareFraction || 0)))
                radius: 2
                color: root.adaptColorForTheme(modelData.color || agentColor)
              }
            }
          }
        }
      }
    }

    // Provider Recent Sessions
    SectionCard {
      title: agentName + " Sessions"
      subtitle: "Recent conversations in terminal (click to resume)"
      visible: Boolean(dataPayload && dataPayload.recentSessions && dataPayload.recentSessions.length > 0)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Repeater {
          model: dataPayload ? (dataPayload.recentSessions || []).slice(0, 7) : []
          delegate: SessionItem {
            required property var modelData
            sessionData: modelData
            tagColor: agentColor
            tagLabel: agentId === "antigravity" ? "AGY" : (agentId === "codex" ? "CODEX" : "CLAUDE")
          }
        }
      }
    }
  }

  // --- DEDICATED SPEND CONTENT TAB ---
  component SpendContent: ColumnLayout {
    id: spendView
    property var provider: null
    readonly property var spend: provider ? (provider.spend || ({})) : ({})
    readonly property var cacheInfo: (spend && spend.cacheSavings) ? spend.cacheSavings : ({})
    property int hoveredDayIndex: -1

    Layout.fillWidth: true
    spacing: 8

    // 1. Overall Spend Overview
    SectionCard {
      title: "Spend & Token Cost"
      titleColor: root.accent
      icon: "assets/spend.svg"
      badgeText: "API Telemetry"
      badgeColor: root.accent
      subtitle: "Estimated local cost derived from prompt and token volume across agents"

      ColumnLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: 6

        RowLayout {
          Layout.fillWidth: true
          Layout.minimumWidth: 0
          spacing: 6

          StatBlock {
            value: usageMain.formatCost(spend.todayCost || 0)
            label: "today"
          }
          StatBlock {
            value: usageMain.formatCost(spend.weekCost || 0)
            label: "7 days"
          }
          StatBlock {
            value: usageMain.formatCost(spend.monthCost || 0)
            label: "30 days"
          }
          StatBlock {
            value: "~" + usageMain.formatCost(spend.projectedMonthCost || 0)
            label: "30d projected"
            valColor: root.accent
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 22
          implicitHeight: 22
          radius: 4
          color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.08)
          border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 6

            Text {
              textFormat: Text.PlainText
              text: "Daily Average: " + usageMain.formatCost(spend.avgDailyCost || 0) + " / day"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 9
              font.bold: true
              Layout.alignment: Qt.AlignVCenter
            }

            Text {
              textFormat: Text.PlainText
              text: "·"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: 9
              Layout.alignment: Qt.AlignVCenter
            }

            Text {
              textFormat: Text.PlainText
              text: (spend.days || 30) + " days active"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: 9
              elide: Text.ElideRight
              Layout.fillWidth: true
              Layout.minimumWidth: 0
              Layout.alignment: Qt.AlignVCenter
            }

            Text {
              textFormat: Text.PlainText
              text: "Full Analytics "
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: 9
              font.bold: true
              Layout.alignment: Qt.AlignVCenter

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openAnalytics()
              }
            }
          }
        }
      }
    }

    // 2. 14-Day Graphical Stacked Bar Chart
    SectionCard {
      title: "Daily Spend Activity (Past 14 Days)"
      subtitle: {
        var peak = spend.peakDailyCost || 0
        return "Stacked daily cost by agent · Peak single day: " + usageMain.formatCost(peak)
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 6

        // Hover Inspection Readout
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 22
          implicitHeight: 22
          radius: 4
          color: root.cardHover
          border.color: root.outline
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 6

            Text {
              textFormat: Text.PlainText
              elide: Text.ElideRight
              font.family: root.fontFamily
              font.pixelSize: 9
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              color: spendView.hoveredDayIndex >= 0 ? root.foreground : root.dim
              text: {
                var hist = spend.dailyHistory || []
                if (spendView.hoveredDayIndex >= 0 && spendView.hoveredDayIndex < hist.length) {
                  var d = hist[spendView.hoveredDayIndex]
                  return d.date + " (" + d.dayOfWeek + "): Total " + usageMain.formatCost(d.cost) +
                         "  ·  Claude: " + usageMain.formatCost(d.claudeCost) +
                         "  ·  Antigravity: " + usageMain.formatCost(d.antigravityCost) +
                         "  ·  Codex: " + usageMain.formatCost(d.codexCost)
                }
                return "Hover any daily bar to inspect per-agent cost breakdown"
              }
            }
          }
        }

        // Stacked Bar Chart Grid
        Item {
          Layout.fillWidth: true
          implicitHeight: 96

          RowLayout {
            anchors.fill: parent
            spacing: 3

            Repeater {
              model: spend.dailyHistory || []
              delegate: Item {
                id: barCol
                required property var modelData
                required property int index
                Layout.fillWidth: true
                Layout.fillHeight: true

                readonly property bool isHovered: spendView.hoveredDayIndex === index
                readonly property real peak: Math.max(0.01, spend.peakDailyCost || 1.0)
                readonly property real dayCost: modelData.cost || 0
                readonly property real totalRatio: Math.min(1.0, dayCost / peak)

                ColumnLayout {
                  anchors.fill: parent
                  spacing: 2

                  // Day cost label
                  Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.PlainText
                    font.family: root.fontFamily
                    font.pixelSize: 8
                    font.bold: isHovered
                    color: isHovered ? root.accent : (dayCost > 0 ? root.foreground : "transparent")
                    text: dayCost >= 1.0 ? ("$" + Math.round(dayCost)) : (dayCost > 0 ? ("$" + dayCost.toFixed(2)) : "")
                    elide: Text.ElideNone
                  }

                  // Bar Column Container
                  Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 3
                    color: isHovered ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent"
                    border.color: isHovered ? root.accent : "transparent"
                    border.width: 1

                    // Background Track
                    Rectangle {
                      anchors.horizontalCenter: parent.horizontalCenter
                      anchors.bottom: parent.bottom
                      width: Math.max(4, Math.min(14, parent.width - 2))
                      height: parent.height
                      color: root.track
                      radius: 2
                      opacity: 0.45
                    }

                    // Stacked Colored Segments
                    Item {
                      anchors.horizontalCenter: parent.horizontalCenter
                      anchors.bottom: parent.bottom
                      width: Math.max(4, Math.min(14, parent.width - 2))
                      height: (dayCost > 0) ? Math.max(4, Math.round(totalRatio * parent.height)) : 2
                      clip: true

                      // Segment: Claude on bottom
                      Rectangle {
                        id: claudeSeg
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: (dayCost > 0) ? Math.max(1, Math.round(((modelData.claudeCost || 0) / dayCost) * parent.height)) : 2
                        color: (dayCost > 0) ? root.agentColor("claude") : root.track
                        visible: (modelData.claudeCost || 0) > 0 || dayCost <= 0
                        radius: 1
                      }

                      // Segment: Antigravity in middle
                      Rectangle {
                        id: agSeg
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: claudeSeg.top
                        height: (dayCost > 0) ? Math.round(((modelData.antigravityCost || 0) / dayCost) * parent.height) : 0
                        color: root.agentColor("antigravity")
                        visible: (modelData.antigravityCost || 0) > 0
                        radius: 1
                      }

                      // Segment: Codex on top
                      Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: agSeg.top
                        anchors.top: parent.top
                        color: root.agentColor("codex")
                        visible: (modelData.codexCost || 0) > 0
                        radius: 1
                      }
                    }
                  }

                  // Day label underneath (stacked number and day)
                  Column {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      textFormat: Text.PlainText
                      font.family: root.fontFamily
                      font.pixelSize: 8
                      font.bold: isHovered || (index === ((spend.dailyHistory || []).length - 1))
                      color: (index === ((spend.dailyHistory || []).length - 1)) ? root.accent : (isHovered ? root.foreground : root.dim)
                      text: String(modelData.dayOfMonth || "")
                    }
                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      textFormat: Text.PlainText
                      font.family: root.fontFamily
                      font.pixelSize: 7
                      color: (index === ((spend.dailyHistory || []).length - 1)) ? root.accent : root.dim
                      text: String(modelData.dayOfWeek || "").slice(0, 2)
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: spendView.hoveredDayIndex = index
                  onExited: if (spendView.hoveredDayIndex === index) spendView.hoveredDayIndex = -1
                }
              }
            }
          }
        }

        // Legend Row
        RowLayout {
          Layout.fillWidth: true
          spacing: 10

          RowLayout {
            spacing: 4
            Rectangle { width: 7; height: 7; radius: 3.5; color: root.agentColor("claude"); Layout.alignment: Qt.AlignVCenter }
            Text { textFormat: Text.PlainText; text: "Claude Code"; color: root.dim; font.family: root.fontFamily; font.pixelSize: 9; Layout.alignment: Qt.AlignVCenter }
          }
          RowLayout {
            spacing: 4
            Rectangle { width: 7; height: 7; radius: 3.5; color: root.agentColor("antigravity"); Layout.alignment: Qt.AlignVCenter }
            Text { textFormat: Text.PlainText; text: "Antigravity"; color: root.dim; font.family: root.fontFamily; font.pixelSize: 9; Layout.alignment: Qt.AlignVCenter }
          }
          RowLayout {
            spacing: 4
            Rectangle { width: 7; height: 7; radius: 3.5; color: root.agentColor("codex"); Layout.alignment: Qt.AlignVCenter }
            Text { textFormat: Text.PlainText; text: "Codex"; color: root.dim; font.family: root.fontFamily; font.pixelSize: 9; Layout.alignment: Qt.AlignVCenter }
          }
          Item { Layout.fillWidth: true }
          Text {
            textFormat: Text.PlainText
            text: "14-day rolling window"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: 8
            Layout.alignment: Qt.AlignVCenter
          }
        }
      }
    }

    // 3. Agent Cost Distribution Cards & Proportion Bar
    SectionCard {
      title: "Agent Cost Distribution"
      subtitle: "30-day cumulative share and volume breakdown"

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 6

        // Segmented Proportion Bar
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 6
          height: 6
          radius: 3
          color: root.track
          clip: true

          readonly property var byAgent: spend.byAgentDetail || ({})
          readonly property real totalCost: Math.max(0.01, spend.monthCost || 1.0)
          readonly property real cCost: byAgent.claude ? (byAgent.claude.monthCost || 0) : (spend.monthByAgent ? spend.monthByAgent.claude : 0)
          readonly property real aCost: byAgent.antigravity ? (byAgent.antigravity.monthCost || 0) : (spend.monthByAgent ? spend.monthByAgent.antigravity : 0)
          readonly property real xCost: byAgent.codex ? (byAgent.codex.monthCost || 0) : (spend.monthByAgent ? spend.monthByAgent.codex : 0)

          Row {
            anchors.fill: parent
            spacing: 1

            Rectangle {
              height: parent.height
              width: Math.max(0, Math.round((parent.parent.cCost / parent.parent.totalCost) * parent.width))
              color: root.agentColor("claude")
              visible: width > 0
            }
            Rectangle {
              height: parent.height
              width: Math.max(0, Math.round((parent.parent.aCost / parent.parent.totalCost) * parent.width))
              color: root.agentColor("antigravity")
              visible: width > 0
            }
            Rectangle {
              height: parent.height
              width: Math.max(0, parent.width - (Math.round((parent.parent.cCost / parent.parent.totalCost) * parent.width) + Math.round((parent.parent.aCost / parent.parent.totalCost) * parent.width)))
              color: root.agentColor("codex")
              visible: parent.parent.xCost > 0 && width > 0
            }
          }
        }

        // 3 Agent Stat Cards
        RowLayout {
          Layout.fillWidth: true
          spacing: 6

          // Claude Card
          Rectangle {
            id: cCard
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.preferredHeight: 68
            radius: 4
            color: root.cardHover
            border.color: root.outline
            border.width: 1

            readonly property var cStat: (spend.byAgentDetail && spend.byAgentDetail.claude) ? spend.byAgentDetail.claude : ({})

            Item {
              anchors.fill: parent
              anchors.margins: 7

              Row {
                id: cTopRow
                anchors.left: parent.left
                anchors.right: cPercentText.left
                anchors.top: parent.top
                height: 12
                spacing: 4

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: 6; height: 6; radius: 3
                  color: root.agentColor("claude")
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: "Claude"
                  font.family: root.fontFamily
                  font.pixelSize: 9
                  font.bold: true
                  color: root.foreground
                }
              }

              Text {
                id: cPercentText
                anchors.right: parent.right
                anchors.verticalCenter: cTopRow.verticalCenter
                textFormat: Text.PlainText
                text: ((cCard.cStat && cCard.cStat.costPercent !== undefined) ? cCard.cStat.costPercent : (spend.monthCost > 0 && spend.monthByAgent ? Math.round((spend.monthByAgent.claude / spend.monthCost) * 1000) / 10 : 0)) + "%"
                font.family: root.fontFamily
                font.pixelSize: 8
                font.bold: true
                color: root.agentColor("claude")
              }

              Text {
                id: cCostText
                anchors.left: parent.left
                anchors.top: cTopRow.bottom
                anchors.topMargin: 4
                textFormat: Text.PlainText
                text: usageMain.formatCost((cCard.cStat && cCard.cStat.monthCost !== undefined) ? cCard.cStat.monthCost : (spend.monthByAgent ? spend.monthByAgent.claude : 0))
                font.family: root.fontFamily
                font.pixelSize: 13
                font.bold: true
                color: root.foreground
              }

              Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: cCostText.bottom
                anchors.topMargin: 2
                textFormat: Text.PlainText
                text: "7d: " + usageMain.formatCost((cCard.cStat && cCard.cStat.weekCost !== undefined) ? cCard.cStat.weekCost : (spend.weekByAgent ? spend.weekByAgent.claude : 0)) + " · " + usageMain.formatNumber((cCard.cStat && cCard.cStat.monthTokens) ? cCard.cStat.monthTokens : 0) + " tok"
                font.family: root.fontFamily
                font.pixelSize: 8
                color: root.dim
                elide: Text.ElideRight
              }
            }
          }

          // Antigravity Card
          Rectangle {
            id: aCard
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.preferredHeight: 68
            radius: 4
            color: root.cardHover
            border.color: root.outline
            border.width: 1

            readonly property var aStat: (spend.byAgentDetail && spend.byAgentDetail.antigravity) ? spend.byAgentDetail.antigravity : ({})

            Item {
              anchors.fill: parent
              anchors.margins: 7

              Row {
                id: aTopRow
                anchors.left: parent.left
                anchors.right: aPercentText.left
                anchors.top: parent.top
                height: 12
                spacing: 4

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: 6; height: 6; radius: 3
                  color: root.agentColor("antigravity")
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: "Antigravity"
                  font.family: root.fontFamily
                  font.pixelSize: 9
                  font.bold: true
                  color: root.foreground
                }
              }

              Text {
                id: aPercentText
                anchors.right: parent.right
                anchors.verticalCenter: aTopRow.verticalCenter
                textFormat: Text.PlainText
                text: ((aCard.aStat && aCard.aStat.costPercent !== undefined) ? aCard.aStat.costPercent : (spend.monthCost > 0 && spend.monthByAgent ? Math.round((spend.monthByAgent.antigravity / spend.monthCost) * 1000) / 10 : 0)) + "%"
                font.family: root.fontFamily
                font.pixelSize: 8
                font.bold: true
                color: root.agentColor("antigravity")
              }

              Text {
                id: aCostText
                anchors.left: parent.left
                anchors.top: aTopRow.bottom
                anchors.topMargin: 4
                textFormat: Text.PlainText
                text: usageMain.formatCost((aCard.aStat && aCard.aStat.monthCost !== undefined) ? aCard.aStat.monthCost : (spend.monthByAgent ? spend.monthByAgent.antigravity : 0))
                font.family: root.fontFamily
                font.pixelSize: 13
                font.bold: true
                color: root.foreground
              }

              Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: aCostText.bottom
                anchors.topMargin: 2
                textFormat: Text.PlainText
                text: "7d: " + usageMain.formatCost((aCard.aStat && aCard.aStat.weekCost !== undefined) ? aCard.aStat.weekCost : (spend.weekByAgent ? spend.weekByAgent.antigravity : 0)) + " · " + usageMain.formatNumber((aCard.aStat && aCard.aStat.monthTokens) ? aCard.aStat.monthTokens : 0) + " tok"
                font.family: root.fontFamily
                font.pixelSize: 8
                color: root.dim
                elide: Text.ElideRight
              }
            }
          }

          // Codex Card
          Rectangle {
            id: xCard
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.preferredHeight: 68
            radius: 4
            color: root.cardHover
            border.color: root.outline
            border.width: 1

            readonly property var xStat: (spend.byAgentDetail && spend.byAgentDetail.codex) ? spend.byAgentDetail.codex : ({})

            Item {
              anchors.fill: parent
              anchors.margins: 7

              Row {
                id: xTopRow
                anchors.left: parent.left
                anchors.right: xPercentText.left
                anchors.top: parent.top
                height: 12
                spacing: 4

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: 6; height: 6; radius: 3
                  color: root.agentColor("codex")
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: "Codex"
                  font.family: root.fontFamily
                  font.pixelSize: 9
                  font.bold: true
                  color: root.foreground
                }
              }

              Text {
                id: xPercentText
                anchors.right: parent.right
                anchors.verticalCenter: xTopRow.verticalCenter
                textFormat: Text.PlainText
                text: ((xCard.xStat && xCard.xStat.costPercent !== undefined) ? xCard.xStat.costPercent : (spend.monthCost > 0 && spend.monthByAgent ? Math.round((spend.monthByAgent.codex / spend.monthCost) * 1000) / 10 : 0)) + "%"
                font.family: root.fontFamily
                font.pixelSize: 8
                font.bold: true
                color: root.agentColor("codex")
              }

              Text {
                id: xCostText
                anchors.left: parent.left
                anchors.top: xTopRow.bottom
                anchors.topMargin: 4
                textFormat: Text.PlainText
                text: usageMain.formatCost((xCard.xStat && xCard.xStat.monthCost !== undefined) ? xCard.xStat.monthCost : (spend.monthByAgent ? spend.monthByAgent.codex : 0))
                font.family: root.fontFamily
                font.pixelSize: 13
                font.bold: true
                color: root.foreground
              }

              Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: xCostText.bottom
                anchors.topMargin: 2
                textFormat: Text.PlainText
                text: "7d: " + usageMain.formatCost((xCard.xStat && xCard.xStat.weekCost !== undefined) ? xCard.xStat.weekCost : (spend.weekByAgent ? spend.weekByAgent.codex : 0)) + " · " + usageMain.formatNumber((xCard.xStat && xCard.xStat.monthTokens) ? xCard.xStat.monthTokens : 0) + " tok"
                font.family: root.fontFamily
                font.pixelSize: 8
                color: root.dim
                elide: Text.ElideRight
              }
            }
          }
        }
      }
    }

    // 4. Model Cost Breakdown
    SectionCard {
      title: "Top Models by Spend"
      subtitle: "Estimated token expenditure ranked by model tier"
      visible: Boolean(spend.topModels && spend.topModels.length > 0)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
          model: spend.topModels || []
          delegate: ColumnLayout {
            required property var modelData
            required property int index
            Layout.fillWidth: true
            spacing: 2

            readonly property real maxModelCost: {
              var list = spend.topModels || []
              return (list.length > 0 && list[0].cost > 0) ? list[0].cost : 1.0
            }
            readonly property real fillRatio: Math.min(1.0, Math.max(0.02, (modelData.cost || 0) / maxModelCost))

            RowLayout {
              Layout.fillWidth: true
              spacing: 6

              Text {
                textFormat: Text.PlainText
                text: modelData.name || "Unknown"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: 10
                font.bold: true
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
              }

              Text {
                textFormat: Text.PlainText
                text: usageMain.formatNumber(modelData.tokens || 0) + " tok"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: 9
                Layout.alignment: Qt.AlignVCenter
              }

              Text {
                textFormat: Text.PlainText
                text: "·"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: 9
                Layout.alignment: Qt.AlignVCenter
              }

              Text {
                textFormat: Text.PlainText
                text: usageMain.formatCost(modelData.cost || 0)
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: 9
                font.bold: true
                Layout.alignment: Qt.AlignVCenter
              }
            }

            // Progress bar
            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 5
              height: 5
              radius: 2
              color: root.track
              clip: true

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.round(fillRatio * parent.width)
                radius: 2
                color: {
                  var nm = String(modelData.name || "").toLowerCase()
                  if (nm.indexOf("claude") !== -1 || nm.indexOf("opus") !== -1 || nm.indexOf("sonnet") !== -1) return root.agentColor("claude")
                  if (nm.indexOf("gemini") !== -1 || nm.indexOf("flash") !== -1) return root.agentColor("antigravity")
                  if (nm.indexOf("gpt") !== -1 || nm.indexOf("codex") !== -1) return root.agentColor("codex")
                  return root.accent
                }
              }
            }
          }
        }
      }
    }

    // 5. Prompt Cache Efficiency
    SectionCard {
      title: "Prompt Cache Efficiency"
      subtitle: "Bandwidth reduction and estimated savings from prompt caching"
      badgeText: {
        var rate = (spendView.cacheInfo && spendView.cacheInfo.overallCacheHitRate !== undefined) ? spendView.cacheInfo.overallCacheHitRate : (provider ? (provider.todayCacheHitRate || 0) : 0)
        return Number(rate).toFixed(1) + "% hit rate"
      }
      badgeColor: root.accent

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 6

        RowLayout {
          Layout.fillWidth: true
          spacing: 6

          StatBlock {
            value: {
              var rate = (spendView.cacheInfo && spendView.cacheInfo.overallCacheHitRate !== undefined) ? spendView.cacheInfo.overallCacheHitRate : (provider ? (provider.todayCacheHitRate || 0) : 0)
              return Number(rate).toFixed(1) + "%"
            }
            label: "30d hit rate"
            valColor: root.accent
          }
          StatBlock {
            value: {
              var tok = (spendView.cacheInfo && spendView.cacheInfo.cacheReadTokens !== undefined) ? spendView.cacheInfo.cacheReadTokens : (provider ? (provider.todayCacheReadTokens || 0) : 0)
              return usageMain.formatNumber(tok)
            }
            label: "cached tokens read"
          }
          StatBlock {
            value: {
              var days = (spendView.cacheInfo && spendView.cacheInfo.activeDays !== undefined) ? spendView.cacheInfo.activeDays : (spendView.spend.days || 30)
              return days + " days"
            }
            label: "active telemetry"
          }
        }

        // Efficiency visual bar
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 6
          height: 6
          radius: 3
          color: root.track
          clip: true

          Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            readonly property real rateVal: (spendView.cacheInfo && spendView.cacheInfo.overallCacheHitRate !== undefined) ? spendView.cacheInfo.overallCacheHitRate : (provider ? (provider.todayCacheHitRate || 0) : 0)
            width: Math.round(Math.min(1.0, Math.max(0.04, Number(rateVal) / 100.0)) * parent.width)
            radius: 3
            color: root.accent
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: 4

          Text {
            textFormat: Text.PlainText
            text: "Today: " + usageMain.formatNumber(provider ? (provider.todayCacheReadTokens || 0) : 0) + " cached (" + (provider ? (provider.todayCacheHitRate || 0) : 0) + "% rate)"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 8
            font.bold: true
            Layout.alignment: Qt.AlignVCenter
          }
          Item { Layout.fillWidth: true }
          Text {
            textFormat: Text.PlainText
            text: "Cached reads avoid up to 90% of base token costs"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: 8
            Layout.alignment: Qt.AlignVCenter
          }
        }
      }
    }

  }

  // --- SETTINGS VIEW CONTENT ---
  component StepperRow: RowLayout {
    id: stepper
    property string label: ""
    property string settingKey: ""
    property int fallback: 0
    property int minValue: 0
    property int maxValue: 100
    property int stepSize: 1
    property string suffix: ""
    readonly property int current: Number(root.draftValue(settingKey, fallback))

    Layout.fillWidth: true
    spacing: 6

    Text {
      textFormat: Text.PlainText
      text: stepper.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: 10
      Layout.fillWidth: true
    }
    Button {
      text: "−"
      fontFamily: root.fontFamily
      fontSize: 10
      onClicked: root.setDraftValue(stepper.settingKey, Math.max(stepper.minValue, stepper.current - stepper.stepSize))
    }
    Text {
      textFormat: Text.PlainText
      text: stepper.current + stepper.suffix
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: 10
      font.bold: true
      horizontalAlignment: Text.AlignHCenter
      Layout.preferredWidth: 38
    }
    Button {
      text: "+"
      fontFamily: root.fontFamily
      fontSize: 10
      onClicked: root.setDraftValue(stepper.settingKey, Math.min(stepper.maxValue, stepper.current + stepper.stepSize))
    }
  }

  component ToggleRow: RowLayout {
    id: toggleRow
    property string label: ""
    property string settingKey: ""
    property bool fallback: false
    Layout.fillWidth: true

    Text {
      textFormat: Text.PlainText
      text: toggleRow.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: 10
      Layout.fillWidth: true
    }
    CheckBox {
      checked: root.draftValue(toggleRow.settingKey, toggleRow.fallback)
      onToggled: root.setDraftValue(toggleRow.settingKey, checked)
    }
  }

  component ChoiceRows: ColumnLayout {
    id: choiceRows
    property string settingKey: ""
    property string fallback: ""
    property var choices: []
    Layout.fillWidth: true
    spacing: 4

    Repeater {
      model: choiceRows.choices
      delegate: RowLayout {
        required property var modelData
        Layout.fillWidth: true
        spacing: 6

        RadioButton {
          checked: root.draftValue(choiceRows.settingKey, choiceRows.fallback) === modelData.id
          onToggled: root.setDraftValue(choiceRows.settingKey, modelData.id)
        }
        Text {
          textFormat: Text.PlainText
          text: modelData.label
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: 10
          Layout.fillWidth: true
        }
      }
    }
  }

  component SettingsContent: ColumnLayout {
    Layout.fillWidth: true
    spacing: 8

    // Agent Enablement
    SectionCard {
      title: "Active AI Agents"
      subtitle: "Enable or disable agent integrations"

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 6

        RowLayout {
          Layout.fillWidth: true
          Text {
            textFormat: Text.PlainText
            text: "Claude Code Integration"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 10
            Layout.fillWidth: true
          }
          CheckBox {
            checked: root.draftValue("enableClaude", true)
            onToggled: root.setDraftValue("enableClaude", checked)
          }
        }

        RowLayout {
          Layout.fillWidth: true
          Text {
            textFormat: Text.PlainText
            text: "Google Antigravity Integration"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 10
            Layout.fillWidth: true
          }
          CheckBox {
            checked: root.draftValue("enableAntigravity", true)
            onToggled: root.setDraftValue("enableAntigravity", checked)
          }
        }

        RowLayout {
          Layout.fillWidth: true
          Text {
            textFormat: Text.PlainText
            text: "OpenAI Codex Integration"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 10
            Layout.fillWidth: true
          }
          CheckBox {
            checked: root.draftValue("enableCodex", true)
            onToggled: root.setDraftValue("enableCodex", checked)
          }
        }
      }
    }

    // Live Hooks Installer
    SectionCard {
      title: "Live Hook Updates"
      subtitle: "Instant zero-latency bar refresh on agent session events"

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 6

        Text {
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
          text: {
            if (!root.provider || !root.provider.hooksKnown) return "Checking live hooks status…"
            var c = root.provider.claudeHooksInstalled ? "Claude: Active" : "Claude: Not Installed"
            var a = root.provider.antigravityHooksInstalled ? "Antigravity: Active" : "Antigravity: Not Installed"
            return c + " · " + a
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: 9
        }

        RowLayout {
          spacing: 6

          Button {
            text: (root.provider && root.provider.hooksInstalled) ? "Remove All Hooks" : "Install All Hooks"
            fontFamily: root.fontFamily
            fontSize: 10
            onClicked: {
              if (root.provider && root.provider.hooksInstalled) {
                root.provider.removeHooks("all")
              } else if (root.provider) {
                root.provider.installHooks("all")
              }
            }
          }

          Button {
            text: "Check Status"
            fontFamily: root.fontFamily
            fontSize: 10
            onClicked: if (root.provider) root.provider.checkHooks()
          }
        }
      }
    }

    // Top Bar Multi-Dot Status Indicator Setting
    SectionCard {
      title: "Top Bar Multi-Dot Status Indicator"
      subtitle: "Color-coded micro dots for Claude, Antigravity, and Codex in the top bar"

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 6

        RowLayout {
          Layout.fillWidth: true
          Text {
            textFormat: Text.PlainText
            text: "Enable Per-Agent Status Dots"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 10
            Layout.fillWidth: true
          }
          CheckBox {
            checked: root.draftValue("enableMultiDot", true)
            onToggled: root.setDraftValue("enableMultiDot", checked)
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 4
          visible: root.draftValue("enableMultiDot", true)

          RowLayout {
            spacing: 6
            RadioButton {
              checked: root.draftValue("multiDotMode", "active") === "active"
              onToggled: root.setDraftValue("multiDotMode", "active")
            }
            Text {
              textFormat: Text.PlainText
              text: "Active agents only (Default · auto-hides idle agents)"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 10
            }
          }

          RowLayout {
            spacing: 6
            RadioButton {
              checked: root.draftValue("multiDotMode", "active") === "all"
              onToggled: root.setDraftValue("multiDotMode", "all")
            }
            Text {
              textFormat: Text.PlainText
              text: "Always show all slots (dim dot when idle)"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 10
            }
          }
        }
      }
    }

    // Limits display
    SectionCard {
      title: "Limits Display"
      subtitle: "Applies to every card, chip and badge. Alert levels are always percent left."

      ChoiceRows {
        settingKey: "limitDisplay"
        fallback: "left"
        choices: [
          { id: "left", label: "Show percent left (Default)" },
          { id: "used", label: "Show percent used" }
        ]
      }
    }

    // Quota alerts
    SectionCard {
      title: "Quota Alerts"
      subtitle: "Desktop notifications at warning and critical levels. They re-arm after a limit resets."

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 6

        ToggleRow { label: "Send desktop alerts"; settingKey: "enableQuotaAlerts"; fallback: true }
        StepperRow {
          label: "Warning level (% left)"
          settingKey: "quotaWarnThreshold"
          fallback: 25
          minValue: 5
          maxValue: 50
          stepSize: 5
          suffix: "%"
          visible: root.draftValue("enableQuotaAlerts", true)
        }
        StepperRow {
          label: "Critical level (% left)"
          settingKey: "quotaCritThreshold"
          fallback: 10
          minValue: 1
          maxValue: 25
          stepSize: 1
          suffix: "%"
          visible: root.draftValue("enableQuotaAlerts", true)
        }
        ToggleRow {
          label: "Announce when a limit resets"
          settingKey: "notifyOnReplenish"
          fallback: true
          visible: root.draftValue("enableQuotaAlerts", true)
        }
      }
    }

    // Bar quota chips
    SectionCard {
      title: "Top Bar Quota Chips"
      subtitle: "One chip per agent with its limit; turns the theme's alert color near a limit"

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 6

        ToggleRow { label: "Show quota chips"; settingKey: "enableQuotaChips"; fallback: false }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 6
          visible: root.draftValue("enableQuotaChips", false)

          Text {
            textFormat: Text.PlainText
            text: "Limit shown"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: 9
            font.bold: true
          }
          ChoiceRows {
            settingKey: "chipWindow"
            fallback: "tightest"
            choices: [
              { id: "tightest", label: "Most constrained limit (Default)" },
              { id: "5h", label: "Pin to 5-hour" },
              { id: "7d", label: "Pin to 7-day" },
              { id: "monthly", label: "Pin to monthly" }
            ]
          }
          ToggleRow { label: "Second limit below the first"; settingKey: "chipSecondLimit"; fallback: false }
          ToggleRow { label: "Show when limits reset"; settingKey: "chipShowReset"; fallback: false }
          ToggleRow { label: "Hide agents that are used up"; settingKey: "chipHideUsedUp"; fallback: false }
          StepperRow { label: "Chips in the bar (rest fold into +N)"; settingKey: "chipMax"; fallback: 3; minValue: 1; maxValue: 3 }
          ToggleRow { label: "Provider colors"; settingKey: "chipProviderColors"; fallback: true }
        }
      }
    }

    // Badge Mode Picker
    SectionCard {
      title: "Top Bar Badge Display"
      subtitle: "Metric shown in the bar widget badge pill"

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Repeater {
          model: [
            { id: "active", label: "Active Sessions count (Default)" },
            { id: "prompts", label: "Today's prompts count" },
            { id: "tokens", label: "Today's tokens volume" },
            { id: "quota", label: "Tightest quota limit" },
            { id: "cost", label: "Today's estimated cost" },
            { id: "off", label: "Disabled (Icon only)" }
          ]
          delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 6

            RadioButton {
              checked: root.draftValue("badgeMode", "active") === modelData.id
              onToggled: root.setDraftValue("badgeMode", modelData.id)
            }

            Text {
              textFormat: Text.PlainText
              text: modelData.label
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 10
              Layout.fillWidth: true
            }
          }
        }
      }
    }

    // Terminal Emulator Override
    SectionCard {
      title: "Terminal Emulator"
      subtitle: "Override command (e.g. ghostty, kitty, foot, alacritty)"

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        TextField {
          Layout.fillWidth: true
          text: root.draftValue("terminalCommand", "")
          placeholderText: "xdg-terminal-exec (Default)"
          font.family: root.fontFamily
          font.pixelSize: 10
          onEditingFinished: root.setDraftValue("terminalCommand", text)
        }
      }
    }
  }

  Loader {
    id: analyticsWindowLoader
    active: root.analyticsOpen
    source: Qt.resolvedUrl("windows/AnalyticsWindow.qml")
    onLoaded: {
      if (item) {
        item.visible = Qt.binding(function() { return root.analyticsOpen })
        item.closed.connect(function() {
          root.analyticsOpen = false
        })
      }
    }
  }
}
