//
//  MessageActionRouter.swift
//  Gameball
//

import UIKit
import UserNotifications
import SafariServices

/// Carries out a click action.
///
/// Every effect is injected, so routing is testable without opening a browser or touching the
/// view hierarchy — and so a host that wants its own navigation can be wired in at one point.
final class MessageActionRouter {

    private let openURL: (URL, Bool) -> Void
    private let navigate: (String, [String: Any]?) -> Void
    private let dismissMessage: () -> Void
    private let requestPushPermission: () -> Void

    init(openURL: @escaping (URL, Bool) -> Void,
         navigate: @escaping (String, [String: Any]?) -> Void,
         dismiss: @escaping () -> Void,
         requestPushPermission: @escaping () -> Void = MessageActionRouter.liveRequestPushPermission) {
        self.openURL = openURL
        self.navigate = navigate
        self.dismissMessage = dismiss
        self.requestPushPermission = requestPushPermission
    }

    /// Performs the action and returns the URL to report alongside the click, when one was
    /// opened. `nil` for everything else — the `url` field on an event is for link attribution,
    /// not for describing the action.
    func perform(_ action: GameballClickAction) -> String? {
        switch action {
        case .dismiss:
            dismissMessage()
            return nil

        case .openURL(let url, let external):
            openURL(url, external)
            return url.absoluteString

        case .navigate(let route, let arguments):
            // Deliberately does not dismiss: the host may want the message to stay while it
            // pushes, and dismissing here would take that choice away.
            navigate(route, arguments)
            return nil

        case .requestPushPermission:
            // Dismissed *after* asking, so the system prompt is not stacked on a message
            // that then vanishes underneath it mid-animation.
            requestPushPermission()
            dismissMessage()
            return nil
        case .unsupported(let type):
            iamLog("ignoring unsupported action '\(type)'")
            return nil
        }
    }

    /// The live requester: the standard alert/badge/sound authorisation prompt. The outcome
    /// is logged, not returned — the click is reported the same way whether the customer
    /// allows or declines, which mirrors the other SDKs.
    static func liveRequestPushPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                iamLog("push permission request failed: \(error.localizedDescription)")
            } else {
                iamLog("push permission \(granted ? "granted" : "declined")")
            }
        }
    }

    // MARK: - Live effects

    /// Opens in an in-app browser, or hands off to the OS when the campaign asked for it.
    static func liveOpenURL(_ url: URL, external: Bool) {
        guard !external else {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            return
        }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            // `SFSafariViewController` traps on a non-web URL, so anything else goes to the OS,
            // which knows how to refuse politely.
            iamLog("\(url) is not a web URL; handing it to the system instead of an in-app browser")
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            return
        }
        guard let presenter = MessageActionRouter.topmostViewController() else {
            iamLog("no view controller to present an in-app browser from; opening in the OS browser")
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            return
        }
        presenter.present(SFSafariViewController(url: url), animated: true, completion: nil)
    }

    /// Walks to the front-most presented controller, so the browser is not presented from
    /// something already covered.
    static func topmostViewController() -> UIViewController? {
        var root: UIViewController?
        if #available(iOS 13.0, *) {
            let scene = UIApplication.shared.connectedScenes
                .first { $0.activationState == .foregroundActive } as? UIWindowScene
            root = (scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first)?
                .rootViewController
        }
        if root == nil {
            root = UIApplication.shared.windows.first { $0.isKeyWindow }?.rootViewController
                ?? UIApplication.shared.windows.first?.rootViewController
        }

        var current = root
        while let presented = current?.presentedViewController {
            current = presented
        }
        return current
    }
}
