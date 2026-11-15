//
//  CapStateMigrationTests.swift
//  GameballTests
//

import XCTest
@testable import Gameball

final class CapStateMigrationTests: XCTestCase {

    /// Exactly what 3.4.0 writes, captured from that release rather than hand-written.
    private static let legacyJSON =
        #"{"lastDisplayByCampaign":{"2215":721692800},"lastDisplayAt":721692800}"#

    func testHistoryWrittenBeforeThisReleaseIsReadAsMessageCampaigns() throws {
        // Without this, every existing install loses its display history on update and every
        // once-ever campaign shows again.
        let decoded = try JSONDecoder().decode(CapState.self,
                                               from: Data(Self.legacyJSON.utf8))

        XCTAssertEqual(decoded.lastDisplayByCampaign,
                       [.message(2215): Date(timeIntervalSinceReferenceDate: 721692800)])
        XCTAssertEqual(decoded.lastDisplayAt,
                       Date(timeIntervalSinceReferenceDate: 721692800))
    }

    func testAGameDisplayRoundTripsThroughStorage() throws {
        var state = CapState.empty
        state.recordDisplay(campaign: .game(9645),
                            at: Date(timeIntervalSinceReferenceDate: 100))

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(CapState.self, from: data)

        XCTAssertEqual(decoded.lastDisplayByCampaign[.game(9645)],
                       Date(timeIntervalSinceReferenceDate: 100))
    }

    func testTheStoredKeyIsTheStorageForm() throws {
        // Guards the shape, not just the round trip: an encoder change that produced a flat array
        // would still round-trip while orphaning every existing history.
        var state = CapState.empty
        state.recordDisplay(campaign: .game(9645), at: Date(timeIntervalSinceReferenceDate: 100))

        let json = String(data: try JSONEncoder().encode(state), encoding: .utf8) ?? ""

        XCTAssertTrue(json.contains("\"game:9645\""), "unexpected encoding: \(json)")
    }

    func testAGameAndAMessageOfTheSameNumberStayApart() throws {
        var state = CapState.empty
        state.recordDisplay(campaign: .message(9645), at: Date(timeIntervalSinceReferenceDate: 1))
        state.recordDisplay(campaign: .game(9645), at: Date(timeIntervalSinceReferenceDate: 2))

        let decoded = try JSONDecoder().decode(CapState.self,
                                               from: try JSONEncoder().encode(state))

        XCTAssertEqual(decoded.lastDisplayByCampaign.count, 2,
                       "the two must not collapse into one stored key")
    }

    func testAnUnreadableKeyDropsOneEntryRatherThanTheWholeHistory() throws {
        let mixed = #"{"lastDisplayByCampaign":{"2215":100,"nonsense:x":200}}"#

        let decoded = try JSONDecoder().decode(CapState.self, from: Data(mixed.utf8))

        XCTAssertEqual(decoded.lastDisplayByCampaign.count, 1)
        XCTAssertNotNil(decoded.lastDisplayByCampaign[.message(2215)])
    }
}
