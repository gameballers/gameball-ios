//
//  MessageParser.swift
//  Gameball
//

import UIKit

/// Turns a sync payload into campaigns.
///
/// Never throws. The leniency rules are asymmetric on purpose, and the asymmetry is the
/// whole design: a malformed *field* costs the field, a malformed *contract* costs the
/// campaign. Widening is always the more expensive mistake — a filter evaluated as
/// "always true" shows a "spent over $100" message to everyone — so anything that would
/// widen a campaign drops it instead.
enum MessageParser {

    // MARK: - Entry points

    /// Parses a whole sync response. A malformed payload yields an empty result.
    static func parseSyncResponse(_ data: Data) -> SyncResult {
        guard !data.isEmpty else { return .empty }

        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            iamLog("sync payload is not valid JSON: \(error.localizedDescription)")
            return .empty
        }

        guard let json = root as? [String: Any] else {
            iamLog("sync payload root is not an object; ignoring it")
            return .empty
        }

        let cooldown = doubleValue(json["cooldownSeconds"]) ?? defaultDisplayCooldown

        // Absent for most accounts. `QuietHours` logs its own reason when a window is
        // present but unreadable, so there is nothing to report here.
        let quietHours = QuietHours(json: json["quietHours"])
        if let quietHours = quietHours, quietHours.enabled {
            iamLog("quiet hours are active for this account: \(quietHours.diagnosticDescription)")
        }

        guard let messages = json["messages"] as? [[String: Any]] else {
            // Not an error: a customer with no live campaigns gets no `messages` key.
            return SyncResult(campaigns: [], cooldown: cooldown,
                              quietHours: quietHours, rawPayload: data)
        }

        // `responseIndex` is the payload position, assigned before any campaign is
        // dropped, so removing one cannot shift the tie-break of the ones behind it.
        var campaigns: [InAppMessageCampaign] = []
        for (index, message) in messages.enumerated() {
            if let campaign = parseCampaign(message, responseIndex: index) {
                campaigns.append(campaign)
            }
        }

        return SyncResult(campaigns: campaigns, cooldown: cooldown,
                          quietHours: quietHours, rawPayload: data)
    }

    /// The kinds of entry the sync response carries.
    ///
    /// An unrecognised kind is skipped, never coerced. More are expected, and an older client
    /// must degrade to silence rather than to a wrong display.
    private static let outboundCampaignType = 1
    private static let gameCampaignType = 2

    /// Games this SDK can open, as the open-details text the widget expects.
    ///
    /// A value absent from this set is skipped: composing `details_<unknown>_<id>` would ask the
    /// widget to open something it has no renderer for.
    private static let knownGameTypes: Set<String> = [
        "wheel", "slot", "quiz", "scratch", "match", "catcher",
        "tictactoe", "shooter", "puzzle", "tap_target", "highway_drive"
    ]

    /// Parses one campaign. Returns `nil` when it cannot be evaluated or rendered, always
    /// logging which field caused it.
    static func parseCampaign(_ json: [String: Any], responseIndex: Int) -> InAppMessageCampaign? {
        guard let campaignId = intValue(json["campaignId"]) else {
            iamLog("campaign has no campaignId; dropping")
            return nil
        }

        // Anything other than prerendered is a content contract this SDK cannot honour.
        if let mode = stringValue(json["contentMode"]), mode.lowercased() != "prerendered" {
            iamLog("campaign \(campaignId) uses contentMode '\(mode)'; dropping")
            return nil
        }

        guard let rawType = intValue(json["messageType"]) else {
            iamLog("campaign \(campaignId) has no messageType; dropping")
            return nil
        }
        let type = GameballMessageType(rawValue: rawType)
        if type == .unsupported {
            iamLog("campaign \(campaignId) has messageType \(rawType), which this SDK "
                 + "cannot render; keeping it so it is skipped rather than fatal")
        }

        guard let triggerJSON = json["trigger"] as? [String: Any],
              let trigger = parseTrigger(triggerJSON, campaignId: campaignId) else {
            iamLog("campaign \(campaignId) has no usable trigger; dropping")
            return nil
        }

        // Which kind of entry this is. Read before anything about the content, because a game's
        // content arrives at display time and the checks below would otherwise drop it for having
        // no header, body or image.
        let campaignType = intValue(json["campaignType"]) ?? outboundCampaignType
        if campaignType != outboundCampaignType && campaignType != gameCampaignType {
            iamLog("campaign \(campaignId) has unrecognised campaignType \(campaignType); "
                 + "this SDK renders outbound messages and opens game campaigns, so dropping")
            return nil
        }

        var widget: GameballWidgetContent?
        if campaignType == gameCampaignType {
            guard let parsed = parseGameContent(json, campaignId: campaignId) else {
                return nil // already logged
            }
            widget = parsed
        }

        let content = json["content"] as? [String: Any] ?? [:]
        let locale = json["locale"] as? [String: Any] ?? [:]

        let header = stringValue(locale["header"])
        // `message` is the current field; `body` is accepted because older payloads used it.
        let body = stringValue(locale["message"]) ?? stringValue(locale["body"])
        let imageURL = resolveImageURL(content: content, type: type)
        let iconURL = normalisedURL(content["iconUrl"])

        // Drawing an empty box is worse than showing nothing. Exempt by kind, not by which
        // fields happen to be absent: a game renders itself, while a *message* missing all three
        // is still a campaign with nothing to show and must keep failing for that reason.
        let hasText = header != nil || body != nil
        guard widget != nil || hasText || imageURL != nil else {
            iamLog("campaign \(campaignId) has nothing to render; dropping")
            return nil
        }
        if widget == nil && type == .slideup && !hasText {
            iamLog("slideup campaign \(campaignId) has no text; an icon alone is not a "
                 + "message, so dropping")
            return nil
        }

        let variationId = intValue(json["variationId"])
        let closeBehaviour = (stringValue(content["closeBehaviour"]) ?? "both").lowercased()
        let alignments = parseAlignments(content["textAlignment"])

        let message = GameballInAppMessage(
            id: variationId.map { "\(campaignId)/\($0)" } ?? "\(campaignId)",
            type: type,
            header: header,
            body: body,
            imageURL: imageURL,
            iconURL: iconURL,
            // Deliberately not defaulted to `.dismiss`: a surface with no action is inert,
            // and making the whole surface dismiss steals taps the campaign never claimed.
            clickAction: parseAction(content["action"], owner: campaignId),
            buttons: parseButtons(content: content, locale: locale,
                                  type: type, campaignId: campaignId),
            // Reported as `false` for a slideup whatever the campaign asks for. A slideup has
            // never rendered a close button — its dismissal is the swipe and the timer, and the
            // whole surface is the affordance — so claiming one described something that does not
            // happen. Missing `closeBehaviour` defaults to "both", which meant every slideup on
            // the account claimed a button it would never show.
            showCloseButton: type != .slideup
                && (closeBehaviour.contains("button") || closeBehaviour.contains("both")),
            dismissOnScrimTap: closeBehaviour.contains("swipe") || closeBehaviour.contains("both"),
            autoDismissAfter: parseAutoDismiss(content["autoDismissSeconds"],
                                               type: type, campaignId: campaignId),
            layout: parseLayout(content["layout"], type: type, campaignId: campaignId),
            orientation: parseOrientation(content["orientation"]),
            slidePosition: parseSlidePosition(content["slideFrom"]),
            extras: content["extras"] as? [String: Any] ?? [:],
            style: parseStyle(content["colors"], alignments: alignments),
            widget: widget
        )

        let repeatable = boolValue(triggerJSON["repeatable"]) ?? false

        return InAppMessageCampaign(
            campaignId: campaignId,
            variationId: variationId,
            dispatchId: stringValue(json["dispatchId"]),
            name: stringValue(json["name"]),
            priority: intValue(json["priority"]) ?? 0,
            expiresAt: parseDate(json["expiresAt"], campaignId: campaignId),
            isTest: boolValue(json["isTest"]) ?? false,
            repeatable: repeatable,
            // 0 and null both mean "every occurrence"; only a positive gap is a rule.
            minInterval: positiveInterval(triggerJSON["minIntervalSeconds"]),
            trigger: trigger,
            message: message,
            responseIndex: responseIndex
        )
    }

    // MARK: - Trigger

    /// Reads the game fields from a `campaignType: 2` entry.
    ///
    /// `nil` when the entry cannot be opened, which drops it. Both fields are required: without
    /// the id there is nothing to open, and without a recognised type there is no renderer to ask
    /// for.
    private static func parseGameContent(_ json: [String: Any],
                                         campaignId: Int) -> GameballWidgetContent? {
        guard let gameCampaignId = intValue(json["gameCampaignId"]), gameCampaignId != 0 else {
            iamLog("campaign \(campaignId) is a game entry with no gameCampaignId; its "
                 + "campaignId is always 0 and identifies nothing, so dropping")
            return nil
        }

        guard let gameType = stringValue(json["gameCampaignType"]),
              knownGameTypes.contains(gameType) else {
            iamLog("campaign \(campaignId) has unrecognised gameCampaignType "
                 + "'\(stringValue(json["gameCampaignType"]) ?? "")'; this SDK version has no "
                 + "renderer for it, so dropping")
            return nil
        }

        // Nothing else is read for a game: its frequency comes from the trigger, exactly as a
        // message's does. The challenge's own delay and dismissal limit are deliberately not used.
        return GameballWidgetContent(gameCampaignId: gameCampaignId, gameCampaignType: gameType)
    }

    private static func parseTrigger(_ json: [String: Any],
                                     campaignId: Int) -> MessageTrigger? {
        let type = (stringValue(json["type"]) ?? "").lowercased()
        if type == "session_start" { return .sessionStart }

        // Deliberate, not unimplemented. On the web a URL is ambient and free; on mobile nothing
        // is, so a screen trigger needs the host to instrument it — at which point it costs the
        // same as a custom event. Named here so a marketer who targets a screen gets a
        // diagnosable silence rather than an inexplicable one.
        if type == "screen" {
            iamLog("campaign \(campaignId) uses a screen trigger (screen "
                 + "'\(stringValue(json["name"]) ?? "")'), which this SDK version does not "
                 + "support; dropping")
            return nil
        }

        guard type == "event" else {
            iamLog("campaign \(campaignId) has unknown trigger type '\(type)'; dropping")
            return nil
        }

        // Match on the event NAME. `eventId` is internal to the backend and cannot be
        // resolved on a device, so a null name makes the campaign unevaluable.
        guard let name = stringValue(json["name"]) else {
            iamLog("campaign \(campaignId) has an event trigger with no name; dropping")
            return nil
        }

        // `OR` shows the campaign when any one filter matches; `AND`, or no operator at all, only
        // when every one does. Anything else is dropped: read as `AND` it would narrow the
        // campaign, read as `OR` it would widen it, and neither is acceptable.
        let logical = stringValue(json["metadataLogicalOperator"])
        let match: FilterMatch
        switch logical?.lowercased() {
        case nil, "and"?:
            match = .all
        case "or"?:
            match = .any
        default:
            iamLog("campaign \(campaignId) uses metadataLogicalOperator '\(logical ?? "")', "
                 + "which is not supported; dropping")
            return nil
        }

        let declared = json["metadataFilters"] as? [[String: Any]] ?? []
        var filters: [PropertyFilter] = []
        for raw in declared {
            guard let filterName = stringValue(raw["name"]) else {
                // Dropping the filter would WIDEN the campaign. Dropping the campaign is
                // the safe direction.
                iamLog("campaign \(campaignId) has a metadata filter with no name; dropping "
                     + "the campaign rather than widening it")
                return nil
            }
            guard let opName = stringValue(raw["operator"]),
                  let op = FilterOperator(wireName: opName) else {
                iamLog("campaign \(campaignId) filter '\(filterName)' has an unusable "
                     + "operator; dropping the filter")
                continue
            }
            guard let value = raw["value"], !(value is NSNull) else {
                iamLog("campaign \(campaignId) filter '\(filterName)' has a null value; "
                     + "dropping the filter")
                continue
            }
            filters.append(PropertyFilter(name: filterName, op: op, value: value))
        }

        // Under `OR` a dropped filter only narrows the campaign — unless every filter was
        // dropped, when "any of none" would read as no condition at all and show the campaign on
        // every occurrence of its event.
        if match == .any && filters.isEmpty && !declared.isEmpty {
            iamLog("campaign \(campaignId) shows when any of its conditions match, and none of "
                 + "them can be evaluated; dropping the campaign rather than showing it on every "
                 + "'\(name)'")
            return nil
        }

        return .event(name: name, filters: filters, match: match)
    }

    // MARK: - Artwork

    /// Two fields can carry the image and precedence depends on the type: fullscreen
    /// posters are authored as `media`, everything else as `imageUrl`.
    private static func resolveImageURL(content: [String: Any],
                                        type: GameballMessageType) -> URL? {
        let mediaURL = mediaImageURL(content["media"])
        let imageURL = normalisedURL(content["imageUrl"])
        let ordered = (type == .fullscreen) ? [mediaURL, imageURL] : [imageURL, mediaURL]
        return ordered.compactMap { $0 }.first
    }

    private static func mediaImageURL(_ media: Any?) -> URL? {
        guard let media = media as? [String: Any] else { return nil }
        // Use `url` only when the type is image or absent. Handing a video URL to an
        // image view draws a broken frame.
        if let kind = stringValue(media["type"]), kind.lowercased() != "image" {
            iamLog("ignoring media of type '\(kind)'; only images are supported")
            return nil
        }
        return normalisedURL(media["url"])
    }

    /// Blank strings normalise to nil. An empty URL otherwise reaches the artwork loader,
    /// fails, and silently takes the whole campaign with it.
    private static func normalisedURL(_ value: Any?) -> URL? {
        guard let string = stringValue(value), let url = URL(string: string) else { return nil }
        if url.scheme?.lowercased() == "http" {
            iamLog("artwork served over http:// will be refused (in-app artwork must be https): "
                 + "\(url)")
        }
        return url
    }

    // MARK: - Buttons

    private static func parseButtons(content: [String: Any],
                                     locale: [String: Any],
                                     type: GameballMessageType,
                                     campaignId: Int) -> [GameballMessageButton] {
        let contentButtons = content["buttons"] as? [[String: Any]] ?? []
        guard !contentButtons.isEmpty else { return [] }

        // Text lives in the locale half, behaviour in the content half; a button is only
        // renderable when both halves name the same id.
        var texts: [String: String] = [:]
        for raw in (locale["buttons"] as? [[String: Any]] ?? []) {
            if let id = stringValue(raw["id"]), let text = stringValue(raw["text"]) {
                texts[id] = text
            }
        }

        var buttons: [GameballMessageButton] = []
        for raw in contentButtons {
            guard let id = stringValue(raw["id"]) else {
                iamLog("campaign \(campaignId) has a button with no id; dropping it")
                continue
            }
            guard let text = texts[id] else {
                iamLog("campaign \(campaignId) button '\(id)' has no text in the locale "
                     + "half; dropping it")
                continue
            }
            buttons.append(GameballMessageButton(
                id: id,
                text: text,
                // A button that does nothing is a dead end, so an unusable action becomes
                // dismiss. This is the opposite of the surface rule on purpose.
                action: parseAction(raw["action"], owner: campaignId) ?? .dismiss,
                style: parseButtonStyle(raw["colors"])
            ))
        }

        if type == .modal && buttons.count > 2 {
            iamLog("campaign \(campaignId) declares \(buttons.count) buttons; a modal "
                 + "renders at most 2")
            buttons = Array(buttons.prefix(2))
        }
        return buttons
    }

    // MARK: - Actions

    /// Returns `nil` when there is no usable action. The caller decides what that means:
    /// a button falls back to dismiss, a surface stays inert.
    private static func parseAction(_ raw: Any?, owner campaignId: Int) -> GameballClickAction? {
        guard let json = raw as? [String: Any] else { return nil }
        guard let rawType = stringValue(json["type"]) else { return nil }

        switch rawType.lowercased() {
        case "dismiss":
            return .dismiss

        case "open_url":
            guard let url = normalisedURL(json["url"]) else {
                iamLog("campaign \(campaignId) has an open_url action with no usable url")
                return nil
            }
            return .openURL(url: url, external: boolValue(json["external"]) ?? false)

        case "navigate":
            guard var route = stringValue(json["route"]) else {
                iamLog("campaign \(campaignId) has a navigate action with no route")
                return nil
            }
            // The contract is a bare name; a leading slash would break a host router that
            // concatenates rather than resolves.
            while route.hasPrefix("/") { route = String(route.dropFirst()) }
            guard !route.isEmpty else { return nil }
            return .navigate(route: route, arguments: json["arguments"] as? [String: Any])

        case "request_push_permission":
            return .requestPushPermission

        default:
            // Recognised by the backend, not implemented here. Reported so a diagnostic can
            // name what was asked for.
            iamLog("campaign \(campaignId) requests unsupported action '\(rawType)'")
            return .unsupported(type: rawType)
        }
    }

    // MARK: - Layout and geometry

    /// A value a future dashboard invents must not drop the campaign — layout is a
    /// rendering hint, not a contract. And layout is never inferred from which fields are
    /// populated: personalised copy resolving to empty is indistinguishable from a
    /// deliberately image-only campaign.
    /// Resolves `autoDismissSeconds`, which carries **three** distinct states rather than two.
    ///
    /// * **Absent** — the campaign expressed no opinion. A slideup takes the constant default; a
    ///   modal or fullscreen stays until dismissed, because timing out a surface the customer is
    ///   reading would pull it away mid-sentence.
    /// * **Explicit zero** — the author switched the timer off. Honoured on every type. Reading
    ///   this as "unset" and substituting the default overrides a deliberate choice, which is
    ///   what an earlier version of this did.
    /// * **Malformed** — negative, or not a number. Treated as absent and logged, because it is a
    ///   mistake rather than an instruction.
    private static func parseAutoDismiss(_ raw: Any?,
                                         type: GameballMessageType,
                                         campaignId: Int) -> TimeInterval? {
        let fallback: TimeInterval? = type == .slideup ? defaultSlideupAutoDismiss : nil

        guard raw != nil, !(raw is NSNull) else { return fallback }
        guard let seconds = doubleValue(raw) else {
            iamLog("campaign \(campaignId) sent an unreadable autoDismissSeconds "
                 + "(\(raw ?? "nil")); using the default for a \(type)")
            return fallback
        }
        if seconds == 0 { return nil }
        guard seconds > 0 else {
            iamLog("campaign \(campaignId) sent a negative autoDismissSeconds (\(seconds)); "
                 + "using the default for a \(type)")
            return fallback
        }
        return seconds
    }

    private static func parseLayout(_ raw: Any?,
                                    type: GameballMessageType,
                                    campaignId: Int) -> GameballMessageLayout {
        guard let value = stringValue(raw)?.lowercased() else { return .textWithImage }
        switch value {
        case "image_only":
            return .imageOnly
        case "text_with_image", "image_and_text":
            // The two types spell the same arrangement differently.
            return .textWithImage
        default:
            iamLog("campaign \(campaignId) has unrecognised layout '\(value)'; falling back "
                 + "to the default for \(type)")
            return .textWithImage
        }
    }

    private static func parseOrientation(_ raw: Any?) -> GameballMessageOrientation {
        switch (stringValue(raw) ?? "").lowercased() {
        case "portrait":  return .portrait
        case "landscape": return .landscape
        default:          return .any
        }
    }

    private static func parseSlidePosition(_ raw: Any?) -> GameballSlidePosition {
        return (stringValue(raw) ?? "").lowercased() == "top" ? .top : .bottom
    }

    // MARK: - Style

    private static func parseStyle(
        _ raw: Any?,
        alignments: (header: GameballTextAlignment, body: GameballTextAlignment)
    ) -> GameballMessageStyle {
        let colors = raw as? [String: Any] ?? [:]
        return GameballMessageStyle(
            backgroundColor: parseColor(colors["background"]),
            textColor: parseColor(colors["text"]),
            headerColor: parseColor(colors["header"]),
            closeButtonColor: parseColor(colors["closeButton"]),
            borderColor: parseColor(colors["border"]),
            frameColor: parseColor(colors["frame"]),
            headerAlignment: alignments.header,
            bodyAlignment: alignments.body
        )
    }

    private static func parseButtonStyle(_ raw: Any?) -> GameballButtonStyle {
        let colors = raw as? [String: Any] ?? [:]
        return GameballButtonStyle(
            backgroundColor: parseColor(colors["background"]),
            textColor: parseColor(colors["text"]),
            borderColor: parseColor(colors["border"])
        )
    }

    /// Deliberately failable, and deliberately *not* the repo's `UIColor(hexString:)`,
    /// which falls back to a hardcoded light grey. An unstyled campaign must inherit the
    /// host's theme; painting it grey is how a message ends up unreadable in dark mode.
    private static func parseColor(_ raw: Any?) -> UIColor? {
        guard let value = stringValue(raw) else { return nil }
        var hex = value
        if hex.hasPrefix("#") { hex = String(hex.dropFirst()) }

        guard hex.count == 6 || hex.count == 8, let bits = UInt64(hex, radix: 16) else {
            iamLog("could not parse colour '\(value)'; falling back to the host theme")
            return nil
        }

        let divisor: CGFloat = 255
        if hex.count == 6 {
            return UIColor(red: CGFloat((bits & 0xFF0000) >> 16) / divisor,
                           green: CGFloat((bits & 0x00FF00) >> 8) / divisor,
                           blue: CGFloat(bits & 0x0000FF) / divisor,
                           alpha: 1)
        }
        return UIColor(red: CGFloat((bits & 0xFF000000) >> 24) / divisor,
                       green: CGFloat((bits & 0x00FF0000) >> 16) / divisor,
                       blue: CGFloat((bits & 0x0000FF00) >> 8) / divisor,
                       alpha: CGFloat(bits & 0x000000FF) / divisor)
    }

    /// Accepts either a single value for both slots or an object naming each, since the
    /// field is optional on the wire and has appeared in both shapes.
    private static func parseAlignments(
        _ raw: Any?
    ) -> (header: GameballTextAlignment, body: GameballTextAlignment) {
        if let single = stringValue(raw) {
            let alignment = parseAlignment(single)
            return (alignment, alignment)
        }
        guard let json = raw as? [String: Any] else { return (.leading, .leading) }
        return (parseAlignment(stringValue(json["header"])),
                parseAlignment(stringValue(json["body"]) ?? stringValue(json["message"])))
    }

    /// Leading rather than left, so a right-to-left locale mirrors without the parser
    /// needing to know the layout direction.
    private static func parseAlignment(_ raw: String?) -> GameballTextAlignment {
        switch (raw ?? "").lowercased() {
        case "center", "centre", "middle": return .center
        case "right", "end", "trailing":   return .trailing
        default:                           return .leading
        }
    }

    // MARK: - Dates

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// An unparseable stamp means "no expiry", never "expired" — the alternative silently
    /// suppresses a live campaign because of a formatting change.
    private static func parseDate(_ raw: Any?, campaignId: Int) -> Date? {
        guard let value = stringValue(raw) else { return nil }
        if let date = iso8601.date(from: value) ?? iso8601Fractional.date(from: value) {
            return date
        }
        iamLog("campaign \(campaignId) has an unparseable expiresAt '\(value)'; treating it "
             + "as no expiry")
        return nil
    }

    // MARK: - Scalar coercion

    /// JSON numbers arrive as `NSNumber` through `JSONSerialization`, so every scalar read
    /// goes through these rather than a direct cast.
    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let int = value as? Int { return int }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let double = value as? Double { return double }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
    }

    /// Trimmed, and blank normalises to nil so `""` never reaches a label or a URL loader.
    private static func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Only a positive duration is a rule; 0 and negatives mean "no rule", not "immediately".
    private static func positiveInterval(_ value: Any?) -> TimeInterval? {
        guard let seconds = doubleValue(value), seconds > 0 else { return nil }
        return seconds
    }
}
