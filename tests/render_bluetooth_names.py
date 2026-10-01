"""Render extracted plugin Text bindings, with a loopback-only image probe.

This isolates the sinks from Quickshell/device dependencies; it is not a full
panel integration test. A rich-text control proves the HTTP observer is active.
"""
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading

payload = json.load(sys.stdin)
runner = shutil.which('qmltestrunner') or shutil.which('/usr/lib/qt6/bin/qmltestrunner')
if not runner:
    print('SKIP runtime: Qt Quick Test runner unavailable (static/discovery checks passed).')
    sys.exit(0)
requests = []

class Probe(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        requests.append(self.path)
        self.send_response(404)
        self.end_headers()

    def log_message(self, *args):
        pass

# Deliberately fail if this fixed loopback port is occupied; never use an
# external endpoint or mistake an unobserved renderer for a passing test.
server = http.server.ThreadingHTTPServer(('127.0.0.1', 8765), Probe)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    name = json.dumps(payload['name'])
    items = '\n'.join('Text { id: sink%d; %s }' % (i, binding)
                      for i, binding in enumerate(payload['sinks']))
    checks = '\n'.join('compare(sink%d.textFormat, Text.PlainText); '
                        'compare(sink%d.text, %s); '
                        'compare(sink%d.implicitWidth, reference%d.implicitWidth); '
                        'compare(sink%d.implicitHeight, reference%d.implicitHeight);'
                        % (i, i, 'reference%d.text' % i, i, i, i, i)
                        for i in range(len(payload['sinks'])))
    refs = '\n'.join('Text { id: reference%d; textFormat: Text.PlainText; text: sink%d.text }'
                     % (i, i) for i in range(len(payload['sinks'])))
    qml = '''import QtQuick
import QtTest
TestCase {
    name: "BluetoothNames"
    when: windowShown
    width: 1200; height: 200
    property var pods: ({unregisteredName: %s})
    property var connectionRow: ({label: %s})
    %s
    %s
    Text { textFormat: Text.RichText; text: '<img src="http://127.0.0.1:8765/control.png">' }
    function test_literal() {
        wait(1000)
        %s
        verify(sink0.text.indexOf(pods.unregisteredName) === 0)
        compare(sink1.text, connectionRow.label)
    }
}
''' % (name, name, items, refs, checks)
    with tempfile.TemporaryDirectory(prefix='omacore-qml-') as directory:
        Path(directory, 'tst_names.qml').write_text(qml)
        result = subprocess.run([runner, '-input', directory], text=True,
                                capture_output=True, timeout=15,
                                env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen',
                                     'QT_QUICK_BACKEND': 'software'})
        print(result.stdout, end='')
        if result.returncode:
            print(result.stderr, file=sys.stderr)
            raise AssertionError('Qt Quick rendering failed')
    assert '/control.png' in requests, 'rich-text control did not reach loopback observer'
    assert '/probe.png' not in requests, requests
    print('PASS runtime: both extracted Text sinks retain literal text and plain-text layout; zero /probe.png image requests (rich-text control observed).')
finally:
    server.shutdown()
    server.server_close()
    thread.join()
