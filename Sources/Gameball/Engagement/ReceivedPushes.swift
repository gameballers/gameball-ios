//
//  ReceivedPushes.swift
//  Gameball
//

import Foundation

/// Received pushes on disk. They are written by the Notification Service Extension and read by
/// the app, two separate processes, so both must use the same App Group suite. Without an App
/// Group the app's standard defaults are used, which the extension can't reach.
///
/// Foundation only: this runs inside a Notification Service Extension.
final class ReceivedPushes: ReceivedPushStore {

    static let key = "gameballSDKReceivedPushes"

    private let defaults: UserDefaults

    init(appGroup: String?) {
        if let appGroup = appGroup, !appGroup.isEmpty, let suite = UserDefaults(suiteName: appGroup) {
            defaults = suite
        } else {
            defaults = .standard
        }
    }

    func load() -> [ReceivedPush] {
        guard let data = defaults.data(forKey: ReceivedPushes.key) else { return [] }
        do {
            return try JSONDecoder().decode([ReceivedPush].self, from: data)
        } catch {
            NSLog("GameballApp could not read received pushes: \(error)")
            return []
        }
    }

    func save(_ pushes: [ReceivedPush]) {
        if pushes.isEmpty {
            defaults.removeObject(forKey: ReceivedPushes.key)
        } else if let data = try? JSONEncoder().encode(pushes) {
            defaults.set(data, forKey: ReceivedPushes.key)
        }
        // The extension's process is often killed right after it hands the notification back
        defaults.synchronize()
    }
}
