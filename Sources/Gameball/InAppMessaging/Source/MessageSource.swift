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

/// The outcome of one sync: the campaigns to hold for this session, the display floor
/// they are subject to, and the bytes that produced them.
struct SyncResult {
    let campaigns: [InAppMessageCampaign]
    let cooldown: TimeInterval

    /// The exact payload the backend sent, retained so the cache stores bytes rather than
    /// objects and can re-parse on read. `nil` when this result *came from* the cache, so
    /// a cache hit can never be written back over itself.
    let rawPayload: Data?

    static let empty = SyncResult(campaigns: [],
                                 cooldown: defaultDisplayCooldown,
                                 rawPayload: nil)
}
