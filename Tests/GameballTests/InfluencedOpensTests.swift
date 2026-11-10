import XCTest
@testable import Gameball

private final class MemoryStore: ReceivedPushStore {
    var saved: [ReceivedPush] = []
    func load() -> [ReceivedPush] { return saved }
    func save(_ pushes: [ReceivedPush]) { saved = pushes }
}

final class InfluencedOpensTests: XCTestCase {

    private var clock: Int64 = 1_000_000_000
    private let minute: Int64 = 60_000
    private let store = MemoryStore()
    private lazy var influenced = InfluencedOpens(store: store, now: { [unowned self] in self.clock })

    private func receive(_ token: String) {
        influenced.onReceived(key: token, clickToken: token, sentAt: clock - 500)
    }

    private func open() -> ReceivedPush? {
        return influenced.influencedBy(AppOpen(type: AppOpenObserver.typeWarm, openedAt: clock))
    }

    func testOpenWithinTheWindowOfAnUntappedPushIsInfluenced() {
        receive("tok-1")
        clock += 10 * minute
        let push = open()
        XCTAssertEqual(push?.clickToken, "tok-1")
        XCTAssertEqual(push?.receivedAt, 1_000_000_000)
        XCTAssertEqual(push?.sentAt, 999_999_500)
    }

    func testOpenAfterTheWindowIsNotInfluenced() {
        receive("tok-1")
        clock += 31 * minute
        XCTAssertNil(open())
    }

    func testOpenAtExactlyTheWindowIsInfluenced() {
        receive("tok-1")
        clock += 30 * minute
        XCTAssertEqual(open()?.clickToken, "tok-1")
    }

    func testTappedPushNeverCountsAsInfluenced() {
        receive("tok-1")
        clock += minute
        influenced.onTap(key: "tok-1")
        XCTAssertNil(open())
    }

    func testTheMostRecentPushGetsTheCredit() {
        receive("tok-1")
        clock += 5 * minute
        receive("tok-2")
        clock += 5 * minute
        XCTAssertEqual(open()?.clickToken, "tok-2")
    }

    func testAnOldLatestPushGivesNoCreditEvenWithNoFallback() {
        receive("tok-1")
        clock += 1
        receive("tok-2")
        clock += 31 * minute
        XCTAssertNil(open())
    }

    func testAnOpenClearsTheSavedPushes() {
        receive("tok-1")
        clock += minute
        _ = open()
        clock += minute
        XCTAssertNil(open())
        XCTAssertTrue(store.saved.isEmpty)
    }

    func testOpenWithNoPushIsNotInfluenced() {
        XCTAssertNil(open())
    }

    func testTheSamePushDeliveredTwiceIsSavedOnce() {
        receive("tok-1")
        receive("tok-1")
        XCTAssertEqual(store.saved.count, 1)
    }

    func testAtMostTwentyPushesAreKept() {
        for i in 0..<25 {
            receive("tok-\(i)")
            clock += 1
        }
        XCTAssertEqual(store.saved.count, InfluencedOpens.maxSaved)
        XCTAssertEqual(store.saved.last?.clickToken, "tok-24")
    }

    func testAnOpenFromATapIsNeverInfluencedEvenWithAnOlderUntappedPush() {
        receive("tok-A")
        clock += 5 * minute
        receive("tok-B")
        influenced.onTap(key: "tok-B")
        XCTAssertNil(influenced.influencedBy(AppOpen(type: AppOpenObserver.typeWarm, openedAt: clock, fromTap: true)))
        XCTAssertTrue(store.saved.isEmpty)
    }

    func testClearForgetsEverything() {
        receive("tok-1")
        influenced.clear()
        XCTAssertNil(open())
    }
}

final class GameballPushTests: XCTestCase {

    func testGameballPushIsReadCaseInsensitively() {
        let push = GameballPush(payload: ["isGB": "TRUE", "gbClickToken": "tok-1", "gcm.message_id": "m-1"])
        XCTAssertEqual(push?.clickToken, "tok-1")
        XCTAssertEqual(push?.key, "tok-1")
    }

    func testOtherPushesAreIgnored() {
        XCTAssertNil(GameballPush(payload: ["gbClickToken": "tok-1"]))
        XCTAssertNil(GameballPush(payload: ["isGB": "false", "gbClickToken": "tok-1"]))
    }

    func testWithoutATokenTheMessageIdIsTheKey() {
        let push = GameballPush(payload: ["isGB": "true", "gcm.message_id": "m-1"])
        XCTAssertNil(push?.clickToken)
        XCTAssertEqual(push?.key, "m-1")
    }

    func testSentAtComesFromFCMsSendTime() {
        XCTAssertEqual(GameballPush(payload: ["isGB": "true", "google.c.a.ts": "1700000000"])?.sentAt, 1_700_000_000_000)
        XCTAssertNil(GameballPush(payload: ["isGB": "true"])?.sentAt)
    }

    func testReceivedPushesSurviveInDefaults() {
        let group = "test.gameball.\(UUID().uuidString)"
        ReceivedPushes(appGroup: group).save([ReceivedPush(key: "k", clickToken: nil, sentAt: nil, receivedAt: 5)])
        XCTAssertEqual(ReceivedPushes(appGroup: group).load(), [ReceivedPush(key: "k", clickToken: nil, sentAt: nil, receivedAt: 5)])
        ReceivedPushes(appGroup: group).save([])
        XCTAssertTrue(ReceivedPushes(appGroup: group).load().isEmpty)
    }

    func testLogLineFormat() {
        XCTAssertEqual(engagementLine("influenced_open", [("clickToken", "tok-1"), ("sentAt", nil as Int64?), ("receivedAt", Int64(5))]),
                       "GameballApp engagement influenced_open clickToken=tok-1 sentAt=null receivedAt=5")
    }
}
