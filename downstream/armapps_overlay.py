"""Route the ARM card's own dialogs through the Chinese wrappers; nothing else changes."""
from progress_overlay import replace_once

# The Homebrew consent text is assembled from up to three sentences, so the fork writes the Chinese sentences
# in place instead of keeping one translation per combination.
BREW_BEFORE = '''        let a = NSAlert()
        a.messageText = "Set up Homebrew?"
        a.informativeText = (wantArm ? "ARM Homebrew goes in /opt/homebrew and installs Homebrew's Apple-silicon packages, translated for this Mac (the first install of a big package can take a while). " : "")
            + (wantIntel ? "Intel Homebrew goes in /usr/local and runs natively; Homebrew no longer publishes Intel packages for most formulae, so it usually builds them from source. " : "")
            + "In Terminal, brew is the \\(primary == "arm" ? "ARM" : "Intel") one; abrew is always ARM and ibrew always Intel. macOS asks for your password once, to create the folders."'''

BREW_AFTER = '''        let a = ChineseAlert()
        a.messageText = "设置 Homebrew？"
        a.informativeText = (wantArm ? "ARM Homebrew 安装到 /opt/homebrew，安装 Homebrew 的 Apple 芯片软件包，并为本机翻译后运行（大型软件包首次安装可能需要一段时间）。" : "")
            + (wantIntel ? "Intel Homebrew 安装到 /usr/local，原生运行；Homebrew 已不再为多数软件包发布 Intel 版本，因此通常从源码构建。" : "")
            + "在终端里，brew 是 \\(primary == "arm" ? "ARM" : "Intel") 版本；abrew 始终是 ARM，ibrew 始终是 Intel。macOS 会请求一次密码，用于创建这些文件夹。"'''

# macOS 15 的 Swift 6.0 在 CI 上算不出这一长串拼接的类型（"unable to type-check this expression in reasonable
# time"）；拆成多次 += 得到完全相同的字符串，新编译器同样接受。
CHAIN_BEFORE = r'''            c += "todo=''; for d in " + dirs.joined(separator: " ") + "; do "
                + "rootchain \"$(/usr/bin/dirname \"$d\")\" || continue; "
                + "if [ -L \"$d\" ]; then echo \"STOP: $d is a symbolic link\"; exit 1; fi; "
                + "if [ -e \"$d\" ] && [ ! -d \"$d\" ]; then echo \"STOP: $d is not a folder\"; exit 1; fi; "
                + "[ -d \"$d\" ] || /bin/mkdir \"$d\"; "
                + "if rootdir \"$d\"; then todo=\"$d $todo\"; fi; done; "
                + "for d in $todo; do rootchain \"$(/usr/bin/dirname \"$d\")\" || { echo \"STOP: a folder above $d changed\"; exit 1; }; "
                + "/bin/chmod -h ug=rwx \"$d\"; /usr/sbin/chown -h \"$u:$g\" \"$d\"; done; "'''

CHAIN_AFTER = r'''            c += "todo=''; for d in " + dirs.joined(separator: " ") + "; do "
            c += "rootchain \"$(/usr/bin/dirname \"$d\")\" || continue; "
            c += "if [ -L \"$d\" ]; then echo \"STOP: $d is a symbolic link\"; exit 1; fi; "
            c += "if [ -e \"$d\" ] && [ ! -d \"$d\" ]; then echo \"STOP: $d is not a folder\"; exit 1; fi; "
            c += "[ -d \"$d\" ] || /bin/mkdir \"$d\"; "
            c += "if rootdir \"$d\"; then todo=\"$d $todo\"; fi; done; "
            c += "for d in $todo; do rootchain \"$(/usr/bin/dirname \"$d\")\" || { echo \"STOP: a folder above $d changed\"; exit 1; }; "
            c += "/bin/chmod -h ug=rwx \"$d\"; /usr/sbin/chown -h \"$u:$g\" \"$d\"; done; "'''

EDITS = [
    ('        let a = NSAlert()\n        a.messageText = "Turn off ARM apps?"',
     '        let a = ChineseAlert()\n        a.messageText = "Turn off ARM apps?"'),
    ('        let panel = NSOpenPanel()\n        panel.allowedContentTypes = [.applicationBundle]',
     '        let panel = ChineseOpenPanel()\n        panel.allowedContentTypes = [.applicationBundle]'),
    (BREW_BEFORE, BREW_AFTER),
    (CHAIN_BEFORE, CHAIN_AFTER),
]


def instrument(source):
    for before, after in EDITS:
        source = replace_once(source, before, after)
    return source


def strip(source):
    for before, after in reversed(EDITS):
        source = replace_once(source, after, before)
    return source
