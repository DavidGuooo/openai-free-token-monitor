import SwiftUI
import MonitorCore

struct AllowanceBar: View {
    let counts: TokenCounts
    let cap: Int

    var body: some View {
        let segments = AllowanceSegments(counts: counts, cap: cap)
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Color.blue.frame(width: geometry.size.width * segments.input)
                Color.purple.frame(width: geometry.size.width * segments.output)
                Color.secondary.opacity(0.14).frame(maxWidth: .infinity)
            }
        }
        .frame(height: 14)
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily free allowance")
        .accessibilityValue("Input \(percent(counts.input)), output \(percent(counts.output)), remaining \(percent(max(0, cap - counts.total)))")
    }

    private func percent(_ value: Int) -> String {
        (Double(value) / Double(max(1, cap))).formatted(.percent.precision(.fractionLength(0)))
    }
}
