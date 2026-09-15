//
//  QuietHours.swift
//  Gameball
//

import Foundation

/// A wall-clock time of day, to the minute, with no date and no zone attached.
///
/// Minutes since midnight rather than an hour/minute pair: the window comparison is
/// ordering on a single number, and keeping two fields would push that arithmetic to
/// every call site.
struct TimeOfDay: Equatable {
    /// `0` is midnight. `1440` is midnight at the far end of the day, which the backend
    /// spells `24:00` and which is a legitimate window boundary.
    let minutesSinceMidnight: Int

    /// Parses `HH:mm` or `HH:mm:ss`. Seconds are read and discarded — the window is a
    /// suppression band hours wide, and honouring seconds would imply a precision the
    /// dashboard does not offer.
    ///
    /// Returns `nil` for anything else. That includes the shapes a well-meaning backend
    /// change might introduce (`"2200"`, an integer, an ISO timestamp): a boundary the SDK
    /// cannot read must not become a boundary the SDK guesses at.
    init?(_ raw: Any?) {
        guard let text = raw as? String else { return nil }

        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }

        // `Int(...)` on a substring rejects "+8", " 8" and "8.0" as well as letters, which
        // is why the components are not sanitised first.
        guard let hour = Int(parts[0]), let minute = Int(parts[1]),
              parts[0].count == 2, parts[1].count == 2,
              hour >= 0, minute >= 0, minute < 60 else { return nil }

        // 24:00 is the one hour past 23 that means something: the end of the day. Anything
        // above it, and any minute alongside it, is a malformed boundary.
        if hour == 24 {
            guard minute == 0, parts.count == 2 || Int(parts[2]) == 0 else { return nil }
        } else if hour > 23 {
            return nil
        }

        if parts.count == 3 {
            guard let second = Int(parts[2]), parts[2].count == 2,
                  second >= 0, second < 60 else { return nil }
        }

        self.minutesSinceMidnight = hour * 60 + minute
    }

    /// Renders back to `HH:mm`, for the diagnostic that reports the window in local terms.
    var formatted: String {
        return String(format: "%02d:%02d",
                      (minutesSinceMidnight / 60) % 24,
                      minutesSinceMidnight % 60)
    }
}

/// The account-wide window during which no in-app message displays.
///
/// **The boundaries are the device's local wall clock.** Decided with product on
/// 2026-09-05, superseding the earlier reading that they were UTC. The backend sends
/// the two `HH:mm` strings exactly as the marketer typed them (verified on alpha: a
/// window saved as 03:00–04:00 arrives as 03:00–04:00, no zone, no conversion), and the
/// dashboard promises "22:00 means 22:00 wherever the customer is". So whether now is
/// quiet is decided by reading the device's own hour and minute: a customer in Cairo and
/// one in Lisbon each get their own 22:00, two hours apart as instants.
///
struct QuietHours: Equatable {
    let enabled: Bool
    let start: TimeOfDay
    let end: TimeOfDay

    /// The calendar every comparison goes through: Gregorian, in the device's current zone.
    /// Computed rather than cached so a zone change while the app runs — travel, or a manual
    /// clock change — moves the window with it. Gregorian is fixed because a non-Gregorian
    /// calendar would carry its own idea of when a day starts.
    private static var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.autoupdatingCurrent
        return calendar
    }

    /// Returns `nil` when the payload carries no window, or one that cannot be read.
    ///
    /// Both collapse to the same outcome on purpose. A window the SDK cannot parse must
    /// leave messaging working: silence for a whole account because a boundary was
    /// mistyped in the dashboard is a worse failure than ignoring the setting and logging
    /// loudly about it.
    init?(json: Any?) {
        guard let object = json as? [String: Any] else { return nil }

        guard let start = TimeOfDay(object["start"]), let end = TimeOfDay(object["end"]) else {
            iamLog("quietHours is present but unreadable (start=\(object["start"] ?? "nil"), "
                 + "end=\(object["end"] ?? "nil")); messages will NOT be suppressed. "
                 + "Expected two 'HH:mm' strings.")
            return nil
        }

        // Absent `enabled` means the account was never opted in. Defaulting it to true
        // would turn a partial payload into an outage.
        self.enabled = (object["enabled"] as? Bool) ?? false
        self.start = start
        self.end = end
    }

    init(enabled: Bool, start: TimeOfDay, end: TimeOfDay) {
        self.enabled = enabled
        self.start = start
        self.end = end
    }

    /// Whether `date` falls inside the window.
    ///
    /// Half-open — `start` is inside, `end` is not — so a 22:00–08:00 window does not
    /// suppress the first message of the morning at exactly 08:00.
    ///
    /// Takes no time zone on purpose: the window is judged on the device's own clock, so
    /// the same instant is quiet on one device and not on another two zones away — which
    /// is what "22:00 wherever the customer is" means.
    func contains(_ date: Date) -> Bool {
        guard enabled else { return false }

        // Equal boundaries describe an empty window, not an endless one. A dashboard typo
        // should cost the setting, not the feature.
        guard start != end else { return false }

        let components = QuietHours.localCalendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return false }
        let nowMinutes = hour * 60 + minute

        if start.minutesSinceMidnight < end.minutesSinceMidnight {
            // A window inside one day: 09:00–17:00.
            return nowMinutes >= start.minutesSinceMidnight
                && nowMinutes < end.minutesSinceMidnight
        }

        // A window that wraps midnight: 22:00–08:00 is late evening *or* early morning,
        // which is a union rather than a range. Testing it as a range is the classic
        // inversion — it would suppress the entire working day instead.
        return nowMinutes >= start.minutesSinceMidnight
            || nowMinutes < end.minutesSinceMidnight
    }

    /// One line for the log. The window is already in the device's terms, so this names
    /// the zone it is being judged in rather than converting anything.
    var diagnosticDescription: String {
        return "\(start.formatted)-\(end.formatted) on the device clock "
             + "(\(TimeZone.current.identifier))"
    }
}
