import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Rectangle {
  id: shareRoot
  property var byAgent: null
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
  Layout.preferredHeight: 180
  implicitHeight: 180
  radius: Style.cornerRadius
  color: cardColor
  border.color: isLightTheme ? Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.12)
                             : Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.05)
  border.width: 1

  readonly property real claudeShare: byAgent && byAgent.claude ? Number(byAgent.claude.sharePercent || 0) : 0
  readonly property real agyShare: byAgent && byAgent.antigravity ? Number(byAgent.antigravity.sharePercent || 0) : 0
  readonly property real codexShare: byAgent && byAgent.codex ? Number(byAgent.codex.sharePercent || 0) : 0

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

    Text {
      textFormat: Text.PlainText
      text: "Workload Share Across Agents"
      color: shareRoot.foregroundColor
      font.family: shareRoot.fontFamily
      font.pixelSize: 11
      font.bold: true
    }

    // Proportional Segmented Bar
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 10
      radius: 4
      color: shareRoot.trackColor
      clip: true

      RowLayout {
        anchors.fill: parent
        spacing: 1

        Rectangle {
          visible: shareRoot.claudeShare > 0
          Layout.preferredHeight: 10
          Layout.fillWidth: true
          Layout.preferredWidth: Math.max(2, shareRoot.claudeShare)
          color: shareRoot.claudeColor
        }

        Rectangle {
          visible: shareRoot.agyShare > 0
          Layout.preferredHeight: 10
          Layout.fillWidth: true
          Layout.preferredWidth: Math.max(2, shareRoot.agyShare)
          color: shareRoot.antigravityColor
        }

        Rectangle {
          visible: shareRoot.codexShare > 0
          Layout.preferredHeight: 10
          Layout.fillWidth: true
          Layout.preferredWidth: Math.max(2, shareRoot.codexShare)
          color: shareRoot.codexColor
        }
      }
    }

    // Detail Breakdown Table Rows
    ColumnLayout {
      Layout.fillWidth: true
      spacing: 6

      // Claude Row
      RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Rectangle { width: 8; height: 8; radius: 2; color: shareRoot.claudeColor }
        Text { textFormat: Text.PlainText; text: "Claude Code"; color: shareRoot.foregroundColor; font.family: shareRoot.fontFamily; font.pixelSize: 10; font.bold: true; Layout.preferredWidth: 90 }
        Text { textFormat: Text.PlainText; text: (byAgent && byAgent.claude ? String(byAgent.claude.prompts) : "0") + " prompts"; color: shareRoot.dimColor; font.family: shareRoot.fontFamily; font.pixelSize: 9; Layout.preferredWidth: 80 }
        Text { textFormat: Text.PlainText; text: (byAgent && byAgent.claude ? shareRoot.formatNumber(byAgent.claude.tokens) : "0") + " tok"; color: shareRoot.dimColor; font.family: shareRoot.fontFamily; font.pixelSize: 9; Layout.fillWidth: true }
        Text { textFormat: Text.PlainText; text: "$" + (byAgent && byAgent.claude ? Number(byAgent.claude.cost).toFixed(2) : "0.00"); color: shareRoot.claudeColor; font.family: shareRoot.fontFamily; font.pixelSize: 10; font.bold: true }
        Text { textFormat: Text.PlainText; text: shareRoot.claudeShare.toFixed(1) + "%"; color: shareRoot.dimColor; font.family: shareRoot.fontFamily; font.pixelSize: 9; horizontalAlignment: Text.AlignRight; Layout.preferredWidth: 40 }
      }

      // Antigravity Row
      RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Rectangle { width: 8; height: 8; radius: 2; color: shareRoot.antigravityColor }
        Text { textFormat: Text.PlainText; text: "Antigravity"; color: shareRoot.foregroundColor; font.family: shareRoot.fontFamily; font.pixelSize: 10; font.bold: true; Layout.preferredWidth: 90 }
        Text { textFormat: Text.PlainText; text: (byAgent && byAgent.antigravity ? String(byAgent.antigravity.prompts) : "0") + " prompts"; color: shareRoot.dimColor; font.family: shareRoot.fontFamily; font.pixelSize: 9; Layout.preferredWidth: 80 }
        Text { textFormat: Text.PlainText; text: (byAgent && byAgent.antigravity ? shareRoot.formatNumber(byAgent.antigravity.tokens) : "0") + " tok"; color: shareRoot.dimColor; font.family: shareRoot.fontFamily; font.pixelSize: 9; Layout.fillWidth: true }
        Text { textFormat: Text.PlainText; text: "$" + (byAgent && byAgent.antigravity ? Number(byAgent.antigravity.cost).toFixed(2) : "0.00"); color: shareRoot.antigravityColor; font.family: shareRoot.fontFamily; font.pixelSize: 10; font.bold: true }
        Text { textFormat: Text.PlainText; text: shareRoot.agyShare.toFixed(1) + "%"; color: shareRoot.dimColor; font.family: shareRoot.fontFamily; font.pixelSize: 9; horizontalAlignment: Text.AlignRight; Layout.preferredWidth: 40 }
      }

      // Codex Row
      RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Rectangle { width: 8; height: 8; radius: 2; color: shareRoot.codexColor }
        Text { textFormat: Text.PlainText; text: "OpenAI Codex"; color: shareRoot.foregroundColor; font.family: shareRoot.fontFamily; font.pixelSize: 10; font.bold: true; Layout.preferredWidth: 90 }
        Text { textFormat: Text.PlainText; text: (byAgent && byAgent.codex ? String(byAgent.codex.prompts) : "0") + " prompts"; color: shareRoot.dimColor; font.family: shareRoot.fontFamily; font.pixelSize: 9; Layout.preferredWidth: 80 }
        Text { textFormat: Text.PlainText; text: (byAgent && byAgent.codex ? shareRoot.formatNumber(byAgent.codex.tokens) : "0") + " tok"; color: shareRoot.dimColor; font.family: shareRoot.fontFamily; font.pixelSize: 9; Layout.fillWidth: true }
        Text { textFormat: Text.PlainText; text: "$" + (byAgent && byAgent.codex ? Number(byAgent.codex.cost).toFixed(2) : "0.00"); color: shareRoot.codexColor; font.family: shareRoot.fontFamily; font.pixelSize: 10; font.bold: true }
        Text { textFormat: Text.PlainText; text: shareRoot.codexShare.toFixed(1) + "%"; color: shareRoot.dimColor; font.family: shareRoot.fontFamily; font.pixelSize: 9; horizontalAlignment: Text.AlignRight; Layout.preferredWidth: 40 }
      }
    }
  }
}
