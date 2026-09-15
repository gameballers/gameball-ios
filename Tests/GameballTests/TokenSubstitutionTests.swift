//
//  TokenSubstitutionTests.swift
//  GameballTests
//

import XCTest
@testable import Gameball

final class TokenSubstitutionTests: XCTestCase {

    private let values = ["points": "1,250", "name": "Sam", "tier": "Gold"]

    // MARK: - Substitution

    func testKnownTokenIsSubstituted() {
        XCTAssertEqual(TokenSubstitution.substitute("You have {points} points",
                                                    values: values),
                       "You have 1,250 points")
    }

    /// Blanking it would delete copy a marketer wrote; leaving it at least makes the
    /// misconfiguration visible.
    /// An empty value is a value, and it substitutes as one. The result reads badly — "Welcome
    /// {player_name}!" becomes "Welcome !" — and that is the agreed contract across every
    /// Gameball SDK, not a defect: the backend returns "" when a customer has no name on file,
    /// and supplying a default belongs in the campaign, not in the client.
    ///
    /// Pinned by a test because it is the kind of behaviour a future reader "fixes" on sight.
    /// Changing it here without changing it in the Flutter, Android and Web SDKs is what makes
    /// the same campaign render differently per platform.
    func testEmptyValueSubstitutesAsEmpty() {
        XCTAssertEqual(
            TokenSubstitution.substitute("Welcome {player_name}!", values: ["player_name": ""]),
            "Welcome !")
        XCTAssertEqual(
            TokenSubstitution.substitute("Hi {player_name}, you have {points} points",
                                         values: ["player_name": "", "points": "0"]),
            "Hi , you have 0 points")
    }

    /// The distinction the rule turns on: *absent* leaves the placeholder, *empty* removes it.
    /// Collapsing the two in either direction is wrong — an absent token means the SDK could not
    /// resolve it, an empty one means the backend resolved it to nothing.
    func testEmptyIsNotTreatedAsAbsent() {
        let empty = TokenSubstitution.substitute("Welcome {name}!", values: ["name": ""])
        let absent = TokenSubstitution.substitute("Welcome {name}!", values: [:])
        XCTAssertEqual(empty, "Welcome !")
        XCTAssertEqual(absent, "Welcome {name}!")
        XCTAssertNotEqual(empty, absent)
    }

    /// Whitespace is content, not emptiness. Trimming here would be the SDK editing copy.
    func testWhitespaceValueIsInsertedAsGiven() {
        XCTAssertEqual(TokenSubstitution.substitute("[{x}]", values: ["x": "  "]), "[  ]")
    }

    func testUnknownTokenIsLeftExactlyAsWritten() {
        XCTAssertEqual(TokenSubstitution.substitute("Hello {mystery}", values: values),
                       "Hello {mystery}")
    }

    /// The backend sends pre-formatted strings — points already thousand-separated. Re-parsing
    /// or re-formatting them would break locales the SDK knows nothing about.
    func testValuesAreInsertedVerbatim() {
        XCTAssertEqual(TokenSubstitution.substitute("{points}", values: values), "1,250")
    }

    func testMultipleTokensInOneStringAreAllSubstituted() {
        XCTAssertEqual(TokenSubstitution.substitute("{name}, you are {tier} with {points}",
                                                    values: values),
                       "Sam, you are Gold with 1,250")
    }

    func testRepeatedTokenIsSubstitutedEveryTime() {
        XCTAssertEqual(TokenSubstitution.substitute("{name} {name}", values: values), "Sam Sam")
    }

    // MARK: - Strictness

    func testSpacedBracesAreNotTokens() {
        XCTAssertEqual(TokenSubstitution.substitute("{ points }", values: values), "{ points }")
    }

    func testNumericBracesAreNotTokens() {
        XCTAssertEqual(TokenSubstitution.substitute("index {2}", values: ["2": "two"]),
                       "index {2}")
    }

    func testLoneBraceIsUntouched() {
        XCTAssertEqual(TokenSubstitution.substitute("100% {", values: values), "100% {")
        XCTAssertEqual(TokenSubstitution.substitute("}", values: values), "}")
    }

    /// A value cannot inject a token, so no cycle is possible.
    func testOnePassOnly() {
        let result = TokenSubstitution.substitute("{a}", values: ["a": "{b}", "b": "boom"])
        XCTAssertEqual(result, "{b}")
    }

    // MARK: - Detection

    func testContainsTokenIsFalseForPlainText() {
        XCTAssertFalse(TokenSubstitution.containsToken("No placeholders here"))
        XCTAssertFalse(TokenSubstitution.containsToken(nil))
        XCTAssertFalse(TokenSubstitution.containsToken("{ spaced }"))
        XCTAssertFalse(TokenSubstitution.containsToken("{2}"))
    }

    func testContainsTokenIsTrueForARealToken() {
        XCTAssertTrue(TokenSubstitution.containsToken("You have {points}"))
        XCTAssertTrue(TokenSubstitution.containsToken("{_private}"))
    }

    func testTokensInMessageCollectsFromAllFields() {
        let message = makeMessage(header: "Hi {name}",
                                  body: "You have {points}",
                                  buttons: [makeButton(id: "a", text: "Spend {points}"),
                                            makeButton(id: "b", text: "See {tier}")])
        XCTAssertEqual(TokenSubstitution.tokens(in: message), ["name", "points", "tier"])
    }

    func testTokensInMessageIsEmptyForPlainCopy() {
        let message = makeMessage(header: "Hi", body: "Plain copy",
                                  buttons: [makeButton(text: "Go")])
        XCTAssertTrue(TokenSubstitution.tokens(in: message).isEmpty)
    }

    // MARK: - Applying to a message

    func testAppliesToHeaderBodyAndButtonLabels() {
        let message = makeMessage(header: "Hi {name}",
                                  body: "You have {points}",
                                  buttons: [makeButton(id: "a", text: "Spend {points}")])
        let applied = TokenSubstitution.apply(values: values, to: message)

        XCTAssertEqual(applied.header, "Hi Sam")
        XCTAssertEqual(applied.body, "You have 1,250")
        XCTAssertEqual(applied.buttons.first?.text, "Spend 1,250")
    }

    func testApplyPreservesEverythingElse() {
        let action = GameballClickAction.navigate(route: "orders", arguments: nil)
        let message = makeMessage(id: "7/2", type: .fullscreen,
                                  header: "Hi {name}",
                                  imageURL: URL(string: "https://example.com/a.png"),
                                  clickAction: action,
                                  buttons: [makeButton(id: "a", text: "Go", action: .dismiss)],
                                  showCloseButton: false,
                                  autoDismissAfter: 5,
                                  layout: .imageOnly,
                                  orientation: .landscape,
                                  slidePosition: .top,
                                  extras: ["tag": "summer"])
        let applied = TokenSubstitution.apply(values: values, to: message)

        XCTAssertEqual(applied.id, "7/2")
        XCTAssertEqual(applied.type, .fullscreen)
        XCTAssertEqual(applied.imageURL?.absoluteString, "https://example.com/a.png")
        XCTAssertEqual(applied.showCloseButton, false)
        XCTAssertEqual(applied.autoDismissAfter, 5)
        XCTAssertEqual(applied.layout, .imageOnly)
        XCTAssertEqual(applied.orientation, .landscape)
        XCTAssertEqual(applied.slidePosition, .top)
        XCTAssertEqual(applied.extras["tag"] as? String, "summer")
        XCTAssertEqual(applied.buttons.first?.id, "a")
        if case .some(.navigate) = applied.clickAction {} else {
            XCTFail("the surface action was lost")
        }
        if case .dismiss = applied.buttons.first!.action {} else {
            XCTFail("the button action was lost")
        }
    }

    func testApplyWithNoValuesReturnsTheMessageUnchanged() {
        let message = makeMessage(header: "Hi {name}")
        XCTAssertEqual(TokenSubstitution.apply(values: [:], to: message).header, "Hi {name}")
    }
}
