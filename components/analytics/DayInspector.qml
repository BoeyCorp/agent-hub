import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Rectangle {
  id: inspectRoot
  property var dayData: null
  property color claudeColor: "#D97757"
  property color antigravityColor: "#38BDF8"
  property color codexColor: "#10A37F"
  property color foregroundColor: "#D8DEE9"
  property color dimColor: "#6B6B6B"
  property color trackColor: Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.12)
  property color cardColor: Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.05)
  property bool isLightTheme: false
  property string fontFamily: "JetBrainsMono Nerd Font"

  Layout.fillWidth: true
  Layout.fillHeight: true
  radius: Style.cornerRadius
  color: cardColor
  border.color: isLightTheme ? Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.12)
                             : Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.05)
  border.width: 1

  function formatNumber(n) {
    if (n === undefined || n === null) return "0"
    var num = Number(n)
    if (num >= 1e9) return (num / 1e9).toFixed(2) + "B"
    if (num >= 1e6) return (num / 1e6).toFixed(1) + "M"
    if (num >= 1e3) return (num / 1e3).toFixed(1) + "K"
    return String(num)
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 12
    spacing: 8

    // Date Header
    RowLayout {
      Layout.fillWidth: true
      spacing: 6

      Text {
        textFormat: Text.PlainText
        text: inspectRoot.dayData ? (inspectRoot.dayData.dayOfWeek + " · " + inspectRoot.dayData.date) : "Select a Day"
        color: inspectRoot.foregroundColor
        font.family: inspectRoot.fontFamily
        font.pixelSize: 12
        font.bold: true
        Layout.fillWidth: true
      }

      Rectangle {
        visible: Boolean(inspectRoot.dayData && inspectRoot.dayData.topModel)
        radius: 3
        color: Qt.rgba(inspectRoot.foregroundColor.r, inspectRoot.foregroundColor.g, inspectRoot.foregroundColor.b, 0.10)
        implicitHeight: 18
        implicitWidth: modelLabel.implicitWidth + 8

        Text {
          id: modelLabel
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: inspectRoot.dayData ? inspectRoot.dayData.topModel : ""
          color: inspectRoot.foregroundColor
          font.family: inspectRoot.fontFamily
          font.pixelSize: 8
          font.bold: true
        }
      }
    }

    // Mini Stat Tiles
    RowLayout {
      Layout.fillWidth: true
      spacing: 6

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 46
        radius: 3
        color: inspectRoot.trackColor
        ColumnLayout {
          anchors.centerIn: parent
          spacing: 1
          Text { textFormat: Text.PlainText; text: inspectRoot.dayData ? String(inspectRoot.dayData.prompts || 0) : "0"; color: inspectRoot.foregroundColor; font.family: inspectRoot.fontFamily; font.pixelSize: 12; font.bold: true; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
          Text { textFormat: Text.PlainText; text: "PROMPTS"; color: inspectRoot.dimColor; font.family: inspectRoot.fontFamily; font.pixelSize: 7; font.bold: true; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 46
        radius: 3
        color: inspectRoot.trackColor
        ColumnLayout {
          anchors.centerIn: parent
          spacing: 1
          Text { textFormat: Text.PlainText; text: inspectRoot.dayData ? String(inspectRoot.dayData.steps || 0) : "0"; color: inspectRoot.foregroundColor; font.family: inspectRoot.fontFamily; font.pixelSize: 12; font.bold: true; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
          Text { textFormat: Text.PlainText; text: "TURNS"; color: inspectRoot.dimColor; font.family: inspectRoot.fontFamily; font.pixelSize: 7; font.bold: true; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 46
        radius: 3
        color: inspectRoot.trackColor
        ColumnLayout {
          anchors.centerIn: parent
          spacing: 1
          Text { textFormat: Text.PlainText; text: inspectRoot.dayData ? inspectRoot.formatNumber(inspectRoot.dayData.tokens || 0) : "0"; color: inspectRoot.foregroundColor; font.family: inspectRoot.fontFamily; font.pixelSize: 12; font.bold: true; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
          Text { textFormat: Text.PlainText; text: "TOKENS"; color: inspectRoot.dimColor; font.family: inspectRoot.fontFamily; font.pixelSize: 7; font.bold: true; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 46
        radius: 3
        color: inspectRoot.trackColor
        ColumnLayout {
          anchors.centerIn: parent
          spacing: 1
          Text { textFormat: Text.PlainText; text: "$" + (inspectRoot.dayData ? Number(inspectRoot.dayData.cost || 0).toFixed(2) : "0.00"); color: inspectRoot.foregroundColor; font.family: inspectRoot.fontFamily; font.pixelSize: 12; font.bold: true; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
          Text { textFormat: Text.PlainText; text: "EST. COST"; color: inspectRoot.dimColor; font.family: inspectRoot.fontFamily; font.pixelSize: 7; font.bold: true; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
        }
      }
    }

    // Cache Efficiency Pill
    Rectangle {
      visible: Boolean(inspectRoot.dayData && inspectRoot.dayData.cacheReadTokens > 0)
      Layout.fillWidth: true
      Layout.preferredHeight: 22
      radius: 3
      color: Qt.rgba(inspectRoot.foregroundColor.r, inspectRoot.foregroundColor.g, inspectRoot.foregroundColor.b, 0.06)

      RowLayout {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 6

        Text {
          textFormat: Text.PlainText
          text: "⚡ Cache:"
          color: inspectRoot.foregroundColor
          font.family: inspectRoot.fontFamily
          font.pixelSize: 9
          font.bold: true
        }

        Text {
          textFormat: Text.PlainText
          text: (inspectRoot.dayData ? inspectRoot.dayData.cacheHitRate : 0) + "% hit rate"
          color: inspectRoot.dimColor
          font.family: inspectRoot.fontFamily
          font.pixelSize: 9
        }

        Text {
          textFormat: Text.PlainText
          text: "· " + inspectRoot.formatNumber(inspectRoot.dayData ? inspectRoot.dayData.cacheReadTokens : 0) + " cached"
          color: inspectRoot.dimColor
          font.family: inspectRoot.fontFamily
          font.pixelSize: 9
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
      }
    }

    // Per-Agent Day Details
    ColumnLayout {
      Layout.fillWidth: true
      spacing: 6

      // Claude
      RowLayout {
        id: claudeRow
        Layout.fillWidth: true
        spacing: 6
        readonly property var cData: inspectRoot.dayData && inspectRoot.dayData.agents ? inspectRoot.dayData.agents.claude : null
        Rectangle { width: 8; height: 8; radius: 2; color: inspectRoot.claudeColor }
        Text { textFormat: Text.PlainText; text: "Claude Code"; color: inspectRoot.foregroundColor; font.family: inspectRoot.fontFamily; font.pixelSize: 9; font.bold: true; Layout.preferredWidth: 80 }
        Text { textFormat: Text.PlainText; text: (claudeRow.cData ? String(claudeRow.cData.prompts) : "0") + " prompts"; color: inspectRoot.dimColor; font.family: inspectRoot.fontFamily; font.pixelSize: 9; Layout.preferredWidth: 70 }
        Text { textFormat: Text.PlainText; text: (claudeRow.cData ? inspectRoot.formatNumber(claudeRow.cData.tokens) : "0") + " tok"; color: inspectRoot.dimColor; font.family: inspectRoot.fontFamily; font.pixelSize: 9; Layout.fillWidth: true }
        Text { textFormat: Text.PlainText; text: "$" + (claudeRow.cData ? Number(claudeRow.cData.cost).toFixed(2) : "0.00"); color: inspectRoot.claudeColor; font.family: inspectRoot.fontFamily; font.pixelSize: 9; font.bold: true }
      }

      // Antigravity
      RowLayout {
        id: agyRow
        Layout.fillWidth: true
        spacing: 6
        readonly property var aData: inspectRoot.dayData && inspectRoot.dayData.agents ? inspectRoot.dayData.agents.antigravity : null
        Rectangle { width: 8; height: 8; radius: 2; color: inspectRoot.antigravityColor }
        Text { textFormat: Text.PlainText; text: "Antigravity"; color: inspectRoot.foregroundColor; font.family: inspectRoot.fontFamily; font.pixelSize: 9; font.bold: true; Layout.preferredWidth: 80 }
        Text { textFormat: Text.PlainText; text: (agyRow.aData ? String(agyRow.aData.prompts) : "0") + " prompts"; color: inspectRoot.dimColor; font.family: inspectRoot.fontFamily; font.pixelSize: 9; Layout.preferredWidth: 70 }
        Text { textFormat: Text.PlainText; text: (agyRow.aData ? inspectRoot.formatNumber(agyRow.aData.tokens) : "0") + " tok"; color: inspectRoot.dimColor; font.family: inspectRoot.fontFamily; font.pixelSize: 9; Layout.fillWidth: true }
        Text { textFormat: Text.PlainText; text: "$" + (agyRow.aData ? Number(agyRow.aData.cost).toFixed(2) : "0.00"); color: inspectRoot.antigravityColor; font.family: inspectRoot.fontFamily; font.pixelSize: 9; font.bold: true }
      }

      // Codex
      RowLayout {
        id: codexRow
        Layout.fillWidth: true
        spacing: 6
        readonly property var xData: inspectRoot.dayData && inspectRoot.dayData.agents ? inspectRoot.dayData.agents.codex : null
        Rectangle { width: 8; height: 8; radius: 2; color: inspectRoot.codexColor }
        Text { textFormat: Text.PlainText; text: "OpenAI Codex"; color: inspectRoot.foregroundColor; font.family: inspectRoot.fontFamily; font.pixelSize: 9; font.bold: true; Layout.preferredWidth: 80 }
        Text { textFormat: Text.PlainText; text: (codexRow.xData ? String(codexRow.xData.prompts) : "0") + " prompts"; color: inspectRoot.dimColor; font.family: inspectRoot.fontFamily; font.pixelSize: 9; Layout.preferredWidth: 70 }
        Text { textFormat: Text.PlainText; text: (codexRow.xData ? inspectRoot.formatNumber(codexRow.xData.tokens) : "0") + " tok"; color: inspectRoot.dimColor; font.family: inspectRoot.fontFamily; font.pixelSize: 9; Layout.fillWidth: true }
        Text { textFormat: Text.PlainText; text: "$" + (codexRow.xData ? Number(codexRow.xData.cost).toFixed(2) : "0.00"); color: inspectRoot.codexColor; font.family: inspectRoot.fontFamily; font.pixelSize: 9; font.bold: true }
      }
    }
  }
}
