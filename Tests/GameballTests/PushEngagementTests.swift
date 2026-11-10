import XCTest
@testable import Gameball

final class PushEngagementTests: XCTestCase {

    func testTheTypesKeepTheBackendsNumbers() {
        XCTAssertEqual(PushEngagementType.clicked.rawValue, 1)
        XCTAssertEqual(PushEngagementType.dismissed.rawValue, 2)
        XCTAssertEqual(PushEngagementType.influencedOpen.rawValue, 3)
    }

    func testTheBodyHasTheFourFields() {
        let body = PushEngagement(clickToken: "tok-1", type: .influencedOpen, occurredAt: 1_000_000_000_007, eventUid: "uid-1").body

        XCTAssertEqual(Set(body.keys), ["clickToken", "engagementType", "eventUid", "occurredAt"])
        XCTAssertEqual(body["clickToken"] as? String, "tok-1")
        XCTAssertEqual(body["engagementType"] as? Int, 3)
        XCTAssertEqual(body["eventUid"] as? String, "uid-1")
        XCTAssertEqual(body["occurredAt"] as? String, "2001-09-09T01:46:40.007Z")
    }

    func testEveryEventGetsAFreshUid() {
        let first = PushEngagement(clickToken: "tok-1", type: .clicked, occurredAt: 5)
        let second = PushEngagement(clickToken: "tok-1", type: .clicked, occurredAt: 5)

        XCTAssertNotEqual(first.eventUid, second.eventUid)
        XCTAssertNotNil(UUID(uuidString: first.eventUid))
        XCTAssertNotNil(UUID(uuidString: second.eventUid))
    }

    func testOccurredAtIsUtcIsoWithMilliseconds() {
        XCTAssertEqual(PushEngagement.isoTimestamp(0), "1970-01-01T00:00:00.000Z")
        XCTAssertEqual(PushEngagement.isoTimestamp(1_000_000_000_007), "2001-09-09T01:46:40.007Z")
        XCTAssertEqual(PushEngagement.isoTimestamp(1_700_000_000_999), "2023-11-14T22:13:20.999Z")
        XCTAssertEqual(PushEngagement.isoTimestamp(1_794_232_640_807), "2026-11-09T13:57:20.807Z")
    }

    func testTheRequestPostsTheBodyToPushEngagement() throws {
        let engagement = PushEngagement(clickToken: "tok-1", type: .clicked, occurredAt: 1_794_232_640_807, eventUid: "uid-1")
        let request = NetworkManager.shared().pushEngagementRequest(engagement, sessionToken: nil)

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v4.0/integrations/mobile/push-engagement")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["clickToken"] as? String, "tok-1")
        XCTAssertEqual(json["eventUid"] as? String, "uid-1")
        XCTAssertEqual(json["occurredAt"] as? String, "2026-11-09T13:57:20.807Z")
        // A JSON number, not a string
        XCTAssertEqual((json["engagementType"] as? NSNumber)?.intValue, 1)
        XCTAssertFalse(json["engagementType"] is String)
        XCTAssertTrue(String(data: body, encoding: .utf8)?.contains("\"engagementType\":1") == true)
    }

    func testEachTypeSendsItsNumber() throws {
        for (type, number) in [(PushEngagementType.clicked, 1), (.dismissed, 2), (.influencedOpen, 3)] {
            let request = NetworkManager.shared().pushEngagementRequest(
                PushEngagement(clickToken: "tok-1", type: type, occurredAt: 0), sessionToken: nil)
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual((json["engagementType"] as? NSNumber)?.intValue, number)
        }
    }
}
