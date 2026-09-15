//
//  MessageWindowPresenter.swift
//  Gameball
//

import UIKit

/// Owns the window a message lives in, for exactly as long as it lives.
///
/// The window is rebuilt per presentation and released on dismissal, so a stale surface handle
/// cannot survive a scene change. It is shown with `isHidden = false` and **never**
/// `makeKeyAndVisible`: taking key status would steal the host's first responder and dismiss
/// its keyboard, which is a visible regression for anything with a text field on screen.
final class MessageWindowPresenter: MessagePresenting, MessageViewCoordinating {

    private let viewFactory: (PresentationContext) -> InAppMessageView?

    private var window: MessageWindow?
    private var messageView: InAppMessageView?
    private var handlers: PresentationHandlers?
    private var context: PresentationContext?
    private var autoDismissTimer: Timer?
    private var hasReportedShown = false

    /// Presents without requiring a host window. Tests set this; the SDK never does.
    var headless = false

    /// The scene to attach to, or nil when the host has no window yet. Overridable so the
    /// no-surface path is testable — the test host always has a window of its own.
    var surfaceProvider: () -> Any? = MessageWindowPresenter.defaultSurface

    /// The interface orientation the host is currently in, or nil when it cannot be read.
    /// Overridable so the gating below is testable without a real device rotation.
    var orientationProvider: () -> UIInterfaceOrientation? = MessageWindowPresenter.currentOrientation

    init(viewFactory: @escaping (PresentationContext) -> InAppMessageView?) {
        self.viewFactory = viewFactory
    }

    deinit {
        autoDismissTimer?.invalidate()
    }

    var isShowing: Bool {
        return window != nil
    }

    // MARK: - MessagePresenting

    func present(context: PresentationContext,
                 handlers: PresentationHandlers) -> PresentationObstacle? {
        // Each check logs its own reason: "why didn't my message show" is the question
        // integrators ask most, and every one of these is otherwise invisible.
        guard Thread.isMainThread else {
            iamLog("cannot present off the main thread")
            return .notMainThread
        }
        guard !isShowing else {
            iamLog("cannot present: a message is already showing")
            return .alreadyShowing
        }

        var resolvedContext = context
        // Gated, not forced. `supportedInterfaceOrientations` on the message's view
        // controller used to make UIKit rotate the message window into the authored
        // orientation whatever the device was doing — a portrait strip beside a black
        // half-screen. Now the message waits for a matching rotation, and it is presented in
        // the orientation the device is actually in rather than a hard-coded portrait.
        let current = orientationProvider()
        if let current = current, !context.message.orientation.admits(current) {
            iamLog("cannot present: campaign wants \(context.message.orientation) and the device "
                 + "is \(current.isLandscape ? "landscape" : "portrait"); waiting for a rotation")
            return .orientationMismatch
        }
        resolvedContext.preferredOrientation = current ?? .portrait
        if !headless {
            guard let surface = surfaceProvider() else {
                iamLog("cannot present: the host has no window to attach to yet")
                return .noSurface
            }
            resolvedContext.windowScene = surface
        }

        guard let view = viewFactory(resolvedContext) else {
            iamLog("cannot present: no view could be built for a \(context.message.type) message")
            return .noSurface
        }

        self.context = resolvedContext
        self.handlers = handlers
        self.messageView = view
        self.hasReportedShown = false

        let window = makeWindow(for: resolvedContext)
        let controller = MessageViewController(context: resolvedContext, messageView: view)
        window.rootViewController = controller
        window.windowLevel = resolvedContext.windowLevel
        // Not `makeKeyAndVisible`: the host keeps its keyboard and first responder.
        window.isHidden = false
        self.window = window
        window.layoutIfNeeded()
        var sceneOrientation = -1
        if #available(iOS 13.0, *), let scene = resolvedContext.windowScene as? UIWindowScene {
            sceneOrientation = scene.interfaceOrientation.rawValue
        }
        iamLog("presented \(context.message.type) (authored \(context.message.orientation)) in interface "
             + "orientation \(current?.rawValue ?? -1) / scene \(sceneOrientation): window "
             + "\(Int(window.bounds.width))x\(Int(window.bounds.height)), root view "
             + "\(Int(controller.view.bounds.width))x\(Int(controller.view.bounds.height)), "
             + "transform identity \(controller.view.transform.isIdentity && window.transform.isIdentity), "
             + "screen \(Int(UIScreen.main.bounds.width))x\(Int(UIScreen.main.bounds.height))")

        view.present(completion: nil)
        return nil
    }

    func dismiss() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.dismiss() }
            return
        }
        guard let view = messageView else { return }
        view.dismiss(completion: nil)
    }

    // MARK: - MessageViewCoordinating

    func viewWillPresent() {}

    func viewDidPresent() {
        guard !hasReportedShown else { return }
        hasReportedShown = true

        // Scheduled here rather than at window-show, so a configured duration measures time
        // actually *visible* rather than time since insertion.
        if let seconds = context?.message.autoDismissAfter, seconds > 0 {
            autoDismissTimer = Timer.scheduledTimer(withTimeInterval: seconds,
                                                    repeats: false) { [weak self] _ in
                self?.dismiss()
            }
        }
        handlers?.onShown()
    }

    func viewWillDismiss() {}

    func viewDidDismiss() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil

        let onDismissed = handlers?.onDismissed
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        messageView = nil
        handlers = nil
        context = nil
        hasReportedShown = false

        onDismissed?()
    }

    func viewDidClick(buttonId: String?) {
        guard let message = context?.message else { return }
        if let buttonId = buttonId,
           let button = message.buttons.first(where: { $0.id == buttonId }) {
            handlers?.onButtonPressed(button)
        } else {
            handlers?.onMessagePressed()
        }
    }

    func viewDidRequest(action: GameballClickAction, buttonId: String?) {
        // Routing is the service's business; the presenter only reports. Dismissal for a
        // `.dismiss` action is driven by the view itself.
        if case .dismiss = action { dismiss() }
    }

    /// The interface orientation of the host's active scene; the status bar's on iOS 12.
    static func currentOrientation() -> UIInterfaceOrientation? {
        if #available(iOS 13.0, *) {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first {
                return scene.interfaceOrientation
            }
        }
        return UIApplication.shared.statusBarOrientation
    }

    // MARK: - Window construction

    private func makeWindow(for context: PresentationContext) -> MessageWindow {
        if #available(iOS 13.0, *) {
            if let scene = context.windowScene as? UIWindowScene {
                return MessageWindow(windowScene: scene)
            }
        }
        return MessageWindow(frame: UIScreen.main.bounds)
    }

    /// The foreground scene on iOS 13+, or the host's own window below it.
    private static func defaultSurface() -> Any? {
        if #available(iOS 13.0, *) {
            let scenes = UIApplication.shared.connectedScenes
            if let active = scenes.first(where: { $0.activationState == .foregroundActive })
                as? UIWindowScene {
                return active
            }
            return scenes.first as? UIWindowScene
        }
        return UIApplication.shared.windows.first
    }
}
