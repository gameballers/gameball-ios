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

/// A navigation as WebKit hands one to its delegate, without a page to start it.
final class StubNavigationAction: WKNavigationAction {
    private let stubRequest: URLRequest

    init(_ link: String) {
        stubRequest = URLRequest(url: URL(string: link)!)
        super.init()
    }

    override var request: URLRequest { stubRequest }
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

    private func hosted(_ view: GameballWidgetView) -> IAMLayoutHost {
        let host = IAMLayoutHost(size: CGSize(width: 375, height: 667))
        host.install(view)
        return host
    }

    private func descendants(of view: UIView) -> [UIView] {
        return view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }

    private func closeButton(in view: UIView) -> MessageCloseButton? {
        return descendants(of: view).compactMap { $0 as? MessageCloseButton }.first
    }

    private func webView(in view: UIView) -> WKWebView? {
        return view.subviews.compactMap { $0 as? WKWebView }.first
    }

    /// The control behind a modal game that closes it — any control but the close button.
    private func scrim(in view: UIView) -> UIControl? {
        return view.subviews.compactMap { $0 as? UIControl }.first { !($0 is MessageCloseButton) }
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

    /// The widget draws no close or back control for a game on mobile, so the SDK draws its own
    /// over every game: in the top-end corner, inside the safe area, at least 44pt, labelled.
    func testEveryGameHasACloseButtonInItsTopEndCorner() {
        for type in [GameballMessageType.modal, .fullscreen] {
            let view = game(type)
            let host = hosted(view)
            guard let close = closeButton(in: view), let web = webView(in: view) else {
                XCTFail("a \(type) game has no close button")
                continue
            }
            let button = close.convert(close.bounds, to: view)
            let content = web.convert(web.bounds, to: view)

            XCTAssertEqual(close.accessibilityLabel, MessageCloseButton.accessibilityLabel())
            XCTAssertGreaterThanOrEqual(button.width, 44, "\(type)")
            XCTAssertGreaterThanOrEqual(button.height, 44, "\(type)")
            XCTAssertTrue(view.bounds.inset(by: view.safeAreaInsets).contains(button),
                          "\(type): \(button) is outside the safe area")
            XCTAssertEqual(button.minY, content.minY, accuracy: 8, "\(type): not at the top")
            XCTAssertEqual(button.maxX, content.maxX, accuracy: 8, "\(type): not at the end")
            withExtendedLifetime(host) {}
        }
    }

    /// Whatever the campaign says: without it a fullscreen game could only be left by leaving
    /// the app.
    func testAGameGetsACloseButtonEvenWhenTheCampaignAsksForNone() {
        let message = makeMessage(widget: GameballWidgetContent(gameCampaignId: 9645,
                                                                gameCampaignType: "wheel"),
                                  type: .fullscreen, header: nil, body: nil,
                                  showCloseButton: false)
        let view = GameballWidgetView(message: message, attributes: .defaults,
                                      url: URL(string: "https://m.gameball.app")!,
                                      coordinator: coordinator, onFailed: nil)
        XCTAssertNotNil(closeButton(in: view))
    }

    func testTheCloseButtonDismissesWithoutAClick() {
        let view = game()
        let host = hosted(view)
        guard let close = closeButton(in: view) else { return XCTFail("no close button") }
        simulateTap(close)

        XCTAssertEqual(coordinator.didDismissCount, 1)
        XCTAssertTrue(coordinator.clicks.isEmpty, "closing a game reported a click")
        withExtendedLifetime(host) {}
    }

    /// The close button, the scrim, the page's own close and a failed load can each ask. A second
    /// dismissal would reach the presenter after it had moved on to whatever shows next.
    func testAGameIsDismissedOnceHoweverOftenItIsAsked() {
        let view = game()
        let host = hosted(view)
        guard let close = closeButton(in: view) else { return XCTFail("no close button") }
        simulateTap(close)
        post("GBIamClose", "", to: view)

        XCTAssertEqual(coordinator.didDismissCount, 1)
        withExtendedLifetime(host) {}
    }

    // MARK: - The scrim

    func testATapOnTheScrimClosesAModalGame() {
        let view = game(.modal)
        let host = hosted(view)
        guard let scrim = scrim(in: view) else { return XCTFail("a modal game has no scrim") }
        simulateTap(scrim)

        XCTAssertEqual(coordinator.didDismissCount, 1)
        XCTAssertTrue(coordinator.clicks.isEmpty)
        withExtendedLifetime(host) {}
    }

    /// Behind the game, so a tap on the game itself never reaches it.
    func testTheScrimSitsBehindTheGame() {
        let view = game(.modal)
        guard let scrim = scrim(in: view), let web = webView(in: view),
              let scrimIndex = view.subviews.firstIndex(of: scrim),
              let webIndex = view.subviews.firstIndex(of: web) else {
            return XCTFail("a modal game has no scrim")
        }
        XCTAssertLessThan(scrimIndex, webIndex)
    }

    /// A fullscreen game fills the screen: there is no outside to tap.
    func testAFullscreenGameHasNoScrim() {
        XCTAssertNil(scrim(in: game(.fullscreen)))
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

    // MARK: - Links

    /// A game whose outside links are recorded rather than opened. `widget` is the page it opens.
    private func linkingGame(widget: String = "https://m.gameball.app/?openDetail=details_wheel_9645",
                             opened: @escaping (URL) -> Void) -> GameballWidgetView {
        return GameballWidgetView(message: makeGameCampaign().message,
                                  attributes: .defaults,
                                  url: URL(string: widget)!,
                                  coordinator: coordinator,
                                  onFailed: nil,
                                  openOutside: opened)
    }

    private func policy(for link: String, in view: GameballWidgetView) -> WKNavigationActionPolicy? {
        var decided: WKNavigationActionPolicy?
        (view as WKNavigationDelegate).webView?(WKWebView(),
                                                decidePolicyFor: StubNavigationAction(link),
                                                decisionHandler: { decided = $0 })
        return decided
    }

    /// As in the profile widget: a link to anywhere but Gameball leaves the game for the device
    /// browser, and the game stays where it was.
    func testALinkToAnotherSiteOpensOutsideTheGame() {
        var opened: [URL] = []
        let view = linkingGame { opened.append($0) }

        XCTAssertEqual(policy(for: "https://example.com/offer?ref=game", in: view), .cancel)
        XCTAssertEqual(opened, [URL(string: "https://example.com/offer?ref=game")!])
        XCTAssertEqual(coordinator.didDismissCount, 0)
    }

    /// A look-alike host is not Gameball.
    func testALookAlikeHostOpensOutsideTheGame() {
        var opened: [URL] = []
        let view = linkingGame { opened.append($0) }

        XCTAssertEqual(policy(for: "https://evilgameball.app/", in: view), .cancel)
        XCTAssertEqual(opened.count, 1)
    }

    /// The widget's own pages, its frames, and the host it was configured on all load in place.
    func testTheWidgetsOwnPagesStayInTheGame() {
        var opened: [URL] = []
        let view = linkingGame(widget: "https://widget.staging.example/?openDetail=details_wheel_9645") {
            opened.append($0)
        }

        for link in ["https://widget.staging.example/next",
                     "https://m.gameball.app/details",
                     "https://gameball.app/",
                     "https://alpha.gameball.app/challenge",
                     "about:srcdoc",
                     "about:blank"] {
            XCTAssertEqual(policy(for: link, in: view), .allow, link)
        }
        XCTAssertTrue(opened.isEmpty, "\(opened)")
    }
}
