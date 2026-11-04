//
//  GameballWidgetViewTests.swift
//  GameballTests
//

import XCTest
import WebKit
@testable import Gameball

/// A script message as the widget's bridge delivers one, without a page to post it.
final class StubScriptMessage: WKScriptMessage {
    private let stubName: String
    private let stubBody: Any

    init(name: String, body: Any) {
        stubName = name
        stubBody = body
        super.init()
    }

    override var name: String { stubName }
    override var body: Any { stubBody }
}

final class GameballWidgetViewTests: XCTestCase {

    private var coordinator: RecordingCoordinator!
    private var failures = 0

    override func setUp() {
        super.setUp()
        coordinator = RecordingCoordinator()
        failures = 0
        iamReduceMotionEnabled = { true }
    }

    override func tearDown() {
        iamReduceMotionEnabled = { UIAccessibility.isReduceMotionEnabled }
        super.tearDown()
    }

    private func game(_ type: GameballMessageType = .modal) -> GameballWidgetView {
        return GameballWidgetView(message: makeGameCampaign(type: type).message,
                                  attributes: .defaults,
                                  url: URL(string: "https://m.gameball.app/?openDetail=details_wheel_9645")!,
                                  coordinator: coordinator,
                                  onFailed: { [weak self] in self?.failures += 1 })
    }

    private func post(_ name: String, _ body: Any, to view: GameballWidgetView) {
        view.userContentController(WKUserContentController(),
                                   didReceive: StubScriptMessage(name: name, body: body))
    }

    // MARK: - Closing

    /// The page's own close is the customer leaving the game: a dismissal, and never a click,
    /// which for a game would be reported against campaign 0.
    func testThePagesOwnCloseIsADismissalNotAClick() {
        let view = game()
        post("GBIamClose", "", to: view)

        XCTAssertTrue(coordinator.clicks.isEmpty, "closing a game reported a click")
        XCTAssertEqual(coordinator.didDismissCount, 1)
    }

    // MARK: - The widget's own events

    /// As the widget posts it. `campaignType` is the widget's own name for the game, not the
    /// sync's (`wheel`), so nothing may be matched on it.
    private let gameCompleted = """
        {"type":"gameCompleted","metadata":{"campaignId":"9645","campaignType":"spinTheWheel"}}
        """

    func testAFinishedGameIsReportedToTheCoordinator() {
        let view = game()
        post("GBIamEvent", gameCompleted, to: view)

        XCTAssertEqual(coordinator.gamesCompleted, 1)
        XCTAssertTrue(coordinator.clicks.isEmpty, "a finished game reported a click")
        XCTAssertEqual(coordinator.didDismissCount, 0, "the game closed over its own result")
    }

    func testAnEventPostedAsAnObjectIsReadToo() {
        let view = game()
        post("GBIamEvent", ["type": "gameCompleted", "metadata": ["campaignId": "9645"]], to: view)
        XCTAssertEqual(coordinator.gamesCompleted, 1)
    }

    func testOtherEventsAreNotAFinishedGame() {
        let view = game()
        post("GBIamEvent", "{\"type\":\"rewardClaimed\",\"metadata\":{}}", to: view)
        post("GBIamEvent", "not json", to: view)
        post("GBIamEvent", "", to: view)

        XCTAssertEqual(coordinator.gamesCompleted, 0)
    }
}
