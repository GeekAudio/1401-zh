import SwiftUI

/// Top-level destinations for the native app. The page renderer and action routing
/// continue to use each destination's stable upstream page ID.
struct NativeNavigation: View {
    @Binding var selection: String
    let issueCount: Int
    let activePages: Set<String>
    let reduceMotion: Bool
    let selectPage: (String) -> Void
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 3) {
            ForEach(NativeDestination.all) { destination in
                NativeNavigationItem(
                    destination: destination,
                    isSelected: selection == destination.id,
                    issueCount: destination.id == "efi" ? issueCount : 0,
                    isBusy: activePages.contains(destination.id),
                    namespace: selectionNamespace,
                    reduceMotion: reduceMotion
                ) {
                    selectPage(destination.id)
                }
            }
        }
        .padding(4)
        .background(NativePalette.soft, in: Capsule())
        .overlay(Capsule().strokeBorder(NativePalette.line, lineWidth: 1))
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct NativeNavigationItem: View {
    let destination: NativeDestination
    let isSelected: Bool
    let issueCount: Int
    let isBusy: Bool
    let namespace: Namespace.ID
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: destination.symbol)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .frame(width: 13)
                    .accessibilityHidden(true)
                Text(destination.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                if issueCount > 0 {
                    Text("\(issueCount)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(NativePalette.dangerSurface, in: Capsule())
                        .foregroundStyle(NativePalette.danger)
                }
                if isBusy {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.75)
                        .frame(width: 10, height: 10)
                        .accessibilityLabel(L10n.ui("后台任务进行中", "Background task in progress"))
                }
            }
            .foregroundStyle(isSelected ? NativePalette.ink : NativePalette.muted)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background {
                if isSelected {
                    let selectedSurface = Capsule()
                        .fill(NativePalette.card)
                        .overlay(Capsule().strokeBorder(NativePalette.line, lineWidth: 1))
                    if reduceMotion {
                        selectedSurface.transition(.opacity)
                    } else {
                        selectedSurface.matchedGeometryEffect(id: "selected-tab", in: namespace)
                    }
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(destination.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("page-" + destination.id)
    }
}
