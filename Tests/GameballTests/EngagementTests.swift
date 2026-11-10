import XCTest
@testable import Gameball

private final class MemoryStore: ReceivedPushStore {
    var saved: [ReceivedPush] = []
    func load() -> [ReceivedPush] { return saved }
    func save(_ pushes: [ReceivedPush]) { saved = pushes }
}

/// Taps, app opens and the saved list wired together, as the app runs them; asserts on the log
/// lines and on what is sent to push-engagement.
final class EngagementTests: XCTestCase {

    private var clock: Int64 = 1_000_000_000
    // How far the clock moves on every read, so "dated at the open" can't pass by accident
    private var tick: Int64 = 0
    private let minute: Int64 = 60_000
    private let store = MemoryStore()
    private var lines: [String] = []
    private var sent: [(engagement: PushEngagement, sessionToken: String?)] = []
    private lazy var engagement = Engagement(
        store: store,
        now: { [unowned self] in
            defer { self.clock += self.tick }
            return self.clock
        },
        sessionToken: { "global-token" },
        send: { [unowned self] engagement, sessionToken, completion in
            self.sent.append((engagement, sessionToken))
            completion?(true)
        })

    override func setUp() {
        super.setUp()
        engagementLogSink = { [unowned self] line in self.lines.append(line) }
    }

    override func tearDown() {
        engagementLogSink = nil
        super.tearDown()
    }

    // An arrival as the Notification Service Extension records it, into the same store
    private func receive(_ token: String?, key: String? = nil) {
        InfluencedOpens(store: store, now: { [unowned self] in self.clock })
            .onReceived(key: key ?? token ?? "", clickToken: token, sentAt: nil)
    }

    private func tap(_ token: String, sessionToken: String? = nil, completion: ((Bool) -> Void)? = nil) -> Bool {
        let push = GameballPush(payload: ["isGB": "true", "gbClickToken": token])!
        return engagement.onTap(push, sessionToken: sessionToken, completion: completion)
    }

    private var appOpens: [String] { return lines.filter { $0.contains(" app_open ") } }
    private var influencedOpens: [String] { return lines.filter { $0.contains(" influenced_open ") } }
    private var sentTypes: [PushEngagementType] { return sent.map { $0.engagement.type } }

    // MARK: - What is sent

    func testATapSendsClickedWithItsSessionTokenAtTheTimeItIsHandled() {
        var reported: Bool?
        XCTAssertTrue(tap("tok-B", sessionToken: "call-token") { reported = $0 })

        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.engagement.type, .clicked)
        XCTAssertEqual(sent.first?.engagement.clickToken, "tok-B")
        XCTAssertEqual(sent.first?.engagement.occurredAt, 1_000_000_000)
        XCTAssertEqual(sent.first?.sessionToken, "call-token")
        XCTAssertEqual(reported, true, "the caller's completion gets the report's result")
        XCTAssertEqual(lines, ["GameballApp engagement push_click clickToken=tok-B"])
    }

    func testARepeatedTapSendsNothingMore() {
        XCTAssertTrue(tap("tok-B"))
        XCTAssertFalse(tap("tok-B"))

        XCTAssertEqual(sentTypes, [.clicked])
        XCTAssertEqual(lines.filter { $0.contains(" push_click ") }.count, 1)
    }

    func testATapWithoutAClickTokenIsLoggedButNotSent() {
        var called = false
        let push = GameballPush(payload: ["isGB": "true", "gcm.message_id": "m-1"])!
        XCTAssertTrue(engagement.onTap(push, sessionToken: nil) { _ in called = true })

        XCTAssertTrue(sent.isEmpty)
        XCTAssertFalse(called, "as in 4.0.0, no report means no completion")
        XCTAssertEqual(lines, ["GameballApp engagement push_click clickToken=null"])
    }

    func testAnInfluencedOpenSendsInfluencedOpenDatedAtTheOpen() {
        engagement.appDidBecomeActive()
        engagement.appDidEnterBackground()
        receive("tok-A")
        clock += 5 * minute
        tick = 1_000 // every later clock read moves on
        engagement.appDidBecomeActive()

        let openedAt = Int64(appOpens.last?.components(separatedBy: "openedAt=").last?
            .components(separatedBy: " ").first ?? "")
        XCTAssertNotNil(openedAt)
        XCTAssertEqual(influencedOpens.count, 1, "the log line stays")
        XCTAssertEqual(sentTypes, [.influencedOpen])
        XCTAssertEqual(sent.first?.engagement.clickToken, "tok-A")
        // The clock moved on after the open was read, so a send dated "now" would miss this
        XCTAssertEqual(sent.first?.engagement.occurredAt, openedAt)
        XCTAssertEqual(sent.first?.sessionToken, "global-token")
    }

    func testAnInfluencedOpenWithoutAClickTokenIsLoggedButNotSent() {
        engagement.appDidBecomeActive()
        engagement.appDidEnterBackground()
        receive(nil, key: "m-1")
        clock += minute
        engagement.appDidBecomeActive()

        XCTAssertEqual(influencedOpens.count, 1)
        XCTAssertTrue(influencedOpens.first?.contains("clickToken=null") == true)
        XCTAssertTrue(sent.isEmpty)
    }

    func testAppOpensAreNotSent() {
        engagement.appDidBecomeActive()
        engagement.appDidEnterBackground()
        clock += minute
        engagement.appDidBecomeActive()

        XCTAssertEqual(appOpens.count, 2)
        XCTAssertTrue(sent.isEmpty)
    }

    // MARK: - Tap opens are never influenced

    // a. A saved, then B saved and tapped, then the open: a normal click, A is cleared with the rest
    func testAnOpenFromATapIsNeverInfluencedEvenWithAnOlderUntappedPush() {
        engagement.appDidBecomeActive()
        engagement.appDidEnterBackground()
        receive("tok-A")
        clock += 5 * minute
        receive("tok-B")
        clock += 10_000
        XCTAssertTrue(tap("tok-B"))
        XCTAssertFalse(tap("tok-B"), "the same tap reaching the SDK twice counts once")
        clock += 2_000
        engagement.appDidBecomeActive()

        XCTAssertEqual(appOpens.last, "GameballApp engagement app_open type=warm openedAt=\(clock) fromTap=true")
        XCTAssertEqual(influencedOpens, [])
        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertEqual(sentTypes, [.clicked])
    }

    // b. A tap while the app is on screen opens nothing, so the next icon open can still be influenced
    func testATapWhileOnScreenDoesNotStopTheNextIconOpenFromBeingInfluenced() {
        engagement.appDidBecomeActive()
        receive("tok-A")
        clock += 10_000
        XCTAssertTrue(tap("tok-B"))
        clock += 10_000
        engagement.appDidEnterBackground()
        clock += 31_000
        engagement.appDidBecomeActive()

        XCTAssertEqual(appOpens.last, "GameballApp engagement app_open type=warm openedAt=\(clock) fromTap=false")
        XCTAssertEqual(influencedOpens.count, 1)
        XCTAssertTrue(influencedOpens.first?.hasPrefix("GameballApp engagement influenced_open clickToken=tok-A ") == true)
        XCTAssertEqual(sentTypes, [.clicked, .influencedOpen])
        XCTAssertEqual(sent.map { $0.engagement.clickToken }, ["tok-B", "tok-A"])
    }

    // c. A tap followed by a return within 30 s uses the mark up, so a later icon open can be influenced
    func testAReturnWithinTheGapUsesUpTheTapSoALaterIconOpenCanBeInfluenced() {
        engagement.appDidBecomeActive()
        engagement.appDidEnterBackground()
        clock += 5_000
        XCTAssertTrue(tap("tok-T"))
        clock += 2_000
        engagement.appDidBecomeActive() // back within 30 s: not an app_open, but the tap is spent
        engagement.appDidEnterBackground()
        receive("tok-A")
        clock += 40_000
        engagement.appDidBecomeActive()

        XCTAssertEqual(appOpens, [
            "GameballApp engagement app_open type=cold openedAt=1000000000 fromTap=false",
            "GameballApp engagement app_open type=warm openedAt=\(clock) fromTap=false"
        ])
        XCTAssertEqual(influencedOpens.count, 1)
        XCTAssertTrue(influencedOpens.first?.hasPrefix("GameballApp engagement influenced_open clickToken=tok-A ") == true)
        XCTAssertEqual(sentTypes, [.clicked, .influencedOpen])
    }

    // A cold launch from a tap: the tap arrives before the app has ever been active
    func testAColdOpenFromATapIsMarkedAndNotInfluenced() {
        receive("tok-A")
        clock += minute
        XCTAssertTrue(tap("tok-A"))
        clock += 1_000
        engagement.appDidBecomeActive()

        XCTAssertEqual(appOpens, ["GameballApp engagement app_open type=cold openedAt=\(clock) fromTap=true"])
        XCTAssertEqual(influencedOpens, [])
        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertEqual(sentTypes, [.clicked])
    }
}
