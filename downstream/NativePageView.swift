import AppKit
// Presentation only. Original page schema, copy and action routing are retained.
import SwiftUI

struct NativePageView: View {
    @ObservedObject var model: NativeModel
    static let pages: [PageNode] = {
        guard let url = Bundle.main.url(forResource: "native-pages", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let pages = try? JSONDecoder().decode([PageNode].self, from: data)
        else { return [] }
        return pages
    }()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if let page = Self.pages.first(where: { $0.id == model.selected }) {
                    VStack(alignment: .leading, spacing: NativeStyle.sectionGap) {
                        ForEach(arranged(page), id: \.key) { node in render(node) }
                    }
                    .padding(NativeStyle.pageInset)
                    .frame(maxWidth: page.id == "efi" ? 668 : .infinity, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: NativeLayoutHeightKey.self, value: ["page": geometry.size.height])
                        }
                    }
                    .id("page-top")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: model.selected) { _, _ in proxy.scrollTo("page-top", anchor: .top) }
            .onAppear {
                let arguments = CommandLine.arguments
                if arguments.contains("--ui-snapshot"), let i = arguments.firstIndex(of: "--ui-focus"), i + 1 < arguments.count {
                    proxy.scrollTo(arguments[i + 1], anchor: .center)
                }
            }
        }
    }
    func rich(_ text: String) -> Text {
        let pattern = #"\*\*(.+?)\*\*|\*([^*]+?)\*|\[([^\]]+)\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return Text(text) }
        var result = AttributedString("")
        var cursor = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text) else { continue }
            result.append(AttributedString(String(text[cursor..<whole.lowerBound])))
            if let range = Range(match.range(at: 1), in: text) {
                var part = AttributedString(String(text[range]))
                part.inlinePresentationIntent = .stronglyEmphasized
                result.append(part)
            } else if let range = Range(match.range(at: 2), in: text) {
                var part = AttributedString(String(text[range]))
                part.inlinePresentationIntent = .emphasized
                result.append(part)
            } else if let label = Range(match.range(at: 3), in: text),
                let address = Range(match.range(at: 4), in: text)
            {
                var part = AttributedString(String(text[label]))
                part.link = URL(string: String(text[address]))
                result.append(part)
            }
            cursor = whole.upperBound
        }
        result.append(AttributedString(String(text[cursor...])))
        return Text(result)
    }
    func bodyText(_ text: String) -> some View {
        let paragraphs = Self.semanticParagraphs(text)
        return Group {
            if paragraphs.count == 1, paragraphs[0].count == 1, paragraphs[0][0].count == 1 {
                rich(text)
                    .lineLimit(nil).lineSpacing(NativeStyle.lineGap).fixedSize(
                        horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: NativeStyle.lineGap) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, sentences in
                        SemanticFlowLayout {
                            ForEach(Array(sentences.enumerated()), id: \.offset) { _, clauses in
                                SemanticFlowLayout {
                                    ForEach(Array(clauses.enumerated()), id: \.offset) { _, clause in
                                        rich(clause)
                                            .lineLimit(nil).lineSpacing(NativeStyle.lineGap).fixedSize(
                                                horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Groups explicit lines, complete sentences, then safe punctuation clauses.
    /// The layout packs these groups using the width SwiftUI actually proposes.
    static func semanticParagraphs(_ source: String) -> [[[String]]] {
        source.components(separatedBy: "\n").map(semanticSentences)
    }

    private static func semanticSentences(_ source: String) -> [[String]] {
        let protectedPattern = #"\[[^\]]+\]\([^)]+\)|\*\*.+?\*\*|\*[^*\n]+?\*"#
        guard let protectedRegex = try? NSRegularExpression(pattern: protectedPattern) else {
            return [[source]]
        }
        let protected = protectedRegex.matches(in: source, range: NSRange(source.startIndex..., in: source))
            .compactMap { match -> Range<Int>? in
                guard let range = Range(match.range, in: source) else { return nil }
                let lower = source.distance(from: source.startIndex, to: range.lowerBound)
                let upper = source.distance(from: source.startIndex, to: range.upperBound)
                return lower..<upper
            }

        func isProtected(_ offset: Int) -> Bool {
            protected.contains { $0.contains(offset) }
        }
        let characters = Array(source)
        var sentences: [[String]] = []
        var clauses: [String] = []
        var start = 0
        for offset in characters.indices where !isProtected(offset) {
            guard "，：；。！？".contains(characters[offset]) else { continue }
            let end = offset + 1
            let clause = String(characters[start..<end])
            clauses.append(clause)
            start = end
            if "；。！？".contains(characters[offset]) {
                sentences.append(clauses)
                clauses = []
            }
        }
        if start < characters.count { clauses.append(String(characters[start...])) }
        if !clauses.isEmpty { sentences.append(clauses) }
        return sentences.isEmpty ? [[source]] : sentences
    }
    func containsLongParagraph(_ node: PageNode) -> Bool {
        let text = node.kind == "status" ? model.text(node.id) : node.text
        return text.count >= 60 || node.children.contains(where: containsLongParagraph)
    }
    @ViewBuilder func copy(_ text: String, nested: Bool = false) -> some View {
        if text.hasPrefix("**"), let end = text.dropFirst(2).range(of: "**") {
            let heading = String(text[text.index(text.startIndex, offsetBy: 2)..<end.lowerBound])
            let remainder = String(text[end.upperBound...])
            VStack(alignment: .leading, spacing: NativeStyle.controlGap) {
                Text(heading).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                    .font(NativeStyle.sectionTitle)
                if !remainder.isEmpty { bodyText(remainder).foregroundStyle(NativePalette.muted) }
            }
            .padding(nested ? NativeStyle.rowGap : 0)
            .background {
                if nested { RoundedRectangle(cornerRadius: 9).fill(NativePalette.soft) }
            }
        } else {
            bodyText(text)
        }
    }
    // The ARM card: the request 1401 for Windows left, the translation progress and the translated apps.
    var armRequestBanner: some View {
        let canRun = model.armRequest?["canRun"] as? Bool == true
        return VStack(alignment: .leading, spacing: NativeStyle.controlGap) {
            bodyText(model.armRequest?["text"] as? String ?? "")
            HStack(alignment: .firstTextBaseline, spacing: NativeStyle.controlGap) {
                if canRun {
                    NativeActionButton(
                        title: "开启", kind: .primary, disabled: model.armStarting, identifier: "armreqon"
                    ) { model.press("armreqon") }
                }
                Button("暂不") { model.press("armreqno") }
                    .buttonStyle(.link).foregroundStyle(NativePalette.accent)
                    .accessibilityIdentifier("armreqno")
            }
        }
        .padding(NativeStyle.rowGap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(NativePalette.soft))
    }
    var armProgress: some View {
        VStack(alignment: .leading, spacing: NativeStyle.controlGap) {
            if let percentage = model.armPct {
                ProgressView(value: min(max(percentage, 0), 100), total: 100).progressViewStyle(.linear)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            HStack(alignment: .firstTextBaseline, spacing: NativeStyle.controlGap) {
                if !model.armMsg.isEmpty {
                    Text(model.armMsg).font(NativeStyle.caption).foregroundStyle(NativePalette.muted)
                        .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                }
                NativeActionButton(
                    title: "取消", kind: .secondary, disabled: model.disabled("armcancel"), identifier: "armcancel"
                ) { model.press("armcancel") }
            }
        }
    }
    var armAppList: some View {
        VStack(alignment: .leading, spacing: NativeStyle.controlGap) {
            if model.armApps.isEmpty {
                Text("尚无翻译后的应用。").font(NativeStyle.caption).foregroundStyle(NativePalette.muted)
            } else {
                ForEach(Array(model.armApps.enumerated()), id: \.offset) { _, app in
                    HStack(alignment: .firstTextBaseline, spacing: NativeStyle.controlGap) {
                        Text(app["name"] ?? "").lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: NativeStyle.controlGap)
                        Button("打开") { model.armTask("open", ["path": app["path"] ?? ""]) }
                            .buttonStyle(.bordered).disabled(model.armRunning)
                        Button("移除") { model.armTask("remove", ["name": app["name"] ?? ""]) }
                            .buttonStyle(.bordered).disabled(model.armRunning)
                    }
                }
            }
        }
    }
    func actionKind(_ id: String) -> NativeActionKind {
        switch id {
        case "rm": return .destructive
        case "swu", "up", "cf", "cr": return .link
        case "efichk", "efimount", "sl": return .primary
        case "xeon", "tccg": return .primary
        case "xeoff": return .secondary
        case "dl": return model.package.isEmpty ? .primary : .secondary
        case "dry": return !model.package.isEmpty && !model.previewed ? .primary : .secondary
        case "go": return model.canInstall ? .primary : .secondary
        case "rs": return model.installed ? .primary : .secondary
        case "updchk": return model.driverUpdate || model.appUpdate ? .secondary : .primary
        case "upddrv", "updapp": return .primary
        case "uw": return model.watching ? .secondary : .primary
        case "uwr": return model.watching ? .primary : .secondary
        case "armon", "armreqon": return .primary
        case "armtr": return model.armOn && model.armOk ? .primary : .secondary
        default: return .secondary
        }
    }
    func arranged(_ page: PageNode) -> [PageNode] {
        if page.id == "drv", page.children.count >= 4 {
            return [
                PageNode(kind: "pageHeader", id: "", text: "", children: Array(page.children.prefix(2))),
                PageNode(kind: "overview", id: "", text: "", children: Array(page.children[2...3])),
            ] + Array(page.children.dropFirst(4).dropLast(2)) + [
                PageNode(
                    kind: "paired", id: "driver-support", text: "", children: Array(page.children.suffix(2)))
            ]
        }
        if page.id == "efi", let head = page.children.first {
            return [
                PageNode(kind: "checkPanel", id: "", text: "", children: [head]),
                PageNode(kind: "resultsPanel", id: "", text: "", children: Array(page.children.dropFirst())),
            ]
        }
        if page.id == "tools", page.children.count >= 3 {
            return [
                page.children[0],
                PageNode(kind: "paired", id: "tools-entry", text: "", children: Array(page.children[1...2])),
            ] + Array(page.children.dropFirst(3))
        }
        if page.id == "crash", page.children.count == 5 {
            return [
                page.children[0], page.children[1],
                PageNode(
                    kind: "paired", id: "report-options", text: "", children: Array(page.children[2...3])),
                page.children[4],
            ]
        }
        return page.children
    }
    func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NativePanel(content: content)
    }
    func children(_ node: PageNode) -> some View {
        VStack(alignment: .leading, spacing: NativeStyle.rowGap) {
            ForEach(node.children.filter(isVisible), id: \.key) { child in
                render(child)
                if child.kind == "button" { NativeTaskProgress(tasks: model.tasks.at([child.id])) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    func controls(_ nodes: [PageNode]) -> some View {
        let firstButton = nodes.firstIndex(where: { $0.kind == "button" }) ?? nodes.count
        let leading = Array(nodes.prefix(firstButton)).filter(isVisible)
        let buttons = nodes.filter { $0.kind == "button" && isVisible($0) }
        let trailing = Array(nodes.dropFirst(firstButton)).filter { $0.kind != "button" && isVisible($0) }
        return VStack(alignment: .leading, spacing: NativeStyle.controlGap) {
            ForEach(leading, id: \.key) { n in render(n) }
            if !buttons.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: NativeStyle.controlGap) {
                        ForEach(buttons, id: \.key) { n in render(n) }
                    }
                    VStack(alignment: .leading, spacing: NativeStyle.controlGap) {
                        ForEach(buttons, id: \.key) { n in render(n) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            NativeTaskProgress(tasks: model.tasks.at(nodes.filter { $0.kind == "button" }.map(\.id)))
            ForEach(trailing, id: \.key) { n in render(n) }
        }
    }
    func section(_ node: PageNode) -> some View {
        NativePanel {
            if let title = node.children.first {
                Text(title.text).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                    .font(NativeStyle.sectionTitle)
                    .foregroundStyle(NativePalette.ink).accessibilityAddTraits(.isHeader)
            }
            if node.id == "logwrap" {
                NativeTaskProgress(tasks: model.tasks.at(["logwrap"]))
                Text(model.output).font(.system(size: 11, design: .monospaced))
                    .lineSpacing(NativeStyle.lineGap).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(node.children.dropFirst()).filter(isVisible), id: \.key) { render($0) }
        }
    }
    func isVisible(_ n: PageNode) -> Bool {
        guard model.visible(n.id) else { return false }
        if n.kind == "status" {
            return !model.text(n.id).isEmpty
                || !model.tasks.at([n.id]).isEmpty
                || (n.id == "updt" && model.major == 15 && model.eligibility == nil
                    && model.goodPackage == nil)
        }
        if n.kind == "text" && n.text.isEmpty { return n.children.contains(where: isVisible) }
        return true
    }
    func render(_ n: PageNode) -> AnyView {
        guard isVisible(n) else { return AnyView(EmptyView()) }
        switch n.kind {
        case "title":
            return AnyView(
                Text(n.text).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                    .font(NativeStyle.title).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader))
        case "subtitle":
            return AnyView(
                Text(n.text).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                    .font(NativeStyle.sectionTitle).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader))
        case "legal":
            return AnyView(
                VStack(alignment: .leading, spacing: NativeStyle.rowGap) {
                    Divider()
                    bodyText(n.text).font(.system(size: 11)).foregroundStyle(NativePalette.muted)
                })
        case "button":
            return AnyView(
                NativeActionButton(
                    title: model.buttonTitle(n.id, n.text), kind: actionKind(n.id),
                    disabled: model.disabled(n.id), identifier: n.id
                ) { model.press(n.id) })
        case "text":
            return AnyView(
                VStack(alignment: .leading, spacing: NativeStyle.rowGap) {
                    if !n.text.isEmpty { copy(n.text, nested: true) }
                    if !n.children.isEmpty { controls(n.children) }
                })
        case "step":
            return AnyView(
                VStack(alignment: .leading, spacing: NativeStyle.controlGap) {
                    if !n.text.isEmpty { copy(n.text) }
                    if !n.children.isEmpty { controls(n.children) }
                })
        case "status":
            let t = model.text(n.id)
            return AnyView(
                VStack(alignment: .leading, spacing: NativeStyle.controlGap) {
                    if !t.isEmpty { bodyText(t).foregroundStyle(NativePalette.muted) }
                    NativeTaskProgress(tasks: model.tasks.at([n.id]))
                    if n.id == "updt" && model.major == 15 && model.eligibility == nil
                        && model.goodPackage == nil
                    {
                        HStack(spacing: NativeStyle.controlGap) {
                            Text("需要驱动包：")
                            Button("下载驱动包") { model.press("dl3") }.buttonStyle(.bordered)
                        }
                    }
                }.id(n.id))
        case "pageHeader":
            return AnyView(
                VStack(alignment: .leading, spacing: NativeStyle.controlGap) {
                    ForEach(n.children, id: \.key) { child in
                        if child.kind == "title" {
                            render(child)
                        } else {
                            render(child).foregroundStyle(NativePalette.muted)
                        }
                    }
                })
        case "overview":
            return AnyView(
                panel {
                    machineTable
                    NativeTaskProgress(tasks: model.tasks.at(["machine"]))
                    if !model.verdict.isEmpty {
                        Divider()
                        bodyText(model.verdict).foregroundStyle(NativePalette.muted)
                    }
                    if model.parkedDriver {
                        NativeActionButton(
                            title: "启用驱动", kind: .primary, disabled: model.busy,
                            identifier: "nvon") { model.press("nvon") }
                        NativeTaskProgress(tasks: model.tasks.at(["nvon"]))
                    }
                })
        case "checkPanel": return AnyView(panel { children(n) })
        case "resultsPanel":
            return AnyView(
                Group {
                    if model.checkingEFI || !model.text("efichkr").isEmpty || !model.issues.isEmpty {
                        panel { children(n) }
                    }
                })
        case "card": return AnyView(section(n).id(n.id))
        case "paired":
            let blocks = n.children.filter(isVisible)
            return AnyView(
                Group {
                    if blocks.contains(where: containsLongParagraph) {
                        VStack(alignment: .leading, spacing: NativeStyle.sectionGap) {
                            ForEach(blocks, id: \.key) { child in
                                render(child).frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                        }
                    } else {
                        HStack(alignment: .top, spacing: NativeStyle.sectionGap) {
                            ForEach(blocks, id: \.key) { child in
                                render(child).frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                        }
                    }
                })
        case "steps":
            return AnyView(
                VStack(alignment: .leading, spacing: NativeStyle.rowGap) {
                    ForEach(n.children, id: \.key) { c in
                        HStack(alignment: .firstTextBaseline, spacing: NativeStyle.controlGap) {
                            Text("\((n.children.firstIndex(where:{$0.key==c.key}) ?? 0)+1).").bold().frame(
                                width: 18, alignment: .leading)
                            render(c)
                        }
                    }
                })
        case "efiPicker":
            return AnyView(
                VStack(alignment: .leading, spacing: NativeStyle.rowGap) {
                    bodyText(n.text)
                    Picker("", selection: $model.efi) {
                        ForEach(model.candidates, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(maxWidth: 300)
                })
        case "verdict": return AnyView(Group { if !model.verdict.isEmpty { bodyText(model.verdict) } })
        case "machine": return AnyView(machineTable)
        case "issues": return AnyView(issueList)
        case "ports": return AnyView(usbTables)
        case "group":
            switch n.id {
            case "armreq": return AnyView(armRequestBanner)
            case "armprog": return AnyView(armProgress)
            case "armapps": return AnyView(armAppList)
            default: return AnyView(children(n))
            }
        default: return AnyView(children(n))
        }
    }
    var machineTable: some View {
        Grid(
            alignment: .leading, horizontalSpacing: NativeStyle.sectionGap,
            verticalSpacing: NativeStyle.controlGap
        ) {
            if model.machine.isEmpty {
                GridRow {
                    Text("正在查找…")
                    Text("请稍候")
                }
            } else {
                fact(
                    "macOS",
                    (model.machine["macos"] as? String ?? "")
                        + ([15, 26].contains(model.major) ? "" : "（驱动适用于 macOS 15 和 26）"))
                fact(
                    "处理器",
                    model.machine["arch"] as? String == "x86_64"
                        && model.machine["translated"] as? Bool != true
                        ? "x86_64" : "Apple 芯片，此驱动适用于 Intel Mac 和 PC")
                fact(
                    "显卡",
                    model.gpus.isEmpty
                        ? "未找到"
                        : model.gpus.map { g in
                            (g["name"] as? String ?? "")
                                + (g["supported"] as? Bool == true
                                    ? (g["tested"] as? Bool == true ? "（已列出且已测试）" : "（NVIDIA 已列出，型号尚未测试）")
                                    : g["vendor"] as? String == "10DE" ? "（不支持，需要 RTX 20 系列或更新）" : "")
                        }.joined(separator: "\n"))
                fact(
                    "OpenCore",
                    (model.machine["opencore"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                        ?? (model.machine["nativeMacPro"] as? Bool == true
                            ? "无需 OpenCore：Mac Pro (2019) 使用 Apple 固件（实验性，需要关闭 SIP）"
                            : "未检测到"))
                fact(
                    "已安装驱动包",
                    (model.machine["installedDriverVersion"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                        ?? "无版本记录")
                fact(
                    "NullMoth 驱动",
                    model.driverOn
                        ? "正在运行（\(model.metal.joined(separator:"、"))）"
                        : (model.machine["kexts"] as? Int ?? 0) >= 4
                            ? "已加载，尚无 NVIDIA Metal 设备"
                            : model.machine["files"] as? Bool == true ? "已安装，尚未运行" : "未安装")
            }
        }
    }
    func fact(_ key: String, _ value: String) -> some View {
        GridRow {
            Text(key).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(NativePalette.muted).frame(
                width: NativeStyle.labelWidth, alignment: .leading)
            bodyText(value)
        }
    }
    var issueList: some View {
        VStack(alignment: .leading, spacing: NativeStyle.rowGap) {
            ForEach(
                model.issues.map {
                    NativeRecord(key: $0["id"] as? String ?? $0["title"] as? String ?? "", value: $0)
                }
            ) { entry in
                let issue = entry.value
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: NativeStyle.rowGap) {
                        bodyText(
                            ZH.text(issue["what"] as? String ?? "")
                                + (issue["restart"] as? Bool == true ? " 下次重启后生效。" : ""))
                        if let now = issue["now"] as? [String], !now.isEmpty {
                            bodyText("本机当前值：" + now.joined(separator: " "))
                        }
                        ForEach(issue["steps"] as? [String] ?? [], id: \.self) { step in
                            bodyText(
                                "\(((issue["steps"] as? [String] ?? []).firstIndex(of:step) ?? 0)+1). "
                                    + ZH.text(step))
                        }
                    }.padding(.top, 8)
                } label: {
                    Text(ZH.text(issue["title"] as? String ?? "")).font(NativeStyle.sectionTitle)
                }.disclosureGroupStyle(NativeDisclosureStyle())
            }
            if !model.issues.isEmpty {
                bodyText("编辑 config.plist 前请保留副本。如果更改导致无法启动，请从 1401 启动 U 盘启动，并恢复该副本。")
            }
        }
    }
    var usbTables: some View {
        VStack(alignment: .leading, spacing: NativeStyle.sectionGap) {
            ForEach(
                model.controllers.map {
                    NativeRecord(key: $0["key"] as? String ?? $0["controller"] as? String ?? "", value: $0)
                }
            ) { entry in
                let c = entry.value
                let key = c["key"] as? String ?? c["controller"] as? String ?? ""
                VStack(alignment: .leading, spacing: NativeStyle.rowGap) {
                    Text(
                        "控制器 \(c["controller"] as? String ?? "")（\(c["vendor"] as? String ?? ""):\(c["device"] as? String ?? "")）— 已选 \(model.picks[key]?.count ?? 0) / 15"
                    ).lineLimit(nil).fixedSize(horizontal: false, vertical: true).fontWeight(.semibold)
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow {
                            Text("使用")
                            Text("端口")
                            Text("已检测")
                            Text("接口")
                            Text("当前设备")
                        }.foregroundStyle(NativePalette.muted)
                        ForEach(
                            (c["ports"] as? [[String: Any]] ?? []).map {
                                NativeRecord(key: $0["name"] as? String ?? "", value: $0)
                            }
                        ) { entry in
                            let p = entry.value
                            let name = p["name"] as? String ?? ""
                            GridRow {
                                Toggle(
                                    "",
                                    isOn: Binding(
                                        get: { model.picks[key]?[name] != nil },
                                        set: { on in
                                            if on {
                                                model.excluded.remove(key + "/" + name)
                                                model.picks[key, default: [:]][name] = model.connector(p)
                                            } else {
                                                model.excluded.insert(key + "/" + name)
                                                model.picks[key]?.removeValue(forKey: name)
                                            }
                                        })
                                ).labelsHidden()
                                Text(name + (p["usb3"] as? Bool == true ? " (USB 3)" : ""))
                                Text(model.seen[key, default: []].contains(name) ? "是" : "否").foregroundStyle(
                                    model.seen[key, default: []].contains(name) ? .green : .secondary)
                                Picker(
                                    "",
                                    selection: Binding(
                                        get: { model.picks[key]?[name] ?? model.connector(p) },
                                        set: {
                                            model.excluded.remove(key + "/" + name)
                                            model.picks[key, default: [:]][name] = $0
                                        })
                                ) {
                                    Text("USB 2 Type-A").tag(0)
                                    Text("USB 3 Type-A").tag(3)
                                    Text("USB-C 可翻转").tag(9)
                                    Text("USB-C 单方向").tag(10)
                                    Text("机箱内部").tag(255)
                                }.labelsHidden().frame(width: 145)
                                Text((p["devices"] as? [String] ?? []).joined(separator: "、"))
                                    .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: 190, alignment: .leading)
                            }
                        }
                    }
                }.padding(NativeStyle.panelInset).background(
                    .background, in: RoundedRectangle(cornerRadius: NativeStyle.cornerRadius))
            }
        }
    }
}

/// Packs whole sentence views onto each row using the width offered by their SwiftUI parent.
/// A sentence wider than the row receives a constrained proposal and can wrap at punctuation
/// clause boundaries inside its nested instance of this layout.
struct SemanticFlowLayout: Layout {
    static func rowGroups(for widths: [CGFloat], availableWidth: CGFloat) -> [[Int]] {
        let limit = max(0, availableWidth)
        var rows: [[Int]] = []
        var row: [Int] = []
        var rowWidth: CGFloat = 0
        for (index, width) in widths.enumerated() {
            if width > limit {
                if !row.isEmpty { rows.append(row); row = []; rowWidth = 0 }
                rows.append([index])
                continue
            }
            if !row.isEmpty && rowWidth + width > limit {
                rows.append(row)
                row = []
                rowWidth = 0
            }
            row.append(index)
            rowWidth += width
        }
        if !row.isEmpty { rows.append(row) }
        return rows
    }

    private func idealSizes(_ subviews: Subviews) -> [CGSize] {
        subviews.map { $0.sizeThatFits(.unspecified) }
    }

    private func constrainedSize(_ index: Int, _ sizes: [CGSize], _ width: CGFloat, _ subviews: Subviews) -> CGSize {
        sizes[index].width > width
            ? subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            : sizes[index]
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = idealSizes(subviews)
        let naturalWidth = sizes.reduce(CGFloat.zero) { $0 + $1.width }
        let width = max(0, proposal.width ?? naturalWidth)
        let rows = Self.rowGroups(for: sizes.map(\.width), availableWidth: width)
        var height: CGFloat = 0
        var measuredWidth: CGFloat = 0
        for (rowIndex, row) in rows.enumerated() {
            var rowHeight: CGFloat = 0
            var rowWidth: CGFloat = 0
            for index in row {
                let size = constrainedSize(index, sizes, width, subviews)
                rowHeight = max(rowHeight, size.height)
                rowWidth += size.width
            }
            height += rowHeight
            measuredWidth = max(measuredWidth, rowWidth)
            if rowIndex < rows.count - 1 { height += NativeStyle.lineGap }
        }
        return CGSize(width: proposal.width ?? measuredWidth, height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let sizes = idealSizes(subviews)
        let rows = Self.rowGroups(for: sizes.map(\.width), availableWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            var rowHeight: CGFloat = 0
            for index in row {
                let size = constrainedSize(index, sizes, bounds.width, subviews)
                subviews[index].place(
                    at: CGPoint(x: x, y: y), anchor: .topLeading,
                    proposal: ProposedViewSize(width: size.width, height: size.height))
                x += size.width
                rowHeight = max(rowHeight, size.height)
            }
            y += rowHeight + NativeStyle.lineGap
        }
    }
}
