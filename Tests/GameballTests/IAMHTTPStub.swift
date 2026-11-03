//
//  IAMHTTPStub.swift
//  GameballTests
//
//  A `URLProtocol` that answers every request from a handler, so transport tests never
//  touch the network.
//

import Foundation
@testable import Gameball

final class IAMHTTPStub: URLProtocol {

    struct Reply {
        var status: Int?
        var body: Data?
        var error: Error?

        static func status(_ code: Int, body: Data? = Data("{}".utf8)) -> Reply {
            return Reply(status: code, body: body, error: nil)
        }

        static func transportError() -> Reply {
            return Reply(status: nil, body: nil,
                         error: NSError(domain: NSURLErrorDomain,
                                        code: NSURLErrorNotConnectedToInternet,
                                        userInfo: nil))
        }
    }

    /// Replies are consumed in order; the last one repeats once exhausted.
    static var replies: [Reply] = []
    static var requests: [URLRequest] = []
    static var bodies: [Data?] = []

    static func reset() {
        replies = []
        requests = []
        bodies = []
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IAMHTTPStub.self]
        return URLSession(configuration: configuration)
    }

    static var lastRequest: URLRequest? { return requests.last }

    static func lastBodyJSON() -> [String: Any]? {
        guard let data = bodies.last ?? nil else { return nil }
        return (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any]
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { return true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { return request }

    override func startLoading() {
        // `URLSession` converts an assigned httpBody into a stream before the protocol sees
        // it, so the stream is the only reliable place to read the payload back from.
        IAMHTTPStub.requests.append(request)
        IAMHTTPStub.bodies.append(IAMHTTPStub.readBody(from: request))

        let reply: IAMHTTPStub.Reply
        if IAMHTTPStub.replies.count > 1 {
            reply = IAMHTTPStub.replies.removeFirst()
        } else {
            reply = IAMHTTPStub.replies.first ?? .status(200)
        }

        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        if let status = reply.status,
           let url = request.url,
           let response = HTTPURLResponse(url: url, statusCode: status,
                                          httpVersion: "HTTP/1.1", headerFields: nil) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        if let body = reply.body {
            client?.urlProtocol(self, didLoad: body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let capacity = 4096
        var buffer = [UInt8](repeating: 0, count: capacity)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: capacity)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// Captures `iamLog` output for the duration of a block, so "logged loudly" can be
/// asserted rather than assumed.
func capturingIAMLog(_ body: () -> Void) -> [String] {
    var lines: [String] = []
    iamLogSink = { lines.append($0) }
    defer { iamLogSink = nil }
    body()
    return lines
}
