"""Reversible App-only scheduling hooks; the installer and swap script stay upstream."""
from progress_overlay import replace_once

EDITS = [
    ('    func updateApp() {\n        let fail: (String) -> Void = { self.send("appupd", ["state": "error", "why": $0]) }',
     '    func updateApp() {\n        guard automaticAppUpdates.beginUpdate(version: latestApp?.version) else { return }\n        let fail: (String) -> Void = { self.appUpdateFailed($0) }'),
    ('            let backup = support.appendingPathComponent("app-update/previous.app"), swap = work.appendingPathComponent("swap.sh")',
     '            self.replaceAppWhenIdle(version: l.version) { [self] in\n            let backup = support.appendingPathComponent("app-update/previous.app"), swap = work.appendingPathComponent("swap.sh")'),
    ('            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }',
     '            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }\n            }'),
    ('        guard ["", "flicker"].contains(sample) else { return }\n        let a = ChineseAlert()',
     '        guard ["", "flicker"].contains(sample) else { return }\n        automaticAppUpdates.logsStarted()\n        let a = ChineseAlert()'),
]

def instrument(source):
    for before, after in EDITS: source = replace_once(source, before, after)
    return source

def strip(source):
    for before, after in reversed(EDITS): source = replace_once(source, after, before)
    return source
