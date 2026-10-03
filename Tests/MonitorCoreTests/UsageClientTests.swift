import Foundation
import Testing
@testable import MonitorCore

private let now = ISO8601DateFormatter().date(from: "2026-10-03T09:00:00Z")!

private actor PagedAPI {
    var requests: [URLRequest] = []
    func fetch(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let day = UTCDay(containing: now)
        let second = requests.count == 2
        let start = second ? day.start : day.start - 86_400
        let body = """
        {"data":[{"start_time":\(start),"end_time":\(start + 86400),"results":[
          {"input_tokens":100,"output_tokens":300,"model":"example","service_tier":"free_example"}
        ]}],"has_more":\(!second),"next_page":\(second ? "null" : "\"next\"")}
        """
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@Test func fetchesAllPagesAndUsesOrganizationScope() async throws {
    let api = PagedAPI()
    let client = UsageClient { try await api.fetch($0) }
    let snapshot = try await client.snapshot(key: "fake-test-key", now: now)
    #expect(snapshot.rows(on: UTCDay(containing: now)).count == 1)
    #expect(snapshot.observedTiers == ["free_example"])
    let requests = await api.requests
    #expect(requests.count == 2)
    let query = URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)!.queryItems!
    #expect(query.filter { $0.name == "group_by[]" }.compactMap(\.value) == ["model", "service_tier"])
    #expect(!query.contains { $0.name.contains("project") || $0.name.contains("api_key") })
    #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer fake-test-key")
    #expect(URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)!.queryItems!.contains { $0.name == "page" && $0.value == "next" })
}

@Test(arguments: [401, 403, 429, 500]) func errorsDoNotExposeResponseBody(status: Int) async {
    let client = UsageClient { request in
        (Data("sensitive-error-body".utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    do {
        _ = try await client.snapshot(key: "fake-test-key", now: now)
        Issue.record("Expected an HTTP failure")
    } catch {
        #expect(!error.localizedDescription.contains("sensitive-error-body"))
        #expect(!error.localizedDescription.contains("fake-test-key"))
        if status == 403 { #expect(error.localizedDescription.contains("Admin key")) }
    }
}

@Test func rejectsMalformedAndNegativeCounts() async {
    for body in ["{}", """
    {"data":[{"start_time":\(UTCDay(containing: now).start),"end_time":\(UTCDay(containing: now).end),
      "results":[{"input_tokens":-1,"output_tokens":10}]}],"has_more":false,"next_page":null}
    """] {
        let client = UsageClient { request in
            (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        await #expect(throws: UsageError.self) { try await client.snapshot(key: "fake-test-key", now: now) }
    }
}

@Test func rejectsPaginationWithoutCursor() async {
    let client = UsageClient { request in
        (Data("{\"data\":[],\"has_more\":true,\"next_page\":null}".utf8),
         HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    await #expect(throws: UsageError.self) { try await client.snapshot(key: "fake-test-key", now: now) }
}

@Test func doesNotRequestWithoutKey() async {
    let client = UsageClient { _ in
        Issue.record("An empty key must not make a request")
        throw UsageError.invalidResponse
    }
    await #expect(throws: UsageError.self) { try await client.snapshot(key: "", now: now) }
}

private actor InterruptedAPI {
    let failures: Int
    let code: Int
    let status: Int
    var attempts = 0

    init(failures: Int, code: Int = URLError.networkConnectionLost.rawValue, status: Int = 200) {
        self.failures = failures
        self.code = code
        self.status = status
    }

    func fetch(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        attempts += 1
        if attempts <= failures {
            throw NSError(domain: NSURLErrorDomain, code: code,
                          userInfo: [NSLocalizedDescriptionKey: "secret-request-detail"])
        }
        return (Data("{\"data\":[],\"has_more\":false,\"next_page\":null}".utf8),
                HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@Test func recoversFromInterruptedConnection() async throws {
    let api = InterruptedAPI(failures: 1)
    let client = UsageClient(retryDelay: {}, fetch: { try await api.fetch($0) })
    let result = try await client.snapshot(key: "fake-test-key", now: now)
    #expect(result.buckets.isEmpty)
    #expect(await api.attempts == 2)
}

@Test func persistentNetworkFailureHasBoundedRetryAndSafeMessage() async {
    let api = InterruptedAPI(failures: 10, code: URLError.timedOut.rawValue)
    let client = UsageClient(retryDelay: {}, fetch: { try await api.fetch($0) })
    do {
        _ = try await client.snapshot(key: "fake-test-key", now: now)
        Issue.record("Expected a timeout")
    } catch let error as UsageError {
        #expect(error.localizedDescription.contains("timed out"))
        #expect(!error.localizedDescription.contains("secret-request-detail"))
        #expect(error.shouldRetrySoon)
    } catch { Issue.record("Expected a classified transport error") }
    #expect(await api.attempts == 2)
}

@Test func certificateFailureIsNotRetriedOrHidden() async {
    let api = InterruptedAPI(failures: 10, code: URLError.serverCertificateUntrusted.rawValue)
    let client = UsageClient(retryDelay: {}, fetch: { try await api.fetch($0) })
    do {
        _ = try await client.snapshot(key: "fake-test-key", now: now)
        Issue.record("Expected a certificate failure")
    } catch let error as UsageError {
        #expect(error.localizedDescription.contains("certificate"))
        #expect(!error.localizedDescription.contains("secret-request-detail"))
        #expect(!error.shouldRetrySoon)
    } catch { Issue.record("Expected a classified transport error") }
    #expect(await api.attempts == 1)
}

@Test func authenticationFailureIsNotRetried() async {
    let api = InterruptedAPI(failures: 0, status: 401)
    let client = UsageClient(retryDelay: {}, fetch: { try await api.fetch($0) })
    await #expect(throws: UsageError.self) { try await client.snapshot(key: "fake-test-key", now: now) }
    #expect(await api.attempts == 1)
}
