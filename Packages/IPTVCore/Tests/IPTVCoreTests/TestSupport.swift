import Foundation
import Testing
import Synchronization
@testable import IPTVCore

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

func stream(
    _ id: Int, _ number: Int, _ name: String, category: String? = "1", icon: String? = nil, epg: String? = nil
) -> LiveStream {
    LiveStream(
        id: id, number: number, name: name, categoryID: category,
        iconURL: icon.flatMap { URL(string: $0) }, epgChannelID: epg
    )
}

/// URLProtocol that answers from a handler registered per host, so tests can run in parallel
/// by using different hosts. Never touches the network.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    private static let handlers = Mutex<[String: Handler]>([:])

    static func register(host: String, _ handler: @escaping Handler) {
        handlers.withLock { $0[host] = handler }
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let host = request.url?.host(), let handler = Self.handlers.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            if (300...399).contains(response.statusCode),
               let location = response.value(forHTTPHeaderField: "Location"),
               let target = URL(string: location, relativeTo: request.url)?.absoluteURL {
                // Like a real server: the session asks its delegate whether to follow, and if it does,
                // loads the target through this protocol (and that host's handler) again.
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
