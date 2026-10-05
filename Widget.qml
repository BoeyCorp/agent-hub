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
  property string currentTab: "overview" // "overview" | "claude" | "antigravity"
  property var draftSettings: ({})
  property string settingsStatusText: ""
  property bool refreshFlash: false
  property double nowMs: Date.now()

  readonly property color foreground: (bar && bar.foreground) ? bar.foreground : (Color.foreground || "#D8DEE9")
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

  function resumeSession(agentId, conversationId, workspacePath) {
    if (!conversationId) return
    var cmd = (agentId === "antigravity")
      ? ["agy", "--conversation", conversationId]
      : ["claude", "--resume", conversationId]

    var args = getTerminalArgs(cmd, workspacePath)
    try {
      Quickshell.execDetached(["uwsm-app", "--"].concat(args))
    } catch (e) {
      Quickshell.execDetached(args)
    }
    root.close()
  }

  function newSession(agentId) {
    var chosenAgent = agentId || (currentTab === "antigravity" ? "antigravity" : "claude")
    var cmd = (chosenAgent === "antigravity") ? ["agy"] : ["claude"]
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

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function agentColor(agentId) {
    return agentId === "antigravity" ? "#38BDF8" : "#D97757"
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
      enableAntigravity: true
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

  readonly property url iconSource: Qt.resolvedUrl(isLightTheme ? "assets/agent-hub-light.svg" : "assets/agent-hub.svg")

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
    return "Agent Hub" + status + "\n" +
           (provider.todayPrompts || 0) + " prompts today • " + tokensFmt + " tokens\n" +
           "Claude Code & Google Antigravity"
  }

  width: button.implicitWidth
  implicitWidth: button.implicitWidth

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
  }

  component UsageChip: Item {
    id: chip

    readonly property bool tooltipHovered: mouseArea.containsMouse
    readonly property string badgeTextValue: root.getBadgeText()
    readonly property bool hasBadge: badgeTextValue.length > 0

    width: hasBadge ? (14 + badgeText.implicitWidth + 10) : root.barSize
    height: root.barSize

    RowLayout {
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

        // Active pulse glow
        Rectangle {
          width: 4
          height: 4
          radius: 2
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: -1
          color: root.isWorking ? "#10B981" : (root.isWaiting ? "#38BDF8" : "transparent")
          visible: root.hasActiveSession

          SequentialAnimation on opacity {
            running: root.isWorking
            loops: Animation.Infinite
            NumberAnimation { from: 0.3; to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 1.0; to: 0.3; duration: 600; easing.type: Easing.InOutQuad }
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
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: {
      var headerH = (root.settingsMode ? settingsHeader.implicitHeight : statsHeader.implicitHeight) + 16
      var navH = root.settingsMode ? 0 : 36
      var needed = headerH + navH + contentColumn.implicitHeight + Style.space(24)
      return panel.fittedContentHeight(needed, Style.space(660))
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
        else if (!root.settingsMode && t >= "4" && t <= "9") {
          var idx = parseInt(t) - 1
          var list = root.provider ? (root.provider.recentSessions || []) : []
          if (idx >= 0 && idx < list.length) {
            var s = list[idx]
            root.resumeSession(s.agentId, s.conversationId, s.workspace)
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
          visible: !root.settingsMode
          Layout.fillWidth: true
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
                { id: "antigravity", label: "Antigravity", icon: "assets/antigravity.svg" }
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
          Layout.preferredHeight: Math.min(520, contentColumn.implicitHeight)
          contentWidth: width
          contentHeight: contentColumn.implicitHeight
          clip: true

          ColumnLayout {
            id: contentColumn
            width: parent.width
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

    Layout.fillWidth: true
    color: root.card
    borderSpec: Border.flat(Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05), 1)

    RowLayout {
      anchors.fill: parent
      anchors.margins: 8
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

        Text {
          textFormat: Text.PlainText
          text: hdr.subtitle
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: 9
          elide: Text.ElideRight
          Layout.fillWidth: true
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
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 11
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
  }

  component SectionCard: BorderSurface {
    id: section
    property string title: ""
    property string subtitle: ""
    property color titleColor: root.foreground
    property Component headerAccessory: null
    default property alias content: body.data

    Layout.fillWidth: true
    color: root.card
    borderSpec: Border.flat(Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05), 1)

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 8
      spacing: 6

      RowLayout {
        Layout.fillWidth: true
        spacing: 4

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 1

          Text {
            textFormat: Text.PlainText
            text: section.title
            color: section.titleColor
            font.family: root.fontFamily
            font.pixelSize: 11
            font.bold: true
          }

          Text {
            visible: section.subtitle.length > 0
            textFormat: Text.PlainText
            text: section.subtitle
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: 8
            elide: Text.ElideRight
            Layout.fillWidth: true
          }
        }

        Loader {
          sourceComponent: section.headerAccessory
          Layout.alignment: Qt.AlignVCenter
        }
      }

      Item {
        id: body
        Layout.fillWidth: true
        implicitHeight: childrenRect.height
      }
    }
  }

  component StatBlock: Rectangle {
    property string label: ""
    property string value: ""
    property color valColor: root.foreground

    Layout.fillWidth: true
    implicitHeight: 44
    radius: 3
    color: root.track

    ColumnLayout {
      anchors.centerIn: parent
      spacing: 1

      Text {
        textFormat: Text.PlainText
        text: value
        color: valColor
        font.family: root.fontFamily
        font.pixelSize: 13
        font.bold: true
        Layout.alignment: Qt.AlignHCenter
      }

      Text {
        textFormat: Text.PlainText
        text: label
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: 8
        Layout.alignment: Qt.AlignHCenter
      }
    }
  }

  // --- OVERVIEW TAB CONTENT ---
  component OverviewContent: ColumnLayout {
    property var provider: null
    spacing: 8

    // Combined Today & Totals Card
    SectionCard {
      title: "Today & Cross-Agent Totals"
      subtitle: "Combined metrics across Claude Code & Antigravity"

      ColumnLayout {
        width: parent.width
        spacing: 6

        RowLayout {
          width: parent.width
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
            valColor: (provider && provider.activeSessions && provider.activeSessions.length > 0) ? "#10B981" : root.foreground
          }
        }

        // Sub-breakdown row
        RowLayout {
          width: parent.width
          spacing: 8

          Text {
            textFormat: Text.PlainText
            text: "Claude: " + usageMain.formatNumber(provider ? provider.todayTokensByAgent.claude : 0) + " tokens"
            color: "#D97757"
            font.family: root.fontFamily
            font.pixelSize: 9
            font.bold: true
          }

          Text { textFormat: Text.PlainText; text: "·"; color: root.dim; font.pixelSize: 9 }

          Text {
            textFormat: Text.PlainText
            text: "Antigravity: " + usageMain.formatNumber(provider ? provider.todayTokensByAgent.antigravity : 0) + " tokens"
            color: "#38BDF8"
            font.family: root.fontFamily
            font.pixelSize: 9
            font.bold: true
          }

          Item { Layout.fillWidth: true }

          Text {
            textFormat: Text.PlainText
            text: "Total Prompts: " + usageMain.formatNumber(provider ? provider.totalPrompts : 0)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: 9
          }
        }
      }
    }

    // Consolidated Quota Card
    SectionCard {
      title: "Quota Limits & Reset Forecasting"
      subtitle: "Hourly consumption burn rates and reset projections"
      visible: Boolean(provider && provider.quotaGroups && provider.quotaGroups.length > 0)

      ColumnLayout {
        width: parent.width
        spacing: 8

        Repeater {
          model: provider ? provider.quotaGroups : []
          delegate: ColumnLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 4

            Text {
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
                    text: modelData.remainingPercent + "% left"
                    color: modelData.remainingPercent <= 15 ? root.urgent : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: 9
                    font.bold: true
                  }
                }

                // Progress Bar
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
                    width: parent.width * Math.max(0.0, Math.min(1.0, Number(modelData.remainingFraction || 0)))
                    radius: 2
                    color: modelData.remainingPercent <= 15 ? root.urgent : (modelData.color || root.accent)
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
                    visible: Boolean(modelData.resetTime && modelData.resetTime.length > 0)
                    textFormat: Text.PlainText
                    text: "Resets " + root.formatExactResetTime(modelData.resetTime)
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
    }

    // Unified Recent Sessions
    SectionCard {
      title: "Active & Recent Sessions"
      subtitle: "Click or press 4-9 to resume in terminal"
      visible: Boolean(provider && provider.recentSessions && provider.recentSessions.length > 0)

      ColumnLayout {
        width: parent.width
        spacing: 4

        Repeater {
          model: provider ? (provider.recentSessions || []).slice(0, 7) : []
          delegate: Rectangle {
            required property var modelData
            required property int index
            Layout.fillWidth: true
            implicitHeight: rowCol.implicitHeight + 6
            radius: 3
            color: sMouse.containsMouse ? root.cardHover : "transparent"

            MouseArea {
              id: sMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.resumeSession(modelData.agentId, modelData.conversationId, modelData.workspace)
            }

            ColumnLayout {
              id: rowCol
              anchors.fill: parent
              anchors.margins: 4
              spacing: 2

              RowLayout {
                Layout.fillWidth: true
                spacing: 4

                // Agent Pill
                Rectangle {
                  radius: 2
                  color: modelData.agentColor || root.accent
                  Layout.preferredHeight: 12
                  Layout.preferredWidth: aTagText.implicitWidth + 6

                  Text {
                    id: aTagText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: modelData.agentId === "antigravity" ? "AGY" : "CLAUDE"
                    color: "#FFFFFF"
                    font.family: root.fontFamily
                    font.pixelSize: 7
                    font.bold: true
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  text: modelData.preview || modelData.title || "Session"
                  color: sMouse.containsMouse ? root.accent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: 10
                  font.bold: true
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }

                // Active badge & Kill
                RowLayout {
                  spacing: 4

                  Rectangle {
                    visible: !!modelData.isActive
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
                        root.killSession(modelData.agentId, modelData.conversationId)
                      }
                    }
                  }

                  Rectangle {
                    radius: 2
                    color: modelData.isActive ? "#10B981" : root.track
                    Layout.preferredHeight: 12
                    Layout.preferredWidth: sTagText.implicitWidth + 6

                    Text {
                      id: sTagText
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: modelData.isActive ? "ACTIVE" : "IDLE"
                      color: modelData.isActive ? "#FFFFFF" : root.dim
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
                  text: " " + (modelData.workspaceName || "Workspace")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: 8
                }

                Text { textFormat: Text.PlainText; text: "·"; color: root.dim; font.pixelSize: 8 }

                Text {
                  textFormat: Text.PlainText
                  text: modelData.stepCount + " steps"
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

    // Normalized Tool Telemetry
    SectionCard {
      title: "Cross-Agent Tool Executions"
      subtitle: "Combined operations across all active agents"
      visible: Boolean(provider && provider.toolUsage && Object.keys(provider.toolUsage).length > 0)

      GridLayout {
        width: parent.width
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

    // Combined 7-Day Activity
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
        width: parent.width
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
    spacing: 8

    SectionCard {
      title: agentName + " Overview"
      subtitle: dataPayload.currentModel || ""

      RowLayout {
        width: parent.width
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
      }
    }

    // Model Usage Breakdown
    SectionCard {
      title: "Model Usage Breakdown"
      subtitle: "Prompt and step volume by model"
      visible: Boolean(dataPayload && dataPayload.modelList && dataPayload.modelList.length > 0)

      ColumnLayout {
        width: parent.width
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
                text: (modelData.todayPrompts || 0) + " today · " + (modelData.prompts || 0) + " total"
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

    // Provider Quota Groups
    SectionCard {
      title: "Quota Limits"
      subtitle: dataPayload.tierLabel || ""
      visible: Boolean(dataPayload && dataPayload.quotaGroups && dataPayload.quotaGroups.length > 0)

      ColumnLayout {
        width: parent.width
        spacing: 6

        Repeater {
          model: dataPayload.quotaGroups || []
          delegate: ColumnLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 4

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
                    textFormat: Text.PlainText
                    text: modelData.remainingPercent + "%"
                    color: modelData.remainingPercent <= 15 ? root.urgent : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: 9
                    font.bold: true
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
                    width: parent.width * Math.max(0.0, Math.min(1.0, Number(modelData.remainingFraction || 0)))
                    radius: 2
                    color: modelData.remainingPercent <= 15 ? root.urgent : agentColor
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // --- SETTINGS VIEW CONTENT ---
  component SettingsContent: ColumnLayout {
    spacing: 8

    // Agent Enablement
    SectionCard {
      title: "Active AI Agents"
      subtitle: "Enable or disable agent integrations"

      ColumnLayout {
        width: parent.width
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
      }
    }

    // Live Hooks Installer
    SectionCard {
      title: "Live Hook Updates"
      subtitle: "Instant zero-latency bar refresh on agent session events"

      ColumnLayout {
        width: parent.width
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

    // Badge Mode Picker
    SectionCard {
      title: "Top Bar Badge Display"
      subtitle: "Metric shown in the bar widget badge pill"

      ColumnLayout {
        width: parent.width
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
        width: parent.width
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
