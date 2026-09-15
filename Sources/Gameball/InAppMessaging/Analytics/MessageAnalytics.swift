//
//  MessageAnalytics.swift
//  Gameball
//

import Foundation

/// Where a message's telemetry goes.
///
/// A protocol so a test can assert what was reported without a transport, and so a test
/// campaign can be wired to a sink that reports nothing.
protocol MessageAnalytics: AnyObject {
    /// Reads anything left undelivered by a previous launch.
    func load()
    /// Records an event. Must never block the caller — the caller is a view's `didPresent`.
    func log(_ event: MessageEvent)
    /// Sends what is pending, if anything, and if nothing is already in flight.
    func flush()
    /// Stops the timer and releases resources.
    func dispose()
}

/// Logs to the console and keeps events in memory. Used for `isTest` campaigns and in tests.
final class LoggingMessageAnalytics: MessageAnalytics {
    private(set) var events: [MessageEvent] = []
    private let silent: Bool

    init(silent: Bool = false) {
        self.silent = silent
    }

    func load() {}

    func log(_ event: MessageEvent) {
        events.append(event)
        if !silent {
            iamLog("event \(event.type.rawValue) for campaign \(event.campaignId) "
                 + "(not reported)")
        }
    }

    func flush() {}

    func dispose() {
        events.removeAll()
    }
}
