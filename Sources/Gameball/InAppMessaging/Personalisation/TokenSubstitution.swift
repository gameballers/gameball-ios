//
//  TokenSubstitution.swift
//  Gameball
//

import Foundation

/// Replaces `{token}` placeholders in campaign copy.
///
/// Strictness matters twice over. A loose pattern would let a value map mangle ordinary copy
/// that merely contains a brace, and it is also what keeps this feature inert today: the
/// variables endpoint is not deployed, so a message with no real token must never trigger a
/// fetch or change a single character.
enum TokenSubstitution {

    /// Escaped rather than a raw string literal: this target compiles in Swift 4.2 language
    /// mode, which predates `#"..."#`.
    static let pattern = "\\{([A-Za-z_][A-Za-z0-9_]*)\\}"

    private static let regex: NSRegularExpression? = {
        do {
            return try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            iamLog("token pattern failed to compile; personalisation is disabled: "
                 + "\(error.localizedDescription)")
            return nil
        }
    }()

    /// A single character scan before the regex, so copy with no placeholder costs almost
    /// nothing and never reaches the matcher.
    static func containsToken(_ text: String?) -> Bool {
        guard let text = text, text.contains("{") else { return false }
        return !matches(in: text).isEmpty
    }

    static func tokens(in message: GameballInAppMessage) -> Set<String> {
        var found: Set<String> = []
        for text in [message.header, message.body] + message.buttons.map({ $0.text }) {
            guard let text = text, text.contains("{") else { continue }
            for match in matches(in: text) {
                if let name = name(of: match, in: text) { found.insert(name) }
            }
        }
        return found
    }

    /// Substitutes known tokens. An unknown token is left **exactly as written** — blanking it
    /// would delete copy a marketer intended, and showing the raw placeholder at least makes
    /// the misconfiguration visible.
    static func substitute(_ text: String, values: [String: String]) -> String {
        guard text.contains("{") else { return text }
        let found = matches(in: text)
        guard !found.isEmpty else { return text }

        var result = text
        // Walked in reverse so each replacement cannot invalidate the ranges still to come.
        for match in found.reversed() {
            guard let name = name(of: match, in: text),
                  let value = values[name],
                  let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: value)
        }
        return result
    }

    /// One pass only: a substituted value containing `{other}` is not expanded again, so a
    /// value cannot inject a token and no cycle is possible.
    static func apply(values: [String: String],
                      to message: GameballInAppMessage) -> GameballInAppMessage {
        guard !values.isEmpty else { return message }

        let buttons = message.buttons.map { button in
            GameballMessageButton(id: button.id,
                                  text: substitute(button.text, values: values),
                                  action: button.action,
                                  style: button.style)
        }

        return GameballInAppMessage(id: message.id,
                                    type: message.type,
                                    header: message.header.map { substitute($0, values: values) },
                                    body: message.body.map { substitute($0, values: values) },
                                    imageURL: message.imageURL,
                                    iconURL: message.iconURL,
                                    clickAction: message.clickAction,
                                    buttons: buttons,
                                    showCloseButton: message.showCloseButton,
                                    dismissOnScrimTap: message.dismissOnScrimTap,
                                    autoDismissAfter: message.autoDismissAfter,
                                    layout: message.layout,
                                    orientation: message.orientation,
                                    slidePosition: message.slidePosition,
                                    extras: message.extras,
                                    style: message.style)
    }

    // MARK: - Internals

    private static func matches(in text: String) -> [NSTextCheckingResult] {
        guard let regex = regex else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range)
    }

    private static func name(of match: NSTextCheckingResult, in text: String) -> String? {
        guard match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
