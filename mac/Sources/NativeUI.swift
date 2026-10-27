// Fixed-size native macOS utility window with the original five destinations.
import SwiftUI

struct NativeRoot: View {
    @ObservedObject var model: NativeModel
    @AppStorage("theme") private var theme = "system"
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            NativeNavigation(
                selection: $model.selected, issueCount: model.issues.count,
                isDark: colorScheme == .dark, toggleTheme: toggleTheme)
            NativePageView(model: model)
            Divider()
            NativeFooter(version: model.machine["version"] as? String ?? "", action: model.press)
        }
        .font(NativeStyle.body)
        .foregroundStyle(NativePalette.ink).tint(NativePalette.accent)
        .background(NativePalette.background)
        .frame(width: NativeStyle.windowWidth, height: NativeStyle.windowHeight)
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
}

struct NativeNavigation: View {
    @Binding var selection: String
    let issueCount: Int
    let isDark: Bool
    let toggleTheme: () -> Void

    var body: some View {
        HStack(spacing: NativeStyle.controlGap) {
            ForEach(NativeDestination.all, id: \.id) { destination in
                Button {
                    selection = destination.id
                } label: {
                    HStack(spacing: 6) {
                        Text(destination.title)
                        if destination.id == "efi" && issueCount > 0 {
                            Text("\(issueCount)").font(NativeStyle.caption).monospacedDigit()
                        }
                    }
                    .font(.system(size: 12, weight: selection == destination.id ? .semibold : .regular))
                    .foregroundStyle(selection == destination.id ? NativePalette.ink : NativePalette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .background(
                        selection == destination.id ? NativePalette.selection : Color.clear,
                        in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == destination.id ? .isSelected : [])
                .accessibilityIdentifier("page-" + destination.id)
            }
            Spacer(minLength: 0)
            Button(action: toggleTheme) { Image(systemName: isDark ? "sun.max" : "moon") }
                .buttonStyle(.borderless)
                .frame(width: 28, height: 28)
                .help("切换浅色与深色")
                .accessibilityLabel("切换浅色与深色")
                .accessibilityIdentifier("theme")
        }
        .padding(.horizontal, NativeStyle.pageInset)
        .padding(.vertical, NativeStyle.controlGap)
        .overlay(alignment: .bottom) { NativePalette.line.frame(height: 1) }
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
    }
}
