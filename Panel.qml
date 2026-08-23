import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.birajdotdev.omacore"
  ipcTarget: "omacore"
  manageIpc: false

  property int cursorIndex: 0
  property bool cursorActive: false
  // Dropdowns registered by SpecRow delegates (keyed by setting id) so the keyboard
  // cursor can open them.
  property var _dropdowns: ({})

  readonly property bool hideWhenDisconnected: setting("hideWhenDisconnected", true) === true
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color barIconColor: pods.hasEarbuds ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool guidanceVisible: !pods.hasEarbuds && pods.lastError !== ""

  readonly property var sections: Model.SECTIONS
  readonly property var modeValues: Model.optionValues(pods.schemaMap, Model.AMBIENT_SOUND_MODE)

  function specsFor(sectionKey) {
    var out = []
    for (var i = 0; i < Model.KNOWN_SETTINGS.length; i++) {
      var spec = Model.KNOWN_SETTINGS[i]
      if (spec.section !== sectionKey) continue
      if (!pods.present(spec.id)) continue
      if (!Model.whenShows(spec, pods.valuesMap)) continue
      out.push(spec)
    }
    return out
  }

  function specById(id) {
    for (var i = 0; i < Model.KNOWN_SETTINGS.length; i++)
      if (Model.KNOWN_SETTINGS[i].id === id) return Model.KNOWN_SETTINGS[i]
    return null
  }

  readonly property var cursorRows: {
    var rows = []
    if (!pods.hasEarbuds) return rows
    for (var i = 0; i < modeValues.length; i++) rows.push("mode:" + modeValues[i])
    for (var s = 0; s < sections.length; s++) {
      if (!root.isExpanded(sections[s].key)) continue
      var list = root.specsFor(sections[s].key)
      for (var j = 0; j < list.length; j++) {
        var kind = list[j].kind
        if (kind === "toggle" || kind === "select" || kind === "range") rows.push(list[j].id)
      }
    }
    return rows
  }

  readonly property string cursorRow: cursorRows.length === 0
    ? ""
    : cursorRows[Math.max(0, Math.min(cursorIndex, cursorRows.length - 1))]

  function rowHasCursor(name) { return cursorActive && cursorRow === name }

  function moveCursor(dy) {
    cursorActive = true
    if (cursorRows.length === 0) return
    cursorIndex = Math.max(0, Math.min(cursorRows.length - 1, cursorIndex + dy))
  }

  function activateCursor() {
    var name = cursorRow
    if (name.indexOf("mode:") === 0) { pods.setSetting(Model.AMBIENT_SOUND_MODE, name.substring(5)); return }
    var spec = root.specById(name)
    if (!spec) return
    if (spec.kind === "toggle") pods.setSetting(name, !(pods.value(name) === true))
    else if (spec.kind === "select" || spec.kind === "range") {
      var d = root._dropdowns[name]
      if (d) d.toggle()
    }
  }

  function focusRow(name) {
    var at = cursorRows.indexOf(name)
    if (at < 0) return
    cursorActive = true
    cursorIndex = at
  }

  // --- collapsible sections ----------------------------------------------
  // Only the sections marked collapsible (Settings, Buttons) start closed;
  // every other section is always shown. See Model.SECTIONS[].collapsible.
  property var _expanded: ({})
  function isCollapsible(key) {
    for (var i = 0; i < sections.length; i++)
      if (sections[i].key === key) return sections[i].collapsible === true
    return false
  }
  function isExpanded(key) {
    if (!root.isCollapsible(key)) return true
    return _expanded[key] === true
  }
  function toggleSection(key) {
    // Fresh object so bindings (which read _expanded through isExpanded) recompute.
    var copy = {}
    for (var k in _expanded) copy[k] = _expanded[k]
    copy[key] = !(_expanded[key] === true)
    _expanded = copy
    cursorActive = false
  }

  visible: !hideWhenDisconnected || pods.hasEarbuds
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    cursorIndex = 0
    if (panelFlick) panelFlick.contentY = 0
    pods.refresh()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: pods
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { pods.refresh(); return "ok" }
    function status(): string { return Model.modeLabel(pods.currentMode()) }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        SoundcoreIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: root.barIconColor
          type: pods.deviceType
          fontFamily: root.fontFamily
        }
      }
    }
    onPressed: function (buttonCode) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function (dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) {
        var key = String(t).toLowerCase()
        if (key === "r") pods.refresh()
        else if (!pods.hasEarbuds) return
        else if (key === "n") pods.setSetting(Model.AMBIENT_SOUND_MODE, Model.MODE_NOISE_CANCELING)
        else if (key === "t") pods.setSetting(Model.AMBIENT_SOUND_MODE, Model.MODE_TRANSPARENCY)
        else if (key === "o") pods.setSetting(Model.AMBIENT_SOUND_MODE, Model.MODE_NORMAL)
        else if (key === "w" && pods.value(Model.AMBIENT_SOUND_MODE) === Model.MODE_NOISE_CANCELING
                 && pods.present(Model.WIND_NOISE_SUPPRESSION))
          pods.setSetting(Model.WIND_NOISE_SUPPRESSION, !(pods.value(Model.WIND_NOISE_SUPPRESSION) === true))
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(10)

          PanelHero {
            id: hero
            width: parent.width
            title: Model.modelDisplayName(pods.model)
            meta: pods.hasEarbuds ? Model.modeLabel(pods.currentMode())
                                  : (pods.lastError !== "" ? pods.lastError : "Checking…")
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: pods.hasEarbuds ? 1.0 : 0.5
            iconComponent: Component {
              SoundcoreIcon {
                iconSize: Style.font.display
                color: pods.hasEarbuds ? root.foreground : root.dim
                type: pods.deviceType
                fontFamily: root.fontFamily
              }
            }
          }

          Text {
            visible: pods.actionStatus !== ""
            width: parent.width
            text: pods.actionStatus
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Repeater {
            model: root.sections
            delegate: Item {
              required property var modelData
              readonly property string sectionKey: modelData.key
              readonly property string sectionTitle: modelData.title
              readonly property var specs: root.specsFor(sectionKey)
              readonly property bool hasBattery: sectionKey === "battery"
                && Model.hasBattery(pods.schemaMap) && pods.batteryRows.length > 0
              readonly property bool hasContent: hasBattery || sectionKey === "soundMode" || specs.length > 0
              readonly property bool collapsible: root.isCollapsible(sectionKey)
              readonly property bool expanded: root.isExpanded(sectionKey)
              width: parent.width
              implicitHeight: hasContent ? content.implicitHeight : 0

              Column {
                id: content
                width: parent.width
                spacing: Style.space(8)
                visible: hasContent

                // Collapsible sections get a clickable header with a chevron;
                // everything else is a plain, always-visible header.
                Item {
                  id: sectionHeader
                  width: parent.width
                  implicitHeight: headerRow.implicitHeight
                  visible: hasContent

                  RowLayout {
                    id: headerRow
                    width: parent.width
                    spacing: Style.space(8)

                    Text {
                      Layout.fillWidth: true
                      text: sectionTitle
                      color: root.foreground
                      opacity: 0.8
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.subtitle
                      elide: Text.ElideRight
                    }

                    Text {
                      visible: collapsible
                      text: expanded ? "󰅃" : "󰅀"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.icon
                      Layout.preferredWidth: Style.space(18)
                      horizontalAlignment: Text.AlignRight
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: collapsible
                    cursorShape: collapsible ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: { if (collapsible) root.toggleSection(sectionKey) }
                  }
                }

                Column {
                  width: parent.width
                  spacing: Style.space(6)
                  visible: expanded

                  Repeater {
                    model: hasBattery ? pods.batteryRows : []
                    delegate: LevelRow {
                      required property var modelData
                      width: parent.width
                      label: modelData.label
                      level: modelData.level
                      charging: modelData.charging
                    }
                  }

                  Repeater {
                    model: sectionKey === "soundMode" ? root.modeValues : []
                    delegate: OptionRow {
                      required property var modelData
                      width: parent.width
                      rowName: "mode:" + modelData
                      label: Model.modeLabel(modelData)
                      selected: pods.value(Model.AMBIENT_SOUND_MODE) === modelData
                      onActivated: pods.setSetting(Model.AMBIENT_SOUND_MODE, modelData)
                    }
                  }

                  Repeater {
                    model: expanded ? specs : []
                    delegate: SpecRow {
                      required property var modelData
                      spec: modelData
                    }
                  }
                }
              }
            }
          }

          Text {
            visible: root.guidanceVisible
            width: parent.width
            text: pods.lastError
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }

  component LevelRow: Item {
    id: levelRow
    property string label: ""
    property int level: Model.LEVEL_UNKNOWN
    property bool charging: false

    implicitHeight: levelLayout.implicitHeight

    RowLayout {
      id: levelLayout
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(8)

      Text {
        text: levelRow.label
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.preferredWidth: Style.space(44)
      }
      Rectangle {
        id: meterTrack
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        implicitHeight: Style.space(6)
        radius: height / 2
        color: Qt.darker(root.foreground, 3.2)
        Rectangle {
          width: meterTrack.width * Model.levelFraction(levelRow.level)
          height: parent.height
          radius: parent.radius
          color: (levelRow.level !== Model.LEVEL_UNKNOWN && levelRow.level <= pods.lowBatteryPercent) ? root.urgent : root.foreground
        }
      }
      Text {
        text: Model.levelText(levelRow.level)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        horizontalAlignment: Text.AlignRight
        Layout.preferredWidth: Style.space(38)
      }
      Text {
        text: levelRow.charging ? "Charging" : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        Layout.preferredWidth: Style.space(56)
      }
    }
  }

  component OptionRow: CursorSurface {
    id: optionRow
    property string rowName: ""
    property string label: ""
    property bool selected: false
    signal activated()

    hasCursor: root.rowHasCursor(rowName)
    foreground: root.foreground
    implicitHeight: optionLabel.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.focusRow(optionRow.rowName)
      onClicked: optionRow.activated()
    }
    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)
      Text {
        id: optionLabel
        Layout.fillWidth: true
        text: optionRow.label
        color: root.foreground
        opacity: optionRow.selected ? 1.0 : 0.75
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
      Text {
        Layout.alignment: Qt.AlignVCenter
        text: "󰄬"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        opacity: optionRow.selected ? 1.0 : 0.0
      }
    }
  }

  component ToggleRow: CursorSurface {
    id: toggleRow
    property string rowName: ""
    property string label: ""
    property bool on: false
    signal activated()

    foreground: root.foreground
    implicitHeight: rowLabel.implicitHeight > toggleSwitch.implicitHeight
      ? rowLabel.implicitHeight
      : toggleSwitch.implicitHeight

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(8)
      Text {
        id: rowLabel
        Layout.fillWidth: true
        text: toggleRow.label
        color: root.foreground
        opacity: toggleRow.on ? 1.0 : 0.75
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
      ToggleSwitch {
        id: toggleSwitch
        Layout.alignment: Qt.AlignVCenter
        trackHeight: Math.round(rowLabel.font.pixelSize * 1.2)
        checked: toggleRow.on
        interactive: false
        cursorRing: true
        hasCursor: root.rowHasCursor(toggleRow.rowName)
        foreground: root.foreground
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.focusRow(toggleRow.rowName)
          onClicked: toggleRow.activated()
        }
      }
    }
  }

  // Generic renderer for a known setting: toggle switch, select/range dropdown,
  // or read-only info line, based on spec.kind.
  component SpecRow: Item {
    id: specRow
    property var spec
    readonly property string specId: spec ? (spec.id || "") : ""
    readonly property string label: spec ? (spec.label || "") : ""
    readonly property string kind: spec ? (spec.kind || "") : ""
    readonly property string unit: spec ? (spec.unit || "") : ""
    readonly property var currentValue: pods.value(specId)

    implicitHeight: kind === "toggle" ? toggleBody.implicitHeight
      : (kind === "select" || kind === "range") ? selectBody.implicitHeight
      : infoBody.implicitHeight

    width: parent ? parent.width : 0

    ToggleRow {
      id: toggleBody
      visible: specRow.kind === "toggle"
      width: specRow.width
      rowName: specRow.specId
      label: specRow.label
      on: specRow.currentValue === true
      onActivated: pods.setSetting(specRow.specId, !(specRow.currentValue === true))
    }

    RowLayout {
      id: selectBody
      visible: specRow.kind === "select" || specRow.kind === "range"
      width: specRow.width
      spacing: Style.space(8)

      Text {
        text: specRow.label
        color: root.foreground
        opacity: 0.75
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Layout.preferredWidth: Style.space(116)
        elide: Text.ElideRight
      }
      Dropdown {
        id: dd
        Layout.fillWidth: true
        showLabel: false
        value: specRow.currentValue === undefined ? "" : String(specRow.currentValue)
        options: specRow.kind === "range"
          ? Model.rangeObjects(pods.schemaMap, specRow.specId, specRow.unit)
          : Model.optionObjects(pods.schemaMap, specRow.specId)
        foreground: root.foreground
        fontFamily: root.fontFamily
        hasCursor: root.rowHasCursor(specRow.specId)
        onChanged: function (v) { pods.setSetting(specRow.specId, v) }
        onHovered: function (h) { if (h) root.focusRow(specRow.specId) }
        Component.onCompleted: { if (root) root._dropdowns[specRow.specId] = dd }
        Component.onDestruction: { if (root) delete root._dropdowns[specRow.specId] }
        Binding {
          target: dd
          property: "value"
          value: specRow.currentValue === undefined ? "" : String(specRow.currentValue)
        }
      }
    }

    RowLayout {
      id: infoBody
      visible: specRow.kind === "info"
      width: specRow.width
      spacing: Style.space(8)
      Text {
        text: specRow.label
        color: root.foreground
        opacity: 0.75
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Layout.preferredWidth: Style.space(110)
      }
      Text {
        Layout.fillWidth: true
        text: specRow.currentValue === undefined || specRow.currentValue === null ? "—" : String(specRow.currentValue)
        color: root.foreground
        opacity: 0.85
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
    }
  }
}
