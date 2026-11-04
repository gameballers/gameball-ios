//
//  MessageTrigger.swift
//  Gameball
//

import Foundation

/// The event name a purchase is folded into before evaluation, so a purchase campaign is
/// authored and matched exactly like any other event campaign.
let gameballPurchaseEventName = "purchase"

/// How an event trigger's metadata filters combine: `metadataLogicalOperator` on the wire.
enum FilterMatch {
    /// Every filter must match. `AND`, and what no operator at all means.
    case all
    /// At least one filter must match. `OR`, the dashboard's "Any".
    case any
}

/// The condition that makes a campaign eligible to display.
enum MessageTrigger {
    case sessionStart
    /// Matched on the event *name*. The wire also carries an `eventId`, but that is
    /// internal to the backend and cannot be resolved on a device.
    case event(name: String, filters: [PropertyFilter], match: FilterMatch = .all)
}

/// Something that just happened and may satisfy a trigger.
///
/// The mirror of `MessageTrigger`: the trigger is the standing condition, the occurrence
/// is the single moment being tested against it.
enum TriggerOccurrence {
    case sessionStart
    case event(name: String, properties: [String: Any])
}
