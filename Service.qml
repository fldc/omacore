import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  // One-time CLI presence probe, cached.
  property bool installed: false
  property bool checkedInstalled: false
  // Whether the device's settings schema has been discovered yet.
  property bool discovered: false
  // settingId -> { type, options, localizedOptions, min, max, step }
  property var schemaMap: ({})
  // settingId -> current typed value (string / boolean / number).
  property var valuesMap: ({})
  // Bumped on every status update so the panel's reactive views recompute.
  property int tick: 0
  // Battery rows for the panel: [{ label, level, charging }].
  property var batteryRows: []
  property bool connected: false
  property string lastError: ""
  property string actionStatus: ""
  // Debounced disconnect: only flip/notify after this many consecutive failures.
  property int consecutiveFailures: 0
  readonly property int disconnectThreshold: 3
  property var _notifiedBatteries: ({})
  property var _pendingWrites: ({})
  property var _writeBuffer: ({})
  property var _actionBatch: []
  readonly property int settleHoldMs: 4000
  readonly property int actionStatusMs: 2200
  readonly property int lowBatteryPercent: 20

  readonly property string macAddress: String(setting("macAddress", "") || "").trim()
  readonly property string model: String(setting("model", "SoundcoreA3040") || "").trim()
  readonly property int pollIntervalSec: intSetting("pollIntervalSec", 30, 10, 300)
  readonly property string ctlPath: String(setting("ctlPath", "") || "").trim()
  readonly property string resolvedBin: ctlPath !== "" ? ctlPath : "openscq30"
  readonly property bool busy: statusProcess.running || discoverProcess.running || actionProcess.running
  readonly property bool hasEarbuds: connected
  readonly property bool notifyEnabled: setting("notifyEnabled", true) === true
  readonly property string deviceType: Model.modelDeviceType(model)

  // OS lockfile that serialises openscq30 across every per-monitor copy (and even
  // across processes), since QML does not share module state across Service
  // instances. See _flock().
  readonly property string lockFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp")
    + "/omacore-poll.lock"

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  // --- accessors for the panel ---------------------------------------------
  function value(id) { return valuesMap[id] }
  function present(id) { return id in schemaMap }
  function schema(id) { return schemaMap[id] }
  function currentMode() { return String(valuesMap[Model.AMBIENT_SOUND_MODE] || "") }

  // --- main tick -----------------------------------------------------------
  function refresh() {
    if (macAddress === "") {
      connected = false
      lastError = "Set the headphones' Bluetooth MAC address in this widget's settings."
      return
    }
    if (!checkedInstalled) {
      whichProcess.command = resolvedBin.indexOf("/") >= 0
        ? ["test", "-x", resolvedBin]
        : ["which", resolvedBin]
      whichProcess.running = true
      return
    }
    if (!installed) {
      connected = false
      lastError = "openscq30 CLI not found. Install openscq30-cli(-bin) from the AUR."
      return
    }
    if (statusProcess.running || discoverProcess.running) return
    if (!discovered) { runDiscovery(); return }
    runPoll()
  }

  function runDiscovery() {
    discoverProcess.command = _flock([resolvedBin, "device", "-a", macAddress, "list-settings", "--json"])
    discoverProcess.running = true
    pollWatchdog.restart()
  }

  function runPoll() {
    var batch = Model.buildPollBatch(schemaMap)
    if (batch.length === 0) {
      connected = false
      lastError = "This device exposes no known settings."
      return
    }
    var args = [resolvedBin, "device", "-a", macAddress, "setting"]
    for (var i = 0; i < batch.length; i++) args.push("-g", batch[i])
    args.push("--json")
    statusProcess.command = _flock(args)
    statusProcess.running = true
    pollWatchdog.restart()
  }

  // Wrap an openscq30 invocation in the flock so only one BLE connection is ever
  // open at a time across all per-monitor copies. Exit 75 = lock busy.
  function _flock(args) {
    var cmdStr = args.join(" ")
    return ["sh", "-c", 'exec 9>"' + lockFile + '"; flock -n 9 || exit 75; ' + cmdStr]
  }

  function applyStatus(raw) {
    var parsed = Model.parseSettingsJson(raw)
    if (!parsed.ok) {
      _noteDisconnected("Could not read the headphones' status.")
      return
    }
    var m = parsed.map
    // Hold optimistic values until the device actually reports them. A pending id
    // whose reported value matches is confirmed (drop it); otherwise keep showing
    // the intended value so the panel doesn't snap back mid-write.
    var confirmed = []
    for (var id in _pendingWrites) {
      if ((id in m) && m[id] === _pendingWrites[id]) confirmed.push(id)
      else m[id] = _pendingWrites[id]
    }
    for (var c = 0; c < confirmed.length; c++) delete _pendingWrites[confirmed[c]]
    connected = true
    consecutiveFailures = 0
    lastError = ""
    valuesMap = m
    batteryRows = Model.batteryEntries(valuesMap)
    _checkLowBatteries()
    tick++
  }

  function _noteDisconnected(message) {
    consecutiveFailures++
    lastError = message
    if (consecutiveFailures < disconnectThreshold) return
    if (connected) _notify("Soundcore headphones disconnected", message, "normal")
    connected = false
    lastError = message
    _notifiedBatteries = {}
  }

  function _checkLowBatteries() {
    for (var i = 0; i < batteryRows.length; i++) {
      var row = batteryRows[i]
      var low = row.level !== Model.LEVEL_UNKNOWN && row.level <= lowBatteryPercent && !row.charging
      if (!low) {
        if (row.label in _notifiedBatteries) delete _notifiedBatteries[row.label]
        continue
      }
      if (row.label in _notifiedBatteries) continue
      _notifiedBatteries[row.label] = true
      _notify(row.label + " battery low", row.level + "% remaining", "normal")
    }
  }

  function _notify(headline, description, urgency) {
    if (!notifyEnabled) return
    _notifyQueue.push({ headline: headline, description: description, urgency: urgency })
    _pumpNotifyQueue()
  }

  function _pumpNotifyQueue() {
    if (notifyProcess.running || _notifyQueue.length === 0) return
    var next = _notifyQueue.shift()
    notifyProcess.command = ["omarchy-notification-send", "--app-name", "Soundcore", "-u", next.urgency, next.headline, next.description]
    notifyProcess.running = true
  }

  function _writeValue(value) {
    if (typeof value === "boolean") return value ? "true" : "false"
    return String(value)
  }

  // --- writing -------------------------------------------------------------
  // Writes are optimistic on the value map (the panel shows the intended value
  // immediately) and debounced into one batched `-s … -s …` invocation, so a
  // burst of changes (stepping a level, opening a dropdown) costs a single BLE
  // connection instead of one per change. The write also serialises with polls
  // through the same flock, so a click never races a poll and silently fails.
  function setSetting(id, value) {
    if (!connected || id === "") return
    _pendingWrites[id] = value
    _writeBuffer[id] = value
    // Fresh object so the panel's bindings (which read valuesMap) re-evaluate.
    var copy = {}
    for (var k in valuesMap) copy[k] = valuesMap[k]
    copy[id] = value
    valuesMap = copy
    batteryRows = Model.batteryEntries(valuesMap)
    tick++
    pendingSettleTimer.restart()
    writeDebounceTimer.restart()
  }

  function flushWrites() {
    var ids = []
    for (var id in _writeBuffer) ids.push(id)
    if (ids.length === 0) return
    if (actionProcess.running) { writeDebounceTimer.restart(); return }
    var args = [resolvedBin, "device", "-a", macAddress, "setting"]
    for (var i = 0; i < ids.length; i++) {
      args.push("-s", ids[i] + "=" + _writeValue(_writeBuffer[ids[i]]))
    }
    var batch = ids
    _writeBuffer = {}
    _actionBatch = batch
    actionProcess.command = _flock(args)
    actionProcess.running = true
  }

  property var _notifyQueue: []

  Timer {
    id: pollTimer
    interval: root.pollIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // Re-attempt shortly after another copy released the flock, or after a failed
  // discovery, instead of waiting the whole poll interval.
  Timer {
    id: pollRetryTimer
    interval: 4000
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    // Every openscq30 invocation opens a fresh BLE connection, which can hang if
    // the headphones are out of range but BlueZ has not noticed yet. Reap it well
    // inside the interval so a stuck poll does not stop refreshing.
    id: pollWatchdog
    interval: 15000
    repeat: false
    onTriggered: {
      if (discoverProcess.running) discoverProcess.running = false
      if (statusProcess.running) statusProcess.running = false
    }
  }

  Timer {
    id: pendingSettleTimer
    interval: 15000
    repeat: false
    // Fallback only: normally a pending write is confirmed by the device on the
    // next poll (see applyStatus). If the device never reports it, drop the
    // optimistic value so the panel reverts to reality. Kept well past the write
    // (~5s BLE) so it doesn't snap back mid-write.
    onTriggered: { root._pendingWrites = {} }
  }

  // Debounce rapid writes into one batched openscq30 invocation.
  Timer {
    id: writeDebounceTimer
    interval: 220
    repeat: false
    onTriggered: root.flushWrites()
  }

  Timer {
    id: actionStatusTimer
    interval: root.actionStatusMs
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: whichProcess
    running: false
    command: []
    onExited: function (exitCode) {
      root.checkedInstalled = true
      root.installed = exitCode === 0
      root.refresh()
    }
  }

  Process {
    id: discoverProcess
    running: false
    command: []
    stdout: StdioCollector { id: discoverOut; waitForEnd: true }
    stderr: StdioCollector { id: discoverErr; waitForEnd: true }
    onExited: function (exitCode) {
      if (exitCode === 75) { pollRetryTimer.restart(); return }
      if (exitCode !== 0) {
        root.lastError = Model.elideError(discoverErr.text) || "Could not reach the headphones."
        pollRetryTimer.restart()
        return
      }
      root.schemaMap = Model.parseListSettings(discoverOut.text)
      root.discovered = true
      root.refresh()
    }
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    stderr: StdioCollector { id: statusErr; waitForEnd: true }
    onExited: function (exitCode) {
      if (exitCode === 75) { pollRetryTimer.restart(); return }
      if (exitCode === 0) root.applyStatus(statusOut.text)
      else root._noteDisconnected(Model.elideError(statusErr.text) || "Could not reach the headphones.")
    }
  }

  Process {
    id: notifyProcess
    running: false
    command: []
    onExited: root._pumpNotifyQueue()
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function (exitCode) {
      // 75 = the flock was held by a poll on another copy; retry shortly.
      if (exitCode === 75) { writeDebounceTimer.restart(); return }
      if (exitCode !== 0) {
        // Real failure: stop overriding and surface the error; the next poll
        // corrects the displayed value.
        for (var i = 0; i < root._actionBatch.length; i++) delete root._pendingWrites[root._actionBatch[i]]
        root._actionBatch = []
        root.actionStatus = Model.elideError(actionErr.text) || "openscq30 rejected the command"
        actionStatusTimer.restart()
        pendingSettleTimer.restart()
      } else {
        // Success: keep the optimistic value; the regular poll confirms it. If a
        // further write was queued meanwhile, flush it now.
        root._actionBatch = []
        writeDebounceTimer.restart()
      }
    }
  }
}
