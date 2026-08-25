//
//  InAppMessagingService.swift
//  Gameball
//

import UIKit

/// What the host wants done with a message that is about to display.
public enum GameballDisplayDecision {
    /// Show it now.
    case show
    /// Hold it and retry at the next opportunity — the host is mid-checkout, say.
    case later
    /// Do not show it, and do not retry. The occurrence is spent.
    case discard
}

/// How long the app may sit in the background before returning counts as a new session.
///
/// Thirty seconds, deliberately equal to the default display floor. A message can only display in
/// the foreground, so time-since-last-display is always at least time-spent-in-background —
/// aligning the two guarantees the floor can never suppress a warm session-start message. A lower
/// value reintroduces exactly that gap.
let iamSessionTimeout: TimeInterval = 30

/// The one owner of mutable in-app messaging state.
///
/// Every field below is confined to `queue`. Presentation hops to main; nothing else does. The
/// service is inert until `start()`, and every collaborator is injected so the whole lifecycle can
/// be driven from a fixture with no network, no window and no clock.
final class InAppMessagingService {

    // MARK: - Collaborators

    private let customerId: String
    private let source: MessageSource
    private let presenter: MessagePresenting
    private let analytics: MessageAnalytics
    private let cap: FrequencyCap
    private let cache: CampaignCache
    private let prefetcher: ArtworkPrefetcher
    private let variables: VariableSource
    private let router: MessageActionRouter
    private let now: () -> Date
    private let sessionTimeout: TimeInterval

    // MARK: - State, confined to `queue`

    private let queue = DispatchQueue(label: "co.gameball.inappmessaging.service")
    private let queueKey = DispatchSpecificKey<UInt8>()

    private var started = false
    private var campaigns: [InAppMessageCampaign] = []
    private var cooldown: TimeInterval = defaultDisplayCooldown
    /// The account's quiet window. `nil` until a sync says otherwise, which is also the
    /// value that means "never suppress on time of day".
    private var quietHours: QuietHours?
    /// Newest last. A stack rather than the specification's single slot (divergence D1): a
    /// deferral is cheap to keep, and losing an older message because a newer one arrived first
    /// is a silent drop nobody can debug.
    private var deferred: [InAppMessageCampaign] = []
    private var backgroundedAt: Date?

    // Per-presentation, reset on every dismissal.
    private var showing: InAppMessageCampaign?
    private var didReportImpression = false
    private var didEngage = false

    // MARK: - Host hooks

    var beforeDisplay: ((GameballInAppMessage) -> GameballDisplayDecision)?
    var onActionHandled: ((GameballInAppMessage, GameballMessageButton?, GameballClickAction) -> Bool)?
    var onMessageSelected: ((GameballInAppMessage) -> Void)?

    init(customerId: String,
         source: MessageSource,
         presenter: MessagePresenting,
         analytics: MessageAnalytics,
         cap: FrequencyCap,
         cache: CampaignCache,
         prefetcher: ArtworkPrefetcher,
         variables: VariableSource,
         router: MessageActionRouter,
         now: @escaping () -> Date = Date.init,
         sessionTimeout: TimeInterval = iamSessionTimeout) {
        self.customerId = customerId
        self.source = source
        self.presenter = presenter
        self.analytics = analytics
        self.cap = cap
        self.cache = cache
        self.prefetcher = prefetcher
        self.variables = variables
        self.router = router
        self.now = now
        self.sessionTimeout = sessionTimeout
        queue.setSpecific(key: queueKey, value: 1)
    }

    // MARK: - Test visibility

    var isStarted: Bool {
        return queue.sync { started }
    }

    var deferredMessages: [InAppMessageCampaign] {
        return queue.sync { deferred }
    }

    /// Drains the queue. Exposed so tests can assert without sleeping.
    func settle() {
        queue.sync {}
    }

    // MARK: - Lifecycle

    func start() {
        perform {
            guard !self.started else { return }
            self.started = true
            self.analytics.load()
            self.beginSession()
        }
    }

    func stop() {
        perform {
            guard self.started else { return }
            self.started = false

            self.analytics.flush()
            self.analytics.dispose()
            self.campaigns = []
            self.deferred = []
            self.showing = nil
            self.prefetcher.reset()
            self.variables.clear()

            DispatchQueue.main.async { self.presenter.dismiss() }
        }
    }

    /// Discards everything persisted for this customer. Called when the host identifies someone
    /// else, before a service for the new customer is built.
    func resetStoredState() {
        perform {
            self.cap.reset()
            self.cache.clear()
            self.variables.clear()
            self.prefetcher.reset()
            self.deferred = []
        }
    }

    func onSessionStart() {
        perform {
            guard self.started else { return }
            self.beginSession()
        }
    }

    func onForeground() {
        perform {
            guard self.started else { return }
            let wasBackgrounded = self.backgroundedAt
            self.backgroundedAt = nil

            if let since = wasBackgrounded,
               self.now().timeIntervalSince(since) > self.sessionTimeout {
                self.beginSession()
                return
            }
            // A warm resume is not a new session; it is just another chance to show what is held.
            self.retryDeferred()
        }
    }

    func onBackground() {
        perform {
            guard self.started else { return }
            self.backgroundedAt = self.now()
            // Flushed here because the process may not come back.
            self.analytics.flush()
        }
    }

    /// A drawing surface appeared, or the host's widget closed.
    func onDisplayOpportunity() {
        perform {
            guard self.started else { return }
            self.retryDeferred()
        }
    }

    // MARK: - Occurrences

    func onCustomEvent(name: String, properties: [String: Any]) {
        perform {
            guard self.started else { return }
            // Values can change between two events in a session, so the cache is dropped here
            // as well as at the start of every session.
            self.variables.forgetCachedValues()
            self.evaluate(.event(name: name, properties: properties))
        }
    }

    /// A purchase is not a trigger type: it is folded into an event named `purchase` so filters
    /// work on its fields with the same syntax as any other event.
    ///
    /// Exactly one occurrence is produced (divergence D3). Firing both a purchase and a generic
    /// event would let two campaigns display for one act.
    func onPurchase(productId: String,
                    price: Double,
                    currency: String,
                    quantity: Int,
                    properties: [String: Any]?) {
        var folded = properties ?? [:]
        folded["productId"] = productId
        folded["price"] = price
        folded["currency"] = currency
        folded["quantity"] = quantity
        onCustomEvent(name: gameballPurchaseEventName, properties: folded)
    }

    // MARK: - Session

    /// Must run on `queue`.
    private func beginSession() {
        // Personalisation is resolved per trigger, and a new session is a trigger. Dropping the
        // cache here matters for exactly one case, which is also the common one: a customer who
        // backgrounds the app for longer than the session timeout and comes back. The session
        // timeout is 30s and the value cache lives 60s, so without this the second session is
        // served from the first session's values — and anything earned in between, including on
        // another channel, is invisible. On a cold launch there is nothing cached and this costs
        // nothing.
        variables.forgetCachedValues()

        // Issued first so the request is in flight while local state is read: the stored history
        // gates the decision, not the request.
        source.fetch(customerId: customerId) { [weak self] result in
            guard let self = self else { return }
            self.perform { self.applySync(result) }
        }
        cap.load()
    }

    /// Must run on `queue`.
    private func applySync(_ result: Result<SyncResult, Error>) {
        switch result {
        case .success(let value):
            // A successful sync always wins, including an empty one — a customer whose campaigns
            // were switched off must stop seeing them.
            campaigns = value.campaigns
            cooldown = value.cooldown
            quietHours = value.quietHours
            if let payload = value.rawPayload {
                cache.save(payload: payload, customerId: customerId)
            }

        case .failure(let error):
            iamLog("sync failed (\(error)); falling back to the cache")
            // Applied only on failure. That is the backend's rule, and it also removes the race
            // where a slow cache read lands after a fast sync and clobbers fresher campaigns.
            if let cached = cache.load(customerId: customerId, now: now()) {
                campaigns = cached.campaigns
                cooldown = cached.cooldown
                quietHours = cached.quietHours
            }
        }

        // Narrow what personalisation may write to disk to the tokens actually referenced.
        var tokens: Set<String> = []
        for campaign in campaigns {
            tokens.formUnion(TokenSubstitution.tokens(in: campaign.message))
        }
        variables.setPersistableTokens(tokens)

        let held = campaigns
        prefetcher.warm(campaigns: held) { [weak self] in
            guard let self = self else { return }
            self.perform { self.evaluate(.sessionStart) }
        }
    }

    // MARK: - Evaluation

    /// Must run on `queue`.
    private func evaluate(_ occurrence: TriggerOccurrence) {
        guard started else { return }

        guard let selected = selectCampaign(occurrence: occurrence,
                                            campaigns: campaigns,
                                            capState: cap.state,
                                            now: now(),
                                            cooldown: cooldown,
                                            quietHours: quietHours,
                                            isArtworkReady: { [weak self] campaign in
                                                self?.prefetcher.isReady(campaign) ?? false
                                            }) else {
            return
        }

        // Selection happened, so the host is told about it either way — and told once, because
        // the retry path below does not re-announce.
        notifySelected(selected.message)

        // Asked *before* the host, not after. The hook's contract is "what the host wants done
        // with a message that is about to display", and a message that cannot have the slot is not
        // about to display: consulting anyway runs the host's side effects, discards its answer,
        // and spends a personalisation request, all for a message that was never going to appear.
        guard showing == nil else {
            deferCampaign(selected, because: "another message is showing")
            return
        }

        decideThenPresent(selected)
    }

    /// Consults the host, then acts on the answer.
    ///
    /// Shared by the first evaluation and by every retry. A deferral used to bypass this and
    /// present directly, which honoured `.later` exactly once — so a host that was still busy at
    /// the retry got the message anyway, which is the one thing `.later` exists to prevent.
    ///
    /// Must run on `queue`.
    private func decideThenPresent(_ campaign: InAppMessageCampaign) {
        resolveDecision(for: campaign.message) { [weak self] decision in
            guard let self = self else { return }
            switch decision {
            case .show:
                self.resolveTokensThenPresent(campaign)
            case .later:
                self.deferCampaign(campaign, because: "the host asked to show it later")
            case .discard:
                // Spent, not held: nothing retries, and because the cap is only recorded at
                // impression it is eligible again next session with no manual reset.
                iamLog("campaign \(campaign.campaignId) discarded by the host")
            }
        }
    }

    /// Asks the host, on main, and continues on `queue`.
    ///
    /// Deliberately **not** `DispatchQueue.main.sync`. The host can call `isInAppMessagingStarted`
    /// from main at any moment, which takes `queue.sync` — a synchronous hop the other way would
    /// then deadlock the app outright: main waiting on the queue, the queue waiting on main.
    private func resolveDecision(for message: GameballInAppMessage,
                                 then continuation: @escaping (GameballDisplayDecision) -> Void) {
        guard let hook = beforeDisplay else {
            continuation(.show)
            return
        }
        DispatchQueue.main.async { [weak self] in
            let decision = hook(message)
            self?.perform { continuation(decision) }
        }
    }

    private func notifySelected(_ message: GameballInAppMessage) {
        guard let hook = onMessageSelected else { return }
        DispatchQueue.main.async { hook(message) }
    }

    /// Must run on `queue`.
    private func resolveTokensThenPresent(_ campaign: InAppMessageCampaign) {
        let tokens = TokenSubstitution.tokens(in: campaign.message)
        guard !tokens.isEmpty else {
            present(campaign, message: campaign.message)
            return
        }
        variables.values(neededTokens: tokens) { [weak self] values in
            guard let self = self else { return }
            self.perform {
                let personalised = TokenSubstitution.apply(values: values, to: campaign.message)
                self.present(campaign, message: personalised)
            }
        }
    }

    /// Must run on `queue`.
    private func present(_ campaign: InAppMessageCampaign, message: GameballInAppMessage) {
        // The service owns the one-at-a-time rule rather than discovering it from the presenter.
        // Asking the presenter first and reacting to `.alreadyShowing` would mean overwriting the
        // live presentation's accounting before learning it had failed — losing the showing
        // message's impression. The presenter's obstacle stays as a backstop for races.
        guard showing == nil else {
            deferCampaign(campaign, because: "another message is showing")
            return
        }

        let context = PresentationContext(message: message)
        let handlers = PresentationHandlers(
            onShown: { [weak self] in self?.handleShown(campaign) },
            onButtonPressed: { [weak self] button in
                self?.handleClick(campaign, message: message, button: button)
            },
            onMessagePressed: { [weak self] in
                self?.handleClick(campaign, message: message, button: nil)
            },
            onDismissed: { [weak self] in self?.handleDismissed(campaign) }
        )

        // Set *before* presenting, not after: a view that honours reduce motion reports
        // `didPresent` synchronously from inside `present`, and the impression would be dropped
        // as a stale callback if the accounting were not already in place.
        showing = campaign
        didReportImpression = false
        didEngage = false

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let obstacle = self.presenter.present(context: context, handlers: handlers)
            guard let obstacle = obstacle else { return }
            self.perform {
                // Safe to clear: nothing else can have been showing, because of the guard above.
                self.showing = nil
                switch obstacle {
                case .noSurface:
                    self.deferCampaign(campaign, because: "there is no drawing surface yet")
                case .alreadyShowing:
                    self.deferCampaign(campaign, because: "another message is showing")
                case .notMainThread:
                    self.deferCampaign(campaign, because: "presentation was attempted off main")
                }
            }
        }
    }

    // MARK: - Deferral

    /// Must run on `queue`. Deduplicated and moved to the top, so a repeat deferral of the same
    /// campaign does not grow the stack.
    private func deferCampaign(_ campaign: InAppMessageCampaign, because reason: String) {
        deferred.removeAll { $0.campaignId == campaign.campaignId }
        deferred.append(campaign)
        iamLog("deferring campaign \(campaign.campaignId): \(reason)")
    }

    /// Must run on `queue`.
    private func retryDeferred() {
        guard started, let candidate = deferred.last else { return }

        // Re-validated, because the world moved while it waited.
        guard isRepeatEligible(campaign: candidate, capState: cap.state, now: now()) else {
            iamLog("dropping deferred campaign \(candidate.campaignId): it has since been shown")
            deferred.removeLast()
            return
        }
        guard !isWithinFloor(capState: cap.state, now: now(), cooldown: cooldown) else {
            // Kept, not dropped: a message deferred before another displayed must not slip
            // through inside the floor, but it deserves the next opportunity.
            iamLog("holding deferred campaign \(candidate.campaignId): inside the display floor")
            return
        }
        // The replay path needs its own gate. A message deferred at 21:59 and released by a
        // dismissal at 22:01 would otherwise be the one thing quiet hours cannot stop. Held
        // rather than dropped, for the same reason as the floor above: the window ends.
        if let quietHours = quietHours, quietHours.contains(now()) {
            iamLog("holding deferred campaign \(candidate.campaignId): inside quiet hours")
            return
        }

        // The same rule as the first evaluation: do not consult the host about a slot that is
        // already taken. Held rather than removed, so the campaign keeps its place in the stack.
        guard showing == nil else {
            iamLog("holding deferred campaign \(candidate.campaignId): another message is showing")
            return
        }

        // Removed before the decision, which is asynchronous: the removal is the claim on this
        // candidate, and `deferCampaign` de-duplicates by campaign id if the host says `.later`
        // again and it goes back on the stack.
        deferred.removeLast()
        decideThenPresent(candidate)
    }

    // MARK: - Presentation callbacks

    private func handleShown(_ campaign: InAppMessageCampaign) {
        perform {
            guard self.showing?.campaignId == campaign.campaignId else { return }
            self.didReportImpression = true

            // Recorded here, not at selection: a message deferred or discarded must not burn its
            // slot, and `impressions = clicks + dismissals` only holds if this is the anchor.
            self.cap.recordDisplay(campaignId: campaign.campaignId, at: self.now())

            guard !campaign.isTest else {
                iamLog("campaign \(campaign.campaignId) is a test send; reporting nothing")
                return
            }
            self.analytics.log(MessageEvent(campaignId: campaign.campaignId,
                                            variationId: campaign.variationId,
                                            dispatchId: campaign.dispatchId,
                                            type: .impression,
                                            occurredAt: self.now()))
        }
    }

    private func handleClick(_ campaign: InAppMessageCampaign,
                             message: GameballInAppMessage,
                             button: GameballMessageButton?) {
        let action = button?.action ?? message.clickAction
        perform {
            self.didEngage = true

            guard let action = action else {
                self.logClick(campaign, buttonId: button?.id, url: nil)
                return
            }

            self.resolveHostHandling(message: message, button: button,
                                     action: action) { [weak self] handled in
                guard let self = self else { return }
                guard !handled else {
                    self.logClick(campaign, buttonId: button?.id, url: nil)
                    return
                }
                // Routing opens browsers and pushes routes, so it belongs on main.
                DispatchQueue.main.async {
                    let url = self.router.perform(action)
                    self.perform { self.logClick(campaign, buttonId: button?.id, url: url) }
                }
            }
        }
    }

    /// Must run on `queue`.
    private func logClick(_ campaign: InAppMessageCampaign, buttonId: String?, url: String?) {
        guard !campaign.isTest else { return }
        analytics.log(MessageEvent(campaignId: campaign.campaignId,
                                   variationId: campaign.variationId,
                                   dispatchId: campaign.dispatchId,
                                   type: .click,
                                   occurredAt: now(),
                                   buttonId: buttonId,
                                   url: url))
    }

    /// Asks the host whether it handled the action itself. Async for the same deadlock reason as
    /// `resolveDecision`.
    private func resolveHostHandling(message: GameballInAppMessage,
                                     button: GameballMessageButton?,
                                     action: GameballClickAction,
                                     then continuation: @escaping (Bool) -> Void) {
        guard let hook = onActionHandled else {
            continuation(false)
            return
        }
        DispatchQueue.main.async { [weak self] in
            let handled = hook(message, button, action)
            self?.perform { continuation(handled) }
        }
    }

    private func handleDismissed(_ campaign: InAppMessageCampaign) {
        perform {
            let reportDismissal = self.didReportImpression && !self.didEngage

            self.showing = nil
            self.didReportImpression = false
            self.didEngage = false

            if reportDismissal && !campaign.isTest {
                // Only when shown and not engaged, so the dismissal that follows a tap is not
                // also counted as "shown and ignored".
                self.analytics.log(MessageEvent(campaignId: campaign.campaignId,
                                                variationId: campaign.variationId,
                                                dispatchId: campaign.dispatchId,
                                                type: .dismiss,
                                                occurredAt: self.now()))
            }

            self.retryDeferred()
        }
    }

    // MARK: - Queue

    /// Runs `work` with the queue's exclusivity, inline when already on it.
    ///
    /// The inline case is load-bearing: a stub collaborator answers synchronously from inside a
    /// queue block, and re-dispatching there would order the state change behind a read already
    /// waiting — making a completed presentation look pending.
    private func perform(_ work: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            work()
        } else {
            queue.async(execute: work)
        }
    }
}
