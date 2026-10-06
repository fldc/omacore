import QtQuick
import qs.Commons

// Device-aware icon: mirrored AirPods Pro-style earbuds (silicone tips, angled
// shells, short stems) for earbuds, and an over-ear headphone (headband + two
// cups) for headphones. Set `headphone` to switch between the two.
Canvas {
  id: root
  property real iconSize: 16
  property color color: Color.foreground
  property bool headphone: false

  implicitWidth: iconSize * 36 / 24
  implicitHeight: iconSize
  width: implicitWidth
  height: implicitHeight
  onColorChanged: requestPaint()
  onHeadphoneChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var c = getContext("2d")
    c.reset()
    c.scale(width / 36, height / 24)
    c.fillStyle = root.color
    c.strokeStyle = root.color
    function earbud() {
      // Silicone tip protrudes from the broad, tilted speaker housing.
      c.beginPath()
      c.moveTo(4.5, 5)
      c.bezierCurveTo(2, 4, 0, 5.5, 0, 8)
      c.bezierCurveTo(0, 10.5, 2.5, 12, 5.5, 10.5)
      c.closePath()
      c.fill()

      c.beginPath()
      c.moveTo(5, 3)
      c.bezierCurveTo(9, -1, 15, 0, 15, 5.5)
      c.bezierCurveTo(15, 8, 13.5, 10.5, 12, 12)
      c.lineTo(10.5, 21.5)
      c.bezierCurveTo(10, 24.5, 5.5, 23.5, 6, 20.5)
      c.lineTo(7.5, 12.5)
      c.bezierCurveTo(2.5, 12, 1.5, 7, 5, 3)
      c.closePath()
      c.fill()

      // Housing vent and tip seam distinguish the Pro shape at small sizes.
      c.save()
      c.globalCompositeOperation = "destination-out"
      c.lineCap = "round"
      c.lineWidth = 1.5
      c.beginPath()
      c.moveTo(8, 3.2)
      c.lineTo(11, 2.8)
      c.stroke()
      c.lineWidth = 1
      c.beginPath()
      c.moveTo(3.5, 6)
      c.quadraticCurveTo(2.5, 8, 4.3, 10)
      c.stroke()
      c.restore()
    }
    function headphone() {
      // Over-ear headphone: two rounded ear cups joined by a headband arc.
      c.lineCap = "round"
      c.lineJoin = "round"

      c.beginPath()
      c.roundedRect(2.5, 12, 8, 11, 3, 3)
      c.fill()
      c.beginPath()
      c.roundedRect(25.5, 12, 8, 11, 3, 3)
      c.fill()

      c.lineWidth = 2.5
      c.beginPath()
      c.arc(18, 12, 11.5, Math.PI, 2 * Math.PI)
      c.stroke()
    }
    if (root.headphone) {
      headphone()
    } else {
      earbud()
      c.translate(36, 0)
      c.scale(-1, 1)
      earbud()
    }
  }
}
