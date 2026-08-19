# In-App Messaging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in in-app messaging module to the Gameball iOS SDK that syncs campaigns, evaluates triggers locally, draws modal / slideup / fullscreen messages above the host app, and reports impression / click / dismiss telemetry — without changing the behaviour of the existing widget SDK.

**Architecture:** A self-contained module under `Sources/Gameball/InAppMessaging/`, built from seven single-responsibility units behind protocols plus one orchestrator that owns all mutable state. The evaluator is pure functions with the clock passed in. Presentation uses our own `UIWindow` with a single touch-passthrough rule. The module is dormant until `startInAppMessaging` is called.

**Tech Stack:** Swift (4.2 language mode), UIKit, `URLSession`, `UserDefaults`, XCTest. **No third-party dependencies.**

**Spec:** `docs/superpowers/specs/2026-08-18-in-app-messaging-design.md` — read it before starting. It cites the binding port specification at `../gameball-flutter/docs/reference/in-app-messaging-port-specification.md` and the wire contract at `../gameball-flutter/docs/reference/backend-sdk-endpoints-reference.md`.

**On code in this plan:** interfaces, signatures, property names and test lists are given exactly, because cross-task consistency depends on them and a wrong name is a bug that surfaces three tasks later. Full bodies are inlined only where the logic is non-obvious or a rule is easy to get subtly wrong — the parser's leniency rules, the selection algorithm, `hitTest`, the outbox state machine. Mechanical code (a struct of `Codable` properties, a stack of constraints) is specified by its shape and contract rather than transcribed.

---

## Global Constraints

Copied verbatim from the design. Every task's requirements implicitly include this section.

- **Platform floor unchanged:** `Package.swift` `.iOS(.v11)`, `swiftLanguageVersions: [.v4_2]`; `Gameball.podspec` `11.0` / `4.2`. Do not edit these values.
- **No `async`/`await`, no actors, no `Sendable`, no `@MainActor`** — Swift 4.2 language mode forbids them. Serial `DispatchQueue` for state isolation, `@escaping` completions carrying `Result`, presentation confined to main.
- **No third-party dependencies.** Do not add anything to `Package.swift` `dependencies` or the podspec.
- **Never throws into the host.** Every failure is logged via `IAMLog` and swallowed. No `try!`, no force-unwraps on parsed input, no `fatalError`.
- **Dormant until opt-in.** Before `startInAppMessaging`: no requests, no timers, no storage writes, nothing drawn.
- **Isolation from the widget SDK.** All new code lives under `Sources/Gameball/InAppMessaging/`. The *only* permitted edits to pre-existing source are the two guarded one-line hooks in Task 16. Do not modify `NetworkManager.swift`, `Constants.swift`, `GB_WEBVIEWWIDGETViewController`, `BaseViewController`, or any widget file.
- **Endpoints pinned to v4.0.** `POST /api/v4.0/integrations/inapp-messages/{sync,events,variables}`. Never route through `NetworkManager`'s `URL` extension, which switches to v4.1 when a session token is present; v4.1 answers 401 to APIKey auth.
- **`platform` is always `1`** (iOS) in request bodies. A value other than 1 or 2 must be logged loudly before sending.
- **`eventUid` must be a lowercased v4 UUID.** Generated once per event, never regenerated on retry.
- **RTL:** directional constraints only. Never assign `semanticContentAttribute`; never touch `UIView.appearance()`. Read `traitCollection.layoutDirection` when a branch needs direction.
- **Diagnostics prefix:** `[GameballIAM]`. Never post module diagnostics to the backend.
- **Build/test command:** `Scripts/test.sh` (created in Task 1). `swift test` cannot work — no UIKit on macOS. Bare `xcodebuild` from the repo root builds the stale tracked `_Pods.xcodeproj` and fails.

---

## File Structure

Every path below is new except the two noted in Task 16.

| File | Responsibility |
|---|---|
| `Scripts/test.sh` | The only working build/test entry point |
| `InAppMessaging/IAMLog.swift` | `[GameballIAM]` console diagnostics |
| `InAppMessaging/Models/GameballMessageType.swift` | Wire enums with forward-compatible unknown cases |
| `InAppMessaging/Models/GameballClickAction.swift` | Action enum + button/style value types |
| `InAppMessaging/Models/GameballInAppMessage.swift` | The renderable message (public) |
| `InAppMessaging/Models/MessageTrigger.swift` | Trigger, occurrence, purchase event name |
| `InAppMessaging/Models/PropertyFilter.swift` | Filter operators and matching |
| `InAppMessaging/Models/InAppMessageCampaign.swift` | Identity, priority, expiry, repeat rule |
| `InAppMessaging/Source/MessageParser.swift` | Every leniency rule in port spec §3 |
| `InAppMessaging/Source/MessageSource.swift` | `SyncResult`, `MessageSource` protocol |
| `InAppMessaging/Source/IAMHTTPClient.swift` | `URLSession` transport for the three endpoints |
| `InAppMessaging/Source/HTTPMessageSource.swift` | Transport + parser wiring |
| `InAppMessaging/Source/StubMessageSource.swift` | Fixture source for tests |
| `InAppMessaging/Source/CampaignCache.swift` | Last good raw payload, per customer |
| `InAppMessaging/Evaluation/TriggerEvaluator.swift` | Pure selection |
| `InAppMessaging/Evaluation/FrequencyCap.swift` | `CapState` + persistence |
| `InAppMessaging/Storage/IAMStore.swift` | Store protocol, `UserDefaults` suite, in-memory double |
| `InAppMessaging/Analytics/MessageEvent.swift` | Event value type + UUID v4 |
| `InAppMessaging/Analytics/MessageAnalytics.swift` | Protocol + logging implementation |
| `InAppMessaging/Analytics/BatchedMessageAnalytics.swift` | Outbox, flush, retry/discard |
| `InAppMessaging/Presentation/ArtworkPrefetcher.swift` | Bounded concurrent warm + `NSCache` |
| `InAppMessaging/Presentation/InAppMessageView.swift` | View protocol + lifecycle extension |
| `InAppMessaging/Presentation/MessageWindow.swift` | `UIWindow` with passthrough `hitTest` |
| `InAppMessaging/Presentation/MessageViewController.swift` | Orientation, status bar, accessibility |
| `InAppMessaging/Presentation/PresentationContext.swift` | Message + attributes + level + scene |
| `InAppMessaging/Presentation/MessageWindowPresenter.swift` | Validation, window lifecycle, auto-dismiss |
| `InAppMessaging/Presentation/Views/MessageViewAttributes.swift` | Per-type layout/typography constants |
| `InAppMessaging/Presentation/Views/SlideupMessageView.swift` | Slideup composition |
| `InAppMessaging/Presentation/Views/ModalMessageView.swift` | Modal, text + image |
| `InAppMessaging/Presentation/Views/ModalImageMessageView.swift` | Modal, image only |
| `InAppMessaging/Presentation/Views/FullscreenMessageView.swift` | Fullscreen, image + text |
| `InAppMessaging/Presentation/Views/FullscreenImageMessageView.swift` | Fullscreen, image only |
| `InAppMessaging/Presentation/Views/MessageButtonView.swift` | Button + wrapping stack |
| `InAppMessaging/Presentation/Views/MessageCloseButton.swift` | 44pt close affordance |
| `InAppMessaging/Presentation/MessageActionRouter.swift` | dismiss / open_url / navigate |
| `InAppMessaging/Personalisation/TokenSubstitution.swift` | `{token}` detect + substitute |
| `InAppMessaging/Personalisation/VariableSource.swift` | Fetch, 60s cache, PII filter |
| `InAppMessaging/InAppMessagingService.swift` | Orchestrator; the only mutable state |
| `InAppMessaging/GameballApp+InAppMessaging.swift` | Public surface, delegate, `logPurchase` |
| `Tests/GameballTests/…` | One test file per unit, plus `EndToEndTests` |
| `Tests/GameballTests/Fixtures/v4-sync-response.json` | Live captured payload |

---

## Task 1: Test harness

**Files:**
- Create: `Scripts/test.sh` (already written and verified — commit it)
- Create: `Sources/Gameball/InAppMessaging/IAMLog.swift`
- Modify: `Tests/GameballTests/GameballTests.swift` (replace the broken stub)
- Modify: `Package.swift` — add `resources: [.copy("Fixtures")]` to the **testTarget only**
- Create: `Tests/GameballTests/Fixtures/v4-sync-response.json` (copy from `../gameball-flutter/test/fixtures/v4-sync-response.json`)

**Interfaces produced:**
- `func iamLog(_ message: String)` — prints `[GameballIAM] <message>`
- `enum IAMFixture { static func data(_ name: String) -> Data }` — loads a fixture from the test bundle

- [x] **Step 1: Confirm the current failure**

Run: `./Scripts/test.sh test`
Expected: `error: cannot call value of non-function type 'module<Gameball>'` at `GameballTests.swift:9`. This is the pre-existing breakage; there is no green baseline.

- [x] **Step 2: Replace the broken stub with a real test**

`Tests/GameballTests/GameballTests.swift`:

```swift
import XCTest
@testable import Gameball

final class GameballTests: XCTestCase {
    func testSDKVersionIsSet() {
        XCTAssertFalse(SDKInfo.version.isEmpty)
    }
}
```

- [x] **Step 3: Write `IAMLog.swift`**

```swift
import Foundation

/// Local diagnostic logging for the in-app messaging module.
///
/// Deliberately separate from `GameballLogger`, which posts telemetry to the Gameball
/// backend. Parse and evaluation diagnostics belong in the integrator's console, not in
/// a network request. Since the module never throws, a log line is the only evidence of
/// why something did not happen.
func iamLog(_ message: String) {
    print("[GameballIAM] \(message)")
}
```

- [x] **Step 4: Copy the fixture and add the loader**

```bash
mkdir -p Tests/GameballTests/Fixtures
cp ../gameball-flutter/test/fixtures/v4-sync-response.json Tests/GameballTests/Fixtures/
```

Copied into this repo deliberately: the suite must not depend on a sibling checkout existing.

`Tests/GameballTests/IAMFixture.swift`:

```swift
import Foundation
import XCTest

enum IAMFixture {
    static func data(_ name: String) -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            XCTFail("fixture \(name).json not found in test bundle")
            return Data()
        }
        return data
    }
}
```

Add to `Package.swift`'s testTarget only — the library target is untouched:

```swift
.testTarget(
    name: "GameballTests",
    dependencies: ["Gameball"],
    resources: [.copy("Fixtures")]
),
```

- [x] **Step 5: Verify green**

Run: `./Scripts/test.sh test`
Expected: `** TEST SUCCEEDED **`. This is the first green baseline the repo has had.

- [x] **Step 6: Commit**

```bash
git add Scripts/test.sh Sources/Gameball/InAppMessaging/IAMLog.swift Tests/ Package.swift
git commit -m "test: establish a working iOS test harness and IAM diagnostics"
```

---

## Task 2: Models

**Files:**
- Create: `Models/GameballMessageType.swift`, `Models/GameballClickAction.swift`, `Models/GameballInAppMessage.swift`, `Models/MessageTrigger.swift`, `Models/PropertyFilter.swift`, `Models/InAppMessageCampaign.swift`
- Test: `Tests/GameballTests/PropertyFilterTests.swift`

**Interfaces produced** — later tasks depend on these names exactly:

```swift
public enum GameballMessageType {
    case slideup, modal, fullscreen, unsupported
    init(rawValue: Int)      // 1/2/3 map; 4, 5 and anything else -> .unsupported
}

public enum GameballMessageLayout { case textWithImage, imageOnly }
public enum GameballMessageOrientation { case portrait, landscape, any }
public enum GameballSlidePosition { case top, bottom }

public enum GameballClickAction {
    case dismiss
    case openURL(url: URL, external: Bool)
    case navigate(route: String, arguments: [String: Any]?)
    case unsupported(type: String)
}

public struct GameballButtonStyle {
    public let backgroundColor: UIColor?
    public let textColor: UIColor?
    public let borderColor: UIColor?
}

public struct GameballMessageButton {
    public let id: String
    public let text: String
    public let action: GameballClickAction
    public let style: GameballButtonStyle
}

public enum GameballTextAlignment { case leading, center, trailing }

public struct GameballMessageStyle {
    public let backgroundColor: UIColor?
    public let textColor: UIColor?
    public let headerColor: UIColor?
    public let closeButtonColor: UIColor?
    public let borderColor: UIColor?
    public let frameColor: UIColor?
    public let headerAlignment: GameballTextAlignment
    public let bodyAlignment: GameballTextAlignment
}

public struct GameballInAppMessage {
    public let id: String                       // "{campaignId}" or "{campaignId}/{variationId}"
    public let type: GameballMessageType
    public let header: String?
    public let body: String?
    public let imageURL: URL?
    public let iconURL: URL?
    public let clickAction: GameballClickAction?    // nil means the surface is inert
    public let buttons: [GameballMessageButton]
    public let showCloseButton: Bool
    public let dismissOnScrimTap: Bool
    public let autoDismissAfter: TimeInterval?
    public let layout: GameballMessageLayout
    public let orientation: GameballMessageOrientation
    public let slidePosition: GameballSlidePosition
    public let extras: [String: Any]
    public let style: GameballMessageStyle
}

let gameballPurchaseEventName = "purchase"

enum MessageTrigger {
    case sessionStart
    case event(name: String, filters: [PropertyFilter])
}

enum TriggerOccurrence {
    case sessionStart
    case event(name: String, properties: [String: Any])
}

enum FilterOperator {
    case equals, notEquals, greaterThan, greaterThanOrEqual, lessThan, lessThanOrEqual, contains
    init?(wireName: String)     // case-insensitive; accepts is/isnot/equals/notequals/…
}

struct PropertyFilter {
    let name: String
    let op: FilterOperator
    let value: Any
    func matches(properties: [String: Any]) -> Bool
}

struct InAppMessageCampaign {
    let campaignId: Int
    let variationId: Int?
    let dispatchId: String?
    let name: String?
    let priority: Int
    let expiresAt: Date?
    let isTest: Bool
    let repeatable: Bool
    let minInterval: TimeInterval?
    let trigger: MessageTrigger
    let message: GameballInAppMessage
    let responseIndex: Int
    func hasExpired(at now: Date) -> Bool
}
```

- [x] **Step 1: Write the failing filter tests**

`PropertyFilterTests.swift` — one test per row:

| Test | Asserts |
|---|---|
| `testEqualsMatchesString` | `equals` on `"electronics"` matches |
| `testEqualsComparesNumbersNumerically` | `equals` `100` matches `100.0` — JSON gives `Int` or `Double` unpredictably |
| `testNotEqualsInvertsEquals` | `notEquals` on a differing value matches |
| `testGreaterThanOnNumbers` | `150 > 100` matches, `50 > 100` does not |
| `testGreaterThanOrEqualBoundary` | `100 >= 100` matches |
| `testLessThanOnNumbers` | `50 < 100` matches |
| `testLessThanOrEqualBoundary` | `100 <= 100` matches |
| `testContainsIsCaseInsensitiveSubstring` | `"PRO"` in `"iPhone Pro"` matches |
| `testMissingPropertyNeverMatches` | every operator returns `false` when the key is absent, **including `notEquals`** |
| `testOperatorWireNamesAreCaseInsensitive` | `Is`, `is`, `IsNot`, `GreaterThan`, `Equals` all map |
| `testUnknownOperatorWireNameIsNil` | `FilterOperator(wireName: "Between")` is `nil` |

The missing-property case is the one to get right: a filter is a *requirement*, so absence is failure even for a negative operator. Port spec §3.7.

- [x] **Step 2: Run and watch it fail**

Run: `./Scripts/test.sh test -only-testing:GameballTests/PropertyFilterTests`
Expected: compile failure — the types do not exist.

- [x] **Step 3: Implement the models**

Numeric comparison helper, because JSON numbers arrive as `Int`, `Double` or `NSNumber` and string comparison of `"100"` vs `"100.0"` would fail:

```swift
private func asDouble(_ value: Any) -> Double? {
    if let d = value as? Double { return d }
    if let i = value as? Int { return Double(i) }
    if let n = value as? NSNumber { return n.doubleValue }
    if let s = value as? String { return Double(s) }
    return nil
}

private func asString(_ value: Any) -> String? {
    if let s = value as? String { return s }
    if let n = value as? NSNumber { return n.stringValue }
    return nil
}

func matches(properties: [String: Any]) -> Bool {
    // A filter is a requirement, so a missing property is failure — for every
    // operator, negative ones included. Otherwise filters become decorative.
    guard let actual = properties[name] else { return false }

    switch op {
    case .equals, .notEquals:
        let equal: Bool
        if let a = asDouble(actual), let b = asDouble(value) {
            equal = a == b
        } else {
            equal = asString(actual) == asString(value)
        }
        return op == .equals ? equal : !equal
    case .greaterThan, .greaterThanOrEqual, .lessThan, .lessThanOrEqual:
        guard let a = asDouble(actual), let b = asDouble(value) else { return false }
        switch op {
        case .greaterThan:        return a > b
        case .greaterThanOrEqual: return a >= b
        case .lessThan:           return a < b
        default:                  return a <= b
        }
    case .contains:
        guard let a = asString(actual), let b = asString(value) else { return false }
        return a.lowercased().contains(b.lowercased())
    }
}
```

`FilterOperator(wireName:)` lowercases and strips nothing else, mapping: `is`/`equals` → `.equals`; `isnot`/`notequals` → `.notEquals`; `greaterthan` → `.greaterThan`; `greaterthanorequal` → `.greaterThanOrEqual`; `lessthan` → `.lessThan`; `lessthanorequal` → `.lessThanOrEqual`; `contains` → `.contains`; anything else `nil`.

`GameballMessageType(rawValue:)` maps 1/2/3 and sends **4, 5 and everything else** to `.unsupported` — types 4 and 5 are out of scope and must arrive as no-ops, not errors.

- [x] **Step 4: Verify green** — `./Scripts/test.sh test -only-testing:GameballTests/PropertyFilterTests`

- [x] **Step 5: Commit** — `git commit -m "feat(iam): message, campaign, trigger and filter models"`

---

## Task 3: MessageParser

**Files:**
- Create: `Source/MessageParser.swift`
- Test: `Tests/GameballTests/MessageParserTests.swift`

**Interfaces produced:**

```swift
enum MessageParser {
    /// Never throws. A malformed payload yields an empty result; a malformed campaign
    /// is dropped with a log naming the field that caused it.
    static func parseSyncResponse(_ data: Data) -> SyncResult
    static func parseCampaign(_ json: [String: Any], responseIndex: Int) -> InAppMessageCampaign?
}
```

- [x] **Step 1: Write the failing parser tests**

Every row is a rule from port spec §3. Write them all before implementing.

| Test | Asserts |
|---|---|
| `testFullyPopulatedCampaignParses` | every field mapped |
| `testMinimalCampaignParses` | id + type + trigger + some text is enough |
| `testMissingCampaignIdDropsCampaign` | dropped |
| `testUnknownMessageTypeIsKeptAsUnsupported` | **kept**, `.unsupported`, not dropped |
| `testUnknownContentModeDropsCampaign` | `contentMode` other than `prerendered` → dropped |
| `testButtonsPairByIdAcrossContentAndLocale` | only ids present in both render |
| `testUnpairedButtonIdsAreDropped` | content-only or locale-only ids vanish |
| `testModalKeepsAtMostTwoButtons` | third dropped |
| `testEventTriggerWithNullNameDropsCampaign` | dropped; never match on `eventId` |
| `testFilterWithMissingNameDropsWholeCampaign` | whole campaign — widening would show a "spent over $100" message to everyone |
| `testFilterWithBadOperatorIsDroppedIndividually` | that filter only; campaign kept |
| `testFilterWithNullValueIsDroppedIndividually` | that filter only; campaign kept |
| `testOrLogicalOperatorDropsCampaign` | `metadataLogicalOperator: "Or"` → dropped |
| `testLayoutValuesParse` | `text_with_image`, `image_only`, `image_and_text` |
| `testUnknownLayoutFallsBackToTypeDefault` | campaign kept; modal → `.textWithImage`, fullscreen → `.textWithImage` |
| `testAbsentCopyDoesNotImplyImageOnly` | a campaign with no header/body but an `imageUrl` and `layout: text_with_image` stays `.textWithImage` |
| `testFullscreenPrefersMediaURL` | `media.url` wins over `imageUrl` |
| `testModalPrefersImageURL` | `imageUrl` wins over `media.url` |
| `testEachTypeFallsBackToTheOtherImageField` | both directions |
| `testVideoMediaIsIgnored` | `media.type == "video"` → `imageURL` nil, campaign kept if other content exists |
| `testBlankURLTreatedAsAbsent` | `""` → nil |
| `testCampaignWithNothingToRenderIsDropped` | no header, no body, no image → dropped |
| `testSlideupWithoutTextIsDropped` | icon alone is not a message |
| `testCloseBehaviourButtonEnablesCloseButton` | `"button"` → `showCloseButton` true, `dismissOnScrimTap` false |
| `testCloseBehaviourSwipeEnablesScrimTap` | `"swipe"` → inverse |
| `testCloseBehaviourBothEnablesBoth` | `"both"` → both true |
| `testAutoDismissIgnoresNonPositive` | `0` and `-5` → nil |
| `testExpiresAtParsesISO8601` | `"2026-09-30T21:59:59Z"` |
| `testButtonWithNoUsableActionFallsBackToDismiss` | `.dismiss` |
| `testSurfaceWithNoActionStaysNil` | `clickAction` nil — **not** `.dismiss` |
| `testUnimplementedActionTypesParseAsUnsupported` | `log_event`, `log_attribute`, `request_push_permission` |
| `testMalformedJSONYieldsEmptyResult` | no throw |
| `testNonObjectRootYieldsEmptyResult` | no throw |
| `testMissingMessagesKeyYieldsEmptyResult` | no throw |
| `testUnknownRootKeysAreIgnored` | `quietHours`, `campaignOrdering` present → still parses |
| `testCooldownDefaultsToThirtySeconds` | absent `cooldownSeconds` → 30 |
| `testResponseIndexFollowsPayloadOrder` | 0, 1, 2… |

- [x] **Step 2: Run and watch it fail**

Run: `./Scripts/test.sh test -only-testing:GameballTests/MessageParserTests`

- [x] **Step 3: Implement the parser**

Structure: `parseSyncResponse` → `JSONSerialization`, read `cooldownSeconds` (default 30) and `messages`, map with index, `compactMap` through `parseCampaign`. Retain the raw `Data` on the result so the cache stores bytes, not objects.

The artwork precedence rule, which differs by type and is the easiest thing to invert:

```swift
// Two fields can carry the image and precedence depends on the type.
// Fullscreen posters are authored as `media`; everything else as `imageUrl`.
private static func resolveImageURL(content: [String: Any],
                                   type: GameballMessageType) -> URL? {
    let mediaURL = mediaImageURL(content["media"])
    let imageURL = normalisedURL(content["imageUrl"])
    let ordered = (type == .fullscreen) ? [mediaURL, imageURL] : [imageURL, mediaURL]
    return ordered.compactMap { $0 }.first
}

private static func mediaImageURL(_ media: Any?) -> URL? {
    guard let media = media as? [String: Any] else { return nil }
    // Use `url` only when the type is image or absent. Handing a video URL to an
    // image view draws a broken frame.
    if let kind = media["type"] as? String, kind.lowercased() != "image" {
        iamLog("ignoring media of type \(kind); only images are supported")
        return nil
    }
    return normalisedURL(media["url"])
}

/// Blank strings normalise to nil. An empty URL otherwise reaches the artwork
/// loader, fails, and silently takes the whole campaign with it.
private static func normalisedURL(_ value: Any?) -> URL? {
    guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !string.isEmpty, let url = URL(string: string) else { return nil }
    if url.scheme?.lowercased() == "http" {
        iamLog("artwork served over http:// will be blocked by App Transport Security: \(url)")
    }
    return url
}
```

Layout, which must never cost the customer the message:

```swift
// A value a future dashboard invents must not drop the campaign — layout is a
// rendering hint, not a contract. And never infer layout from which fields are
// populated: personalised copy resolving to empty is indistinguishable from a
// deliberately image-only campaign.
private static func parseLayout(_ raw: Any?, type: GameballMessageType) -> GameballMessageLayout {
    guard let value = (raw as? String)?.lowercased() else { return .textWithImage }
    switch value {
    case "image_only":                       return .imageOnly
    case "text_with_image", "image_and_text": return .textWithImage
    default:
        iamLog("unrecognised layout '\(value)'; falling back to the default for \(type)")
        return .textWithImage
    }
}
```

Trigger parsing, where the asymmetry is deliberate — a filter we cannot *name* drops the campaign, a filter with one bad *field* is dropped alone:

```swift
private static func parseTrigger(_ json: [String: Any]) -> MessageTrigger? {
    let type = (json["type"] as? String)?.lowercased() ?? ""
    if type == "session_start" { return .sessionStart }
    guard type == "event" else {
        iamLog("unknown trigger type '\(type)'; dropping campaign")
        return nil
    }
    // Match on the event NAME. `eventId` is internal to the backend and cannot be
    // resolved on a device, so a null name means the campaign is unevaluable.
    guard let name = (json["name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
        iamLog("event trigger has no name; dropping campaign")
        return nil
    }
    if let op = json["metadataLogicalOperator"] as? String,
       op.lowercased() != "and" {
        iamLog("metadataLogicalOperator '\(op)' is not supported; dropping campaign")
        return nil
    }
    var filters: [PropertyFilter] = []
    for raw in (json["metadataFilters"] as? [[String: Any]] ?? []) {
        guard let filterName = raw["name"] as? String, !filterName.isEmpty else {
            // Evaluating an unnamed filter as "always true" would silently WIDEN the
            // campaign. Dropping the campaign is the safe direction.
            iamLog("metadata filter has no name; dropping campaign")
            return nil
        }
        guard let opName = raw["operator"] as? String,
              let op = FilterOperator(wireName: opName) else {
            iamLog("filter '\(filterName)' has an unusable operator; dropping the filter")
            continue
        }
        guard let value = raw["value"], !(value is NSNull) else {
            iamLog("filter '\(filterName)' has a null value; dropping the filter")
            continue
        }
        filters.append(PropertyFilter(name: filterName, op: op, value: value))
    }
    return .event(name: name, filters: filters)
}
```

Renderability, enforced last:

```swift
// Drawing an empty box is worse than showing nothing. A slideup additionally
// requires text — an icon alone is not a message.
let hasText = (header?.isEmpty == false) || (body?.isEmpty == false)
guard hasText || imageURL != nil else {
    iamLog("campaign \(campaignId) has nothing to render; dropping")
    return nil
}
if type == .slideup && !hasText {
    iamLog("slideup campaign \(campaignId) has no text; dropping")
    return nil
}
```

- [x] **Step 4: Verify green** — all `MessageParserTests` pass

- [x] **Step 5: Add the live-payload test**

`Tests/GameballTests/RealSyncResponseTests.swift` — parse `IAMFixture.data("v4-sync-response")` and assert a non-empty campaign list, that every campaign has a non-zero `campaignId`, and that no campaign has `.unsupported` unless the payload's `messageType` is 4 or 5. Reading the documentation is not a substitute for parsing what the backend actually sent.

- [x] **Step 6: Commit** — `git commit -m "feat(iam): sync payload parser with the leniency rules"`

---

## Task 4: Evaluator and frequency cap

**Files:**
- Create: `Evaluation/TriggerEvaluator.swift`, `Evaluation/FrequencyCap.swift`
- Test: `Tests/GameballTests/TriggerEvaluatorTests.swift`, `Tests/GameballTests/FrequencyCapTests.swift`

**Interfaces produced:**

```swift
struct CapState: Codable {
    var lastDisplayAt: Date?
    var lastDisplayByCampaign: [Int: Date]
    mutating func recordDisplay(campaignId: Int, at time: Date)
}

let defaultDisplayCooldown: TimeInterval = 30

func selectCampaign(occurrence: TriggerOccurrence,
                    campaigns: [InAppMessageCampaign],
                    capState: CapState,
                    now: Date,
                    cooldown: TimeInterval,
                    isArtworkReady: (InAppMessageCampaign) -> Bool) -> InAppMessageCampaign?

func triggerMatches(_ trigger: MessageTrigger, _ occurrence: TriggerOccurrence) -> Bool
func isRepeatEligible(campaign: InAppMessageCampaign, capState: CapState, now: Date) -> Bool
func isWithinFloor(capState: CapState, now: Date, cooldown: TimeInterval) -> Bool

final class FrequencyCap {
    init(store: IAMStore, customerId: String)
    var state: CapState { get }
    func load()
    func recordDisplay(campaignId: Int, at time: Date)
    func reset()
}
```

`isArtworkReady` is injected as a closure so the evaluator stays pure — it must not reach for the prefetcher.

- [x] **Step 1: Write the failing evaluator tests**

| Test | Asserts |
|---|---|
| `testSessionStartSelectsSessionStartCampaign` | matched |
| `testNamedEventSelectsMatchingCampaign` | matched by name |
| `testNonMatchingEventNameSelectsNothing` | nil |
| `testFiltersMustAllMatch` | two filters, one failing → nil |
| `testMissingPropertyNeverMatches` | nil |
| `testExpiredCampaignIsNeverSelected` | `expiresAt <= now` → nil |
| `testExpiryIsCheckedAtSelectionNotOnlyAtFetch` | a campaign parsed while valid, evaluated after expiry → nil |
| `testNonRepeatableCampaignIsNeverSelectedTwice` | second call → nil |
| `testRepeatableCampaignRespectsMinInterval` | inside → nil, after → selected |
| `testRepeatableWithNilIntervalSelectsEveryOccurrence` | selected |
| `testInsideGlobalFloorNothingIsSelected` | nil even for a fresh campaign |
| `testFloorIsCheckedAfterEligibilityNotPerCampaign` | an ineligible high-priority campaign does not consume the decision |
| `testHighestPriorityWins` | 10 beats 5 |
| `testTiesBreakOnResponseOrderStably` | **20 equal-priority campaigns, run 50 times, always the same winner** |
| `testUnsupportedTypeIsFilteredSoLowerPriorityWins` | supported priority-1 wins over unsupported priority-10 |
| `testUnreadyArtworkIsFilteredSoLowerPriorityWins` | same shape, via `isArtworkReady` |
| `testPurchaseSelectsCampaignTriggeredOnPurchaseEvent` | trigger name `purchase` |
| `testPurchaseFiltersOnPriceAndProductId` | `price > 100`, `productId == "sku"` |

The stability test needs the repetition: Swift's `sort` is not guaranteed stable, so a single run can pass by luck.

- [x] **Step 2: Run and watch it fail**

- [x] **Step 3: Implement**

```swift
func selectCampaign(occurrence: TriggerOccurrence,
                    campaigns: [InAppMessageCampaign],
                    capState: CapState,
                    now: Date,
                    cooldown: TimeInterval = defaultDisplayCooldown,
                    isArtworkReady: (InAppMessageCampaign) -> Bool) -> InAppMessageCampaign? {
    var eligible: [InAppMessageCampaign] = []
    for candidate in campaigns {
        if !triggerMatches(candidate.trigger, occurrence) { continue }
        // Checked here and not only at fetch: campaigns are cached for the session, so
        // one fetched at 23:58 would otherwise fire all night, and keep firing after
        // the campaign was paused.
        if candidate.hasExpired(at: now) { continue }
        if !isRepeatEligible(campaign: candidate, capState: capState, now: now) { continue }
        // Filtered here rather than refused at display, so a usable lower-priority
        // campaign can still win instead of the occurrence being wasted.
        if candidate.message.type == .unsupported {
            iamLog("campaign \(candidate.campaignId) skipped: unsupported message type")
            continue
        }
        if !isArtworkReady(candidate) {
            iamLog("campaign \(candidate.campaignId) skipped: artwork not ready")
            continue
        }
        eligible.append(candidate)
    }

    if eligible.isEmpty { return nil }

    // After eligibility, before sorting. Inside the floor nothing displays at all;
    // it is not a per-campaign rule.
    if isWithinFloor(capState: capState, now: now, cooldown: cooldown) {
        iamLog("suppressed: inside the \(Int(cooldown))s display floor")
        return nil
    }

    // Swift's sort is not guaranteed stable, so ordering by priority alone would make
    // equal-priority ties rotate arbitrarily between runs. responseIndex is the
    // documented tie-break and is carried explicitly for exactly this reason.
    return eligible.sorted {
        $0.priority != $1.priority ? $0.priority > $1.priority
                                   : $0.responseIndex < $1.responseIndex
    }.first
}
```

`isRepeatEligible`: no record → true; not repeatable → false (once ever, forever); `minInterval` nil → true; else `now - last >= minInterval`.

`isWithinFloor`: no `lastDisplayAt` → false; else `now - last < cooldown`.

`FrequencyCap` persists `CapState` as JSON via `IAMStore`, stamped with the customer id and discarded on mismatch at read. History is **not pruned** — the backend stops returning a non-repeatable campaign once its impression lands, so forgetting it could show a once-ever message twice.

- [x] **Step 4: Write the failing cap tests**

| Test | Asserts |
|---|---|
| `testRecordedDisplaySurvivesReload` | new `FrequencyCap` over the same store sees it |
| `testStateForADifferentCustomerIsDiscarded` | empty state |
| `testCorruptStoredDataYieldsEmptyStateWithoutThrowing` | garbage bytes → empty |
| `testResetClearsHistory` | empty |
| `testHistoryIsNotPrunedByCampaignCount` | 200 entries all retained |

- [x] **Step 5: Verify green** — both suites

- [x] **Step 6: Commit** — `git commit -m "feat(iam): pure trigger evaluator and persisted frequency cap"`

---

## Task 5: Storage

**Files:**
- Create: `Storage/IAMStore.swift`
- Test: `Tests/GameballTests/IAMStoreTests.swift`

**Interfaces produced:**

```swift
protocol IAMStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    func removeAll()
}

final class UserDefaultsIAMStore: IAMStore {
    init(suiteName: String = "co.gameball.inappmessaging")
}

final class InMemoryIAMStore: IAMStore { init() }   // test double

enum IAMStoreKey {
    static let displayHistory   = "gameball_iam_display_history"
    static let campaignCache    = "gameball_iam_campaign_cache"
    static let analyticsOutbox  = "gameball_iam_analytics_outbox"
    static let variables        = "gameball_iam_variables"
}

/// Wraps a stored value with the customer it belongs to, so a mismatch is
/// discarded at read. One slot stamped with the customer — not one key per
/// customer, which would retain every previous customer's data indefinitely,
/// including the PII the variables store holds.
struct CustomerScoped<T: Codable>: Codable {
    let customerId: String
    let value: T
}
```

A dedicated suite keeps the module's data out of the host's preferences plist. The protocol is what lets every later suite inject `InMemoryIAMStore`, so the real suite is never touched by tests.

- [x] **Step 1: Write failing tests** — round-trip; overwrite; `nil` removes; `removeAll` empties; `CustomerScoped` decode returns nil value on customer mismatch; the `UserDefaults` implementation writes to its suite and **not** to `UserDefaults.standard`.

- [x] **Step 2: Run and watch it fail**

- [x] **Step 3: Implement.** `UserDefaultsIAMStore` holds a `UserDefaults(suiteName:)`, falling back to `.standard` only if the suite cannot be created, with a log. No read timeout: port spec §10 requires one because Flutter's `shared_preferences` crosses a platform channel that can wedge; `UserDefaults` is in-process and synchronous.

- [x] **Step 4: Verify green**

- [x] **Step 5: Commit** — `git commit -m "feat(iam): customer-scoped key-value store behind a protocol"`

---

## Task 6: HTTP client and sync

**Files:**
- Create: `Source/IAMHTTPClient.swift`, `Source/MessageSource.swift`, `Source/HTTPMessageSource.swift`, `Source/StubMessageSource.swift`
- Test: `Tests/GameballTests/IAMHTTPClientTests.swift`, `Tests/GameballTests/HTTPMessageSourceTests.swift`

**Interfaces produced:**

```swift
struct SyncResult {
    let campaigns: [InAppMessageCampaign]
    let cooldown: TimeInterval
    let rawPayload: Data?          // nil when the result came FROM the cache
    static let empty: SyncResult
}

protocol MessageSource: AnyObject {
    func fetch(customerId: String, completion: @escaping (Result<SyncResult, Error>) -> Void)
}

enum IAMEndpoint {
    static let sync      = "/api/v4.0/integrations/inapp-messages/sync"
    static let events    = "/api/v4.0/integrations/inapp-messages/events"
    static let variables = "/api/v4.0/integrations/inapp-messages/variables"
}

enum IAMHTTPOutcome {
    case success(Data)
    case permanentFailure(status: Int)     // 400, 401, 404, 422 — never retry
    case retryableFailure(status: Int?)    // 408, 429, 5xx, transport errors
}

protocol IAMTransport: AnyObject {
    func post(path: String, body: [String: Any],
              completion: @escaping (IAMHTTPOutcome) -> Void)
}

final class IAMHTTPClient: IAMTransport {
    init(session: URLSession = .shared,
         baseURL: @escaping () -> String,
         apiKey: @escaping () -> String,
         language: @escaping () -> String)
}

final class HTTPMessageSource: MessageSource {
    init(transport: IAMTransport, appVersion: String, sdkVersion: String, locale: String)
}

final class StubMessageSource: MessageSource {
    init(result: Result<SyncResult, Error>)
    var fetchCount: Int { get }
}
```

`baseURL`, `apiKey` and `language` are closures so the client reads current SDK configuration at request time without importing `NetworkManager`'s mutable singleton state into its own initialiser.

- [x] **Step 1: Write the failing client tests** using a `URLProtocol` stub

| Test | Asserts |
|---|---|
| `testSyncPathIsPinnedToV40` | the URL ends `/api/v4.0/integrations/inapp-messages/sync` |
| `testSessionTokenDoesNotChangeTheVersion` | still v4.0 — v4.1 answers 401 to APIKey auth |
| `testRequestCarriesAPIKeyAndAgentHeaders` | `APIKey`, `x-gb-agent`, `lang` |
| `testBodyCarriesCustomerIdAndPlatformOne` | `platform == 1` |
| `testBodyCarriesLocaleAppVersionSdkVersion` | present |
| `test2xxIsSuccess` | `.success` with the body |
| `test400IsPermanent` / `401` / `404` / `422` | `.permanentFailure` |
| `test408IsRetryable` / `429` / `500` / `503` | `.retryableFailure` |
| `testTransportErrorIsRetryable` | `.retryableFailure(nil)` |
| `test404WithEmptyBodyIsLoggedAsNotDeployed` | distinguishable from a 404 with an `ErrorResponse` body |
| `testNonSerialisableBodyDoesNotCrash` | no `try!` — returns a failure |

- [x] **Step 2: Run and watch it fail**

- [x] **Step 3: Implement.** Build `URLRequest` by hand — do **not** use `NetworkManager`'s `URL`/`URLRequest` extensions, which force-unwrap and switch to v4.1. Serialise with `JSONSerialization.data(withJSONObject:)` inside a `do`/`catch`. Status mapping exactly as the tests specify.

- [x] **Step 4: Write `HTTPMessageSource` tests** — success parses via `MessageParser`; permanent and retryable failures both surface as `.failure` so the caller falls back to cache; the raw payload is retained on success.

- [x] **Step 5: Verify green**

- [x] **Step 6: Commit** — `git commit -m "feat(iam): v4.0-pinned HTTP client and sync source"`

---

## Task 7: Campaign cache

**Files:**
- Create: `Source/CampaignCache.swift`
- Test: `Tests/GameballTests/CampaignCacheTests.swift`

**Interfaces produced:**

```swift
final class CampaignCache {
    init(store: IAMStore)
    func save(payload: Data, customerId: String)
    /// Re-parses on read, so a payload a newer SDK rejects is not resurrected as
    /// stale objects, and there is no serialiser to keep in step with the model.
    func load(customerId: String, now: Date) -> SyncResult?
    func clear()
}
```

- [x] **Step 1: Write failing tests** — round-trip through the parser; a different customer yields nil; corrupt bytes yield nil without throwing; **campaigns already past `expiresAt` are excluded on load**; `clear` empties.

- [x] **Step 2: Run and watch it fail**

- [x] **Step 3: Implement.** Store the raw payload wrapped in `CustomerScoped<Data>`; on load, re-parse and filter expired.

- [x] **Step 4: Verify green**

- [x] **Step 5: Commit** — `git commit -m "feat(iam): campaign cache storing the raw payload"`

---

## Task 8: Analytics outbox

**Files:**
- Create: `Analytics/MessageEvent.swift`, `Analytics/MessageAnalytics.swift`, `Analytics/BatchedMessageAnalytics.swift`
- Test: `Tests/GameballTests/MessageEventTests.swift`, `Tests/GameballTests/BatchedMessageAnalyticsTests.swift`

**Interfaces produced:**

```swift
enum MessageEventType: String, Codable { case impression, click, dismiss }

struct MessageEvent: Codable {
    let eventUid: String        // lowercased v4 UUID, generated once
    let dispatchId: String?
    let campaignId: Int
    let variationId: Int?
    let type: MessageEventType
    let occurredAt: Date        // device time when it happened, never send time
    let buttonId: String?
    let url: String?
    init(campaignId: Int, variationId: Int?, dispatchId: String?,
         type: MessageEventType, occurredAt: Date,
         buttonId: String? = nil, url: String? = nil,
         eventUid: String = MessageEvent.newEventUid())
    static func newEventUid() -> String     // UUID().uuidString.lowercased()
    func wireDictionary() -> [String: Any]
}

protocol MessageAnalytics: AnyObject {
    func load()
    func log(_ event: MessageEvent)
    func flush()
    func dispose()
}

final class BatchedMessageAnalytics: MessageAnalytics {
    init(transport: IAMTransport, store: IAMStore, customerId: String,
         flushInterval: TimeInterval = 30,
         flushThreshold: Int = 10,
         batchSize: Int = 50,
         ceiling: Int = 500)
    var pendingCount: Int { get }        // test visibility
}
```

- [x] **Step 1: Write failing event tests** — `eventUid` matches `^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`; `occurredAt` serialises as ISO-8601 UTC; `buttonId` and `url` omitted when nil.

The UUID shape assertion is deliberate: a non-GUID is a hard 400 that discards the entire batch, so a future refactor must not be able to break ingestion silently.

- [x] **Step 2: Write failing outbox tests**

| Test | Asserts |
|---|---|
| `testLogDoesNotBlockTheCaller` | `log` returns before any request |
| `testFlushesAtTenEvents` | one request |
| `testFlushChunksAtFifty` | 120 events → 3 requests |
| `test2xxClearsTheBatch` | `pendingCount == 0` |
| `test2xxWithRejectedGreaterThanZeroStillClears` | cleared, `rejected` logged |
| `testUnreadable2xxBodyStillAccepted` | cleared |
| `testPermanentStatusDiscardsWithoutRetry` | 400/401/404/422 → cleared, logged loudly |
| `testRetryableStatusKeepsTheBatch` | 408/429/500/503 → retained |
| `testTransportErrorKeepsTheBatch` | retained |
| `testEventUidIsNotRegeneratedOnRetry` | same uid across two attempts |
| `testOutboxSurvivesReload` | new instance over the same store sees them |
| `testCeilingDropsOldestAndLogs` | 501st event evicts the 1st |
| `testOneRequestInFlightAtATime` | second flush during a request does not double-send |
| `testDisposeCancelsTheTimer` | no further requests |
| `testPoisonBatchDoesNotBlockLaterEvents` | after a permanent discard the next batch sends |

The poison-batch test is the important one: the outbox is FIFO, so one permanently-rejected batch at the head would otherwise take every event behind it down until the ceiling rotated it out.

- [x] **Step 3: Run and watch them fail**

- [x] **Step 4: Implement.** In-memory array persisted after every mutation, serial queue, `Timer` for the interval, `isSending` guard for the single in-flight request. Status handling: `.success` → drop the sent slice; `.permanentFailure` → drop the slice and log loudly; `.retryableFailure` → keep.

- [x] **Step 5: Verify green**

- [x] **Step 6: Commit** — `git commit -m "feat(iam): batched analytics outbox with retry and discard semantics"`

---

## Task 9: Artwork prefetcher

**Files:**
- Create: `Presentation/ArtworkPrefetcher.swift`
- Test: `Tests/GameballTests/ArtworkPrefetcherTests.swift`

**Interfaces produced:**

```swift
final class ArtworkPrefetcher {
    init(session: URLSession = .shared, timeout: TimeInterval = 5)
    /// Warms every campaign's imageURL and iconURL concurrently, then calls back.
    func warm(campaigns: [InAppMessageCampaign], completion: @escaping () -> Void)
    func isReady(_ campaign: InAppMessageCampaign) -> Bool
    func image(for url: URL) -> UIImage?
    func reset()
}
```

- [x] **Step 1: Write failing tests** — every campaign warmed, not just the first; a failed load makes `isReady` false; a campaign with no artwork is ready; concurrency (8 images at 300ms complete in well under 2.4s); a hung load is bounded by the timeout and the campaign is not ready; `reset` clears readiness so the next sync re-evaluates.

- [x] **Step 2: Run and watch it fail**

- [x] **Step 3: Implement.** `DispatchGroup` over all URLs, `URLSession` data tasks with the timeout on the request, decoded images into an `NSCache`, a `Set<URL>` of failures guarded by the serial queue. Warm the whole set — an event trigger fires with no warning and no time to fetch.

- [x] **Step 4: Verify green**

- [x] **Step 5: Commit** — `git commit -m "feat(iam): bounded concurrent artwork prefetcher"`

---

## Task 10: Window, view controller, presenter

**Files:**
- Create: `Presentation/InAppMessageView.swift`, `Presentation/MessageWindow.swift`, `Presentation/MessageViewController.swift`, `Presentation/PresentationContext.swift`, `Presentation/MessageWindowPresenter.swift`
- Test: `Tests/GameballTests/MessageWindowPresenterTests.swift`

**Interfaces produced:**

```swift
protocol InAppMessageView: UIView {
    var presented: Bool { get }
    func present(completion: (() -> Void)?)
    func dismiss(completion: (() -> Void)?)
}

extension InAppMessageView {
    static var closeButtonMinimumTouchTargetSize: CGFloat { 44 }
    var coordinator: MessageViewCoordinating? { get }
    func willPresent()
    func didPresent()        // impression anchor + VoiceOver .screenChanged
    func willDismiss()
    func didDismiss()
    func logClick(buttonId: String?)
    func process(action: GameballClickAction, buttonId: String?)
}

protocol MessageViewCoordinating: AnyObject {
    func viewWillPresent()
    func viewDidPresent()
    func viewWillDismiss()
    func viewDidDismiss()
    func viewDidClick(buttonId: String?)
    func viewDidRequest(action: GameballClickAction, buttonId: String?)
}

struct PresentationContext {
    var message: GameballInAppMessage
    var attributes: MessageViewAttributes
    var windowLevel: UIWindow.Level     // .normal
    var preferredOrientation: UIInterfaceOrientation
    var windowScene: Any?               // UIWindowScene on iOS 13+, cast at use
}

struct PresentationHandlers {
    let onShown: () -> Void
    let onButtonPressed: (GameballMessageButton) -> Void
    let onMessagePressed: () -> Void
    let onDismissed: () -> Void
}

enum PresentationObstacle { case noSurface, alreadyShowing, notMainThread }

protocol MessagePresenting: AnyObject {
    var isShowing: Bool { get }
    func present(context: PresentationContext,
                 handlers: PresentationHandlers) -> PresentationObstacle?
    func dismiss()
}

final class MessageWindowPresenter: MessagePresenting {
    init(viewFactory: @escaping (PresentationContext) -> InAppMessageView?)
    var headless: Bool          // present without a UIApplication, for tests
}
```

`present` returns an optional obstacle rather than throwing — that return value is what feeds the deferral in the orchestrator.

- [x] **Step 1: Write the `MessageWindow` hitTest test first**

This is the single rule that makes a slideup non-blocking and a modal blocking, with no per-type branch:

```swift
func testHitTestPassesThroughOutsideTheMessageView() {
    let window = MessageWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
    let controller = UIViewController()
    let message = StubMessageView(frame: CGRect(x: 0, y: 500, width: 320, height: 68))
    controller.view.addSubview(message)
    window.rootViewController = controller
    window.isHidden = false

    // Inside the banner: captured.
    XCTAssertNotNil(window.hitTest(CGPoint(x: 160, y: 530), with: nil))
    // Outside it: passed to the app underneath.
    XCTAssertNil(window.hitTest(CGPoint(x: 160, y: 100), with: nil))
}
```

- [x] **Step 2: Run and watch it fail**

- [x] **Step 3: Implement `MessageWindow`**

```swift
final class MessageWindow: UIWindow {
    /// One rule, not a per-type branch: capture a touch only when it landed on the
    /// message view or something inside it. A slideup then passes touches through
    /// automatically because it occupies only its own band, and a modal blocks
    /// because its scrim is part of the message view.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        var node: UIView? = hit
        while let current = node {
            if current is InAppMessageView { return hit }
            node = current.superview
        }
        return nil
    }
}
```

- [x] **Step 4: Implement the view protocol extension**

`coordinator` is a `weak` reference injected at init and stored on each concrete view, exposed through the protocol. `didPresent()` posts `UIAccessibility.post(notification: .screenChanged, argument: self)` so VoiceOver moves focus, then calls `coordinator?.viewDidPresent()`.

- [x] **Step 5: Implement `MessageViewController`**

Owns `supportedInterfaceOrientations` derived from `context.message.orientation` (`.portrait` → `.portrait`, `.landscape` → `.landscape`, `.any` → `.all`), `preferredInterfaceOrientationForPresentation` from `context.preferredOrientation`, and observes `UIDevice.orientationDidChangeNotification`. Sets `view.backgroundColor = .clear`. This constrains orientation rather than deferring on mismatch — divergence D2 in the design.

- [x] **Step 6: Implement `MessageWindowPresenter`**

Validation chain, each step logging its own reason: main thread → not already showing → a surface exists (unless `headless`). Then build the window (`MessageWindow(windowScene:)` on iOS 13+ via the `Any?` cast, `MessageWindow(frame: UIScreen.main.bounds)` below), set `accessibilityViewIsModal` (true for modal/fullscreen, false for slideup), `windowLevel = context.windowLevel`, `rootViewController`, then `window.isHidden = false` — **never** `makeKeyAndVisible`, so the host keeps its keyboard and first responder.

Auto-dismiss `Timer` is scheduled in `viewDidPresent()`, not at window-show, so a configured duration measures time *visible*.

Teardown in `viewDidDismiss()`: invalidate the timer, nil the scene on iOS 13+, nil the window, call `handlers.onDismissed`. The window is rebuilt per presentation, so a stale surface handle cannot survive.

- [x] **Step 7: Write the presenter tests**

| Test | Asserts |
|---|---|
| `testPresentReturnsNoSurfaceWhenThereIsNoWindow` | `.noSurface`, no crash |
| `testPresentReturnsAlreadyShowingWhenOneIsUp` | `.alreadyShowing` |
| `testHeadlessPresentsWithoutAHostApp` | succeeds |
| `testOnShownFiresAfterDidPresentNotAtInsertion` | ordering |
| `testAutoDismissTimerStartsAtVisibility` | not at insertion |
| `testDismissTearsDownTheWindow` | `isShowing` false, window released |
| `testWindowIsNotMadeKey` | `window.isKeyWindow` false |
| `testWindowLevelIsNormal` | `.normal` |
| `testSlideupWindowIsNotAccessibilityModal` | false; modal true |

- [x] **Step 8: Verify green**

- [x] **Step 9: Commit** — `git commit -m "feat(iam): message window, view controller and presenter"`

---

## Task 11: The five message views

**Files:**
- Create: `Presentation/Views/MessageViewAttributes.swift`, `SlideupMessageView.swift`, `ModalMessageView.swift`, `ModalImageMessageView.swift`, `FullscreenMessageView.swift`, `FullscreenImageMessageView.swift`, `MessageButtonView.swift`, `MessageCloseButton.swift`
- Test: `Tests/GameballTests/MessageLayoutResilienceTests.swift`, `Tests/GameballTests/MessageViewTests.swift`

**Interfaces produced:**

```swift
struct MessageViewAttributes {
    struct Modal {
        var margin = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        var padding = UIEdgeInsets(top: 40, left: 25, bottom: 30, right: 25)
        var labelsSpacing: CGFloat = 10
        var spacing: CGFloat = 20
        var cornerRadius: CGFloat = 8
        var minWidth: CGFloat = 320
        var maxWidth: CGFloat = 450
        var maxHeight: CGFloat = 720
        var headerFont = UIFont.preferredFont(forTextStyle: .title3)
        var bodyFont = UIFont.preferredFont(forTextStyle: .subheadline)
        static let defaults = Modal()
    }
    struct Slideup { /* iconSize 40x40, padding, cornerRadius, fonts */ static let defaults = Slideup() }
    struct Fullscreen { /* padding, spacing, fonts */ static let defaults = Fullscreen() }
    var modal = Modal.defaults
    var slideup = Slideup.defaults
    var fullscreen = Fullscreen.defaults
    static let defaults = MessageViewAttributes()
}

final class MessageButtonView: UIButton {
    init(button: GameballMessageButton, style: GameballButtonStyle)
    var onTap: ((GameballMessageButton) -> Void)?
}

final class MessageCloseButton: UIButton { init(tintColor: UIColor?) }   // 44x44 minimum

final class SlideupMessageView: UIView, InAppMessageView { … }
final class ModalMessageView: UIView, InAppMessageView { … }
final class ModalImageMessageView: UIView, InAppMessageView { … }
final class FullscreenMessageView: UIView, InAppMessageView { … }
final class FullscreenImageMessageView: UIView, InAppMessageView { … }
```

Each view's initialiser takes `(message: GameballInAppMessage, attributes: MessageViewAttributes, image: UIImage?, icon: UIImage?, coordinator: MessageViewCoordinating?)`.

Five classes rather than three with a layout flag: `image_only` is a genuinely different composition, not the other one with text hidden.

- [x] **Step 1: Write the failing layout-resilience tests first**

These are the tests that catch the defects ranked most expensive in the port spec's trap list. Write them before any view exists.

```swift
private let smallScreen = CGSize(width: 320, height: 568)

private func traits(contentSize: UIContentSizeCategory) -> UITraitCollection {
    UITraitCollection(preferredContentSizeCategory: contentSize)
}
```

| Test | Asserts |
|---|---|
| `testModalWithLongCopyDoesNotOverflowOnSmallScreen` | laid out in 320×568, content height ≤ bounds and the scroll view scrolls |
| `testModalAtDoubleTextScaleDoesNotOverflow` | `.accessibilityExtraExtraExtraLarge` |
| `testShortModalStaysShort` | a one-line message is **well under** full height — the obvious "make it scrollable" fix makes every card full-height |
| `testButtonsWrapRatherThanOverflow` | two 25-character labels; total width ≤ container width |
| `testFullscreenLongCopyScrolls` | no clipping |
| `testSlideupFitsItsBandOnly` | height ≤ 120pt, does not fill the screen |
| `testCloseButtonMeetsFortyFourPointTarget` | ≥ 44×44 |
| `testRTLMirrorsFrames` | under `.forceRightToLeft` traits the close glyph sits at the leading (left) edge |
| `testRTLDoesNotMutateGlobalAppearance` | `UIView.appearance().semanticContentAttribute == .unspecified` after building every view |
| `testReduceMotionSkipsEntranceAnimation` | `presented` is true immediately, no animation |
| `testDeadImageURLStillRendersTheMessage` | `image: nil` → header and body still present |

`testRTLDoesNotMutateGlobalAppearance` exists because this repo shipped exactly that bug in `BaseViewController` and fixed it in `8f8f368`.

- [x] **Step 2: Run and watch them fail**

- [x] **Step 3: Implement the views**

Rules that apply to all five:
- Text lives in a `UIScrollView` so copy scrolls rather than clips; the scroll view's height is constrained `<=` the available space with a lower-priority `==` content-height constraint, so a short message stays short.
- Buttons in a `UIStackView` that switches `axis` to `.vertical` when the horizontal intrinsic width exceeds the available width.
- `.preferredFont(forTextStyle:)` everywhere, `adjustsFontForContentSizeCategory = true`, `numberOfLines = 0`.
- **Directional constraints only** (`leadingAnchor`/`trailingAnchor`). Never assign `semanticContentAttribute`. Read `traitCollection.layoutDirection` if a branch genuinely needs direction.
- Colours from `message.style` with `nil` falling back to the host's theme — never a hardcoded literal.
- Entrance: if `UIAccessibility.isReduceMotionEnabled`, skip the animation outright and call `didPresent()` synchronously; otherwise animate 200ms and call `didPresent()` in the completion.
- Slideup: no scrim, swipe-to-dismiss via a `UIPanGestureRecognizer` restricted to its own edge axis, no buttons, whole surface tappable, no gesture that competes with host scroll views.
- Modal/fullscreen: a scrim subview *inside* the message view, tappable only when `message.dismissOnScrimTap`.

- [x] **Step 4: Write `MessageViewTests`** — button tap calls `logClick` with the button id; surface tap calls it without; a nil `clickAction` leaves the surface inert; close button dismisses; scrim tap honours `dismissOnScrimTap`.

- [x] **Step 5: Verify green**

- [x] **Step 6: Commit** — `git commit -m "feat(iam): slideup, modal and fullscreen message views"`

---

## Task 12: Action router

**Files:**
- Create: `Presentation/MessageActionRouter.swift`
- Test: `Tests/GameballTests/MessageActionRouterTests.swift`

**Interfaces produced:**

```swift
final class MessageActionRouter {
    init(openURL: @escaping (URL, Bool) -> Void,
         navigate: @escaping (String, [String: Any]?) -> Void,
         dismiss: @escaping () -> Void)
    /// Returns the url to report alongside the click, when the action opened one.
    func perform(_ action: GameballClickAction) -> String?
}
```

- [x] **Step 1: Write failing tests** — `.dismiss` dismisses; `.openURL(external: false)` opens in-app and returns the url string; `.openURL(external: true)` opens the OS browser; `.navigate` forwards route and arguments untouched and does not dismiss; `.unsupported` logs and does nothing.

- [x] **Step 2: Run and watch it fail**

- [x] **Step 3: Implement.** The in-app browser is `SFSafariViewController` presented from the topmost view controller; external is `UIApplication.shared.openURL` (iOS 11 — `open(_:options:completionHandler:)` is available from iOS 10, use that).

- [x] **Step 4: Verify green**

- [x] **Step 5: Commit** — `git commit -m "feat(iam): click action router"`

---

## Task 13: Token substitution

**Files:**
- Create: `Personalisation/TokenSubstitution.swift`
- Test: `Tests/GameballTests/TokenSubstitutionTests.swift`

**Interfaces produced:**

```swift
enum TokenSubstitution {
    static let pattern = #"\{([A-Za-z_][A-Za-z0-9_]*)\}"#
    /// Cheap `{` scan before the regex, so a message with no token costs one
    /// character comparison and never triggers a variables fetch.
    static func containsToken(_ text: String?) -> Bool
    static func tokens(in message: GameballInAppMessage) -> Set<String>
    static func substitute(_ text: String, values: [String: String]) -> String
    static func apply(values: [String: String],
                      to message: GameballInAppMessage) -> GameballInAppMessage
}
```

- [x] **Step 1: Write failing tests**

| Test | Asserts |
|---|---|
| `testKnownTokenIsSubstituted` | `{points}` → `1,250` |
| `testUnknownTokenIsLeftExactlyAsWritten` | `{mystery}` unchanged — blanking would delete copy a marketer wrote |
| `testValuesAreInsertedVerbatim` | `1,250` keeps its separator; never re-parsed or re-formatted |
| `testSpacedBracesAreNotTokens` | `{ spaced }` untouched |
| `testNumericBracesAreNotTokens` | `{2}` untouched |
| `testLoneBraceIsUntouched` | `{` untouched |
| `testOnePassOnly` | a value containing `{other}` is not expanded again |
| `testAppliesToHeaderBodyAndButtonLabels` | all three |
| `testContainsTokenIsFalseForPlainText` | false |
| `testTokensInMessageCollectsFromAllFields` | header + body + buttons |

- [x] **Step 2: Run and watch it fail**

- [x] **Step 3: Implement.** `NSRegularExpression` built once as a `static let`. Substitute by walking matches in reverse so ranges stay valid, replacing only when the key exists. Strictness matters twice over: a loose pattern lets a value map mangle ordinary copy, and it is also what keeps the feature inert today.

- [x] **Step 4: Verify green**

- [x] **Step 5: Commit** — `git commit -m "feat(iam): strict single-pass token substitution"`

---

## Task 14: Variable source

**Files:**
- Create: `Personalisation/VariableSource.swift`
- Test: `Tests/GameballTests/VariableSourceTests.swift`

**Interfaces produced:**

```swift
final class VariableSource {
    init(transport: IAMTransport, store: IAMStore, customerId: String,
         timeout: TimeInterval = 2, cacheTTL: TimeInterval = 60)
    /// Always calls back — with values, or empty on any failure. Never throws,
    /// never blocks a display.
    func values(neededTokens: Set<String>, completion: @escaping ([String: String]) -> Void)
    /// Called on every event and purchase, before evaluating — never on session start.
    func forgetCachedValues()
    /// Narrows what is persisted to the tokens the held campaigns actually use.
    func setPersistableTokens(_ tokens: Set<String>)
    func clear()
}
```

- [x] **Step 1: Write failing tests**

| Test | Asserts |
|---|---|
| `testSuccessfulFetchReturnsValues` | parsed from `{"variables": {...}}` |
| `testFailureReturnsEmptyNotAnError` | 404/422/503/transport all → `[:]` |
| `testTimeoutReturnsWhatIsHeld` | falls back to persisted values |
| `testValuesAreCachedForTheTTL` | two calls inside 60s → one request |
| `testForgetCachedValuesForcesARefetch` | two requests |
| `testOnlyNeededTokensArePersisted` | `player_email` returned but not persisted when no campaign uses it |
| `testNoNeededTokensPersistsNothing` | store empty |
| `testPersistedValuesSurviveReload` | fallback works |
| `testClearRemovesStoredValues` | store empty |
| `testPendingWriteCannotResurrectClearedValues` | a fetch in flight, `clear()` called, the write must not restore — the customer is re-checked **after** acquiring storage |

The last test encodes a race that was real: a check performed *before* the await always passes, because the clear has not been issued yet.

- [x] **Step 2: Run and watch it fail**

- [x] **Step 3: Implement.** Serial queue; in-memory `[String: String]` plus a fetch timestamp; persisted copy filtered to `persistableTokens`. Re-read the current customer id from the instance *after* the transport completion fires, before writing.

- [x] **Step 4: Verify green**

- [x] **Step 5: Commit** — `git commit -m "feat(iam): variable source with TTL cache and PII-filtered persistence"`

---

## Task 15: The orchestrator

**Files:**
- Create: `InAppMessagingService.swift`
- Test: `Tests/GameballTests/InAppMessagingServiceTests.swift`

**Interfaces produced:**

```swift
public enum GameballDisplayDecision { case show, later, discard }

final class InAppMessagingService {
    init(customerId: String,
         source: MessageSource,
         presenter: MessagePresenting,
         analytics: MessageAnalytics,
         cap: FrequencyCap,
         cache: CampaignCache,
         prefetcher: ArtworkPrefetcher,
         variables: VariableSource,
         router: MessageActionRouter,
         now: @escaping () -> Date = Date.init)

    var isStarted: Bool { get }
    var deferredMessages: [InAppMessageCampaign] { get }    // the stack, for tests

    func start()
    func stop()
    func onSessionStart()
    func onCustomEvent(name: String, properties: [String: Any])
    func onPurchase(productId: String, price: Double, currency: String,
                    quantity: Int, properties: [String: Any]?)
    func onForeground()
    func onBackground()

    var beforeDisplay: ((GameballInAppMessage) -> GameballDisplayDecision)?
    var onActionHandled: ((GameballInAppMessage, GameballMessageButton?, GameballClickAction) -> Bool)?
    var onMessageSelected: ((GameballInAppMessage) -> Void)?
}
```

- [x] **Step 1: Write failing tests**

| Test | Asserts |
|---|---|
| `testNothingHappensBeforeStart` | zero fetches, zero writes, nothing presented |
| `testStartSyncsOnce` | `source.fetchCount == 1` |
| `testFailedSyncFallsBackToCache` | cached campaign selected |
| `testEmptySuccessfulSyncReplacesTheCache` | no campaign selected |
| `testCacheIsAppliedOnlyOnFailure` | a successful sync is never clobbered by a slow cache read |
| `testWarmResumeBeyondSessionTimeoutResyncs` | `fetchCount == 2` |
| `testResumeInsideSessionTimeoutDoesNotResync` | `fetchCount == 1` |
| `testImpressionRecordsCapAndFloorAtVisibility` | not at selection |
| `testMessageDismissedBeforePaintReportsNothing` | no impression, no dismissal |
| `testDismissReportedOnlyWhenShownAndNotEngaged` | tap then dismiss → click only |
| `testButtonTapReportsClickWithButtonId` | present |
| `testSurfaceTapReportsClickWithoutButtonId` | nil |
| `testIsTestCampaignDisplaysAndReportsNothing` | presenter called, analytics empty |
| `testDeferredWhenNoSurface` | on the stack |
| `testDeferredWhenAnotherIsShowing` | on the stack |
| `testBeforeDisplayLaterDefers` | on the stack |
| `testBeforeDisplayDiscardSuppresses` | stack empty, nothing retried |
| `testNewerDeferralMovesToTopOfStack` | order, deduped |
| `testRetryOnDismissalPresentsTheStackTop` | presented |
| `testRetryRechecksAlreadyShownAndTheFloor` | suppressed inside the floor |
| `testSuppressedCampaignIsEligibleNextSessionWithoutReset` | selected |
| `testVariableCacheClearedOnEventNotOnSessionStart` | one fetch on session start, refetch on event |
| `testStopDismissesFlushesAndClears` | all three |
| `testCustomerChangeResetsCapsAndDiscardsCache` | reset |
| `testThrowingHooksAreContained` | a hook that traps is not called; a hook returning garbage does not break the feature |
| `testPurchaseFiresExactlyOneOccurrence` | one evaluation — divergence D3 |

- [x] **Step 2: Run and watch them fail**

- [x] **Step 3: Implement.** One serial `DispatchQueue` owns campaigns, cooldown, the deferred stack and session timestamps. Sync and the cap load are dispatched concurrently; the cache is applied only in the sync-failure branch. `_evaluate(occurrence)` calls `selectCampaign`, notifies `onMessageSelected`, consults `beforeDisplay`, resolves tokens when needed, then presents — mapping a returned obstacle onto the stack. Presentation work hops to main.

Deferral uses a stack with dedup-and-move-to-top (divergence D1). Retry triggers: dismissal, foreground, and a surface appearing.

- [x] **Step 4: Verify green**

- [x] **Step 5: Commit** — `git commit -m "feat(iam): orchestrator with deferral stack and display accounting"`

---

## Task 16: Public API and host wiring

**Files:**
- Create: `GameballApp+InAppMessaging.swift`
- Modify: `Sources/Gameball/GameballApp.swift` — **exactly two added lines**, both guarded
- Test: `Tests/GameballTests/PublicAPITests.swift`

**Interfaces produced:** the public surface from design §9, verbatim.

- [x] **Step 1: Write failing tests** — `isInAppMessagingStarted` false initially; `startInAppMessaging` flips it; delegate assignment before start is honoured; `stopInAppMessaging` flips it back; starting twice for the same customer is idempotent; starting for a different customer resets state; the delegate is held **weakly** (assign a local object, let it deallocate, assert nil); `logPurchase` produces one `purchase` occurrence with the four properties folded in.

The weak-delegate test matters: `GameballApp` is an immortal singleton, so a strong reference would leak the host's view controller for the life of the app.

- [x] **Step 2: Run and watch it fail**

- [x] **Step 3: Implement the extension**

The delegate cannot be a stored property in an extension, and a computed property cannot be `weak`. So an internal coordinator owns it:

```swift
final class InAppMessagingCoordinator {
    static let shared = InAppMessagingCoordinator()
    weak var delegate: GameballInAppMessagingDelegate?
    var service: InAppMessagingService?
    private init() {}
}
```

`GameballApp.inAppMessagingDelegate` is a computed forwarder onto it. The coordinator exists from first access rather than from `startInAppMessaging`, so assigning the delegate before starting works and call ordering does not matter.

Delegate methods are bridged to the service's closures inside `startInAppMessaging`, each call individually guarded and hopping to main.

- [x] **Step 4: Add the two hooks to `GameballApp.swift`**

These are the *only* edits to pre-existing source. Both no-op entirely when the module was never started, so a widget-only integrator is unaffected. Both sit **outside** the existing completion chains, so a fault in our addition cannot escape into the widget's code path.

In `initializeCustomer`, immediately after `self.customerId = request.customerId`:

```swift
// In-app messaging: additive and guarded. No-op unless startInAppMessaging ran.
InAppMessagingCoordinator.shared.notifyCustomerChanged(request.customerId)
```

In `sendEvent`, immediately after the `networkManager.sendEvent(...)` call returns control (not inside its completion):

```swift
// In-app messaging: additive and guarded. No-op unless startInAppMessaging ran.
InAppMessagingCoordinator.shared.notifyEvents(event.events)
```

Both coordinator methods begin `guard let service = service, service.isStarted else { return }` and wrap their body so nothing can propagate.

- [x] **Step 5: Register lifecycle observers**

On first `startInAppMessaging`, observe `UIApplication.didBecomeActiveNotification` and `didEnterBackgroundNotification`. The iOS SDK has no lifecycle observer today, so this is new internal machinery. Backgrounding forces an analytics flush.

- [x] **Step 6: Verify green, and verify the widget path is untouched**

Run: `./Scripts/test.sh test`
Then confirm by inspection that `git diff` against pre-existing files shows only the two added hook lines plus their comments.

- [x] **Step 7: Commit** — `git commit -m "feat(iam): public API, delegate and guarded host wiring"`

---

## Task 17: End-to-end and compatibility

**Files:**
- Test: `Tests/GameballTests/EndToEndTests.swift`, `Tests/GameballTests/CompatibilityTests.swift`

- [x] **Step 1: Write the end-to-end test**

Drive the whole module through the **public API only**, against `StubMessageSource` and a headless presenter: start → a session-start campaign renders → tap the button → it dismisses → assert an `impression` and a `click` were reported with the right campaign and button ids. This is the test that catches wiring mistakes every unit test passes — the port spec's trap list has a case where filters were fully unit-tested and completely dead because the event hook never passed properties through.

- [x] **Step 2: Write the compatibility tests**

| Test | Asserts |
|---|---|
| `testWidgetPathWorksWithoutStartingInAppMessaging` | `init` + `initializeCustomer` + `sendEvent` behave exactly as before; zero IAM requests, zero IAM storage writes |
| `testStartingInAppMessagingDoesNotAffectWidgetCalls` | both coexist |
| `testIAMStorageIsInItsOwnSuite` | `UserDefaults.standard` has no `gameball_iam_*` keys |
| `testNoIAMTimersBeforeStart` | none |

- [x] **Step 3: Run the full suite** — `./Scripts/test.sh test`

- [x] **Step 4: Commit** — `git commit -m "test(iam): end-to-end and widget-compatibility coverage"`

---

## Task 18: Documentation and version

**Files:**
- Modify: `README.md` (add an in-app messaging section), `CHANGELOG.md`, `MIGRATION.md`
- Modify: `Sources/Gameball/Constants.swift` — `SDKInfo.version` to `3.3.0`
- Modify: `Gameball.podspec` — `s.version` to `3.3.0`

- [x] **Step 1: Document the public API** — `startInAppMessaging`, `stopInAppMessaging`, `isInAppMessagingStarted`, `inAppMessagingDelegate`, `logPurchase`, the four delegate methods with their defaults, and a worked example. State plainly that the module is opt-in and that existing widget integrations are unaffected by upgrading.

- [x] **Step 2: Changelog and migration** — a `3.3.0` entry describing the new module; in `MIGRATION.md`, note that no migration is required and nothing changes for widget-only integrators.

- [x] **Step 3: Bump the version in both places** — `Constants.swift` and the podspec must agree; `sdkVersion` in the sync body reads from `SDKInfo.version`.

- [x] **Step 4: Full suite green** — `./Scripts/test.sh test`

- [x] **Step 5: Commit** — `git commit -m "docs: document in-app messaging and bump to 3.3.0"`

---

## Self-Review

**1. Spec coverage.** Walked every section of the design against the tasks:

| Design section | Task |
|---|---|
| §1 module layout | 2–16 (every file placed) |
| §2 lifecycle, session timeout, concurrent sync/history, cache-on-failure-only | 15 |
| §2.1 artwork, 5s bound, concurrency, `http://` log | 9, plus the log in 3 |
| §3 evaluation, stable tie-break, floor placement | 4 |
| §4 presentation: window, level, passthrough, five views, `didPresent`, orientation, RTL, layout, accessibility, reduce motion, deferral | 10, 11 |
| §5 networking, v4.0 pin, platform code, no `NetworkManager` reuse | 6 |
| §6 analytics, uid, outbox rules, status mapping, poison batch, `isTest` | 8, 15 |
| §7 personalisation, strictness, TTL, PII filter, write-after-clear race | 13, 14 |
| §8 persistence, suite, customer scoping, raw payload, no read timeout | 5, 7 |
| §9 host API, delegate, weak storage, polarity, `logPurchase`, wiring | 16 |
| §10 diagnostics | every task (log lines specified inline) |
| §11 testing, harness, matrix, layout assertions, live fixture, e2e | 1, 3, 11, 17 |
| §12 divergences D1–D5 | D1/D2 in 10 and 15, D3 in 15, D4 in 5, D5 in 16 |
| §14 phases | tasks grouped 1–5 / 6–8 / 9–12 / 13–14 / 15–18 |

Two gaps found and fixed while reviewing: the `http://` artwork warning had no home, so it is now specified in Task 3's `normalisedURL`; and the widget-isolation guarantee had no test, so `CompatibilityTests` was added to Task 17.

**2. Placeholder scan.** No "TBD", no "add error handling", no "similar to Task N", no "write tests for the above". Every test step names its assertions; every non-obvious implementation step carries code.

**3. Type consistency.** Checked the names used across task boundaries: `IAMTransport.post` is consumed identically by `HTTPMessageSource` (6), `BatchedMessageAnalytics` (8) and `VariableSource` (14). `IAMStore` is consumed by `FrequencyCap` (4), `CampaignCache` (7), `BatchedMessageAnalytics` (8) and `VariableSource` (14). `MessageViewCoordinating` is produced in 10 and consumed by all five views in 11. `PresentationObstacle` is returned in 10 and mapped to the stack in 15. `GameballDisplayDecision` is declared in 15 and surfaced publicly in 16. One inconsistency found and fixed: the evaluator originally read the prefetcher directly, which would have broken its purity — artwork readiness is now the injected `isArtworkReady` closure in Task 4's signature.
