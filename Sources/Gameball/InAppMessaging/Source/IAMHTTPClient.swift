//
//  IAMHTTPClient.swift
//  Gameball
//

import Foundation

/// The iOS platform code the backend expects in every in-app messaging request body.
let iamPlatformCode = 1

/// The module's three endpoints, pinned to v4.0.
///
/// Pinned deliberately and permanently: `NetworkManager`'s `URLRequest` extension rewrites
/// `/events` and `/customers` to v4.1 whenever a session token is present, and v4.1 answers
/// 401 to APIKey authentication. Routing in-app messaging through that extension would make
/// the feature fail for exactly the customers who are signed in.
enum IAMEndpoint {
    static let sync      = "/api/v4.0/integrations/inapp-messages/sync"
    static let events    = "/api/v4.0/integrations/inapp-messages/events"
    static let variables = "/api/v4.0/integrations/inapp-messages/variables"
}

/// What came back, reduced to the only distinction the callers act on: is it worth trying
/// this again?
enum IAMHTTPOutcome {
    case success(Data)
    /// 4xx other than 408/429. Retrying cannot change the answer, so the payload is dropped.
    case permanentFailure(status: Int)
    /// 408, 429, 5xx, and transport errors. `nil` status means the request never got a reply.
    case retryableFailure(status: Int?)
}

/// The transport seam. Everything above it — sync, analytics, variables — is testable
/// without a network.
protocol IAMTransport: AnyObject {
    func post(path: String,
              body: [String: Any],
              completion: @escaping (IAMHTTPOutcome) -> Void)
}

/// `URLSession` transport for the three in-app messaging endpoints.
///
/// Builds its `URLRequest` by hand rather than reusing `NetworkManager`'s `URL` and
/// `URLRequest` extensions: those force-unwrap and carry the v4.1 switch described on
/// `IAMEndpoint`.
final class IAMHTTPClient: IAMTransport {
    private let session: URLSession
    private let baseURL: () -> String
    private let apiKey: () -> String
    private let language: () -> String

    /// Credentials arrive as closures so the client reads current SDK configuration at
    /// request time, rather than capturing a key that may not have been registered yet.
    init(session: URLSession = .shared,
         baseURL: @escaping () -> String = { APIEndPoints.base_URL },
         apiKey: @escaping () -> String,
         language: @escaping () -> String) {
        self.session = session
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.language = language
    }

    func post(path: String,
              body: [String: Any],
              completion: @escaping (IAMHTTPOutcome) -> Void) {
        // Scheme and host are checked explicitly. `URL(string:)` alone is not enough: it
        // accepts strings with spaces and no scheme, which then produce a request that can
        // never succeed rather than a failure we can report.
        guard let url = URL(string: baseURL() + path),
              url.scheme != nil, url.host != nil else {
            iamLog("could not build a usable URL from '\(baseURL())\(path)'; dropping the request")
            completion(.permanentFailure(status: 0))
            return
        }

        var payload = body
        if let declared = payload["platform"] as? Int {
            if declared != 1 && declared != 2 {
                iamLog("REQUEST CARRIES AN UNEXPECTED platform CODE \(declared); the backend "
                     + "will mis-attribute this. Expected 1 (iOS) or 2 (Android).")
            }
        } else {
            payload["platform"] = iamPlatformCode
        }

        // Checked before serialising, not caught after. `JSONSerialization.data` raises an
        // NSInvalidArgumentException for an unsupported value type, and an Objective-C
        // exception cannot be caught by a Swift `do`/`catch` — so a `try` here would take
        // the host process down with it. `isValidJSONObject` is the only safe gate.
        guard JSONSerialization.isValidJSONObject(payload) else {
            iamLog("request body for \(path) is not JSON-serialisable; dropping the request")
            completion(.permanentFailure(status: 0))
            return
        }

        let encoded: Data
        do {
            encoded = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            iamLog("could not serialise the request body for \(path): "
                 + "\(error.localizedDescription)")
            completion(.permanentFailure(status: 0))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = encoded
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey(), forHTTPHeaderField: "APIKey")
        request.setValue(SDKInfo.userAgent, forHTTPHeaderField: "x-gb-agent")
        request.setValue(language(), forHTTPHeaderField: "lang")

        session.dataTask(with: request) { data, response, error in
            completion(IAMHTTPClient.outcome(data: data, response: response,
                                             error: error, path: path))
        }.resume()
    }

    private static func outcome(data: Data?,
                                response: URLResponse?,
                                error: Error?,
                                path: String) -> IAMHTTPOutcome {
        if let error = error {
            iamLog("\(path) failed in transport: \(error.localizedDescription)")
            return .retryableFailure(status: nil)
        }

        guard let http = response as? HTTPURLResponse else {
            iamLog("\(path) came back without an HTTP response")
            return .retryableFailure(status: nil)
        }

        let status = http.statusCode

        if status >= 200 && status < 300 {
            return .success(data ?? Data())
        }

        if status == 408 || status == 429 || status >= 500 {
            iamLog("\(path) returned \(status); will retry")
            return .retryableFailure(status: status)
        }

        // A bodyless 404 means the endpoint is not deployed for this tenant, which is a
        // different conversation from a 404 that came back with an error document.
        if status == 404 && (data?.isEmpty ?? true) {
            iamLog("\(path) returned 404 with no body — the in-app messaging endpoints are "
                 + "most likely not deployed for this account")
        } else {
            iamLog("\(path) returned \(status); not retrying")
        }
        return .permanentFailure(status: status)
    }
}
