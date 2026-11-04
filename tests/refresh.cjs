// Read-only mocks: prove session reduction, cache invalidation and partial merges.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {spawnSync} = require('node:child_process');
process.chdir(path.resolve(__dirname, '..'));
const dir = fs.mkdtempSync('/tmp/opencode/omacore-refresh-');
const mac = 'AA:BB:CC:DD:EE:FF';
const schema = [{categoryId:'soundModes', settings:[
  {settingId:'ambientSoundMode',type:'select'},
  {settingId:'noiseCancelingMode',type:'select',setting:{options:['Manual','Adaptive'],localizedOptions:['Manual','Adaptive']}}
]}, {categoryId:'deviceInformation',settings:[{settingId:'batteryLevel',type:'information'}]}];
try {
  fs.writeFileSync(path.join(dir, 'schema.json'), JSON.stringify(schema));
  fs.writeFileSync(path.join(dir, 'bluetoothctl'), `#!/bin/sh
if [ "$TEST_DISCONNECTED" != 1 ]; then echo 'Device ${mac} soundcore Test'; fi
`, {mode:0o755});
  fs.writeFileSync(path.join(dir, 'openscq30'), `#!/usr/bin/env python
import json, os, sys
from pathlib import Path
a = sys.argv[1:]
folder = Path(os.environ['TEST_DIR'])
with (folder / 'calls').open('a') as f: f.write(json.dumps(a) + '\\n')
if a[:2] == ['paired-devices','list']:
 print(json.dumps([{'macAddress':'${mac}','model':'Test'}]))
elif 'list-settings' in a:
 print((folder / 'schema.json').read_text())
elif 'setting' in a:
 ids = [a[i+1] for i, arg in enumerate(a) if arg == '--get']
 if os.environ.get('TEST_FAIL') == '1': sys.exit(1)
 if os.environ.get('TEST_INCOMPLETE') == '1': ids = ids[:1]
 values = {'ambientSoundMode':'Normal','noiseCancelingMode':'Manual','batteryLevel':'5/5'}
 print(json.dumps([{'settingId':i,'value':{'value':values[i]}} for i in ids]))
`, {mode:0o755});
  function run(args = [], extra = {}) {
    fs.writeFileSync(path.join(dir, 'calls'), '');
    const result = spawnSync('bash', ['omacore-status', ...args], {encoding:'utf8',
      env:{...process.env,PATH:dir+':'+process.env.PATH,TEST_DIR:dir,...extra}});
    assert.equal(result.status, 0, result.stderr);
    return {data:JSON.parse(result.stdout), calls:fs.readFileSync(path.join(dir,'calls'),'utf8').trim().split('\n').filter(Boolean).map(JSON.parse)};
  }
  const cache = {mac, model:'Test', schema};
  const args = ['--cached-schema', JSON.stringify(cache)];
  let result = run();
  assert.equal(result.data.partial, false, JSON.stringify(result));
  assert.ok(result.calls.some(a => a.includes('list-settings')));
  const full = result.data;
  result = run(args);
  assert.ok(!result.calls.some(a => a.includes('list-settings')));
  assert.equal(Object.keys(result.data.values).length, 3, 'periodic polls still read all values');
  result = run([...args, '--get', 'ambientSoundMode']);
  assert.equal(result.data.partial, true);
  assert.deepEqual(result.data.values, {ambientSoundMode:'Normal'});
  assert.equal(result.calls.filter(a => a[0] === 'device').length, 1, 'readback uses one device session');
  for (const invalid of ['{}', 'invalid JSON', JSON.stringify({...cache, mac:'OTHER'}), JSON.stringify({...cache, model:'OTHER'})]) {
    result = run(['--cached-schema', invalid, '--get', 'ambientSoundMode']);
    assert.equal(result.data.partial, false);
    assert.ok(result.calls.some(a => a.includes('list-settings')));
  }
  result = run([...args, '--get', 'unsupported']);
  assert.equal(result.data.partial, false);
  assert.equal(Object.keys(result.data.values).length, 3);
  assert.equal(run(args, {TEST_FAIL:'1'}).data.readError, true);
  assert.equal(run(args, {TEST_FAIL:'1'}).data.error, 'Bluetooth is connected, but the device status could not be read.');
  assert.ok(!/earbud/i.test(fs.readFileSync('omacore-status','utf8')), 'status errors must be device-neutral');
  assert.equal(run([...args,'--get','ambientSoundMode','--get','noiseCancelingMode'], {TEST_INCOMPLETE:'1'}).data.readError, true);
  assert.equal(run(args, {TEST_DISCONNECTED:'1'}).data.connected, false);

  const model = vm.createContext({});
  vm.runInContext(fs.readFileSync('Model.js','utf8'), model);
  const service = fs.readFileSync('Service.qml','utf8');
  const timer = {stop(){},restart(){}};
  const state = {Model:model, settings:{}, deviceMatch:'', connected:true, discoveredMac:mac,
    statusScript:'status',setScript:'set', deviceChoiceProcess:{running:false},
    statusProcess:{running:false}, updating:false, pollWatchdog:timer,
    _statusSnapshot:cache, _schemaReadAt:Date.now(), _forceSchemaRefresh:false,
    _statusUsedCache:false, _readbackIds:[],_verificationIds:[],_fullReadbackRequired:false,
    _pendingWrites:{},_pendingMode:'',_windNoisePending:false,
    pendingSettleTimer:timer,settleTimer:timer,windNoiseSettleTimer:timer,
    cliMissing:false, isHeadphone:true};
  const ctx = vm.createContext(state);
  state.root = ctx;
  vm.runInContext(service.match(/^  function [\s\S]*?^  }/gm).join('\n'),ctx);
  ctx._checkLowBattery = () => {};
  ctx.refreshCodec = () => {};
  ctx._notify = () => {};
  ctx.applyStatus(JSON.stringify(full));
  ctx.applyStatus(JSON.stringify({...full,partial:true,values:{ambientSoundMode:'Transparency'}}));
  assert.equal(ctx.ancMode, 'Transparency');
  assert.equal(ctx.batteryLevel, 100, 'partial reads preserve untouched values');
  ctx._trackReadback(['set',mac,'ambientSoundMode=Normal']);
  assert.deepEqual(Array.from(ctx._readbackIds).sort(), ['ambientSoundMode','noiseCancelingMode']);
  ctx.refresh(false,ctx._readbackIds);
  assert.ok(ctx.statusProcess.command.includes('--cached-schema'));
  assert.ok(ctx.statusProcess.command.includes('--get'));
  ctx.refresh(true); // Manual refresh while busy must not be dropped.
  assert.equal(ctx._forceSchemaRefresh,true);
  ctx.statusProcess.running=false;
  ctx.refresh();
  assert.ok(!ctx.statusProcess.command.includes('--cached-schema'));
  assert.ok(!ctx.statusProcess.command.includes('--get'));
  ctx.statusProcess.running=false;
  ctx._schemaReadAt=Date.now()-300001;
  ctx.refresh();
  assert.ok(!ctx.statusProcess.command.includes('--cached-schema'), 'schema expires');
  ctx._trackReadback(['ldac-helper',mac,'true']);
  assert.equal(ctx._fullReadbackRequired,true);
  ctx._fullReadbackRequired=false;
  ctx._trackReadback(['set',mac,'customEqualizerProfile=+Test']);
  assert.equal(ctx._fullReadbackRequired,true,'changing preset choices refreshes schema');
  ctx._readbackIds=[];
  ctx._fullReadbackRequired=false;
  ctx._statusSnapshot.values = {ldac:true,spatialAudio:false,spatialAudioMode:'Music',
    presetEqualizerProfile:'Flat',customEqualizerProfile:null,volumeAdjustments:[0]};
  ctx._trackReadback(['set',mac,'spatialAudio=true']);
  assert.deepEqual(Array.from(ctx._readbackIds).sort(), Object.keys(ctx._statusSnapshot.values).sort(),
    'spatial audio verifies LDAC, EQ and all linked settings together');
  ctx._trackReadback(['set',mac,'ldac=false']);
  assert.equal(ctx._fullReadbackRequired,true,'LDAC always requests fresh schema and all values');
  ctx.applyStatus(JSON.stringify({...full, values:{...full.values, firmwareVersion:'1'}}));
  ctx.applyStatus(JSON.stringify({...full, values:{...full.values, firmwareVersion:'2'}}));
  assert.equal(ctx._forceSchemaRefresh,true,'firmware changes invalidate schema');
  ctx._noteReadError('Test failure');
  assert.equal(ctx._statusSnapshot,null);
  assert.equal(ctx.connected,true, 'read failures retain last known UI values');
  ctx.statusProcess.running=false;
  ctx.refresh();
  assert.ok(!ctx.statusProcess.command.includes('--cached-schema'));
  ctx.applyStatus(JSON.stringify(full));
  ctx.applyStatus(JSON.stringify({...full,mac:'OTHER',partial:true,values:{ambientSoundMode:'Normal'}}));
  assert.equal(ctx.statusStale,true,'reject partial results for another device');
  ctx.applyStatus(JSON.stringify(full));
  ctx._noteDisconnected('Disconnected');
  assert.equal(ctx._statusSnapshot,null);
  assert.equal(ctx._schemaReadAt,0);
  console.log('PASS refresh: cached schema, selective/linked reads, full polling, identity/TTL/error/firmware invalidation and partial merges');
} finally {
  fs.rmSync(dir,{recursive:true,force:true});
}
