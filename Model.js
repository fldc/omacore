// No QML imports on purpose, so every function here runs in a plain JS harness.

// ---------------------------------------------------------------------------
// Schema-driven Soundcore widget.
//
// Instead of a hard-coded set of settings, the widget discovers what the device
// supports by calling `openscq30 device -a <mac> list-settings --json`, then polls
// only the settings it knows how to render that the device actually exposes. This
// lets one panel serve both over-ear headphones (Space Q45) and the earbuds
// (R60i NC / P31i, …) and adapts to whatever the firmware reports.
// ---------------------------------------------------------------------------

// Known settings the widget renders, in display order within their section.
// For "select"/"range" kinds the options/min/max/step come from the live schema;
// "when" (if present) gates whether the row shows, based on the value map.
// Only Settings and Buttons are collapsible in the panel (see Panel.qml); the rest
// of these sections are always shown.
var KNOWN_SETTINGS = [
  { id: "transparencyMode", section: "soundMode", label: "Transparency mode", kind: "select", when: "TransparencyMode" },
  { id: "manualTransparency", section: "soundMode", label: "Transparency level", kind: "range", when: "TransparencyManual" },
  { id: "noiseCancelingMode", section: "soundMode", label: "ANC mode", kind: "select", when: "NoiseCancelingMode" },
  { id: "manualNoiseCanceling", section: "soundMode", label: "ANC level", kind: "range", when: "NoiseCancelingManual" },
  { id: "multiSceneNoiseCanceling", section: "soundMode", label: "Multi-scene", kind: "select", when: "NoiseCancelingMultiScene" },
  { id: "realTimeAdaptiveNoiseCanceling", section: "soundMode", label: "Real-time adaptive ANC", kind: "toggle", when: "NoiseCanceling" },
  { id: "windNoiseSuppression", section: "soundMode", label: "Wind noise suppression", kind: "toggle", when: "NoiseCanceling" },
  { id: "spatialAudio", section: "soundEffects", label: "Spatial audio", kind: "toggle" },
  { id: "spatialAudioMode", section: "soundEffects", label: "Sound effect", kind: "select" },
  { id: "presetEqualizerProfile", section: "equalizer", label: "Preset EQ", kind: "select" },
  { id: "normalModeInCycle", section: "button", label: "Normal in cycle", kind: "toggle" },
  { id: "transparencyModeInCycle", section: "button", label: "Transparency in cycle", kind: "toggle" },
  { id: "noiseCancelingModeInCycle", section: "button", label: "Noise cancelling in cycle", kind: "toggle" },
  { id: "dualConnections", section: "misc", label: "Dual connections", kind: "toggle" },
  { id: "ldac", section: "misc", label: "LDAC", kind: "toggle" },
  { id: "voicePrompt", section: "misc", label: "Voice prompts", kind: "toggle" },
  { id: "lowBatteryPrompt", section: "misc", label: "Low battery prompt", kind: "toggle" },
  { id: "autoPowerOff", section: "misc", label: "Auto power off", kind: "select" },
  { id: "limitHighVolume", section: "volumeLimit", label: "Limit high volume", kind: "toggle" },
  { id: "limitHighVolumeDbLimit", section: "volumeLimit", label: "Volume limit (dB)", kind: "range", unit: " dB" },
  { id: "limitHighVolumeRefreshRate", section: "volumeLimit", label: "Refresh rate", kind: "select" }
]

// Section order and titles. "battery" is drawn specially (single vs multi).
// Only the sections marked collapsible (Settings, Buttons, Volume Limiter) start
// closed; the rest are always shown. Device info is intentionally omitted.
var SECTIONS = [
  { key: "battery", title: "BATTERY" },
  { key: "soundMode", title: "SOUND MODE" },
  { key: "equalizer", title: "EQUALIZER" },
  { key: "misc", title: "SETTINGS", collapsible: true },
  { key: "button", title: "BUTTONS", collapsible: true },
  { key: "volumeLimit", title: "VOLUME LIMITER", collapsible: true },
  { key: "soundEffects", title: "SOUND EFFECTS" }
]

// Battery-setting ids: the single-battery (over-ear) variant versus the
// earbuds left/right/case variant. Whichever are present drive the rows.
var BATTERY_SINGLE = "batteryLevel"
var BATTERY_LEFT = "batteryLevelLeft"
var BATTERY_RIGHT = "batteryLevelRight"
var BATTERY_CASE = "caseBatteryLevel"
var CHARGING_LEFT = "isChargingLeft"
var CHARGING_RIGHT = "isChargingRight"

var AMBIENT_SOUND_MODE = "ambientSoundMode"
var WIND_NOISE_SUPPRESSION = "windNoiseSuppression"

// AmbientSoundMode raw values (same across models).
var MODE_NOISE_CANCELING = "NoiseCanceling"
var MODE_TRANSPARENCY = "Transparency"
var MODE_NORMAL = "Normal"

var LEVEL_UNKNOWN = -1
var MAX_ERROR_CHARS = 140
var ELIDED_ERROR_CHARS = 137

// Over-ear / on-ear headphone models, so the bar can draw a headphone icon for
// these and earbuds for everything else. Keep in sync with `openscq30 list-models`.
var HEADPHONE_MODELS = {
  "SoundcoreA3004": true, "SoundcoreA3027": true, "SoundcoreA3028": true,
  "SoundcoreA3029": true, "SoundcoreA3030": true, "SoundcoreA3031": true,
  "SoundcoreA3033": true, "SoundcoreA3035": true, "SoundcoreA3040": true,
  "SoundcoreA3062": true
}

function modelDisplayName(modelId) {
  if (modelId === "SoundcoreA3040") return "Soundcore Space Q45"
  return "Soundcore"
}

function modelDeviceType(modelId) {
  return HEADPHONE_MODELS[String(modelId || "")] ? "headphones" : "earbuds"
}

// --------------------------------------------------------------------------
// Schema discovery
// --------------------------------------------------------------------------

// `list-settings --json` returns an array of categories, each with a `settings`
// array of { settingId, type, setting:{options,localizedOptions,start,end,step} }.
// Flatten into a map: settingId -> { type, options:[], localizedOptions:[], min, max, step }.
function parseListSettings(raw) {
  var map = {}
  var text = String(raw || "").trim()
  if (text === "") return map
  var parsed
  try { parsed = JSON.parse(text) } catch (e) { return map }
  if (!Array.isArray(parsed)) return map
  for (var c = 0; c < parsed.length; c++) {
    var cat = parsed[c]
    var settings = cat && cat.settings
    if (!Array.isArray(settings)) continue
    for (var s = 0; s < settings.length; s++) {
      var entry = settings[s]
      if (!entry) continue
      var id = entry.settingId
      if (typeof id !== "string") continue
      var meta = entry.setting || {}
      var opt = meta.options || []
      // In some versions options come as objects; coerce to labels.
      var opts = opt.map(function (o) { return typeof o === "object" ? o.label : o })
      map[id] = {
        type: entry.type,
        options: opts,
        localizedOptions: (meta.localizedOptions || opts),
        min: (meta.start !== undefined) ? meta.start : undefined,
        max: (meta.end !== undefined) ? meta.end : undefined,
        step: (meta.step !== undefined) ? meta.step : undefined
      }
    }
  }
  return map
}

// Build the -g poll batch: every known setting the device exposes, plus whichever
// battery/charging ids are present. Unknown ids fail the whole batch, so we must
// intersect strictly with the discovered schema.
function buildPollBatch(schemaMap) {
  var batch = []
  if (schemaMap[AMBIENT_SOUND_MODE]) batch.push(AMBIENT_SOUND_MODE)
  for (var i = 0; i < KNOWN_SETTINGS.length; i++) {
    var id = KNOWN_SETTINGS[i].id
    if (schemaMap[id]) batch.push(id)
  }
  var batteryIds = [BATTERY_SINGLE, BATTERY_LEFT, BATTERY_RIGHT, BATTERY_CASE, CHARGING_LEFT, CHARGING_RIGHT]
  for (var b = 0; b < batteryIds.length; b++) {
    if (schemaMap[batteryIds[b]] && batch.indexOf(batteryIds[b]) < 0) batch.push(batteryIds[b])
  }
  return batch
}

// Does the schema expose any battery id?
function hasBattery(schemaMap) {
  return !!(schemaMap[BATTERY_SINGLE] || schemaMap[BATTERY_LEFT] || schemaMap[BATTERY_RIGHT] || schemaMap[BATTERY_CASE])
}

// --------------------------------------------------------------------------
// Value parsing
// --------------------------------------------------------------------------

// `setting -g <ids> --json` prints [{"settingId":"x","value":{"type":"str|bool|i32","value":…}}]
function parseSettingsJson(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: false, map: {} }
  var parsed
  try { parsed = JSON.parse(text) } catch (e) { return { ok: false, map: {} } }
  if (!Array.isArray(parsed)) return { ok: false, map: {} }
  var map = {}
  for (var i = 0; i < parsed.length; i++) {
    var entry = parsed[i]
    if (!entry || typeof entry !== "object") continue
    var id = entry.settingId
    var value = entry.value
    if (typeof id !== "string" || !value || typeof value !== "object") continue
    map[id] = value.value
  }
  return { ok: true, map: map }
}

// --------------------------------------------------------------------------
// Labels / formatting
// --------------------------------------------------------------------------

function modeLabel(mode) {
  if (mode === MODE_NOISE_CANCELING) return "Noise Cancellation"
  if (mode === MODE_TRANSPARENCY) return "Transparency"
  if (mode === MODE_NORMAL) return "Normal"
  return "Unknown"
}

// Friendly label for a select value, using the device's localized options if there
// are exactly enough, otherwise the raw value.
function selectLabel(schema, id, value) {
  var meta = id ? (schema[id] || {}) : {}
  var options = meta.localizedOptions || []
  var values = meta.options || []
  if (options.length && values.length && options.length === values.length) {
    var idx = values.indexOf(value)
    if (idx >= 0) return String(options[idx])
  }
  var s = String(value === undefined || value === null ? "" : value)
  return s === "" ? "—" : s
}

// Raw option values of a select/picker setting.
function optionValues(schemaMap, id) {
  var s = schemaMap[id]
  return s && s.options ? s.options.slice() : []
}

// [{"value": raw, "label": localized}] pairs for a dropdown, in schema order.
function optionObjects(schemaMap, id) {
  var s = schemaMap[id] || {}
  var raw = s.options || []
  var labels = s.localizedOptions || []
  var out = []
  for (var i = 0; i < raw.length; i++) {
    out.push({ value: String(raw[i]), label: String(labels[i] !== undefined ? labels[i] : raw[i]) })
  }
  return out
}

// [{"value","label"}] steps for a range control, with optional unit appended.
function rangeObjects(schemaMap, id, unit) {
  var s = schemaMap[id] || {}
  var min = s.min
  var max = s.max
  var step = s.step || 1
  if (!isFinite(min) || !isFinite(max)) return []
  var out = []
  for (var v = min; v <= max; v += step) {
    out.push({ value: String(v), label: String(v) + (unit || "") })
  }
  return out
}

// label for a range value (e.g. "4", "90 dB"), with optional unit from the spec.
function rangeLabel(value, unit) {
  return String(value) + (unit || "")
}

// Battery value arrives as "raw/max" (ten discrete steps) → percent.
function levelFromFraction(text) {
  var value = String(text || "")
  var parts = value.split("/")
  if (parts.length !== 2) return LEVEL_UNKNOWN
  var raw = parseInt(parts[0], 10)
  var max = parseInt(parts[1], 10)
  if (!isFinite(raw) || !isFinite(max) || max <= 0) return LEVEL_UNKNOWN
  return Math.max(0, Math.min(100, Math.round((raw / max) * 100)))
}

function levelText(level) {
  return level === LEVEL_UNKNOWN ? "--" : String(level) + "%"
}

function levelFraction(level) {
  if (level === LEVEL_UNKNOWN) return 0
  return Math.max(0, Math.min(100, level)) / 100
}

// Build the list of battery rows for the panel from the value map.
// Returns [{label, level, charging}].
function batteryEntries(values) {
  var out = []
  function push(label, levelId, chargingId) {
    var level = levelFromFraction(values[levelId])
    var charging = chargingId ? String(values[chargingId] || "").toLowerCase() === "yes" : false
    out.push({ label: label, level: level, charging: charging })
  }
  if (BATTERY_SINGLE in values) push("Battery", BATTERY_SINGLE, null)
  else {
    if (BATTERY_LEFT in values) push("Left", BATTERY_LEFT, CHARGING_LEFT)
    if (BATTERY_RIGHT in values) push("Right", BATTERY_RIGHT, CHARGING_RIGHT)
    if (BATTERY_CASE in values) push("Case", BATTERY_CASE, null)
  }
  return out
}

// --------------------------------------------------------------------------
// The "when" predicates for mode-gated sound-mode rows.
// --------------------------------------------------------------------------
function whenShows(spec, values) {
  if (!spec.when) return true
  var mode = String(values[AMBIENT_SOUND_MODE] || "")
  var tMode = String(values.transparencyMode || "")
  var ncMode = String(values.noiseCancelingMode || "")
  switch (spec.when) {
    case "NoiseCanceling": return mode === MODE_NOISE_CANCELING
    case "TransparencyMode": return mode === MODE_TRANSPARENCY
    case "TransparencyManual": return mode === MODE_TRANSPARENCY && tMode === "Manual"
    case "NoiseCancelingMode": return mode === MODE_NOISE_CANCELING
    case "NoiseCancelingManual": return mode === MODE_NOISE_CANCELING && ncMode === "Manual"
    case "NoiseCancelingMultiScene": return mode === MODE_NOISE_CANCELING && ncMode === "MultiScene"
    default: return true
  }
}

// Collapse the CLI's stderr into one line the panel can show.
function elideError(text) {
  var value = String(text || "").replace(/\s+/g, " ").trim()
  return value.length > MAX_ERROR_CHARS ? value.substring(0, ELIDED_ERROR_CHARS) + "…" : value
}
