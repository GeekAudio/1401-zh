#!/usr/bin/env python3
"""Release gates for native UI, project routing, translation coverage and no automatic telemetry."""
import base64
import hashlib
import json
import pathlib
import re

root = pathlib.Path(__file__).resolve().parents[1]
source = (root / 'mac/Sources/main.swift').read_text()
channel = (root / 'mac/Sources/UpdateChannel.swift').read_text()
build = (root / 'mac/build.sh').read_text()
config = json.loads((root / 'downstream/config.json').read_text())
assert 'WKWebView' not in source and 'import WebKit' not in source
assert 'NSHostingView(rootView: NativeRoot(model: native))' in source
assert '-framework WebKit' not in build
assert 'Downstream.packageURL(' in source
assert 'api.github.com/repos/' + config['repository'] in channel
assert 'nullmothsystems.com' not in channel
assert 'self.web.' not in source
assert 'ReachedDesktop.arm(' not in source
assert 'exit(Tester.report())' not in source
send_logs = source[source.index('    func sendLogs('):source.index('    func crashReportFromWindow()')]
assert 'uploadReports(' not in send_logs and 'ReportPreview.show(export)' in send_logs
assert 'Data(redact(text).utf8)' in send_logs
assert 'static let publicKeyBase64 = "' + (root / 'downstream/release-public-key.txt').read_text().strip() + '"' in (root / 'mac/Sources/ReleaseSignature.swift').read_text()
assert len(base64.b64decode((root / 'downstream/release-public-key.txt').read_text())) == 32
translations = json.loads((root / 'mac/Resources/zh-Hans.json').read_text())
for rule in json.loads((root / 'p1401/efi_rules.json').read_text())['rules']:
    for text in [rule['title'], rule['what'], *rule['steps']]: assert text in translations, text
snapshot = {rule['id']: hashlib.sha256(json.dumps(rule, sort_keys=True).encode()).hexdigest() for rule in json.loads((root / 'p1401/efi_rules.json').read_text())['rules']}
baseline = json.loads((root / 'downstream/efi-source-hashes.json').read_text())
assert snapshot == baseline, 'Upstream EFI rule content changed; review the Chinese translation before publishing'
assert '-nvrmnoflip' not in (root / 'downstream/NativeUI.swift').read_text(), 'UI must not silently add machine-specific boot flags'
print('Native UI, GitHub routing, translation coverage, public key and local-only diagnostics: OK')
