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

    /// Substitutes known tokens. An unknown token is left **exactly as written**, so a caller can
    /// still tell resolved from unresolved. Nothing reaches the screen in that state:
    /// `clearUnresolved(in:)` is the last step before display and blanks whatever is left.
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
        return rewritingText(of: message) { substitute($0, values: values) }
    }

    /// `message` with every remaining `{token}` replaced by nothing.
    ///
    /// The last step before a message is drawn, on every path — including the ones where
    /// `apply` had nothing to work with, such as a values call that failed or timed out with
    /// nothing held. Sync sends the copy as a template, so whatever is still unresolved here is
    /// a raw placeholder, not a missed enhancement.
    ///
    /// Blanking rather than withholding the message is deliberate.
    /// An unresolved token means the values call did not answer or did not know the name, which
    /// is a backend problem to fix there. Withholding the campaign would hide the symptom and cost
    /// the customer the message; rendering the braces would show them the SDK's internals.
    static func clearUnresolved(in message: GameballInAppMessage) -> GameballInAppMessage {
        guard !tokens(in: message).isEmpty else { return message }
        return rewritingText(of: message) { blankTokens(in: $0) }
    }

    // MARK: - Internals

    /// `message` with `transform` applied to its header, body and every button label, and
    /// everything else carried through unchanged.
    private static func rewritingText(of message: GameballInAppMessage,
                                      with transform: (String) -> String) -> GameballInAppMessage {
        let buttons = message.buttons.map { button in
            GameballMessageButton(id: button.id,
                                  text: transform(button.text),
                                  action: button.action,
                                  style: button.style)
        }

        return GameballInAppMessage(id: message.id,
                                    type: message.type,
                                    header: message.header.map(transform),
                                    body: message.body.map(transform),
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

    private static func blankTokens(in text: String) -> String {
        guard text.contains("{"), let regex = regex else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

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
