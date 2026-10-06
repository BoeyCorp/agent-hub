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
  property bool settingsMode: false
  property string currentTab: "overview" // "overview" | "claude" | "antigravity" | "codex"
  property var draftSettings: ({})
  property string settingsStatusText: ""
  property bool refreshFlash: false
  property double nowMs: Date.now()
  onPopupOpenChanged: {
    if (popupOpen) {
      root.nowMs = Date.now()
    }
  }

  readonly property color foreground: (bar && bar.barForeground) ? bar.barForeground : ((bar && bar.foreground) ? bar.foreground : (Color.foreground || "#D8DEE9"))
  readonly property color background: (Color.popups && Color.popups.background) ? Color.popups.background : "#1E1E2E"
  readonly property color border: (Color.popups && Color.popups.border) ? Color.popups.border : "#313244"
  readonly property color urgent: (bar && bar.urgent) ? bar.urgent : (Color.urgent || "#F38BA8")
  readonly property color accent: (bar && bar.accent) ? bar.accent : (Color.accent || "#89B4FA")
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color card: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.055)
  readonly property color cardHover: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.085)
  readonly property color outline: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.18)
  readonly property color track: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.24)
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

    var parts = termSetting.split(/\s+/).filter(function(p) { return p.length > 0 })
    if (parts.length === 0) {
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
    if (agentId === "antigravity") return "#38BDF8"
    if (agentId === "codex") return "#10A37F"
    return "#D97757"
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
      quotaAlertThreshold: 15,
      notifyOnReplenish: true,
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

  function setting(name, fallback) {
    var value = root.settings ? root.settings[name] : undefined
    return value === undefined || value === null ? fallback : value
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
      color: agentId === "claude" ? "#D97757" : (agentId === "antigravity" ? "#38BDF8" : "#10A37F"),
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
    settingsStatusText = "Saved"
    settingsStatusTimer.restart()
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

  readonly property bool isLightTheme: {
    var bgLum = (Color.background ? (Color.background.r * 0.299 + Color.background.g * 0.587 + Color.background.b * 0.114) : 0)
    var fgLum = (foreground.r * 0.299 + foreground.g * 0.587 + foreground.b * 0.114)
    return bgLum > 0.5 || fgLum < 0.5
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
    } else if (mode === "quota") {
      // Find minimum remaining percentage across all quota buckets
      var groups = provider.quotaGroups || []
      var minPct = 100
      var found = false
      for (var i = 0; i < groups.length; i++) {
        var buckets = groups[i].buckets || []
        for (var j = 0; j < buckets.length; j++) {
          var rem = buckets[j].remainingPercent
          if (rem !== undefined && rem !== null) {
            minPct = Math.min(minPct, Number(rem))
            found = true
          }
        }
      }
      return found ? (minPct + "%") : ""
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
           agentSummary + "\n" +
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
    function setBadgeMode(mode: string): string { root.updateSetting("badgeMode", mode); return "ok" }
    function setMultiDot(enabled: bool): string { root.updateSetting("enableMultiDot", enabled); return "ok" }
    function setTab(tabName: string): string {
      if (tabName === "overview" || tabName === "claude" || tabName === "antigravity" || tabName === "codex") {
        root.showUsage()
        root.currentTab = tabName
        return "ok"
      }
      return "invalid tab"
    }
  }

  component UsageChip: Item {
    id: chip

    readonly property bool tooltipHovered: mouseArea.containsMouse
    readonly property string badgeTextValue: root.getBadgeText()
    readonly property bool hasBadge: badgeTextValue.length > 0
    readonly property bool multiDotEnabled: root.setting("enableMultiDot", true)
    readonly property string multiDotMode: root.setting("multiDotMode", "active") // "active" | "all"

    readonly property var agentList: [
      { id: "claude", name: "Claude Code", color: "#D97757", enabled: root.setting("enableClaude", true) },
      { id: "antigravity", name: "Google Antigravity", color: "#38BDF8", enabled: root.setting("enableAntigravity", true) },
      { id: "codex", name: "OpenAI Codex", color: "#10A37F", enabled: root.setting("enableCodex", true) }
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
          color: root.isWorking ? "#10B981" : (root.isWaiting ? "#38BDF8" : "transparent")
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
            var val = parseInt(chip.badgeTextValue)
            if (!isNaN(val) && val <= 15) return root.urgent
            if (!isNaN(val) && val <= 30) return "#F59E0B"
            return root.accent
          }
          return root.isWorking ? "#10B981" : (root.isWaiting ? "#38BDF8" : root.dim)
        }
        font.family: root.fontFamily
        font.pixelSize: 9
        font.bold: true
        Layout.alignment: Qt.AlignVCenter
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
      return panel.fittedContentHeight(needed, Style.space(900))
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
        else if (t === "s" || t === "S") root.settingsMode ? root.saveSettings() : root.openSettings()
        else if (t === "n" || t === "N") { if (!root.settingsMode) root.newSession() }
        else if (t === "q" || t === "Q") root.close()
        else if (t === "1") root.currentTab = "overview"
        else if (t === "2") root.currentTab = "claude"
        else if (t === "3") root.currentTab = "antigravity"
        else if (t === "4") root.currentTab = "codex"
        else if (!root.settingsMode && t >= "5" && t <= "9") {
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
        }

        // Settings Header
        Header {
          id: settingsHeader
          visible: root.settingsMode
          Layout.fillWidth: true
          title: "Agent Hub Settings"
          subtitle: "Configuration, Agent Toggles & Live Hooks"
          refreshing: usageMain.refreshing
          showActionButtons: false
          onRefreshClicked: root.triggerRefresh(true)
          onSettingsClicked: root.showUsage()
          onNewSessionClicked: root.newSession()
        }

        // Tab Navigation Bar (Overview | Claude Code | Antigravity)
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
                { id: "codex", label: "Codex", icon: "assets/codex.svg" }
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
              agentColor: "#D97757"
              dataPayload: root.provider ? root.provider.claudeData : ({})
            }

            // --- ANTIGRAVITY TAB ---
            ProviderDetailContent {
              visible: !root.settingsMode && root.currentTab === "antigravity"
              Layout.fillWidth: true
              agentId: "antigravity"
              agentName: "Antigravity"
              agentColor: "#38BDF8"
              dataPayload: root.provider ? root.provider.antigravityData : ({})
            }

            // --- CODEX TAB ---
            ProviderDetailContent {
              visible: !root.settingsMode && root.currentTab === "codex"
              Layout.fillWidth: true
              agentId: "codex"
              agentName: "Codex"
              agentColor: "#10A37F"
              dataPayload: root.provider ? root.provider.codexData : ({})
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

    readonly property double refMs: (root.provider && root.provider.lastFullRefreshMs > 0) ? root.provider.lastFullRefreshMs : (root.provider ? root.provider.lastUpdatedMs : 0)
    readonly property int ageSec: refMs > 0 ? Math.max(0, Math.floor((root.nowMs - refMs) / 1000)) : -1

    Layout.fillWidth: true
    color: root.card
    borderSpec: Border.flat(Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05), 1)
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
    borderSpec: Border.flat(Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05), 1)
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
        spacing: 6

        Image {
          visible: section.icon !== ""
          source: section.icon !== "" ? Qt.resolvedUrl(section.icon) : ""
          sourceSize.width: 14
          sourceSize.height: 14
          Layout.preferredWidth: 14
          Layout.preferredHeight: 14
          fillMode: Image.PreserveAspectFit
        }

        Text {
          visible: section.title !== ""
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: section.title
          color: section.titleColor
          font.family: root.fontFamily
          font.pixelSize: 11
          font.bold: true
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
        wrapMode: Text.WordWrap
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
      anchors.fill: parent
      anchors.margins: 2
      spacing: 1

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
    property color tagColor: (sessionData && sessionData.agentColor) ? sessionData.agentColor : (sessionData && sessionData.agentId === "antigravity" ? "#38BDF8" : (sessionData && sessionData.agentId === "codex" ? "#10A37F" : (sessionData && sessionData.agentId === "claude" ? "#D97757" : root.accent)))
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
            color: (sItem.sessionData && sItem.sessionData.isActive) ? "#10B981" : root.track
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
          color: modelData.color || root.foreground
          font.family: root.fontFamily
          font.pixelSize: 9
          font.bold: true
        }

        Repeater {
          model: modelData.buckets || []
          delegate: ColumnLayout {
            required property var modelData
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
              }

              Text {
                visible: Boolean(modelData.burnRateText && modelData.burnRateText.length > 0)
                textFormat: Text.PlainText
                text: "🔥 " + modelData.burnRateText
                color: modelData.forecastStatus === "critical" ? root.urgent : (modelData.forecastStatus === "warning" ? "#F59E0B" : root.dim)
                font.family: root.fontFamily
                font.pixelSize: 8
                font.bold: true
              }

              Text {
                textFormat: Text.PlainText
                text: (modelData.remainingPercent !== undefined ? modelData.remainingPercent : Math.round(Number(modelData.remainingFraction || 0) * 100)) + "% left"
                color: Number(modelData.remainingPercent || 0) <= 15 ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: 9
                font.bold: true
              }
            }

            // Progress Bar
            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 5
              radius: 2
              color: root.track
              clip: true

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * Math.max(0.0, Math.min(1.0, Number(modelData.remainingFraction !== undefined ? modelData.remainingFraction : (Number(modelData.remainingPercent || 0) / 100.0))))
                radius: 2
                color: Number(modelData.remainingPercent || 0) <= 15 ? root.urgent : (modelData.color || root.accent)
              }
            }

            // Sub-info: Reset and forecast
            RowLayout {
              Layout.fillWidth: true
              spacing: 4

              Text {
                textFormat: Text.PlainText
                text: modelData.forecastText || ""
                color: modelData.forecastStatus === "critical" ? root.urgent : (modelData.forecastStatus === "warning" ? "#F59E0B" : root.dim)
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
      subtitle: "Combined metrics across Claude Code, Antigravity & Codex"

      ColumnLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: 6

        RowLayout {
          Layout.fillWidth: true
          Layout.minimumWidth: 0
          spacing: 4

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
            valColor: (provider && provider.activeSessions && provider.activeSessions.length > 0) ? "#10B981" : root.foreground
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
            color: "#D97757"
            font.family: root.fontFamily
            font.pixelSize: 9
            font.bold: true
          }

          Text { textFormat: Text.PlainText; text: "·"; color: root.dim; font.pixelSize: 9 }

          Text {
            textFormat: Text.PlainText
            text: "Antigravity: " + usageMain.formatNumber(provider ? (provider.todayTokensByAgent ? provider.todayTokensByAgent.antigravity : 0) : 0)
            color: "#38BDF8"
            font.family: root.fontFamily
            font.pixelSize: 9
            font.bold: true
          }

          Text { textFormat: Text.PlainText; text: "·"; color: root.dim; font.pixelSize: 9 }

          Text {
            textFormat: Text.PlainText
            text: "Codex: " + usageMain.formatNumber(provider ? (provider.todayTokensByAgent ? provider.todayTokensByAgent.codex : 0) : 0)
            color: "#10A37F"
            font.family: root.fontFamily
            font.pixelSize: 9
            font.bold: true
          }

          Item { Layout.fillWidth: true; Layout.minimumWidth: 0 }

          Text {
            textFormat: Text.PlainText
            text: "Total: " + usageMain.formatNumber(provider ? provider.totalPrompts : 0) + " prompts"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: 9
            elide: Text.ElideRight
          }
        }

        // Prompt Cache Efficiency Pill
        Rectangle {
          visible: Boolean(provider && (provider.todayCacheReadTokens > 0 || provider.todayCacheHitRate > 0))
          Layout.fillWidth: true
          Layout.preferredHeight: 22
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
              font.pixelSize: 10
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: (provider ? (provider.todayCacheHitRate || 0) : 0) + "% hit rate"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 10
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: "·"
              color: root.dim
              font.pixelSize: 9
            }

            Text {
              textFormat: Text.PlainText
              text: "Saved " + usageMain.formatNumber(provider ? (provider.todayCacheReadTokens || 0) : 0) + " cached tokens"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: 10
              Layout.fillWidth: true
              elide: Text.ElideRight
            }
          }
        }
      }
    }

    // --- CLAUDE CODE DEDICATED SECTION ---
    SectionCard {
      title: "Claude Code"
      titleColor: "#D97757"
      icon: "assets/claude.svg"
      badgeText: (provider && provider.claudeData && provider.claudeData.currentModel) ? provider.claudeData.currentModel : "Claude"
      badgeColor: "#D97757"
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

        Text {
          visible: !((provider && provider.claudeData && provider.claudeData.quotaGroups && provider.claudeData.quotaGroups.length > 0))
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
      titleColor: "#38BDF8"
      icon: "assets/antigravity.svg"
      badgeText: (provider && provider.antigravityData && provider.antigravityData.currentModel) ? provider.antigravityData.currentModel : "Gemini"
      badgeColor: "#38BDF8"
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

        Text {
          visible: !((provider && provider.antigravityData && provider.antigravityData.quotaGroups && provider.antigravityData.quotaGroups.length > 0))
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
      titleColor: "#10A37F"
      icon: "assets/codex.svg"
      badgeText: (provider && provider.codexData && provider.codexData.currentModel) ? provider.codexData.currentModel : "Codex"
      badgeColor: "#10A37F"
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

        Text {
          visible: !((provider && provider.codexData && provider.codexData.quotaGroups && provider.codexData.quotaGroups.length > 0))
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

    // --- COMBINED ACTIVE & RECENT SESSIONS ---
    SectionCard {
      title: "Active & Recent Sessions"
      subtitle: "Combined sessions across all agents · click or press 5-9 to resume"
      visible: Boolean(provider && provider.recentSessions && provider.recentSessions.length > 0)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Repeater {
          model: provider ? (provider.recentSessions || []).slice(0, 7) : []
          delegate: SessionItem {
            required property var modelData
            sessionData: modelData
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

  // --- DEDICATED PROVIDER DETAIL CONTENT (CLAUDE / ANTIGRAVITY) ---
  component ProviderDetailContent: ColumnLayout {
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
      badgeText: dataPayload.currentModel || ""
      badgeColor: agentColor
      subtitle: agentId === "antigravity" ? "Google Antigravity Agentic Assistant • Gemini & 3rd-Party Models" : (agentId === "codex" ? "OpenAI Codex CLI • ChatGPT & OpenAI Models" : "Anthropic Claude Code CLI")

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 6

        RowLayout {
          Layout.fillWidth: true
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
          visible: Boolean(dataPayload && (dataPayload.todayCacheReadTokens > 0 || dataPayload.todayCacheHitRate > 0))
          Layout.fillWidth: true
          Layout.preferredHeight: 22
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
              font.pixelSize: 10
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: (dataPayload ? (dataPayload.todayCacheHitRate || 0) : 0) + "% hit rate"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 10
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: "·"
              color: root.dim
              font.pixelSize: 9
            }

            Text {
              textFormat: Text.PlainText
              text: "Saved " + usageMain.formatNumber(dataPayload ? (dataPayload.todayCacheReadTokens || 0) : 0) + " cached tokens"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: 10
              Layout.fillWidth: true
              elide: Text.ElideRight
            }
          }
        }
      }
    }

    // Provider Quota Groups (matching Overview page QuotaGroupView)
    SectionCard {
      title: "Quota Limits & Reset Forecasting"
      visible: Boolean(dataPayload && dataPayload.quotaGroups && dataPayload.quotaGroups.length > 0)

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
        spacing: 4

        Repeater {
          model: dataPayload.modelList || []
          delegate: ColumnLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
              Layout.fillWidth: true
              spacing: 4

              Text {
                textFormat: Text.PlainText
                text: modelData.name || "Model"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: 10
                font.bold: true
                elide: Text.ElideRight
                Layout.fillWidth: true
              }

              Text {
                textFormat: Text.PlainText
                text: (modelData.todayPrompts || 0) + " today" + (modelData.todayTokens ? " · " + usageMain.formatNumber(modelData.todayTokens) + " tok" : "") + " · " + (modelData.prompts || 0) + " total"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: 9
              }
            }

            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 5
              radius: 2
              color: root.track
              clip: true

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * Math.min(1.0, Math.max(0.0, Number(modelData.shareFraction || 0)))
                radius: 2
                color: modelData.color || agentColor
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

  // --- SETTINGS VIEW CONTENT ---
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
            { id: "quota", label: "Lowest quota remaining %" },
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
}
