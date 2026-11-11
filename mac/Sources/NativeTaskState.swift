import Foundation

// Observes existing commands and events; never starts, retries or cancels work.
struct NativeTaskState {
    private(set) var active: [NativeTask] = []
    private var sourceAnchor: String?
    private var pendingChecks: [String: Int] = [:]

    func at(_ anchors: [String]) -> [NativeTask] {
        active.filter { anchors.contains($0.anchor) }
    }

    mutating func beginAppCheck() {
        pendingChecks["appCheck", default: 0] += 1
        let title = pendingChecks["driverCheck", default: 0] > 0 ? L10n.ui("正在检查驱动和 App 更新", "Checking for driver and app updates") : L10n.ui("正在检查 App 更新", "Checking for app updates")
        if active.contains(where: { $0.id == "updateCheck" }) { change("updateCheck") { $0.title = title } }
        else { start("updateCheck", "drv", "updchk", title) }
    }

    mutating func begin(_ command: [String: Any], setupRunning: Bool = false, downloadPending: Bool = false, source: String? = nil) {
        sourceAnchor = source
        defer { sourceAnchor = nil }
        let action = command["act"] as? String ?? ""
        switch action {
        case "scan": enqueue("scan", "drv", "machine", L10n.ui("正在读取本机信息", "Reading system information"))
        case "checkUpdate":
            pendingChecks["driverCheck", default: 0] += 1
            pendingChecks["appCheck", default: 0] += 1
            start("updateCheck", "drv", "updchk", L10n.ui("正在检查驱动和 App 更新", "Checking for driver and app updates"))
        case "download":
            if !setupRunning && !downloadPending { start("download", "drv", "dl", L10n.ui("正在下载驱动", "Downloading driver")) }
        case "updateDriver":
            if !setupRunning && !downloadPending { start("driverUpdate", "drv", "upddrv", L10n.ui("正在下载驱动更新", "Downloading driver update")) }
        case "updateApp": start("appUpdate", "drv", "updapp", L10n.ui("正在下载并校验 App", "Downloading and verifying app"))
        case "run", "verbose", "backlight", "hidpi", "gputest", "xe", "osupdate", "usbWrite",
             "hybrid", "experimental", "gpuboost", "ryzenpower", "autologinoff":
            guard !setupRunning && !downloadPending else { return }
            switch action {
            case "run":
                switch command["mode"] as? String {
                case "dry": start("setup", "drv", "dry", L10n.ui("正在读取并预览更改", "Reviewing proposed changes"))
                case "install": start("setup", "drv", "go", L10n.ui("正在安装驱动", "Installing driver"))
                case "remove": start("setup", "drv", "rm", L10n.ui("正在移除驱动", "Removing driver"))
                default: break
                }
            case "verbose": start("setup", "tools", "vbon", L10n.ui("正在设置详细模式", "Enabling verbose mode"))
            case "backlight": start("setup", "tools", "blon", L10n.ui("正在设置内屏亮度控制", "Configuring internal display brightness"))
            case "hidpi": start("setup", "tools", "hdon", L10n.ui("正在设置 HiDPI 显示模式", "Configuring HiDPI display mode"))
            case "gputest": start("setup", "experimental", "gpuon", L10n.ui("正在配置测试驱动", "Configuring test driver"))
            case "xe": start("setup", "experimental", "xeon", L10n.ui("正在设置 Intel Xe 图形", "Configuring Intel Xe graphics"))
            case "osupdate":
                if command["cancel"] as? Bool == true { start("setup", "drv", "updc", L10n.ui("正在取消 Tahoe 升级准备", "Cancelling Tahoe upgrade preparation")) }
                else if !(command["pkg"] as? String ?? "").isEmpty { start("setup", "drv", "upd", L10n.ui("正在准备 Tahoe 升级", "Preparing for the Tahoe upgrade")) }
            case "usbWrite": start("setup", "usb", "uwr", L10n.ui("正在写入 USB 映射", "Writing USB mapping"))
            case "hybrid": start("setup", "tools", source ?? "hybcopy", L10n.ui("正在设置混合显卡", "Configuring hybrid graphics"))
            case "experimental": start("setup", "experimental", "expapply", L10n.ui("正在设置实验功能", "Applying experimental features"))
            case "gpuboost":
                if command["op"] as? String != "status" {
                    start("setup", "tools", source ?? "boston", L10n.ui("正在设置 GPU 加速", "Configuring GPU acceleration"))
                }
            case "ryzenpower": start("setup", "tools", source ?? "ryzon", L10n.ui("正在设置 Ryzen 功耗配置", "Configuring Ryzen power settings"))
            case "autologinoff": start("setup", "tools", source ?? "autologinoff", L10n.ui("正在关闭自动登录设置", "Disabling automatic login"))
            default: break
            }
        case "checkEfi": start("efiCheck", "efi", "efichk", L10n.ui("正在读取并检查 EFI", "Reading and checking EFI"))
        case "gpumap": start("gpuMap", "crash", "gpumap", L10n.ui("正在测量 GPU", "Measuring GPU"))
        case "sendLogs":
            start("logs", "crash", "sl", command["sample"] as? String == "flicker" ? L10n.ui("正在记录闪屏并发送日志", "Recording display flicker and sending logs") : L10n.ui("正在收集并发送日志", "Collecting and sending logs"))
        case "optionalDiagnostics": start("diagnostics", "crash", "od", L10n.ui("正在检查诊断条件", "Checking diagnostic requirements"))
        default: break
        }
    }

    mutating func receive(_ event: String, _ data: Any) {
        let fields = data as? [String: Any] ?? [:]
        let state = fields["state"] as? String ?? ""
        switch event {
        case "scan": completeCheck("scan")
        case "upd":
            completeCheck("driverCheck")
            if state == "error" { finish("driverUpdate") }
        case "appCheck": completeCheck("appCheck")
        case "appupd":
            if state == "error" { finish("appUpdate") }
            else if state == "waiting" {
                change("appUpdate") { $0.title = L10n.ui("App 已校验，等待当前任务结束", "App verified. Waiting for the current task to finish") }
            }
            else if state == "restarting" {
                change("appUpdate") { $0.title = L10n.ui("正在替换并重新打开 App", "Replacing and reopening app"); $0.fraction = 0.99 }
            } else { start("appUpdate", "drv", "updapp", L10n.ui("正在下载并校验 App", "Downloading and verifying app")) }
        case "dl":
            let id = downloadID
            if state == "start", !active.contains(where: { $0.id == id }) {
                start(id, "drv", "dl", L10n.ui("正在下载驱动", "Downloading driver"))
            }
            if state == "progress" {
                let done = (fields["done"] as? NSNumber)?.doubleValue ?? 0
                let total = (fields["total"] as? NSNumber)?.doubleValue ?? 0
                change(id) {
                    let download = total > 0 ? min(max(done / total, 0), 1) : 0
                    $0.fraction = id == "driverUpdate" ? download * 0.6 : id == "setup" ? max($0.fraction ?? 0, download * 0.25) : total > 0 ? download : nil
                    $0.basis = id == "driverUpdate" ? L10n.ui("总进度", "Overall progress") : id == "setup" ? L10n.ui("阶段进度", "Stage progress") : ""
                    $0.amount = total > 0 ? String(format: "%.1f / %.1f MB", done / 1048576, total / 1048576) : String(format: "%.1f MB", done / 1048576)
                    // Downloaded bytes do not include verification or installation.
                    if total > 0 && done >= total {
                        $0.title = L10n.ui("正在校验下载文件", "Verifying downloaded file")
                        $0.fraction = id == "driverUpdate" ? 0.6 : id == "setup" ? max($0.fraction ?? 0, 0.25) : nil
                    }
                }
            }
            if state == "done" {
                if id == "driverUpdate" { change(id) { $0.title = L10n.ui("正在准备安装驱动更新", "Preparing to install driver update"); $0.fraction = 0.6; $0.amount = "" } }
                else { finish(id) }
            }
            if state == "error" { finish(id) }
        case "run":
            if state == "start" {
                if active.contains(where: { $0.id == "driverUpdate" }) {
                    change("driverUpdate") { $0.title = L10n.ui("正在安装驱动更新", "Installing driver update"); $0.fraction = max($0.fraction ?? 0, 0.6); $0.amount = "" }
                } else if !active.contains(where: { $0.id == "setup" }) {
                    let mode = fields["mode"] as? String ?? ""
                    start("setup", mode == "usbmap" ? "usb" : "drv", "logwrap", L10n.ui("正在执行操作", "Running operation"))
                } else { change("setup") { $0.fraction = $0.fraction ?? 0; $0.amount = "" } }
            } else if ["end", "cancelled"].contains(state) {
                finish("setup")
                if fields["mode"] as? String == "install" || state == "cancelled" { finish("driverUpdate") }
            }
        case "efiCheck": finish("efiCheck")
        case "efiMount": finish("efiMount")
        case "usbErr": finish("setup")
        case "gpumapStatus":
            if fields["done"] as? Bool == true { finish("gpuMap") }
            else {
                // The upstream stage is announced before it starts; count completed stages only.
                let text = fields["text"] as? String ?? ""
                if let range = text.range(of: #"\((\d+) of (\d+)\)"#, options: .regularExpression) {
                    let counts = text[range].split(whereSeparator: { !$0.isNumber }).compactMap { Double($0) }
                    if counts.count == 2, counts[1] > 0 {
                        change("gpuMap") {
                            $0.fraction = min(max((counts[0] - 1) / counts[1], 0), 1)
                            $0.amount = L10n.ui("已完成 \(Int(counts[0] - 1)) / \(Int(counts[1])) 项", "\(Int(counts[0] - 1)) / \(Int(counts[1])) steps completed")
                        }
                    }
                }
            }
        case "logsStatus":
            if !active.contains(where: { $0.id == "logs" }) { start("logs", "crash", "sl", L10n.ui("正在收集并发送日志", "Collecting and sending logs")) }
            if fields["text"] as? String == "Sending..." { change("logs") { $0.title = L10n.ui("正在整理并发送日志", "Preparing and sending logs") } }
        case "taskProgress":
            guard let fraction = (fields["fraction"] as? NSNumber)?.doubleValue, fraction.isFinite,
                  (0..<1).contains(fraction), let task = fields["task"] as? String else { return }
            let id = task == "setup" && active.contains(where: { $0.id == "driverUpdate" }) ? "driverUpdate" : task
            guard ["setup", "driverUpdate", "logs", "appUpdate"].contains(id) else { return }
            change(id) {
                let value = id == "driverUpdate" ? 0.6 + 0.4 * fraction : fraction
                guard value >= ($0.fraction ?? 0) else { return }
                $0.fraction = value
                if id == "logs" {
                    $0.title = fraction < 0.62 ? L10n.ui("正在采集系统与驱动日志", "Collecting system and driver logs") : fraction < 0.70 ? L10n.ui("正在整理硬件信息", "Preparing hardware information") : fraction < 0.75 ? L10n.ui("正在整理并校验报告", "Preparing and verifying the report") : L10n.ui("正在发送日志", "Sending logs")
                    if let completed = fields["completed"] as? Int, let total = fields["total"] as? Int, total > 0 {
                        $0.amount = L10n.ui("已处理 \(completed) / \(total) 份", "\(completed) of \(total) files processed")
                    }
                } else if id == "appUpdate" {
                    $0.title = fraction < 0.75 ? L10n.ui("正在校验 App 更新签名", "Verifying app update signature") : fraction < 0.85 ? L10n.ui("正在解压并检查 App", "Extracting and checking app") : fraction < 0.95 ? L10n.ui("正在校验 App 代码签名", "Verifying app code signature") : L10n.ui("正在准备替换 App", "Preparing to replace app")
                }
            }
        case "logsDone": finish("logs")
        case "diagnosticsStatus":
            if fields["text"] as? String != "Checking availability. No trace starts." { finish("diagnostics") }
        default: break
        }
    }

    private var downloadID: String {
        if active.contains(where: { $0.id == "driverUpdate" }) { return "driverUpdate" }
        if active.contains(where: { $0.id == "setup" && $0.anchor == "gpuon" }) { return "setup" }
        return "download"
    }

    private mutating func start(_ id: String, _ page: String, _ anchor: String, _ title: String) {
        var task = NativeTask(id: id, page: page, anchor: sourceAnchor == "dl3" ? "updt" : sourceAnchor ?? anchor, title: title)
        if ["setup", "logs", "gpuMap", "driverUpdate", "appUpdate"].contains(id) {
            task.fraction = 0
            task.basis = id == "driverUpdate" ? L10n.ui("总进度", "Overall progress") : L10n.ui("阶段进度", "Stage progress")
        }
        if let index = active.firstIndex(where: { $0.id == id }) { active[index] = task }
        else { active.append(task) }
    }

    private mutating func change(_ id: String, _ update: (inout NativeTask) -> Void) {
        if let index = active.firstIndex(where: { $0.id == id }) { update(&active[index]) }
    }

    private mutating func enqueue(_ id: String, _ page: String, _ anchor: String, _ title: String) {
        pendingChecks[id, default: 0] += 1
        start(id, page, anchor, title)
    }

    private mutating func completeCheck(_ id: String) {
        let remaining = max((pendingChecks[id] ?? 1) - 1, 0)
        pendingChecks[id] = remaining
        guard id == "driverCheck" || id == "appCheck" else {
            if remaining == 0 { finish(id) }
            return
        }
        let driverPending = pendingChecks["driverCheck", default: 0]
        let appPending = pendingChecks["appCheck", default: 0]
        if driverPending == 0 && appPending == 0 {
            finish("updateCheck")
        } else {
            let title: String
            if driverPending > 0 && appPending > 0 { title = L10n.ui("正在检查驱动和 App 更新", "Checking for driver and app updates") }
            else if driverPending > 0 { title = L10n.ui("正在检查驱动更新", "Checking for driver updates") }
            else { title = L10n.ui("正在检查 App 更新", "Checking for app updates") }
            change("updateCheck") { $0.title = title }
        }
    }

    private mutating func finish(_ id: String) { active.removeAll { $0.id == id } }
}
