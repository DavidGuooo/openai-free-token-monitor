import Foundation
import MonitorCore

final class UsageSession: NSObject, URLSessionTaskDelegate, Sendable {
    // Fixed origin, ephemeral session, and no redirects: never forward the Admin
    // credential to another URL or retain it in a disk-backed HTTP cache.
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    static func client() -> UsageClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: UsageSession(), delegateQueue: nil)
        return UsageClient { request in
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw UsageError.invalidResponse }
            return (data, http)
        }
    }
}
