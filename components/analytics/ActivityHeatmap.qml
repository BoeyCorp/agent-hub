import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Rectangle {
  id: heatRoot
  property var heatmapData: []
  property color accentColor: "#89B4FA"
  property color foregroundColor: "#D8DEE9"
  property color dimColor: "#6B6B6B"
  property color trackColor: Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.12)
  property color cardColor: Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.05)
  property bool isLightTheme: false
  property string fontFamily: "JetBrainsMono Nerd Font"

  signal dayClicked(string dateStr)

  Layout.fillWidth: true
  Layout.preferredHeight: 160
  implicitHeight: 160
  radius: Style.cornerRadius
  color: cardColor
  border.color: isLightTheme ? Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.12)
                             : Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.05)
  border.width: 1

  function getTileColor(intensity) {
    if (intensity === 0) return heatRoot.trackColor
    if (intensity === 1) return Qt.rgba(heatRoot.accentColor.r, heatRoot.accentColor.g, heatRoot.accentColor.b, 0.30)
    if (intensity === 2) return Qt.rgba(heatRoot.accentColor.r, heatRoot.accentColor.g, heatRoot.accentColor.b, 0.55)
    if (intensity === 3) return Qt.rgba(heatRoot.accentColor.r, heatRoot.accentColor.g, heatRoot.accentColor.b, 0.80)
    return heatRoot.accentColor
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 12
    spacing: 8

    RowLayout {
      Layout.fillWidth: true
      spacing: 6

      Text {
        textFormat: Text.PlainText
        text: "Monthly Activity Heatmap"
        color: heatRoot.foregroundColor
        font.family: heatRoot.fontFamily
        font.pixelSize: 11
        font.bold: true
        Layout.fillWidth: true
      }

      // Intensity Legend
      RowLayout {
        spacing: 3
        Text { textFormat: Text.PlainText; text: "Less"; color: heatRoot.dimColor; font.family: heatRoot.fontFamily; font.pixelSize: 8 }
        Rectangle { width: 9; height: 9; radius: 2; color: heatRoot.getTileColor(0) }
        Rectangle { width: 9; height: 9; radius: 2; color: heatRoot.getTileColor(1) }
        Rectangle { width: 9; height: 9; radius: 2; color: heatRoot.getTileColor(2) }
        Rectangle { width: 9; height: 9; radius: 2; color: heatRoot.getTileColor(3) }
        Rectangle { width: 9; height: 9; radius: 2; color: heatRoot.getTileColor(4) }
        Text { textFormat: Text.PlainText; text: "More"; color: heatRoot.dimColor; font.family: heatRoot.fontFamily; font.pixelSize: 8 }
      }
    }

    // Grid of Days
    Flow {
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: 4

      Repeater {
        model: heatRoot.heatmapData || []

        delegate: Rectangle {
          required property var modelData
          required property int index
          width: 18
          height: 18
          radius: 3
          color: heatRoot.getTileColor(modelData ? modelData.intensity : 0)
          border.width: hMouse.containsMouse ? 1 : 0
          border.color: heatRoot.foregroundColor

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: modelData ? String(modelData.dayOfMonth || "") : ""
            color: (modelData && modelData.intensity >= 3) ? (heatRoot.isLightTheme ? "#FFFFFF" : "#000000") : heatRoot.dimColor
            font.family: heatRoot.fontFamily
            font.pixelSize: 8
            font.bold: modelData && modelData.intensity > 0
          }

          MouseArea {
            id: hMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (modelData && modelData.date) {
                heatRoot.dayClicked(modelData.date)
              }
            }
          }
        }
      }
    }
  }
}
