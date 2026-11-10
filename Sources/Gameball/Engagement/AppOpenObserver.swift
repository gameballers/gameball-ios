//
//  AppOpenObserver.swift
//  Gameball
//

import Foundation

/// One app-level open. `type` is cold for the first in this process, warm for a later one.
/// `fromTap` means a tap on a Gameball push brought the app up: a normal click, never influenced.
struct AppOpen: Equatable {
    let type: String
    let openedAt: Int64
    let fromTap: Bool

    init(type: String, openedAt: Int64, fromTap: Bool = false) {
        self.type = type
        self.openedAt = openedAt
        self.fromTap = fromTap
    }
}

/// Decides which foregrounds are app opens. Fed by the app-level `didBecomeActive` and
/// `didEnterBackground` notifications, so moving between screens and rotating never count.
/// A return within `sessionGapMillis` continues the last open, the same rule as an in-app
/// messaging session.
///
/// Foundation only, so it can be tested without an app. Safe from any thread.
final class AppOpenObserver {

    static let typeCold = "cold"
    static let typeWarm = "warm"

    /// In-app messaging's default session timeout, so both agree on what an open is.
    static let sessionGapMillis: Int64 = 30_000

    /// A tap only explains an open that follows within this time, e.g. not one hours later.
    static let tapToOpenMillis: Int64 = 60_000

    private let now: () -> Int64
    private let sessionGapMillis: Int64
    private let report: (AppOpen) -> Void
    private let lock = NSLock()

    private var started = false
    // Active, and not in the background since: covered for a moment (Notification Center, an alert) still counts
    private var inForeground = false
    private var backgroundedAt: Int64?
    private var tappedAt: Int64?

    init(now: @escaping () -> Int64 = currentTimeMillis,
         sessionGapMillis: Int64 = AppOpenObserver.sessionGapMillis,
         report: @escaping (AppOpen) -> Void) {
        self.now = now
        self.sessionGapMillis = sessionGapMillis
        self.report = report
    }

    /// A tap on a Gameball push. iOS hands it to the app before the open it causes, cold and warm.
    /// One made while the app is on screen (a banner, or Notification Center pulled over the app)
    /// opens nothing, so it marks nothing.
    func onTap() {
        lock.lock(); defer { lock.unlock() }
        if !inForeground { tappedAt = now() }
    }

    /// The app became active.
    func onForeground() {
        lock.lock()
        let open = foregrounded(at: now())
        lock.unlock()
        if let open = open { report(open) }
    }

    /// The app went to the background.
    func onBackground() {
        lock.lock(); defer { lock.unlock() }
        inForeground = false
        backgroundedAt = now()
    }

    // Every return uses up a pending tap, even one that isn't an open, so it can't mark a later one
    private func foregrounded(at: Int64) -> AppOpen? {
        // Active again without having gone to the background: Notification Center, Control Center
        // or a system alert covered the app for a moment. Not a return.
        if inForeground { return nil }
        let fromTap = tappedAt.map { (0...AppOpenObserver.tapToOpenMillis).contains(at - $0) } ?? false
        tappedAt = nil
        inForeground = true
        let away = backgroundedAt.map { at - $0 }
        backgroundedAt = nil
        if started, let away = away, away <= sessionGapMillis { return nil }
        let open = AppOpen(type: started ? AppOpenObserver.typeWarm : AppOpenObserver.typeCold,
                           openedAt: at, fromTap: fromTap)
        started = true
        return open
    }
}

/// Wall-clock milliseconds since 1970, the unit every engagement timestamp uses.
func currentTimeMillis() -> Int64 {
    return Int64((Date().timeIntervalSince1970 * 1000).rounded())
}
