import AppKit
import SwiftUI
import MonitorCore

struct MonitorPanel: View {
    @Bindable var store: MonitorStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { timeline in
            let day = UTCDay(containing: timeline.date)
            VStack(alignment: .leading, spacing: 14) {
                if store.isPreview {
                    Text("DEMO").font(.caption).foregroundStyle(.orange)
                }
                if store.hasKey || store.isPreview {
                    ForEach(store.configuration.pools) { pool in
                        allowance(pool, day: day)
                    }
                    Divider()
                    HStack {
                        Text("Paid tokens").font(.callout)
                        Spacer()
                        if let snapshot = store.currentSnapshot {
                            let paid = snapshot.totals(on: day) { store.configuration.kind(of: $0) == .paid }
                            Text(paid.total.formatted()).monospacedDigit().fontWeight(.medium)
                                .foregroundStyle(paid.total > 0 ? .orange : .primary)
                        } else { Text("—").foregroundStyle(.secondary) }
                    }
                    if let snapshot = store.currentSnapshot { coverageNotes(snapshot, day: day) }
                } else {
                    SettingsLink { Text("Add Admin key…") }.buttonStyle(.borderedProminent)
                }
                if let error = store.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                footer(day: day, now: timeline.date)
            }
            .padding(18)
            .frame(width: 350)
        }
    }

    private func allowance(_ pool: AllowancePool, day: UTCDay) -> some View {
        let counts = store.currentSnapshot.map { store.configuration.poolCounts(pool, snapshot: $0, day: day) }
        let cap = pool.cap ?? 1
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(pool.name).font(.callout).fontWeight(.medium)
                Spacer()
                Text("\(counts.map { $0.total.formatted() } ?? "—") / \(cap.formatted())")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    .help("Published Tier 1 allowance. GPT-6.1 Sol’s larger-pool assignment is inferred; its pool is not published. Reporting may lag.")
            }
            if let counts {
                AllowanceBar(counts: counts, cap: cap)
                HStack(spacing: 16) {
                    tokenLabel("Input", count: counts.input, cap: cap, color: .blue)
                        .frame(width: 88, alignment: .leading)
                    tokenLabel("Output", count: counts.output, cap: cap, color: .purple)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if counts.total > cap {
                    Text("Above estimated allowance").font(.caption2).foregroundStyle(.orange)
                }
            } else {
                Capsule().fill(.secondary.opacity(0.14)).frame(height: 10)
                Text(store.isRefreshing ? "Updating…" : "Waiting for usage")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func tokenLabel(_ title: String, count: Int, cap: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(title)
            Text((Double(count) / Double(cap)).formatted(.percent.precision(.fractionLength(0))))
                .foregroundStyle(.secondary)
        }.font(.caption2).monospacedDigit()
            .help("\(title): \(count.formatted()) tokens")
    }

    @ViewBuilder private func coverageNotes(_ snapshot: UsageSnapshot, day: UTCDay) -> some View {
        let unknown = snapshot.totals(on: day) { store.configuration.kind(of: $0) == .unclassified }.total
        let unmapped = snapshot.totals(on: day) {
            store.configuration.kind(of: $0) == .free && !store.configuration.isAssigned($0)
        }.total
        if unknown > 0 {
            Text("\(unknown.formatted()) tokens · unknown tier").font(.caption2).foregroundStyle(.orange)
        }
        if unmapped > 0 {
            Text("\(unmapped.formatted()) free tokens · unknown pool").font(.caption2).foregroundStyle(.orange)
        }
    }

    private func footer(day: UTCDay, now: Date) -> some View {
        HStack(spacing: 10) {
            if store.hasKey || store.isPreview {
                Text("Resets in \(day.countdown(at: now))")
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer()
            Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .disabled(store.isRefreshing || !store.hasKey)
                .help("Refresh").accessibilityLabel("Refresh usage")
            SettingsLink { Image(systemName: "key") }.help("Admin key").accessibilityLabel("Admin key")
            Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }
                .help("Quit").accessibilityLabel("Quit Free Token Monitor")
        }.buttonStyle(.borderless)
    }
}
