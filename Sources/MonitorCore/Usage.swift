import Foundation

public struct UsagePage: Decodable, Sendable {
    public let data: [UsageBucket]
    public let hasMore: Bool
    public let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data, hasMore = "has_more", nextPage = "next_page"
    }
}

public struct UsageBucket: Codable, Sendable {
    public let startTime: Int
    public let endTime: Int
    public let results: [UsageRow]

    public init(startTime: Int, endTime: Int, results: [UsageRow]) {
        self.startTime = startTime
        self.endTime = endTime
        self.results = results
    }

    enum CodingKeys: String, CodingKey {
        case startTime = "start_time", endTime = "end_time", results
    }
}

public struct UsageRow: Codable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let model: String?
    public let serviceTier: String?

    public init(inputTokens: Int, outputTokens: Int, model: String?, serviceTier: String?) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.model = model
        self.serviceTier = serviceTier
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens", outputTokens = "output_tokens"
        case model, serviceTier = "service_tier"
    }
}

public struct TokenCounts: Equatable, Sendable {
    public var input = 0
    public var output = 0
    public var total: Int { input + output }

    public init(input: Int = 0, output: Int = 0) {
        self.input = input
        self.output = output
    }

    public mutating func add(_ row: UsageRow) {
        // input_tokens already includes cached tokens. Never add cached fields again.
        input += row.inputTokens
        output += row.outputTokens
    }
}

public struct UTCDay: Equatable, Sendable {
    public let start: Int
    public var end: Int { start + 86_400 }

    public init(containing date: Date) {
        start = Int(floor(date.timeIntervalSince1970 / 86_400)) * 86_400
    }

    public func countdown(at date: Date) -> String {
        let minutes = max(0, Int(ceil((Double(end) - date.timeIntervalSince1970) / 60)))
        return "\(minutes / 60) hours \(minutes % 60) minutes"
    }
}

public struct UsageSnapshot: Codable, Sendable {
    public let fetchedAt: Date
    public let buckets: [UsageBucket]

    public init(fetchedAt: Date, buckets: [UsageBucket]) {
        self.fetchedAt = fetchedAt
        self.buckets = buckets
    }

    public func rows(on day: UTCDay) -> [UsageRow] {
        buckets.filter { $0.startTime == day.start }.flatMap(\.results)
    }

    public var observedTiers: [String] {
        Array(Set(buckets.flatMap(\.results).compactMap(\.serviceTier))).sorted()
    }

    public var observedModels: [String] {
        Array(Set(buckets.flatMap(\.results).compactMap(\.model))).sorted()
    }

    public func totals(on day: UTCDay, matching predicate: (UsageRow) -> Bool) -> TokenCounts {
        rows(on: day).filter(predicate).reduce(into: TokenCounts()) { $0.add($1) }
    }
}
