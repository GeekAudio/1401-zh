import SwiftUI

enum NativeActionKind { case primary, secondary, link, destructive }

struct NativeActionButton: View {
    let title: String
    let kind: NativeActionKind
    let disabled: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        styledButton
            .controlSize(.regular)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minHeight: 30)
            .disabled(disabled)
            .accessibilityIdentifier(identifier)
    }

    private var label: some View {
        Text(title).frame(minWidth: kind == .link ? 0 : 76)
    }

    @ViewBuilder private var styledButton: some View {
        switch kind {
        case .primary:
            Button(action: action) { label }.buttonStyle(NativeSoftButtonStyle(kind: .primary))
        case .secondary:
            Button(action: action) { label }.buttonStyle(NativeSoftButtonStyle(kind: .secondary))
        case .link:
            Button(action: action) { label }.buttonStyle(.link).foregroundStyle(NativePalette.accent)
        case .destructive:
            Button(role: .destructive, action: action) { label }.buttonStyle(
                NativeSoftButtonStyle(kind: .destructive))
        }
    }
}
