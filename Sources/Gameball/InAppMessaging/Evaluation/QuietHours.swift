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
/// **The boundaries are UTC.** The backend sends two wall-clock strings with no zone, and
/// they are always UTC — so the window describes a band of *instants*, identical for every
/// device on earth. Whether now is quiet is therefore decided by converting the current
/// instant to UTC, never by reading the device's local hour and comparing it to a UTC
/// number: at 23:00 UTC a device in Tokyo reads 08:00 locally, and comparing 08:00 against
/// a 22:00–08:00 window answers the opposite of the truth.
///
/// `localWindow(in:)` exists to make that conversion visible in the log rather than only
/// correct in the arithmetic.
struct QuietHours: Equatable {
    let enabled: Bool
    let start: TimeOfDay
    let end: TimeOfDay

    /// The calendar every comparison goes through. Fixed to UTC and to the Gregorian
    /// calendar: `Calendar.current` would carry the device's zone, which is the bug, and
    /// a non-Gregorian calendar would carry its own idea of when a day starts.
    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

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
                 + "Expected two UTC 'HH:mm' strings.")
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
    /// Takes no time zone, and that is the contract: the answer is a property of the
    /// instant, so two devices in different zones always agree.
    func contains(_ date: Date) -> Bool {
        guard enabled else { return false }

        // Equal boundaries describe an empty window, not an endless one. A dashboard typo
        // should cost the setting, not the feature.
        guard start != end else { return false }

        let components = QuietHours.utcCalendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return false }
        let nowMinutes = hour * 60 + minute

        if start.minutesSinceMidnight < end.minutesSinceMidnight {
            // A window inside one UTC day: 09:00–17:00.
            return nowMinutes >= start.minutesSinceMidnight
                && nowMinutes < end.minutesSinceMidnight
        }

        // A window that wraps midnight: 22:00–08:00 is late evening *or* early morning,
        // which is a union rather than a range. Testing it as a range is the classic
        // inversion — it would suppress the entire working day instead.
        return nowMinutes >= start.minutesSinceMidnight
            || nowMinutes < end.minutesSinceMidnight
    }

    /// The same window expressed on a given device's clock — 22:00–08:00 UTC is
    /// 01:00–11:00 in Cairo — so a log line can say when users will actually see it.
    ///
    /// Offsets are not always whole hours (Kolkata is +05:30, Kathmandu +05:45), so the
    /// shift is applied in minutes.
    func localWindow(in timeZone: TimeZone = .current) -> (start: String, end: String) {
        let shift = timeZone.secondsFromGMT() / 60
        func shifted(_ time: TimeOfDay) -> String {
            let total = ((time.minutesSinceMidnight + shift) % 1440 + 1440) % 1440
            return TimeOfDay(String(format: "%02d:%02d", total / 60, total % 60))?.formatted
                ?? time.formatted
        }
        return (shifted(start), shifted(end))
    }

    /// One line for the log, carrying both readings of the window so a support thread does
    /// not have to do the arithmetic.
    var diagnosticDescription: String {
        let local = localWindow()
        return "\(start.formatted)-\(end.formatted) UTC "
             + "(\(local.start)-\(local.end) in \(TimeZone.current.identifier))"
    }
}
