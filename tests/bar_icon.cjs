const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const panel = fs.readFileSync('Panel.qml', 'utf8');
const button = panel.slice(panel.indexOf('  WidgetButton {'), panel.indexOf('  KeyboardPanel {'));
assert.ok(button.includes('id: button'), 'the bar uses a WidgetButton');
assert.ok(!button.includes('iconComponent:'), 'do not normalize the icon and battery text as one glyph');
assert.match(button, /hasVisualContent: true/, 'custom content keeps the button visible and interactive');
assert.match(button, /labelVisible: false/, 'do not render the built-in text label');
assert.match(button, /fixedWidth: vertical \? -1 : slotSize/);
assert.match(button, /fixedHeight: vertical \? slotSize : -1/);
assert.match(button, /scale: button\.pressScale/, 'preserve native press feedback');
assert.match(button, /iconSize: Style\.space\(12\)/, 'device icon retains its own size');
assert.match(button, /font\.pixelSize: Style\.font\.caption/, 'battery text retains its own size');
assert.match(button, /columns: bar && bar\.vertical \? 1 : 2/);
assert.match(button, /columns: bar && bar\.vertical \? 1 : 3/);
assert.match(button, /headphone: pods\.isHeadphone/);
const deviceIcon = button.match(/SoundcoreIcon \{([\s\S]*?)\n\s*\}/)[1];
assert.ok(!deviceIcon.includes('transform:'), 'battery text must not shift the device icon off the bar center');
assert.match(button, /batteryFontMetrics\.tightBoundingRect\("0"\)\.height/, 'optically center percentage digits instead of moving the icon');
assert.match(button, /Qt\.RightButton\) root\.cycleBatteryDisplay\(\)/);
assert.match(button, /else root\.toggle\(\)/);
const manifest = JSON.parse(fs.readFileSync('manifest.json', 'utf8'));
const percentageSetting = manifest.barWidget.schema.find(setting => setting.key === 'showBatteryPercent');
assert.equal(percentageSetting.type, 'boolean');
assert.equal(percentageSetting.defaultValue, true);
assert.equal(manifest.barWidget.defaults.showBatteryPercent, true);
const visibility = panel.match(/readonly property bool barBatteryVisible: (.+)/)[1];
for (const showBatteryPercent of [false, true]) {
  for (const batteryDisplayMode of [0, 1, 2]) {
    for (const connected of [false, true]) {
      assert.equal(vm.runInNewContext(visibility, {
        showBatteryPercent, batteryDisplayMode, pods: {hasEarbuds: connected}
      }), showBatteryPercent && batteryDisplayMode !== 0 && connected);
    }
  }
}
console.log('PASS bar icon: unscaled battery layout, both orientations, device selection and click actions');
console.log('PASS battery percentage toggle: schema defaults and visibility for every display/connection mode');
const save = {running: false};
const context = vm.createContext({barBatteryPercentSave: save,
  root: {moduleName: manifest.id, showBatteryPercent: true}});
vm.runInContext(panel.match(/^  function toggleBarBatteryPercent\(\) \{[\s\S]*?^  \}/m)[0], context);
context.toggleBarBatteryPercent();
assert.deepEqual(Array.from(save.command), ['omarchy', 'bar', 'set', manifest.id, 'showBatteryPercent', 'false', '--json']);
assert.equal(save.running, true);
context.root.showBatteryPercent = false;
context.toggleBarBatteryPercent();
assert.equal(save.command[5], 'false', 'do not overwrite an in-flight save');
save.running = false;
context.toggleBarBatteryPercent();
assert.equal(save.command[5], 'true');
assert.match(panel, /onActivated: root\.toggleBarBatteryPercent\(\)/);
console.log('PASS widget toggle: saves both values and guards overlapping writes');
