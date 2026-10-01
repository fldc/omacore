OmaCore marketplace blocker fix

The registration message and current/saved dual-connection device labels now
explicitly use `Text.PlainText`. Bluetooth names remain unchanged through
`omacore-status`, JSON parsing and Service.qml; markup in a name is rendered as
ordinary text instead of allowing Qt Quick to load an HTML image. Discovery,
registration, device controls and the explicit installer with its pinned,
SHA-256-verified OpenSCQ30 release are unchanged.

The installed Omarchy 4.0.4 implementations were inspected at
`/usr/share/omarchy/shell/Ui/PanelHero.qml` (title Text) and `Dropdown.qml`
(selected label and popup option Text). Each explicitly uses `Text.PlainText`.
These shared components protect the plugin's hero and device-picker names.
The plugin's ConnectionRow receives current/saved device labels from the
OpenSCQ30 dualConnectionsDevices schema's localizedOptions via
Model.selectOptions; its Text previously used automatic formatting too.

Regression command: `node tests/bluetooth_names.cjs` (also invoked by
`node tests/regression.cjs`). Fake Bluetooth/OpenSCQ30 executables exercise
registered and unregistered discovery with
`soundcore <img src="http://127.0.0.1:8765/probe.png">`; Model.parseStatus and
the actual Service.applyStatus preserve the unregistered name. Qt Quick Test
renders the actual text and textFormat bindings extracted from both changed
Text elements. It checks unchanged literal text and layout equal to a plain-text
reference, and observes zero /probe.png requests on a loopback-only server.
A rich-text control must request /control.png to confirm the observer works.
Qt 6.11.2 passed this test locally. This is an isolated sink rendering test,
not a full Quickshell panel or physical Bluetooth integration test. The runtime
check explicitly reports a skip when Qt Quick Test is unavailable.

Additional live-device check (2026-10-01): the connected soundcore R60i NC
(model SoundcoreD1202C) was discovered successfully. The repository's actual
Service.qml was instantiated in a temporary Quickshell harness using the
installed discovery helpers. It reported connected=true, statusStale=false,
no error, batteries 80% left / 70% right / 70% case, Transparency mode, one
available device and two dual-connection options. The running Omarchy instance
also refreshed successfully and reported Transparency through its IPC endpoint.
The malicious-name rendering regression passed again. No device name, registry
entry or control setting was changed. The installed Panel.qml differs from the
working copy; this does not establish full-panel validation of the patched UI.

Existing checks: `node tests/regression.cjs` and `node tests/navigation.cjs`.

Verification applies to an exact commit. After this fix is merged, submit a new
Verify request targeting the resulting full commit SHA, then await automated
checks and maintainer approval. Do not reuse the blocked
9109f0b56a806989a0dedf20ef87efe51555114d. Resolve the full target SHA from
the published commit; this fix does not itself grant marketplace verification.
