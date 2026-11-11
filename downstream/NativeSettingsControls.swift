import SwiftUI

struct NativeCardApplication: Identifiable, Equatable {
    let id: UUID
    var name: String
    var card: Int

    init(id: UUID = UUID(), name: String, card: Int) {
        self.id = id
        self.name = name
        self.card = card
    }

    static func == (lhs: NativeCardApplication, rhs: NativeCardApplication) -> Bool {
        lhs.name == rhs.name && lhs.card == rhs.card
    }
}

struct NativeCardSelection: Equatable {
    var defaultCard: Int?
    var applications: [NativeCardApplication]
}

enum NativeSettingsControlValues {
    static func framebufferMask(_ value: String) -> Int {
        guard let mask = Int(value), (0...255).contains(mask) else { return 0 }
        return mask
    }

    static func framebufferSelected(_ index: Int, in value: String) -> Bool {
        guard (0..<8).contains(index) else { return false }
        return framebufferMask(value) & (1 << index) != 0
    }

    static func settingFramebuffer(_ index: Int, selected: Bool, in value: String) -> String {
        guard (0..<8).contains(index) else { return value }
        var mask = framebufferMask(value)
        if selected { mask |= 1 << index } else { mask &= ~(1 << index) }
        return mask == 0 ? "default" : String(mask)
    }

    static func cardSelection(_ value: String) -> NativeCardSelection {
        if value == "default" { return NativeCardSelection(defaultCard: nil, applications: []) }
        if let card = cardNumber(value) { return NativeCardSelection(defaultCard: card, applications: []) }
        var selection = NativeCardSelection(defaultCard: nil, applications: [])
        for entry in value.split(separator: ",", omittingEmptySubsequences: false) {
            let pair = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard pair.count == 2, let card = cardNumber(pair[1]) else { continue }
            if pair[0] == "*" { selection.defaultCard = card }
            else if !pair[0].isEmpty { selection.applications.append(NativeCardApplication(name: pair[0], card: card)) }
        }
        return selection
    }

    static func cardValue(defaultCard: Int?, applications: [NativeCardApplication]) -> String {
        var entries = applications.compactMap { app -> String? in
            guard !app.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  (0...7).contains(app.card) else { return nil }
            return app.name.trimmingCharacters(in: .whitespacesAndNewlines) + "=" + String(app.card)
        }
        if let card = defaultCard, (0...7).contains(card) {
            if entries.isEmpty { return String(card) }
            entries.append("*=" + String(card))
        }
        return entries.isEmpty ? "default" : entries.joined(separator: ",")
    }

    private static func cardNumber(_ value: String) -> Int? {
        guard value.count == 1, let number = Int(value), (0...7).contains(number) else { return nil }
        return number
    }
}

/// The eight framebuffer bits form the mask consumed by DriverSettings.normalize.
struct NativeSurroundControl: View {
    @Binding var value: String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<8, id: \.self) { index in
                Toggle("\(index)", isOn: Binding(
                    get: { NativeSettingsControlValues.framebufferSelected(index, in: value) },
                    set: { value = NativeSettingsControlValues.settingFramebuffer(index, selected: $0, in: value) }
                ))
                .toggleStyle(.checkbox)
                .accessibilityLabel(L10n.ui("显示器帧缓冲 \(index)", "Display framebuffer \(index)"))
            }
        }
    }
}

/// A structured editor for the global and per-application NVMTL_CARD mappings.
struct NativeCardControl: View {
    @Binding var value: String
    let gpuCount: Int
    @State private var defaultCard: Int?
    @State private var applications: [NativeCardApplication] = []
    @State private var lastWrittenValue: String?

    init(value: Binding<String>, gpuCount: Int) {
        _value = value
        self.gpuCount = gpuCount
        let initial = NativeSettingsControlValues.cardSelection(value.wrappedValue)
        _defaultCard = State(initialValue: initial.defaultCard)
        _applications = State(initialValue: initial.applications)
    }

    private var detectedGPUCount: Int { max(1, min(8, gpuCount)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Toggle(L10n.ui("其余应用使用显卡", "Use this GPU for other apps"), isOn: Binding(
                    get: { defaultCard != nil },
                    set: { enabled in
                        if enabled { if defaultCard == nil { defaultCard = 0 } }
                        else { defaultCard = nil }
                        writeValue()
                    }
                ))
                .toggleStyle(.checkbox)
                Picker(L10n.ui("默认显卡", "Default GPU"), selection: Binding(
                    get: { defaultCard ?? 0 },
                    set: { defaultCard = $0; writeValue() }
                )) {
                    ForEach(0..<8, id: \.self) { card in
                        Text(card == 0 ? L10n.ui("0（主卡）", "0 (primary)") : String(card)).tag(card)
                    }
                }
                .frame(width: 125)
                .disabled(defaultCard == nil)
            }

            ForEach(applications) { application in
                HStack(spacing: 6) {
                    TextField(L10n.ui("应用可执行文件名", "Application executable name"), text: applicationName(application.id))
                    .textFieldStyle(.roundedBorder)
                    Picker(L10n.ui("应用显卡", "Application GPU"), selection: applicationCard(application.id)) {
                        ForEach(0..<8, id: \.self) { card in
                            Text(card == 0 ? L10n.ui("0（主卡）", "0 (primary)") : String(card)).tag(card)
                        }
                    }
                    .frame(width: 115)
                    Button(L10n.ui("移除", "Remove")) { removeApplication(application.id) }
                }
            }

            Button(L10n.ui("添加应用", "Add Application")) { applications.append(NativeCardApplication(name: "", card: 1)) }
            Text(L10n.ui(
                "检测到 \(detectedGPUCount) 张 NVIDIA 显卡。编号范围为 0–7；第 1 张以后的显卡需要先开启多显卡并重启。",
                "Detected \(detectedGPUCount) NVIDIA GPU(s). Valid indices are 0–7. GPUs after the first require multi-GPU support and a restart."
            ))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: value) { _, newValue in
            guard newValue != lastWrittenValue else { lastWrittenValue = nil; return }
            readValue(newValue)
        }
    }

    private func readValue(_ source: String) {
        let selection = NativeSettingsControlValues.cardSelection(source)
        defaultCard = selection.defaultCard
        var previous = applications
        applications = selection.applications.map { next in
            if let index = previous.firstIndex(where: { $0.name == next.name && $0.card == next.card }) {
                return previous.remove(at: index)
            }
            return next
        }
        lastWrittenValue = nil
    }

    private func writeValue() {
        let encoded = NativeSettingsControlValues.cardValue(defaultCard: defaultCard, applications: applications)
        lastWrittenValue = encoded
        value = encoded
    }

    private func applicationName(_ id: UUID) -> Binding<String> {
        Binding(
            get: { applications.first(where: { $0.id == id })?.name ?? "" },
            set: { name in
                guard let index = applications.firstIndex(where: { $0.id == id }) else { return }
                applications[index].name = name
                writeValue()
            }
        )
    }

    private func applicationCard(_ id: UUID) -> Binding<Int> {
        Binding(
            get: { applications.first(where: { $0.id == id })?.card ?? 0 },
            set: { card in
                guard let index = applications.firstIndex(where: { $0.id == id }) else { return }
                applications[index].card = card
                writeValue()
            }
        )
    }

    private func removeApplication(_ id: UUID) {
        applications.removeAll { $0.id == id }
        writeValue()
    }
}
