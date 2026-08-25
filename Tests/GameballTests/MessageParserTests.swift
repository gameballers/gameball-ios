//
//  MessageParserTests.swift
//  GameballTests
//
//  Every test here encodes a leniency rule from port specification §3. The parser's job
//  is to be forgiving in one direction only: a malformed *field* should cost the field,
//  a malformed *contract* should cost the campaign, and neither should ever throw.
//

import XCTest
@testable import Gameball

final class MessageParserTests: XCTestCase {

    // MARK: - Fixtures

    /// A campaign that parses cleanly, for tests to bend one field at a time.
    private func campaignJSON(_ overrides: [String: Any] = [:],
                              content contentOverrides: [String: Any] = [:],
                              locale localeOverride: [String: Any]? = nil,
                              removing removed: [String] = []) -> [String: Any] {
        var content: [String: Any] = [:]
        for (key, value) in contentOverrides { content[key] = value }

        var json: [String: Any] = [
            "campaignId": 2055,
            "variationId": 20,
            "dispatchId": "310a53d0-d90c-46d8-a41d-676fa29de82e",
            "name": "QA Modal",
            "priority": 3,
            "messageType": 2,
            "contentMode": "prerendered",
            "trigger": ["type": "session_start", "repeatable": true],
            "content": content,
            "locale": localeOverride ?? ["header": "Header", "message": "Body"],
            "isTest": false
        ]
        for (key, value) in overrides { json[key] = value }
        for key in removed { json.removeValue(forKey: key) }
        return json
    }

    private func payload(_ campaigns: [[String: Any]], root: [String: Any] = [:]) -> Data {
        var json: [String: Any] = ["cooldownSeconds": 30, "messages": campaigns]
        for (key, value) in root { json[key] = value }
        return try! JSONSerialization.data(withJSONObject: json)
    }

    /// Parses a single campaign and returns it, or nil when the parser dropped it.
    private func parseOne(_ overrides: [String: Any] = [:],
                          content: [String: Any] = [:],
                          locale: [String: Any]? = nil,
                          removing removed: [String] = []) -> InAppMessageCampaign? {
        let json = campaignJSON(overrides, content: content, locale: locale, removing: removed)
        return MessageParser.parseSyncResponse(payload([json])).campaigns.first
    }

    // MARK: - Whole-campaign mapping

    func testFullyPopulatedCampaignParses() {
        let campaign = parseOne([
            "expiresAt": "2026-09-30T21:59:59Z",
            "isTest": true,
            "trigger": [
                "type": "event",
                "eventId": 1382,
                "name": "place_order",
                "repeatable": true,
                "minIntervalSeconds": 300,
                "metadataLogicalOperator": "And",
                "metadataFilters": [
                    ["name": "price", "operator": "GreaterThan", "value": 100]
                ]
            ]
        ], content: [
            "imageUrl": "https://example.com/hero.png",
            "iconUrl": "https://example.com/icon.png",
            "closeBehaviour": "both",
            "autoDismissSeconds": 8,
            "layout": "text_with_image",
            "orientation": "portrait",
            "slideFrom": "top",
            "extras": ["campaign_tag": "summer"],
            "colors": ["background": "#FFFFFF", "text": "#1F2937", "header": "#111827"],
            "action": ["type": "open_url", "url": "https://example.com", "external": true],
            "buttons": [
                ["id": "ok",
                 "action": ["type": "navigate", "route": "orders", "arguments": ["id": 7]],
                 "colors": ["background": "#000000", "text": "#FFFFFF", "border": "#CCCCCC"]]
            ]
        ], locale: [
            "header": "Order placed!",
            "message": "Your points are on the way.",
            "buttons": [["id": "ok", "text": "Track my order"]]
        ])

        guard let parsed = campaign else { return XCTFail("campaign was dropped") }
        XCTAssertEqual(parsed.campaignId, 2055)
        XCTAssertEqual(parsed.variationId, 20)
        XCTAssertEqual(parsed.dispatchId, "310a53d0-d90c-46d8-a41d-676fa29de82e")
        XCTAssertEqual(parsed.name, "QA Modal")
        XCTAssertEqual(parsed.priority, 3)
        XCTAssertTrue(parsed.isTest)
        XCTAssertTrue(parsed.repeatable)
        XCTAssertEqual(parsed.minInterval, 300)
        XCTAssertEqual(parsed.responseIndex, 0)
        XCTAssertNotNil(parsed.expiresAt)

        // Identity folds in the variation, because an A/B arm is a distinct rendering.
        XCTAssertEqual(parsed.message.id, "2055/20")
        XCTAssertEqual(parsed.message.type, .modal)
        XCTAssertEqual(parsed.message.header, "Order placed!")
        XCTAssertEqual(parsed.message.body, "Your points are on the way.")
        XCTAssertEqual(parsed.message.imageURL?.absoluteString, "https://example.com/hero.png")
        XCTAssertEqual(parsed.message.iconURL?.absoluteString, "https://example.com/icon.png")
        XCTAssertTrue(parsed.message.showCloseButton)
        XCTAssertTrue(parsed.message.dismissOnScrimTap)
        XCTAssertEqual(parsed.message.autoDismissAfter, 8)
        XCTAssertEqual(parsed.message.layout, .textWithImage)
        XCTAssertEqual(parsed.message.orientation, .portrait)
        XCTAssertEqual(parsed.message.slidePosition, .top)
        XCTAssertEqual(parsed.message.extras["campaign_tag"] as? String, "summer")
        XCTAssertNotNil(parsed.message.style.backgroundColor)
        XCTAssertNotNil(parsed.message.style.textColor)

        if case .some(.openURL(let url, let external)) = parsed.message.clickAction {
            XCTAssertEqual(url.absoluteString, "https://example.com")
            XCTAssertTrue(external)
        } else {
            XCTFail("expected an openURL surface action, got \(String(describing: parsed.message.clickAction))")
        }

        XCTAssertEqual(parsed.message.buttons.count, 1)
        XCTAssertEqual(parsed.message.buttons.first?.id, "ok")
        XCTAssertEqual(parsed.message.buttons.first?.text, "Track my order")
        if case .some(.navigate(let route, let arguments)) = parsed.message.buttons.first?.action {
            XCTAssertEqual(route, "orders")
            XCTAssertEqual(arguments?["id"] as? Int, 7)
        } else {
            XCTFail("expected a navigate button action")
        }

        if case .event(let name, let filters) = parsed.trigger {
            XCTAssertEqual(name, "place_order")
            XCTAssertEqual(filters.count, 1)
        } else {
            XCTFail("expected an event trigger")
        }
    }

    func testMinimalCampaignParses() {
        let json: [String: Any] = [
            "campaignId": 99,
            "messageType": 2,
            "trigger": ["type": "session_start"],
            "locale": ["message": "Hello"]
        ]
        let parsed = MessageParser.parseSyncResponse(payload([json])).campaigns.first
        XCTAssertEqual(parsed?.campaignId, 99)
        XCTAssertEqual(parsed?.message.body, "Hello")
        // Identity has no variation to fold in.
        XCTAssertEqual(parsed?.message.id, "99")
        // Defaults from §3.1.
        XCTAssertEqual(parsed?.priority, 0)
        XCTAssertEqual(parsed?.repeatable, false)
        XCTAssertNil(parsed?.minInterval)
    }

    func testMissingCampaignIdDropsCampaign() {
        XCTAssertNil(parseOne(removing: ["campaignId"]))
    }

    /// Kept, not dropped. Types 4 and 5 are out of scope, so they must arrive as a
    /// harmless no-op rather than taking the payload with them.
    func testUnknownMessageTypeIsKeptAsUnsupported() {
        for rawType in [4, 5, 99] {
            let parsed = parseOne(["messageType": rawType])
            XCTAssertNotNil(parsed, "messageType \(rawType) should be kept")
            XCTAssertEqual(parsed?.message.type, .unsupported)
        }
    }

    func testUnknownContentModeDropsCampaign() {
        XCTAssertNil(parseOne(["contentMode": "html"]))
        XCTAssertNil(parseOne(["contentMode": "server_rendered"]))
        // Absent means prerendered, which is fine.
        XCTAssertNotNil(parseOne(removing: ["contentMode"]))
    }

    // MARK: - Buttons

    func testButtonsPairByIdAcrossContentAndLocale() {
        let parsed = parseOne(content: [
            "buttons": [
                ["id": "yes", "action": ["type": "dismiss"]],
                ["id": "no", "action": ["type": "dismiss"]]
            ]
        ], locale: [
            "header": "Header",
            "message": "Body",
            "buttons": [["id": "yes", "text": "Yes please"], ["id": "no", "text": "No thanks"]]
        ])
        XCTAssertEqual(parsed?.message.buttons.map { $0.id } ?? [], ["yes", "no"])
        XCTAssertEqual(parsed?.message.buttons.map { $0.text } ?? [], ["Yes please", "No thanks"])
    }

    func testUnpairedButtonIdsAreDropped() {
        let parsed = parseOne(content: [
            "buttons": [
                ["id": "paired", "action": ["type": "dismiss"]],
                ["id": "content_only", "action": ["type": "dismiss"]]
            ]
        ], locale: [
            "header": "Header",
            "message": "Body",
            "buttons": [["id": "paired", "text": "Tap"], ["id": "locale_only", "text": "Orphan"]]
        ])
        XCTAssertEqual(parsed?.message.buttons.map { $0.id } ?? [], ["paired"])
    }

    func testModalKeepsAtMostTwoButtons() {
        let parsed = parseOne(content: [
            "buttons": [
                ["id": "a", "action": ["type": "dismiss"]],
                ["id": "b", "action": ["type": "dismiss"]],
                ["id": "c", "action": ["type": "dismiss"]]
            ]
        ], locale: [
            "header": "Header",
            "message": "Body",
            "buttons": [["id": "a", "text": "A"], ["id": "b", "text": "B"], ["id": "c", "text": "C"]]
        ])
        XCTAssertEqual(parsed?.message.buttons.map { $0.id } ?? [], ["a", "b"])
    }

    // MARK: - Triggers

    func testEventTriggerWithNullNameDropsCampaign() {
        XCTAssertNil(parseOne(["trigger": ["type": "event", "eventId": 1382, "name": NSNull()]]))
        XCTAssertNil(parseOne(["trigger": ["type": "event", "eventId": 1382]]))
        XCTAssertNil(parseOne(["trigger": ["type": "event", "eventId": 1382, "name": "   "]]))
    }

    /// The whole campaign, not just the filter: evaluating a filter we cannot name as
    /// "always true" would widen a "spent over $100" campaign to every customer.
    func testFilterWithMissingNameDropsWholeCampaign() {
        XCTAssertNil(parseOne(["trigger": [
            "type": "event",
            "name": "place_order",
            "metadataFilters": [["operator": "GreaterThan", "value": 100]]
        ]]))
    }

    func testFilterWithBadOperatorIsDroppedIndividually() {
        let parsed = parseOne(["trigger": [
            "type": "event",
            "name": "place_order",
            "metadataFilters": [
                ["name": "price", "operator": "Between", "value": 100],
                ["name": "sku", "operator": "Is", "value": "abc"]
            ]
        ]])
        guard case .some(.event(_, let filters)) = parsed?.trigger else {
            return XCTFail("campaign should be kept with the usable filter")
        }
        XCTAssertEqual(filters.map { $0.name }, ["sku"])
    }

    func testFilterWithNullValueIsDroppedIndividually() {
        let parsed = parseOne(["trigger": [
            "type": "event",
            "name": "place_order",
            "metadataFilters": [
                ["name": "price", "operator": "Is", "value": NSNull()],
                ["name": "sku", "operator": "Is", "value": "abc"]
            ]
        ]])
        guard case .some(.event(_, let filters)) = parsed?.trigger else {
            return XCTFail("campaign should be kept with the usable filter")
        }
        XCTAssertEqual(filters.map { $0.name }, ["sku"])
    }

    func testOrLogicalOperatorDropsCampaign() {
        XCTAssertNil(parseOne(["trigger": [
            "type": "event",
            "name": "place_order",
            "metadataLogicalOperator": "Or",
            "metadataFilters": [["name": "price", "operator": "Is", "value": 1]]
        ]]))
        // And, in either spelling, is supported.
        XCTAssertNotNil(parseOne(["trigger": [
            "type": "event", "name": "place_order", "metadataLogicalOperator": "and"
        ]]))
        XCTAssertNotNil(parseOne(["trigger": [
            "type": "event", "name": "place_order", "metadataLogicalOperator": NSNull()
        ]]))
    }

    func testUnknownTriggerTypeDropsCampaign() {
        XCTAssertNil(parseOne(["trigger": ["type": "app_open"]]))
        XCTAssertNil(parseOne(removing: ["trigger"]))
    }

    // MARK: - Layout

    func testLayoutValuesParse() {
        XCTAssertEqual(parseOne(content: ["layout": "text_with_image"])?.message.layout, .textWithImage)
        XCTAssertEqual(parseOne(content: ["layout": "image_and_text"])?.message.layout, .textWithImage)
        XCTAssertEqual(parseOne(content: [
            "layout": "image_only", "imageUrl": "https://example.com/a.png"
        ])?.message.layout, .imageOnly)
    }

    /// Layout is a rendering hint, not a contract — a value a future dashboard invents
    /// must never cost the customer the message.
    func testUnknownLayoutFallsBackToTypeDefault() {
        let modal = parseOne(["messageType": 2], content: ["layout": "carousel"])
        XCTAssertNotNil(modal)
        XCTAssertEqual(modal?.message.layout, .textWithImage)

        let fullscreen = parseOne(["messageType": 3], content: ["layout": "carousel"])
        XCTAssertNotNil(fullscreen)
        XCTAssertEqual(fullscreen?.message.layout, .textWithImage)
    }

    /// Personalised copy that resolves to empty is indistinguishable from a deliberately
    /// image-only campaign, so layout must never be inferred from which fields are set.
    func testAbsentCopyDoesNotImplyImageOnly() {
        let parsed = parseOne(content: [
            "layout": "text_with_image",
            "imageUrl": "https://example.com/a.png"
        ], locale: [:])
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.message.layout, .textWithImage)
    }

    // MARK: - Artwork resolution

    func testFullscreenPrefersMediaURL() {
        let parsed = parseOne(["messageType": 3], content: [
            "imageUrl": "https://example.com/image.png",
            "media": ["type": "image", "url": "https://example.com/media.png"]
        ])
        XCTAssertEqual(parsed?.message.imageURL?.absoluteString, "https://example.com/media.png")
    }

    func testModalPrefersImageURL() {
        let parsed = parseOne(["messageType": 2], content: [
            "imageUrl": "https://example.com/image.png",
            "media": ["type": "image", "url": "https://example.com/media.png"]
        ])
        XCTAssertEqual(parsed?.message.imageURL?.absoluteString, "https://example.com/image.png")
    }

    func testEachTypeFallsBackToTheOtherImageField() {
        let fullscreen = parseOne(["messageType": 3], content: [
            "imageUrl": "https://example.com/image.png"
        ])
        XCTAssertEqual(fullscreen?.message.imageURL?.absoluteString, "https://example.com/image.png")

        let modal = parseOne(["messageType": 2], content: [
            "media": ["type": "image", "url": "https://example.com/media.png"]
        ])
        XCTAssertEqual(modal?.message.imageURL?.absoluteString, "https://example.com/media.png")
    }

    /// Handing a video URL to an image view draws a broken frame.
    func testVideoMediaIsIgnored() {
        let parsed = parseOne(["messageType": 3], content: [
            "media": ["type": "video", "url": "https://example.com/clip.mp4"]
        ])
        XCTAssertNotNil(parsed, "the campaign still has copy, so it must survive")
        XCTAssertNil(parsed?.message.imageURL)
    }

    func testBlankURLTreatedAsAbsent() {
        let parsed = parseOne(content: ["imageUrl": "", "iconUrl": "   "])
        XCTAssertNil(parsed?.message.imageURL)
        XCTAssertNil(parsed?.message.iconURL)
    }

    // MARK: - Renderability

    func testCampaignWithNothingToRenderIsDropped() {
        XCTAssertNil(parseOne(locale: [:]))
        XCTAssertNil(parseOne(locale: ["header": "", "message": ""]))
    }

    /// An icon alone is not a message.
    func testSlideupWithoutTextIsDropped() {
        // Artwork present, so only the slideup-specific text rule can drop this.
        XCTAssertNil(parseOne(["messageType": 1],
                              content: ["imageUrl": "https://example.com/a.png"],
                              locale: [:]))
        XCTAssertNil(parseOne(["messageType": 1],
                              content: ["iconUrl": "https://example.com/icon.png"],
                              locale: [:]))
        // A modal in the same shape survives, because artwork alone is a modal.
        XCTAssertNotNil(parseOne(["messageType": 2],
                                 content: ["imageUrl": "https://example.com/a.png"],
                                 locale: [:]))
    }

    // MARK: - Close behaviour

    func testCloseBehaviourButtonEnablesCloseButton() {
        let parsed = parseOne(content: ["closeBehaviour": "button"])
        XCTAssertEqual(parsed?.message.showCloseButton, true)
        XCTAssertEqual(parsed?.message.dismissOnScrimTap, false)
    }

    func testCloseBehaviourSwipeEnablesScrimTap() {
        let parsed = parseOne(content: ["closeBehaviour": "swipe"])
        XCTAssertEqual(parsed?.message.showCloseButton, false)
        XCTAssertEqual(parsed?.message.dismissOnScrimTap, true)
    }

    func testCloseBehaviourBothEnablesBoth() {
        for value in ["both", "button,swipe", "BOTH"] {
            let parsed = parseOne(content: ["closeBehaviour": value])
            XCTAssertEqual(parsed?.message.showCloseButton, true, "value \(value)")
            XCTAssertEqual(parsed?.message.dismissOnScrimTap, true, "value \(value)")
        }
    }

    /// Absent means both, per §3.2 — a message the customer cannot close is a trap.
    func testAbsentCloseBehaviourEnablesBoth() {
        let parsed = parseOne()
        XCTAssertEqual(parsed?.message.showCloseButton, true)
        XCTAssertEqual(parsed?.message.dismissOnScrimTap, true)
    }

    // MARK: - Scalars

    func testAutoDismissIgnoresNonPositive() {
        XCTAssertNil(parseOne(content: ["autoDismissSeconds": 0])?.message.autoDismissAfter)
        XCTAssertNil(parseOne(content: ["autoDismissSeconds": -5])?.message.autoDismissAfter)
        XCTAssertEqual(parseOne(content: ["autoDismissSeconds": 8])?.message.autoDismissAfter, 8)
    }

    func testExpiresAtParsesISO8601() {
        let parsed = parseOne(["expiresAt": "2026-09-30T21:59:59Z"])
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 30
        components.hour = 21; components.minute = 59; components.second = 59
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(parsed?.expiresAt, calendar.date(from: components))

        // Unparseable means "no expiry" rather than "expired", so a bad stamp cannot
        // silently suppress a live campaign.
        XCTAssertNil(parseOne(["expiresAt": "not a date"])?.expiresAt)
        XCTAssertNil(parseOne(["expiresAt": NSNull()])?.expiresAt)
    }

    // MARK: - Actions

    func testButtonWithNoUsableActionFallsBackToDismiss() {
        let parsed = parseOne(content: [
            "buttons": [
                ["id": "a"],
                ["id": "b", "action": NSNull()],
                ["id": "c", "action": ["type": "open_url", "url": ""]]
            ]
        ], locale: [
            "header": "Header", "message": "Body",
            "buttons": [["id": "a", "text": "A"], ["id": "b", "text": "B"], ["id": "c", "text": "C"]]
        ])
        // Modal caps at two, so check the two that survive.
        XCTAssertEqual(parsed?.message.buttons.count, 2)
        for button in parsed?.message.buttons ?? [] {
            if case .dismiss = button.action { continue }
            XCTFail("button \(button.id) should fall back to dismiss, got \(button.action)")
        }
    }

    /// Not `.dismiss` — making the whole surface dismiss on tap steals taps the campaign
    /// never asked to receive.
    func testSurfaceWithNoActionStaysNil() {
        XCTAssertNil(parseOne()?.message.clickAction)
        XCTAssertNil(parseOne(content: ["action": NSNull()])?.message.clickAction)
    }

    func testUnimplementedActionTypesParseAsUnsupported() {
        for type in ["log_event", "log_attribute", "request_push_permission"] {
            let parsed = parseOne(content: ["action": ["type": type]])
            guard case .some(.unsupported(let reported)) = parsed?.message.clickAction else {
                XCTFail("\(type) should parse as unsupported")
                continue
            }
            XCTAssertEqual(reported, type)
        }
    }

    // MARK: - Slideup dismissal

    /// Six of the seven live slideups send no `closeBehaviour`, no `autoDismissSeconds` and no
    /// buttons. A swipe is unconditional so none of them is *stuck*, but a swipe is a gesture
    /// nobody announces — so without a default the banner sits over the host app for the rest of
    /// the session. Auto-dismiss is the default across the Gameball SDKs, and this is Swift's.
    func testSlideupWithoutADurationAutoDismissesByDefault() {
        let message = parseOne(["messageType": 1], content: ["slideFrom": "bottom"])?.message
        XCTAssertEqual(message?.type, .slideup)
        XCTAssertEqual(message?.autoDismissAfter, defaultSlideupAutoDismiss)
    }

    /// A campaign that names a duration keeps it. The default is a floor for the unconfigured
    /// case, not a cap — campaign 2054 asks for 8s and must get 8s.
    func testAConfiguredDurationIsNotOverriddenByTheDefault() {
        let message = parseOne(["messageType": 1],
                               content: ["autoDismissSeconds": 8])?.message
        XCTAssertEqual(message?.autoDismissAfter, 8)
    }

    /// The default belongs to the slideup, which is a transient surface by type. A modal and a
    /// fullscreen take over the screen deliberately and must wait to be dismissed — timing one
    /// out would yank content the customer is reading.
    func testOnlySlideupsGetTheDefaultDuration() {
        XCTAssertNil(parseOne(["messageType": 2])?.message.autoDismissAfter,
                     "a modal must not auto-dismiss")
        XCTAssertNil(parseOne(["messageType": 3])?.message.autoDismissAfter,
                     "a fullscreen must not auto-dismiss")
    }

    /// A zero or negative duration is not a request for an instant dismissal — it is an
    /// unconfigured field spelled badly, and it falls back like an absent one.
    func testANonPositiveDurationFallsBackToTheDefault() {
        for value in [0, -1] {
            let message = parseOne(["messageType": 1],
                                   content: ["autoDismissSeconds": value])?.message
            XCTAssertEqual(message?.autoDismissAfter, defaultSlideupAutoDismiss,
                           "autoDismissSeconds: \(value)")
        }
    }

    /// `showCloseButton` used to be reported as `true` for every slideup, because a missing
    /// `closeBehaviour` defaults to "both". No slideup has ever rendered one — dismissal is the
    /// swipe and the timer — so the flag described something that never happened. Reporting it
    /// honestly is the fix; making the view honour it would have put a close button on all six
    /// live slideups.
    func testSlideupNeverClaimsACloseButton() {
        XCTAssertEqual(parseOne(["messageType": 1])?.message.showCloseButton, false,
                       "no closeBehaviour sent")
        XCTAssertEqual(parseOne(["messageType": 1],
                                content: ["closeBehaviour": "button"])?.message.showCloseButton,
                       false, "even when the campaign asks for one")
    }

    /// The other types still report it, so the change is scoped to the slideup.
    func testModalStillHonoursCloseBehaviour() {
        XCTAssertEqual(parseOne(["messageType": 2],
                                content: ["closeBehaviour": "button"])?.message.showCloseButton,
                       true)
        XCTAssertEqual(parseOne(["messageType": 2],
                                content: ["closeBehaviour": "swipe"])?.message.showCloseButton,
                       false)
    }

    // MARK: - Malformed input

    func testMalformedJSONYieldsEmptyResult() {
        let result = MessageParser.parseSyncResponse(Data("{ not json".utf8))
        XCTAssertTrue(result.campaigns.isEmpty)
    }

    func testNonObjectRootYieldsEmptyResult() {
        XCTAssertTrue(MessageParser.parseSyncResponse(Data("[1,2,3]".utf8)).campaigns.isEmpty)
        XCTAssertTrue(MessageParser.parseSyncResponse(Data()).campaigns.isEmpty)
    }

    func testMissingMessagesKeyYieldsEmptyResult() {
        let data = try! JSONSerialization.data(withJSONObject: ["cooldownSeconds": 30])
        XCTAssertTrue(MessageParser.parseSyncResponse(data).campaigns.isEmpty)
    }

    /// `quietHours` used to be listed here as an example of a key the parser ignores, with
    /// a `from`/`to` shape the backend never sent. It is now parsed — see QuietHoursTests —
    /// so the example had to be replaced with keys that really are unread.
    func testUnknownRootKeysAreIgnored() {
        let data = payload([campaignJSON()], root: [
            "campaignOrdering": "priority",
            "somethingInventedNextQuarter": true
        ])
        XCTAssertEqual(MessageParser.parseSyncResponse(data).campaigns.count, 1)
    }

    func testCooldownDefaultsToThirtySeconds() {
        let data = try! JSONSerialization.data(withJSONObject: ["messages": [campaignJSON()]])
        XCTAssertEqual(MessageParser.parseSyncResponse(data).cooldown, 30)

        let explicit = payload([campaignJSON()], root: ["cooldownSeconds": 45])
        XCTAssertEqual(MessageParser.parseSyncResponse(explicit).cooldown, 45)
    }

    func testResponseIndexFollowsPayloadOrder() {
        let data = payload([
            campaignJSON(["campaignId": 1]),
            campaignJSON(["campaignId": 2]),
            campaignJSON(["campaignId": 3])
        ])
        let campaigns = MessageParser.parseSyncResponse(data).campaigns
        XCTAssertEqual(campaigns.map { $0.campaignId }, [1, 2, 3])
        XCTAssertEqual(campaigns.map { $0.responseIndex }, [0, 1, 2])
    }

    /// A dropped campaign must not shift the index of the ones after it, or the
    /// tie-break silently changes depending on what else was in the payload.
    func testResponseIndexSurvivesADroppedCampaign() {
        let data = payload([
            campaignJSON(["campaignId": 1]),
            campaignJSON(["campaignId": 2], removing: ["campaignId"]),
            campaignJSON(["campaignId": 3])
        ])
        let campaigns = MessageParser.parseSyncResponse(data).campaigns
        XCTAssertEqual(campaigns.map { $0.campaignId }, [1, 3])
        XCTAssertEqual(campaigns.map { $0.responseIndex }, [0, 2])
    }

    // MARK: - Colours

    /// The repo's existing `UIColor(hexString:)` falls back to a hardcoded light grey.
    /// Reusing it here would paint an unstyled campaign grey instead of letting the view
    /// inherit the host's theme, so parsing must fail to nil.
    func testUnparseableColourIsNilRatherThanAHardcodedGrey() {
        let parsed = parseOne(content: [
            "colors": ["background": "not a colour", "text": NSNull(), "header": ""]
        ])
        XCTAssertNil(parsed?.message.style.backgroundColor)
        XCTAssertNil(parsed?.message.style.textColor)
        XCTAssertNil(parsed?.message.style.headerColor)
    }

    func testRawPayloadIsRetainedForTheCache() {
        let data = payload([campaignJSON()])
        XCTAssertEqual(MessageParser.parseSyncResponse(data).rawPayload, data)
    }
}
