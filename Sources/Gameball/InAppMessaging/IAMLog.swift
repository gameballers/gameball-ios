//
//  IAMLog.swift
//  Gameball
//

import Foundation

/// Local diagnostic logging for the in-app messaging module.
///
/// Deliberately separate from `GameballLogger`, which posts telemetry to the Gameball
/// backend. Parse and evaluation diagnostics belong in the integrator's console, not in
/// a network request.
///
/// Since the module never throws, a log line is the only evidence of why something did
/// not happen — and "why didn't my campaign show" is the question integrators ask most.
func iamLog(_ message: String) {
    print("[GameballIAM] \(message)")
}
