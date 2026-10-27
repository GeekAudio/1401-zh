// Native Chinese interface for the 1401 downstream distribution.
// Original installer and diagnostics: Copyright (c) 2026 NullMoth Systems.
import SwiftUI
import AppKit

final class NativeModel: ObservableObject {
    @Published var machine: [String: Any] = [:]
    @Published var status = "正在读取硬件与驱动状态…"
    @Published var output = ""
    @Published var updates = "更新来自 GeekAudio/1401-zh。"
    @Published var appStatus = "中文 App 更新来自 GeekAudio/1401-zh。"
    @Published var busy = false
    @Published var downloading = false
    @Published var previewed = false
    @Published var previewIdentity = ""
    @Published var package = ""
    @Published var efi = "auto" { didSet { if oldValue != efi { previewed = false } } }
    @Published var candidates: [String] = []
    @Published var driverUpdate = false
    @Published var appUpdate = false
    @Published var early = false
    @Published var testerOn = false
    @Published var testerStatus = "测试计划按作者原有流程运行。"
    @Published var collecting = false
    @Published var issues: [[String: Any]] = []
    @Published var efiStatus = "读取启动分区并检查配置；此检查不会修改 EFI。"
    @Published var diagnosticStatus = "确认后按作者原有流程向 NullMoth 上传诊断。"
    @Published var controllers: [[String: Any]] = []
    @Published var seen: [String: [String]] = [:]
    @Published var picks: [String: [String: Int]] = [:]
    @Published var excluded = Set<String>()
    @Published var watching = false
    @Published var selected: String? = "mac"
    var action: ([String: Any]) -> Void = { _ in }

    var working: Bool { busy || downloading }
    var previewKey: String { package + "\n" + efi }
    var canInstall: Bool { !working && !package.isEmpty && previewed && previewIdentity == previewKey && eligibility == nil }
    var eligibility: String? {
        guard !machine.isEmpty else { return "正在读取系统信息。" }
        if machine["arch"] as? String != "x86_64" || machine["translated"] as? Bool == true { return "此驱动适用于 Intel Mac 和 x86 PC，Apple 芯片 Mac 无需安装。" }
        if ![15, 26].contains(machine["major"] as? Int ?? 0) { return "此驱动适用于 macOS 15 Sequoia 和 macOS 26 Tahoe。" }
        let gpu = (machine["gpus"] as? [[String: Any]] ?? []).contains { $0["supported"] as? Bool == true }
        if !gpu { return "未检测到受支持的 NVIDIA 显卡。请先检查 BIOS、GPU 屏蔽参数及 DeviceProperties。" }
        if (machine["opencore"] as? String ?? "").isEmpty { return "未检测到 OpenCore，请先确认当前启动方式。" }
        return nil
    }
    func perform(_ act: String, _ fields: [String: Any] = [:]) {
        var command = fields; command["act"] = act
        if command["efi"] == nil { command["efi"] = efi }
        if command["pkg"] == nil { command["pkg"] = package }
        if act == "run", fields["mode"] as? String == "install", !canInstall { return }
        if act == "run", fields["mode"] as? String == "dry" { previewIdentity = previewKey }
        if act == "checkUpdate" { updates = "正在检查作者的最新驱动…"; appStatus = "正在检查中文 App 更新…" }
        action(command)
    }
    func receive(_ event: String, _ data: Any) {
        let d = data as? [String: Any] ?? [:], state = d["state"] as? String ?? ""
        let reason = ZH.text(d["why"] as? String ?? "")
        switch event {
        case "scan":
            machine = d
            let checked = (d["packages"] as? [[String: Any]] ?? []).first { $0["ok"] as? String == "yes" }?["path"] as? String ?? ""
            if package != checked { package = checked; previewed = false }
            status = eligibility ?? "硬件信息已读取。安装前请预览 OpenCore 配置更改。"
        case "lines":
            for line in data as? [String] ?? [] {
                output += line + "\n"
                if line.hasPrefix("NOTE candidate "), let disk = line.split(separator: " ").dropFirst(2).first.map(String.init), !candidates.contains(disk) { candidates.append(disk) }
            }
        case "run":
            busy = state == "start"
            if busy { output = ""; status = "正在执行，请留意系统密码窗口…"; return }
            if state == "cancelled" { status = "操作已取消。"; return }
            let ok = d["ok"] as? Bool == true
            if d["mode"] as? String == "dry" { previewed = ok && previewIdentity == previewKey }
            status = ok ? (d["mode"] as? String == "dry" ? "预览完成。请确认下方更改记录，再点击安装。" : "操作完成。驱动安装或配置更改需重启后验证。") : "操作未完成。" + reason + " 请查看操作记录。"
            perform("scan")
        case "dl":
            if state == "start" { downloading = true; status = "正在下载驱动包…" }
            if state == "progress" {
                let done = (d["done"] as? NSNumber)?.doubleValue ?? 0, total = (d["total"] as? NSNumber)?.doubleValue ?? 0
                status = total > 0 ? String(format: "正在下载：%.0f%%（%.1f / %.1f MB）", done / total * 100, done / 1048576, total / 1048576) : String(format: "已下载 %.1f MB", done / 1048576)
            }
            if ["done", "error"].contains(state) { downloading = false; status = state == "done" ? "驱动包下载完成，SHA-256 校验通过。" : reason; if state == "done" { perform("scan") } }
        case "upd":
            if state == "error" { updates = reason; driverUpdate = false }
            else {
                driverUpdate = d["newer"] as? Bool == true
                updates = "驱动：本机 \(d["installed"] as? String ?? "未知")，作者最新版本 \(d["latest"] as? String ?? "未知")。"
            }
        case "appCheck":
            appUpdate = state == "checked" && d["newer"] as? Bool == true
            appStatus = state == "error" ? reason : "App：本机 \(d["have"] as? String ?? "")，最新 \(d["latest"] as? String ?? "")。"
        case "appupd": appStatus = state == "error" ? reason : state == "restarting" ? "更新已通过校验，正在重新打开 App…" : "正在下载并验证 App 更新…"
        case "efiCheck":
            if d["cancelled"] as? Bool == true { efiStatus = "检查已取消。"; return }
            issues = d["issues"] as? [[String: Any]] ?? []
            efiStatus = d["ok"] as? Bool == true ? "分区 \(d["partition"] as? String ?? "")：发现 \(issues.count) 项待检查设置。" : reason
            for disk in d["candidates"] as? [String] ?? [] { if !candidates.contains(disk) { candidates.append(disk) } }
        case "efiMount": efiStatus = d["cancelled"] as? Bool == true ? "挂载已取消。" : d["ok"] as? Bool == true ? "已挂载 \(d["partition"] as? String ?? "")：\(d["where"] as? String ?? "")" : reason
        case "early": early = d["on"] as? Bool == true
        case "tester":
            if d["ok"] as? Bool == true { testerOn = d["on"] as? Bool == true; testerStatus = testerOn ? "已加入：每次重启后按作者原流程上传测试报告。" : "已退出：不再运行测试报告登录项。" }
            else { testerStatus = reason }
        case "usb":
            controllers = d["controllers"] as? [[String: Any]] ?? []; seen = d["seen"] as? [String: [String]] ?? [:]
            for controller in controllers {
                let key = controller["key"] as? String ?? controller["controller"] as? String ?? ""
                for port in controller["ports"] as? [[String: Any]] ?? [] {
                    let name = port["name"] as? String ?? ""
                    if seen[key, default: []].contains(name), picks[key]?[name] == nil, !excluded.contains(key + "/" + name) {
                        picks[key, default: [:]][name] = connector(port)
                    }
                }
            }
        case "usbErr": status = ZH.text(data as? String ?? "USB 映射失败。")
        case "logsStatus": collecting = true; diagnosticStatus = ZH.text(d["text"] as? String ?? "")
        case "diagnosticsStatus", "diagnosticReceipt", "gpumapStatus": diagnosticStatus = ZH.text(d["text"] as? String ?? "")
        case "logsDone":
            collecting = false
            let errors = (d["errors"] as? [String] ?? []).map(ZH.text).joined(separator: "；")
            diagnosticStatus = d["ok"] as? Bool == true ? "已发送。报告编号：\((d["ids"] as? [String] ?? []).joined(separator: "、"))。" + errors : reason.isEmpty ? "未发送：" + errors : reason
        case "crashDone": diagnosticStatus = d["ok"] as? Bool == true ? "崩溃报告已保存：\(d["path"] as? String ?? "")" : reason
        default: break
        }
    }
    func connector(_ port: [String: Any]) -> Int {
        let value = port["connector"] as? Int ?? -1
        return port["connectorKnown"] as? Bool == true && [0,3,9,10,255].contains(value) ? value : port["usb3"] as? Bool == true ? 3 : 0
    }
}

struct NativeRoot: View {
    @ObservedObject var model: NativeModel
    private let sections = [("mac", "本机与驱动", "desktopcomputer"), ("efi", "EFI 检查", "checkmark.shield"), ("tools", "系统工具", "wrench.and.screwdriver"), ("usb", "USB 端口", "cable.connector"), ("reports", "诊断与反馈", "doc.text.magnifyingglass"), ("about", "关于", "info.circle")]
    var body: some View {
        NavigationSplitView {
            List(selection: $model.selected) {
                ForEach(sections, id: \.0) { item in Label(item.1, systemImage: item.2).tag(item.0) }
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 165, max: 210)
            .safeAreaInset(edge: .bottom) { VStack(alignment: .leading, spacing: 4) { Text("1401 中文版").font(.headline); Text("GeekAudio · 原生 macOS 界面").font(.caption).foregroundStyle(.secondary) }.padding() }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(sections.first { $0.0 == model.selected }?.1 ?? "本机与驱动").font(.title2.bold())
                    switch model.selected {
                    case "efi": efi
                    case "tools": tools
                    case "usb": usb
                    case "reports": reports
                    case "about": about
                    default: machine
                    }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .toolbar { ToolbarItem { Button { model.perform("scan") } label: { Label("刷新", systemImage: "arrow.clockwise") }.disabled(model.working).help("重新读取硬件与驱动状态") } }
        .onChange(of: model.selected) { _, page in if page != "usb" { model.watching = false; model.perform("usbStop") } }
    }
    func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GroupBox { VStack(alignment: .leading, spacing: 10, content: content).frame(maxWidth: .infinity, alignment: .leading).padding(5) } label: { Text(title).font(.headline) }
    }
    var destination: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("OpenCore 分区", selection: $model.efi) {
                Text("自动确认当前启动分区").tag("auto")
                ForEach(model.candidates, id: \.self) { Text($0).tag($0) }
                if model.efi != "auto" && !model.candidates.contains(model.efi) { Text(model.efi).tag(model.efi) }
            }.frame(maxWidth: 500)
            HStack { TextField("或输入分区标识，例如 disk0s1", text: Binding(get: { model.efi == "auto" ? "" : model.efi }, set: { model.efi = $0.isEmpty ? "auto" : $0 })).frame(maxWidth: 340); Text("更换分区后需重新预览。").font(.caption).foregroundStyle(.secondary) }
        }.disabled(model.working)
    }
    var machine: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("安装前请保持 OpenCore 启动盘连接。预览会列出配置更改，安装会先备份原配置。").foregroundStyle(.secondary)
            card("系统状态") {
                Grid(alignment: .leading, horizontalSpacing: 26, verticalSpacing: 10) {
                    fact("macOS", model.machine["macos"] as? String ?? "读取中…")
                    fact("处理器架构", model.machine["arch"] as? String ?? "读取中…")
                    fact("OpenCore", (model.machine["opencore"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "未检测到")
                    fact("显卡", (model.machine["gpus"] as? [[String: Any]] ?? []).map { $0["name"] as? String ?? "" }.joined(separator: "、"))
                    fact("已加载驱动组件", "\(model.machine["kexts"] as? Int ?? 0) / 4")
                    fact("Metal 设备", (model.machine["metal"] as? [String] ?? []).joined(separator: "、"))
                    fact("已安装驱动版本", (model.machine["installedDriverVersion"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "无版本记录")
                }.textSelection(.enabled)
                Text("组件已加载与 Metal 设备可见仍需结合显示、应用和睡眠唤醒测试确认。").font(.caption).foregroundStyle(.secondary)
            }
            card("安装 NVIDIA 驱动") {
                destination
                if let why = model.eligibility { Label(why, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                HStack {
                    Button("1. 下载驱动包") { model.perform("download") }.disabled(model.working)
                    Button("2. 预览配置更改") { model.perform("run", ["mode": "dry"]) }.disabled(model.working || model.package.isEmpty || model.eligibility != nil)
                    Button("3. 安装驱动") { if confirm("安装 NVIDIA 驱动？", "将按预览修改所选 OpenCore 分区，并安装驱动。请先核对下方操作记录。") { model.perform("run", ["mode": "install"]) } }.disabled(!model.canInstall).buttonStyle(.borderedProminent)
                    Button("重启…") { if confirm("现在重新启动？", "请先保存所有正在编辑的文件。") { model.perform("restart") } }
                }
                if model.working { ProgressView().controlSize(.small) }
                Text(model.status).textSelection(.enabled)
                Button("打开隐私与安全性") { model.perform("privacy") }.buttonStyle(.link)
            }
            card("App 与驱动更新") {
                Text(model.updates + "\n" + model.appStatus).textSelection(.enabled)
                HStack {
                    Button("检查更新") { model.perform("checkUpdate") }.disabled(model.working)
                    if model.driverUpdate { Button("更新驱动…") { if confirm("更新 NVIDIA 驱动？", "将下载并校验新版驱动，备份所选分区的配置后执行安装。") { model.perform("updateDriver") } }.disabled(model.working) }
                    if model.appUpdate { Button("更新 App") { model.perform("updateApp") }.disabled(model.working) }
                    Button("打开下载页面") { model.perform("open", ["url": Downstream.releases]) }
                }
                Toggle("接收作者的驱动测试版更新", isOn: Binding(get: { model.early }, set: { model.perform("early", ["on": $0]) }))
            }
            operationLog
        }
    }
    func fact(_ key: String, _ value: String) -> some View { GridRow { Text(key).foregroundStyle(.secondary); Text(value.isEmpty ? "未检测到" : value).frame(maxWidth: .infinity, alignment: .leading) } }
    var efi: some View {
        VStack(alignment: .leading, spacing: 20) {
            card("启动配置") {
                destination
                HStack { Button("检查 EFI") { model.perform("checkEfi") }; Button("挂载 EFI 并在访达中打开") { model.perform("mountEfi") } }.disabled(model.working)
                Text(model.efiStatus).textSelection(.enabled)
            }
            ForEach(Array(model.issues.enumerated()), id: \.offset) { _, issue in
                card(ZH.text(issue["title"] as? String ?? "待检查设置")) {
                    Text(ZH.text(issue["what"] as? String ?? ""))
                    if let now = issue["now"] as? [String], !now.isEmpty { Text("当前值：" + now.joined(separator: " ")).font(.system(.body, design: .monospaced)) }
                    ForEach(Array((issue["steps"] as? [String] ?? []).enumerated()), id: \.offset) { index, step in Text("\(index + 1). " + ZH.text(step)) }
                    if issue["restart"] as? Bool == true { Text("此设置在下次重启后生效。").foregroundStyle(.secondary) }
                }.textSelection(.enabled)
            }
            Text("手动编辑 config.plist 前请另存备份。检查结果是配置建议，不能代替实际启动验证。").foregroundStyle(.secondary)
        }
    }
    var tools: some View {
        VStack(alignment: .leading, spacing: 20) {
            card("启动与显示") {
                destination
                HStack { Button("开启详细启动") { tool("verbose", true) }; Button("关闭详细启动") { tool("verbose", false) } }
                HStack { Button("开启内屏背光支持") { tool("backlight", true) }; Button("关闭内屏背光支持") { tool("backlight", false) } }
            }
            card("升级到 macOS 26 Tahoe") {
                Text("从 macOS 15 升级前先准备驱动与安装器配置。取消准备可恢复先前设置。")
                HStack {
                    Button("准备升级…") { if confirm("准备升级到 Tahoe？", "将安装驱动并调整所选 OpenCore 的安装器设置。") { model.perform("osupdate", ["cancel": false]) } }.disabled(model.machine["major"] as? Int != 15 || model.package.isEmpty || model.eligibility != nil)
                    Button("取消升级准备…") { if confirm("取消 Tahoe 升级准备？", "将恢复驱动及安装器设置。") { model.perform("osupdate", ["cancel": true]) } }
                    Button("打开软件更新") { model.perform("swupdate") }
                }
            }
            card("实验性 AMD / Intel GPU 与 NPU") {
                Text("使用作者提供的独立签名测试驱动包，保留原有测试通道。")
                HStack { Button("启用测试驱动…") { tool("gputest", true) }; Button("关闭测试驱动…") { tool("gputest", false) } }
                Toggle("加入作者的 AMD / Intel 测试计划", isOn: Binding(get: { model.testerOn }, set: { model.perform("tester", ["on": $0]) }))
                Text("加入后，每次重启会按作者原流程向 nullmothsystems.com 发送已脱敏的测试报告；退出会移除对应登录项。").font(.caption).foregroundStyle(.secondary)
                Text(model.testerStatus).textSelection(.enabled)
            }
            operationLog
        }.disabled(model.working)
    }
    func tool(_ act: String, _ on: Bool) { if confirm("修改 OpenCore 设置？", "此操作会备份并更改所选分区，可能需要重启。") { model.perform(act, ["on": on]) } }
    var usb: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("开始检测后，依次插入 USB 2 和 USB 3 设备。每个控制器最多选择 15 个端口。").foregroundStyle(.secondary)
            destination
            HStack {
                Button(model.watching ? "停止检测" : "开始检测") { model.watching.toggle(); model.perform(model.watching ? "usbStart" : "usbStop") }
                Button("写入 USB 映射…") { if confirm("写入 USB 映射？", "会生成 UTBMap 并更新所选 OpenCore 配置。请先核对每个端口的连接类型。") { model.watching = false; model.perform("usbStop"); model.perform("usbWrite", ["sel": model.picks]) } }.disabled(model.picks.values.allSatisfy { $0.isEmpty } || model.picks.values.contains { $0.count > 15 } || model.working)
            }
            ForEach(Array(model.controllers.enumerated()), id: \.offset) { _, controller in
                let key = controller["key"] as? String ?? controller["controller"] as? String ?? ""
                card("\(controller["controller"] as? String ?? "USB") · 已选 \(model.picks[key]?.count ?? 0) / 15") {
                    ForEach(Array((controller["ports"] as? [[String: Any]] ?? []).enumerated()), id: \.offset) { _, port in
                        let name = port["name"] as? String ?? ""
                        HStack {
                            Toggle(name, isOn: Binding(get: { model.picks[key]?[name] != nil }, set: { on in if on { model.excluded.remove(key + "/" + name); model.picks[key, default: [:]][name] = model.connector(port) } else { model.excluded.insert(key + "/" + name); model.picks[key]?.removeValue(forKey: name) } })).frame(width: 130, alignment: .leading)
                            Text(model.seen[key, default: []].contains(name) ? "已检测" : "未检测").foregroundStyle(.secondary).frame(width: 65)
                            Picker("连接类型", selection: Binding(get: { model.picks[key]?[name] ?? model.connector(port) }, set: { model.excluded.remove(key + "/" + name); model.picks[key, default: [:]][name] = $0 })) { Text("USB 2 Type-A").tag(0); Text("USB 3 Type-A").tag(3); Text("USB-C 可翻转").tag(9); Text("USB-C 单方向").tag(10); Text("内建端口").tag(255) }.labelsHidden().frame(width: 180)
                            Text((port["devices"] as? [String] ?? []).joined(separator: "、")).font(.caption).textSelection(.enabled)
                        }
                    }
                }
            }
            Text(model.status)
            operationLog
        }
    }
    var reports: some View {
        VStack(alignment: .leading, spacing: 20) {
            card("向作者发送诊断") {
                Text("保留作者的日志采集、脱敏、上传确认和重试流程。发送前会显示确认窗口，接收地址仍为 nullmothsystems.com。")
                HStack { Button("发送诊断日志…") { model.perform("sendLogs") }; Button("采集闪屏并发送…") { model.perform("sendLogs", ["sample": "flicker"]) } }.disabled(model.collecting)
                HStack { Button("导出崩溃报告") { model.perform("crashReport") }; Button("打开日志文件夹") { model.perform("logs") }; Button("打开作者的上传页面") { model.perform("open", ["url": "https://nullmothsystems.com/#send"]) } }
                Text(model.diagnosticStatus).textSelection(.enabled)
            }
            card("其他诊断") {
                HStack { Button("检查可选诊断条件") { model.perform("optionalDiagnostics") }; Button("导入诊断回执") { model.perform("importDiagnosticReceipt") }; Button("采集 GPU 能力") { model.perform("gpumap") } }
                Text("GPU 能力采集会运行一组有超时限制的测试；不会修改驱动。")
            }
            card("移除驱动") {
                Button("移除驱动并恢复 OpenCore 配置…", role: .destructive) { if confirm("移除 NVIDIA 驱动？", "会移除已安装的驱动，并恢复安装前备份的 OpenCore 配置。") { model.perform("run", ["mode": "remove"]) } }.disabled(model.working)
            }
            operationLog
        }
    }
    var about: some View {
        card("1401 中文版") {
            Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版")").font(.title2)
            Text("SwiftUI + AppKit 原生界面 · 简体中文")
            Text("原始安装器与驱动由 NullMoth Systems 开发。中文界面、更新源和自动构建由 GeekAudio 维护。")
            Text("遵循 PolyForm Noncommercial 1.0.0，限非商业用途。第三方组件保留各自许可证。")
            HStack { Button("项目源码") { model.perform("open", ["url": Downstream.source]) }; Button("上游项目") { model.perform("open", ["url": "https://github.com/nullmoth/1401"]) }; Button("第三方声明") { model.perform("open", ["url": Downstream.source + "/blob/main/NOTICE.md"]) } }
            HStack { Button("OpenCore 安装指南") { model.perform("open", ["url": "https://dortania.github.io/OpenCore-Install-Guide/"]) }; Button("支持原作者") { model.perform("open", ["url": "https://buymeacoffee.com/nullmoth"]) } }
        }
    }
    var operationLog: some View {
        Group {
            if !model.output.isEmpty {
                card("操作记录") {
                    Text("安装器原始记录保留技术字段，便于排查问题。").font(.caption).foregroundStyle(.secondary)
                    Text(model.output).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    Button("打开日志文件夹") { model.perform("logs") }
                }
            }
        }
    }
    func confirm(_ title: String, _ detail: String) -> Bool {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        alert.addButton(withTitle: "继续"); alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

// Translate presentation only; button order and NSAlert response values remain unchanged.
final class ChineseAlert: NSAlert {
    override func runModal() -> NSApplication.ModalResponse {
        messageText = ZH.text(messageText); informativeText = ZH.text(informativeText)
        for button in buttons { button.title = ZH.text(button.title) }
        return super.runModal()
    }
}
final class ChineseOpenPanel: NSOpenPanel {
    override func runModal() -> NSApplication.ModalResponse {
        title = ZH.text(title)
        return super.runModal()
    }
}
