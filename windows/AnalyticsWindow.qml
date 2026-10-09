import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "../components/analytics"

FloatingWindow {
  id: root
  title: "Agent Hub — Monthly Usage & Analytics"
  color: root.background
  minimumSize: Qt.size(860, 580)
  implicitWidth: 1080
  implicitHeight: 740

  // FloatingWindow already provides closed() signal
  onClosed: {
    // Notify host if needed
  }

  // Theme bindings matching Widget.qml
  property color foreground: (Color.popups && Color.popups.foreground) ? Color.popups.foreground : (Color.foreground || "#D8DEE9")
  property color background: (Color.popups && Color.popups.background) ? Color.popups.background : (Color.background || "#1E1E2E")
  property color accent: Color.accent || "#89B4FA"
  property string fontFamily: "JetBrainsMono Nerd Font"

  readonly property bool isLightTheme: {
    var bgLum = (background.r * 0.299 + background.g * 0.587 + background.b * 0.114)
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
  readonly property color track: Qt.rgba(foreground.r, foreground.g, foreground.b, isLightTheme ? 0.12 : 0.24)

  // Contrast-aware agent brand hues
  readonly property color claudeColor: isLightTheme ? "#C2410C" : "#D97757"
  readonly property color antigravityColor: isLightTheme ? "#0284C7" : "#38BDF8"
  readonly property color codexColor: isLightTheme ? "#059669" : "#10A37F"

  AnalyticsProvider {
    id: provider
  }

  FocusScope {
    id: windowFocusScope
    anchors.fill: parent
    focus: true

    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) {
        root.visible = false
        root.closed()
        event.accepted = true
      } else if (event.key === Qt.Key_R || event.key === Qt.Key_F5) {
        provider.refresh(true)
        event.accepted = true
      } else if (event.key === Qt.Key_Left) {
        if (provider.daily && provider.daily.length > 0) {
          provider.selectedDayIndex = Math.max(0, provider.selectedDayIndex - 1)
        }
        event.accepted = true
      } else if (event.key === Qt.Key_Right) {
        if (provider.daily && provider.daily.length > 0) {
          provider.selectedDayIndex = Math.min(provider.daily.length - 1, provider.selectedDayIndex + 1)
        }
        event.accepted = true
      }
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 16
      spacing: 12

      // Top Header Toolbar
      RowLayout {
        Layout.fillWidth: true
        spacing: 10

        // App Icon
        Image {
          source: Qt.resolvedUrl("../assets/agent-hub.svg")
          sourceSize.width: 22
          sourceSize.height: 22
          Layout.preferredWidth: 22
          Layout.preferredHeight: 22
          fillMode: Image.PreserveAspectFit
        }

        ColumnLayout {
          spacing: 1
          Layout.fillWidth: true

          RowLayout {
            spacing: 6
            Text {
              textFormat: Text.PlainText
              text: "Agent Hub"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 14
              font.bold: true
            }
            Text {
              textFormat: Text.PlainText
              text: "·"
              color: root.dim
              font.pixelSize: 12
            }
            Text {
              textFormat: Text.PlainText
              text: "Monthly Telemetry & Analytics"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: 12
            }
          }

          Text {
            textFormat: Text.PlainText
            text: provider.period ? (provider.period.label + ": " + provider.period.start + " to " + provider.period.end) : "Last 30 Days"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: 9
          }
        }

        // Action Buttons
        RowLayout {
          spacing: 6

          // Refresh Button
          Rectangle {
            radius: 4
            color: refMouse.containsMouse ? root.cardHover : root.track
            Layout.preferredHeight: 26
            Layout.preferredWidth: 26

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: ""
              color: provider.loading ? root.accent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: 12
              transformOrigin: Item.Center

              RotationAnimation on rotation {
                running: provider.loading
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
              onClicked: provider.refresh(true)
            }
          }

          // Close Button
          Rectangle {
            radius: 4
            color: closeMouse.containsMouse ? root.cardHover : root.track
            Layout.preferredHeight: 26
            Layout.preferredWidth: 26

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "✕"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 11
            }

            MouseArea {
              id: closeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.visible = false
                root.closed()
              }
            }
          }
        }
      }

      // KPI Ribbon (4 Cards)
      RowLayout {
        Layout.fillWidth: true
        spacing: 10

        KpiCard {
          title: "Total Tokens"
          value: provider.summary ? provider.formatNumber(provider.summary.totalTokens) : "0"
          subtitle: provider.summary ? (provider.formatNumber(provider.summary.totalInputTokens) + " in · " + provider.formatNumber(provider.summary.totalOutputTokens) + " out") : ""
          iconText: "󱐋"
          accentColor: root.accent
          foregroundColor: root.foreground
          dimColor: root.dim
          isLightTheme: root.isLightTheme
          fontFamily: root.fontFamily
        }

        KpiCard {
          title: "Estimated Cost"
          value: provider.summary ? provider.formatCost(provider.summary.totalCost) : "$0.00"
          subtitle: provider.summary ? ("Avg " + provider.formatCost(provider.summary.avgDailyCost) + " / day") : ""
          iconText: "$"
          accentColor: "#10B981"
          foregroundColor: root.foreground
          dimColor: root.dim
          isLightTheme: root.isLightTheme
          fontFamily: root.fontFamily
        }

        KpiCard {
          title: "Prompts & Turns"
          value: provider.summary ? (provider.formatNumber(provider.summary.totalPrompts) + " prompts") : "0"
          subtitle: provider.summary ? (provider.formatNumber(provider.summary.totalSteps) + " steps across " + provider.summary.activeDaysCount + " active days") : ""
          iconText: ""
          accentColor: root.antigravityColor
          foregroundColor: root.foreground
          dimColor: root.dim
          isLightTheme: root.isLightTheme
          fontFamily: root.fontFamily
        }

        KpiCard {
          title: "Cache Efficiency"
          value: provider.summary ? (provider.summary.overallCacheHitRate + "%") : "0%"
          subtitle: provider.summary ? (provider.formatNumber(provider.summary.totalCacheReadTokens) + " cached tokens saved") : ""
          iconText: "⚡"
          accentColor: root.claudeColor
          foregroundColor: root.foreground
          dimColor: root.dim
          isLightTheme: root.isLightTheme
          fontFamily: root.fontFamily
        }
      }

      // Main Chart: 30-Day Multi-Agent Stacked Timeline
      MonthlyStackedChart {
        id: mainChart
        dailyData: provider.daily || []
        selectedIndex: provider.selectedDayIndex
        claudeColor: root.claudeColor
        antigravityColor: root.antigravityColor
        codexColor: root.codexColor
        foregroundColor: root.foreground
        dimColor: root.dim
        trackColor: root.track
        isLightTheme: root.isLightTheme
        fontFamily: root.fontFamily
        onDaySelected: function(idx, data) {
          provider.selectedDayIndex = idx
        }
      }

      // Bottom Dual-Pane Row
      RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 10

        // Left Pane: Heatmap & Workload Share
        ColumnLayout {
          Layout.fillWidth: true
          Layout.preferredWidth: 5
          Layout.fillHeight: true
          spacing: 10

          ActivityHeatmap {
            heatmapData: provider.heatmap || []
            accentColor: root.accent
            foregroundColor: root.foreground
            dimColor: root.dim
            trackColor: root.track
            isLightTheme: root.isLightTheme
            fontFamily: root.fontFamily
            onDayClicked: function(dStr) {
              provider.selectDayByDate(dStr)
            }
          }

          AgentShareCard {
            byAgent: provider.byAgent
            claudeColor: root.claudeColor
            antigravityColor: root.antigravityColor
            codexColor: root.codexColor
            foregroundColor: root.foreground
            dimColor: root.dim
            trackColor: root.track
            isLightTheme: root.isLightTheme
            fontFamily: root.fontFamily
          }
        }

        // Right Pane: Selected Day Inspector
        ColumnLayout {
          Layout.fillWidth: true
          Layout.preferredWidth: 4
          Layout.fillHeight: true

          DayInspector {
            dayData: provider.selectedDay
            claudeColor: root.claudeColor
            antigravityColor: root.antigravityColor
            codexColor: root.codexColor
            foregroundColor: root.foreground
            dimColor: root.dim
            trackColor: root.track
            isLightTheme: root.isLightTheme
            fontFamily: root.fontFamily
          }
        }
      }
    }
  }
}
