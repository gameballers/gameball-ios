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
#if DEBUG
private let iamLogDefault = true
#else
private let iamLogDefault = false
#endif

private let iamLogEnabledLock = NSLock()
private var iamLogEnabledStorage = iamLogDefault

/// Whether the module writes its diagnostics to the console.
///
/// On in a `DEBUG` build, silent in a release build, where these lines reach the device
/// log of every end user and say nothing that user or the host app can act on. Set it to
/// `true` in a release build only to reproduce a reported problem.
public var GameballInAppMessagingLogging: Bool {
    get {
        iamLogEnabledLock.lock()
        defer { iamLogEnabledLock.unlock() }
        return iamLogEnabledStorage
    }
    set {
        iamLogEnabledLock.lock()
        iamLogEnabledStorage = newValue
        iamLogEnabledLock.unlock()
    }
}

func iamLog(_ message: String) {
    let line = "[GameballIAM] \(message)"
    if GameballInAppMessagingLogging {
        print(line)
    }
    // The sink stays connected regardless: tests assert on lines the console never shows.
    iamLogSink?(line)
}
