import AppKit
import SwiftUI

// The native presentation retains upstream DriverSettings.plan/command and read-back verification.
final class SettingsPanel: NSObject, ObservableObject, NSWindowDelegate {
    static var shared: SettingsPanel?
    private var window: NSWindow?
    let catalog: DriverSettings.Catalog
    @Published var values: [String: String] = [:]
    @Published var messages: [String: String] = [:]
    @Published var gpus: [GpuFacts.Gpu] = []
    @Published var safeBootArgs = false
    @Published var bootArgsReadable = false
    @Published var configurationReadable = false
    @Published var busy = false
    @Published var loading = true

    @discardableResult static func show() -> Bool {
        if let panel = shared { panel.window?.makeKeyAndOrderFront(nil); return true }
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("settings_catalog.json"),
              let data = try? Data(contentsOf: url), let catalog = DriverSettings.load(data) else { return false }
        let panel = SettingsPanel(catalog)
        shared = panel
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "驱动设置"
        window.minSize = NSSize(width: 560, height: 480)
        window.isReleasedWhenClosed = false
        window.delegate = panel
        window.contentView = NSHostingView(rootView: NativeSettingsView(model: panel))
        panel.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        panel.refresh()
        return true
    }
    private init(_ catalog: DriverSettings.Catalog) { self.catalog = catalog }
    // Keep the update gate alive until a privileged change and its read-back have finished.
    func windowShouldClose(_ sender: NSWindow) -> Bool { !busy }
    func windowWillClose(_ notification: Notification) { Self.shared = nil }

    private func bootArgs() -> String? {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/nvram"); process.arguments = ["boot-args"]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return NativeSettingsSafety.parseBootArgs(output, status: process.terminationStatus)
    }
    private func confText() -> String? { NativeSettingsSafety.readConfiguration(catalog.confPath) }
    private func current(_ setting: DriverSettings.Setting, _ args: String?, _ conf: String?) -> String? {
        if setting.where_ == "bootarg" {
            guard let args else { return nil }
            return DriverSettings.bootargsGet(args, setting.key) ?? "default"
        }
        guard let conf else { return nil }
        return DriverSettings.confGet(catalog, conf, setting.key) ?? "default"
    }
    private func selection(_ setting: DriverSettings.Setting, _ current: String) -> String {
        if setting.kind == "bool" { return current == "1" ? "on" : current == "0" ? "off" : "default" }
        if setting.kind == "enum" { return setting.values?.first(where: { $0.value == current })?.key ?? "default" }
        return current
    }
    func refresh() {
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let args = self.bootArgs(), conf = self.confText(), cards = GpuFacts.read()
            let current = Dictionary(uniqueKeysWithValues: self.catalog.settings.compactMap { setting -> (String, String)? in
                guard let value = self.current(setting, args, conf) else { return nil }
                return (setting.id, self.selection(setting, value))
            })
            DispatchQueue.main.async {
                self.values = current; self.gpus = cards
                self.bootArgsReadable = args != nil; self.configurationReadable = conf != nil
                self.safeBootArgs = args.map(DriverSettings.bootargsSafe) ?? false; self.loading = false
            }
        }
    }
    func apply(_ setting: DriverSettings.Setting) {
        let value = (values[setting.id] ?? "default").trimmingCharacters(in: .whitespacesAndNewlines)
        let input = value.isEmpty ? "default" : value
        let change: DriverSettings.Change
        do { change = try NativeSettingsSafety.plan(catalog, setting, input, bootArgs: bootArgs(), conf: confText()) }
        catch DriverSettings.Bad.refused(let why) { messages[setting.id] = "设置未更改：\(why)"; return }
        catch let error as NativeSettingsSafety.ReadError { messages[setting.id] = error.localizedDescription; return }
        catch { messages[setting.id] = "设置未更改：\(error)"; return }
        let detail: String
        switch change {
        case .bootArgs(let line): detail = "将 \(NativeSettingsText.title(setting)) 设为 \(input)。\n\n启动参数将变为：\n\(line.isEmpty ? "（空）" : line)\n\n重启后生效。"
        case .conf: detail = "将 \(NativeSettingsText.title(setting)) 设为 \(input)。\n\n这会将 \(setting.key) 写入 \(catalog.confPath) 的用户设置区，更新时会保留。\n\n\(NativeSettingsText.effect(setting))"
        }
        let alert = NSAlert(); alert.messageText = "更改此设置？"; alert.informativeText = detail
        alert.addButton(withTitle: "更改"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { messages[setting.id] = "已取消，设置未更改。"; return }
        let command = DriverSettings.command(catalog, change), catalog = self.catalog
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Privileged.run(command, timeout: 120)
            if let error = result.error { DispatchQueue.main.async { self.busy = false; self.messages[setting.id] = error }; return }
            guard let now = self.current(setting, self.bootArgs(), self.confText()) else {
                DispatchQueue.main.async { self.busy = false; self.messages[setting.id] = "命令已执行，但无法读取配置，不能确认更改是否生效。" }
                return
            }
            let expected = (try? DriverSettings.normalize(catalog, setting, input)) ?? nil
            let success = now == (expected ?? "default")
            DispatchQueue.main.async {
                self.busy = false
                self.values[setting.id] = self.selection(setting, now)
                self.messages[setting.id] = success ? "已更改。\(NativeSettingsText.effect(setting))" : "设置未生效，当前值：\(now)。"
            }
        }
    }
}

private enum NativeSettingsText {
    static let titles: [String: String] = [
        "hdr": "HDR10", "10bit": "10 位色彩", "vrr": "可变刷新率", "bpc": "输出色深", "format": "输出色彩格式",
        "range": "输出动态范围", "vibrance": "数字鲜艳度", "dsr": "动态超分辨率", "hidpi": "HiDPI 显示模式",
        "rotscale": "旋转显示器缩放", "surround": "多屏拼接", "edp-backlight": "笔记本屏幕亮度",
        "fps-limit": "帧率限制", "queue-depth": "低延迟模式", "shader-cache-mb": "着色器缓存大小",
        "multigpu": "多张 NVIDIA 显卡（实验性）", "card": "为应用选择显卡", "app-profiles": "内置应用配置", "local-map-sysmem": "CPU 写入的内存保留在系统内存"
    ]
    static let helps: [String: String] = [
        "hdr": "向 EDID 中支持 PQ 的显示器提供 HDR10。", "10bit": "切换显示模式时输出 30 位色彩。",
        "vrr": "允许 WindowServer 在支持的显示器上请求可变刷新率。", "bpc": "设置连接中每个颜色通道的位数；默认由驱动选择。",
        "format": "设置连接的像素格式；默认由驱动选择。", "range": "设置 RGB 全范围或受限范围；默认由驱动选择。",
        "vibrance": "饱和度增益为 0–200，100 保持原色。", "dsr": "提供高于屏幕分辨率的桌面并缩小显示，会预留显示内存。",
        "hidpi": "使用最高两倍屏幕分辨率的桌面支持缩放模式。", "rotscale": "为旋转的显示器提供额外分辨率。",
        "surround": "输入组成同一逻辑显示器的帧缓冲编号位掩码，例如前两个填 3；0 或默认关闭。",
        "edp-backlight": "默认开启；关闭后不再通过屏幕 AUX 通道控制亮度。",
        "fps-limit": "可输入全局帧率（如 60）或应用列表（如 Game=60,*=0）；范围为 10–1000，0 表示不限，不作用于 WindowServer。",
        "queue-depth": "GPU 可提前排队的工作数量为 1–32，默认 16。较低值可减少输入延迟，但可能降低帧率；对桌面及所有应用生效。",
        "shader-cache-mb": "着色器缓存达到此大小时会清理，默认 2048 MB；0 关闭清理。",
        "multigpu": "逐张启动并加速 NVIDIA 显卡；每个进程使用主卡或下方指定的显卡。",
        "card": "多卡时 0 为主卡、1 为第二张，最多为 7。可输入全局编号，或应用列表如 Game=1,*=0。",
        "app-profiles": "默认开启；关闭后停用随驱动提供的所有应用配置。",
        "local-map-sysmem": "为保证稳定默认开启；关闭后放在显存中，部分游戏可能更快，但对桌面不安全。"
    ]
    static func title(_ setting: DriverSettings.Setting) -> String { titles[setting.id] ?? setting.title }
    static func help(_ setting: DriverSettings.Setting) -> String { helps[setting.id] ?? setting.help }
    static func effect(_ setting: DriverSettings.Setting) -> String {
        if setting.where_ == "bootarg" || setting.effect == "restart" { return "重启后生效。" }
        if setting.effect == "relaunch the application" { return "重新启动应用后生效。" }
        return "生效时机：\(setting.effect)。"
    }
    static func gpuDescription(_ gpu: GpuFacts.Gpu) -> String {
        func speed(_ value: Double) -> String { value == value.rounded() ? String(Int(value)) : String(value) }
        let link: String
        switch gpu.link.verdict {
        case "unknown": link = "无法读取 PCIe 链路"
        case "degraded": link = "PCIe \(speed(gpu.link.speed)) GT/s x\(gpu.link.width)，低于显卡支持的 x\(gpu.link.maxWidth)"
        case "idle-or-low": link = "PCIe \(speed(gpu.link.speed)) GT/s x\(gpu.link.width)（最高 \(speed(gpu.link.maxSpeed)) GT/s；空闲时可能降速）"
        default: link = "PCIe \(speed(gpu.link.speed)) GT/s x\(gpu.link.width)"
        }
        let driver = gpu.driver.isEmpty ? "未连接" : gpu.driver.joined(separator: ", ")
        return "\(gpu.deviceID) \(gpu.generation)：\(link)" + (gpu.external ? "，外接（Thunderbolt）" : "") + "，驱动：" + driver
    }
    static func option(_ value: String) -> String {
        ["default":"默认", "on":"开启", "off":"关闭", "full":"全范围", "limited":"受限范围"].first(where: { $0.key == value })?.value ?? value.uppercased()
    }
}

private struct NativeSettingsView: View {
    @ObservedObject var model: SettingsPanel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("驱动设置").font(.title.bold())
                Text("每项更改都会先显示完整内容并请求确认。显示设置会修改启动参数，重启后生效。")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if model.loading { ProgressView("正在读取硬件和设置…") }
                if !model.loading && !model.safeBootArgs {
                    Text(model.bootArgsReadable ? "当前启动参数包含此窗口不能安全改写的字符，启动参数设置在此处为只读。" : "无法读取当前启动参数，相关设置暂不可更改。")
                        .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                if !model.loading && !model.configurationReadable {
                    Text("无法读取驱动配置，相关设置暂不可更改。")
                        .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                Text("本机显卡").font(.headline)
                if !model.loading && model.gpus.isEmpty { Text("系统未检测到 NVIDIA 显卡。").foregroundStyle(.secondary) }
                ForEach(Array(model.gpus.enumerated()), id: \.offset) { _, gpu in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NativeSettingsText.gpuDescription(gpu)).textSelection(.enabled)
                        if !gpu.nvrm.isEmpty { Text(gpu.nvrm.keys.sorted().map { "\($0): \(gpu.nvrm[$0] ?? "")" }.joined(separator: "  ")).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(["Display", "Performance"], id: \.self) { group in
                    Text(group == "Display" ? "显示" : "性能").font(.headline)
                    ForEach(model.catalog.settings.filter { $0.group == group }, id: \.id) { setting in
                        NativeSettingRow(model: model, setting: setting)
                    }
                }
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(minWidth: 560, minHeight: 480)
            .background(NativePalette.background)
            .foregroundStyle(NativePalette.ink)
    }
}

private struct NativeSettingRow: View {
    @ObservedObject var model: SettingsPanel
    let setting: DriverSettings.Setting
    private var value: Binding<String> {
        Binding(get: { model.values[setting.id] ?? "default" }, set: { model.values[setting.id] = $0 })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top) {
                Text(NativeSettingsText.title(setting)).fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading)
                if !model.loading && (setting.where_ == "bootarg" ? !model.bootArgsReadable : !model.configurationReadable) {
                    Text("不可读取").foregroundStyle(.secondary).frame(width: 145)
                } else if setting.id == "surround" || setting.id == "card" {
                    EmptyView()
                } else if setting.kind == "bool" || setting.kind == "enum" {
                    Picker("值", selection: value) {
                        let options = ["default"] + (setting.kind == "bool" ? ["on", "off"] : (setting.values?.keys.sorted() ?? []))
                        ForEach(options, id: \.self) { option in Text(NativeSettingsText.option(option)).tag(option) }
                    }.labelsHidden().frame(width: 145)
                } else {
                    TextField("默认", text: value).textFieldStyle(.roundedBorder).frame(width: 145)
                }
                Button("应用") { model.apply(setting) }
                    .disabled(model.busy || model.loading || (setting.where_ == "bootarg" ? !model.safeBootArgs : !model.configurationReadable))
            }
            if setting.id == "surround" {
                NativeSurroundControl(value: value)
                    .disabled(model.loading || !model.safeBootArgs || model.busy)
            } else if setting.id == "card" {
                NativeCardControl(value: value, gpuCount: model.gpus.count)
                    .disabled(model.loading || !model.configurationReadable || model.busy)
            }
            Text(NativeSettingsText.help(setting) + (setting.where_ == "bootarg" ? "（需重启）" : ""))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if setting.id == "surround", !NSScreen.screens.isEmpty {
                Text("当前连接的显示器：" + NSScreen.screens.map(\.localizedName).joined(separator: "、"))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let message = model.messages[setting.id] { Text(message).font(.callout).textSelection(.enabled) }
        }.padding(12)
            .background(NativePalette.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(NativePalette.line, lineWidth: 1))
    }
}
