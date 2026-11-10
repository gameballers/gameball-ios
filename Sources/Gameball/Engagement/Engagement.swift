//
//  Engagement.swift
//  Gameball
//

import Foundation
import UIKit

/// Engagement signals inside the app: app opens, push taps and influenced opens.
/// Push arrivals are recorded by the Notification Service Extension through
/// `GameballApp.handlePushReceived(_:appGroup:)`.
///
/// Taps and influenced opens are reported to the push-engagement endpoint; app opens and
/// arrivals are only logged for now.
final class Engagement {

    static let shared = Engagement()

    /// Sends one engagement with the given session token; one attempt, no retry.
    typealias Sender = (_ engagement: PushEngagement, _ sessionToken: String?, _ completion: ((Bool) -> Void)?) -> Void

    private let lock = NSLock()
    private let now: () -> Int64
    private let sessionToken: () -> String?
    private let send: Sender
    private var influencedOpens: InfluencedOpens
    private var started = false
    // Taps already handled in this process, so one tap that reaches the SDK twice counts once
    private var handledTaps = Set<String>()
    private var appOpens: AppOpenObserver!

    /// The app uses `shared`; tests drive an instance directly with their own store, clock and sender.
    /// `sessionToken` gives the token in use for reports the SDK makes on its own (an influenced open).
    init(store: ReceivedPushStore = ReceivedPushes(appGroup: nil),
         now: @escaping () -> Int64 = currentTimeMillis,
         sessionToken: @escaping () -> String? = { GameballApp.getInstance().currentSessionToken },
         send: @escaping Sender = { NetworkManager.shared().reportPushEngagement($0, sessionToken: $1, completion: $2) }) {
        self.now = now
        self.sessionToken = sessionToken
        self.send = send
        influencedOpens = InfluencedOpens(store: store, now: now)
        appOpens = AppOpenObserver(now: now) { [weak self] open in self?.onAppOpen(open) }
    }

    /// Points the saved pushes at the App Group the extension writes to, and starts watching
    /// app opens. Safe on every init.
    func start(appGroup: String?) {
        lock.lock()
        influencedOpens = InfluencedOpens(store: ReceivedPushes(appGroup: appGroup), now: now)
        let already = started
        started = true
        lock.unlock()
        guard !already else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let center = NotificationCenter.default
            // App-level notifications, posted for scene-based apps too: moving between screens,
            // rotating or opening another scene never posts them
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.appDidBecomeActive()
            }
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                self?.appDidEnterBackground()
            }
            // init ran after the app was already on screen: that first foreground is the cold open
            if Engagement.sharedApplication?.applicationState == .active {
                self.appDidBecomeActive()
            }
        }
    }

    /// `UIApplication.shared` without naming it, so this file still compiles when the module is
    /// built for an app extension (where `shared` is unavailable). Nil inside an extension.
    private static var sharedApplication: UIApplication? {
        let selector = NSSelectorFromString("sharedApplication")
        guard UIApplication.responds(to: selector) else { return nil }
        return UIApplication.perform(selector)?.takeUnretainedValue() as? UIApplication
    }

    /// The app became active.
    func appDidBecomeActive() {
        appOpens.onForeground()
    }

    /// The app went to the background.
    func appDidEnterBackground() {
        appOpens.onBackground()
    }

    /// A tap on a Gameball push, as `handlePushClick` hands it over. Returns false, doing nothing,
    /// when this tap was already handled in this process. Otherwise it's logged and, when the push
    /// carries a click token, reported as clicked; `completion` gets that report's result and isn't
    /// called without a token, as in 4.0.0.
    func onTap(_ push: GameballPush, sessionToken: String?, completion: ((Bool) -> Void)?) -> Bool {
        let tappedAt = now()
        lock.lock()
        let isNew = push.key.map { handledTaps.insert($0).inserted } ?? true
        let opens = influencedOpens
        lock.unlock()
        guard isNew else { return false }
        // A tapped push is a normal tap and never counts toward an influenced open
        if let key = push.key { opens.onTap(key: key) }
        // Nor does the open the tap causes, whatever else is saved
        appOpens.onTap()
        logEngagement("push_click", [("clickToken", push.clickToken)])
        if let token = push.clickToken {
            send(PushEngagement(clickToken: token, type: .clicked, occurredAt: tappedAt), sessionToken, completion)
        }
        return true
    }

    /// Another customer's pushes must never credit this customer's opens.
    func clearReceivedPushes() {
        currentInfluencedOpens().clear()
    }

    private func onAppOpen(_ open: AppOpen) {
        logEngagement("app_open", [("type", open.type), ("openedAt", open.openedAt), ("fromTap", open.fromTap)])
        // Not from a tap, and the most recent untapped push arrived within the window: it influenced this open
        if let push = currentInfluencedOpens().influencedBy(open) {
            logEngagement("influenced_open", [
                ("clickToken", push.clickToken),
                ("sentAt", push.sentAt),
                ("receivedAt", push.receivedAt),
                ("type", open.type),
                ("openedAt", open.openedAt)
            ])
            // Dated at the open, not at this check; a push without a token can't be reported
            if let token = push.clickToken {
                send(PushEngagement(clickToken: token, type: .influencedOpen, occurredAt: open.openedAt), sessionToken(), nil)
            }
        }
    }

    private func currentInfluencedOpens() -> InfluencedOpens {
        lock.lock(); defer { lock.unlock() }
        return influencedOpens
    }
}

// MARK: - Notification Service Extension

public extension GameballApp {

    /// Records a Gameball push as it reaches the device, so an app open that follows it without
    /// a tap can be credited to it (an influenced open).
    ///
    /// Call it from your Notification Service Extension's `didReceive(_:withContentHandler:)`
    /// with `request.content.userInfo`, then hand the notification back as usual. It never
    /// changes or delays the notification. Pass the same App Group you give the app in
    /// `GameballConfig(appGroup:)`; both the app and the extension must have it enabled.
    ///
    /// Returns true when the push is a Gameball one. Never throws.
    /// - Parameters:
    ///   - payload: The notification's `userInfo`.
    ///   - appGroup: The App Group shared by the app and the extension, e.g. "group.com.example.app".
    @discardableResult
    static func handlePushReceived(_ payload: [AnyHashable: Any], appGroup: String) -> Bool {
        guard let push = GameballPush(payload: payload) else { return false }
        let receivedAt = currentTimeMillis()
        logEngagement("push_received", [
            ("clickToken", push.clickToken),
            ("sentAt", push.sentAt),
            ("receivedAt", receivedAt)
        ])
        if let key = push.key {
            InfluencedOpens(store: ReceivedPushes(appGroup: appGroup), now: { receivedAt })
                .onReceived(key: key, clickToken: push.clickToken, sentAt: push.sentAt)
        }
        return true
    }
}
