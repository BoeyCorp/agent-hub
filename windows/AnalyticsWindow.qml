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

  property alias provider: provider

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

  property bool showDateRangePicker: false
  property string inputStartDate: ""
  property string inputEndDate: ""

  AnalyticsProvider {
    id: provider
  }

  Connections {
    target: provider
    function onPayloadChanged() {
      if (provider.period) {
        root.inputStartDate = provider.period.start
        root.inputEndDate = provider.period.end
      }
    }
  }

  FocusScope {
    id: windowFocusScope
    anchors.fill: parent
    focus: true

    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) {
        if (root.showDateRangePicker) {
          root.showDateRangePicker = false
          event.accepted = true
          return
        }
        root.visible = false
        root.closed()
        event.accepted = true
      } else if (event.key === Qt.Key_R || event.key === Qt.Key_F5) {
        provider.refresh(true)
        event.accepted = true
      } else if (event.key === Qt.Key_1) {
        root.showDateRangePicker = false
        provider.setDays(30)
        event.accepted = true
      } else if (event.key === Qt.Key_2) {
        root.showDateRangePicker = false
        provider.setDays(60)
        event.accepted = true
      } else if (event.key === Qt.Key_3) {
        root.showDateRangePicker = false
        provider.setDays(90)
        event.accepted = true
      } else if (event.key === Qt.Key_C) {
        root.showDateRangePicker = !root.showDateRangePicker
        if (root.showDateRangePicker && provider.period) {
          if (!root.inputStartDate || provider.viewMode !== "custom") root.inputStartDate = provider.period.start
          if (!root.inputEndDate || provider.viewMode !== "custom") root.inputEndDate = provider.period.end
        }
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
            text: provider.period ? (provider.period.label + " (" + provider.period.start + " to " + provider.period.end + ") · " + provider.period.daysCount + " days") : "Last 30 Days"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: 9
          }
        }

        // Period Views: 30D | 60D | 90D |  Custom
        RowLayout {
          spacing: 4
          Layout.alignment: Qt.AlignVCenter

          Repeater {
            model: [
              { label: "30D", days: 30 },
              { label: "60D", days: 60 },
              { label: "90D", days: 90 }
            ]
            delegate: Rectangle {
              required property var modelData
              required property int index
              readonly property bool isActive: provider.viewMode === String(modelData.days)
              radius: 4
              color: isActive ? root.accent : (pMouse.containsMouse ? root.cardHover : root.track)
              Layout.preferredHeight: 26
              Layout.preferredWidth: 42

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: modelData.label
                color: isActive ? (root.isLightTheme ? "#FFFFFF" : "#0F141C") : root.foreground
                font.family: root.fontFamily
                font.pixelSize: 10
                font.bold: isActive
              }

              MouseArea {
                id: pMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.showDateRangePicker = false
                  provider.setDays(modelData.days)
                }
              }
            }
          }

          // Custom Date Range Toggle Button
          Rectangle {
            id: customBtnRec
            readonly property bool isActive: provider.viewMode === "custom" || root.showDateRangePicker
            radius: 4
            color: customBtnRec.isActive ? root.accent : (cMouse.containsMouse ? root.cardHover : root.track)
            Layout.preferredHeight: 26
            Layout.preferredWidth: 76

            RowLayout {
              anchors.centerIn: parent
              spacing: 4

              Text {
                textFormat: Text.PlainText
                text: ""
                color: customBtnRec.isActive ? (root.isLightTheme ? "#FFFFFF" : "#0F141C") : root.foreground
                font.family: root.fontFamily
                font.pixelSize: 10
              }

              Text {
                textFormat: Text.PlainText
                text: "Custom"
                color: customBtnRec.isActive ? (root.isLightTheme ? "#FFFFFF" : "#0F141C") : root.foreground
                font.family: root.fontFamily
                font.pixelSize: 10
                font.bold: customBtnRec.isActive
              }
            }

            MouseArea {
              id: cMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.showDateRangePicker = !root.showDateRangePicker
                if (root.showDateRangePicker && provider.period) {
                  if (!root.inputStartDate || provider.viewMode !== "custom") root.inputStartDate = provider.period.start
                  if (!root.inputEndDate || provider.viewMode !== "custom") root.inputEndDate = provider.period.end
                }
              }
            }
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

      // Expandable Custom Date Range Selector Bar
      Rectangle {
        visible: root.showDateRangePicker
        Layout.fillWidth: true
        Layout.preferredHeight: 44
        radius: 6
        color: root.cardHover
        border.color: root.accent
        border.width: 1

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: 12
          anchors.rightMargin: 12
          spacing: 10

          Text {
            textFormat: Text.PlainText
            text: "Date Range:"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 10
            font.bold: true
          }

          // From Date Box
          RowLayout {
            spacing: 4
            Text {
              textFormat: Text.PlainText
              text: "From"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: 9
            }
            Rectangle {
              radius: 4
              color: root.background
              border.color: startInput.activeFocus ? root.accent : root.track
              border.width: 1
              Layout.preferredWidth: 104
              Layout.preferredHeight: 26

              TextInput {
                id: startInput
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                verticalAlignment: TextInput.AlignVCenter
                text: root.inputStartDate
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: 10
                selectByMouse: true
                onTextChanged: root.inputStartDate = text
              }
            }
          }

          // To Date Box
          RowLayout {
            spacing: 4
            Text {
              textFormat: Text.PlainText
              text: "To"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: 9
            }
            Rectangle {
              radius: 4
              color: root.background
              border.color: endInput.activeFocus ? root.accent : root.track
              border.width: 1
              Layout.preferredWidth: 104
              Layout.preferredHeight: 26

              TextInput {
                id: endInput
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                verticalAlignment: TextInput.AlignVCenter
                text: root.inputEndDate
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: 10
                selectByMouse: true
                onTextChanged: root.inputEndDate = text
              }
            }
          }

          // Quick Presets: [This Month] [Last Month] [Last 14d]
          RowLayout {
            spacing: 4

            // "This Month"
            Rectangle {
              radius: 3
              color: tmMouse.containsMouse ? root.track : "transparent"
              border.color: root.track
              border.width: 1
              Layout.preferredHeight: 24
              Layout.preferredWidth: 76

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "This Month"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: 9
              }
              MouseArea {
                id: tmMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  var now = new Date()
                  var y = now.getFullYear()
                  var m = (now.getMonth() + 1 < 10 ? "0" : "") + (now.getMonth() + 1)
                  var d = (now.getDate() < 10 ? "0" : "") + now.getDate()
                  root.inputStartDate = y + "-" + m + "-01"
                  root.inputEndDate = y + "-" + m + "-" + d
                }
              }
            }

            // "Last Month"
            Rectangle {
              radius: 3
              color: lmMouse.containsMouse ? root.track : "transparent"
              border.color: root.track
              border.width: 1
              Layout.preferredHeight: 24
              Layout.preferredWidth: 76

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "Last Month"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: 9
              }
              MouseArea {
                id: lmMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  var now = new Date()
                  var prevMonthLastDay = new Date(now.getFullYear(), now.getMonth(), 0)
                  var prevMonthFirstDay = new Date(prevMonthLastDay.getFullYear(), prevMonthLastDay.getMonth(), 1)
                  function fmt(dtObj) {
                    var yr = dtObj.getFullYear()
                    var mo = (dtObj.getMonth() + 1 < 10 ? "0" : "") + (dtObj.getMonth() + 1)
                    var dy = (dtObj.getDate() < 10 ? "0" : "") + dtObj.getDate()
                    return yr + "-" + mo + "-" + dy
                  }
                  root.inputStartDate = fmt(prevMonthFirstDay)
                  root.inputEndDate = fmt(prevMonthLastDay)
                }
              }
            }

            // "Last 14d"
            Rectangle {
              radius: 3
              color: l14Mouse.containsMouse ? root.track : "transparent"
              border.color: root.track
              border.width: 1
              Layout.preferredHeight: 24
              Layout.preferredWidth: 64

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "Last 14d"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: 9
              }
              MouseArea {
                id: l14Mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  var now = new Date()
                  var past = new Date(now.getTime() - 13 * 86400000)
                  function fmt(dtObj) {
                    var yr = dtObj.getFullYear()
                    var mo = (dtObj.getMonth() + 1 < 10 ? "0" : "") + (dtObj.getMonth() + 1)
                    var dy = (dtObj.getDate() < 10 ? "0" : "") + dtObj.getDate()
                    return yr + "-" + mo + "-" + dy
                  }
                  root.inputStartDate = fmt(past)
                  root.inputEndDate = fmt(now)
                }
              }
            }
          }

          Item { Layout.fillWidth: true }

          // Apply Button
          Rectangle {
            radius: 4
            color: root.accent
            Layout.preferredHeight: 26
            Layout.preferredWidth: 64

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "Apply"
              color: root.isLightTheme ? "#FFFFFF" : "#0F141C"
              font.family: root.fontFamily
              font.pixelSize: 10
              font.bold: true
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (root.inputStartDate && root.inputEndDate) {
                  provider.setCustomRange(root.inputStartDate, root.inputEndDate)
                }
              }
            }
          }

          // Close Drawer Button
          Rectangle {
            radius: 4
            color: closeDrawerMouse.containsMouse ? root.track : "transparent"
            Layout.preferredHeight: 24
            Layout.preferredWidth: 24

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "✕"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: 9
            }

            MouseArea {
              id: closeDrawerMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.showDateRangePicker = false
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
