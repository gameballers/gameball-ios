//
//  HTTPMessageSource.swift
//  Gameball
//

import Foundation

/// Sync over the transport: builds the request body, hands the response to the parser.
///
/// Holds no state. Version and locale are injected rather than read from globals, so a test
/// can pin them and the orchestrator stays the only place that knows the environment.
final class HTTPMessageSource: MessageSource {
    private let transport: IAMTransport
    private let appVersion: String
    private let sdkVersion: String
    /// Resolved on every fetch, not once at construction: the source is built when
    /// messaging starts, which can be before `initializeCustomer` has written the customer's
    /// preferred language and before the host switches language mid-session. A value
    /// captured then asked for the wrong locale for the rest of the run.
    private let locale: () -> String

    init(transport: IAMTransport, appVersion: String, sdkVersion: String,
         locale: @escaping () -> String) {
        self.transport = transport
        self.appVersion = appVersion
        self.sdkVersion = sdkVersion
        self.locale = locale
    }

    /// A constant locale. For tests and for hosts that pin the language for the whole run.
    convenience init(transport: IAMTransport, appVersion: String, sdkVersion: String, locale: String) {
        self.init(transport: transport, appVersion: appVersion, sdkVersion: sdkVersion,
                  locale: { locale })
    }

    func fetch(customerId: String, completion: @escaping (Result<SyncResult, Error>) -> Void) {
        let body: [String: Any] = [
            "customerId": customerId,
            "locale": locale(),
            "appVersion": appVersion,
            "sdkVersion": sdkVersion
        ]

        transport.post(path: IAMEndpoint.sync, body: body) { outcome in
            switch outcome {
            case .success(let data):
                let result = MessageParser.parseSyncResponse(data)
                // An empty *parse* of a non-empty body means the payload was malformed.
                // Reporting that as a successful empty sync would clobber a good cache with
                // nothing, so it is a failure instead.
                if result.rawPayload == nil && !data.isEmpty {
                    iamLog("sync returned a body the parser could not read; keeping the cache")
                    completion(.failure(IAMSyncError.unreadablePayload))
                    return
                }
                completion(.success(result))

            case .permanentFailure(let status):
                completion(.failure(IAMSyncError.permanent(status: status)))

            case .retryableFailure(let status):
                completion(.failure(IAMSyncError.retryable(status: status)))
            }
        }
    }
}
