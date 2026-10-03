import Foundation
import Observation
import MonitorCore

@MainActor @Observable
final class MonitorStore {
    // No editable quota/tier/model preferences. Defaults use researched policy
    // and this account's verified API classification; old manual settings are ignored.
    let configuration = MonitorConfiguration()
    private(set) var snapshot: UsageSnapshot?
    private(set) var isRefreshing = false
    private(set) var hasKey = false
    private(set) var errorMessage: String?
    private(set) var nextRefresh: Date = .now
    let isPreview: Bool
    @ObservationIgnored private let client: UsageClient
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastAttemptDay: UTCDay?

    init(preview: Bool = false) {
        isPreview = preview
        client = UsageSession.client()
        if preview {
            let day = UTCDay(containing: .now)
            snapshot = UsageSnapshot(fetchedAt: .now, buckets: [UsageBucket(
                startTime: day.start, endTime: day.end, results: [
                    UsageRow(inputTokens: 25_000, outputTokens: 75_000,
                             model: "gpt-6-sol", serviceTier: "incentivized-tier"),
                    UsageRow(inputTokens: 250_000, outputTokens: 750_000,
                             model: "gpt-5.4-mini", serviceTier: "incentivized-tier"),
                    UsageRow(inputTokens: 1_500, outputTokens: 750,
                             model: "gpt-6-sol", serviceTier: "default")
                ])])
            return
        }
        do { hasKey = try AdminKeyStore.load() != nil }
        catch { errorMessage = error.localizedDescription }
        // App-owned task continues while the popup is closed.
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.hasKey && (Date.now >= self.nextRefresh || self.lastAttemptDay != UTCDay(containing: .now)) {
                    await self.refresh()
                }
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    var currentSnapshot: UsageSnapshot? {
        guard let snapshot, UTCDay(containing: snapshot.fetchedAt) == UTCDay(containing: .now) else { return nil }
        return snapshot
    }

    func refresh() async {
        guard !isPreview, !isRefreshing else { return }
        isRefreshing = true
        lastAttemptDay = UTCDay(containing: .now)
        let requestGeneration = generation
        var retrySoon = false
        defer {
            isRefreshing = false
            nextRefresh = Date.now.addingTimeInterval(retrySoon ? 30 : Double(configuration.refreshMinutes) * 60)
        }
        do {
            guard let key = try AdminKeyStore.load() else {
                hasKey = false
                throw UsageError.missingKey
            }
            let result = try await client.snapshot(key: key)
            guard requestGeneration == generation else { return }
            snapshot = result
            errorMessage = nil
        } catch {
            guard requestGeneration == generation else { return }
            if let usage = error as? UsageError {
                errorMessage = usage.localizedDescription
                retrySoon = usage.shouldRetrySoon
            }
            else if let keychain = error as? KeychainError { errorMessage = keychain.localizedDescription }
            else { errorMessage = "Usage refresh failed. Try refreshing again." }
        }
    }

    func saveKey(_ value: String) throws {
        guard !isPreview else { return }
        try AdminKeyStore.save(value)
        generation += 1
        hasKey = true
        snapshot = nil
        errorMessage = nil
        nextRefresh = .now
        Task { await refresh() }
    }
}
