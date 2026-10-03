import Foundation

public enum UsageError: LocalizedError, Sendable {
    case missingKey, unauthorized, forbidden, rateLimited, server(Int), invalidResponse, transport(Int)
    public var errorDescription: String? {
        switch self {
        case .missingKey: "Add an organization Admin key in Settings."
        case .unauthorized: "The Admin key was rejected. Check or replace it in Settings."
        case .forbidden: "This key cannot read organization usage. Use an Admin key with usage access."
        case .rateLimited: "OpenAI rate limited the refresh. The monitor will try again later."
        case .server(let status): "Usage refresh failed (HTTP \(status)). Try again later."
        case .invalidResponse: "OpenAI returned an unexpected usage response. Counts were not updated."
        case .transport(let code):
            switch code {
            case URLError.timedOut.rawValue: "OpenAI timed out. Retrying shortly."
            case URLError.networkConnectionLost.rawValue: "Connection interrupted. Retrying shortly."
            case URLError.notConnectedToInternet.rawValue: "Offline. Retrying shortly."
            case URLError.cannotFindHost.rawValue, URLError.dnsLookupFailed.rawValue: "OpenAI’s address could not be resolved. Retrying shortly."
            case URLError.cannotConnectToHost.rawValue: "Connection to OpenAI failed. Retrying shortly."
            case URLError.secureConnectionFailed.rawValue: "Secure connection to OpenAI failed. Retrying shortly."
            case URLError.serverCertificateUntrusted.rawValue, URLError.serverCertificateHasBadDate.rawValue,
                 URLError.serverCertificateHasUnknownRoot.rawValue, URLError.serverCertificateNotYetValid.rawValue:
                "OpenAI’s TLS certificate could not be verified. Check your network."
            default: "Usage connection failed (\(code))."
            }
        }
    }

    public var shouldRetrySoon: Bool {
        guard case .transport(let code) = self else { return false }
        return Self.isTransient(code)
    }

    static func isTransient(_ code: Int) -> Bool {
        [URLError.timedOut, .networkConnectionLost, .notConnectedToInternet,
         .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost, .secureConnectionFailed]
            .contains { $0.rawValue == code }
    }
}

public struct UsageClient: Sendable {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let fetch: Fetch
    private let retryDelay: @Sendable () async throws -> Void

    public init(retryDelay: @escaping @Sendable () async throws -> Void = {
        try await Task.sleep(for: .seconds(1))
    }, fetch: @escaping Fetch) {
        self.fetch = fetch
        self.retryDelay = retryDelay
    }

    private func fetchRecoveringConnection(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        for attempt in 0..<2 {
            do { return try await fetch(request) }
            catch {
                let failure = error as NSError
                guard failure.domain == NSURLErrorDomain else { throw error }
                if attempt == 0 && UsageError.isTransient(failure.code) {
                    try await retryDelay()
                    continue
                }
                // Never include localized transport descriptions or userInfo:
                // they can contain a URL, request details, or proxy credentials.
                throw UsageError.transport(failure.code)
            }
        }
        throw UsageError.invalidResponse
    }

    public func snapshot(key: String, now: Date = .now) async throws -> UsageSnapshot {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw UsageError.missingKey }
        let day = UTCDay(containing: now)
        var buckets: [UsageBucket] = []
        var page: String?
        var seenPages = Set<String>()
        repeat {
            var url = URLComponents(string: "https://api.openai.com/v1/organization/usage/completions")!
            url.queryItems = [
                URLQueryItem(name: "start_time", value: String(day.start - 6 * 86_400)),
                URLQueryItem(name: "end_time", value: String(Int(now.timeIntervalSince1970) + 1)),
                URLQueryItem(name: "bucket_width", value: "1d"),
                URLQueryItem(name: "limit", value: "7"),
                URLQueryItem(name: "group_by[]", value: "model"),
                URLQueryItem(name: "group_by[]", value: "service_tier")
            ]
            if let page { url.queryItems?.append(URLQueryItem(name: "page", value: page)) }
            var request = URLRequest(url: url.url!)
            request.timeoutInterval = 30
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await fetchRecoveringConnection(request)
            switch response.statusCode {
            case 200: break
            case 401: throw UsageError.unauthorized
            case 403: throw UsageError.forbidden
            case 429: throw UsageError.rateLimited
            default: throw UsageError.server(response.statusCode)
            }
            // Do not log raw response bodies: error responses can contain account details.
            guard let decoded = try? JSONDecoder().decode(UsagePage.self, from: data),
                  decoded.data.allSatisfy({ bucket in
                      bucket.startTime >= day.start - 6 * 86_400 && bucket.startTime < day.end &&
                      bucket.endTime > bucket.startTime && bucket.results.allSatisfy {
                          $0.inputTokens >= 0 && $0.outputTokens >= 0 &&
                          !$0.inputTokens.addingReportingOverflow($0.outputTokens).overflow
                      }
                  }) else { throw UsageError.invalidResponse }
            buckets.append(contentsOf: decoded.data)
            if decoded.hasMore {
                guard let next = decoded.nextPage, !next.isEmpty,
                      seenPages.insert(next).inserted, seenPages.count <= 100 else {
                    throw UsageError.invalidResponse
                }
                page = next
            } else {
                page = nil
            }
        } while page != nil
        // A duplicated day bucket would count a page twice; fail rather than invent totals.
        guard Set(buckets.map(\.startTime)).count == buckets.count else { throw UsageError.invalidResponse }
        var sum = 0
        for row in buckets.flatMap(\.results) {
            let next = sum.addingReportingOverflow(row.inputTokens + row.outputTokens)
            guard !next.overflow else { throw UsageError.invalidResponse }
            sum = next.partialValue
        }
        return UsageSnapshot(fetchedAt: now, buckets: buckets)
    }
}
