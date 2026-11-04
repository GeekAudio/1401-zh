"""Route the ARM card's own dialogs through the Chinese wrappers; nothing else changes."""
from progress_overlay import replace_once

EDITS = [
    ('        let a = NSAlert()\n        a.messageText = "Turn off ARM apps?"',
     '        let a = ChineseAlert()\n        a.messageText = "Turn off ARM apps?"'),
    ('        let panel = NSOpenPanel()\n        panel.allowedContentTypes = [.applicationBundle]',
     '        let panel = ChineseOpenPanel()\n        panel.allowedContentTypes = [.applicationBundle]'),
]


def instrument(source):
    for before, after in EDITS:
        source = replace_once(source, before, after)
    return source


def strip(source):
    for before, after in reversed(EDITS):
        source = replace_once(source, after, before)
    return source
