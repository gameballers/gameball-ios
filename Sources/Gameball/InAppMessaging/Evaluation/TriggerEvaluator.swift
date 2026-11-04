//
//  TriggerEvaluator.swift
//  Gameball
//

import Foundation

/// Picks the one campaign an occurrence should display, or none.
///
/// Free functions taking every input explicitly — the clock, the cap state, artwork
/// readiness — so selection is pure and fully testable without a service, a store or a
/// network. `isArtworkReady` is injected rather than reached for, which is what keeps the
/// prefetcher out of this file.
func selectCampaign(occurrence: TriggerOccurrence,
                    campaigns: [InAppMessageCampaign],
                    capState: CapState,
                    now: Date,
                    cooldown: TimeInterval = defaultDisplayCooldown,
                    quietHours: QuietHours? = nil,
                    isArtworkReady: (InAppMessageCampaign) -> Bool) -> InAppMessageCampaign? {
    var eligible: [InAppMessageCampaign] = []
    for candidate in campaigns {
        if !triggerMatches(candidate.trigger, occurrence) { continue }

        // Checked here and not only at fetch: campaigns are held for the session, so one
        // fetched at 23:58 would otherwise fire all night, and keep firing after the
        // campaign was paused.
        if candidate.hasExpired(at: now) {
            iamLog("\(candidate.key) skipped: expired")
            continue
        }
        if !isRepeatEligible(campaign: candidate, capState: capState, now: now) { continue }

        // Filtered here rather than refused at display, so a usable lower-priority campaign
        // can still win instead of the occurrence being wasted.
        if candidate.message.type == .unsupported {
            iamLog("\(candidate.key) skipped: unsupported message type")
            continue
        }
        if !isArtworkReady(candidate) {
            iamLog("\(candidate.key) skipped: artwork not ready")
            continue
        }
        eligible.append(candidate)
    }

    if eligible.isEmpty { return nil }

    // After eligibility, before sorting. Inside the floor nothing displays at all; it is
    // not a per-campaign rule, and checking it earlier would let an ineligible campaign
    // consume the decision.
    if isWithinFloor(capState: capState, now: now, cooldown: cooldown) {
        iamLog("suppressed: inside the \(Int(cooldown))s display floor")
        return nil
    }

    // Account-wide, like the floor, and checked in the same place for the same reason: a
    // campaign that was never eligible must not be the one reported as suppressed.
    //
    // Deliberately *not* also checked at fetch time. Campaigns are held for the session,
    // so a session that starts at 21:59 crosses into the window while running — the gate
    // has to sit on the display decision, which is the only thing that happens repeatedly.
    if let quietHours = quietHours, quietHours.contains(now) {
        iamLog("suppressed: inside quiet hours \(quietHours.diagnosticDescription)")
        return nil
    }

    // Swift's sort is not guaranteed stable, so ordering by priority alone would make
    // equal-priority ties rotate arbitrarily between runs. `responseIndex` is the
    // documented tie-break and is carried on the campaign for exactly this reason.
    return eligible.sorted {
        $0.priority != $1.priority ? $0.priority > $1.priority
                                   : $0.responseIndex < $1.responseIndex
    }.first
}

func triggerMatches(_ trigger: MessageTrigger, _ occurrence: TriggerOccurrence) -> Bool {
    switch (trigger, occurrence) {
    case (.sessionStart, .sessionStart):
        return true

    case (.event(let triggerName, let filters, let match), .event(let eventName, let properties)):
        guard triggerName.lowercased() == eventName.lowercased() else { return false }
        // No filter is no condition, however the filters would have combined.
        guard !filters.isEmpty else { return true }
        switch match {
        case .all:
            // A filter is a requirement, so one failure disqualifies.
            return filters.allSatisfy { $0.matches(properties: properties) }
        case .any:
            return filters.contains { $0.matches(properties: properties) }
        }

    default:
        return false
    }
}

func isRepeatEligible(campaign: InAppMessageCampaign,
                      capState: CapState,
                      now: Date) -> Bool {
    guard let last = capState.lastDisplayByCampaign[campaign.key] else {
        return true
    }
    guard campaign.repeatable else {
        iamLog("\(campaign.key) skipped: not repeatable and already shown")
        return false
    }
    guard let interval = campaign.minInterval else { return true }
    if now.timeIntervalSince(last) >= interval { return true }
    iamLog("\(campaign.key) skipped: inside its \(Int(interval))s interval")
    return false
}

func isWithinFloor(capState: CapState, now: Date, cooldown: TimeInterval) -> Bool {
    guard let last = capState.lastDisplayAt else { return false }
    return now.timeIntervalSince(last) < cooldown
}
