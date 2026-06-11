# 📋 Changelog

All notable changes to Gameball iOS SDK are documented here.


## [3.2.0] - 2026-06-17 📱

> **Minor Release**: Widget event channel, widget dismissal controls, external-link handling, diagnostic logging, and channel-merging parameters

### ✨ Added
- 🏗️ **Widget Event Channel**: `ShowProfileRequest.widgetEventCallback` receives events posted from the widget (e.g. game completion) as a `[String: Any]` `{type, metadata}`; the `gameCompleted` payload carries `hasWon`, `rewardType`, `discountType`, `rewardName`, `campaignId`, `campaignType`
- 🏗️ **Web-Initiated Close**: the widget can dismiss its own webview via `window.GameballWidget.closeWidget()`
- 🏗️ **Host-Initiated Dismiss**: new `GameballApp.hideProfile()` dismisses the widget programmatically (no-op when nothing is shown)
- ⚙️ **External-Link Handling**: links flagged `gbExternalBrowser=true` open in the system browser; optional `externalLinkCallback` lets the host intercept them
- 📊 **Diagnostic Logging**: added internal diagnostic logging to aid SDK troubleshooting
- 📇 **Channel-Merging Parameters**: `showProfile` now accepts optional `mobile` and `email` to support customer channel merging

### 🔄 Changed
- 🔧 **User-Agent Header**: unified the `x-gb-agent` header format to `GB/<sdkType>/<version>`


## [3.1.1] - 2025-12-15 🔧

> **Patch Release**: Guest mode support for profile widget

### 🐛 Fixed
- 🎁 **Guest Mode Support**: Profile widget can now be displayed without customer authentication
- 🔓 **Optional Customer ID**: `ShowProfileRequest.customerId` is now optional, defaulting to `nil` for guest mode

### 🔄 Changed
- 🏗️ **ShowProfileRequest Initializer**: No longer throws - customer ID validation removed for guest mode support
- 📝 **Widget URL Construction**: Enhanced to support both authenticated and guest modes

### 🛠️ Developer Experience
- ⚡ **Simpler API**: Create `ShowProfileRequest` without `try` keyword - non-throwing initializer
- 🎯 **Flexible Usage**: Support for preview/showcase scenarios before user registration
- 📖 **Better Documentation**: Clear examples for both guest and authenticated modes

---

## [3.1.0] - 2025-11-05 🔐

> **Feature Release**: Token-based authentication with automatic endpoint versioning

### ✨ Added
- 🔐 **Session Token Authentication**: Optional token-based authentication for enhanced API security
- 🔄 **Automatic Endpoint Versioning**: Seamless switching between v4.0 and v4.1 endpoints based on token presence
- 🎯 **Per-Request Token Override**: Flexible token management with per-method sessionToken parameter
- 📝 **X-GB-TOKEN Header**: Automatic header injection for authenticated requests
- 🔧 **Widget Token Support**: Session token integration in profile widget URL
- 🧵 **Thread-Safe Token Access**: Secure token storage with dispatch queue synchronization

### 🔄 Changed
- ⚡ **Non-Blocking Initialization**: SDK init no longer waits for bot settings API call
- 🔧 **Optional Completion Handler**: Init completion handler is now optional
- 📡 **Smart API Routing**: Endpoints automatically route to secure v4.1 when token is present

### 🛡️ Security
- 🔒 **Enhanced API Security**: Optional token-based authentication layer beyond API key
- 🎯 **Flexible Authentication**: Support for multi-user scenarios and per-request authentication control
- 🔐 **In-Memory Token Storage**: Session tokens stored in memory (not persisted) for security

### 📚 Documentation
- Added session token configuration examples
- Documented per-request token override patterns
- Updated API versioning behavior

---

## [3.0.0] - 2025-10-13 🎉

> **Major Release**: Complete SDK modernization with breaking API changes for iOS best practices

### ✨ Added
- 🏗️ **Modern Swift Architecture**: Singleton pattern with `GameballApp.getInstance()`
- ⚙️ **Type-Safe Request Models**: Throwing initializers with built-in validation
- 🔧 **Enhanced Validation**: `GameballError` enum for comprehensive error handling
- 🚀 **Immutable Models**: All request models (`InitializeCustomerRequest`, `Event`, `ShowProfileRequest`) with throwing constructors
- 📊 **Improved Event Tracking**: Restructured `Event` model with flexible metadata support
- 🎁 **Advanced Profile Widget**: New `ShowProfileRequest` with comprehensive customization options
- 🌐 **Language Management**: Enhanced language priority system (customer → global → config)
- 📱 **Push Notification Support**: Native Firebase and Huawei push provider integration
- 🛡️ **Input Validation**: Comprehensive validation with proper error messages
- 🔗 **Referral Code Support**: Built-in referral tracking in customer initialization
- ⚡ **Thread Safety**: Thread-safe singleton with serial dispatch queue
- 🔧 **Custom Widget URL**: Support for custom widget URL prefixes
- 🎨 **Customizable Close Button**: Custom colors and RTL/LTR positioning for widget close button

### 🔄 Changed
- 💥 **BREAKING**: Migrated from individual static methods to singleton pattern
- 💥 **BREAKING**: All request models now use throwing initializers instead of builder pattern
- 💥 **BREAKING**: Method signatures updated to use throwing Swift structs
- 💥 **BREAKING**: Customer initialization now requires `InitializeCustomerRequest` object
- 💥 **BREAKING**: Event tracking requires `Event` object with validation
- 💥 **BREAKING**: Profile widget requires `ShowProfileRequest` object
- 💥 **BREAKING**: `registerPlayer` renamed to `initializeCustomer`
- 💥 **BREAKING**: `playerID` terminology replaced with `customerId` throughout
- 🚀 **Performance**: Optimized internal architecture with Codable encoding
- 📦 **Network Layer**: Refactored to use object-based communication instead of manual parameter extraction
- 🔧 **Error Handling**: Enhanced error messages with specific validation feedback
- 📱 **Widget Integration**: Improved profile widget rendering with better language support
- 🧹 **Code Organization**: Centralized SDK info with `SDKInfo` enum

### 🗑️ Removed
- 💥 **BREAKING**: Removed deprecated v2.x Player-based API methods
- 💥 **BREAKING**: Removed legacy UI components (Challenge, Mission, Leaderboard, Profile views)
- 💥 **BREAKING**: Removed multiple method overloads (replaced with single throwing initializer pattern)
- 💥 **BREAKING**: Removed view models (ChallengesViewModel, LeaderboardsViewModel, etc.)
- 🧹 **Cleanup**: Removed unused internal dependencies and legacy code paths
- 💥 **BREAKING**: Removed deprecated parent view controller and custom UI components
- 💥 **BREAKING**: Removed hardcoded SDK version from NetworkManager (now in SDKInfo)

### 🐛 Fixed
- 🔧 **Widget Display**: Fixed profile widget language resolution using priority system
- 🔧 **Memory Management**: Resolved memory leaks with weak self references
- 🔧 **Type Safety**: Fixed compilation issues with Swift strict mode
- 🔧 **Async Handling**: Improved callback handling and error propagation
- 🔧 **Push Notifications**: Fixed device token validation for Firebase and Huawei providers
- 🔧 **SDK Version**: Fixed stale SDK version in HTTP headers
- 🔧 **Customer Attributes**: Fixed missing completion callback in initializeCustomer

### 🔒 Security
- 🛡️ **Input Validation**: Enhanced validation prevents invalid API calls and data corruption
- 🛡️ **API Key Management**: Improved API key handling with better security practices
- 🛡️ **Error Sanitization**: Proper error message sanitization to prevent information leakage
- 🛡️ **Thread Safety**: Thread-safe singleton prevents race conditions

---

## [2.2.3] - 2024-11-15 📱

> **Patch Release**: Privacy manifest updates

### 🔄 Changed
- 📱 **Privacy Info**: Adjusted privacy information in manifest for App Store compliance

---

## [2.2.2] - 2024-10-28 🔧

> **Patch Release**: Privacy and widget improvements

### ✨ Added
- 📋 **Privacy Manifest**: Added privacy info to manifest for better transparency
- 🎛️ **Pull to Dismiss**: Added pullToDismiss option for widget

---

## [2.2.1] - 2024-09-20 🌐

> **Patch Release**: Language handling improvements

### ✨ Added
- 🌍 **Language Headers**: Pass lang parameter to network request headers for better localization

---

## [2.2.0] - 2024-08-15 📢

> **Minor Release**: Referral system improvements

### 🐛 Fixed
- 🔧 **Register Player**: Fix register player being called multiple times

---

## [2.1.1] - 2024-07-10 🔧

> **Patch Release**: Version bump with improvements

### 🔄 Changed
- 📦 **Version Management**: Bumped version with improved release process

---

## [2.1.0] - 2024-06-01 🎛️

> **Minor Release**: Widget customization enhancements

### ✨ Added
- 🎛️ **Close Button Control**: Option to show/hide the widget close button
- 🎨 **Widget Customization**: Enhanced widget display options

---

## [2.0.0] - 2024-03-15 🎉

> **Major Release**: Customer-centric API transition

### ✨ Added
- 🎯 **Customer-Centric API**: Complete transition from "Player" to "Customer" terminology
- 📱 **Better WebView**: Improved scrolling and interaction in the customer profile widget
- 📦 **Updated Dependencies**: Latest Firebase versions for better performance

### 🔄 Changed
- 💥 **BREAKING**: Now runs on Integrations APIs V4 - more powerful and flexible!
- 🎨 **Enhanced Profile Widget**: Smoother scrolling and better user experience

---

## [1.0.0] - 2023-10-01 🎉

> **Initial Release**: Welcome to Gameball iOS SDK!

### ✨ Added
- 👥 **Player Registration**: Register and manage player profiles
- 🔗 **Referral System**: Built-in referral tracking and management
- 📊 **Event Tracking**: Track user actions and behaviors
- 🎨 **Profile Widget**: Beautiful customer profile display widget
- 🏆 **Challenges & Missions**: Challenge and mission tracking
- 📊 **Leaderboards**: Leaderboard integration
- 🔔 **Push Notifications**: Firebase push notification support

*Ready to engage your customers like never before!* 🚀

---

*For migration guides and detailed upgrade instructions, see [MIGRATION.md](MIGRATION.md)*
