//
//  ArtworkPrefetcherTests.swift
//  GameballTests
//

import XCTest
@testable import Gameball

/// Serves artwork per URL, with an optional delay, and can hang a request forever.
final class IAMImageStub: URLProtocol {

    struct Reply {
        var data: Data?
        var delay: TimeInterval = 0
        var hangs = false
        var status = 200
    }

    private static let lock = NSLock()
    private static var replies: [String: Reply] = [:]
    private static var requested: [String] = []

    static func reset() {
        lock.lock()
        replies = [:]
        requested = []
        lock.unlock()
    }

    static func set(_ reply: Reply, for url: String) {
        lock.lock(); replies[url] = reply; lock.unlock()
    }

    static var requestedURLs: [String] {
        lock.lock(); defer { lock.unlock() }
        return requested
    }

    static func session(timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IAMImageStub.self]
        configuration.timeoutIntervalForRequest = timeout
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { return true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { return request }

    override func startLoading() {
        let key = request.url?.absoluteString ?? ""
        IAMImageStub.lock.lock()
        IAMImageStub.requested.append(key)
        let reply = IAMImageStub.replies[key]
        IAMImageStub.lock.unlock()

        guard let found = reply else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain,
                                                               code: NSURLErrorFileDoesNotExist,
                                                               userInfo: nil))
            return
        }
        if found.hangs { return }   // never answers; the prefetcher's bound must save us

        let deliver = { [weak self] in
            guard let self = self, let url = self.request.url else { return }
            if let response = HTTPURLResponse(url: url, statusCode: found.status,
                                             httpVersion: "HTTP/1.1", headerFields: nil) {
                self.client?.urlProtocol(self, didReceive: response,
                                         cacheStoragePolicy: .notAllowed)
            }
            if let data = found.data { self.client?.urlProtocol(self, didLoad: data) }
            self.client?.urlProtocolDidFinishLoading(self)
        }

        if found.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + found.delay, execute: deliver)
        } else {
            deliver()
        }
    }

    override func stopLoading() {}
}

/// A small opaque PNG, so `UIImage(data:)` actually decodes something.
func makePNGData(size: CGSize = CGSize(width: 4, height: 4)) -> Data {
    UIGraphicsBeginImageContextWithOptions(size, false, 1)
    UIColor.red.setFill()
    UIRectFill(CGRect(origin: .zero, size: size))
    let image = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return image?.pngData() ?? Data()
}

final class ArtworkPrefetcherTests: XCTestCase {

    private let png = makePNGData()

    override func setUp() {
        super.setUp()
        IAMImageStub.reset()
    }

    override func tearDown() {
        IAMImageStub.reset()
        super.tearDown()
    }

    private func makePrefetcher(timeout: TimeInterval = 5) -> ArtworkPrefetcher {
        return ArtworkPrefetcher(session: IAMImageStub.session(timeout: timeout), timeout: timeout)
    }

    private func warm(_ prefetcher: ArtworkPrefetcher,
                      _ campaigns: [InAppMessageCampaign],
                      timeout: TimeInterval = 5) {
        let done = expectation(description: "warm completed")
        prefetcher.warm(campaigns: campaigns) { done.fulfill() }
        wait(for: [done], timeout: timeout)
    }

    private func campaign(_ id: Int, image: String?, icon: String? = nil) -> InAppMessageCampaign {
        return makeCampaign(campaignId: id,
                            message: makeMessage(id: "\(id)",
                                                 imageURL: image.flatMap { URL(string: $0) },
                                                 iconURL: icon.flatMap { URL(string: $0) }))
    }

    // MARK: - Coverage

    /// An event trigger fires with no warning and no time to fetch, so the whole set is
    /// warmed rather than the one campaign that happens to be first.
    func testEveryCampaignIsWarmedNotJustTheFirst() {
        let urls = (0..<5).map { "https://example.com/image\($0).png" }
        for url in urls { IAMImageStub.set(.init(data: png), for: url) }

        let campaigns = urls.enumerated().map { campaign($0.offset, image: $0.element) }
        let prefetcher = makePrefetcher()
        warm(prefetcher, campaigns)

        for campaign in campaigns {
            XCTAssertTrue(prefetcher.isReady(campaign),
                          "campaign \(campaign.campaignId) was not warmed")
        }
        XCTAssertEqual(Set(IAMImageStub.requestedURLs), Set(urls))
    }

    func testBothImageAndIconAreWarmed() {
        IAMImageStub.set(.init(data: png), for: "https://example.com/hero.png")
        IAMImageStub.set(.init(data: png), for: "https://example.com/icon.png")

        let target = campaign(1, image: "https://example.com/hero.png",
                              icon: "https://example.com/icon.png")
        let prefetcher = makePrefetcher()
        warm(prefetcher, [target])

        XCTAssertTrue(prefetcher.isReady(target))
        XCTAssertNotNil(prefetcher.image(for: URL(string: "https://example.com/icon.png")!))
    }

    func testTheSameURLIsFetchedOnlyOnce() {
        IAMImageStub.set(.init(data: png), for: "https://example.com/shared.png")

        let prefetcher = makePrefetcher()
        warm(prefetcher, [campaign(1, image: "https://example.com/shared.png"),
                          campaign(2, image: "https://example.com/shared.png")])

        XCTAssertEqual(IAMImageStub.requestedURLs.count, 1,
                       "a shared URL was fetched more than once")
    }

    // MARK: - Readiness

    /// Artwork that failed to load must not report ready, or the view draws a broken frame.
    func testFailedLoadIsNotReady() {
        // No stub reply registered, so the request errors.
        let target = campaign(1, image: "https://example.com/missing.png")
        let prefetcher = makePrefetcher()
        warm(prefetcher, [target])
        XCTAssertFalse(prefetcher.isReady(target))
    }

    func testNonImageBytesAreNotReady() {
        IAMImageStub.set(.init(data: Data("this is not a png".utf8)),
                         for: "https://example.com/bogus.png")
        let target = campaign(1, image: "https://example.com/bogus.png")
        let prefetcher = makePrefetcher()
        warm(prefetcher, [target])
        XCTAssertFalse(prefetcher.isReady(target))
    }

    /// A text-only campaign has nothing to wait for and must never be held back.
    func testCampaignWithNoArtworkIsReady() {
        let target = campaign(1, image: nil)
        let prefetcher = makePrefetcher()
        XCTAssertTrue(prefetcher.isReady(target), "ready even before warming")
        warm(prefetcher, [target])
        XCTAssertTrue(prefetcher.isReady(target))
    }

    func testReadinessIsFalseBeforeWarming() {
        IAMImageStub.set(.init(data: png), for: "https://example.com/hero.png")
        let target = campaign(1, image: "https://example.com/hero.png")
        XCTAssertFalse(makePrefetcher().isReady(target))
    }

    // MARK: - Concurrency

    /// Eight 300ms loads run together. Serially this would take at least 2.4s.
    func testLoadsRunConcurrently() {
        let urls = (0..<8).map { "https://example.com/slow\($0).png" }
        for url in urls { IAMImageStub.set(.init(data: png, delay: 0.3), for: url) }

        let campaigns = urls.enumerated().map { campaign($0.offset, image: $0.element) }
        let prefetcher = makePrefetcher()

        let started = Date()
        warm(prefetcher, campaigns, timeout: 10)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertLessThan(elapsed, 1.5, "loads appear to be serial (took \(elapsed)s)")
        for campaign in campaigns { XCTAssertTrue(prefetcher.isReady(campaign)) }
    }

    // MARK: - Timeout

    /// A hung load must not stall the session forever, and its campaign must not be ready.
    func testHungLoadIsBoundedAndNotReady() {
        IAMImageStub.set(.init(data: nil, hangs: true), for: "https://example.com/hangs.png")
        IAMImageStub.set(.init(data: png), for: "https://example.com/fine.png")

        let hung = campaign(1, image: "https://example.com/hangs.png")
        let fine = campaign(2, image: "https://example.com/fine.png")
        let prefetcher = makePrefetcher(timeout: 0.5)

        let started = Date()
        warm(prefetcher, [hung, fine], timeout: 8)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertLessThan(elapsed, 5, "the hung load was not bounded (took \(elapsed)s)")
        XCTAssertFalse(prefetcher.isReady(hung))
        XCTAssertTrue(prefetcher.isReady(fine), "one hung load must not block the others")
    }

    func testWarmWithNoCampaignsCallsBackImmediately() {
        let prefetcher = makePrefetcher()
        let done = expectation(description: "warm completed")
        prefetcher.warm(campaigns: []) { done.fulfill() }
        wait(for: [done], timeout: 1)
    }

    // MARK: - Reset

    /// Reset clears readiness so the next sync re-evaluates rather than trusting a cache
    /// entry for a campaign that may have changed its artwork.
    func testResetClearsReadiness() {
        IAMImageStub.set(.init(data: png), for: "https://example.com/hero.png")
        let target = campaign(1, image: "https://example.com/hero.png")
        let prefetcher = makePrefetcher()
        warm(prefetcher, [target])
        XCTAssertTrue(prefetcher.isReady(target))

        prefetcher.reset()
        XCTAssertFalse(prefetcher.isReady(target))
        XCTAssertNil(prefetcher.image(for: URL(string: "https://example.com/hero.png")!))
    }

    /// The property that made the `failed` set unnecessary, and which was an untested inference
    /// when IAM-7 was filed: a URL that failed is retried on the **next warm**, with no reset in
    /// between. `load` consults the image cache only, and a failure puts nothing in it.
    ///
    /// This is the behaviour the module wants — a failure is more often the network than the
    /// asset — so recording failures in order to skip them later would have contradicted it.
    func testAFailedURLIsRetriedOnTheNextWarm() {
        let target = campaign(1, image: "https://example.com/flaky.png")
        let prefetcher = makePrefetcher()

        warm(prefetcher, [target])
        XCTAssertFalse(prefetcher.isReady(target), "no reply was set, so the load fails")
        let afterFirst = IAMImageStub.requestedURLs.filter { $0.hasSuffix("flaky.png") }.count
        XCTAssertEqual(afterFirst, 1)

        // Same prefetcher, no reset. The asset is now available.
        IAMImageStub.set(.init(data: png), for: "https://example.com/flaky.png")
        warm(prefetcher, [target])

        XCTAssertTrue(prefetcher.isReady(target), "the retry must be allowed to succeed")
        XCTAssertEqual(IAMImageStub.requestedURLs.filter { $0.hasSuffix("flaky.png") }.count, 2,
                       "the second warm must actually re-request it")
    }

    /// The complement: a URL that succeeded is *not* re-requested on the next warm, so the retry
    /// above is a property of failure rather than the cache being ignored altogether.
    func testASucceededURLIsNotRefetchedOnTheNextWarm() {
        IAMImageStub.set(.init(data: png), for: "https://example.com/hero.png")
        let target = campaign(1, image: "https://example.com/hero.png")
        let prefetcher = makePrefetcher()

        warm(prefetcher, [target])
        warm(prefetcher, [target])

        XCTAssertEqual(IAMImageStub.requestedURLs.filter { $0.hasSuffix("hero.png") }.count, 1)
        XCTAssertTrue(prefetcher.isReady(target))
    }

    /// A previously failed URL is retried after a reset — the failure may have been the
    /// network rather than the asset.
    func testResetAllowsAFailedURLToBeRetried() {
        let target = campaign(1, image: "https://example.com/flaky.png")
        let prefetcher = makePrefetcher()
        warm(prefetcher, [target])
        XCTAssertFalse(prefetcher.isReady(target))

        prefetcher.reset()
        IAMImageStub.set(.init(data: png), for: "https://example.com/flaky.png")
        warm(prefetcher, [target])
        XCTAssertTrue(prefetcher.isReady(target))
    }
}
