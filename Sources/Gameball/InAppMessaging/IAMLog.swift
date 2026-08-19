//
//  IAMLog.swift
//  Gameball
//

import Foundation

private let iamLogLock = NSLock()
private var iamLogSinkStorage: ((String) -> Void)?

/// Test-only tap on the diagnostic stream.
///
/// Several of this module's rules are only observable as a log line — a discarded analytics
/// batch, a suppressed campaign, an endpoint that is not deployed — because the module
/// never throws and never surfaces those to the host. The tap is what lets a test assert
/// "this was reported loudly" instead of trusting it was.
var iamLogSink: ((String) -> Void)? {
    get {
        iamLogLock.lock()
        defer { iamLogLock.unlock() }
        return iamLogSinkStorage
    }
    set {
        iamLogLock.lock()
        iamLogSinkStorage = newValue
        iamLogLock.unlock()
    }
}

/// Local diagnostic logging for the in-app messaging module.
///
/// Deliberately separate from `GameballLogger`, which posts telemetry to the Gameball
/// backend. Parse and evaluation diagnostics belong in the integrator's console, not in
/// a network request.
///
/// Since the module never throws, a log line is the only evidence of why something did
/// not happen — and "why didn't my campaign show" is the question integrators ask most.
func iamLog(_ message: String) {
    let line = "[GameballIAM] \(message)"
    print(line)
    iamLogSink?(line)
}
