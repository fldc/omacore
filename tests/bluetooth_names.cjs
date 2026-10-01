// Discovery, QML-service parsing, and an optional real Qt Quick rendering probe.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const {spawnSync} = require('node:child_process');
process.chdir(path.resolve(__dirname, '..'));
const name = 'soundcore <img src="http://127.0.0.1:8765/probe.png">';
const panel = fs.readFileSync('Panel.qml', 'utf8');
// Extract the actual bindings and format from each affected Text element.
function sink(binding) {
  const line = panel.indexOf('text: ' + binding);
  assert.ok(line >= 0, binding);
  const start = panel.lastIndexOf('Text {', line);
  const end = panel.indexOf('\n', line);
  const block = panel.slice(start, end);
  assert.match(block, /textFormat: Text\.PlainText/, binding + ' must be plain text');
  return block.match(/textFormat: [^\n]+/)[0] + '\n' + block.match(/text: [^\n]+/)[0];
}
const sinks = [sink('pods.unregisteredName +'), sink('connectionRow.label')];
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'omacore-names-'));
try {
  fs.writeFileSync(path.join(dir, 'bluetoothctl'), '#!/bin/sh\nprintf "Device AA:BB:CC:DD:EE:FF %s\\n" "$TEST_DEVICE_NAME"\n', {mode:0o755});
  fs.writeFileSync(path.join(dir, 'openscq30'), `#!/bin/sh
case "$*" in
  'paired-devices list --json')
    if [ "$TEST_REGISTERED" = 1 ]; then echo '[{"macAddress":"AA:BB:CC:DD:EE:FF","model":"Test"}]'; else echo '[]'; fi ;;
  'list-models --json') echo '[]' ;;
  *list-settings*) echo '[{"categoryId":"deviceInformation","settings":[]}]' ;;
esac
`, {mode:0o755});
  const model = vm.createContext({});
  vm.runInContext(fs.readFileSync('Model.js', 'utf8'), model);
  const service = fs.readFileSync('Service.qml', 'utf8');
  const ctx = vm.createContext({Model:model, connected:false, cliMissing:false, registeredMissing:false,
    registerProcess:{running:false}, registering:false});
  vm.runInContext(service.match(/^  function [\s\S]*?^  }/gm).join('\n'), ctx);
  // Stub side effects; exercise the real applyStatus and model parser.
  ctx._startAutoRegister = () => {};
  for (const registered of ['0', '1']) {
    const result = spawnSync('bash', ['omacore-status'], {encoding:'utf8', env:{...process.env,
      PATH:dir + ':' + process.env.PATH, TEST_DEVICE_NAME:name, TEST_REGISTERED:registered}});
    assert.equal(result.status, 0, result.stderr);
    const parsed = model.parseStatus(result.stdout);
    if (registered === '0') {
      assert.equal(parsed.registeredMissing, true);
      assert.equal(parsed.unregisteredName, name);
      ctx.applyStatus(result.stdout);
      assert.equal(ctx.unregisteredName, name);
    } else {
      assert.equal(parsed.name, name);
      assert.equal(parsed.devices[0].name, name);
    }
  }
  console.log('PASS: registered/unregistered discovery and service parsing preserve the exact Bluetooth name; both plugin sinks enforce PlainText.');
  const result = spawnSync('python', ['tests/render_bluetooth_names.py'], {
    encoding:'utf8', input:JSON.stringify({name, sinks}), timeout:20000});
  process.stdout.write(result.stdout || '');
  process.stderr.write(result.stderr || '');
  assert.equal(result.status, 0, 'Qt rendering check failed');
} finally { fs.rmSync(dir, {recursive:true, force:true}); }
