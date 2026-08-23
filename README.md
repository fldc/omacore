<h1 align="center">Omacore</h1>

<p align="center">
  Soundcore headphones and earbuds in the <a href="https://omarchy.org">Omarchy</a> bar: battery, ambient sound mode (Noise Cancelling / Transparency / Normal) with its own per-mode settings, and the device's other settings, drawn in Omarchy's own panel idiom.
</p>

<p align="center">
  The <a href="https://omarchyplugins.com/plugin.html?id=io.github.thisisgm.omapods">omapods</a> plugin does this for AirPods. Omacore is the same idea for Soundcore.
</p>

## Install

```bash
omarchy plugin add https://github.com/birajdotdev/omacore.git --enable
```

Then follow **Setup** below to point it at your earbuds.

## What it shows

The panel is schema-driven: on connect it runs `openscq30 device -a <mac>
list-settings --json` and renders only the sections and rows the device actually
exposes. Depending on the device it can show:

- **Which device** — the panel title shows the friendly model name from the
  "OpenSCQ30 model id" setting, not a generic "Soundcore".
- **Battery** — a single headphone battery, or Left / Right / Case for earbuds,
  shown as a rounded percent (Soundcore's hardware reports ten discrete steps).
- **Sound mode** — Noise Cancellation, Transparency or Normal, switched with one
  click or `n`/`t`/`o`. Each mode reveals its own settings when the firmware
  reports them: ANC mode (Manual / Adaptive / Multi-Scene) with a 1-5 manual
  level or scene picker, real-time adaptive ANC, wind noise suppression, and the
  transparency mode (Talk Mode / Fully Transparent / Vocal Mode) with its level.
- **Equalizer** — the preset equalizer profile.
- **Settings** (collapsible) — LDAC, voice prompts, low-battery prompt, auto
  power-off, dual connections.
- **Buttons** (collapsible) — the in-cycle mode toggles.
- **Volume limiter** (collapsible) — limit-high-volume toggle, dB limit and
  refresh rate.
- **Sound Effects** (earbuds) — spatial audio / sound-effect mode.

Battery and Sound Mode are always open; Settings, Buttons and Volume Limiter are
collapsible groups. The bar icon is a headphone glyph for over-ear models and the
earbuds glyph otherwise. Everything above is only shown when the device reports
the setting at all, so `openscq30 device -a <mac> list-settings --json` is the
source of truth; each setting is wired through
`Model.js`/`Service.qml`/`Panel.qml`.

## How it works

Unlike [omapods](https://github.com/thisisgm/omarchy-pods) (AirPods, which
speaks Apple's own BLE protocol via a background daemon), there is no
background daemon here. [OpenSCQ30](https://github.com/Oppzippy/OpenSCQ30)'s
CLI opens a fresh Bluetooth connection on every invocation, so this widget:

1. Discovers the device's settings with
   `openscq30 device -a <mac> list-settings --json`.
2. Polls only the settings it knows how to render that the device exposes, via
   `openscq30 device -a <mac> setting -g … --json` every `pollIntervalSec`
   seconds (30 by default).
3. Applies a click by running `setting -s <settingId>=<value>`.

Every `openscq30` invocation is wrapped in an OS `flock`, so the one bar per
monitor never opens two BLE connections at once (`UUID already registered`).
Rapid writes are debounced into a single batched `-s … -s …` invocation, and the
panel holds the intended value optimistically until the device confirms it on the
next poll. Disconnects are debounced so a transient BLE hiccup doesn't flap the
icon or spam a notification.

## Requirements

- **[OpenSCQ30](https://github.com/Oppzippy/OpenSCQ30)'s CLI**, `openscq30`,
  on `PATH` (or point the "Path to the openscq30 CLI" setting at it). It is
  free/open-source (GPL-3.0-or-later) and not written by or affiliated with
  this plugin's author — it just happens to be the CLI this widget shells
  out to.

  **Version matters for newer devices.** R60i NC / P31i support landed in
  OpenSCQ30 v2.10.0; the `openscq30-cli-bin` AUR package was pinned to
  v2.7.0 at the time this was written (check `pacman -Qi openscq30-cli-bin`
  / the AUR page — it may since have caught up). If `openscq30 list-models`
  doesn't list `SoundcoreD1202C`, skip the AUR package and grab the official
  binary release instead:

  ```bash
  mkdir -p ~/.local/opt/openscq30
  gh release download vX.Y.Z -R Oppzippy/OpenSCQ30 \
    -p 'openscq30-cli-linux-x86_64' -D ~/.local/opt/openscq30
  chmod +x ~/.local/opt/openscq30/openscq30-cli-linux-x86_64
  # Point the plugin's "Path to the openscq30 CLI" setting at that file,
  # since it won't be on PATH under that name.
  ```

  Otherwise, install the prebuilt AUR package:

  ```bash
  yay -S openscq30-cli-bin
  # or, to build from source instead of using the prebuilt binary:
  yay -S openscq30-cli
  ```

- Earbuds paired over the normal Bluetooth flow first (`omarchy bluetooth
  device` or the stock Bluetooth panel).

## Setup

1. Install `openscq30` (above, picking whichever path gets you a build new
   enough for your model) and pair your earbuds over Bluetooth as usual.

2. Find the MAC address:

   ```bash
   bluetoothctl devices | grep -i soundcore
   ```

3. Register the device with OpenSCQ30 (its CLI keeps its own small database
   mapping MAC address → model, separate from BlueZ's pairing):

   ```bash
   openscq30 paired-devices add -a AA:BB:CC:DD:EE:FF -m SoundcoreD1202C
   ```

   Use `SoundcoreD1202C` for the **R60i NC**, `SoundcoreD1202` for the
   **P31i**. Run `openscq30 list-models` to see every supported model id —
   the exact id string (and whether it's prefixed `Soundcore...`) has
   changed between OpenSCQ30 versions, so trust `list-models` over any id
   written down here.

4. Sanity-check it talks to the earbuds:

   ```bash
   openscq30 device -a AA:BB:CC:DD:EE:FF list-settings --json | less
   ```

5. Install and enable the plugin (skip `add` if you already ran the
   **Install** command above), then set the same MAC address in its settings:

   ```bash
   omarchy plugin add https://github.com/birajdotdev/omacore.git --enable
   omarchy bar set io.github.birajdotdev.omacore macAddress "AA:BB:CC:DD:EE:FF"
   # If openscq30 isn't on PATH under that name (see Requirements above):
   omarchy bar set io.github.birajdotdev.omacore ctlPath "/full/path/to/openscq30"
   ```

   Settings can also be edited later from the Omarchy menu → Plugins, or
   directly in `~/.config/omarchy/shell.json`.

## Update / Remove

```bash
omarchy plugin update io.github.birajdotdev.omacore
omarchy plugin remove io.github.birajdotdev.omacore
```

`openscq30` and its paired-device database are untouched — remove them
separately with your AUR helper and `openscq30 paired-devices remove -a
<mac>` if you no longer want them.

## Keyboard

| Key | Action |
|-----|--------|
| `j` / `k`, `↓` / `↑` | move between rows |
| `←` / `→` | adjust the Manual ANC level, when it's the focused row |
| `enter` / `space` | activate the current row |
| `n` | Noise Cancellation |
| `t` | Transparency |
| `o` | Normal |
| `w` | toggle wind noise suppression (while in Noise Cancellation, if supported) |
| `r` | refresh |
| `tab` | move to the next panel |
| `esc` | close |

Every other setting (scene, transparency mode, sound effect) is reached by
moving the cursor to its row and pressing `enter`/`space`, or by clicking it
directly. The ANC Mode dropdown works the same way to open it; once open, its
own `j`/`k`/`↓`/`↑` and `enter` pick an option and `esc` closes it without
closing the panel. For a toggle row (wind noise suppression, real-time
adaptive ANC), a mouse click only registers on the switch itself, not the
row's label — keyboard `enter`/`space` on the row still works either way.

Left click opens the panel.

## Settings

| Setting | Default | Notes |
|---------|---------|-------|
| Bluetooth MAC address | empty | Required. Same address used in `paired-devices add`. |
| OpenSCQ30 model id | `SoundcoreD1202C` | Reference only, for the `paired-devices add` command above. |
| Poll interval (seconds) | 30 | How often the widget re-runs `openscq30 device ... setting -g ...`. |
| Path to the openscq30 CLI | empty | Leave empty to find `openscq30` on `PATH`. |
| Hide when unreachable | on | Leaves the bar entirely rather than sitting there with nothing to say. |
| Desktop notifications | on | Notifies on disconnect and when a bud/case battery drops to 20% or below (once per drop, via `omarchy-notification-send`). |

## Credits

The hard part is not this panel. It is
[OpenSCQ30](https://github.com/Oppzippy/OpenSCQ30) by **Oppzippy**, which
reverse-engineered Soundcore's BLE/RFCOMM control protocol across dozens of
devices. This panel only shells out to its CLI and draws what comes back.

## Licence

MIT. See [LICENSE](LICENSE). This plugin vendors no OpenSCQ30 code — it only
invokes the separately-installed `openscq30` binary, which is GPL-3.0-or-later
under its own project.
