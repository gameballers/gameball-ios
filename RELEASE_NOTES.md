# Release Notes - Gameball iOS SDK

This file contains detailed release notes for the latest version. For complete version history, see [CHANGELOG.md](CHANGELOG.md).

---

## Latest Release: v3.1.1

**Release Date**: 2025-12-15
**Version**: 3.1.1
**Type**: Patch Release

---

## 🎉 What's New

v3.1.1 fixes the profile widget to support guest mode, allowing users to explore loyalty features before signing up. All v3.0.0 and v3.1.0 code continues to work without modifications.

### Guest Mode Support

The profile widget now works without requiring customer authentication:

```swift
// Show widget without customer ID
let guestRequest = ShowProfileRequest(
    showCloseButton: true,
    closeButtonColor: "#4CAF50"
)
GameballApp.getInstance().showProfile(guestRequest)

// Authenticated mode
let customerRequest = ShowProfileRequest(
    customerId: "customer_123",
    showCloseButton: true
)
GameballApp.getInstance().showProfile(customerRequest)
```

### Simplified API

`ShowProfileRequest` is now non-throwing since customer ID is optional:

```swift
// v3.1.0 - throwing initializer
let request = try ShowProfileRequest(customerId: "customer_123")

// v3.1.1 - non-throwing
let request = ShowProfileRequest(customerId: "customer_123")  // No 'try'
```

---

## 🔄 Changes

- `ShowProfileRequest` initializer is now non-throwing (no validation errors)
- `customerId` parameter is optional (defaults to `nil` for guest mode)

---

## Usage Examples

**Conditional Display** - Show guest mode for unauthenticated users:
```swift
func showLoyaltyWidget() {
    if let customerId = UserDefaults.standard.string(forKey: "customerId") {
        let request = ShowProfileRequest(customerId: customerId)
        GameballApp.getInstance().showProfile(request, presentationStyle: .fullScreen)
    } else {
        let guestRequest = ShowProfileRequest()
        GameballApp.getInstance().showProfile(guestRequest, presentationStyle: .pageSheet)
    }
}
```

**UI Presentation** - Customize modal presentation:
```swift
// Full screen (default)
GameballApp.getInstance().showProfile(request, presentationStyle: .fullScreen)

// Page sheet (card-like)
GameballApp.getInstance().showProfile(request, presentationStyle: .pageSheet)

// Form sheet (centered)
GameballApp.getInstance().showProfile(request, presentationStyle: .formSheet)
```

**SwiftUI Integration**:
```swift
import SwiftUI
import Gameball

struct ContentView: View {
    var body: some View {
        Button("Show Loyalty") {
            let request = ShowProfileRequest(customerId: "customer_123")
            GameballApp.getInstance().showProfile(request, presentationStyle: .fullScreen)
        }
    }
}
```

---

## Requirements

- iOS 12.0+
- Swift 5.0+
- Xcode 12.0+

---

## Migration

No changes required. Existing v3.1.0 and v3.0.0 code works without modifications.

See [MIGRATION.md](MIGRATION.md) for details.

---

## Installation

```swift
.package(url: "https://github.com/gameballers/gameball-ios.git", from: "3.1.1")
```

---

## Support

- 📧 Email: support@gameball.co
- 📖 Documentation: https://developer.gameball.co/
- 🐛 Issues: https://github.com/gameballers/gameball-ios/issues

---

## Previous Release: v3.0.0

**Release Date**: 2025-10-13
**Version**: 3.0.0
**Type**: Major Release

---

### What's New

Complete SDK modernization with Swift-first architecture, throwing initializers, and transition from Player to Customer terminology.

**Key Changes:**
- Singleton pattern: `GameballApp.getInstance()`
- Throwing initializers with compile-time validation
- Player → Customer terminology
- Enhanced type safety with `GameballError` enum

---

### Breaking Changes

Migration required for v2.x users:

- `GameballApp.shared()` → `GameballApp.getInstance()`
- `registerPlayer()` → `initializeCustomer()`
- Player terminology → Customer terminology
- `PlayerAttributes` → `CustomerAttributes`
- `playerUniqueId` → `customerId`
- `mobileNumber` → `mobile`
- All request models require `try` keyword
- Removed v2.x UI components

See [MIGRATION.md](MIGRATION.md) for upgrade instructions.
