//
//  InAppMessagingServiceTests.swift
//  GameballTests
//

import XCTest
@testable import Gameball

/// A presenter the test drives by hand, so impression timing and obstacles are explicit.
final class StubPresenter: MessagePresenting {
    var obstacle: PresentationObstacle?
    private(set) var presentedMessages: [GameballInAppMessage] = []
    private(set) var dismissCount = 0
    private var handlers: PresentationHandlers?
    var isShowing = false

    func present(context: PresentationContext,
                 handlers: PresentationHandlers) -> PresentationObstacle? {
        if let obstacle = obstacle { return obstacle }
        presentedMessages.append(context.message)
        self.handlers = handlers
        isShowing = true
        return nil
    }

    func dismiss() {
        dismissCount += 1
        guard isShowing else { return }
        isShowing = false
        handlers?.onDismissed()
    }

    // Driving the presentation from a test.
    func reportShown() { handlers?.onShown() }
    func tapButton(_ button: GameballMessageButton) { handlers?.onButtonPressed(button) }
    func tapSurface() { handlers?.onMessagePressed() }
    func reportDismissed() {
        isShowing = false
        handlers?.onDismissed()
    }
}

final class RecordingAnalytics: MessageAnalytics {
    private let lock = NSLock()
    private var recorded: [MessageEvent] = []
    private var loads = 0
    private var flushes = 0
    private var disposals = 0

    var events: [MessageEvent] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }
    var loadCount: Int { lock.lock(); defer { lock.unlock() }; return loads }
    var flushCount: Int { lock.lock(); defer { lock.unlock() }; return flushes }
    var disposeCount: Int { lock.lock(); defer { lock.unlock() }; return disposals }

    func types(for campaignId: Int? = nil) -> [MessageEventType] {
        return events.filter { campaignId == nil || $0.campaignId == campaignId! }.map { $0.type }
    }

    func load() { lock.lock(); loads += 1; lock.unlock() }
    func log(_ event: MessageEvent) { lock.lock(); recorded.append(event); lock.unlock() }
    func flush() { lock.lock(); flushes += 1; lock.unlock() }
    func dispose() { lock.lock(); disposals += 1; lock.unlock() }
}

final class InAppMessagingServiceTests: XCTestCase {

    private var clock = Date(timeIntervalSince1970: 1_700_000_000)
    private var presenter: StubPresenter!
    private var analytics: RecordingAnalytics!
    private var store: InMemoryIAMStore!
    private var variablesTransport: OutboxTransport!
    private var routedActions: [GameballClickAction] = []
    private var dismissalsRequested = 0

    override func setUp() {
        super.setUp()
        clock = Date(timeIntervalSince1970: 1_700_000_000)
        presenter = StubPresenter()
        analytics = RecordingAnalytics()
        store = InMemoryIAMStore()
        variablesTransport = OutboxTransport()
        routedActions = []
        dismissalsRequested = 0
    }

    // MARK: - Assembly

    private func makeService(source: MessageSource,
                             customerId: String = "cust-1",
                             sessionTimeout: TimeInterval = 30) -> InAppMessagingService {
        let router = MessageActionRouter(openURL: { url, external in
            self.routedActions.append(.openURL(url: url, external: external))
        }, navigate: { route, arguments in
            self.routedActions.append(.navigate(route: route, arguments: arguments))
        }, dismiss: {
            self.dismissalsRequested += 1
            self.presenter.dismiss()
        })

        return InAppMessagingService(
            customerId: customerId,
            source: source,
            presenter: presenter,
            analytics: analytics,
            cap: FrequencyCap(store: store, customerId: customerId),
            cache: CampaignCache(store: store),
            prefetcher: ArtworkPrefetcher(session: .shared, timeout: 1),
            variables: VariableSource(transport: variablesTransport,
                                      store: store,
                                      customerId: customerId,
                                      timeout: 0.2,
                                      cacheTTL: 60,
                                      now: { self.clock }),
            router: router,
            now: { self.clock },
            sessionTimeout: sessionTimeout)
    }

    private func result(_ campaigns: [InAppMessageCampaign],
                        cooldown: TimeInterval = 0,
                        quietHours: QuietHours? = nil) -> SyncResult {
        return SyncResult(campaigns: campaigns, cooldown: cooldown,
                          quietHours: quietHours, rawPayload: nil)
    }

    /// The live account's window, which is the one worth testing against.
    private var nightlyQuietHours: QuietHours {
        return QuietHours(json: ["enabled": true, "start": "22:00", "end": "08:00"])!
    }

    /// An instant on a fixed day, named by its UTC wall clock. The default `clock` is
    /// 22:13 UTC, which is *inside* the nightly window — so every test below sets it.
    ///
    /// `dayOffset` matters more than it looks: the window wraps midnight, so "the morning
    /// after 22:30" is a different day, and reusing the same one sends the clock backwards.
    /// A backwards clock reads as inside the display floor and holds the message for a
    /// reason that has nothing to do with quiet hours.
    private func utc(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2023; components.month = 11; components.day = 14 + dayOffset
        components.hour = hour; components.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }

    /// Alternates draining the service queue and the main queue until both are quiet.
    ///
    /// The service deliberately hops to main for host hooks and presentation, and back again, so a
    /// single barrier in either direction is not enough.
    private func drain(_ service: InAppMessagingService, rounds: Int = 6) {
        for _ in 0..<rounds {
            service.settle()
            let tick = expectation(description: "main tick")
            DispatchQueue.main.async { tick.fulfill() }
            wait(for: [tick], timeout: 3)
        }
    }

    private func startedService(_ campaigns: [InAppMessageCampaign],
                               cooldown: TimeInterval = 0) -> (InAppMessagingService, StubMessageSource) {
        let source = StubMessageSource(result: .success(result(campaigns, cooldown: cooldown)))
        let service = makeService(source: source)
        service.start()
        drain(service)
        return (service, source)
    }

    // MARK: - Dormancy

    func testNothingHappensBeforeStart() {
        let source = StubMessageSource(result: .success(result([makeCampaign()])))
        let service = makeService(source: source)
        drain(service)

        XCTAssertFalse(service.isStarted)
        XCTAssertEqual(source.fetchCount, 0)
        XCTAssertTrue(presenter.presentedMessages.isEmpty)
        XCTAssertTrue(analytics.events.isEmpty)
        XCTAssertNil(store.data(forKey: IAMStoreKey.displayHistory))
        XCTAssertNil(store.data(forKey: IAMStoreKey.campaignCache))

        // Occurrences before start are ignored too.
        service.onCustomEvent(name: "place_order", properties: [:])
        service.onSessionStart()
        drain(service)
        XCTAssertEqual(source.fetchCount, 0)
        XCTAssertTrue(presenter.presentedMessages.isEmpty)
    }

    // MARK: - Sync

    func testStartSyncsOnce() {
        let (service, source) = startedService([makeCampaign()])
        XCTAssertTrue(service.isStarted)
        XCTAssertEqual(source.fetchCount, 1)
        XCTAssertEqual(analytics.loadCount, 1)
    }

    func testStartIsIdempotent() {
        let (service, source) = startedService([makeCampaign()])
        service.start()
        drain(service)
        XCTAssertEqual(source.fetchCount, 1)
    }

    func testSessionStartCampaignIsPresented() {
        let (_, _) = startedService([makeCampaign(campaignId: 7, trigger: .sessionStart)])
        XCTAssertEqual(presenter.presentedMessages.map { $0.id }, ["7"])
    }

    func testFailedSyncFallsBackToCache() {
        // Seed the cache through a successful sync for the same customer.
        let payload = try! JSONSerialization.data(withJSONObject: [
            "cooldownSeconds": 0,
            "messages": [[
                "campaignId": 55,
                "messageType": 2,
                "trigger": ["type": "session_start", "repeatable": true],
                "locale": ["message": "From the cache"]
            ]]
        ])
        CampaignCache(store: store).save(payload: payload, customerId: "cust-1")

        let source = StubMessageSource(result: .failure(IAMSyncError.retryable(status: 503)))
        let service = makeService(source: source)
        service.start()
        drain(service)

        XCTAssertEqual(presenter.presentedMessages.map { $0.body }, ["From the cache"])
    }

    /// A successful sync always wins, empty included — a customer whose campaigns were switched
    /// off must stop seeing them.
    func testEmptySuccessfulSyncReplacesTheCache() {
        let payload = try! JSONSerialization.data(withJSONObject: [
            "messages": [[
                "campaignId": 55,
                "messageType": 2,
                "trigger": ["type": "session_start", "repeatable": true],
                "locale": ["message": "Stale"]
            ]]
        ])
        CampaignCache(store: store).save(payload: payload, customerId: "cust-1")

        let (_, _) = startedService([])
        XCTAssertTrue(presenter.presentedMessages.isEmpty)
    }

    func testCacheIsAppliedOnlyOnFailure() {
        let payload = try! JSONSerialization.data(withJSONObject: [
            "messages": [[
                "campaignId": 55,
                "messageType": 2,
                "trigger": ["type": "session_start", "repeatable": true],
                "locale": ["message": "Stale"]
            ]]
        ])
        CampaignCache(store: store).save(payload: payload, customerId: "cust-1")

        let (_, _) = startedService([makeCampaign(campaignId: 7,
                                                  message: makeMessage(id: "7", body: "Fresh"))])
        XCTAssertEqual(presenter.presentedMessages.map { $0.body }, ["Fresh"])
    }

    func testSuccessfulSyncWritesTheCache() {
        let payload = try! JSONSerialization.data(withJSONObject: ["messages": []])
        let source = StubMessageSource(result: .success(
            SyncResult(campaigns: [], cooldown: 0, rawPayload: payload)))
        let service = makeService(source: source)
        service.start()
        drain(service)
        XCTAssertNotNil(store.data(forKey: IAMStoreKey.campaignCache))
    }

    // MARK: - Session timeout

    func testWarmResumeBeyondSessionTimeoutResyncs() {
        let (service, source) = startedService([makeCampaign(repeatable: true)])
        service.onBackground()
        drain(service)

        clock = clock.addingTimeInterval(31)
        service.onForeground()
        drain(service)

        XCTAssertEqual(source.fetchCount, 2)
    }

    func testResumeInsideSessionTimeoutDoesNotResync() {
        let (service, source) = startedService([makeCampaign()])
        service.onBackground()
        drain(service)

        clock = clock.addingTimeInterval(10)
        service.onForeground()
        drain(service)

        XCTAssertEqual(source.fetchCount, 1)
    }

    func testBackgroundingFlushesAnalytics() {
        let (service, _) = startedService([makeCampaign()])
        let before = analytics.flushCount
        service.onBackground()
        drain(service)
        XCTAssertEqual(analytics.flushCount, before + 1)
    }

    // MARK: - Impression accounting

    /// Recorded at visibility, not at selection: a message deferred or discarded must not burn
    /// its slot.
    func testImpressionRecordsCapAndFloorAtVisibility() {
        let (service, _) = startedService([makeCampaign(campaignId: 7)])
        XCTAssertEqual(presenter.presentedMessages.count, 1)
        XCTAssertTrue(analytics.events.isEmpty, "nothing is reported before the message is visible")

        presenter.reportShown()
        drain(service)

        XCTAssertEqual(analytics.types(), [.impression])
        let reloaded = FrequencyCap(store: store, customerId: "cust-1")
        reloaded.load()
        XCTAssertEqual(reloaded.state.lastDisplayAt, clock)
        XCTAssertEqual(reloaded.state.lastDisplayByCampaign[7], clock)
    }

    func testMessageDismissedBeforePaintReportsNothing() {
        let (service, _) = startedService([makeCampaign(campaignId: 7)])
        presenter.reportDismissed()
        drain(service)

        XCTAssertTrue(analytics.events.isEmpty,
                      "a message that never painted reported \(analytics.types())")
        let reloaded = FrequencyCap(store: store, customerId: "cust-1")
        reloaded.load()
        XCTAssertNil(reloaded.state.lastDisplayAt, "an unseen message burned its slot")
    }

    func testDismissReportedWhenShownAndNotEngaged() {
        let (service, _) = startedService([makeCampaign(campaignId: 7)])
        presenter.reportShown()
        drain(service)
        presenter.reportDismissed()
        drain(service)

        XCTAssertEqual(analytics.types(), [.impression, .dismiss])
    }

    /// The dismissal that follows a tap must not also be counted as "shown and ignored".
    func testDismissNotReportedAfterEngagement() {
        let (service, _) = startedService([makeCampaign(campaignId: 7)])
        presenter.reportShown()
        drain(service)
        presenter.tapSurface()
        drain(service)
        presenter.reportDismissed()
        drain(service)

        XCTAssertEqual(analytics.types(), [.impression, .click])
    }

    func testButtonTapReportsClickWithButtonId() {
        let button = makeButton(id: "cta", action: .navigate(route: "orders", arguments: nil))
        let campaign = makeCampaign(campaignId: 7,
                                    message: makeMessage(id: "7", buttons: [button]))
        let (service, _) = startedService([campaign])
        presenter.reportShown()
        drain(service)
        presenter.tapButton(button)
        drain(service)

        XCTAssertEqual(analytics.types(), [.impression, .click])
        XCTAssertEqual(analytics.events.last?.buttonId, "cta")
        XCTAssertEqual(routedActions.count, 1)
    }

    func testSurfaceTapReportsClickWithoutButtonId() {
        let campaign = makeCampaign(campaignId: 7,
                                    message: makeMessage(id: "7", clickAction: .dismiss))
        let (service, _) = startedService([campaign])
        presenter.reportShown()
        drain(service)
        presenter.tapSurface()
        drain(service)

        XCTAssertEqual(analytics.events.last?.type, .click)
        XCTAssertNil(analytics.events.last?.buttonId)
    }

    func testOpenURLClickReportsTheURL() {
        let url = URL(string: "https://example.com/offer")!
        let button = makeButton(id: "cta", action: .openURL(url: url, external: false))
        let campaign = makeCampaign(campaignId: 7,
                                    message: makeMessage(id: "7", buttons: [button]))
        let (service, _) = startedService([campaign])
        presenter.reportShown()
        drain(service)
        presenter.tapButton(button)
        drain(service)

        XCTAssertEqual(analytics.events.last?.url, "https://example.com/offer")
    }

    func testIsTestCampaignDisplaysAndReportsNothing() {
        let (service, _) = startedService([makeCampaign(campaignId: 7, isTest: true)])
        XCTAssertEqual(presenter.presentedMessages.count, 1, "a test send must still display")

        presenter.reportShown()
        drain(service)
        presenter.tapSurface()
        drain(service)
        presenter.reportDismissed()
        drain(service)

        XCTAssertTrue(analytics.events.isEmpty,
                      "a test send reported \(analytics.types())")
    }

    // MARK: - Deferral

    func testDeferredWhenNoSurface() {
        presenter.obstacle = .noSurface
        let (service, _) = startedService([makeCampaign(campaignId: 7)])
        XCTAssertEqual(service.deferredMessages.map { $0.campaignId }, [7])
        XCTAssertTrue(presenter.presentedMessages.isEmpty)
    }

    func testDeferredWhenAnotherIsShowing() {
        presenter.obstacle = .alreadyShowing
        let (service, _) = startedService([makeCampaign(campaignId: 7)])
        XCTAssertEqual(service.deferredMessages.map { $0.campaignId }, [7])
    }

    func testBeforeDisplayLaterDefers() {
        let source = StubMessageSource(result: .success(result([makeCampaign(campaignId: 7)])))
        let service = makeService(source: source)
        service.beforeDisplay = { _ in .later }
        service.start()
        drain(service)

        XCTAssertEqual(service.deferredMessages.map { $0.campaignId }, [7])
        XCTAssertTrue(presenter.presentedMessages.isEmpty)
    }

    func testBeforeDisplayShowPresents() {
        let source = StubMessageSource(result: .success(result([makeCampaign(campaignId: 7)])))
        let service = makeService(source: source)
        service.beforeDisplay = { _ in .show }
        service.start()
        drain(service)

        XCTAssertEqual(presenter.presentedMessages.count, 1)
        XCTAssertTrue(service.deferredMessages.isEmpty)
    }

    func testBeforeDisplayDiscardSuppresses() {
        let source = StubMessageSource(result: .success(result([makeCampaign(campaignId: 7)])))
        let service = makeService(source: source)
        service.beforeDisplay = { _ in .discard }
        service.start()
        drain(service)

        XCTAssertTrue(service.deferredMessages.isEmpty, "a discard must hold nothing")
        XCTAssertTrue(presenter.presentedMessages.isEmpty)
        XCTAssertTrue(analytics.events.isEmpty)
    }

    /// The cap is only recorded at impression, so a discarded campaign is eligible again next
    /// session with no manual reset.
    func testSuppressedCampaignIsEligibleNextSessionWithoutReset() {
        let source = StubMessageSource(result: .success(result([makeCampaign(campaignId: 7)])))
        let service = makeService(source: source)
        service.beforeDisplay = { _ in .discard }
        service.start()
        drain(service)
        XCTAssertTrue(presenter.presentedMessages.isEmpty)

        service.beforeDisplay = { _ in .show }
        service.onSessionStart()
        drain(service)
        XCTAssertEqual(presenter.presentedMessages.count, 1)
    }

    func testNewerDeferralMovesToTopOfStackAndDeduplicates() {
        presenter.obstacle = .noSurface
        let campaigns = [makeCampaign(campaignId: 1, priority: 5, responseIndex: 0),
                         makeCampaign(campaignId: 2, priority: 9, responseIndex: 1)]
        let (service, _) = startedService(campaigns)

        // Priority 9 wins the session-start occurrence and is deferred.
        XCTAssertEqual(service.deferredMessages.map { $0.campaignId }, [2])

        // Another occurrence defers it again; the stack must not grow.
        service.onSessionStart()
        drain(service)
        XCTAssertEqual(service.deferredMessages.map { $0.campaignId }, [2])
    }

    func testRetryOnDismissalPresentsTheStackTop() {
        // First message shows; a second occurrence is deferred because one is already showing.
        let campaigns = [makeCampaign(campaignId: 1, priority: 9,
                                      trigger: .sessionStart, responseIndex: 0),
                         makeCampaign(campaignId: 2, priority: 1,
                                      trigger: .event(name: "e", filters: []),
                                      responseIndex: 1)]
        let (service, _) = startedService(campaigns)
        XCTAssertEqual(presenter.presentedMessages.map { $0.id }, ["1"])

        presenter.reportShown()
        drain(service)
        service.onCustomEvent(name: "e", properties: [:])
        drain(service)
        XCTAssertEqual(service.deferredMessages.map { $0.campaignId }, [2])

        // Dismissal is a display opportunity.
        presenter.reportDismissed()
        drain(service)

        XCTAssertEqual(presenter.presentedMessages.map { $0.id }, ["1", "2"])
        XCTAssertTrue(service.deferredMessages.isEmpty)
    }

    /// A message deferred before another displayed must not slip through inside the floor.
    ///
    /// The deferral has to happen *before* any impression, or the floor would suppress the second
    /// campaign at selection and it would never be held at all.
    func testRetryRechecksTheFloor() {
        let campaigns = [makeCampaign(campaignId: 1, priority: 9, responseIndex: 0),
                         makeCampaign(campaignId: 2, priority: 1,
                                      trigger: .event(name: "e", filters: []),
                                      responseIndex: 1)]
        let source = StubMessageSource(result: .success(result(campaigns, cooldown: 30)))
        let service = makeService(source: source)
        service.start()
        drain(service)
        XCTAssertEqual(presenter.presentedMessages.count, 1)

        // Campaign 1 is up but has not painted, so there is no floor yet and campaign 2 is
        // selected — then deferred, because one message is already showing.
        service.onCustomEvent(name: "e", properties: [:])
        drain(service)
        XCTAssertEqual(service.deferredMessages.map { $0.campaignId }, [2])

        // Now campaign 1 paints, which starts the floor.
        presenter.reportShown()
        drain(service)
        presenter.reportDismissed()
        drain(service)

        XCTAssertEqual(presenter.presentedMessages.count, 1,
                       "the deferred message slipped through inside the floor")
        XCTAssertEqual(service.deferredMessages.map { $0.campaignId }, [2],
                       "it should still be held for the next opportunity")

        // Past the floor, the next opportunity shows it.
        clock = clock.addingTimeInterval(31)
        service.onDisplayOpportunity()
        drain(service)
        XCTAssertEqual(presenter.presentedMessages.count, 2)
    }

    func testDisplayOpportunityRetriesTheStack() {
        presenter.obstacle = .noSurface
        let (service, _) = startedService([makeCampaign(campaignId: 7)])
        XCTAssertEqual(service.deferredMessages.count, 1)

        presenter.obstacle = nil
        service.onDisplayOpportunity()
        drain(service)
        XCTAssertEqual(presenter.presentedMessages.count, 1)
    }

    func testWarmForegroundRetriesTheStack() {
        presenter.obstacle = .noSurface
        let (service, _) = startedService([makeCampaign(campaignId: 7)])
        service.onBackground()
        drain(service)

        presenter.obstacle = nil
        clock = clock.addingTimeInterval(5)   // inside the session timeout
        service.onForeground()
        drain(service)
        XCTAssertEqual(presenter.presentedMessages.count, 1)
    }

    // MARK: - Personalisation

    /// Values can change between two events in a session, but nothing can have changed before the
    /// session began.
    func testVariableCacheClearedOnEventNotOnSessionStart() {
        variablesTransport.script([.success(Data("{\"variables\":{\"name\":\"Sam\"}}".utf8)),
                                   .success(Data("{\"variables\":{\"name\":\"Sam\"}}".utf8))])

        let personalised = makeMessage(id: "1", header: "Hi {name}")
        let campaigns = [makeCampaign(campaignId: 1, trigger: .sessionStart,
                                      message: personalised),
                         makeCampaign(campaignId: 2,
                                      trigger: .event(name: "e", filters: []),
                                      message: makeMessage(id: "2", header: "Hi {name}"))]
        let (service, _) = startedService(campaigns)
        XCTAssertEqual(variablesTransport.postCount, 1)
        XCTAssertEqual(presenter.presentedMessages.first?.header, "Hi Sam")

        presenter.reportShown()
        drain(service)
        presenter.reportDismissed()
        drain(service)

        service.onCustomEvent(name: "e", properties: [:])
        drain(service)
        XCTAssertEqual(variablesTransport.postCount, 2,
                       "an event should have dropped the variable cache")
    }

    func testCampaignWithNoTokensNeverFetchesVariables() {
        let (_, _) = startedService([makeCampaign(campaignId: 7)])
        XCTAssertEqual(variablesTransport.postCount, 0,
                       "a campaign with no tokens must not trigger a variables request")
    }

    // MARK: - Purchase

    /// Exactly one occurrence: firing both a purchase and a generic event would let two
    /// campaigns display for one act.
    func testPurchaseFiresExactlyOneOccurrence() {
        let campaigns = [makeCampaign(campaignId: 1, priority: 9,
                                      trigger: .event(name: gameballPurchaseEventName,
                                                      filters: []),
                                      responseIndex: 0),
                         makeCampaign(campaignId: 2, priority: 1,
                                      trigger: .event(name: gameballPurchaseEventName,
                                                      filters: []),
                                      responseIndex: 1)]
        let (service, _) = startedService(campaigns)
        presenter.obstacle = nil

        service.onPurchase(productId: "sku-1", price: 150, currency: "USD",
                           quantity: 1, properties: nil)
        drain(service)

        XCTAssertEqual(presenter.presentedMessages.count, 1,
                       "one purchase produced \(presenter.presentedMessages.count) displays")
    }

    func testPurchaseFoldsItsFieldsIntoTheOccurrence() {
        let campaign = makeCampaign(campaignId: 7,
                                    trigger: .event(name: gameballPurchaseEventName, filters: [
                                        PropertyFilter(name: "price", op: .greaterThan, value: 100),
                                        PropertyFilter(name: "productId", op: .equals, value: "sku-1"),
                                        PropertyFilter(name: "currency", op: .equals, value: "USD"),
                                        PropertyFilter(name: "quantity", op: .equals, value: 2)
                                    ]))
        let (service, _) = startedService([campaign])

        service.onPurchase(productId: "sku-1", price: 150, currency: "USD",
                           quantity: 2, properties: ["source": "app"])
        drain(service)
        XCTAssertEqual(presenter.presentedMessages.count, 1)
    }

    func testPurchaseBelowAFilterThresholdShowsNothing() {
        let campaign = makeCampaign(campaignId: 7,
                                    trigger: .event(name: gameballPurchaseEventName, filters: [
                                        PropertyFilter(name: "price", op: .greaterThan, value: 100)
                                    ]))
        let (service, _) = startedService([campaign])
        service.onPurchase(productId: "sku-1", price: 50, currency: "USD",
                           quantity: 1, properties: nil)
        drain(service)
        XCTAssertTrue(presenter.presentedMessages.isEmpty)
    }

    // MARK: - Hooks

    func testOnMessageSelectedIsNotifiedBeforeDisplay() {
        var selected: [String] = []
        let source = StubMessageSource(result: .success(result([makeCampaign(campaignId: 7)])))
        let service = makeService(source: source)
        service.onMessageSelected = { selected.append($0.id) }
        service.start()
        drain(service)

        XCTAssertEqual(selected, ["7"])
    }

    /// A host that handles the action itself stops the SDK routing it — but the click is still
    /// reported, because the engagement happened either way.
    func testOnActionHandledSuppressesRoutingButNotReporting() {
        let button = makeButton(id: "cta", action: .navigate(route: "orders", arguments: nil))
        let source = StubMessageSource(result: .success(result([
            makeCampaign(campaignId: 7, message: makeMessage(id: "7", buttons: [button]))
        ])))
        let service = makeService(source: source)
        service.onActionHandled = { _, _, _ in true }
        service.start()
        drain(service)

        presenter.reportShown()
        drain(service)
        presenter.tapButton(button)
        drain(service)

        XCTAssertTrue(routedActions.isEmpty, "the SDK routed an action the host claimed")
        XCTAssertEqual(analytics.types(), [.impression, .click])
    }

    func testUnsetHooksUseTheDefaultBehaviour() {
        let (service, _) = startedService([makeCampaign(campaignId: 7)])
        XCTAssertTrue(service.beforeDisplay == nil)
        XCTAssertTrue(service.onActionHandled == nil)
        XCTAssertTrue(service.onMessageSelected == nil)
        XCTAssertEqual(presenter.presentedMessages.count, 1,
                       "with no beforeDisplay hook the default must be to show")
    }

    // MARK: - Teardown

    func testStopDismissesFlushesAndClears() {
        let (service, _) = startedService([makeCampaign(campaignId: 7)])
        presenter.reportShown()
        drain(service)

        let flushesBefore = analytics.flushCount
        service.stop()
        drain(service)

        XCTAssertFalse(service.isStarted)
        XCTAssertGreaterThan(analytics.flushCount, flushesBefore)
        XCTAssertEqual(analytics.disposeCount, 1)
        XCTAssertGreaterThan(presenter.dismissCount, 0)
        XCTAssertTrue(service.deferredMessages.isEmpty)
    }

    func testStopMakesTheServiceInertAgain() {
        let (service, source) = startedService([makeCampaign(campaignId: 7)])
        service.stop()
        drain(service)

        service.onCustomEvent(name: "e", properties: [:])
        service.onSessionStart()
        drain(service)
        XCTAssertEqual(source.fetchCount, 1, "a stopped service kept syncing")
    }

    func testResetStoredStateClearsCapsAndCache() {
        let (service, _) = startedService([makeCampaign(campaignId: 7)])
        presenter.reportShown()
        drain(service)
        XCTAssertNotNil(store.data(forKey: IAMStoreKey.displayHistory))

        service.resetStoredState()
        drain(service)

        XCTAssertNil(store.data(forKey: IAMStoreKey.displayHistory))
        XCTAssertNil(store.data(forKey: IAMStoreKey.campaignCache))
        XCTAssertNil(store.data(forKey: IAMStoreKey.variables))
    }

    // MARK: - Quiet hours

    func testQuietHoursSuppressSessionStart() {
        clock = utc(23, 0)
        let source = StubMessageSource(result: .success(
            result([makeCampaign(campaignId: 7)], quietHours: nightlyQuietHours)))
        let service = makeService(source: source)
        service.start()
        drain(service)

        XCTAssertTrue(presenter.presentedMessages.isEmpty,
                      "nothing displays inside the account's quiet window")
        XCTAssertTrue(service.deferredMessages.isEmpty,
                      "suppression is not a deferral: the occurrence is spent, not queued")
        XCTAssertTrue(analytics.events.isEmpty, "a message that never showed reports nothing")
    }

    func testOutsideQuietHoursSessionStartPresents() {
        clock = utc(12, 0)
        let source = StubMessageSource(result: .success(
            result([makeCampaign(campaignId: 7)], quietHours: nightlyQuietHours)))
        let service = makeService(source: source)
        service.start()
        drain(service)

        XCTAssertEqual(presenter.presentedMessages.count, 1)
    }

    /// The window ends at 08:00 exclusive, so 08:00 itself is the first minute a message may
    /// display. An off-by-one here costs a customer their morning message.
    func testTheFirstMinuteAfterTheWindowPresents() {
        clock = utc(8, 0)
        let source = StubMessageSource(result: .success(
            result([makeCampaign(campaignId: 7)], quietHours: nightlyQuietHours)))
        let service = makeService(source: source)
        service.start()
        drain(service)

        XCTAssertEqual(presenter.presentedMessages.count, 1)
    }

    /// A session that starts before 22:00 holds its campaigns for the whole session, so the
    /// gate cannot live at fetch time — it has to be re-asked at every display decision.
    func testASessionThatCrossesIntoTheWindowStopsDisplaying() {
        clock = utc(21, 30)
        let campaigns = [makeCampaign(campaignId: 1),
                         makeCampaign(campaignId: 2,
                                      trigger: .event(name: "e", filters: []))]
        let source = StubMessageSource(result: .success(
            result(campaigns, quietHours: nightlyQuietHours)))
        let service = makeService(source: source)
        service.start()
        drain(service)
        XCTAssertEqual(presenter.presentedMessages.count, 1, "21:30 is outside the window")

        presenter.reportShown()
        drain(service)
        presenter.reportDismissed()
        drain(service)

        // Same session, same held campaigns, thirty-one minutes later.
        clock = utc(22, 1)
        service.onCustomEvent(name: "e", properties: [:])
        drain(service)

        XCTAssertEqual(presenter.presentedMessages.count, 1,
                       "the session crossed into quiet hours and must stop displaying")
    }

    /// The replay path has its own gate, and this is the case that needs it: a message
    /// deferred at 21:59 and released by a dismissal at 22:01 would otherwise be the one
    /// thing quiet hours cannot stop.
    func testADeferredMessageIsHeldInsideQuietHoursAndReleasedAfter() {
        clock = utc(21, 30)
        let campaigns = [makeCampaign(campaignId: 1, priority: 9, responseIndex: 0),
                         makeCampaign(campaignId: 2, priority: 1,
                                      trigger: .event(name: "e", filters: []),
                                      responseIndex: 1)]
        let source = StubMessageSource(result: .success(
            result(campaigns, quietHours: nightlyQuietHours)))
        let service = makeService(source: source)
        service.start()
        drain(service)
        XCTAssertEqual(presenter.presentedMessages.count, 1)

        // Campaign 2 is selected while campaign 1 is up, so it is deferred rather than shown.
        service.onCustomEvent(name: "e", properties: [:])
        drain(service)
        XCTAssertEqual(service.deferredMessages.map { $0.campaignId }, [2])

        presenter.reportShown()
        drain(service)

        // The clock crosses into the window *before* the dismissal that would release the
        // deferral. Ordering is the whole point: released at 21:30 the message is entitled to
        // display, and a version of this test that dismissed first passed against a gate that
        // was never consulted.
        clock = utc(22, 30)
        presenter.reportDismissed()
        drain(service)

        // The cooldown is zero, so the display floor cannot be what holds it.
        service.onDisplayOpportunity()
        drain(service)
        XCTAssertEqual(presenter.presentedMessages.count, 1,
                       "the deferred message slipped through inside quiet hours")
        XCTAssertEqual(service.deferredMessages.map { $0.campaignId }, [2],
                       "held, not dropped — the window ends")

        // And once it ends — the next morning, not the same one — the next opportunity
        // releases it.
        clock = utc(8, 0, dayOffset: 1)
        service.onDisplayOpportunity()
        drain(service)
        XCTAssertEqual(presenter.presentedMessages.count, 2)
        XCTAssertTrue(service.deferredMessages.isEmpty)
    }

    /// A sync failure falls back to the cache, and the window has to come back with the
    /// campaigns — otherwise an offline launch at 3am displays everything.
    func testQuietHoursSurviveACacheFallback() {
        clock = utc(12, 0)
        let payload = IAMFixture.data("v4-sync-quiet-hours")

        // First run: a successful sync writes the payload to the cache.
        let live = StubMessageSource(result: .success(
            MessageParser.parseSyncResponse(payload)))
        let first = makeService(source: live)
        first.start()
        drain(first)
        XCTAssertNotNil(store.data(forKey: IAMStoreKey.campaignCache))

        // Second run, inside the window, with a sync that fails. The presenter is shared
        // across both services, so the assertion is on the delta rather than on emptiness.
        clock = utc(23, 0)
        let shownBefore = presenter.presentedMessages.count
        let offline = StubMessageSource(
            result: .failure(IAMSyncError.retryable(status: nil)))
        let second = makeService(source: offline)
        second.start()
        drain(second)

        XCTAssertEqual(presenter.presentedMessages.count, shownBefore,
                       "the cached window must suppress just as the fetched one does")
    }

    // MARK: - Personalisation is fetched per trigger

    private func variableFetches() -> Int {
        return variablesTransport.allPaths.filter { $0.contains("variables") }.count
    }

    private func personalisedCampaign(_ id: Int = 1,
                                      trigger: MessageTrigger = .sessionStart)
        -> InAppMessageCampaign {
        return makeCampaign(campaignId: id, trigger: trigger,
                            message: makeMessage(id: "\(id)", type: .modal,
                                                 body: "Hi {player_name}"))
    }

    private func variablePayload(_ name: String) -> Data {
        return try! JSONSerialization.data(withJSONObject: ["variables": ["player_name": name]])
    }

    /// Substitution moved from the backend into the SDK when the variables endpoint deployed, and
    /// the contract that came with it is that the endpoint is asked **per trigger**. A campaign
    /// with no token still asks nothing — that part is unchanged.
    func testASessionStartFetchesVariables() {
        variablesTransport.script([.success(variablePayload("Ada"))])
        let source = StubMessageSource(result: .success(result([personalisedCampaign()])))
        let service = makeService(source: source)
        service.start()
        drain(service)

        XCTAssertEqual(variableFetches(), 1)
        XCTAssertEqual(presenter.presentedMessages.first?.body, "Hi Ada")
    }

    /// The gap this closes. A 30s session timeout sits inside a 60s value cache, so a customer who
    /// backgrounds the app for 31 seconds gets a *new session* served from *old values* — and
    /// anything that happened in between, including points earned on another channel, is invisible.
    func testANewSessionRefetchesVariables() {
        variablesTransport.script([.success(variablePayload("Ada")),
                                   .success(variablePayload("Grace"))])
        let campaigns = [personalisedCampaign(1)]
        let source = StubMessageSource(result: .success(result(campaigns)))
        let service = makeService(source: source, sessionTimeout: 30)
        service.start()
        drain(service)
        XCTAssertEqual(presenter.presentedMessages.map { $0.body }, ["Hi Ada"])

        presenter.reportShown(); drain(service)
        presenter.reportDismissed(); drain(service)

        // Backgrounded past the session timeout but inside the value cache's TTL.
        service.onBackground(); drain(service)
        clock = clock.addingTimeInterval(31)
        service.onForeground(); drain(service)

        XCTAssertEqual(variableFetches(), 2,
                       "a new session must ask the endpoint again")
        XCTAssertEqual(presenter.presentedMessages.map { $0.body }, ["Hi Ada", "Hi Grace"],
                       "the second session served stale values")
    }

    /// A warm resume is not a new session, so it must not spend a request. The distinction is the
    /// whole reason the session timeout exists.
    func testAWarmResumeDoesNotRefetchVariables() {
        variablesTransport.script([.success(variablePayload("Ada")),
                                   .success(variablePayload("Grace"))])
        let source = StubMessageSource(result: .success(result([personalisedCampaign()])))
        let service = makeService(source: source, sessionTimeout: 30)
        service.start()
        drain(service)
        let afterFirst = variableFetches()

        service.onBackground(); drain(service)
        clock = clock.addingTimeInterval(5)      // well inside the timeout
        service.onForeground(); drain(service)

        XCTAssertEqual(variableFetches(), afterFirst)
    }

    /// Already true before this change, and asserted so it stays true: values can change between
    /// two events in one session, which is the case the whole feature exists for.
    func testAnEventRefetchesVariables() {
        variablesTransport.script([.success(variablePayload("Ada")),
                                   .success(variablePayload("Grace"))])
        let campaigns = [personalisedCampaign(1),
                         personalisedCampaign(2, trigger: .event(name: "e", filters: []))]
        let source = StubMessageSource(result: .success(result(campaigns)))
        let service = makeService(source: source)
        service.start()
        drain(service)
        presenter.reportShown(); drain(service)
        presenter.reportDismissed(); drain(service)

        service.onCustomEvent(name: "e", properties: [:])
        drain(service)

        XCTAssertEqual(variableFetches(), 2)
        XCTAssertEqual(presenter.presentedMessages.map { $0.body }, ["Hi Ada", "Hi Grace"])
    }

    /// The cheap path stays cheap: no token, no request, whatever the trigger.
    func testACampaignWithoutTokensNeverAsks() {
        let source = StubMessageSource(result: .success(result([makeCampaign(campaignId: 1)])))
        let service = makeService(source: source)
        service.start()
        drain(service)

        XCTAssertEqual(presenter.presentedMessages.count, 1)
        XCTAssertEqual(variableFetches(), 0)
    }

    /// An empty value is substituted as empty, end to end. The unit-level contract is in
    /// TokenSubstitutionTests; this is the same rule asserted through the service, because that is
    /// where a well-meaning change would most likely reintroduce a fallback.
    func testAnEmptyValueReachesTheMessageAsEmpty() {
        variablesTransport.script([.success(variablePayload(""))])
        let source = StubMessageSource(result: .success(result([personalisedCampaign()])))
        let service = makeService(source: source)
        service.start()
        drain(service)

        XCTAssertEqual(presenter.presentedMessages.first?.body, "Hi ")
    }
}
