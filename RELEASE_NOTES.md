# Release Notes - Gameball iOS SDK

This file contains detailed release notes for the latest version. For complete version history, see [CHANGELOG.md](CHANGELOG.md).

---

## Latest Release: v4.1.0

**Release Date**: 2026-11-19
**Version**: 4.1.0
**Type**: Minor Release

---

## 📱 What's New

v4.1.0 brings **game campaigns** to in-app messaging, shows campaigns when **any of their conditions** match, and reports **influenced opens** of Gameball pushes. There are no breaking changes.

- **Game campaigns**: a spin the wheel, quiz or scratch and win opens itself over your app on its in-app messaging trigger
- **Any of the conditions**: a campaign set to match any of its event conditions shows when one of them matches
- **Influenced opens**: `GameballApp.handlePushReceived(_:appGroup:)` and `GameballConfig(appGroup:)` report app opens that a push led to without being tapped
- **Push taps counted once**: `handlePushClick` reports to the new `push-engagement` endpoint, once per tap
- **Widget host on the configuration**: `GameballConfig(widgetUrlPrefix:)` for the profile widget and game campaigns

---

## 🚀 Key Features

### 🎡 Game campaigns

A campaign the merchant set to open itself over your app arrives in the same sync as in-app messages and displays through the same window, so **there is nothing extra to integrate**:

```swift
GameballApp.getInstance().startInAppMessaging()
```

The SDK opens the game itself and shows the card only once the game has finished drawing, as a modal or fullscreen, with its own close button in the game's top-end corner. Games follow the message frequency rules — `repeatable`, `minIntervalSeconds`, the display cooldown and quiet hours — and a game the customer has finished isn't offered again until the next successful sync. A game is never opened from a cached campaign set, and reports no in-app messaging telemetry.

### 🔀 Any of the conditions

A campaign whose event conditions are set to match *any* (`metadataLogicalOperator: OR`) shows when at least one condition matches, for messages and games alike. Such campaigns used to be dropped.

### 📣 Influenced opens

An influenced open is an app open that no tap caused, within 30 minutes of an untapped Gameball push arriving. Enable one App Group for the app and its Notification Service Extension, then:

```swift
// In the app
let config = GameballConfig(apiKey: "your_api_key", lang: "en", appGroup: "group.com.example.app")

// In the Notification Service Extension's didReceive(_:withContentHandler:)
GameballApp.handlePushReceived(request.content.userInfo, appGroup: "group.com.example.app")
contentHandler(request.content)
```

`handlePushReceived` never changes or delays the notification. The extension only runs for pushes sent with `mutable-content: 1`. Swipe-aways aren't reported on iOS.

### 👆 Push taps counted once

`handlePushClick(_:completion:sessionToken:)` now reports to `push-engagement`, which replaces `push-click`, and counts a tap once per app process: calling it again for the same tap returns `true` and sends nothing. Taps and influenced opens stay on v4.0 when a session token is set.

### 🌐 Widget host on the configuration

`GameballConfig(widgetUrlPrefix:)` sets the widget host once, for the profile widget and any campaign a message opens.

---

## 🐛 Fixes

- **Game end dates**: an end date the sync sends without a time zone is read as UTC; it used to fail to parse, so the game never applied its end date

---

## ⚠️ Breaking Changes

None. Every v4.0.0 call keeps its signature and behaviour.

---

## 🔄 Changes

- Added game campaigns to in-app messaging
- Added any-condition (OR) event triggers
- Added `GameballApp.handlePushReceived(_:appGroup:)` and `GameballConfig(appGroup:)` for influenced opens
- Added `GameballConfig(widgetUrlPrefix:)`
- Changed push tap reporting to the `push-engagement` endpoint, once per tap
- Fixed game end dates sent without a time zone

---

## 🔧 Technical Details

### Requirements

- iOS 15.0+
- Swift 5.7+
- Xcode 14.0+
- For influenced opens: an App Group enabled for the app and its Notification Service Extension, and pushes sent with `mutable-content: 1`

---

## 📚 Migration Support

No code changes are required. To report influenced opens, add a Notification Service Extension that calls `GameballApp.handlePushReceived(_:appGroup:)`, and pass the same App Group to `GameballConfig(appGroup:)`.

### Migration Resources
- **[Migration Guide](MIGRATION.md)**: Step-by-step migration instructions
- **[README](README.md)**: Complete usage documentation with examples
- **[Changelog](CHANGELOG.md)**: Detailed list of all changes

### Support

- 📧 Email: support@gameball.co
- 📖 Documentation: https://developer.gameball.co/
- 🐛 Issues: https://github.com/gameballers/gameball-ios/issues

---

## 📦 Installation

```swift
.package(url: "https://github.com/gameballers/gameball-ios.git", from: "4.1.0")
```

---

## Previous Release: v4.0.0

**Release Date**: 2026-10-22
**Type**: Major Release

Raised the minimum supported iOS version to 15.0, and added in-app messaging: slideup, modal and fullscreen campaigns from the Gameball dashboard, triggered on session start or by custom events, with `logPurchase(...)`, `inAppMessagingDelegate` and automatic analytics. See [CHANGELOG.md](CHANGELOG.md) for the full history.
