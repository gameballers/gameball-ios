//
//  GameballApp+InAppMessaging.swift
//  Gameball
//

import UIKit

/// Host callbacks for in-app messaging.
///
/// Every method has a default, so a host implements only what it needs. The hooks replace the
/// *action*, never the bookkeeping: the impression, the click and the dismissal are reported
/// whatever a hook returns.
public protocol GameballInAppMessagingDelegate: AnyObject {

    /// Asked immediately before a message would display.
    ///
    /// Return `.later` while the customer is mid-checkout, `.discard` to spend the occurrence.
    /// Defaults to `.show`.
    func gameballShouldDisplay(_ message: GameballInAppMessage) -> GameballDisplayDecision

    /// Return `true` when the host has handled the tap itself, so the SDK does nothing further.
    /// `button` is `nil` for a tap on the message surface. Defaults to `false`.
    func gameballDidHandleAction(_ message: GameballInAppMessage,
                                button: GameballMessageButton?,
                                action: GameballClickAction) -> Bool

    /// Called for every message *selected*, whatever happens to it next.
    func gameballDidSelectMessage(_ message: GameballInAppMessage)

    /// Called for a `navigate` action, for hosts whose router the SDK cannot drive.
    func gameballShouldNavigate(route: String, arguments: [String: Any]?)
}

public extension GameballInAppMessagingDelegate {
    func gameballShouldDisplay(_ message: GameballInAppMessage) -> GameballDisplayDecision {
        return .show
    }

    func gameballDidHandleAction(_ message: GameballInAppMessage,
                                button: GameballMessageButton?,
                                action: GameballClickAction) -> Bool {
        return false
    }

    func gameballDidSelectMessage(_ message: GameballInAppMessage) {}

    func gameballShouldNavigate(route: String, arguments: [String: Any]?) {}
}

/// Owns the in-app messaging service and the host's delegate.
///
/// Exists because a Swift extension cannot hold a stored property, and a computed property cannot
/// be `weak` — while the delegate *must* be weak, since `GameballApp` is an immortal singleton and
/// a strong reference would leak the host's view controller for the life of the app.
///
/// It also exists from first access rather than from `startInAppMessaging`, so assigning the
/// delegate before starting works and call ordering does not matter.
final class InAppMessagingCoordinator {

    static let shared = InAppMessagingCoordinator()

    weak var delegate: GameballInAppMessagingDelegate?

    private let lock = NSLock()
    private var service: InAppMessagingService?
    private var serviceCustomerId: String?
    /// Set when the host opted in before a customer was known. The module then starts itself as
    /// soon as `initializeCustomer` identifies one.
    private var wantsToStart = false
    private var observersRegistered = false

    /// Test-only override for the service assembly.
    ///
    /// Without it, exercising the public API means building a real `IAMHTTPClient` and talking to
    /// api.gameball.co, so the end-to-end suite could not drive the surface an integrator actually
    /// calls. The SDK never assigns this.
    var serviceBuilderOverride: ((String) -> InAppMessagingService)?

    private init() {}

    // MARK: - Opt in and out

    var isStarted: Bool {
        lock.lock()
        let current = service
        lock.unlock()
        return current?.isStarted ?? false
    }

    func start(customerId explicitId: String?) {
        // Spelled out rather than written as `explicitId ?? GameballApp...currentCustomerId`.
        // That property synchronises on the app's own serial queue, and `notifyCustomerChanged`
        // runs *inside* that queue — reading it there deadlocks. `??` happens to short-circuit,
        // so the terse version is correct today, but it leaves the next edit one keystroke away
        // from a hang that only reproduces for customers who opted in.
        let resolved: String?
        if let explicitId = explicitId {
            resolved = explicitId
        } else {
            resolved = GameballApp.getInstance().currentCustomerId
        }

        lock.lock()
        wantsToStart = true
        let existing = service
        let existingId = serviceCustomerId
        lock.unlock()

        guard let customerId = resolved, !customerId.isEmpty else {
            iamLog("startInAppMessaging was called before a customer was identified; the module "
                 + "will start as soon as initializeCustomer runs")
            return
        }

        // Idempotent for the same customer.
        if let existing = existing, existingId == customerId, existing.isStarted {
            return
        }

        // A different customer refetches and resets caps, so the host need not stop first.
        if let existing = existing, existingId != customerId {
            iamLog("customer changed from \(existingId ?? "none") to \(customerId); resetting")
            existing.stop()
            existing.resetStoredState()
        }

        let built = serviceBuilderOverride?(customerId) ?? buildService(customerId: customerId)
        lock.lock()
        service = built
        serviceCustomerId = customerId
        lock.unlock()

        registerLifecycleObservers()
        built.start()
    }

    func stop() {
        lock.lock()
        wantsToStart = false
        let current = service
        lock.unlock()
        current?.stop()
    }

    // MARK: - Host wiring

    /// Called from `initializeCustomer`. No-op unless the host opted in.
    ///
    /// Never reads `GameballApp.currentCustomerId`: that takes the app's own serial queue, and this
    /// runs from inside it, so the read would deadlock.
    func notifyCustomerChanged(_ customerId: String) {
        lock.lock()
        let wanted = wantsToStart
        lock.unlock()
        guard wanted else { return }
        start(customerId: customerId)
    }

    /// Called from `sendEvent`. No-op unless the module was started.
    func notifyEvents(_ events: [String: [String: Any]]) {
        lock.lock()
        let current = service
        lock.unlock()
        guard let service = current, service.isStarted else { return }

        for (name, properties) in events {
            service.onCustomEvent(name: name, properties: properties)
        }
    }

    func logPurchase(productId: String,
                     price: Double,
                     currency: String,
                     quantity: Int,
                     properties: [String: Any]?) {
        lock.lock()
        let current = service
        lock.unlock()
        guard let service = current, service.isStarted else {
            iamLog("logPurchase was called before in-app messaging was started; ignoring it")
            return
        }
        service.onPurchase(productId: productId, price: price, currency: currency,
                           quantity: quantity, properties: properties)
    }

    /// Test-only. Returns the coordinator to the state a fresh process would have.
    func resetForTesting() {
        lock.lock()
        let current = service
        service = nil
        serviceCustomerId = nil
        wantsToStart = false
        serviceBuilderOverride = nil
        lock.unlock()

        current?.stop()
        delegate = nil
    }

    // MARK: - Assembly

    private func buildService(customerId: String) -> InAppMessagingService {
        let store = UserDefaultsIAMStore()
        let transport = IAMHTTPClient(apiKey: { NetworkManager.shared().APIKey },
                                     language: { LanguageHelper.resolveLanguage() })
        let prefetcher = ArtworkPrefetcher()

        // The presenter needs to hand itself to each view as its coordinator, so the reference is
        // captured after construction.
        var presenter: MessageWindowPresenter!
        presenter = MessageWindowPresenter(viewFactory: { context in
            let message = context.message
            return MessageViewFactory.make(
                context: context,
                image: message.imageURL.flatMap { prefetcher.image(for: $0) },
                icon: message.iconURL.flatMap { prefetcher.image(for: $0) },
                coordinator: presenter)
        })

        let router = MessageActionRouter(
            openURL: { url, external in MessageActionRouter.liveOpenURL(url, external: external) },
            navigate: { route, arguments in
                InAppMessagingCoordinator.shared.delegate?
                    .gameballShouldNavigate(route: route, arguments: arguments)
            },
            dismiss: { presenter.dismiss() })

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

        let service = InAppMessagingService(
            customerId: customerId,
            source: HTTPMessageSource(transport: transport,
                                      appVersion: appVersion,
                                      sdkVersion: SDKInfo.version,
                                      locale: LanguageHelper.resolveLanguage()),
            presenter: presenter,
            analytics: BatchedMessageAnalytics(transport: transport,
                                               store: store,
                                               customerId: customerId),
            cap: FrequencyCap(store: store, customerId: customerId),
            cache: CampaignCache(store: store),
            prefetcher: prefetcher,
            variables: VariableSource(transport: transport,
                                      store: store,
                                      customerId: customerId),
            router: router)

        // Each hook is bridged individually and guarded, so a host that returns something odd
        // loses its override rather than its messages.
        service.beforeDisplay = { message in
            guard let delegate = InAppMessagingCoordinator.shared.delegate else { return .show }
            return delegate.gameballShouldDisplay(message)
        }
        service.onActionHandled = { message, button, action in
            guard let delegate = InAppMessagingCoordinator.shared.delegate else { return false }
            return delegate.gameballDidHandleAction(message, button: button, action: action)
        }
        service.onMessageSelected = { message in
            InAppMessagingCoordinator.shared.delegate?.gameballDidSelectMessage(message)
        }

        return service
    }

    /// The widget SDK has no lifecycle observer, so this is new internal machinery. Registered once.
    private func registerLifecycleObservers() {
        lock.lock()
        let already = observersRegistered
        observersRegistered = true
        lock.unlock()
        guard !already else { return }

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleDidBecomeActive),
                           name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(handleDidEnterBackground),
                           name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    @objc private func handleDidBecomeActive() {
        lock.lock()
        let current = service
        lock.unlock()
        current?.onForeground()
    }

    @objc private func handleDidEnterBackground() {
        lock.lock()
        let current = service
        lock.unlock()
        current?.onBackground()
    }
}

// MARK: - Public surface

public extension GameballApp {

    /// Whether in-app messaging is running.
    var isInAppMessagingStarted: Bool {
        return InAppMessagingCoordinator.shared.isStarted
    }

    /// The host's in-app messaging callbacks. Held **weakly**.
    ///
    /// May be assigned before or after `startInAppMessaging` — ordering does not matter.
    weak var inAppMessagingDelegate: GameballInAppMessagingDelegate? {
        get { return InAppMessagingCoordinator.shared.delegate }
        set { InAppMessagingCoordinator.shared.delegate = newValue }
    }

    /// Opts in to in-app messaging.
    ///
    /// Idempotent for the same customer. A different customer refetches and resets caps, so the
    /// host need not stop first. Safe to call before `initializeCustomer`: the module starts as
    /// soon as a customer is identified.
    ///
    /// - Parameter customerId: Defaults to the customer already identified with the SDK.
    func startInAppMessaging(customerId: String? = nil) {
        InAppMessagingCoordinator.shared.start(customerId: customerId)
    }

    /// Opts out: dismisses what is showing, flushes telemetry, clears per-customer state.
    func stopInAppMessaging() {
        InAppMessagingCoordinator.shared.stop()
    }

    /// Reports a purchase to the trigger engine.
    ///
    /// Reaches campaigns as an event named `purchase`, with these fields folded into its properties
    /// so filters work on them with the same syntax as any other event.
    func logPurchase(productId: String,
                     price: Double,
                     currency: String,
                     quantity: Int = 1,
                     properties: [String: Any]? = nil) {
        InAppMessagingCoordinator.shared.logPurchase(productId: productId,
                                                     price: price,
                                                     currency: currency,
                                                     quantity: quantity,
                                                     properties: properties)
    }
}
