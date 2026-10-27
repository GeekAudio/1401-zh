#!/usr/bin/env python3
"""Enforce scope: Chinese/native UI and app updater; upstream features stay unchanged."""
import base64
import hashlib
import json
import pathlib
import re
import subprocess
root = pathlib.Path(__file__).resolve().parents[1]
state = json.loads((root / 'downstream/state.json').read_text())
def original(path):
    return subprocess.check_output(['git', 'show', state['upstream_sha'] + ':' + path], cwd=root).decode()
def section(text, start, end=None):
    begin = text.index(start)
    return text[begin:text.index(end, begin)] if end else text[begin:]
source = (root / 'mac/Sources/main.swift').read_text()
upstream = original('mac/Sources/main.swift')
normalized = source.replace('ChineseAlert()', 'NSAlert()').replace('ChineseOpenPanel()', 'NSOpenPanel()')
for begin, end in [
    ('        switch act {', '    func scan()'),
    ('    func scan()', '    var pendingDownload:'),
    ('    func startDownload(', '    func updateApp()'),
    ('    func urlSession(', None),
]:
    assert section(normalized, begin, end) == section(upstream, begin, end), 'Upstream behavior changed: ' + begin
assert source[:source.index('final class App:')].replace('import SwiftUI', 'import WebKit') == upstream[:upstream.index('final class App:')]
for name in ['UpdateChannel.swift', 'ReleaseSignature.swift', 'TesterLane.swift', 'ReachedDesktop.swift']:
    assert (root / 'mac/Sources' / name).read_text() == original('mac/Sources/' + name), 'Upstream module changed: ' + name
assert 'WKWebView' not in source and 'import WebKit' not in source
assert 'NSHostingView(rootView: NativeRoot(model: native))' in source
assert 'AppReleaseSignature.verify(zip: zip' in source
assert 'checkForkAppUpdate()' in source
app_updater = (root / 'mac/Sources/AppUpdater.swift').read_text()
assert 'Downstream.api + "/releases/latest"' in app_updater
assert 'self.latestApp =' in app_updater
assert 'self.latestApp =' not in section(source, '    func checkRelease(', '    func startDownload(')
assert '-framework WebKit' not in (root / 'mac/build.sh').read_text()
public = (root / 'downstream/release-public-key.txt').read_text().strip()
assert len(base64.b64decode(public)) == 32
assert 'static let publicKeyBase64 = "' + public + '"' in (root / 'mac/Sources/AppReleaseSignature.swift').read_text()
ui = '\n'.join((root / 'downstream' / name).read_text() for name in ['NativeUI.swift', 'NativeModel.swift', 'NativePageView.swift'])
actions = re.findall(r'^        case "([^"]+)"', section(upstream, '        switch act {', '    func scan()'), re.M)
for action in actions:
    assert '"' + action + '"' in ui, 'Native UI omitted upstream action: ' + action
translations = json.loads((root / 'mac/Resources/zh-Hans.json').read_text())
rules = json.loads((root / 'p1401/efi_rules.json').read_text())['rules']
for rule in rules:
    for text in [rule['title'], rule['what'], *rule['steps']]: assert text in translations, text
snapshot = {rule['id']: hashlib.sha256(json.dumps(rule, sort_keys=True).encode()).hexdigest() for rule in rules}
assert snapshot == json.loads((root / 'downstream/efi-source-hashes.json').read_text()), 'Review changed upstream EFI translations'
print('Scope verified: native Chinese UI and app updater only; all upstream operation bodies and channels match exactly')
from page_schema import source_document
document = source_document()
assert document == json.loads((root / 'downstream/ui-source.json').read_text()), 'Original page content or UI logic changed'
translated = json.loads((root / 'downstream/ui-zh.json').read_text())
assert set(translated) == set(document['entries']), 'Original text must be translated one for one'
def localize(node):
    node = dict(node)
    if node['text']: node['text'] = translated[node['text']]
    node['children'] = [localize(child) for child in node['children']]
    return node
assert [localize(p) for p in document['pages']] == json.loads((root / 'mac/Resources/native-pages.json').read_text())
assert [p['id'] for p in document['pages']] == ['drv', 'efi', 'tools', 'usb', 'crash']
assert '"about"' not in ui and 'Button("打开下载页面")' not in ui
print(f'Page parity verified: 5 original pages, {len(translated)} original text blocks, no added or removed static content')
