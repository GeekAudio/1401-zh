import AppKit
import SwiftUI

enum NativePalette {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
                return NSColor(
                    srgbRed: Double((value >> 16) & 255) / 255,
                    green: Double((value >> 8) & 255) / 255,
                    blue: Double(value & 255) / 255, alpha: 1)
            })
    }
    static let background = adaptive(0xF4F5F3, 0x1C221F)
    static let card = adaptive(0xFDFEFC, 0x252E29)
    static let soft = adaptive(0xECEFEB, 0x313D35)
    static let line = adaptive(0xDDE3DE, 0x3E4A42)
    static let ink = adaptive(0x34433D, 0xE1E9E3)
    static let muted = adaptive(0x65736A, 0xABB9AF)
    static let accent = adaptive(0x4F6F60, 0x9FBBAA)
    static let onAccent = adaptive(0xFFFFFF, 0x18271E)
    static let selection = adaptive(0xDCE6DE, 0x394D40)
    static let danger = adaptive(0x984F49, 0xE2AAA2)
    static let dangerSurface = adaptive(0xF2E7E4, 0x49332F)
}

enum NativeStyle {
    static let windowWidth: CGFloat = 820
    static let windowHeight: CGFloat = 600
    static let pageInset: CGFloat = 22
    static let labelWidth: CGFloat = 108
    static let sectionGap: CGFloat = 14
    static let panelInset: CGFloat = 16
    static let rowGap: CGFloat = 12
    static let controlGap: CGFloat = 8
    static let lineGap: CGFloat = 4
    static let cornerRadius: CGFloat = 13
    static let body = Font.system(size: 12)
    static let title = Font.system(size: 23, weight: .semibold)
    static let taskTitle = Font.system(size: 15, weight: .semibold)
    static let sectionTitle = Font.system(size: 13, weight: .semibold)
    static let caption = Font.system(size: 11)
}

struct NativePanel<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: NativeStyle.rowGap) { content }
            .padding(NativeStyle.panelInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NativePalette.card, in: RoundedRectangle(cornerRadius: NativeStyle.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: NativeStyle.cornerRadius)
                    .strokeBorder(NativePalette.line, lineWidth: 1))
    }
}

struct NativeSoftButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let kind: NativeActionKind
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(
                kind == .primary
                    ? NativePalette.onAccent : kind == .destructive ? NativePalette.danger : NativePalette.ink
            )
            .background(
                kind == .primary
                    ? NativePalette.accent
                    : kind == .destructive ? NativePalette.dangerSurface : NativePalette.soft,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.7 : 1)
    }
}

struct NativeDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: NativeStyle.controlGap) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: NativeStyle.controlGap) {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(NativePalette.muted).frame(width: 12).accessibilityHidden(true)
                    configuration.label
                    Spacer(minLength: 0)
                }.contentShape(Rectangle()).padding(.vertical, 4)
            }.buttonStyle(.plain).accessibilityValue(configuration.isExpanded ? "已展开" : "已折叠")
            if configuration.isExpanded { configuration.content.padding(.leading, 20) }
        }
    }
}
