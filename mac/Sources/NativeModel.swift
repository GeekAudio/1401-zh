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
    var xeCardVisible: Bool {
        machine["arch"] as? String == "x86_64" && machine["translated"] as? Bool != true
            && gpus.contains { $0["xe"] as? Bool == true }
            && ((major == 15 && minor >= 8) || (major == 26 && minor >= 7))
    }
    var parkedDriver: Bool { machine["safemode"] as? Bool == true && machine["record"] as? Bool == true }
    var goodPackage: [String: Any]? { (machine["packages"] as? [[String: Any]] ?? []).first { $0["ok"] as? String == "yes" } }
    var eligibility: String? {
        guard !machine.isEmpty else { return nil }
        if machine["arch"] as? String != "x86_64" || machine["translated"] as? Bool == true { return "本机使用 Apple 芯片，其图形驱动已由 Apple 提供。" }
        if ![15,26].contains(major) { return "此驱动适用于 macOS 15 Sequoia 和 macOS 26 Tahoe（测试版）；本机运行 macOS \(machine["macos"] as? String ?? "")。" }
        let hiding = (machine["gpuHiding"] as? [String] ?? []).filter { $0 != "-wegnoigpu" }
        if card == nil && !hiding.isEmpty { return "启动参数 \(hiding.joined(separator: " ")) 隐藏了独立显卡，因此看不到 NVIDIA 显卡。请在 OpenCore 的 config.plist 中移除对应 boot-args，重启后重新打开 1401。" }
        let hidden = machine["hiddenNvidia"] as? [String] ?? []
        if card == nil && !hidden.isEmpty { return "NVIDIA 显卡（\(hidden.joined(separator: "、"))）位于总线上，但已对 macOS 停用，通常由 OpenCore DeviceProperties 中的 disable-gpu 属性导致。请移除该属性并重启，再打开 1401。" }
        if card == nil && (machine["hwModel"] as? String ?? "").hasPrefix("MacBook") { return "未找到 NVIDIA 显卡。笔记本可能在 macOS 启动前由 BIOS 显卡模式或关闭独显的 SSDT 将其停用。请在 BIOS 中选择 Hybrid/MSHybrid 或 Discrete，并检查 OpenCore ACPI 中关闭独显的 SSDT，修正后重启并重新打开 1401。" }
        if card?["supported"] as? Bool != true { return "未找到受支持的 NVIDIA 显卡。此驱动需要 GeForce RTX 20 系列或更新显卡。" }
        if (machine["opencore"] as? String ?? "").isEmpty { return "本机未报告 OpenCore。驱动所需设置保存在 OpenCore 配置中，因此没有 OpenCore 时 1401 不会安装。" }
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
            text = "NullMoth 组件已加载，并且 NVIDIA Metal 设备可见。\n使用“检查更新”更新驱动，或使用下方的“移除驱动”卸载。" + (major == 15 ? "如需升级 macOS 26 Tahoe，请使用下方的“准备升级到 Tahoe”。" : "")
        } else if hiddenOwnGPU {
            text = "macOS 未看到任何 GPU。\nOpenCore 很可能通过 disable-gpu 属性" + ((machine["gpuHiding"] as? [String] ?? []).contains("-wegnoigpu") ? "及 -wegnoigpu 启动参数" : "") + "将其停用。对于处理器内置的 Intel 或 AMD GPU，下方“AMD / Intel GPU 与 NPU 驱动（测试）”可重新启用并加载测试驱动，关闭按钮可再次停用。启用时会下载并校验该驱动的独立安装包。"
        } else if eligibility != nil && otherGPU {
            text = "未找到 NVIDIA 显卡，因此 NVIDIA 驱动不适用。\n本机的 \(gpus.filter { $0["vendor"] as? String != "10DE" }.map { $0["name"] as? String ?? "" }.joined(separator: "、")) 可尝试下方的 AMD / Intel GPU 实验性驱动。启用时会下载并校验其独立安装包。"
        } else if let why = eligibility {
            text = "无法在此电脑安装。\n" + why
        } else if machine["files"] as? Bool == true && !installed && (machine["kexts"] as? Int ?? 0) >= 4 {
            text = "驱动已加载，但 macOS 暂未显示 NVIDIA Metal 设备。\n如果笔记本内屏连接到 Intel 或 AMD 显卡且没有 MUX 切换，NVIDIA 显卡只负责连接到自身 HDMI 或 DisplayPort 的显示器，请连接后重启。其他情况请先重启一次；若仍如此，请发送日志。"
        } else if machine["files"] as? Bool == true && !installed {
            text = "驱动已安装，但尚未运行。\n请重新启动。如果 macOS 阻止了系统扩展，请在“隐私与安全性”中允许，然后再次重启。"
        } else {
            text = "\(card?["name"] as? String ?? "") 有可用的驱动配置。这台电脑仍需进行启动、显示和应用检查。请依次完成以下四步。"
        }
        if parkedDriver {
            text = "本次启动的 boot-args 中包含 -nvoff，因此 NVIDIA 驱动暂未启动。可以点击“启用驱动”恢复，并在重启后加载；如果开启驱动曾导致黑屏，请先发送日志再启用。若要彻底移除驱动，请使用下方的“移除驱动”。\n" + text
        }
        if machine["itlwmNeedsHeliPort"] as? Bool == true {
            text += "\n\nWi-Fi 提示：本机使用 itlwm 驱动 Intel 无线网卡，需要通过 HeliPort 连接网络；它不会出现在 macOS 的 Wi-Fi 菜单中。请从 [HeliPort 发布页](https://github.com/OpenIntelWireless/HeliPort/releases) 下载并将 App 移到“应用程序”，然后在 HeliPort 中选择网络。若需开机自动启动，请在 HeliPort 菜单中开启“登录时启动”。"
        }
        return text
    }
    func perform(_ act: String, _ fields: [String: Any] = [:]) {
        var command = fields; command["act"] = act
        if command["efi"] == nil { command["efi"] = efi }
        if command["pkg"] == nil { command["pkg"] = package }
        if act == "checkUpdate" { texts["updr"] = "正在检查…"; appStatus = "" }
        action(command)
    }
    func receive(_ event: String, _ data: Any) {
        tasks.receive(event, data)
        let d = data as? [String: Any] ?? [:], state = d["state"] as? String ?? ""
        let reason = ZH.text(d["why"] as? String ?? "")
        switch event {
        case "scan":
            machine = d
            let checked = goodPackage?["path"] as? String ?? ""
            if !checked.isEmpty { package = checked }
            let crashes = d["crashes"] as? [String] ?? []
            texts["cr"] = crashes.isEmpty ? "本机没有包含该驱动的崩溃记录。" : "本机有 \(crashes.count) 份崩溃文件包含该驱动。"
        case "lines":
            for line in data as? [String] ?? [] {
                output += line + "\n"
                if line.hasPrefix("NOTE candidate "), let disk = line.split(separator: " ").dropFirst(2).first.map(String.init), !candidates.contains(disk) { candidates.append(disk); if efi == "auto" { efi = disk } }
            }
        case "run":
            busy = state == "start"
            if busy { output = ""; showLog = true; return }
            if !reason.isEmpty { showLog = true; output += reason + "\n" }
            if state == "cancelled" { if driverUpdating { driverUpdating = false; texts["updr"] = "驱动更新已取消。" }; output += "NOTE 已取消，未进行任何更改\n"; perform("scan"); return }
            let ok = d["ok"] as? Bool == true, mode = d["mode"] as? String ?? ""
            if mode == "dry" && ok { previewed = true }
            if mode == "install" && ok { installed = true }
            if driverUpdating && mode == "install" { driverUpdating = false; texts["updr"] = ok ? "驱动已安装，请重启以加载。" : "驱动更新已停止，请查看下方安装记录。"; if ok { driverUpdate = false } }
            if mode == "tahoe" { tahoeReady = ok; texts["updt"] = ok ? "已为 Tahoe 准备就绪，请打开“软件更新”安装 macOS 26。" : "Tahoe 升级准备已停止，请查看上方安装记录。" }
            if mode == "tahoecancel" { tahoeReady = false; texts["updt"] = ok ? "已取消 Tahoe 升级准备，驱动和安装器设置已恢复。" : "取消操作已停止，请查看上方安装记录。" }
            perform("scan")
        case "dl":
            if state == "start" { downloading = true }
            if state == "progress" {
                let done = (d["done"] as? NSNumber)?.doubleValue ?? 0, total = (d["total"] as? NSNumber)?.doubleValue ?? 0
                texts["dlp"] = total > 0 ? String(format: "%.0f%%（%.1f / %.1f MB）", done/total*100, done/1048576, total/1048576) : String(format: "%.1f MB", done/1048576)
                if driverUpdating { texts["updr"] = "正在下载最新驱动：" + (texts["dlp"] ?? "") }
            }
            if ["done","error"].contains(state) { downloading = false; texts["dlp"] = state == "done" ? "完成，校验通过" : reason; if state == "done" { if driverUpdating { texts["updr"] = "下载已校验，正在安装驱动…" }; perform("scan") } else if driverUpdating { driverUpdating = false; texts["updr"] = reason } }
        case "upd":
            if state == "error" { texts["updr"] = reason; driverUpdate = false }
            else { driverUpdate = d["newer"] as? Bool == true; let have = d["installed"] as? String ?? "", latest = d["latest"] as? String ?? "", kind = d["prerelease"] as? Bool == true ? "提前发布版本" : "版本"; texts["updr"] = have.isEmpty ? "1401 无法确定已安装的驱动版本，最新\(kind)为 \(latest)，可直接更新。" : driverUpdate ? "已安装 \(have)，最新\(kind) \(latest)，可以更新。" : "已安装 \(have)，当前已是最新驱动（\(latest)）。" }
        case "appCheck":
            appUpdate = state == "checked" && d["newer"] as? Bool == true
            appStatus = state == "error" ? reason : appUpdate ? "App \(d["have"] as? String ?? "") → \(d["latest"] as? String ?? "") 已可更新。" : "App（\(d["have"] as? String ?? "")）已是最新版本。"
        case "appupd": appUpdating = state != "error"; appStatus = state == "error" ? reason : state == "restarting" ? "1401 \(d["version"] as? String ?? "") 已校验，正在重新打开…" : "正在下载 1401 \(d["version"] as? String ?? "")…"
        case "tccStatus":
            tccGranting = false
            texts["tccr"] = tccStatusText(d["text"] as? String ?? "")
        case "efiCheck":
            checkingEFI = false
            if d["cancelled"] as? Bool == true { texts["efichkr"] = ""; return }
            issues = d["issues"] as? [[String: Any]] ?? []
            texts["efichkr"] = d["ok"] as? Bool == true ? issues.isEmpty ? "在 \(d["partition"] as? String ?? "") 中未发现问题。" : "\(d["partition"] as? String ?? "") 有 \(issues.count) 项设置需要更改。" : reason
        case "efiMount": mountingEFI = false; texts["efimountr"] = d["cancelled"] as? Bool == true ? "" : d["ok"] as? Bool == true ? "已挂载 \(d["partition"] as? String ?? "")：\(d["where"] as? String ?? "")" : reason
        case "early": early = d["on"] as? Bool == true; texts["earlyr"] = early ? "已开启：新驱动会在向所有人提供前先推送到本机。" : "已关闭：本机将在提前使用者验证版本稳定后获取更新。"
        case "tester": if d["ok"] as? Bool == true { testerOn = d["on"] as? Bool == true; texts["testr"] = testerOn ? "已加入，每次重启后发送报告。" : "已退出，不再运行。" } else { texts["testr"] = reason }
        case "usb":
            controllers = d["controllers"] as? [[String: Any]] ?? []; seen = d["seen"] as? [String: [String]] ?? [:]
            for c in controllers { let key = c["key"] as? String ?? c["controller"] as? String ?? ""; for p in c["ports"] as? [[String: Any]] ?? [] { let name = p["name"] as? String ?? ""; if seen[key, default: []].contains(name), picks[key]?[name] == nil, !excluded.contains(key+"/"+name) { picks[key, default: [:]][name] = connector(p) } } }
        case "usbErr": texts["uerr"] = ZH.text(data as? String ?? "")
        case "logsStatus": collecting = true; texts["slr"] = ZH.text(d["text"] as? String ?? "")
        case "diagnosticsStatus": texts["odr"] = ZH.text(d["text"] as? String ?? "")
        case "diagnosticReceipt": texts["drr"] = ZH.text(d["text"] as? String ?? "")
        case "gpumapStatus": texts["gpumapr"] = ZH.text(d["text"] as? String ?? ""); if d["done"] as? Bool == true { mappingGPU = false }
        case "logsDone":
            collecting = false
            let errors = (d["errors"] as? [String] ?? []).map(ZH.text).joined(separator: "；")
            texts["slr"] = d["ok"] as? Bool == true ? "已发送。报告编号 \((d["ids"] as? [String] ?? []).joined(separator: "、"))，求助时请附上此编号。" + (errors.isEmpty ? "" : "\n未发送："+errors) : reason.isEmpty ? "未发送："+errors : reason
            if d["localPath"] != nil { texts["slr",default:""] += "\n报告文件也已保存在本机，可打开日志文件夹查看，或再次发送日志重试。" }
        case "crashDone": texts["cr"] = d["ok"] as? Bool == true ? "已保存到桌面：\((d["path"] as? String ?? "").components(separatedBy:"/").last ?? "")" : reason
        default: break
        }
    }
    func connector(_ p: [String: Any]) -> Int { let v = p["connector"] as? Int ?? -1; return p["connectorKnown"] as? Bool == true && [0,3,9,10,255].contains(v) ? v : p["usb3"] as? Bool == true ? 3 : 0 }
    func text(_ id: String) -> String {
        if id == "s1t" { return goodPackage.map { "在 \($0["where"] as? String ?? "") 找到驱动，校验通过。" } ?? ((machine["packages"] as? [[String:Any]] ?? []).isEmpty ? "本机尚无驱动包。" : "找到的副本校验不符，请重新下载。") }
        if id == "updr" { return [texts[id] ?? "",appStatus].filter { !$0.isEmpty }.joined(separator:"\n") }
        if id == "updt" { return texts[id] ?? (major == 26 ? "本机已运行 macOS 26。" : "") }
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
            let services = [("Microphone", "麦克风"), ("Camera", "摄像头"), ("ScreenCapture", "屏幕录制")]
            let granted = services.filter { !failed.contains($0.0) }.map { $0.1 }
            let refused = services.filter { failed.contains($0.0) }.map { $0.1 }
            if refused.isEmpty {
                return "\(name) 已获得麦克风、摄像头和屏幕录制权限。若该 App 正在运行，请退出后重新打开。"
            }
            return "\(name) 已获得\(granted.joined(separator: "、"))权限；以下权限未能授予：\(refused.joined(separator: "、"))。若该 App 正在运行，请退出后重新打开。"
        }
        let prefix = "Could not allow "
        if value.hasPrefix(prefix), let separator = value.range(of: ": ", range: value.index(value.startIndex, offsetBy: prefix.count)..<value.endIndex) {
            let name = String(value[value.index(value.startIndex, offsetBy: prefix.count)..<separator.lowerBound])
            let reason = String(value[separator.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return "无法为 \(name) 授予权限：\(ZH.text(reason))"
        }
        return ZH.text(value)
    }
    func visible(_ id: String) -> Bool {
        switch id { case "steps": return showSteps; case "logwrap": return showLog || !output.isEmpty; case "efirow": return !candidates.isEmpty; case "dl": return goodPackage == nil; case "upddrv": return driverUpdate; case "updapp": return appUpdate; case "earlyon": return !early; case "earlyoff": return early; case "swu": return tahoeReady; case "xecard": return xeCardVisible; default:return true }
    }
    func disabled(_ id: String) -> Bool {
        if busy && ["dry","go","rm","dl","updchk","upddrv","upd","updc","xeon","xeoff","tccg"].contains(id) { return true }
        if downloading && ["dl","updchk","upddrv"].contains(id) { return true }
        switch id { case "dry":return package.isEmpty;case "go":return !canInstall;case "rs":return !installed;case "upd":return goodPackage == nil || major != 15 || eligibility != nil;case "updapp":return appUpdating;case "tccg":return tccGranting;case "uw":return watching;case "efichk":return checkingEFI;case "efimount":return mountingEFI;case "gpumap":return mappingGPU;case "sl","fl":return collecting;default:return false }
    }
    func buttonTitle(_ id: String, _ fallback: String) -> String {
        if id == "go" { return package.isEmpty ? "安装驱动（请先获取驱动）" : !previewed ? "安装驱动（请先查看更改）" : fallback }
        if id == "uw" && watching { return "正在监测…" }
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
        case "rm":let a=NSAlert();a.messageText="移除 NullMoth 驱动，并将 OpenCore 配置恢复到安装前的状态？";a.addButton(withTitle:"好");a.addButton(withTitle:"取消");if a.runModal() == .alertFirstButtonReturn { perform("run",["mode":"remove","pkg":""]) }
        case "efichk":checkingEFI=true;texts["efichkr"]="正在读取 EFI…";issues=[];perform("checkEfi",["efi":"auto"])
        case "efimount":mountingEFI=true;texts["efimountr"]="正在查找 EFI…";perform("mountEfi")
        case "vbon","vboff":perform("verbose",["on":id=="vbon"])
        case "blon","bloff":perform("backlight",["on":id=="blon"])
        case "gpuon","gpuoff":perform("gputest",["on":id=="gpuon"])
        case "xeon","xeoff":perform("xe",["on":id=="xeon"])
        case "tccg":tccGranting=true;texts["tccr"]="正在选择要授权的 App…";perform("tccGrant")
        case "nvon":perform("osupdate",["cancel":true])
        case "teston","testoff":perform("tester",["on":id=="teston"])
        case "gpumap":mappingGPU=true;texts["gpumapr"]="正在开始…";perform("gpumap")
        case "uw":picks=[:];excluded=[];watching=true;perform("usbStart")
        case "uwr":texts["uerr"]="";perform("usbStop");perform("usbWrite",["sel":picks])
        case "sl","fl":collecting=true;texts["slr"]=id=="fl" ? "正在记录 20 秒显示状态，随后发送…" : "正在收集并发送…";perform("sendLogs",["sample":id=="fl" ? "flicker" : ""])
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
