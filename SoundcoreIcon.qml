import QtQuick
import qs.Commons

// The bar/hero icon for the Soundcore widget. Over-ear models get the Nerd Font
// "headphones" glyph (U+F02B) drawn in whatever family the theme resolves for the
// bar; earbud models get the two-buds glyph drawn with rectangles (the glyph sets
// don't all ship a clean buds glyph, and at bar size the stems would be lost to
// rasterisation anyway).
Item {
  id: root

  property real iconSize: 16
  property color color: Color.foreground
  property string type: "earbuds"
  // Bind this to the bar's fontFamily so the glyph draws in the theme's Nerd Font.
  property string fontFamily: Style.font.family

  readonly property bool headphones: type === "headphones"

  // The Nerd Font glyph's visible height is roughly 70% of its pixel size, so
  // scale the pixel size up a bit to land visually near iconSize.
  readonly property real glyphSize: Math.round(iconSize * 1.4)

  // Earbuds: two buds side by side are wider than they are tall, so the implicit
  // size follows the actual drawn content rather than a square iconSize box —
  // otherwise a Loader with no anchors.fill (e.g. PanelHero) sizes the icon too
  // small and crops it.
  readonly property real earbudHeadSize: iconSize * 0.5
  readonly property real earbudStemWidth: iconSize * 0.22
  readonly property real earbudStemHeight: iconSize * 0.34
  readonly property real earbudBudSpacing: iconSize * 0.16

  implicitWidth: headphones ? glyphSize : earbudHeadSize * 2 + earbudBudSpacing
  implicitHeight: headphones ? glyphSize : earbudHeadSize + earbudStemHeight
  width: implicitWidth
  height: implicitHeight

  Text {
    id: headphoneGlyph
    visible: root.headphones
    anchors.centerIn: parent
    text: "󰋋"
    font.family: root.fontFamily
    font.pixelSize: root.glyphSize
    color: root.color
  }

  Row {
    id: budRow
    visible: !root.headphones
    anchors.centerIn: parent
    spacing: root.earbudBudSpacing

    Bud { head: root.earbudHeadSize; stemW: root.earbudStemWidth; stemH: root.earbudStemHeight; ink: root.color }
    Bud { head: root.earbudHeadSize; stemW: root.earbudStemWidth; stemH: root.earbudStemHeight; ink: root.color }
  }

  // A stubbier capsule than a stemmed earbud, closer to Soundcore's own silhouette.
  component Bud: Item {
    id: bud
    property real head: 0
    property real stemW: 0
    property real stemH: 0
    property color ink: Color.foreground

    width: head
    height: head + stemH

    Rectangle {
      width: bud.head
      height: bud.head
      radius: width * 0.42
      color: bud.ink
    }

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      y: bud.head * 0.78
      width: bud.stemW
      height: bud.stemH
      radius: width / 2
      color: bud.ink
    }
  }
}
