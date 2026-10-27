import SwiftUI

struct NativeTaskProgress: View {
    let tasks: [NativeTask]

    var body: some View {
        ForEach(tasks) { task in
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: NativeStyle.controlGap) {
                    Text(task.title).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if !task.amount.isEmpty { Text(task.amount).monospacedDigit() }
                    if let fraction = task.fraction {
                        Text(fraction, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                    }
                }
                .font(NativeStyle.caption)
                .foregroundStyle(NativePalette.muted)
                ProgressView(value: task.fraction)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .accessibilityLabel(task.title)
                    .accessibilityValue(task.fraction.map { String(format: "%.0f%%", $0 * 100) } ?? "进行中")
                    .accessibilityIdentifier("progress-" + task.id)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
