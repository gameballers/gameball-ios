//
//  MessageEventTests.swift
//  GameballTests
//

import XCTest
@testable import Gameball

final class MessageEventTests: XCTestCase {

    private let occurred = Date(timeIntervalSince1970: 1_755_597_600) // 2025-08-19T10:00:00Z

    private func makeEvent(type: MessageEventType = .impression,
                           variationId: Int? = 20,
                           dispatchId: String? = "dispatch-1",
                           buttonId: String? = nil,
                           url: String? = nil) -> MessageEvent {
        return MessageEvent(campaignId: 2055,
                            variationId: variationId,
                            dispatchId: dispatchId,
                            type: type,
                            occurredAt: occurred,
                            buttonId: buttonId,
                            url: url)
    }

    // MARK: - Identity

    /// A non-GUID is a hard 400 that discards the *entire* batch rather than one event, so
    /// this shape assertion exists to stop a future refactor breaking ingestion silently.
    func testEventUidIsALowercasedV4UUID() {
        let pattern = "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
        let regex = try! NSRegularExpression(pattern: pattern)

        for _ in 0..<50 {
            let uid = MessageEvent.newEventUid()
            let range = NSRange(uid.startIndex..<uid.endIndex, in: uid)
            XCTAssertNotNil(regex.firstMatch(in: uid, options: [], range: range),
                            "\(uid) is not a lowercased v4 UUID")
        }
    }

    func testEachEventGetsItsOwnUid() {
        XCTAssertNotEqual(makeEvent().eventUid, makeEvent().eventUid)
    }

    func testASuppliedUidIsHonoured() {
        let event = MessageEvent(campaignId: 1, variationId: nil, dispatchId: nil,
                                 type: .click, occurredAt: occurred,
                                 eventUid: "11111111-1111-4111-8111-111111111111")
        XCTAssertEqual(event.eventUid, "11111111-1111-4111-8111-111111111111")
    }

    // MARK: - Wire shape

    func testWireDictionaryCarriesTheRequiredFields() {
        let json = makeEvent().wireDictionary()
        XCTAssertEqual(json["campaignId"] as? Int, 2055)
        XCTAssertEqual(json["variationId"] as? Int, 20)
        XCTAssertEqual(json["dispatchId"] as? String, "dispatch-1")
        XCTAssertEqual(json["type"] as? String, "impression")
        XCTAssertNotNil(json["eventUid"] as? String)
    }

    /// Device time, never send time. Events can arrive hours late, and conversion windows
    /// and per-day unique-impression counts are anchored to this field.
    func testOccurredAtSerialisesAsISO8601UTC() {
        XCTAssertEqual(makeEvent().wireDictionary()["occurredAt"] as? String,
                       "2025-08-19T10:00:00Z")
    }

    func testEveryEventTypeHasItsWireName() {
        XCTAssertEqual(makeEvent(type: .impression).wireDictionary()["type"] as? String, "impression")
        XCTAssertEqual(makeEvent(type: .click).wireDictionary()["type"] as? String, "click")
        XCTAssertEqual(makeEvent(type: .dismiss).wireDictionary()["type"] as? String, "dismiss")
    }

    /// Optional fields are omitted rather than sent as null, so a click without a button and
    /// a click on an unknown button are not conflated server-side.
    func testOptionalFieldsAreOmittedWhenNil() {
        let json = makeEvent(variationId: nil, dispatchId: nil).wireDictionary()
        XCTAssertNil(json["variationId"])
        XCTAssertNil(json["dispatchId"])
        XCTAssertNil(json["buttonId"])
        XCTAssertNil(json["url"])
    }

    func testOptionalFieldsArePresentWhenSet() {
        let json = makeEvent(buttonId: "cta", url: "https://example.com").wireDictionary()
        XCTAssertEqual(json["buttonId"] as? String, "cta")
        XCTAssertEqual(json["url"] as? String, "https://example.com")
    }

    func testWireDictionaryIsJSONSerialisable() {
        XCTAssertTrue(JSONSerialization.isValidJSONObject(
            makeEvent(buttonId: "cta", url: "https://example.com").wireDictionary()))
    }

    // MARK: - Persistence

    func testEventRoundTripsThroughCodable() {
        let event = makeEvent(type: .click, buttonId: "cta", url: "https://example.com")
        let encoded = try! JSONEncoder().encode(event)
        let decoded = try! JSONDecoder().decode(MessageEvent.self, from: encoded)

        XCTAssertEqual(decoded.eventUid, event.eventUid)
        XCTAssertEqual(decoded.campaignId, event.campaignId)
        XCTAssertEqual(decoded.variationId, event.variationId)
        XCTAssertEqual(decoded.dispatchId, event.dispatchId)
        XCTAssertEqual(decoded.type, event.type)
        XCTAssertEqual(decoded.occurredAt.timeIntervalSince1970,
                       event.occurredAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(decoded.buttonId, event.buttonId)
        XCTAssertEqual(decoded.url, event.url)
    }
}
