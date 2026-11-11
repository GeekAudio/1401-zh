// Native presentation of the original 1401 pages. Backend operations remain upstream.
import SwiftUI
import AppKit

final class NativeModel: ObservableObject {
    @Published var machine: [String: Any] = [:]
    @Published var output = ""
    @Published var texts: [String: String] = [:]
    @Published var appStatus = ""
    @Published var busy = false
    @Published var downloading = false
    @Published var previewed = false
    @Published var installed = false
    @Published var package = ""
    @Published var efi = "auto" { didSet { if oldValue != efi { previewed = false } } }
    @Published var candidates: [String] = []
    @Published var driverUpdate = false
    @Published var appUpdate = false
    @Published var appUpdating = false
    @Published var driverUpdating = false
    @Published var tccGranting = false
    @Published var early = false
    @Published var testerOn = false
    @Published var collecting = false
    @Published var mappingGPU = false
    @Published var armOn = false
    @Published var armOk = false
    @Published var armCheck: [String: Any] = [:]
    @Published var armRunning = false
    @Published var armCancelling = false
    @Published var armStatusText = ""
    @Published var armLast = ""
    @Published var armMsg = ""
    @Published var armPct: Double? = nil
    @Published var armApps: [[String: String]] = []
    @Published var armRequest: [String: Any]? = nil
    @Published var armStarting = false
    @Published var armBrewPick = "both"
    @Published var armBrewPrimary = "arm"
    @Published var armBrewText = ""
    private var armBrew: [String: Any] = [:]
    // 2.9 tools state mirrors app.js events. These values are populated by the upstream
    // scan/status events; the native view submits the same command names and payloads.
    @Published var experimentalOn = Set<String>()
    @Published var hybridLevel = "copy"
    @Published var ryzenSTAPM = 13
    @Published var ryzenSlow = 14
    @Published var ryzenFast = 15
    @Published var ryzenTemp = 70
    @Published var gameModeInstalled = false
    @Published var gameModeRunning = false
    @Published var gameModeBusy = false
    @Published var gameModeText = ""
    @Published var gpuBoostText = ""
    @Published var ryzenPowerText = ""
    @Published var chosenConfigPath = ""
    @Published var configPickerBusy = false
    @Published var automaticLoginByApp = false
    private var requestedGameModeStatus = false
    @Published var checkingEFI = false
    @Published var mountingEFI = false
    @Published var tahoeReady = false
    @Published var showLog = false
    @Published var issues: [[String: Any]] = []
    @Published var controllers: [[String: Any]] = []
    @Published var seen: [String: [String]] = [:]
    @Published var picks: [String: [String: Int]] = [:]
    @Published var excluded = Set<String>()
    @Published var watching = false
    @Published var selected = "drv"
    @Published var tasks = NativeTaskState()
    private(set) var taskSource: String?
    var action: ([String: Any]) -> Void = { _ in }

    var working: Bool { busy || downloading }
    var canInstall: Bool { !working && !package.isEmpty && previewed }
    var gpus: [[String: Any]] { machine["gpus"] as? [[String: Any]] ?? [] }
    var card: [String: Any]? { gpus.first { $0["supported"] as? Bool == true } ?? gpus.first { $0["vendor"] as? String == "10DE" } }
    var metal: [String] { machine["metal"] as? [String] ?? [] }
    var driverOn: Bool { (machine["kexts"] as? Int ?? 0) >= 4 && metal.contains { $0.range(of: "NVIDIA|GeForce|RTX", options: .regularExpression) != nil } }
    var major: Int { machine["major"] as? Int ?? 0 }
    var minor: Int { machine["minor"] as? Int ?? 0 }
    var driverOsMajor: Int { machine["driverOsMajor"] as? Int ?? 0 }
    var driverNeedsSetupForCurrentOS: Bool {
        driverOsMajor > 0 && driverOsMajor != major
    }
    var xeCardVisible: Bool {
        machine["arch"] as? String == "x86_64" && machine["translated"] as? Bool != true
            && gpus.contains { $0["xe"] as? Bool == true }
            && ((major == 15 && minor >= 8) || (major == 26 && minor >= 7))
    }
    var parkedDriver: Bool { machine["safemode"] as? Bool == true && machine["record"] as? Bool == true }
    var goodPackage: [String: Any]? { (machine["packages"] as? [[String: Any]] ?? []).first { $0["ok"] as? String == "yes" } }
    var eligibility: String? {
        guard !machine.isEmpty else { return nil }
        if machine["arch"] as? String != "x86_64" || machine["translated"] as? Bool == true {
            return L10n.ui("本机使用 Apple 芯片，其图形驱动已由 Apple 提供。", "This Mac uses Apple silicon, whose graphics drivers are provided by Apple.")
        }
        if ![15,26].contains(major) {
            let version = machine["macos"] as? String ?? ""
            return L10n.ui(
                "此驱动适用于 macOS 15 Sequoia 和 macOS 26 Tahoe（测试版）；本机运行 macOS \(version)。",
                "This driver supports macOS 15 Sequoia and macOS 26 Tahoe (beta). This Mac runs macOS \(version)."
            )
        }
        let hiding = (machine["gpuHiding"] as? [String] ?? []).filter { $0 != "-wegnoigpu" }
        if card == nil && !hiding.isEmpty {
            let arguments = hiding.joined(separator: " ")
            return L10n.ui(
                "启动参数 \(arguments) 隐藏了独立显卡，因此看不到 NVIDIA 显卡。请在 OpenCore 的 config.plist 中移除对应 boot-args，重启后重新打开 1401。",
                "Boot arguments \(arguments) hide the discrete GPU, so macOS cannot see the NVIDIA GPU. Remove the matching boot-args from the OpenCore config.plist, restart, then reopen 1401."
            )
        }
        let hidden = machine["hiddenNvidia"] as? [String] ?? []
        if card == nil && !hidden.isEmpty {
            let devices = hidden.joined(separator: "、")
            return L10n.ui(
                "NVIDIA 显卡（\(devices)）位于总线上，但已对 macOS 停用，通常由 OpenCore DeviceProperties 中的 disable-gpu 属性导致。请移除该属性并重启，再打开 1401。",
                "The NVIDIA GPU (\(devices)) is present on the bus but disabled in macOS, usually by the disable-gpu property in OpenCore DeviceProperties. Remove that property, restart, then reopen 1401."
            )
        }
        if card == nil && (machine["hwModel"] as? String ?? "").hasPrefix("MacBook") {
            return L10n.ui(
                "未找到 NVIDIA 显卡。笔记本可能在 macOS 启动前由 BIOS 显卡模式或关闭独显的 SSDT 将其停用。请在 BIOS 中选择 Hybrid/MSHybrid 或 Discrete，并检查 OpenCore ACPI 中关闭独显的 SSDT，修正后重启并重新打开 1401。",
                "No NVIDIA GPU was found. The laptop's BIOS graphics mode or an SSDT may disable the GPU before macOS starts. Choose Hybrid/MSHybrid or Discrete in BIOS, and check OpenCore ACPI for an SSDT that disables the GPU. Correct it, restart, then reopen 1401."
            )
        }
        if card?["supported"] as? Bool != true {
            return L10n.ui("未找到受支持的 NVIDIA 显卡。此驱动需要 GeForce RTX 20 系列或更新显卡。", "No supported NVIDIA GPU was found. This driver requires a GeForce RTX 20 series GPU or newer.")
        }
        if (machine["opencore"] as? String ?? "").isEmpty && machine["nativeMacPro"] as? Bool != true {
            return L10n.ui("本机未报告 OpenCore。驱动所需设置保存在 OpenCore 配置中，因此没有 OpenCore 时 1401 不会安装。", "OpenCore was not detected. The driver settings are stored in the OpenCore configuration, so 1401 cannot install the driver without OpenCore.")
        }
        return nil
    }
    var hiddenOwnGPU: Bool {
        card == nil && machine["arch"] as? String == "x86_64" && machine["translated"] as? Bool != true && [15,26].contains(major) && gpus.isEmpty && (machine["hiddenNvidia"] as? [String] ?? []).isEmpty && !(machine["gpuHiding"] as? [String] ?? []).contains { $0 != "-wegnoigpu" }
    }
    var otherGPU: Bool { card == nil && machine["arch"] as? String == "x86_64" && machine["translated"] as? Bool != true && [15,26].contains(major) && gpus.contains { ["1002","8086"].contains($0["vendor"] as? String ?? "") } }
    var showSteps: Bool { !machine.isEmpty && !driverOn && !hiddenOwnGPU && !(eligibility != nil && otherGPU) && eligibility == nil }
    var verdict: String {
        guard !machine.isEmpty else { return "" }
        var text: String
        if driverOn {
            let chinese = "NullMoth 组件已加载，并且 NVIDIA Metal 设备可见。\n使用“检查更新”更新驱动，或使用下方的“移除驱动”卸载。" + (major == 15 ? "如需升级 macOS 26 Tahoe，请使用下方的“准备升级到 Tahoe”。" : "")
            let english = "The NullMoth components are loaded, and the NVIDIA Metal device is available.\nUse “Check for Updates” to update the driver, or “Remove Driver” below to uninstall it." + (major == 15 ? " To upgrade to macOS 26 Tahoe, use “Prepare for Tahoe Upgrade” below." : "")
            text = L10n.ui(chinese: chinese, english: english)
        } else if hiddenOwnGPU {
            let hiddenByBootArgument = (machine["gpuHiding"] as? [String] ?? []).contains("-wegnoigpu")
            let chinese = "macOS 未看到任何 GPU。\nOpenCore 很可能通过 disable-gpu 属性" + (hiddenByBootArgument ? "及 -wegnoigpu 启动参数" : "") + "将其停用。对于处理器内置的 Intel 或 AMD GPU，请打开「实验」标签，启用「AMD / Intel GPU 与 NPU 驱动（测试）」。关闭按钮可再次停用。启用时会下载并校验该驱动的独立安装包。"
            let english = "macOS cannot see any GPUs.\nOpenCore may have disabled them with the disable-gpu property" + (hiddenByBootArgument ? " and the -wegnoigpu boot argument" : "") + ". For an Intel or AMD GPU built into the processor, open the Lab tab and enable “AMD / Intel GPU and NPU Drivers (Test)”. The Disable button turns it off again. Enabling it downloads and verifies a separate driver package."
            text = L10n.ui(chinese: chinese, english: english)
        } else if eligibility != nil && otherGPU {
            let devices = gpus.filter { $0["vendor"] as? String != "10DE" }
                .map { $0["name"] as? String ?? "" }.joined(separator: "、")
            text = L10n.ui(
                "未找到 NVIDIA 显卡，因此 NVIDIA 驱动不适用。\n本机的 \(devices) 可在「实验」标签尝试 AMD / Intel GPU 实验性驱动。启用时会下载并校验其独立安装包。",
                "No NVIDIA GPU was found, so the NVIDIA driver does not apply.\nGo to the Lab tab to try the AMD / Intel GPU experimental driver on \(devices). Enabling it downloads and verifies a separate driver package."
            )
        } else if let why = eligibility {
            text = L10n.ui("无法在此电脑安装。\n\(why)", "The driver cannot be installed on this Mac.\n\(why)")
        } else if machine["files"] as? Bool == true && !installed && (machine["kexts"] as? Int ?? 0) >= 4 {
            text = L10n.ui(
                "驱动已加载，但 macOS 暂未显示 NVIDIA Metal 设备。\n如果笔记本内屏连接到 Intel 或 AMD 显卡且没有 MUX 切换，NVIDIA 显卡只负责连接到自身 HDMI 或 DisplayPort 的显示器，请连接后重启。其他情况请先重启一次；若仍如此，请发送日志。",
                "The driver is loaded, but macOS has not detected the NVIDIA Metal device.\nIf the laptop's internal display is connected to Intel or AMD graphics without a MUX switch, the NVIDIA GPU only drives displays connected to its own HDMI or DisplayPort outputs. Connect one and restart. Otherwise, restart once. If the issue persists, send a log."
            )
        } else if machine["files"] as? Bool == true && !installed && driverNeedsSetupForCurrentOS {
            text = L10n.ui(
                "安装驱动后，macOS 从 \(driverOsMajor) 升级到了 \(major)，因此驱动没有运行。\n需要为当前 macOS 重新设置驱动：请使用支持 macOS \(major) 的驱动包，按下方四步操作。OpenCore 设置会保留。",
                "macOS was upgraded from \(driverOsMajor) to \(major) after the driver was installed, so the driver is not running.\nSet up the driver for this version of macOS using a package that supports macOS \(major), then follow the four steps below. Your OpenCore settings will be preserved."
            )
        } else if machine["files"] as? Bool == true && !installed {
            text = L10n.ui(
                "驱动已安装，但尚未运行。\n请重新启动。如果 macOS 阻止了系统扩展，请在“隐私与安全性”中允许，然后再次重启。",
                "The driver is installed but not running.\nRestart your Mac. If macOS blocked the system extension, allow it under “Privacy & Security” and restart again."
            )
        } else {
            let name = card?["name"] as? String ?? ""
            text = L10n.ui(
                "\(name) 有可用的驱动配置。这台电脑仍需进行启动、显示和应用检查。请依次完成以下四步。",
                "A driver configuration is available for \(name). Verify startup, display output, and apps on this Mac by following the four steps below."
            )
        }
        if parkedDriver {
            text = L10n.ui(
                "本次启动的 boot-args 中包含 -nvoff，因此 NVIDIA 驱动暂未启动。可以点击“启用驱动”恢复，并在重启后加载；如果开启驱动曾导致黑屏，请先发送日志再启用。若要彻底移除驱动，请使用下方的“移除驱动”。\n\(text)",
                "The boot-args for this startup include -nvoff, so the NVIDIA driver has not started. Click “Enable Driver” to restore it, then restart to load it. If enabling the driver caused a black screen before, send a log before turning it on. To remove the driver completely, use “Remove Driver” below.\n\(text)"
            )
        }
        if machine["itlwmNeedsHeliPort"] as? Bool == true {
            text += L10n.ui(
                "\n\nWi-Fi 提示：本机使用 itlwm 驱动 Intel 无线网卡，需要通过 HeliPort 连接网络；它不会出现在 macOS 的 Wi-Fi 菜单中。请从 [HeliPort 发布页](https://github.com/OpenIntelWireless/HeliPort/releases) 下载并将 App 移到“应用程序”，然后在 HeliPort 中选择网络。若需开机自动启动，请在 HeliPort 菜单中开启“登录时启动”。",
                "\n\nWi-Fi: This Mac uses the itlwm driver for its Intel wireless card. Connect to a network using HeliPort, which does not appear in the macOS Wi-Fi menu. Download HeliPort from its [release page](https://github.com/OpenIntelWireless/HeliPort/releases), move the app to Applications, then choose a network in HeliPort. To open it at login, enable “Launch at Login” from the HeliPort menu."
            )
        }
        return text
    }
    func perform(_ act: String, _ fields: [String: Any] = [:]) {
        var command = fields; command["act"] = act
        if command["efi"] == nil { command["efi"] = efi }
        if command["pkg"] == nil { command["pkg"] = package }
        if act == "checkUpdate" { texts["updr"] = L10n.ui("正在检查…", "Checking…"); appStatus = "" }
        action(command)
    }
    func receive(_ event: String, _ data: Any) {
        tasks.receive(event, data)
        let d = data as? [String: Any] ?? [:], state = d["state"] as? String ?? ""
        let reason = ZH.text(d["why"] as? String ?? "")
        switch event {
        case "scan":
            machine = d
            experimentalOn = Set(d["experimentalOn"] as? [String] ?? [])
            automaticLoginByApp = d["autologinByApp"] as? Bool == true
            let checked = goodPackage?["path"] as? String ?? ""
            if !checked.isEmpty { package = checked }
            let crashes = d["crashes"] as? [String] ?? []
            texts["cr"] = crashes.isEmpty
                ? L10n.ui("本机没有包含该驱动的崩溃记录。", "No crash reports on this Mac mention the driver.")
                : L10n.ui("本机有 \(crashes.count) 份崩溃文件包含该驱动。", "\(crashes.count) crash reports on this Mac mention the driver.")
            // app.js requests this once at startup; keep the native button state in sync without
            // making users open the Tools page or press an extra status button.
            if !requestedGameModeStatus {
                requestedGameModeStatus = true
                perform("gm", ["op": "status"])
            }
        case "lines":
            for line in data as? [String] ?? [] {
                output += localizedSetupNote(line) + "\n"
                if line.hasPrefix("NOTE candidate "), let disk = line.split(separator: " ").dropFirst(2).first.map(String.init), !candidates.contains(disk) { candidates.append(disk); if efi == "auto" { efi = disk } }
            }
        case "run":
            busy = state == "start"
            if busy { output = ""; showLog = true; return }
            if !reason.isEmpty { showLog = true; output += reason + "\n" }
            if state == "cancelled" {
                if driverUpdating { driverUpdating = false; texts["updr"] = L10n.ui("驱动更新已取消。", "Driver update cancelled.") }
                output += L10n.ui("NOTE 已取消，未进行任何更改\n", "NOTE Cancelled. No changes were made.\n")
                perform("scan")
                return
            }
            let ok = d["ok"] as? Bool == true, mode = d["mode"] as? String ?? ""
            if mode == "dry" && ok { previewed = true }
            if mode == "install" && ok { installed = true }
            if driverUpdating && mode == "install" {
                driverUpdating = false
                texts["updr"] = ok
                    ? L10n.ui("驱动已安装，请重启以加载。", "Driver installed. Restart to load it.")
                    : L10n.ui("驱动更新已停止，请查看下方安装记录。", "Driver update stopped. See the installation log below.")
                if ok { driverUpdate = false }
            }
            if mode == "tahoe" {
                tahoeReady = ok
                texts["updt"] = ok
                    ? L10n.ui("已为 Tahoe 准备就绪，请打开“软件更新”安装 macOS 26。", "Tahoe is ready. Open Software Update to install macOS 26.")
                    : L10n.ui("Tahoe 升级准备已停止，请查看上方安装记录。", "Tahoe upgrade preparation stopped. See the installation log above.")
            }
            if mode == "tahoecancel" {
                tahoeReady = false
                texts["updt"] = ok
                    ? L10n.ui("已取消 Tahoe 升级准备，驱动和安装器设置已恢复。", "Tahoe upgrade preparation cancelled. Driver and installer settings were restored.")
                    : L10n.ui("取消操作已停止，请查看上方安装记录。", "Cancellation stopped. See the installation log above.")
            }
            perform("scan")
        case "dl":
            if state == "start" { downloading = true }
            if state == "retry" {
                let retry = L10n.ui("GitHub 直连失败，正在切换代理重试…", "GitHub is unreachable. Retrying through a proxy…")
                texts["dlp"] = retry
                if driverUpdating { texts["updr"] = retry }
            }
            if state == "progress" {
                let done = (d["done"] as? NSNumber)?.doubleValue ?? 0, total = (d["total"] as? NSNumber)?.doubleValue ?? 0
                texts["dlp"] = total > 0
                    ? L10n.ui(
                        chinese: String(format: "%.0f%%（%.1f / %.1f MB）", done / total * 100, done / 1048576, total / 1048576),
                        english: String(format: "%.0f%% (%.1f / %.1f MB)", done / total * 100, done / 1048576, total / 1048576)
                    )
                    : String(format: "%.1f MB", done / 1048576)
                if driverUpdating {
                    let amount = texts["dlp"] ?? ""
                    texts["updr"] = L10n.ui("正在下载最新驱动：\(amount)", "Downloading the latest driver: \(amount)")
                }
            }
            if ["done", "error"].contains(state) {
                downloading = false
                texts["dlp"] = state == "done" ? L10n.ui("完成，校验通过", "Complete. Verification passed.") : reason
                if state == "done" {
                    if driverUpdating { texts["updr"] = L10n.ui("下载已校验，正在安装驱动…", "Download verified. Installing driver…") }
                    perform("scan")
                } else if driverUpdating {
                    driverUpdating = false
                    texts["updr"] = reason
                }
            }
        case "upd":
            if state == "error" { texts["updr"] = reason; driverUpdate = false }
            else {
                driverUpdate = d["newer"] as? Bool == true
                let have = d["installed"] as? String ?? ""
                let latest = d["latest"] as? String ?? ""
                let prerelease = d["prerelease"] as? Bool == true
                let kind = prerelease ? L10n.ui("提前发布版本", "early release") : L10n.ui("版本", "version")
                if have.isEmpty {
                    texts["updr"] = L10n.ui(
                        "1401 无法确定已安装的驱动版本，最新\(kind)为 \(latest)，可直接更新。",
                        "1401 could not determine the installed driver version. The latest \(kind) is \(latest), and you can update now."
                    )
                } else if driverUpdate {
                    texts["updr"] = L10n.ui(
                        "已安装 \(have)，最新\(kind) \(latest)，可以更新。",
                        "Installed \(have). The latest \(kind) is \(latest), and an update is available."
                    )
                } else {
                    texts["updr"] = L10n.ui(
                        "已安装 \(have)，当前已是最新驱动（\(latest)）。",
                        "Installed \(have). The driver is up to date (\(latest))."
                    )
                }
            }
        case "appCheck":
            appUpdate = state == "checked" && d["newer"] as? Bool == true
            let have = d["have"] as? String ?? ""
            let latest = d["latest"] as? String ?? ""
            appStatus = state == "error" ? reason : appUpdate
                ? L10n.ui("App \(have) → \(latest) 已可更新。", "App \(have) → \(latest) is available.")
                : L10n.ui("App（\(have)）已是最新版本。", "App (\(have)) is up to date.")
        case "appupd":
            appUpdating = state != "error"
            let version = d["version"] as? String ?? ""
            appStatus = state == "error" ? reason
                : state == "retry" ? L10n.ui("GitHub 直连失败，正在切换代理重试…", "GitHub is unreachable. Retrying through a proxy…")
                : state == "waiting" ? L10n.ui("App 更新已校验，当前任务结束后会自动重新打开。", "The app update is verified. It will reopen automatically when the current task finishes.")
                : state == "restarting" ? L10n.ui("1401 \(version) 已校验，正在重新打开…", "1401 \(version) is verified. Reopening…")
                : L10n.ui("正在下载 1401 \(version)…", "Downloading 1401 \(version)…")
        case "tccStatus":
            tccGranting = false
            texts["tccr"] = tccStatusText(d["text"] as? String ?? "")
        case "efiCheck":
            checkingEFI = false
            if d["cancelled"] as? Bool == true { texts["efichkr"] = ""; return }
            issues = d["issues"] as? [[String: Any]] ?? []
            let partition = d["partition"] as? String ?? ""
            texts["efichkr"] = d["ok"] as? Bool == true
                ? issues.isEmpty
                    ? L10n.ui("在 \(partition) 中未发现问题。", "No issues were found on \(partition).")
                    : L10n.ui("\(partition) 有 \(issues.count) 项设置需要更改。", "\(issues.count) settings on \(partition) need changes.")
                : reason
        case "efiMount":
            mountingEFI = false
            let partition = d["partition"] as? String ?? ""
            let location = d["where"] as? String ?? ""
            texts["efimountr"] = d["cancelled"] as? Bool == true ? ""
                : d["ok"] as? Bool == true
                    ? L10n.ui("已挂载 \(partition)：\(location)", "Mounted \(partition) at \(location)")
                    : reason
        case "early":
            early = d["on"] as? Bool == true
            texts["earlyr"] = early
                ? L10n.ui("已开启：新驱动会在向所有人提供前先推送到本机。", "Enabled. New drivers will be sent to this Mac before general release.")
                : L10n.ui("已关闭：本机将在提前使用者验证版本稳定后获取更新。", "Disabled. This Mac will receive updates after early users verify a release.")
        case "gm":
            gameModeBusy = false
            gameModeInstalled = d["installed"] as? Bool == true
            gameModeRunning = d["running"] as? Bool == true
            gameModeText = !reason.isEmpty ? reason : gameModeInstalled
                ? gameModeRunning
                    ? L10n.ui("已开启：全屏运行游戏时会自动启动。", "Enabled. It starts automatically when you play a game in full screen.")
                    : L10n.ui("已安装但尚未运行：请重启，或关闭后再重新开启。", "Installed but not running. Restart your Mac, or turn it off and on again.")
                : ""
        case "boostStatus": gpuBoostText = ZH.text(d["text"] as? String ?? "")
        case "configPicked":
            configPickerBusy = false
            chosenConfigPath = d["path"] as? String ?? ""
            if !chosenConfigPath.isEmpty { efi = "config:" + chosenConfigPath }
        case "tester":
            if d["ok"] as? Bool == true {
                testerOn = d["on"] as? Bool == true
                texts["testr"] = testerOn
                    ? L10n.ui("已加入，每次重启后发送报告。", "Joined. A report will be sent after each restart.")
                    : L10n.ui("已退出，不再运行。", "Left the test program. It will no longer run.")
            } else { texts["testr"] = reason }
        case "usb":
            controllers = d["controllers"] as? [[String: Any]] ?? []; seen = d["seen"] as? [String: [String]] ?? [:]
            for c in controllers { let key = c["key"] as? String ?? c["controller"] as? String ?? ""; for p in c["ports"] as? [[String: Any]] ?? [] { let name = p["name"] as? String ?? ""; if seen[key, default: []].contains(name), picks[key]?[name] == nil, !excluded.contains(key+"/"+name) { picks[key, default: [:]][name] = connector(p) } } }
        case "usbErr": texts["uerr"] = ZH.text(data as? String ?? "")
        case "logsStatus": collecting = true; texts["slr"] = ZH.text(d["text"] as? String ?? "")
        case "diagnosticsStatus": texts["odr"] = ZH.text(d["text"] as? String ?? "")
        case "diagnosticReceipt": texts["drr"] = ZH.text(d["text"] as? String ?? "")
        case "gpumapStatus": texts["gpumapr"] = ZH.text(d["text"] as? String ?? ""); if d["done"] as? Bool == true { mappingGPU = false }
        case "arm": arm(event: d)
        case "logsDone":
            collecting = false
            let errors = (d["errors"] as? [String] ?? []).map(ZH.text).joined(separator: L10n.ui("；", "; "))
            let identifiers = (d["ids"] as? [String] ?? []).joined(separator: L10n.ui("、", ", "))
            if d["ok"] as? Bool == true {
                let summary = L10n.ui("已发送。报告编号 \(identifiers)，求助时请附上此编号。",
                                      "Sent. Report ID: \(identifiers). Include this ID when asking for help.")
                texts["slr"] = summary + (errors.isEmpty ? "" : L10n.ui("\n未发送：\(errors)", "\nNot sent: \(errors)"))
            } else if reason.isEmpty {
                texts["slr"] = errors.isEmpty ? "" : L10n.ui("未发送：\(errors)", "Not sent: \(errors)")
            } else {
                texts["slr"] = reason
            }
            if d["localPath"] != nil {
                texts["slr", default: ""] += L10n.ui("\n报告文件也已保存在本机，可打开日志文件夹查看，或再次发送日志重试。", "\nA copy of the report is saved on this Mac. Open the log folder to view it, or send the log again.")
            }
        case "crashDone":
            if d["ok"] as? Bool == true {
                let filename = (d["path"] as? String ?? "").components(separatedBy: "/").last ?? ""
                texts["cr"] = L10n.ui("已保存到桌面：\(filename)", "Saved to Desktop: \(filename)")
            } else { texts["cr"] = reason }
        default: break
        }
    }
    /// armTurnOn prefixes its own messages when 1401 for Windows asked for the feature, so the prefix is
    /// translated once and the rest looked up on its own.
    func armText(_ value: String) -> String {
        let lead = "1401 for Windows asked for ARM apps. "
        if value.hasPrefix(lead) {
            return L10n.ui("1401 for Windows 请求了 ARM 应用。", "1401 for Windows requested ARM apps. ") + ZH.text(String(value.dropFirst(lead.count)))
        }
        let setup = "ARM apps (asked for in 1401 for Windows): not set up - "
        if value.hasPrefix(setup) {
            return L10n.ui("ARM 应用（由 1401 for Windows 请求）：未设置 - ", "ARM apps (requested by 1401 for Windows): not set up - ") + ZH.text(String(value.dropFirst(setup.count)))
        }
        return ZH.text(value)
    }
    /// The ARM apps card, carried over from app.js's armEvent: one status line, one transient outcome,
    /// the translation progress and the list of translated apps.
    private func arm(event d: [String: Any]) {
        switch d["kind"] as? String ?? "" {
        case "status":
            armOn = d["installed"] as? Bool == true
            armRunning = d["translating"] as? Bool == true
            armCheck = d["check"] as? [String: Any] ?? [:]
            armOk = armOn && armCheck["ok"] as? Bool == true
            armApps = d["apps"] as? [[String: String]] ?? []
            armBrew = d["brew"] as? [String: Any] ?? [:]
            armBrewText = armBrewLine()
            armNote = armText(d["note"] as? String ?? "")
            armListWhy = armText(d["listWhy"] as? String ?? "")
            armStarting = false
            if !armRunning { armPct = nil; armMsg = "" }
            armStatusText = armStatusLine()
            armLast = ""  // the line above already carried it once
        case "request":
            var request = d
            let prefix = "1401 for Windows set up ARM apps for this Mac, but "
            if let text = d["text"] as? String {
                if text.hasPrefix(prefix) {
                    var why = String(text.dropFirst(prefix.count))
                    if why.hasSuffix(".") { why.removeLast() }
                    request["text"] = L10n.ui("1401 for Windows 已为本机设置 ARM 应用，但", "1401 for Windows set up ARM apps for this Mac, but ") + armText(why) + L10n.ui("。", ".")
                } else {
                    request["text"] = armText(text)
                }
            }
            armRequest = request
        case "busy":
            armLast = ""
            armStatusText = armText(d["text"] as? String ?? "")
        case "error":
            armStarting = false
            armLast = armText(d["why"] as? String ?? "")
            armStatusText = armLast
        case "progress":
            armRunning = true
            armCancelling = false
            armPct = (d["pct"] as? NSNumber)?.doubleValue
            let app = d["app"] as? String ?? ""
            let step = armText(d["msg"] as? String ?? "")
            let stage = armText(d["stage"] as? String ?? "")
            let detail = step.isEmpty ? stage : step
            armMsg = detail.isEmpty ? app : app.isEmpty ? detail : L10n.ui("\(app)：\(detail)", "\(app): \(detail)")
        case "done":
            armRunning = false
            armPct = nil
            armMsg = ""
            let app = d["app"] as? String ?? ""
            if d["what"] as? String == "brew" {
                // armBrewText in app.js: Homebrew reports its own sentence, not a translated app's.
                armLast =
                    d["ok"] as? Bool == true
                    ? armText(d["msg"] as? String ?? L10n.ui("Homebrew 已设置。请打开一个新的终端窗口。", "Homebrew is set up. Open a new Terminal window."))
                    : L10n.ui("Homebrew：", "Homebrew: ") + armText(d["why"] as? String ?? L10n.ui("设置未能完成", "Setup did not finish"))
            } else {
                armLast =
                    d["ok"] as? Bool == true
                    ? L10n.ui("\(app) 已翻译完成：副本位于“应用程序 › NullMoth ARM”。", "\(app) is ready. The translated copy is in Applications › NullMoth ARM.")
                    : L10n.ui("\(app)：", "\(app): ") + armText(d["why"] as? String ?? L10n.ui("翻译未能完成", "Translation did not finish"))
            }
            armStatusText = armLast
        default:
            break
        }
    }
    private var armNote = ""
    private var armListWhy = ""
    func armStatusLine() -> String {
        var lines: [String] = []
        if !armLast.isEmpty { lines.append(armLast) }
        if !armNote.isEmpty { lines.append(armNote) }
        if !armOn {
            lines.append(L10n.ui("已关闭，未安装任何内容。", "Off. Nothing is installed."))
        } else if armCheck["ok"] as? Bool == true {
            let target = armCheck["target"] as? String ?? ""
            lines.append(L10n.ui("本机可以运行翻译后的应用\(target.isEmpty ? "" : "（" + target + "）")。", "This Mac can run translated apps\(target.isEmpty ? "" : " (" + target + ")")."))
        } else {
            lines.append(armText(armCheck["why"] as? String ?? L10n.ui("本机未通过检查。", "This Mac did not pass the requirements check.")))
        }
        if armOn, let note = armCheck["note"] as? String, !note.isEmpty { lines.append(armText(note)) }
        if !armListWhy.isEmpty { lines.append(armListWhy) }
        return lines.joined(separator: "\n")
    }
    /// armBrewText in app.js: the two Homebrews side by side, their program counts and the Ruby note.
    func armBrewLine() -> String {
        guard !armBrew.isEmpty else { return "" }
        if let why = armBrew["why"] as? String, !why.isEmpty { return ZH.text(why) }
        func side(_ key: String, _ name: String, _ command: String) -> String {
            let state = armBrew[key] as? [String: Any]
            return state?["installed"] as? Bool == true
                ? L10n.ui("\(name) 已就绪（\(command)）", "\(name) is ready (\(command))")
                : L10n.ui("\(name) 未设置", "\(name) is not set up")
        }
        let arm = armBrew["arm"] as? [String: Any]
        var line = side("arm", "ARM Homebrew", "abrew") + " · " + side("intel", "Intel Homebrew", "ibrew")
        if let programs = arm?["programs"] as? [String: Any] {
            let translated = (programs["translated"] as? NSNumber)?.intValue ?? 0
            let waiting = (programs["stub"] as? NSNumber)?.intValue ?? 0
            line += L10n.ui("\n已翻译的程序：\(translated)；等待首次运行：\(waiting)。", "\nTranslated apps: \(translated). Waiting for first launch: \(waiting).")
        }
        if arm?["installed"] as? Bool == true, let ruby = arm?["ruby"] as? [String: Any],
            ruby["launcher"] as? Bool != true
        {
            line += L10n.ui("\nARM Homebrew 的 Ruby 尚未准备好：在终端里运行一次 abrew。", "\nARM Homebrew's Ruby is not ready. Run abrew once in Terminal.")
        }
        return line
    }
    func picker(_ id: String) -> Binding<String> {
        switch id {
        case "armbrewpick": return Binding(get: { self.armBrewPick }, set: { self.armBrewPick = $0 })
        case "armbrewprim": return Binding(get: { self.armBrewPrimary }, set: { self.armBrewPrimary = $0 })
        default: return .constant("")
        }
    }
    func armTask(_ op: String, _ fields: [String: Any] = [:]) {
        var command = fields
        command["op"] = op
        armStarting = op == "on"
        perform("arm", command)
    }
    func setExperimental(_ id: String, enabled: Bool) {
        if enabled { experimentalOn.insert(id) }
        else { experimentalOn.remove(id) }
    }
    func experimentalBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { self.experimentalOn.contains(id) }, set: { self.setExperimental(id, enabled: $0) })
    }
    func connector(_ p: [String: Any]) -> Int { let v = p["connector"] as? Int ?? -1; return p["connectorKnown"] as? Bool == true && [0,3,9,10,255].contains(v) ? v : p["usb3"] as? Bool == true ? 3 : 0 }
    private func localizedSetupNote(_ line: String) -> String {
        let bootPrefix = "NOTE boot-path:"
        if line.hasPrefix(bootPrefix) {
            let path = String(line.dropFirst(bootPrefix.count)).trimmingCharacters(in: .whitespaces)
            return L10n.ui("提示：OpenCore 启动路径：\(path)", "OpenCore boot path: \(path)")
        }
        let partitionPrefix = "NOTE partition "
        if line.hasPrefix(partitionPrefix), let colon = line.firstIndex(of: ":") {
            let start = line.index(line.startIndex, offsetBy: partitionPrefix.count)
            let disk = String(line[start..<colon])
            let details = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            return L10n.ui("提示：分区 \(disk) 信息：\(details)", "Partition \(disk): \(details)")
        }
        return ZH.text(line)
    }
    func text(_ id: String) -> String {
        if id == "s1t" {
            if let package = goodPackage {
                let location = package["where"] as? String ?? ""
                return L10n.ui("在 \(location) 找到驱动，校验通过。", "Driver found at \(location). Verification passed.")
            }
            return (machine["packages"] as? [[String: Any]] ?? []).isEmpty
                ? L10n.ui("本机尚无驱动包。", "No driver package is available on this Mac.")
                : L10n.ui("找到的副本校验不符，请重新下载。", "The driver package found on this Mac failed verification. Download it again.")
        }
        if id == "updr" { return [texts[id] ?? "",appStatus].filter { !$0.isEmpty }.joined(separator:"\n") }
        if id == "updt" { return texts[id] ?? (major == 26 ? L10n.ui("本机已运行 macOS 26。", "This Mac is running macOS 26.") : "") }
        if id == "armr" { return armStatusText }
        if id == "armbrewr" { return armBrewText }
        if id == "gmr" { return gameModeText }
        if id == "bostr" { return gpuBoostText }
        if id == "ryzstat" { return ryzenPowerText }
        return texts[id] ?? ""
    }
    private func tccStatusText(_ value: String) -> String {
        guard !value.isEmpty else { return "" }
        let marker = " may now use the microphone and camera"
        if let range = value.range(of: marker) {
            let name = String(value[..<range.lowerBound])
            let after = value[range.upperBound...]
            var failed = Set<String>()
            if let start = after.range(of: "(not: "), let end = after[start.upperBound...].range(of: ").") {
                failed = Set(String(after[start.upperBound..<end.lowerBound]).components(separatedBy: ", "))
            }
            let services = [
                ("Microphone", L10n.ui("麦克风", "microphone")),
                ("Camera", L10n.ui("摄像头", "camera")),
                ("ScreenCapture", L10n.ui("屏幕录制", "screen recording")),
            ]
            let granted = services.filter { !failed.contains($0.0) }
            let refused = services.filter { failed.contains($0.0) }
            if refused.isEmpty {
                return L10n.ui(
                    "\(name) 已获得麦克风、摄像头和屏幕录制权限。若该 App 正在运行，请退出后重新打开。",
                    "\(name) can now use the microphone, camera, and screen recording. If the app is running, quit and reopen it."
                )
            }
            let separator = L10n.ui("、", ", ")
            let grantedNames = granted.map { $0.1 }.joined(separator: separator)
            let refusedNames = refused.map { $0.1 }.joined(separator: separator)
            return L10n.ui(
                "\(name) 已获得\(grantedNames)权限；以下权限未能授予：\(refusedNames)。若该 App 正在运行，请退出后重新打开。",
                "\(name) can use \(grantedNames). Permission could not be granted for \(refusedNames). If the app is running, quit and reopen it."
            )
        }
        let prefix = "Could not allow "
        if value.hasPrefix(prefix), let separator = value.range(of: ": ", range: value.index(value.startIndex, offsetBy: prefix.count)..<value.endIndex) {
            let name = String(value[value.index(value.startIndex, offsetBy: prefix.count)..<separator.lowerBound])
            let reason = String(value[separator.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let localizedReason = ZH.text(reason)
            return L10n.ui("无法为 \(name) 授予权限：\(localizedReason)", "Unable to grant permission to \(name): \(localizedReason)")
        }
        return ZH.text(value)
    }
    func visible(_ id: String) -> Bool {
        switch id {
        case "steps": return showSteps
        case "logwrap": return showLog || !output.isEmpty
        case "efirow": return !candidates.isEmpty
        case "dl": return goodPackage == nil
        case "upddrv": return driverUpdate
        case "updapp": return appUpdate
        case "earlyon": return !early
        case "earlyoff": return early
        case "swu": return tahoeReady
        case "xecard": return xeCardVisible
        // armButtons() and armEvent() in app.js decide the ARM card's controls the same way.
        case "armreq": return armRequest != nil
        case "armon": return !armOn
        case "armoff", "armchk", "armtr", "armapps": return armOn
        case "armclt": return armOn && !armCommandLineTools
        case "armbrew": return armOn
        case "armprog": return armRunning
        case "gmon": return !gameModeInstalled
        case "gmoff": return gameModeInstalled
        case "autologinoff": return automaticLoginByApp
        default: return true
        }
    }
    var armCommandLineTools: Bool {
        guard let prerequisites = armCheck["prerequisites"] as? [String: Any] else { return true }
        return prerequisites["clt"] as? Bool != false
    }
    func disabled(_ id: String) -> Bool {
        if busy && ["dry","go","rm","dl","updchk","upddrv","upd","updc","hdon","hdoff","xeon","xeoff","tccg"].contains(id) { return true }
        if downloading && ["dl","updchk","upddrv"].contains(id) { return true }
        switch id { case "dry":return package.isEmpty;case "go":return !canInstall;case "rs":return !installed;case "upd":return goodPackage == nil || major != 15 || eligibility != nil || machine["nativeMacPro"] as? Bool == true;case "updapp":return appUpdating;case "tccg":return tccGranting;case "uw":return watching;case "efichk":return checkingEFI;case "efimount":return mountingEFI;case "gpumap":return mappingGPU;case "sl","fl":return collecting;case "armon":return armStarting;case "armtr":return !(armOn && armOk) || armRunning;case "armcancel":return armCancelling;case "armoff","armchk","armclt":return armRunning;case "armbrewgo":return !armOn || armRunning;case "armbrewpick","armbrewprim":return armRunning;case "gmon","gmoff":return gameModeBusy;case "hybcopy","hybimport","hyboff","expapply","boston","bostoff","bostrm","ryzon","ryzstat","ryzoff","autologinoff":return busy || downloading;case "cfgpick":return configPickerBusy;default:return false }
    }
    func buttonTitle(_ id: String, _ fallback: String) -> String {
        if id == "go" {
            return package.isEmpty
                ? L10n.ui("安装驱动（请先获取驱动）", "Install Driver (get the driver package first)")
                : !previewed ? L10n.ui("安装驱动（请先查看更改）", "Install Driver (review changes first)") : fallback
        }
        if id == "uw" && watching { return L10n.ui("正在监测…", "Monitoring…") }
        return fallback
    }
    func press(_ id: String) {
        taskSource = id
        defer { taskSource = nil }
        switch id {
        case "dl","dl3":perform("download")
        case "dry":perform("run",["mode":"dry"])
        case "go":perform("run",["mode":"install"])
        case "rs":perform("restart")
        case "priv":perform("privacy")
        case "logs":perform("logs")
        case "updchk":perform("checkUpdate")
        case "upddrv":driverUpdating=true;perform("updateDriver")
        case "updapp":appUpdating=true;perform("updateApp")
        case "earlyon","earlyoff":perform("early",["on":id=="earlyon"])
        case "upd","updc":perform("osupdate",["cancel":id=="updc"])
        case "swu":perform("swupdate")
        case "rm":
            let alert = NSAlert()
            alert.messageText = L10n.ui("移除 NullMoth 驱动，并将 OpenCore 配置恢复到安装前的状态？", "Remove the NullMoth driver and restore the OpenCore configuration to its pre-install state?")
            alert.addButton(withTitle: L10n.ui("好", "Remove Driver"))
            alert.addButton(withTitle: L10n.ui("取消", "Cancel"))
            if alert.runModal() == .alertFirstButtonReturn { perform("run", ["mode": "remove", "pkg": ""]) }
        case "efichk":
            checkingEFI = true
            texts["efichkr"] = L10n.ui("正在读取 EFI…", "Reading EFI…")
            issues = []
            perform("checkEfi", ["efi": "auto"])
        case "efimount": mountingEFI = true; texts["efimountr"] = L10n.ui("正在查找 EFI…", "Finding EFI…"); perform("mountEfi")
        case "vbon","vboff":perform("verbose",["on":id=="vbon"])
        case "blon","bloff":perform("backlight",["on":id=="blon"])
        case "hdon","hdoff":perform("hidpi",["on":id=="hdon"])
        case "gpuon","gpuoff":perform("gputest",["on":id=="gpuon"])
        case "xeon","xeoff":perform("xe",["on":id=="xeon"])
        case "cfgpick", "pickconfig":
            configPickerBusy = true
            perform("pickconfig") // NSOpenPanel is modal; this returns after select or cancel.
            configPickerBusy = false
        case "autologinoff": perform("autologinoff")
        case "hybcopy": perform("hybrid", ["level": "copy"])
        case "hybimport": perform("hybrid", ["level": "import"])
        case "hyboff": perform("hybrid", ["level": "off"])
        case "hybrid": perform("hybrid", ["level": hybridLevel])
        case "expapply": perform("experimental", ["items": Array(experimentalOn).sorted()])
        case "experimental": perform("experimental", ["items": Array(experimentalOn).sorted()])
        case "boston": perform("gpuboost", ["op": "on"])
        case "bostoff": perform("gpuboost", ["op": "off"])
        case "bostrm": perform("gpuboost", ["op": "remove"])
        case "bostat": perform("gpuboost", ["op": "status"])
        case "gpuboost": perform("gpuboost", ["op": "status"])
        case "ryzon": perform("ryzenpower", ["on": true,
                                               "stapm": ryzenSTAPM, "slow": ryzenSlow,
                                               "fast": ryzenFast, "temp": ryzenTemp])
        case "ryzoff": perform("ryzenpower", ["on": false])
        case "ryzstat": perform("ryzenpower", ["status": true])
        case "ryzenpower": perform("ryzenpower", ["status": true])
        case "gmon": gameModeBusy = true; gameModeText = L10n.ui("正在等待 macOS 授权…", "Waiting for macOS authorization…"); perform("gm", ["op": "on"])
        case "gmoff": gameModeBusy = true; gameModeText = L10n.ui("正在等待 macOS 授权…", "Waiting for macOS authorization…"); perform("gm", ["op": "off"])
        case "gmstat", "gm": perform("gm", ["op": "status"])
        case "settings": perform("settings")
        case "tccg":tccGranting=true;texts["tccr"] = L10n.ui("正在选择要授权的 App…", "Choose an app to authorize…");perform("tccGrant")
        case "nvon":perform("osupdate",["cancel":true])
        case "teston","testoff":perform("tester",["on":id=="teston"])
        case "gpumap":mappingGPU=true;texts["gpumapr"] = L10n.ui("正在开始…", "Starting…");perform("gpumap")
        case "armon":armRequest=nil;armTask("on")
        case "armreqon":armRequest=nil;armTask("on",["from":"windows"])
        case "armreqno":armRequest=nil;armTask("notNow")
        case "armoff":armTask("off")
        case "armchk":armTask("check")
        case "armclt":armTask("clt")
        case "armtr":armTask("translate")
        case "armbrewgo":armTask("brew",["pick":armBrewPick,"primary":armBrewPrimary])
        case "armcancel":armCancelling=true;armMsg = L10n.ui("正在取消…", "Cancelling…");armTask("cancel")
        case "uw":picks=[:];excluded=[];watching=true;perform("usbStart")
        case "uwr":texts["uerr"]="";perform("usbStop");perform("usbWrite",["sel":picks])
        case "sl", "fl":
            collecting = true
            texts["slr"] = id == "fl"
                ? L10n.ui("正在记录 20 秒显示状态，随后发送…", "Recording display activity for 20 seconds before sending…")
                : L10n.ui("正在收集并发送…", "Collecting and sending…")
            perform("sendLogs", ["sample": id == "fl" ? "flicker" : ""])
        case "mk":perform("crashReport")
        case "od":perform("optionalDiagnostics")
        case "dr":perform("importDiagnosticReceipt")
        case "up":perform("open",["url":"https://nullmothsystems.com/#send"])
        case "cf":perform("open",["url":"https://buymeacoffee.com/nullmoth"])
        case "cr":perform("open",["url":"https://github.com/nullmoth/1401/blob/main/NOTICE.md"])
        case "src":perform("open",["url":"https://github.com/nullmoth/nvidia-macos-driver"])
        case "ocg":perform("open",["url":"https://dortania.github.io/OpenCore-Install-Guide/"])
        default:break
        }
    }
}
