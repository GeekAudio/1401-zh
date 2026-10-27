#!/usr/bin/env python3
"""Reapply the native downstream to a known upstream tree; missing anchors fail closed."""
import argparse
import json
import pathlib
import re
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONFIG = json.loads((ROOT / 'downstream/config.json').read_text())

def replace(text, old, new, count=1):
    if text.count(old) != count:
        raise RuntimeError(f'Upstream changed: expected {count} occurrence(s) of {old[:95]!r}, found {text.count(old)}')
    return text.replace(old, new)

def upstream(ref, path):
    return subprocess.check_output(['git', 'show', f'{ref}:{path}'], cwd=ROOT).decode()

def apply(ref, build):
    source = upstream(ref, 'mac/Sources/main.swift')
    driver = re.search(r'struct Package \{\s+static let version = "([^"]+)"', source).group(1)
    original_build = upstream(ref, 'mac/build.sh')
    app_version = re.search(r'CFBundleShortVersionString</key><string>([^<]+)', original_build).group(1) + '.' + str(build)
    source = replace(source, 'import WebKit', 'import SwiftUI')
    source = replace(source, 'NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKUIDelegate, URLSessionDownloadDelegate', 'NSObject, NSApplicationDelegate, URLSessionDownloadDelegate')
    source = replace(source, 'var web: WKWebView!', 'let native = NativeModel()')
    begin = source.index('        let cfg = WKWebViewConfiguration()')
    end = source.index('        NSApp.activate(ignoringOtherApps: true)', begin)
    source = source[:begin] + '''        native.action = { [weak self] command in self?.perform(command) }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 820),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = Downstream.appName
        window.minSize = NSSize(width: 960, height: 680)
        window.contentView = NSHostingView(rootView: NativeRoot(model: native))
        let menu = NSMenu(); let item = NSMenuItem(); let submenu = NSMenu()
        submenu.addItem(withTitle: "关于 1401 中文版", action: #selector(showAbout), keyEquivalent: "")
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "退出 1401 中文版", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = submenu; menu.addItem(item); NSApp.mainMenu = menu
        window.center(); window.makeKeyAndOrderFront(nil)
        perform(["act": "early"])
        if CommandLine.arguments.contains("--ui-snapshot") {
            native.receive("scan", ["arch": "x86_64", "macos": "26.1", "major": 26, "opencore": "REL-110", "kexts": 4,
                "metal": ["NVIDIA GeForce RTX 3080"], "gpus": [["name": "NVIDIA GeForce RTX 3080", "supported": true]],
                "packages": [], "installedDriverVersion": Package.version])
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if let i = CommandLine.arguments.firstIndex(of: "--ui-snapshot"), i + 1 < CommandLine.arguments.count,
                   let view = self.window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[i+1]))
                }
                NSApp.terminate(nil)
            }
        } else { perform(["act": "scan"]) }
''' + source[end:]
    begin = source.index('    func webView(')
    end = source.index('    func send(', begin)
    source = source[:begin] + '''    @objc func showAbout() { native.selected = "about" }

''' + source[end:]
    begin = source.index('        guard let j = try? JSONSerialization.data(withJSONObject: ["event": event, "data": payload])')
    end = source.index('        switch act {', begin)
    source = source[:begin] + '''        let delivered = payload
        DispatchQueue.main.async { self.native.receive(event, delivered) }
    }

    func perform(_ b: [String: Any]) {
        guard let act = b["act"] as? String else { return }
''' + source[end:]
    source = replace(source, 'URL(string: "https://github.com/nullmoth/nvidia-macos-driver/releases/download/v' + driver + '/nullmoth-nvidia-' + driver + '.tar.gz")!', 'Downstream.packageURL("nullmoth-nvidia-' + driver + '.tar.gz")')
    source = replace(source, 'URL(string: "https://nullmothsystems.com/#send")!', 'URL(string: Downstream.issues)!')
    source = replace(source, '.appendingPathComponent("NullMoth")', '.appendingPathComponent("1401-zh")')
    source = replace(source, '.appendingPathComponent("Logs/NullMoth")', '.appendingPathComponent("Logs/1401-zh")')
    source = replace(source, r'^1401-Mac-([0-9]+\.[0-9]+(?:\.[0-9]+)?)\.zip$', r'^1401-Mac-([0-9]+\.[0-9]+(?:\.[0-9]+){0,2})\.zip$')
    source = replace(source, 'this release is not signed by NullMoth, so it was not installed', '此版本缺少 GeekAudio 更新签名，已停止安装')
    source = replace(source, "the update's signature is not from NullMoth, so it was not installed", '更新签名验证失败，已停止安装')
    source = replace(source, 'let panel = NSOpenPanel(); panel.title = "Choose a saved diagnostics receipt"', 'let panel = NSOpenPanel(); panel.title = "选择已保存的诊断回执"')
    # Export diagnostics locally. GitHub has no anonymous attachment upload API; never pretend an upstream uploader is ours.
    begin = source.index('        let a = NSAlert()\n', source.index('    func sendLogs('))
    end = source.index('        DispatchQueue.global().async {', begin)
    source = source[:begin] + '''        let a = NSAlert()
        a.messageText = sample == "flicker" ? "采集 20 秒闪屏诊断？" : "收集本机诊断？"
        a.informativeText = "将读取驱动状态、系统与 OpenCore 日志，并移除用户名、序列号和网络地址。系统可能询问管理员密码。报告只保存在本机，完成后可预览、编辑和另存，不会上传。"
        a.addButton(withTitle: "开始收集"); a.addButton(withTitle: "取消")
        guard a.runModal() == .alertFirstButtonReturn else { send("logsDone", ["ok": false, "why": "已取消收集。"]); return }
''' + source[end:]
    begin = source.index('            // One random value per send,', source.index('    func sendLogs('))
    end = source.index('\n        }\n    }\n\n    func crashReportFromWindow()', begin)
    source = source[:begin] + '''            // Redact every retained file before the preview or Finder exposes it.
            do {
                let export = try SavedReports.session(in: logs.appendingPathComponent("Exports"))
                for file in files + pendingFiles {
                    guard let data = try? Data(contentsOf: file), data.count <= 4 * 1024 * 1024,
                          let text = String(data: data, encoding: .utf8) else { continue }
                    let clean = Data(redact(text).utf8)
                    _ = try SavedReports.create(clean, in: export, name: file.lastPathComponent)
                }
                DispatchQueue.main.async {
                    ReportPreview.show(export)
                    self.send("logsDone", ["ok": true, "ids": [], "errors": collectionErrors, "localPath": export.path])
                }
            } catch { self.send("logsDone", ["ok": false, "why": "无法保存脱敏报告：\\(error.localizedDescription)"]) }
''' + source[end:]
    source = replace(source, 'NSWorkspace.shared.activateFileViewerSelecting([dst]); NSWorkspace.shared.open(uploadPage)', 'NSWorkspace.shared.activateFileViewerSelecting([dst])')
    # Disable upstream automatic telemetry in this downstream; installer operations remain the upstream implementation.
    begin = source.index('        if mode == "install" {\n            let a = NSAlert()')
    end = source.index('        let log: URL', begin)
    source = source[:begin] + source[end:]
    source = replace(source, 'var reachedDesktopConsent = false', 'let reachedDesktopConsent = false')
    source = replace(source, 'if mode == "install" { ReachedDesktop.arm(consent: succeeded && reachedDesktopConsent) }', '// Downstream does not register automatic telemetry login items.')
    source = replace(source, '        let reachedDesktopConsent = false\n', '')
    source = replace(source, 'var ids: [String] = [], errs: [String] = collectionErrors, acknowledgements: [[String: String]] = []', 'var errs: [String] = collectionErrors')
    source = replace(source, '"errors": collectionErrors, "localPath": export.path', '"errors": errs, "localPath": export.path')
    source = replace(source, 'if argv.contains("--tester-report") { exit(Tester.report()) }', 'if argv.contains("--tester-report") { exit(0) }')
    source = replace(source, 'if argv.contains("--reached-desktop") { exit(ReachedDesktop.report()) }', 'if argv.contains("--reached-desktop") { exit(0) }')
    (ROOT / 'mac/Sources/main.swift').write_text(source)
    for name in ('NativeUI.swift', 'ZH.swift'):
        shutil.copy2(ROOT / 'downstream' / name, ROOT / 'mac/Sources' / name)
    cfg = CONFIG
    public = (ROOT / 'downstream/release-public-key.txt').read_text().strip()
    generated = f'''import Foundation
enum Downstream {{
    static let repository = "{cfg['repository']}"
    static let appName = "{cfg['app_name']}"
    static let source = "https://github.com/" + repository
    static let releases = source + "/releases"
    static let issues = source + "/issues/new"
    static let api = "https://api.github.com/repos/" + repository
    static func packageURL(_ name: String) -> URL {{ URL(string: releases + "/latest/download/" + name)! }}
}}
'''
    (ROOT / 'mac/Sources/Downstream.swift').write_text(generated)
    channel = upstream(ref, 'mac/Sources/UpdateChannel.swift')
    channel = replace(channel, '"NullMoth/early-updates.json"', '"1401-zh/early-updates.json"')
    channel = channel.replace('https://api.github.com/repos/nullmoth/nvidia-macos-driver', 'https://api.github.com/repos/' + cfg['repository'])
    channel = replace(channel, 'https://nullmothsystems.com/download/channels.json', 'https://github.com/' + cfg['repository'] + '/releases/latest/download/channels.json')
    channel = replace(channel, r'^v[0-9]+\.[0-9]+\.[0-9]+$', r'^v[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
    (ROOT / 'mac/Sources/UpdateChannel.swift').write_text(channel)
    sig = upstream(ref, 'mac/Sources/ReleaseSignature.swift')
    sig = re.sub(r'static let publicKeyBase64 = "[^"]+"', f'static let publicKeyBase64 = "{public}"', sig)
    (ROOT / 'mac/Sources/ReleaseSignature.swift').write_text(sig)
    tester = upstream(ref, 'mac/Sources/TesterLane.swift').replace('https://nullmothsystems.com/download/test/amd-intel/manifest.json', 'https://github.com/' + cfg['repository'] + '/releases/latest/download/amd-intel-manifest.json')
    (ROOT / 'mac/Sources/TesterLane.swift').write_text(tester)
    buildscript = original_build.replace('APP=$OUT/1401.app', 'APP="$OUT/1401 中文版.app"').replace('-framework WebKit', '-framework SwiftUI')
    buildscript = replace(buildscript, 'RUN=();', 'RUN=(/usr/bin/env);')
    buildscript = replace(buildscript, 'Sources/EfiCheck.swift Sources/TitleBar.swift -o', 'Sources/EfiCheck.swift Sources/NativeUI.swift Sources/Downstream.swift Sources/ZH.swift -o')
    begin = buildscript.index('IS=$(mktemp -d)/m.iconset;')
    end = buildscript.index('cat > "$APP/Contents/Info.plist"', begin)
    buildscript = buildscript[:begin] + '''swift ../downstream/make-icon.swift "$APP/Contents/Resources/1401.icns"
rm -f "$APP/Contents/Resources/"{index.html,app.js,app.css,guide.css,moth-mark.jpg}
''' + buildscript[end:]
    buildscript = replace(buildscript, '<key>CFBundleDevelopmentRegion</key><string>en</string>', '<key>CFBundleDevelopmentRegion</key><string>zh_CN</string>\n<key>CFBundleLocalizations</key><array><string>zh-Hans</string></array>')
    buildscript = buildscript.replace('<string>com.nullmoth.1401</string>', '<string>' + cfg['bundle_id'] + '</string>')
    buildscript = buildscript.replace('<key>CFBundleName</key><string>1401</string>', '<key>CFBundleName</key><string>1401 中文版</string>').replace('<key>CFBundleDisplayName</key><string>1401</string>', '<key>CFBundleDisplayName</key><string>1401 中文版</string>')
    buildscript = re.sub(r'(<key>CFBundleShortVersionString</key><string>)[^<]+', r'\g<1>' + app_version, buildscript)
    buildscript = re.sub(r'(<key>CFBundleVersion</key><string>)[^<]+', r'\g<1>' + str(build), buildscript)
    buildscript = buildscript.replace('1401 reads the OpenCore settings on your USB stick or disk to install the driver there.', '1401 中文版需要读取启动盘上的 OpenCore 配置，以预览并安装驱动。').replace('1401 asks macOS for your password to install the driver, and to restart when you click Restart.', '1401 中文版需要通过系统授权安装驱动，并在你选择重启时重新启动。')
    buildscript = replace(buildscript, 'codesign --force --runtime-version 15.0.0 --options runtime,library --entitlements "$ENT" -s - "$APP"', 'xattr -cr "$APP"\ncodesign --force --runtime-version 15.0.0 --options runtime,library --entitlements "$ENT" -s - "$APP"')
    (ROOT / 'mac/build.sh').write_text(buildscript)
    translations = json.loads((ROOT / 'downstream/zh-Hans.json').read_text())
    efi_translations = json.loads((ROOT / 'downstream/efi-zh.json').read_text())
    rules = json.loads(upstream(ref, 'p1401/efi_rules.json'))['rules']
    if set(efi_translations) != {rule['id'] for rule in rules}:
        raise RuntimeError('Upstream EFI rules changed; translate the new rules before publishing')
    for rule in rules:
        title, what, steps = efi_translations[rule['id']]
        if len(steps) != len(rule['steps']):
            raise RuntimeError('Upstream EFI rule steps changed: ' + rule['id'])
        translations[rule['title']] = title
        translations[rule['what']] = what
        translations.update(zip(rule['steps'], steps))
    (ROOT / 'mac/Resources/zh-Hans.json').write_text(json.dumps(translations, ensure_ascii=False, indent=2) + '\n')
    shutil.copy2(ROOT / 'downstream/README.md', ROOT / 'README.md')
    state = {'upstream_sha': subprocess.check_output(['git', 'rev-parse', ref], cwd=ROOT, text=True).strip(), 'driver_version': driver, 'app_version': app_version, 'build_number': build}
    (ROOT / 'downstream/state.json').write_text(json.dumps(state, indent=2) + '\n')
    print(json.dumps(state))

if __name__ == '__main__':
    p = argparse.ArgumentParser(); p.add_argument('--source-ref', default='upstream/main'); p.add_argument('--build', type=int, default=1)
    a = p.parse_args(); apply(a.source_ref, a.build)
