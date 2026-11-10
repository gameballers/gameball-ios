import XCTest
@testable import Gameball

final class AppOpenObserverTests: XCTestCase {

    private var clock: Int64 = 1_000_000
    private var opens: [AppOpen] = []
    private lazy var observer = AppOpenObserver(now: { [unowned self] in self.clock }) { [unowned self] in
        self.opens.append($0)
    }

    func testFirstForegroundIsCold() {
        observer.onForeground()

        XCTAssertEqual(opens, [AppOpen(type: "cold", openedAt: 1_000_000)])
    }

    func testReturnAfterTheGapIsWarm() {
        observer.onForeground()
        observer.onBackground()
        clock += 31_000
        observer.onForeground()

        XCTAssertEqual(opens.map { $0.type }, ["cold", "warm"])
        XCTAssertEqual(opens.last?.openedAt, 1_031_000)
    }

    func testReturnWithinTheGapIsNotAnOpen() {
        observer.onForeground()
        observer.onBackground()
        clock += 10_000
        observer.onForeground()

        XCTAssertEqual(opens.count, 1)
    }

    func testReturnAtExactlyTheGapIsNotAnOpen() {
        observer.onForeground()
        observer.onBackground()
        clock += 30_000
        observer.onForeground()

        XCTAssertEqual(opens.count, 1)
    }

    func testActiveAgainWithoutGoingToTheBackgroundIsNotAnOpen() {
        // Control Center, a system alert or the notification shade
        observer.onForeground()
        clock += 60_000
        observer.onForeground()

        XCTAssertEqual(opens.count, 1)
    }

    func testAColdOpenFromATapIsMarked() {
        observer.onTap()
        observer.onForeground()

        XCTAssertEqual(opens, [AppOpen(type: "cold", openedAt: 1_000_000, fromTap: true)])
    }

    func testAWarmOpenFromATapIsMarked() {
        observer.onForeground()
        observer.onBackground()
        clock += 31_000
        observer.onTap()
        observer.onForeground()

        XCTAssertEqual(opens.map { $0.fromTap }, [false, true])
    }

    func testATapWhileOnScreenMarksNothing() {
        observer.onForeground()
        observer.onTap()
        observer.onBackground()
        clock += 31_000
        observer.onForeground()

        XCTAssertEqual(opens.map { $0.fromTap }, [false, false])
    }

    func testATapFromNotificationCenterPulledOverTheAppMarksNothing() {
        // Notification Center over the app only makes it inactive: no background, so still on screen
        observer.onForeground()
        clock += 5_000
        observer.onTap()
        observer.onForeground()
        observer.onBackground()
        clock += 31_000
        observer.onForeground()

        XCTAssertEqual(opens.map { $0.fromTap }, [false, false])
    }

    func testAReturnWithinTheGapUsesUpTheTap() {
        observer.onForeground()
        observer.onBackground()
        clock += 10_000
        observer.onTap()
        observer.onForeground() // back within the gap: not an open, but the tap is spent
        observer.onBackground()
        clock += 31_000
        observer.onForeground()

        XCTAssertEqual(opens.map { $0.fromTap }, [false, false])
    }

    func testATapLongBeforeTheOpenDoesNotMarkIt() {
        observer.onForeground()
        observer.onBackground()
        observer.onTap()
        clock += 2 * 60_000
        observer.onForeground()

        XCTAssertEqual(opens.map { $0.fromTap }, [false, false])
    }

    func testAShortReturnDoesNotMoveTheGap() {
        observer.onForeground()
        observer.onBackground()
        clock += 10_000
        observer.onForeground()
        observer.onBackground()
        clock += 31_000
        observer.onForeground()

        XCTAssertEqual(opens.map { $0.type }, ["cold", "warm"])
    }
}
