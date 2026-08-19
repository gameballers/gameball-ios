//
//  PropertyFilter.swift
//  Gameball
//

import Foundation

/// The comparison operators a campaign's metadata filter can use.
///
/// Deliberately a closed set: an operator we cannot evaluate must be recognisable as
/// unknown at parse time, so the filter is dropped rather than silently treated as true.
enum FilterOperator {
    case equals
    case notEquals
    case greaterThan
    case greaterThanOrEqual
    case lessThan
    case lessThanOrEqual
    case contains

    /// Maps a dashboard-authored operator name onto a case.
    ///
    /// Case-insensitive, and accepts both the terse dashboard spellings (`is`, `isNot`)
    /// and the verbose ones (`equals`, `notEquals`), because the backend has used both.
    /// Returns `nil` for anything unrecognised — the caller drops that filter.
    init?(wireName: String) {
        switch wireName.lowercased() {
        case "is", "equals":                  self = .equals
        case "isnot", "notequals":            self = .notEquals
        case "greaterthan":                   self = .greaterThan
        case "greaterthanorequal":            self = .greaterThanOrEqual
        case "lessthan":                      self = .lessThan
        case "lessthanorequal":               self = .lessThanOrEqual
        case "contains":                      self = .contains
        default:                              return nil
        }
    }
}

/// JSON numbers arrive as `Int`, `Double` or `NSNumber` depending on how they were
/// authored and which serialiser produced them, so comparison has to normalise first.
/// Comparing `"100"` against `"100.0"` as strings would report a mismatch for two
/// values a marketer wrote as the same number.
private func asDouble(_ value: Any) -> Double? {
    if let double = value as? Double { return double }
    if let int = value as? Int { return Double(int) }
    if let number = value as? NSNumber { return number.doubleValue }
    if let string = value as? String { return Double(string) }
    return nil
}

private func asString(_ value: Any) -> String? {
    if let string = value as? String { return string }
    if let number = value as? NSNumber { return number.stringValue }
    return nil
}

/// One metadata requirement attached to an event trigger.
struct PropertyFilter {
    let name: String
    let op: FilterOperator
    let value: Any

    /// Evaluates this filter against an occurrence's properties.
    func matches(properties: [String: Any]) -> Bool {
        // A filter is a requirement, so a missing property is failure — for every
        // operator, negative ones included. Letting `notEquals` pass on absence would
        // make filters decorative and widen the campaign to every customer.
        guard let actual = properties[name] else { return false }

        switch op {
        case .equals, .notEquals:
            let equal: Bool
            if let lhs = asDouble(actual), let rhs = asDouble(value) {
                equal = lhs == rhs
            } else {
                equal = asString(actual) == asString(value)
            }
            return op == .equals ? equal : !equal

        case .greaterThan, .greaterThanOrEqual, .lessThan, .lessThanOrEqual:
            guard let lhs = asDouble(actual), let rhs = asDouble(value) else { return false }
            switch op {
            case .greaterThan:        return lhs > rhs
            case .greaterThanOrEqual: return lhs >= rhs
            case .lessThan:           return lhs < rhs
            default:                  return lhs <= rhs
            }

        case .contains:
            guard let lhs = asString(actual), let rhs = asString(value) else { return false }
            return lhs.lowercased().contains(rhs.lowercased())
        }
    }
}
