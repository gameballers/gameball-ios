# In-App Messaging — iOS SDK Design

**Status:** approved for planning · **Date:** 2026-08-18 · **Target:** `Gameball` iOS SDK 3.3.0

## Three sources, three roles

Confusing these is how a port goes wrong, so they are named explicitly:

| Source | Role | Authority |
|---|---|---|
| `docs/reference/in-app-messaging-port-specification.md` (in `gameball-flutter`) | **What** the feature does — invariants, display rules, wire contract | Binding for behaviour |
| `braze-swift-sdk` 18.1.0, `Sources/BrazeUI` | **How** presentation should look in Swift | Reference for the presentation layer |
| Swift API Design Guidelines + Apple/community convention | **How** everything else should look | Reference for models, storage, networking, testing, naming |

The Flutter implementation is a **guide to what we built**, not a template for Swift. Its file layout,
async style and widget decomposition are Dart artifacts and are not reproduced.

`BrazeKit` is deliberately *not* a structural reference. It is a monolithic core — analytics, push,
lifecycle, geofences, storage — shipped as a `binaryTarget`, so it is both unreadable and not
in-app-messaging-specific. Where this design needed an answer BrazeKit would have held, it follows
Swift community convention instead.

## Scope

Build the **presenter and its supporting layers**, not a public UI framework. Every type ships
`internal` except the documented host surface in §9. The seams that would let this become a
themeable kit later are kept only where they are *also* the simpler choice today; everything else is
dropped, and Swift's `internal → public` being purely additive is what keeps that reversible.

Out of scope, per port spec §14: `HtmlFullscreen` (type 4), `EmailCapture` (type 5) and the `submit`
event, video media, the `log_event` / `log_attribute` / `request_push_permission` actions, custom
fonts, `allowedAssetUrls`, dayparting, `quietHours`, `campaignOrdering`. An unknown `messageType`
must skip safely so these arrive as no-ops when the backend starts sending them.

## Platform floor

Unchanged: `Package.swift` `.iOS(.v11)`, `swiftLanguageVersions: [.v4_2]`, podspec `11.0` / `4.2`.

Verified nothing in this module needs more. Own `UIWindow`, directional Auto Layout, Dynamic Type,
`isReduceMotionEnabled`, `SFSafariViewController`, `UserDefaults`, `URLSession`, `UUID`,
`ISO8601DateFormatter` and `NSCache` are all iOS 11 or earlier. `UIWindowScene` is the iOS 13 branch
and is required at any floor below 13, so the dual path exists regardless.

Two consequences to accept rather than discover later:

- **No `async`/`await`, no actors, no `Sendable`, no `@MainActor`.** Concurrency is a serial
  `DispatchQueue` for state isolation plus `@escaping` completions carrying `Result`. Main-thread
  contracts are documented and `assert`-ed in debug rather than enforced by the compiler.
- iOS 11 cannot be exercised on a simulator here (lowest installed runtime is iOS 26.5) and warns
  under Xcode 26 for pod consumers. "Supports iOS 11" is therefore an untested claim — pre-existing,
  and out of scope for this work.

## 1. Module layout

```
Sources/Gameball/InAppMessaging/
  InAppMessagingService.swift          orchestrator; the only owner of mutable module state
  IAMLog.swift                         [GameballIAM] diagnostics — never posts to the backend
  Models/
    InAppMessageCampaign.swift         identity, priority, expiry, repeat rule, responseIndex
    InAppMessage.swift                 the renderable message
    MessageTrigger.swift               sessionStart | event(name, filters, logicalOperator)
    PropertyFilter.swift               operator vocabulary + matching
    MessageAction.swift                dismiss | openUrl | navigate | unsupported
    MessageStyle.swift                 colours, alignment, button styles
  Source/
    MessageSource.swift                protocol + SyncResult
    MessageParser.swift                every leniency rule from port spec §3
    HTTPMessageSource.swift            transport only
    CampaignCache.swift                last good raw payload, per customer
    StubMessageSource.swift            fixture-driven; tests and debug builds
  Evaluation/
    TriggerEvaluator.swift             pure selection — free functions, `now` passed in
    FrequencyCap.swift                 CapState, display history
  Presentation/
    InAppMessageView.swift             protocol + protocol-extension lifecycle
    MessageWindowPresenter.swift       coordinator: validation, window, teardown, auto-dismiss
    MessageWindow.swift                UIWindow subclass, passthrough hitTest
    MessageViewController.swift        orientation, status bar, accessibility
    PresentationContext.swift          message + attributes + windowLevel + scene
    Views/
      SlideupMessageView.swift
      ModalMessageView.swift
      ModalImageMessageView.swift
      FullscreenMessageView.swift
      FullscreenImageMessageView.swift
      MessageButtonView.swift
      MessageCloseButton.swift
    MessageActionRouter.swift          dismiss / open_url / navigate, delegate consulted first
    ArtworkPrefetcher.swift            bounded concurrent warm + NSCache
  Analytics/
    MessageEvent.swift                 eventUid (UUID v4), type, occurredAt
    MessageAnalytics.swift             protocol
    BatchedMessageAnalytics.swift      outbox, flush triggers, retry/discard mapping
  Personalisation/
    TokenSubstitution.swift            {token} detection + one-pass substitution
    VariableSource.swift               fetch, 60s cache, PII-filtered persistence
  Storage/
    IAMStore.swift                     protocol + UserDefaults suite impl + in-memory double
  GameballApp+InAppMessaging.swift     the public surface
```

Port spec §2's seven responsibilities map one-to-one onto Source, Cache, Evaluator, FrequencyCap,
Presentation, Analytics and Personalisation, with `InAppMessagingService` as the orchestrator. Every
one of them sits behind a protocol so the conformance suite can substitute it.

## 2. Lifecycle and sessions

Nothing runs before `startInAppMessaging`: no requests, no timers, no storage writes, nothing drawn.
That is testable and is in the conformance matrix.

A session starts when the host opts in, identifies a **different** customer, or returns to the
foreground after more than the session timeout in the background. Each session start triggers exactly
one sync.

**Session timeout is 30 seconds, deliberately equal to the display cooldown.** A message can only
display in the foreground, so time-since-last-display is always at least time-spent-in-background;
aligning the two guarantees the cooldown can never suppress a warm session-start message. Lowering it
reintroduces that gap.

The sync request and the display-history read run **concurrently**, not in series — the stored history
gates the decision, not the request. The cache is applied **only when the sync failed**, which is both
the backend's rule and what removes the race the concurrency creates, where a slow cache read lands
after a fast sync and clobbers fresher campaigns.

`stopInAppMessaging` dismisses what is showing, flushes telemetry, cancels timers and clears
per-customer state. A stopped module holds no timers, so retry after that point is the next `load`'s
job rather than a timer's — which is what stops a failed send re-arming forever after logout.

Foreground/background transitions come from `NotificationCenter`. Backgrounding forces an analytics
flush.

## 2.1 Artwork

Every held campaign's `imageUrl` and `iconUrl` are warmed at sync, before anything displays — not just
the winner's, because an event trigger fires with no warning and no time to fetch. A campaign whose
artwork fails is passed over at selection, letting a lower-priority ready campaign take the slot.

Bounded at **5 seconds per campaign, loaded concurrently**, so the ceiling is the slowest single image
rather than the sum. Failure is per sync, not permanent: the next sync re-evaluates. Decoded images
are held in an `NSCache` so the display path never re-decodes.

`URLSession` handles the transport; there is no third-party image dependency, which matches BrazeUI —
it has none either and exposes a provider seam for animated GIFs instead. We do not need that seam
yet.

Artwork served over `http://` is logged explicitly. App Transport Security blocks cleartext by
default, so the load fails, the campaign is passed over, and the only symptom is a campaign that
silently never shows.

## 3. Evaluation

`TriggerEvaluator` is **free functions with no stored state**: `selectCampaign(occurrence:campaigns:
capState:now:cooldown:) -> InAppMessageCampaign?`. No network, no UI handle, and `now` is a
parameter — port spec §2 requires this and it is what makes every display rule testable in
microseconds.

Selection order (port spec §5.2, invariant): trigger match → drop expired → repeat rule → drop
unsupported type → drop artwork-not-ready → if empty return nil → **then** the global cooldown floor
→ sort by priority descending, ties on response order.

Two details that are load-bearing:

- **The floor is checked after eligibility and before sorting.** Inside the floor nothing displays at
  all; it is not per campaign.
- **The tie-break is response order, so the sort must be stable.** Swift's `sort` is *not*
  guaranteed stable, so `InAppMessageCampaign` carries `responseIndex` assigned at parse and the
  comparator falls back to it. This is port spec §13's non-stable-sort trap.

Expiry is re-checked at selection, not only at fetch, because campaigns are cached for the session.

## 4. Presentation

Braze's answers, adopted. Rationale is in the research notes; the decisions are:

**Window.** `MessageWindow: UIWindow` created per presentation, at `windowLevel = .normal` — a
separate window created later at the same level already sits above the host, and `.normal` correctly
stays below the status bar and system alerts. `Window(windowScene:)` on iOS 13+, `Window(frame:
UIScreen.main.bounds)` below, with the scene stored as `Any?` behind a casting accessor so an iOS 13
type can appear in the API at an iOS 11 floor. Shown with `isHidden = false`, **never**
`makeKeyAndVisible`, so the host keeps its keyboard and first responder; views that need to dismiss
the keyboard call an explicit `makeKey()`. Torn down in `didDismiss()`: invalidate the timer, remove
the view, nil the scene then the window.

Building the window per presentation is how port spec §13's trap #4 — a stale surface handle
surviving a hot restart — becomes structurally impossible rather than merely avoided.

**Touch passthrough.** One rule in `hitTest`, not a per-type branch: return the hit view only when
it is, or is contained by, an `InAppMessageView`; otherwise `nil`. Slideup then passes touches
through automatically because it occupies only its own band, and modal and fullscreen block because
their scrim is part of the view. This is the whole of port spec §6.5's "app usable underneath".

**Five view classes**, because `image_only` is a different composition rather than the other one with
text hidden (port spec §6.5, and Braze ships them as separate classes for the same reason):
slideup, modal, modal-image, fullscreen, fullscreen-image.

**The view contract.** `InAppMessageView` is a protocol on `UIView` requiring only `presented`,
`present(completion:)` and `dismiss(completion:)`. A protocol extension provides `willPresent()`,
`didPresent()`, `willDismiss()`, `didDismiss()`, `logImpression()`, `logClick(buttonId:)` and
`process(action:buttonId:)`. Views hold a `weak` reference to the coordinator, injected at init —
simpler than Braze's responder-chain discovery, which exists only to wire host-supplied views we are
not supporting yet.

**Impression timing.** `didPresent()` is the single anchor, fired after the entrance animation
completes and the message is actually visible. The impression, the frequency-cap record and the
auto-dismiss timer all hang off it. If the app is backgrounded in that instant the callback never
fires and nothing is reported, which is correct (port spec §6.2, port spec §13 trap #3).

**Orientation is constrained, not deferred.** `MessageViewController` reports
`supportedInterfaceOrientations` derived from the message's orientation and observes
`UIDevice.orientationDidChangeNotification`, so a fullscreen message adopts its orientation instead
of waiting for the user to rotate. On iOS 16+ it also calls
`setNeedsUpdateOfSupportedInterfaceOrientations()` on the host's topmost controller during teardown.
**This diverges from port spec §6.1/§6.5** — see §12.

**RTL by reading the trait, never by setting one.** All layout uses directional constraints
(`leadingAnchor`/`trailingAnchor`, `NSDirectionalEdgeInsets`) and any direction-dependent branch
reads `traitCollection.layoutDirection`. `semanticContentAttribute` is never assigned, and
`UIView.appearance()` is never touched. This repo shipped
`UIView.appearance().semanticContentAttribute = .forceRightToLeft` — a global mutation of the host
app's layout direction — and fixed it in `8f8f368` on 2026-07-06. Reading the trait makes that class
of bug unrepeatable rather than merely avoided.

**Layout resilience is default, not remedial** (port spec §6.6): text in a `UIScrollView` so copy
scrolls rather than clips, content-hugging so a short message stays short, buttons in a wrapping
stack, `.preferredFont(forTextStyle:)` throughout, `minWidth` 320 and size-class-aware max
dimensions.

**Accessibility**, none of which the port spec mentions: `accessibilityViewIsModal = true` on the
window for modal and fullscreen (false for slideup, which is non-blocking); `UIAccessibility.post(
notification: .screenChanged,…)` in `didPresent()` so VoiceOver moves focus; a 44×44pt minimum touch
target on the close button per the HIG; the close button's accessibility label taken from the
platform's localised string rather than a hardcoded "Close".

**Reduce motion**: when `UIAccessibility.isReduceMotionEnabled`, skip entry animations outright
rather than shortening them.

**Deferral.** A presentation that cannot proceed returns a failure rather than throwing, which is
what feeds the deferral path. Deferred messages go on a **stack** with dedup-and-move-to-top; the
port spec's guarantees are preserved — at most one displayed, the floor re-checked on retry,
already-shown re-validated. **Diverges from port spec §6.1** — see §12.

## 5. Networking

A dedicated client over `URLSession` with `Codable` models and `Result` completions, behind a
protocol so the suite stubs the transport. It reuses the existing auth header logic (`APIKey`,
`x-gb-agent`, `lang`) and **nothing else**. It deliberately does not build on `NetworkManager`:

- `load`, `loadDebug` and `loadImage` return without invoking their completion when `Reachability`
  reports offline — the `completion(...)` call is commented out. A caller awaiting that closure waits
  forever. Invisible today only because `loadBotSettings` discards its result.
- `URLRequest.init` does `httpBody = try! JSONSerialization.data(...)` and `URL.init` ends with
  `self = (components?.url)!` — two force-unwraps that crash the host on bad input, inside a module
  whose first invariant is never throwing into the host.
- The `URL` extension routes `/events` and `/customers` to v4.1 when a session token is present.
  Port spec §4 forbids that for these endpoints: `/api/v4.1/…/inapp-messages/sync` answers **401**
  to APIKey auth. Our paths do not match its prefix check today, but relying on that is fragile.

All three endpoints are **pinned to v4.0** and identify the customer by `customerId` in the body.
`platform` is always `1`; a value other than 1 or 2 is logged loudly before sending, because the
backend answers `200` with an empty message list rather than an error and the symptom is a feature
that silently does nothing.

## 6. Analytics

`eventUid` is `UUID().uuidString.lowercased()`, generated once when the event is created and **never
regenerated on retry** — a non-GUID is a hard 400 that discards the whole batch, and a test asserts
the v4 shape so a refactor cannot silently break ingestion. `occurredAt` is device time at the moment
it happened, never send time.

Outbox: in-memory buffer persisted after every change, flush at 10 events or 30s, chunked at 50 per
request, ceiling 500 with oldest-dropped-and-logged, one request in flight. Forced flush on
background, on `stopInAppMessaging`, and before an `open_url`/`navigate` action — that last one
bounded at 800ms, since the events are on disk either way and a dead network must not delay a tap.

Status mapping (port spec §4.2): `2xx` accept and clear; `400`/`401`/`404`/`422` discard permanently
and log loudly; `408`/`429`/`5xx`/network/timeout retry and keep. A poison batch must be discarded
rather than retried forever — the outbox is FIFO, so one permanently-rejected batch at the head takes
every event behind it down until the ceiling rotates it out.

`isTest` campaigns display normally and report nothing.

## 7. Personalisation

**Updated 2026-08-25.** This section was written when the backend substituted at sync and no live
message carried a token, and it described the module as "currently inert, built anyway; it activates
by itself". It has since activated. The variables endpoint deployed on 2026-08-24, sync stopped
substituting, and five of the fifteen live campaigns now ship raw tokens — so substitution is the
SDK's job and the endpoint is asked **once per trigger**, not once per session.

A value the backend returns as `""` is substituted as empty. That is deliberate and shared across
every Gameball SDK: `Welcome {player_name}!` renders as `Welcome !` for a customer with no name on
file. Supplying a default belongs in the campaign, not in the client — a later enhancement, not a
client-side workaround.

Tokens are `{name}` — single braces, `[A-Za-z_][A-Za-z0-9_]*`, matched strictly so `{ spaced }`,
`{2}` and a lone `{` are not tokens. A cheap `{` scan precedes the regex, so a message with no token
costs one character comparison and never calls the endpoint. Substitution is one pass over header,
body and button labels; values are inserted verbatim; an unmatched token is left exactly as written.

Fetch is bounded at 2s and cached 60s per customer. The cache is dropped on **every event and
purchase, before evaluating** — and not on session start, because the campaign this exists for is
"you just earned 200 points, you now have X" and a value cached before the purchase quotes the
number from before it.

Persisted values are filtered to **only the tokens the held campaigns actually use**, derived after
each sync. The endpoint returns `player_name`, `player_last_name` and `player_email`; this is the
module's only PII at rest, so a campaign set mentioning no tokens stores nothing at all. Cleared on
logout and customer change, storage included. A pending write must re-check the current customer
*after* acquiring storage, not before — a check before the await always passes, because the clear has
not been issued yet.

## 8. Persistence

One `UserDefaults(suiteName:)` behind an `IAMStore` protocol, `Codable` + `JSONEncoder` for values —
not `NSKeyedArchiver`, which couples the on-disk format to class names. The suite keeps our data out
of the host's preferences plist; the protocol means tests inject an in-memory double and the suite
exists only in production.

Four stores, keyed per customer as **one slot stamped with the customer id, discarded on mismatch at
read** — not one key per customer, which would retain every previous customer's data indefinitely,
including the PII above.

| Store | Survives restart because |
|---|---|
| `gameball_iam_display_history` | a "once ever" campaign would otherwise show again on every launch |
| `gameball_iam_campaign_cache` | a failed sync must fall back to the last good payload |
| `gameball_iam_analytics_outbox` | an impression logged before a force-quit must still arrive |
| `gameball_iam_variables` | a failed fetch must fall back to real values, not raw braces |

Flutter's key names are kept so cross-SDK debugging lines up. The campaign cache stores the **raw
payload** and is re-parsed on read, so there is no serialiser to keep in step with the model and a
payload a newer SDK rejects is not resurrected as stale objects. A corrupt store is logged,
discarded, and messaging starts anyway.

Display history grows without pruning, deliberately: the backend stops returning a non-repeatable
campaign once its impression lands, so forgetting it could show a once-ever message twice.

**No 2-second read timeout.** Port spec §10 requires one because Flutter's `shared_preferences`
crosses a platform channel that can wedge, which no `try` catches. `UserDefaults` is in-process and
synchronous, so the bound would be ceremony. Reads stay off the display-critical path instead.

## 9. Host API

Four entry points, four hooks, and the existing calls wired rather than new ones added.

```swift
public extension GameballApp {
    func startInAppMessaging(customerId: String,
                            delegate: GameballInAppMessagingDelegate? = nil)
    func stopInAppMessaging()
    var isInAppMessagingStarted: Bool { get }

    /// Computed forwarder — see the storage note below.
    var inAppMessagingDelegate: GameballInAppMessagingDelegate? { get set }

    func logPurchase(productId: String, currency: String, price: Double,
                     quantity: Int = 1, properties: [String: Any]? = nil,
                     completion: ((Bool, String?) -> Void)? = nil,
                     sessionToken: String? = nil)
}

public protocol GameballInAppMessagingDelegate: AnyObject {
    func gameball(_ app: GameballApp,
                  displayChoiceFor message: GameballInAppMessage) -> GameballDisplayDecision
    func gameball(_ app: GameballApp,
                  shouldProcess action: GameballClickAction,
                  buttonId: String?,
                  for message: GameballInAppMessage) -> Bool
    func gameball(_ app: GameballApp, navigateTo route: String, arguments: [String: Any]?)
    func gameball(_ app: GameballApp, didPresent message: GameballInAppMessage)
}
```

Every method has a default implementation in a protocol extension, so each is individually optional
and the defaults are the port spec's fallbacks — `.show`, and `true`. All are called on main.

Sender-first, per UIKit convention and Braze's own shape. The sender is redundant with a singleton,
but including it keeps the method names from colliding with anything in the conforming class — a host
view controller with its own `didPresent(_:)` would otherwise silently satisfy the protocol.

**Delegate storage.** Swift forbids stored properties in extensions, and a computed property cannot be
`weak`, so `inAppMessagingDelegate` is a computed forwarder onto a `weak` stored property on an
internal module coordinator. The coordinator is created on first access rather than by
`startInAppMessaging`, so assigning the delegate before starting works and call ordering does not
matter. This also keeps `GameballApp.swift` untouched.

A **delegate rather than closures**, for a reason that is not taste: `GameballApp` is a singleton
that lives for the whole process, so a closure hook retains whatever it captures forever, and a host
writing `beforeDisplay: { self.pause() }` leaks that view controller and its view hierarchy silently.
`weak` makes that impossible. Braze reaches the same conclusion — `public weak var delegate`, with
"the delegate is not retained" in the doc comment.

`shouldProcess` follows **Braze's polarity**: `true` (the default) means the SDK handles the action.
Flutter's `onAction` returns `true` to mean the *host* handled it. Same capability, inverted boolean —
and adopting Braze's naming with Flutter's polarity would silently invert behaviour for anyone
migrating from Braze.

`logPurchase` mirrors Braze's signature including its argument order (`productId, currency, price,
quantity, properties` — currency before price). It is a first-class method there, not a convenience
over `logCustomEvent`, which settles the scope question. Internally the routing is Gameball's: port
spec §3.6 has no purchase trigger type, so it becomes **one** occurrence of an event named `purchase`
with the four fields folded into properties. See §12 on the single fire.

Wiring, each guarded individually and placed outside any existing callback chain that lacks error
handling, so a throw in our addition cannot escape into someone else's path:

- `initializeCustomer` → customer-change notification
- `sendEvent` → one occurrence per entry in `Event.events`, carrying that entry's properties. Port
  spec §13's trap #7 is that Flutter passed only the name and left every filtered campaign dead, so
  the properties must reach the evaluator and a test must prove it end-to-end.
- App lifecycle → `NotificationCenter` observers for foreground/background, registered on first
  `startInAppMessaging`. The iOS SDK has none today, so this is new internal machinery.

Swift's error model means a non-throwing delegate method cannot throw, so port spec §9's per-hook
`try`/`catch` is structurally satisfied. What is guarded instead is re-entrancy — a hook calling back
into the SDK — and thread affinity.

## 10. Diagnostics

`IAMLog` prefixes `[GameballIAM]` and writes to the console only. It is deliberately separate from
`GameballLogger`, which posts to `/mobile/logs`: parse and evaluation diagnostics belong in the
integrator's console, not in a network request.

Since the module never throws, a log line is the only evidence of why something did not happen. Every
item in port spec §11 must be answerable from the log alone — including the ones easiest to omit: a
campaign passed over because artwork was not ready, a pending message displaced by a newer one naming
both, a batch discarded rather than retried and the status that decided it, an unrecognised platform
code, and artwork served over `http://` (which both platforms block by default, so the only symptom
is a campaign that silently never shows).

## 11. Testing

**Fix the harness first.** Today `Tests/GameballTests/GameballTests.swift` calls `Gameball()`, a type
that does not exist, so the test target does not compile — there is no green baseline. Two further
obstacles, both verified:

- `swift build` / `swift test` cannot build this package at all: no UIKit on macOS.
- `xcodebuild` in the repo root resolves the `_Pods.xcodeproj` symlink and builds a stale Pods
  project that fails on 13 XIBs no longer present.

A clean build was only obtained via a symlink farm outside the repo. Phase 1 must establish a single
documented command that works, because every later phase depends on it.

Then port spec §12's matrix in XCTest — parsing, selection, display, layout resilience, artwork,
analytics, personalisation, lifecycle, end-to-end. Protocol seams everywhere and injected doubles; a
`headless` flag on the presenter so display tests run without a host app.

Layout resilience asserts rather than eyeballs: instantiate at 320×568 and at
`.accessibilityExtraExtraExtraLarge` via trait override, assert no overflow with
`systemLayoutSizeFitting`, assert a short message stays short, assert two long localised button
labels wrap. RTL asserts mirrored frames **and** that `UIView.appearance().semanticContentAttribute`
is unchanged afterwards. No screenshots — they rot and need a host app.

Two tests that catch what units miss: drive the whole module through the public API against a stubbed
source and assert a message renders, a tap dismisses it and analytics were reported; and parse
`gameball-flutter/test/fixtures/v4-sync-response.json`, a payload captured from the live backend,
which caught two real defects in Flutter that reading the documentation did not.

## 12. Divergences from the port specification

Recorded because port spec §0 labels these sections INVARIANT, and a silent divergence is a bug.

| # | Divergence | Reason |
|---|---|---|
| D1 | **Stack of deferred messages**, not one pending slot | Port spec §0.5 instructs re-deciding per platform. `braze-swift-sdk` exposes `public internal(set) var stack` with a public `presentNext()` and dedup-and-move-to-top; a single slot that silently displaces is a visible reduction against the SDK we are benchmarked on. Costs an array instead of an optional. Conflicts with port spec §12's "a newer deferral displaces an older one". |
| D2 | **Orientation constrained, not deferred** | Braze sets `supportedInterfaceOrientations` from the message and observes rotation, so the message adopts its orientation immediately instead of waiting for the user. Better UX and removes a deferral branch. Conflicts with port spec §6.1/§6.5 and port spec §12's "refused message retried on rotation". |
| D3 | **A purchase fires one occurrence** | Flutter's `logPurchase` calls `sendEvent` (which already feeds the trigger engine) *and* `onPurchase`, evaluating twice. Usually masked by the cooldown floor, but if the first deferred the second re-selects the same campaign and logs a spurious displacement. Port spec §3.6's text describes one occurrence. |
| D4 | **No 2s storage read timeout** | Guards a Flutter platform-channel hazard that does not exist for in-process `UserDefaults`. |
| D5 | **`shouldProcess` polarity** | Braze's `true` = SDK handles. Naming-and-polarity, not behaviour: the host can still suppress SDK handling. |

D1 and D2 make iOS *more* capable than Flutter and mean the four conformance suites stop being
line-for-line comparable at those points. Accepted deliberately; port spec §0 asks each port to
follow its platform.

## 13. Open questions

| # | Question | Blocks |
|---|---|---|
| O22 | What to do with a token still unresolved after substitution. Port spec §8.4 says do not decide per SDK. Assumption: match Flutter's fail-open (display raw text), the only choice that avoids the divergence §8.4 warns about. Needs product sign-off. | nothing now |
| O19 | The V4 endpoints are on alpha only; production returns a bare 404. **An alpha API key and base URL are needed** to verify the wire contract. Phases 1–4 build against the captured fixture and a stub source. | phase 2 verification |
| O13/O21 | Sync will stop substituting variables. If that lands before the variables endpoint deploys, every personalised campaign shows raw braces. | **Occurred 2026-08-24, without the gap** — the endpoint deployed alongside, so tokens resolve. See §7. |
| O20 | `quietHours` model still to come. A message caught by a window must be **suppressed, not deferred** — "retry when it ends" would never fire from an in-memory stack. | future work |
| — | D1/D2 above: confirm the divergences, or hold Flutter parity. | phase 3 |

## 14. Phases

Each is independently reviewable; the acceptance bar is the relevant slice of port spec §12.

1. **Foundations** — test harness fixed and a documented build/test command; models, parser,
   evaluator, frequency cap, `IAMStore`, `IAMLog`. No networking, no UI. Bar: parsing and selection
   suites green, including the live fixture.

   In parallel, the port spec §0.5 research document. The presentation findings that drove §4 of this
   design are already read from source and cited here; what remains is to formalise them with
   `file:line` tags and cover what has not been read — dismissal and entrance animation behaviour,
   keyboard handling, `ButtonView`/`StackView` layout specifics — plus the BrazeKit-side claims, which
   can only be `[doc]` because that target ships as a binary.
2. **Transport** — sync and events clients, `CampaignCache`, `BatchedMessageAnalytics`. Bar: every
   status in port spec §4.2 produces the right outcome; outbox survives a restart; `eventUid` shape asserted.
3. **Presentation** — window, view controller, five views, action router, artwork prefetcher.
   Largest phase. Bar: display, layout-resilience and artwork suites green.
4. **Personalisation** — token substitution, variable source, PII-filtered persistence.
5. **Integration** — host API, delegate, `logPurchase`, lifecycle observers, end-to-end tests,
   README / CHANGELOG / MIGRATION, version bump to 3.3.0.

## 15. References

- Port specification: `gameball-flutter/docs/reference/in-app-messaging-port-specification.md`
- Wire contract: `gameball-flutter/docs/reference/backend-sdk-endpoints-reference.md`
- Live payload fixture: `gameball-flutter/test/fixtures/v4-sync-response.json`
- Presentation reference: `braze-swift-sdk` 18.1.0, `Sources/BrazeUI/InAppMessageUI/`
- RTL precedent in this repo: commit `8f8f368`
