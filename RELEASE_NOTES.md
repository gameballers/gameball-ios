# Release Notes - Gameball iOS SDK

This file contains detailed release notes for the latest version. For complete version history, see [CHANGELOG.md](CHANGELOG.md).

---

## Latest Release: v3.2.0

**Release Date**: 2026-06-17
**Version**: 3.2.0
**Type**: Minor Release

---

## 🎉 What's New

v3.2.0 introduces a **widget event channel** so your app can react to what customers do inside the widget, **dismissal controls** for both the widget and the host app, **external-link handling**, optional **channel-merging parameters**, and internal **diagnostic logging**. All v3.1.x code continues to work without modification — every addition is backward compatible.

### Widget Event Channel

The widget can now post events (e.g. game completion, reward redemption) back to your app. Register `widgetEventCallback` and each event arrives as a `[String: Any]` dictionary with a top-level `type` and a nested `metadata`:

```swift
let request = ShowProfileRequest(
    customerId: "customer_123",
    widgetEventCallback: { event in
        guard let event = event else { return }                 // nil = malformed payload
        let type = event["type"] as? String                              // e.g. "gameCompleted"
        let metadata = event["metadata"] as? [String: Any] ?? [:]

        switch type {
        case "gameCompleted":
            let hasWon = metadata["hasWon"] as? Bool ?? false
            let rewardType = metadata["rewardType"] as? String       // "Default", "Bonus", "NoReward"…
            let discountType = metadata["discountType"] as? String   // "FreeShipping", "Percentage"… (nil if not a coupon win)
            let rewardName = metadata["rewardName"] as? String       // localized display name
            let campaignId = metadata["campaignId"] as? String              // "90340"
            let campaignType = metadata["campaignType"] as? String   // "spinTheWheel", "scratchCard"…
            if hasWon { refreshBalance() }
        default:
            break
        }
    }
)
GameballApp.getInstance().showProfile(request)
```

The `gameCompleted` event's `metadata` carries:

| Field | Type | Description |
|---|---|---|
| `hasWon` | `Bool` | Whether the player won a reward this round |
| `rewardType` | `String?` | Reward category — `Default`, `Friend`, `Bonus`, `CustomText`, `Streak`, `NoReward` |
| `discountType` | `String?` | Coupon kind when the win is a coupon — e.g. `Fixed`, `Percentage`, `FreeShipping`, `FreeProduct`, `Custom`, `RechargeFixed`, `RechargePercentage`, `ExternalReward`; `nil` for non-coupon wins |
| `rewardName` | `String?` | Localized, human-readable reward name |
| `campaignId` | `String` | Challenge / campaign identifier |
| `campaignType` | `String?` | Game type — `spinTheWheel`, `slotMachine`, `quiz`, `scratchCard`, `matchCards`, `catcher`, `ticTacToe`, `shooter`, `puzzle`, `tapTarget`, `highwayDrive` |

### Web-Initiated Close

The widget can dismiss its own webview by calling `window.GameballWidget.closeWidget()` — no host code required.

### Host-Initiated Dismiss

Dismiss the widget programmatically from your app (e.g. on logout or a deep link):

```swift
GameballApp.getInstance().hideProfile()   // no-op when nothing is shown
```

### External-Link Handling

Links the widget flags with `gbExternalBrowser=true` open in the system browser. Optionally intercept them with `externalLinkCallback`:

```swift
let request = ShowProfileRequest(
    customerId: "customer_123",
    externalLinkCallback: { url in
        // open `url` your own way — in-app browser, router, etc.
    }
)
```

### Channel-Merging Parameters

`showProfile` now accepts optional `mobile` and `email`, so the widget can merge a guest/known profile with a customer's contact channels:

```swift
let request = ShowProfileRequest(
    customerId: "customer_123",
    mobile: "+201234567890",
    email: "customer@example.com"
)
GameballApp.getInstance().showProfile(request)
```

### Diagnostic Logging

The SDK now records internal diagnostic logs to aid troubleshooting. This is automatic and requires no integration changes.

---

## 🔄 Changes

- Added `ShowProfileRequest.widgetEventCallback: (([String: Any]?) -> Void)?`
- Added `ShowProfileRequest.externalLinkCallback: ((String) -> Void)?`
- Added optional `ShowProfileRequest.mobile` and `ShowProfileRequest.email` (channel merging)
- Added `GameballApp.hideProfile()`
- Exposed `window.GameballWidget.closeWidget()` to the widget webview
- Added internal SDK diagnostic logging
- Unified the `x-gb-agent` header format to `GB/<sdkType>/<version>`

---

## Usage Examples

**React to a reward and refresh the wallet:**
```swift
let request = ShowProfileRequest(
    customerId: "customer_123",
    widgetEventCallback: { event in
        guard let metadata = event?["metadata"] as? [String: Any] else { return }
        if metadata["hasWon"] as? Bool == true {
            let reward = metadata["rewardName"] as? String ?? ""
            showWinAnimation(reward)
            refreshBalance()
        }
    }
)
GameballApp.getInstance().showProfile(request)
```

**Dismiss on logout:**
```swift
func logout() {
    GameballApp.getInstance().hideProfile()
    clearSession()
}
```

---

## Requirements

- iOS 12.0+
- Swift 5.0+
- Xcode 12.0+

---

## Migration

No changes required — all v3.1.x and v3.0.0 code works without modification. The new callbacks, parameters, and `hideProfile()` are additive. Diagnostic logging is automatic and requires no integration changes.

See [MIGRATION.md](MIGRATION.md) for details.

---

## Installation

```swift
.package(url: "https://github.com/gameballers/gameball-ios.git", from: "3.2.0")
```

---

## Support

- 📧 Email: support@gameball.co
- 📖 Documentation: https://developer.gameball.co/
- 🐛 Issues: https://github.com/gameballers/gameball-ios/issues

---

## Previous Release: v3.1.1

**Release Date**: 2025-12-15
**Type**: Patch Release

Guest mode support — the profile widget can be shown without customer authentication, and `ShowProfileRequest` became non-throwing with an optional `customerId`. See [CHANGELOG.md](CHANGELOG.md) for the full history.
