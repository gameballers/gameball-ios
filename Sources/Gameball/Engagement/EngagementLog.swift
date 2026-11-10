//
//  EngagementLog.swift
//  Gameball
//

import Foundation

private let engagementLogLock = NSLock()
private var engagementLogSinkStorage: ((String) -> Void)?

/// Test-only tap on the engagement log lines.
var engagementLogSink: ((String) -> Void)? {
    get {
        engagementLogLock.lock(); defer { engagementLogLock.unlock() }
        return engagementLogSinkStorage
    }
    set {
        engagementLogLock.lock()
        engagementLogSinkStorage = newValue
        engagementLogLock.unlock()
    }
}

/// Until the backend has endpoints for app opens, influenced opens and arrivals, each is only
/// logged, as `GameballApp engagement <name> key=value key=value`.
func logEngagement(_ name: String, _ fields: [(String, Any?)]) {
    let line = engagementLine(name, fields)
    NSLog("%@", line)
    engagementLogSink?(line)
}

func engagementLine(_ name: String, _ fields: [(String, Any?)]) -> String {
    let pairs = fields.map { key, value -> String in
        guard let value = value else { return "\(key)=null" }
        return "\(key)=\(value)"
    }
    return (["GameballApp engagement \(name)"] + pairs).joined(separator: " ")
}
