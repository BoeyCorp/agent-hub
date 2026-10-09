import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Rectangle {
  id: chartRoot
  property var dailyData: []
  property string metric: "tokens" // "tokens" | "cost" | "prompts"
  property int selectedIndex: -1
  property int hoveredIndex: -1

  property color claudeColor: "#D97757"
  property color antigravityColor: "#38BDF8"
  property color codexColor: "#10A37F"
  property color foregroundColor: "#D8DEE9"
  property color dimColor: "#6B6B6B"
  property color trackColor: Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.12)
  property color cardColor: Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.05)
  property bool isLightTheme: false
  property string fontFamily: "JetBrainsMono Nerd Font"

  signal daySelected(int index, var dayData)

  Layout.fillWidth: true
  Layout.preferredHeight: 250
  implicitHeight: 250
  radius: Style.cornerRadius
  color: cardColor
  border.color: isLightTheme ? Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.12)
                             : Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.05)
  border.width: 1

  readonly property real maxValue: {
    var m = 1
    if (!dailyData || dailyData.length === 0) return 1
    for (var i = 0; i < dailyData.length; i++) {
      var d = dailyData[i]
      var val = 0
      if (metric === "tokens") val = Number(d.tokens || 0)
      else if (metric === "cost") val = Number(d.cost || 0)
      else if (metric === "prompts") val = Number(d.prompts || 0)
      if (val > m) m = val
    }
    return m
  }

  function formatMetricValue(val) {
    if (metric === "tokens") {
      var n = Number(val || 0)
      if (n >= 1e9) return (n / 1e9).toFixed(2) + "B"
      if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
      if (n >= 1e3) return (n / 1e3).toFixed(1) + "K"
      return String(n)
    } else if (metric === "cost") {
      var c = Number(val || 0)
      if (c <= 0) return "$0.00"
      if (c < 0.01) return "<$0.01"
      return "$" + c.toFixed(2)
    } else {
      return String(val || 0) + " prompts"
    }
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 12
    spacing: 10

    // Top Header & Controls Row
    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      ColumnLayout {
        spacing: 1
        Layout.fillWidth: true

        Text {
          textFormat: Text.PlainText
          text: "30-Day Multi-Agent Activity Timeline"
          color: chartRoot.foregroundColor
          font.family: chartRoot.fontFamily
          font.pixelSize: 12
          font.bold: true
        }

        Text {
          textFormat: Text.PlainText
          text: "Daily cross-agent volume and comparative workload distribution"
          color: chartRoot.dimColor
          font.family: chartRoot.fontFamily
          font.pixelSize: 9
        }
      }

      // Legend
      RowLayout {
        spacing: 10
        Layout.alignment: Qt.AlignVCenter

        RowLayout {
          spacing: 4
          Rectangle { width: 8; height: 8; radius: 2; color: chartRoot.claudeColor }
          Text { textFormat: Text.PlainText; text: "Claude"; color: chartRoot.dimColor; font.family: chartRoot.fontFamily; font.pixelSize: 9 }
        }
        RowLayout {
          spacing: 4
          Rectangle { width: 8; height: 8; radius: 2; color: chartRoot.antigravityColor }
          Text { textFormat: Text.PlainText; text: "Antigravity"; color: chartRoot.dimColor; font.family: chartRoot.fontFamily; font.pixelSize: 9 }
        }
        RowLayout {
          spacing: 4
          Rectangle { width: 8; height: 8; radius: 2; color: chartRoot.codexColor }
          Text { textFormat: Text.PlainText; text: "Codex"; color: chartRoot.dimColor; font.family: chartRoot.fontFamily; font.pixelSize: 9 }
        }
      }

      // Metric Switcher Tabs
      Rectangle {
        Layout.preferredHeight: 24
        Layout.preferredWidth: 200
        radius: 4
        color: chartRoot.trackColor

        RowLayout {
          anchors.fill: parent
          anchors.margins: 2
          spacing: 2

          Repeater {
            model: [
              { id: "tokens", label: "Tokens" },
              { id: "cost", label: "Cost ($)" },
              { id: "prompts", label: "Prompts" }
            ]
            delegate: Rectangle {
              required property var modelData
              Layout.fillWidth: true
              Layout.fillHeight: true
              radius: 3
              readonly property bool isSelected: chartRoot.metric === modelData.id
              color: isSelected ? Qt.rgba(chartRoot.foregroundColor.r, chartRoot.foregroundColor.g, chartRoot.foregroundColor.b, chartRoot.isLightTheme ? 0.25 : 0.15)
                                : (mMouse.containsMouse ? Qt.rgba(chartRoot.foregroundColor.r, chartRoot.foregroundColor.g, chartRoot.foregroundColor.b, 0.08) : "transparent")

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: modelData.label
                color: isSelected ? chartRoot.foregroundColor : chartRoot.dimColor
                font.family: chartRoot.fontFamily
                font.pixelSize: 9
                font.bold: isSelected
              }

              MouseArea {
                id: mMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: chartRoot.metric = modelData.id
              }
            }
          }
        }
      }
    }

    // Chart Canvas Area
    Item {
      id: chartArea
      Layout.fillWidth: true
      Layout.fillHeight: true

      // Horizontal Grid Baseline
      Rectangle {
        anchors.bottom: dateRow.top
        anchors.bottomMargin: 4
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: chartRoot.trackColor
      }

      // 30 Columns Layout
      RowLayout {
        id: barsRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: dateRow.top
        anchors.bottomMargin: 6
        spacing: 3

        Repeater {
          model: chartRoot.dailyData || []

          delegate: Item {
            id: colDelegate
            required property var modelData
            required property int index
            Layout.fillWidth: true
            Layout.fillHeight: true

            readonly property var ag: modelData ? modelData.agents : null
            readonly property real cVal: Number(ag && ag.claude ? (chartRoot.metric === "cost" ? ag.claude.cost : (chartRoot.metric === "prompts" ? ag.claude.prompts : ag.claude.tokens)) : 0)
            readonly property real aVal: Number(ag && ag.antigravity ? (chartRoot.metric === "cost" ? ag.antigravity.cost : (chartRoot.metric === "prompts" ? ag.antigravity.prompts : ag.antigravity.tokens)) : 0)
            readonly property real xVal: Number(ag && ag.codex ? (chartRoot.metric === "cost" ? ag.codex.cost : (chartRoot.metric === "prompts" ? ag.codex.prompts : ag.codex.tokens)) : 0)
            readonly property real totalVal: cVal + aVal + xVal

            readonly property bool isSelected: chartRoot.selectedIndex === index
            readonly property bool isHovered: chartRoot.hoveredIndex === index

            // Selection / Hover Highlight Pill
            Rectangle {
              anchors.fill: parent
              radius: 3
              color: isSelected ? Qt.rgba(chartRoot.foregroundColor.r, chartRoot.foregroundColor.g, chartRoot.foregroundColor.b, chartRoot.isLightTheme ? 0.16 : 0.12)
                                : (isHovered ? Qt.rgba(chartRoot.foregroundColor.r, chartRoot.foregroundColor.g, chartRoot.foregroundColor.b, 0.06) : "transparent")
            }

            // Stacked Bar Container
            Item {
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: 1
              anchors.rightMargin: 1
              height: Math.max(totalVal > 0 ? 3 : 1, (totalVal / chartRoot.maxValue) * (colDelegate.height - 4))

              ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Codex Segment (Top)
                Rectangle {
                  visible: xVal > 0
                  Layout.fillWidth: true
                  Layout.preferredHeight: Math.max(1, (xVal / Math.max(0.001, totalVal)) * parent.height)
                  color: chartRoot.codexColor
                  radius: (cVal === 0 && aVal === 0) ? 2 : 0
                }

                // Antigravity Segment (Middle)
                Rectangle {
                  visible: aVal > 0
                  Layout.fillWidth: true
                  Layout.preferredHeight: Math.max(1, (aVal / Math.max(0.001, totalVal)) * parent.height)
                  color: chartRoot.antigravityColor
                  radius: (xVal === 0 && cVal === 0) ? 2 : 0
                }

                // Claude Segment (Bottom)
                Rectangle {
                  visible: cVal > 0
                  Layout.fillWidth: true
                  Layout.preferredHeight: Math.max(1, (cVal / Math.max(0.001, totalVal)) * parent.height)
                  color: chartRoot.claudeColor
                  radius: (xVal === 0 && aVal === 0) ? 2 : 0
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: chartRoot.hoveredIndex = index
              onExited: if (chartRoot.hoveredIndex === index) chartRoot.hoveredIndex = -1
              onClicked: {
                chartRoot.selectedIndex = index
                chartRoot.daySelected(index, modelData)
              }
            }
          }
        }
      }

      // Dates Row beneath bars
      RowLayout {
        id: dateRow
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 14
        spacing: 3

        Repeater {
          model: chartRoot.dailyData || []
          delegate: Item {
            required property var modelData
            required property int index
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Show label every 5 days or first/last
            readonly property bool showLabel: (index === 0) || (index === chartRoot.dailyData.length - 1) || (index % 5 === 0)

            Text {
              visible: showLabel
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: {
                var d = modelData ? modelData.date : ""
                if (!d) return ""
                var parts = d.split("-")
                return parts.length === 3 ? (parts[1] + "/" + parts[2]) : d
              }
              color: chartRoot.dimColor
              font.family: chartRoot.fontFamily
              font.pixelSize: 8
            }
          }
        }
      }

      // Hover Tooltip Popover
      Rectangle {
        id: tooltipBox
        visible: chartRoot.hoveredIndex >= 0 && chartRoot.hoveredIndex < (chartRoot.dailyData ? chartRoot.dailyData.length : 0)
        z: 99
        radius: 4
        color: chartRoot.isLightTheme ? "#FFFFFF" : "#1A1B26"
        border.color: chartRoot.isLightTheme ? Qt.rgba(0, 0, 0, 0.15) : Qt.rgba(1, 1, 1, 0.18)
        border.width: 1
        implicitWidth: 160
        implicitHeight: tCol.implicitHeight + 12

        readonly property var hoverDay: visible ? chartRoot.dailyData[chartRoot.hoveredIndex] : null

        x: {
          if (!visible || !barsRow) return 0
          var w = barsRow.width / Math.max(1, chartRoot.dailyData.length)
          var posX = chartRoot.hoveredIndex * w
          return Math.max(6, Math.min(chartArea.width - implicitWidth - 6, posX - implicitWidth / 2 + w / 2))
        }
        y: 6

        ColumnLayout {
          id: tCol
          anchors.fill: parent
          anchors.margins: 6
          spacing: 3

          RowLayout {
            Layout.fillWidth: true
            Text {
              textFormat: Text.PlainText
              text: tooltipBox.hoverDay ? (tooltipBox.hoverDay.date + " (" + tooltipBox.hoverDay.dayOfWeek + ")") : ""
              color: chartRoot.foregroundColor
              font.family: chartRoot.fontFamily
              font.pixelSize: 9
              font.bold: true
              Layout.fillWidth: true
            }
          }

          Text {
            textFormat: Text.PlainText
            text: tooltipBox.hoverDay ? ("Total: " + chartRoot.formatMetricValue(chartRoot.metric === "cost" ? tooltipBox.hoverDay.cost : (chartRoot.metric === "prompts" ? tooltipBox.hoverDay.prompts : tooltipBox.hoverDay.tokens))) : ""
            color: chartRoot.foregroundColor
            font.family: chartRoot.fontFamily
            font.pixelSize: 9
            font.bold: true
          }

          Rectangle { Layout.fillWidth: true; height: 1; color: chartRoot.trackColor }

          RowLayout {
            spacing: 4
            Rectangle { width: 6; height: 6; radius: 1; color: chartRoot.claudeColor }
            Text {
              textFormat: Text.PlainText
              text: "Claude: " + (tooltipBox.hoverDay && tooltipBox.hoverDay.agents && tooltipBox.hoverDay.agents.claude ? chartRoot.formatMetricValue(chartRoot.metric === "cost" ? tooltipBox.hoverDay.agents.claude.cost : (chartRoot.metric === "prompts" ? tooltipBox.hoverDay.agents.claude.prompts : tooltipBox.hoverDay.agents.claude.tokens)) : "0")
              color: chartRoot.dimColor
              font.family: chartRoot.fontFamily
              font.pixelSize: 8
            }
          }

          RowLayout {
            spacing: 4
            Rectangle { width: 6; height: 6; radius: 1; color: chartRoot.antigravityColor }
            Text {
              textFormat: Text.PlainText
              text: "AGY: " + (tooltipBox.hoverDay && tooltipBox.hoverDay.agents && tooltipBox.hoverDay.agents.antigravity ? chartRoot.formatMetricValue(chartRoot.metric === "cost" ? tooltipBox.hoverDay.agents.antigravity.cost : (chartRoot.metric === "prompts" ? tooltipBox.hoverDay.agents.antigravity.prompts : tooltipBox.hoverDay.agents.antigravity.tokens)) : "0")
              color: chartRoot.dimColor
              font.family: chartRoot.fontFamily
              font.pixelSize: 8
            }
          }

          RowLayout {
            spacing: 4
            Rectangle { width: 6; height: 6; radius: 1; color: chartRoot.codexColor }
            Text {
              textFormat: Text.PlainText
              text: "Codex: " + (tooltipBox.hoverDay && tooltipBox.hoverDay.agents && tooltipBox.hoverDay.agents.codex ? chartRoot.formatMetricValue(chartRoot.metric === "cost" ? tooltipBox.hoverDay.agents.codex.cost : (chartRoot.metric === "prompts" ? tooltipBox.hoverDay.agents.codex.prompts : tooltipBox.hoverDay.agents.codex.tokens)) : "0")
              color: chartRoot.dimColor
              font.family: chartRoot.fontFamily
              font.pixelSize: 8
            }
          }
        }
      }
    }
  }
}
