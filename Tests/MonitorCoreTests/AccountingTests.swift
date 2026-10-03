import Foundation
import Testing
@testable import MonitorCore

private func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }

@Test func resetAtEightInChina() {
    let before = date("2026-10-03T07:59:00+08:00")
    let after = date("2026-10-03T08:00:00+08:00")
    #expect(UTCDay(containing: before).end == UTCDay(containing: after).start)
    #expect(UTCDay(containing: before).countdown(at: before) == "0 hours 1 minutes")
    #expect(UTCDay(containing: after).countdown(at: after) == "24 hours 0 minutes")
}

@Test func tenPercentInputThirtyPercentOutput() {
    let segments = AllowanceSegments(counts: TokenCounts(input: 100, output: 300), cap: 1_000)
    #expect(abs(segments.input - 0.1) < 0.0001)
    #expect(abs(segments.output - 0.3) < 0.0001)
    #expect(abs(segments.remaining - 0.6) < 0.0001)
}

@Test func overCapDoesNotProduceNegativeRemaining() {
    let segments = AllowanceSegments(counts: TokenCounts(input: 400, output: 800), cap: 1_000)
    #expect(segments.remaining == 0)
    #expect(abs(segments.input + segments.output - 1) < 0.0001)
    #expect(abs(segments.output / segments.input - 2) < 0.0001)
}

@Test func classifyOnlyExplicitTierMappings() {
    var config = MonitorConfiguration()
    let row = UsageRow(inputTokens: 10, outputTokens: 5, model: "large", serviceTier: "default")
    config.freeTier = ""
    config.paidTier = ""
    #expect(config.kind(of: row) == .unclassified)
    config.freeTier = "incentive"
    config.paidTier = "default"
    #expect(config.kind(of: row) == .paid)
    #expect(config.kind(of: UsageRow(inputTokens: 5, outputTokens: 5, model: "large", serviceTier: nil)) == .unclassified)
    #expect(config.kind(of: UsageRow(inputTokens: 5, outputTokens: 5, model: "large", serviceTier: "future_tier")) == .unclassified)
    config.paidTier = "incentive"
    #expect(!config.hasTierMapping)
    #expect(config.kind(of: row) == .unclassified)
}

@Test func researchedDefaultsNeedOnlyAdminKey() {
    let config = MonitorConfiguration()
    #expect(config.freeTier == "incentivized-tier")
    #expect(config.paidTier == "default")
    #expect(config.pools[0].cap == 250_000)
    #expect(config.pools[1].cap == 2_500_000)
    #expect(Set(config.pools[0].models).isDisjoint(with: Set(config.pools[1].models)))
    #expect(config.pools[0].models.contains("gpt-6-luna"))
    #expect(config.pools[1].models.contains("gpt-5.6-luna"))
}

@Test func automaticallyAssignsAliasesSnapshotsAndObservedSol() {
    let day = UTCDay(containing: .now)
    let rows = [
        UsageRow(inputTokens: 10, outputTokens: 30, model: "gpt-6_1-sol", serviceTier: "incentivized-tier"),
        UsageRow(inputTokens: 20, outputTokens: 60, model: "gpt-6-luna", serviceTier: "incentivized-tier"),
        UsageRow(inputTokens: 100, outputTokens: 300, model: "gpt-5.4-mini-2026-03-17", serviceTier: "incentivized-tier"),
        UsageRow(inputTokens: 1000, outputTokens: 3000, model: "unknown-model", serviceTier: "incentivized-tier")
    ]
    let snapshot = UsageSnapshot(fetchedAt: .now, buckets: [UsageBucket(startTime: day.start, endTime: day.end, results: rows)])
    let config = MonitorConfiguration()
    #expect(config.poolCounts(config.pools[0], snapshot: snapshot, day: day).total == 120)
    #expect(config.poolCounts(config.pools[1], snapshot: snapshot, day: day).total == 400)
    #expect(!config.isAssigned(rows[3]))
    #expect(ComplimentaryPolicy.isInferred("gpt-6_1-sol"))
    #expect(!ComplimentaryPolicy.isInferred("gpt-6-luna"))
}

@Test func poolsDoNotMixAndYesterdayIsExcluded() {
    let now = date("2026-10-03T09:00:00Z")
    let day = UTCDay(containing: now)
    var config = MonitorConfiguration()
    config.freeTier = "incentive"
    config.paidTier = "default"
    config.pools[0].models = ["large"]
    config.pools[1].models = ["small"]
    let rows = [
        UsageRow(inputTokens: 100, outputTokens: 300, model: "large", serviceTier: "incentive"),
        UsageRow(inputTokens: 200, outputTokens: 600, model: "small", serviceTier: "incentive"),
        UsageRow(inputTokens: 5, outputTokens: 7, model: "large", serviceTier: "default"),
        UsageRow(inputTokens: 1_000, outputTokens: 2_000, model: "unmapped", serviceTier: "incentive")
    ]
    let snapshot = UsageSnapshot(fetchedAt: now, buckets: [
        UsageBucket(startTime: day.start, endTime: day.end, results: rows),
        UsageBucket(startTime: day.start - 86_400, endTime: day.start, results: rows)
    ])
    #expect(config.poolCounts(config.pools[0], snapshot: snapshot, day: day) == TokenCounts(input: 100, output: 300))
    #expect(config.poolCounts(config.pools[1], snapshot: snapshot, day: day) == TokenCounts(input: 200, output: 600))
    #expect(snapshot.totals(on: day) { config.kind(of: $0) == .paid }.total == 12)
    #expect(snapshot.rows(on: UTCDay(containing: date("2026-10-04T00:01:00Z"))).isEmpty)
}

@Test func cachedInputIsNotAddedTwice() throws {
    let data = Data("""
    {"data":[{"start_time":1790985600,"end_time":1791072000,"results":[
      {"input_tokens":1000,"input_cached_tokens":400,"input_cache_write_tokens":75,
       "output_tokens":500,"model":"large","service_tier":"incentive"}
    ]}],"has_more":false,"next_page":null}
    """.utf8)
    let page = try JSONDecoder().decode(UsagePage.self, from: data)
    var counts = TokenCounts()
    counts.add(page.data[0].results[0])
    #expect(counts.total == 1500)
}
