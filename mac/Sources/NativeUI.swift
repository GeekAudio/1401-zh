// Native macOS utility window with the original five destinations.
import AppKit
import SwiftUI

struct NativeRoot: View {
    @ObservedObject var model: NativeModel
    @AppStorage("theme") private var theme = "system"
    @Environment(\.colorScheme) private var colorScheme
    @State private var windowHeight = NativeStyle.windowHeight

    var body: some View {
        VStack(spacing: 0) {
            NativeHeader(
                isDark: colorScheme == .dark,
                toggleTheme: toggleTheme,
                selection: $model.selected, issueCount: model.issues.count,
                activePages: Set(model.tasks.active.map(\.page)))
            NativePageView(model: model)
            Divider()
            NativeFooter(version: model.machine["version"] as? String ?? "", action: model.press)
        }
        .font(NativeStyle.body)
        .foregroundStyle(NativePalette.ink).tint(NativePalette.accent)
        .background(NativePalette.background)
        .frame(width: NativeStyle.windowWidth, height: windowHeight)
        .onPreferenceChange(NativeLayoutHeightKey.self, perform: resizeWindow)
        .onAppear(perform: configureWindowSizing)
        .preferredColorScheme(theme == "dark" ? .dark : theme == "light" ? .light : nil)
        .environment(
            \.openURL,
            OpenURLAction { url in
                if url.scheme == "action", let id = url.host {
                    model.press(id)
                    return .handled
                }
                return .systemAction
            }
        )
        .onChange(of: model.selected) { _, page in if page != "usb" { model.perform("usbStop") } }
    }

    private func toggleTheme() {
        theme = colorScheme == .dark ? "light" : "dark"
    }

    private func configureWindowSizing() {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
        let minimum = NativeStyle.minimumWindowHeight
        let screenHeight = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        window.contentMinSize = NSSize(width: NativeStyle.windowWidth, height: minimum)
        window.contentMaxSize = NSSize(width: NativeStyle.windowWidth, height: max(minimum, screenHeight - 70))
    }

    private func resizeWindow(using heights: [String: CGFloat]) {
        guard let page = heights["page"], page > 0,
              let header = heights["header"], let footer = heights["footer"] else { return }

        let minimum = NativeStyle.minimumWindowHeight
        let window = NSApp.keyWindow ?? NSApp.windows.first
        let screenHeight = (window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        let maximum = max(minimum, screenHeight - 70)
        let desired = min(max(header + page + footer + 1, minimum), maximum)
        guard abs(desired - windowHeight) > 1 else { return }

        windowHeight = desired
        window?.contentMinSize = NSSize(width: NativeStyle.windowWidth, height: minimum)
        window?.contentMaxSize = NSSize(width: NativeStyle.windowWidth, height: maximum)
        window?.setContentSize(NSSize(width: NativeStyle.windowWidth, height: desired))
    }
}

struct NativeHeader: View {
    let isDark: Bool
    let toggleTheme: () -> Void
    @Binding var selection: String
    let issueCount: Int
    let activePages: Set<String>

    var body: some View {
        ZStack {
            HStack(spacing: 11) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("1401 中文版").font(.system(size: 14, weight: .semibold))
                    Text("NVIDIA 驱动管理").font(NativeStyle.caption).foregroundStyle(NativePalette.muted)
                }
                Spacer(minLength: 0)
                Button(action: toggleTheme) {
                    Image(systemName: isDark ? "sun.max" : "moon")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 30, height: 30)
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(NativePalette.muted)
                .background(NativePalette.soft, in: RoundedRectangle(cornerRadius: 9))
                .help("切换浅色与深色")
                .accessibilityLabel("切换浅色与深色")
                .accessibilityIdentifier("theme")
            }
            NativeNavigation(selection: $selection, issueCount: issueCount, activePages: activePages)
        }
        .padding(.horizontal, NativeStyle.pageInset)
        .padding(.vertical, 11)
        .reportNativeHeight("header")
    }
}

struct NativeFooter: View {
    let version: String
    let action: (String) -> Void

    var body: some View {
        HStack(spacing: NativeStyle.controlGap) {
            Text("驱动 \(version)").foregroundStyle(NativePalette.muted).monospacedDigit()
            Spacer(minLength: NativeStyle.rowGap)
            Button("源代码") { action("src") }
            Text("·").foregroundStyle(NativePalette.muted)
            Button("OpenCore 指南") { action("ocg") }
        }
        .font(NativeStyle.caption)
        .buttonStyle(.link)
        .padding(.horizontal, NativeStyle.pageInset)
        .padding(.vertical, NativeStyle.controlGap)
        .reportNativeHeight("footer")
    }
}
