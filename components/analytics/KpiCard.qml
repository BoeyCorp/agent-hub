import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Rectangle {
  id: card
  property string title: ""
  property string value: ""
  property string subtitle: ""
  property string iconText: ""
  property color accentColor: "#89B4FA"
  property color foregroundColor: "#D8DEE9"
  property color dimColor: "#6B6B6B"
  property color cardColor: Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.05)
  property bool isLightTheme: false
  property string fontFamily: "JetBrainsMono Nerd Font"

  Layout.fillWidth: true
  Layout.preferredHeight: 76
  implicitHeight: 76
  radius: Style.cornerRadius
  color: cardColor
  border.color: isLightTheme ? Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.12)
                             : Qt.rgba(foregroundColor.r, foregroundColor.g, foregroundColor.b, 0.05)
  border.width: 1

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 10
    spacing: 2

    RowLayout {
      Layout.fillWidth: true
      spacing: 6

      Text {
        textFormat: Text.PlainText
        text: card.title.toUpperCase()
        color: card.dimColor
        font.family: card.fontFamily
        font.pixelSize: 9
        font.bold: true
        font.letterSpacing: 0.5
        Layout.fillWidth: true
      }

      Text {
        visible: card.iconText !== ""
        textFormat: Text.PlainText
        text: card.iconText
        color: card.accentColor
        font.family: card.fontFamily
        font.pixelSize: 11
      }
    }

    Text {
      textFormat: Text.PlainText
      text: card.value
      color: card.foregroundColor
      font.family: card.fontFamily
      font.pixelSize: 18
      font.bold: true
      elide: Text.ElideRight
      Layout.fillWidth: true
    }

    Text {
      visible: card.subtitle !== ""
      textFormat: Text.PlainText
      text: card.subtitle
      color: card.dimColor
      font.family: card.fontFamily
      font.pixelSize: 9
      elide: Text.ElideRight
      Layout.fillWidth: true
    }
  }
}
