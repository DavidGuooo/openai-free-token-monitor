import Foundation

public struct AllowancePool: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var cap: Int?
    public var models: [String]

    public init(id: String, name: String, cap: Int? = nil, models: [String] = []) {
        self.id = id
        self.name = name
        self.cap = cap
        self.models = models
    }
}

public enum UsageKind: Sendable { case free, paid, unclassified }

public struct MonitorConfiguration: Codable, Equatable, Sendable {
    // Exact raw API values verified against this account's dashboard on 2026-10-03.
    public var freeTier = "incentivized-tier"
    public var paidTier = "default"
    public var refreshMinutes = 5
    public var pools = [
        AllowancePool(id: "larger", name: "Larger models", cap: ComplimentaryPolicy.largerCap,
                      models: ComplimentaryPolicy.largerModels),
        AllowancePool(id: "smaller", name: "Smaller models", cap: ComplimentaryPolicy.smallerCap,
                      models: ComplimentaryPolicy.smallerModels)
    ]

    public init() {}

    public var hasTierMapping: Bool {
        !freeTier.isEmpty && !paidTier.isEmpty && freeTier != paidTier
    }

    public func kind(of row: UsageRow) -> UsageKind {
        // Never classify an absent or unfamiliar tier as free or paid.
        guard hasTierMapping, let tier = row.serviceTier else { return .unclassified }
        if tier == freeTier { return .free }
        if tier == paidTier { return .paid }
        return .unclassified
    }

    public func poolCounts(_ pool: AllowancePool, snapshot: UsageSnapshot, day: UTCDay) -> TokenCounts {
        let models = Set(pool.models.map(ComplimentaryPolicy.canonicalModel))
        return snapshot.totals(on: day) { row in
            kind(of: row) == .free && row.model.map { models.contains(ComplimentaryPolicy.canonicalModel($0)) } == true
        }
    }

    public func isAssigned(_ row: UsageRow) -> Bool {
        guard let model = row.model else { return false }
        return pools.flatMap(\.models).contains {
            ComplimentaryPolicy.canonicalModel($0) == ComplimentaryPolicy.canonicalModel(model)
        }
    }
}

public struct AllowanceSegments: Equatable, Sendable {
    public let input: Double
    public let output: Double
    public let remaining: Double

    public init(counts: TokenCounts, cap: Int) {
        // When observed usage exceeds a configured cap, keep the two colors in
        // proportion and fill the bar. Numeric labels still show the true overage.
        let denominator = Double(max(1, max(cap, counts.total)))
        input = Double(counts.input) / denominator
        output = Double(counts.output) / denominator
        remaining = cap > counts.total ? Double(cap - counts.total) / denominator : 0
    }
}
