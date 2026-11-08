#!/usr/bin/env python3
"""Reapply the native downstream to a known upstream tree; missing anchors fail closed."""
import argparse
import json
import pathlib
import re
import shutil
import subprocess
from progress_overlay import instrument_source, instrument_setup
from auto_update_overlay import instrument as instrument_auto_update
from proxy_overlay import instrument as instrument_proxy
from armapps_overlay import instrument as instrument_arm_apps

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
    source = replace(source, '    let native = NativeModel()', '    let native = NativeModel()\n    let appUpdateClient = AppUpdateClient()\n    let automaticAppUpdates = AutomaticAppUpdates()')
    begin = source.index('        let cfg = WKWebViewConfiguration()')
    end = source.index('        NSApp.activate(ignoringOtherApps: true)', begin)
    source = source[:begin] + '''        native.action = { [weak self] command in self?.perform(command) }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = Downstream.appName
        window.contentMinSize = NSSize(width: 820, height: 600)
        window.contentMaxSize = NSSize(width: 820, height: 600)
        window.collectionBehavior = [.fullScreenNone]
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        if let i = CommandLine.arguments.firstIndex(of: "--ui-page"), i + 1 < CommandLine.arguments.count {
            native.selected = CommandLine.arguments[i + 1]
        }
        window.contentView = NSHostingView(rootView: NativeRoot(model: native))
        let menu = NSMenu(); let item = NSMenuItem(); let submenu = NSMenu()
        submenu.addItem(withTitle: "退出 1401 中文版", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = submenu; menu.addItem(item); NSApp.mainMenu = menu
        // NSScreen.main follows keyboard focus, so center() opened the window on whichever display held the
        // pointer. Open on the primary display (the one with the menu bar) instead.
        if let primary = NSScreen.screens.first {
            let area = primary.visibleFrame
            window.setFrameOrigin(NSPoint(x: area.midX - window.frame.width / 2,
                                          y: area.midY - window.frame.height / 2))
        }
        window.makeKeyAndOrderFront(nil)
        native.testerOn = Tester.isOn
        perform(["act": "early"])
        // The page asks for the ARM card's state once it is up, exactly as app.js does on load.
        perform(["act": "arm", "op": "status"])
        if CommandLine.arguments.contains("--ui-snapshot") {
            native.receive("scan", ["arch": "x86_64", "macos": "26.1", "major": 26, "opencore": "REL-110", "kexts": 4,
                "metal": ["NVIDIA GeForce RTX 3080"], "gpus": [["name": "NVIDIA GeForce RTX 3080", "supported": true]],
                "packages": [], "installedDriverVersion": Package.version, "version": Package.version])
            native.receive("usb", [
                "controllers": [["key": "XHC0", "controller": "XHC0", "vendor": "8086", "device": "7A60",
                    "ports": [["name": "HS01", "usb3": false, "devices": [
                        "USB Audio Interface with a deliberately long descriptive device name to verify complete wrapping"]]]]],
                "seen": ["XHC0": ["HS01"]]])
            if CommandLine.arguments.contains("--ui-progress") {
                switch native.selected {
                case "drv":
                    native.tasks.begin(["act": "scan"])
                    native.driverUpdate = true; native.appUpdate = true
                    native.texts["updr"] = "下载已校验，正在安装驱动…"
                    native.tasks.begin(["act": "updateDriver"])
                    native.tasks.receive("run", ["state": "start", "mode": "install"])
                    native.tasks.receive("taskProgress", ["task": "setup", "fraction": 0.65])
                    native.tasks.begin(["act": "updateApp"])
                    native.tasks.receive("taskProgress", ["task": "appUpdate", "fraction": 0.85])
                case "efi": native.checkingEFI = true; native.texts["efichkr"] = "正在读取 EFI…"; native.tasks.begin(["act": "checkEfi"])
                case "tools": native.tasks.begin(["act": "mountEfi"]); native.tasks.begin(["act": "verbose"])
                case "usb": native.watching = true; native.tasks.begin(["act": "usbStart"])
                case "crash":
                    native.collecting = true; native.tasks.begin(["act": "sendLogs"])
                    native.tasks.receive("taskProgress", ["task": "logs", "fraction": 0.87, "completed": 8, "total": 16])
                    native.tasks.begin(["act": "optionalDiagnostics"])
                default: break
                }
            }
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
    source = replace(source, '        NSApp.activate(ignoringOtherApps: true)\n    }\n    func applicationShouldTerminateAfterLastWindowClosed', '        NSApp.activate(ignoringOtherApps: true)\n        if !CommandLine.arguments.contains("--ui-snapshot") { startAutomaticAppUpdates() }\n    }\n    func applicationShouldTerminateAfterLastWindowClosed')
    begin = source.index('    func webView(')
    end = source.index('    func send(', begin)
    source = source[:begin] + source[end:]
    begin = source.index('        guard let j = try? JSONSerialization.data(withJSONObject: ["event": event, "data": payload])')
    end = source.index('        switch act {', begin)
    source = source[:begin] + '''        let delivered = payload
        DispatchQueue.main.async {
            if event == "logsDone" { self.automaticAppUpdates.logsFinished() }
            self.native.receive(event, delivered)
        }
    }

    func perform(_ b: [String: Any]) {
        guard let act = b["act"] as? String else { return }
        guard automaticAppUpdates.phase != .committing else { return }
        native.tasks.begin(b, setupRunning: runningSetup, downloadPending: pendingDownload != nil, source: native.taskSource)
''' + source[end:]
    source = replace(source, r'^1401-Mac-([0-9]+\.[0-9]+(?:\.[0-9]+)?)\.zip$', r'^1401-Mac-([0-9]+\.[0-9]+(?:\.[0-9]+){0,2})\.zip$')
    source = replace(source, 'this release is not signed by NullMoth, so it was not installed', '此版本缺少 GeekAudio 更新签名，已停止安装')
    source = replace(source, "the update's signature is not from NullMoth, so it was not installed", '更新签名验证失败，已停止安装')
    # UI localization only: the underlying dialogs, consent and backend operations stay upstream.
    source = source.replace('NSAlert()', 'ChineseAlert()').replace('NSOpenPanel()', 'ChineseOpenPanel()')
    source = replace(source, '    func checkUpdate() {', '    func checkUpdate() {\n        checkForkAppUpdate()')
    source = replace(source, '                    if let a = appz, appSha.count == 64 { self.latestApp = (a.0, a.1, a.2, appSha, appSig) }', '                    // App self-update is checked independently against our own repository.')
    # 2.7.2 binds the signature to the product, the version and the SHA-256; the fork app keeps that check with its own key.
    source = replace(source, '''guard let zipData = try? Data(contentsOf: zip),
                  ReleaseSignature.verifyBound(data: zipData, product: "1401-mac", version: l.version, signatureBase64: sigText)''',
                     '''guard let zipData = try? Data(contentsOf: zip),
                  AppReleaseSignature.verifyBound(data: zipData, product: "1401-mac", version: l.version, signatureBase64: sigText)''')
    source = instrument_proxy(instrument_auto_update(instrument_source(source)))
    (ROOT / 'mac/Sources/main.swift').write_text(source)
    (ROOT / 'mac/Sources/ArmApps.swift').write_text(instrument_arm_apps(upstream(ref, 'mac/Sources/ArmApps.swift')))
    (ROOT / 'mac/Resources/nullmoth-setup.sh').write_text(instrument_setup(upstream(ref, 'mac/Resources/nullmoth-setup.sh')))
    # Mirror the page and its script: a page upstream changed now fails the translation check instead of shipping
    # the previous release's text. Neither file goes into the bundle; the native UI is built from them.
    for name in ('index.html', 'app.js'):
        (ROOT / 'mac/Resources' / name).write_text(upstream(ref, 'mac/Resources/' + name))
    for name in ('NativeUI.swift', 'NativeNavigation.swift', 'NativeModel.swift', 'NativePageView.swift', 'NativePageNode.swift', 'NativeStyle.swift', 'NativeActionButton.swift', 'NativeTask.swift', 'NativeTaskState.swift', 'NativeTaskProgress.swift', 'NativeProgressSession.swift', 'NativeProgressBridge.h', 'ChineseDialogs.swift', 'ZH.swift', 'AppUpdater.swift', 'AppUpdateRelease.swift', 'AppUpdateClient.swift', 'GitHubRetry.swift', 'AutomaticAppUpdates.swift'):
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
}}
'''
    (ROOT / 'mac/Sources/Downstream.swift').write_text(generated)
    # Driver update channels, test-build signing and telemetry retain their upstream implementation.
    for name in ('UpdateChannel.swift', 'ReleaseSignature.swift', 'TesterLane.swift', 'ReachedDesktop.swift'):
        (ROOT / 'mac/Sources' / name).write_text(upstream(ref, 'mac/Sources/' + name))
    sig = upstream(ref, 'mac/Sources/ReleaseSignature.swift').replace('enum ReleaseSignature {', 'enum AppReleaseSignature {')
    sig = re.sub(r'static let publicKeyBase64 = "[^\"]+"', f'static let publicKeyBase64 = "{public}"', sig)
    # 2.7.2 gave verifyBound a default key argument that still names the upstream enum, which the rename above
    # leaves alone: the fork app would then check its own updates against the driver key and refuse every one.
    sig = sig.replace('= ReleaseSignature.publicKeyBase64', '= AppReleaseSignature.publicKeyBase64')
    (ROOT / 'mac/Sources/AppReleaseSignature.swift').write_text(sig)
    buildscript = original_build.replace('APP=$OUT/1401.app', 'APP="$OUT/1401 中文版.app"').replace('-framework WebKit', '-framework SwiftUI')
    buildscript = replace(buildscript, 'RUN=();', 'RUN=(/usr/bin/env);')
    buildscript = replace(buildscript, '-framework SwiftUI -framework Metal', '-import-objc-header Sources/NativeProgressBridge.h -framework SwiftUI -framework Metal')
    # 2.8 compiles BundleHashes.swift last so the root shell can verify its copy of the scripts; keep "$HASHES" in place.
    buildscript = replace(buildscript, 'Sources/EfiCheck.swift Sources/TitleBar.swift "$HASHES" -o', 'Sources/EfiCheck.swift Sources/NativeUI.swift Sources/NativeNavigation.swift Sources/NativeModel.swift Sources/NativePageView.swift Sources/NativePageNode.swift Sources/NativeStyle.swift Sources/NativeActionButton.swift Sources/NativeTask.swift Sources/NativeTaskState.swift Sources/NativeTaskProgress.swift Sources/NativeProgressSession.swift Sources/ChineseDialogs.swift Sources/Downstream.swift Sources/ZH.swift Sources/AppUpdater.swift Sources/AppUpdateRelease.swift Sources/AppUpdateClient.swift Sources/GitHubRetry.swift Sources/AutomaticAppUpdates.swift Sources/AppReleaseSignature.swift "$HASHES" -o')
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
    translations.update(json.loads((ROOT / 'downstream/ui-dialogs.json').read_text()))
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
    from page_schema import build as build_pages
    build_pages()
    shutil.copy2(ROOT / 'downstream/README.md', ROOT / 'README.md')
    state = {'upstream_sha': subprocess.check_output(['git', 'rev-parse', ref], cwd=ROOT, text=True).strip(), 'driver_version': driver, 'app_version': app_version, 'build_number': build}
    (ROOT / 'downstream/state.json').write_text(json.dumps(state, indent=2) + '\n')
    print(json.dumps(state))

if __name__ == '__main__':
    p = argparse.ArgumentParser(); p.add_argument('--source-ref', default='upstream/main'); p.add_argument('--build', type=int, default=1)
    a = p.parse_args(); apply(a.source_ref, a.build)
