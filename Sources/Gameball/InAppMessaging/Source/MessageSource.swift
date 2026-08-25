//
//  MessageSource.swift
//  Gameball
//

import Foundation

/// The display floor applied when the backend does not send one.
///
/// Lives here rather than beside the frequency cap because the sync payload is what
/// carries `cooldownSeconds`, and the parser needs the default before a cap exists.
let defaultDisplayCooldown: TimeInterval = 30

/// How long a slideup stays up when the campaign does not say.
///
/// Six of the seven campaigns on the reference account send no `autoDismissSeconds`, no
/// `closeBehaviour` and no buttons, which means the default *is* the behaviour for almost every
/// slideup in the wild. A swipe is always available, but a swipe is a gesture nobody announces,
/// so without a timer the banner sits over the host app for the rest of the session.
///
/// Seven seconds is roughly one to notice the animation, four and a half to read a fifteen-word
/// slideup at a cautious 200 words per minute, and a second and a half to decide and reach for
/// it. It sits between Braze's five-second slideup default and Material's ten-second "long"
/// snackbar, and just under the eight seconds chosen by the one campaign on the account that
/// asked for a duration at all — so a campaign that wants longer still gets a visible difference
/// by saying so.
///
/// Slideups only. A modal or a fullscreen takes the screen deliberately, and timing one out
/// would pull content the customer is reading.
let defaultSlideupAutoDismiss: TimeInterval = 7

/// Backoff for retrying a sync that failed in a way that could plausibly succeed.
///
/// Two attempts, roughly a second and then three. Long enough to outlast the radio waking from
/// idle or a cell handoff — the failures that actually happen at launch, which is exactly when
/// sync runs — and short enough that a session-start message still arrives while the session is
/// worth showing one in.
let defaultSyncRetryDelays: [TimeInterval] = [1, 3]

/// The outcome of one sync: the campaigns to hold for this session, the display floor
/// they are subject to, and the bytes that produced them.
struct SyncResult {
    let campaigns: [InAppMessageCampaign]
    let cooldown: TimeInterval

    /// The account's quiet window, or `nil` when it has none or sent one we cannot read.
    /// Both cases mean the same thing to every caller: do not suppress on time of day.
    let quietHours: QuietHours?

    /// The exact payload the backend sent, retained so the cache stores bytes rather than
    /// objects and can re-parse on read. `nil` when this result *came from* the cache, so
    /// a cache hit can never be written back over itself.
    let rawPayload: Data?

    /// Written out rather than left to the memberwise init so `quietHours` can default.
    /// Most accounts never configure a window, and every call site that predates the
    /// feature means `nil` by omission.
    init(campaigns: [InAppMessageCampaign],
         cooldown: TimeInterval,
         quietHours: QuietHours? = nil,
         rawPayload: Data?) {
        self.campaigns = campaigns
        self.cooldown = cooldown
        self.quietHours = quietHours
        self.rawPayload = rawPayload
    }

    static let empty = SyncResult(campaigns: [],
                                 cooldown: defaultDisplayCooldown,
                                 rawPayload: nil)
}

/// Where campaigns come from.
///
/// A protocol so the orchestrator can be driven from a fixture in tests without a network,
/// and so a cache read and a live fetch are interchangeable at the call site.
protocol MessageSource: AnyObject {
    /// Always calls back exactly once. Never throws.
    func fetch(customerId: String, completion: @escaping (Result<SyncResult, Error>) -> Void)
}

/// Why a sync did not produce campaigns.
///
/// Both cases surface to the caller as a plain failure — the caller's response is the same,
/// fall back to cache — but the distinction is kept for diagnostics.
enum IAMSyncError: Error {
    case permanent(status: Int)
    case retryable(status: Int?)
    case unreadablePayload
}

/// Replays a fixed result and counts how many times it was asked.
final class StubMessageSource: MessageSource {
    private let result: Result<SyncResult, Error>
    private var fetches = 0

    init(result: Result<SyncResult, Error>) {
        self.result = result
    }

    var fetchCount: Int { return fetches }

    func fetch(customerId: String, completion: @escaping (Result<SyncResult, Error>) -> Void) {
        fetches += 1
        completion(result)
    }
}
