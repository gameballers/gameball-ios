//
//  GameballLogger.swift
//  Gameball
//

import Foundation
import UIKit

/// Fail-silent SDK telemetry logger. Fires one diagnostic entry per call directly to
/// api/v4.0/integrations/mobile/logs (forwarded to Datadog). The payload is sent as-is, immediately
/// and fire-and-forget; this layer must never throw into, or block, the host app.
final class GameballLogger {

    static let shared = GameballLogger()

    private let queue = DispatchQueue(label: "com.gameball.sdk.logger", qos: .utility)
    private lazy var deviceContext: [String: Any] = buildContext()

    private init() {}

    /// Fire one SDK event immediately. Safe from any thread; never throws. `params` is sent as-is.
    func log(_ event: String, params: [String: Any]? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }
            var entry: [String: Any] = [
                "event": event,
                "timestamp": Int(Date().timeIntervalSince1970 * 1000)
            ]
            if let params = params { entry["params"] = params }

            let body: [String: Any] = ["context": self.deviceContext, "logs": [entry]]
            NetworkManager.shared().sendLogs(body: body)
        }
    }

    private func buildContext() -> [String: Any] {
        return [
            "sdkType": "ios",
            "sdkVersion": SDKInfo.version,
            "devicePlatform": "iOS",
            "deviceOsVersion": UIDevice.current.systemVersion,
            "deviceModel": GameballLogger.deviceModelIdentifier(),
            "appBundleId": Bundle.main.bundleIdentifier ?? "",
            "installId": GameballLogger.installId()
        ]
    }

    // MARK: - Helpers

    /// Persisted per-install UUID, generated on first access. Correlates a device's calls in telemetry.
    static func installId() -> String {
        let key = UserDefaultsKeys.installId.rawValue
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }

    /// Hardware model identifier, e.g. "iPhone15,3".
    static func deviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = Mirror(reflecting: systemInfo.machine).children.reduce(into: "") { result, element in
            if let value = element.value as? Int8, value != 0 {
                result.append(Character(UnicodeScalar(UInt8(value))))
            }
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }

    /// Encodes a Codable request to a JSON dictionary (best-effort; nil on failure).
    static func dict<T: Encodable>(_ value: T) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(value),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    /// Builds a dictionary from optional values, omitting nils (safe for JSONSerialization).
    static func compact(_ dict: [String: Any?]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (key, value) in dict {
            if let value = value { out[key] = value }
        }
        return out
    }
}
