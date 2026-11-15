//
//  QuietHoursTests.swift
//  GameballTests
//
//  The backend sends the quiet window as two UTC wall-clock strings. Everything here
//  pins down what that means, because the failure mode is silent: a window evaluated
//  against the wrong clock still suppresses messages, just at the wrong time of day,
//  and no error surfaces to say so.
//

import XCTest
@testable import Gameball

final class QuietHoursTests: XCTestCase {

    /// A fixed instant, named by the wall clock of the machine running the suite. The
    /// window is judged on the device's own clock (decided with product 2026-09-05), so
    /// a local literal is what keeps these assertions machine-independent: 23:00 local
    /// is inside a 22:00–08:00 window in Cairo and in Los Angeles alike.
    private func local(_ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 24
        components.hour = hour; components.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar.date(from: components)!
    }

    // MARK: - Parsing the wire shape

    /// `start` and `end` are the names the live backend uses. This test is the contract:
    /// an earlier draft of the suite assumed `from`/`to`, which parse to nothing.
    func testParsesTheLiveWireShape() {
        let quiet = QuietHours(json: ["enabled": true, "start": "22:00", "end": "08:00"])
        XCTAssertNotNil(quiet)
        XCTAssertTrue(quiet!.enabled)
        XCTAssertEqual(quiet!.start.minutesSinceMidnight, 22 * 60)
        XCTAssertEqual(quiet!.end.minutesSinceMidnight, 8 * 60)
    }

    func testParsesADisabledWindow() {
        let quiet = QuietHours(json: ["enabled": false, "start": "22:00", "end": "08:00"])
        XCTAssertNotNil(quiet, "a disabled window still parses; it just never suppresses")
        XCTAssertFalse(quiet!.enabled)
    }

    /// `enabled` absent means the backend did not opt this account in.
    func testMissingEnabledDefaultsToOff() {
        let quiet = QuietHours(json: ["start": "22:00", "end": "08:00"])
        XCTAssertEqual(quiet?.enabled, false)
    }

    func testSecondsInTheBoundaryAreAccepted() {
        let quiet = QuietHours(json: ["enabled": true, "start": "22:30:45", "end": "08:15:00"])
        XCTAssertEqual(quiet?.start.minutesSinceMidnight, 22 * 60 + 30)
        XCTAssertEqual(quiet?.end.minutesSinceMidnight, 8 * 60 + 15)
    }

    /// Every one of these is a window the SDK cannot honour. Returning `nil` is what makes
    /// the caller fall through to "not quiet" rather than guess at a boundary.
    func testUnusableWindowsYieldNil() {
        let cases: [[String: Any]] = [
            ["enabled": true, "start": "22:00"],                     // no end
            ["enabled": true, "end": "08:00"],                       // no start
            ["enabled": true, "start": "2200", "end": "08:00"],       // no separator
            ["enabled": true, "start": "25:00", "end": "08:00"],      // hour out of range
            ["enabled": true, "start": "22:60", "end": "08:00"],      // minute out of range
            ["enabled": true, "start": "-1:00", "end": "08:00"],      // negative
            ["enabled": true, "start": "", "end": "08:00"],           // empty
            ["enabled": true, "start": "ten", "end": "08:00"],        // not numeric
            ["enabled": true, "start": 2200, "end": "08:00"]          // not a string
        ]
        for json in cases {
            XCTAssertNil(QuietHours(json: json), "should not parse: \(json)")
        }
    }

    func testMidnightBoundariesAreValid() {
        XCTAssertEqual(QuietHours(json: ["enabled": true, "start": "00:00", "end": "23:59"])?
                        .start.minutesSinceMidnight, 0)
        XCTAssertEqual(QuietHours(json: ["enabled": true, "start": "00:00", "end": "24:00"])?
                        .end.minutesSinceMidnight, 24 * 60,
                       "24:00 is midnight-at-the-end and the only hour above 23 worth accepting")
    }

    // MARK: - The window itself

    /// Half-open on purpose: a window of 22:00–08:00 that included 08:00 would suppress
    /// the first message of the morning.
    func testDaytimeWindowIsHalfOpen() {
        let quiet = QuietHours(json: ["enabled": true, "start": "09:00", "end": "17:00"])!
        XCTAssertTrue(quiet.contains(local(9, 0)), "start is inside")
        XCTAssertTrue(quiet.contains(local(12, 0)))
        XCTAssertTrue(quiet.contains(local(16, 59)))
        XCTAssertFalse(quiet.contains(local(17, 0)), "end is outside")
        XCTAssertFalse(quiet.contains(local(8, 59)))
        XCTAssertFalse(quiet.contains(local(23, 0)))
    }

    /// The live account's window. It wraps midnight, which is the case a naive
    /// `start <= now && now < end` comparison gets exactly backwards.
    func testWrappingWindowCoversTheNight() {
        let quiet = QuietHours(json: ["enabled": true, "start": "22:00", "end": "08:00"])!
        XCTAssertTrue(quiet.contains(local(22, 0)), "start is inside")
        XCTAssertTrue(quiet.contains(local(23, 30)))
        XCTAssertTrue(quiet.contains(local(0, 0)), "midnight is inside")
        XCTAssertTrue(quiet.contains(local(3, 15)))
        XCTAssertTrue(quiet.contains(local(7, 59)))
        XCTAssertFalse(quiet.contains(local(8, 0)), "end is outside")
        XCTAssertFalse(quiet.contains(local(12, 0)))
        XCTAssertFalse(quiet.contains(local(21, 59)))
    }

    /// A degenerate window suppresses nothing. The alternative reading — that it suppresses
    /// everything, forever — would silence the whole feature on a dashboard typo.
    func testEqualBoundariesSuppressNothing() {
        let quiet = QuietHours(json: ["enabled": true, "start": "22:00", "end": "22:00"])!
        XCTAssertFalse(quiet.contains(local(22, 0)))
        XCTAssertFalse(quiet.contains(local(3, 0)))
        XCTAssertFalse(quiet.contains(local(12, 0)))
    }

    func testDisabledWindowNeverContainsAnything() {
        let quiet = QuietHours(json: ["enabled": false, "start": "22:00", "end": "08:00"])!
        XCTAssertFalse(quiet.contains(local(23, 0)),
                       "23:00 is inside the window, but the window is off")
    }

    // MARK: - The clock the comparison uses

    /// The contract, stated as an assertion: the device's own hour decides. Written as a
    /// local literal, then handed over as the same instant expressed in UTC, so the test
    /// also proves the verdict depends on the instant and not on how the caller wrote it.
    func testTheWindowIsEvaluatedOnTheDeviceClock() {
        let quiet = QuietHours(json: ["enabled": true, "start": "22:00", "end": "08:00"])!
        let lateEvening = local(23, 0)
        XCTAssertTrue(quiet.contains(lateEvening))
        XCTAssertTrue(quiet.contains(Date(timeIntervalSince1970: lateEvening.timeIntervalSince1970)))
        XCTAssertFalse(quiet.contains(local(15, 0)))
    }

    /// The bug the old contract had the other way round: an implementation that converted
    /// the instant to UTC before comparing would, on any device east of Greenwich, call
    /// 23:00 local "not quiet" for part of the evening. The precondition guards against a
    /// machine that happens to run on UTC, where the two readings coincide.
    func testTheUTCHourIsNotWhatDecides() throws {
        let quiet = QuietHours(json: ["enabled": true, "start": "22:00", "end": "23:00"])!
        let instant = local(22, 30)
        var utcClock = Calendar(identifier: .gregorian)
        utcClock.timeZone = TimeZone(identifier: "UTC")!
        let utcHour = utcClock.component(.hour, from: instant)
        if utcHour == 22 {
            throw XCTSkip("this machine runs on UTC, so local and UTC readings coincide")
        }
        XCTAssertTrue(quiet.contains(instant), "22:30 local is inside 22:00–23:00 whatever UTC says")
    }

    // MARK: - The gate in selection

    private func campaign() -> InAppMessageCampaign {
        return makeCampaign(campaignId: 1, trigger: .sessionStart)
    }

    func testQuietHoursSuppressSelection() {
        let quiet = QuietHours(json: ["enabled": true, "start": "22:00", "end": "08:00"])!
        let selected = selectCampaign(occurrence: .sessionStart,
                                      campaigns: [campaign()],
                                      capState: .empty,
                                      now: local(23, 0),
                                      quietHours: quiet,
                                      isArtworkReady: { _ in true })
        XCTAssertNil(selected, "an eligible campaign must not display inside quiet hours")
    }

    func testOutsideQuietHoursSelectionProceeds() {
        let quiet = QuietHours(json: ["enabled": true, "start": "22:00", "end": "08:00"])!
        let selected = selectCampaign(occurrence: .sessionStart,
                                      campaigns: [campaign()],
                                      capState: .empty,
                                      now: local(12, 0),
                                      quietHours: quiet,
                                      isArtworkReady: { _ in true })
        XCTAssertEqual(selected?.campaignId, 1)
    }

    func testDisabledQuietHoursDoNotSuppress() {
        let quiet = QuietHours(json: ["enabled": false, "start": "22:00", "end": "08:00"])!
        let selected = selectCampaign(occurrence: .sessionStart,
                                      campaigns: [campaign()],
                                      capState: .empty,
                                      now: local(23, 0),
                                      quietHours: quiet,
                                      isArtworkReady: { _ in true })
        XCTAssertEqual(selected?.campaignId, 1)
    }

    /// No window at all is the common case — most accounts never configure one — and it
    /// must behave exactly like a disabled one.
    func testNoQuietHoursDoNotSuppress() {
        let selected = selectCampaign(occurrence: .sessionStart,
                                      campaigns: [campaign()],
                                      capState: .empty,
                                      now: local(23, 0),
                                      quietHours: nil,
                                      isArtworkReady: { _ in true })
        XCTAssertEqual(selected?.campaignId, 1)
    }

    // MARK: - Parsed off the sync envelope

    func testSyncResponseCarriesTheWindow() {
        let json: [String: Any] = [
            "cooldownSeconds": 10,
            "quietHours": ["enabled": true, "start": "22:00", "end": "08:00"],
            "messages": []
        ]
        let result = MessageParser.parseSyncResponse(
            try! JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(result.quietHours?.enabled, true)
        XCTAssertEqual(result.quietHours?.start.minutesSinceMidnight, 22 * 60)
        XCTAssertEqual(result.quietHours?.end.minutesSinceMidnight, 8 * 60)
    }

    func testSyncResponseWithoutAWindowParsesToNil() {
        let json: [String: Any] = ["cooldownSeconds": 10, "messages": []]
        let result = MessageParser.parseSyncResponse(
            try! JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(result.quietHours)
    }

    /// `quietHours: null` is what the backend sends for an account that has never set one,
    /// and it must not be mistaken for a malformed window.
    func testExplicitNullWindowParsesToNil() {
        let result = MessageParser.parseSyncResponse(
            Data(#"{"cooldownSeconds":10,"quietHours":null,"messages":[]}"#.utf8))
        XCTAssertNil(result.quietHours)
    }

    /// A window the parser cannot read must leave the feature working. Suppressing
    /// everything because a boundary was mistyped is the worse failure.
    func testMalformedWindowLeavesMessagingUnsuppressed() {
        let json: [String: Any] = [
            "cooldownSeconds": 10,
            "quietHours": ["enabled": true, "start": "not a time", "end": "08:00"],
            "messages": []
        ]
        let result = MessageParser.parseSyncResponse(
            try! JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(result.quietHours)
    }

    /// The live capture, so the wire contract is asserted against bytes the backend
    /// actually produced rather than against this file's idea of them.
    func testLiveCaptureCarriesTheAccountWindow() {
        let result = MessageParser.parseSyncResponse(IAMFixture.data("v4-sync-quiet-hours"))
        XCTAssertFalse(result.campaigns.isEmpty)
        XCTAssertEqual(result.cooldown, 10)
        guard let quiet = result.quietHours else {
            return XCTFail("the captured payload carries quietHours and it must parse")
        }
        XCTAssertTrue(quiet.enabled)
        XCTAssertEqual(quiet.start.minutesSinceMidnight, 22 * 60)
        XCTAssertEqual(quiet.end.minutesSinceMidnight, 8 * 60)
        XCTAssertTrue(quiet.contains(local(23, 30)))
        XCTAssertFalse(quiet.contains(local(15, 0)))
    }
}
