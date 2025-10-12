# Release Notes - Gameball iOS SDK

This file contains detailed release notes for the latest version. For complete version history, see [CHANGELOG.md](CHANGELOG.md).

---

## Latest Release: v3.0.0

**Release Date**: 2025-10-13
**Version**: 3.0.0
**Type**: Major Release

---

## 🎉 What's New

Gameball iOS SDK v3.0.0 represents a complete modernization with Swift-first architecture, throwing initializers, and enhanced type safety. This major release brings significant improvements to performance, reliability, and developer experience while transitioning from Player to Customer-centric terminology.

### 🔧 Modern Swift Architecture

- **Thread-Safe Singleton Pattern**: `GameballApp.getInstance()` provides centralized SDK management with serial dispatch queue
- **Throwing Initializers**: All request models use throwing constructors with compile-time validation
- **Type Safety**: Leverages Swift's type system to prevent runtime crashes
- **Codable Integration**: Modern Codable-based request encoding replaces manual parameter extraction

### 🛠️ Enhanced Developer Experience

- **Unified API Design**: Consistent method signatures and naming conventions
- **Better Error Handling**: Comprehensive `GameballError` enum with proper throwing mechanisms
- **IDE Support**: Improved auto-completion and IntelliSense support with throwing initializers
- **Type Safety**: Compile-time validation prevents common integration errors

### 📊 Improved Functionality

- **Enhanced Customer Management**: New `InitializeCustomerRequest` with comprehensive validation
- **Advanced Event Tracking**: Restructured `Event` system with flexible metadata support
- **Profile Widget Enhancements**: `ShowProfileRequest` for detailed widget customization
- **Push Notification Support**: Integrated Firebase and Huawei push provider handling
- **Language Management**: Enhanced language priority system (customer → global → config)

---

## 🚀 Key Features

### Centralized SDK Management
```swift
let config = GameballConfig(
    apiKey: "your_api_key",
    lang: "en"
)

GameballApp.getInstance().init(config: config) { error in
    if let error = error {
        print("Initialization failed: \(error)")
    }
}
```

### Customer Initialization with Throwing Initializers
```swift
do {
    let attributes = CustomerAttributes(
        displayName: "John Doe",
        firstName: "John",
        lastName: "Doe",
        mobile: "1234567890",
        preferredLanguage: "en",
        customAttributes: ["tier": "premium"]
    )

    let request = try InitializeCustomerRequest(
        customerId: "customer_123",
        email: "john@example.com",
        customerAttributes: attributes
    )

    GameballApp.getInstance().initializeCustomer(request) { response, errorMessage in
        // Handle response
    }
} catch {
    print("Validation error: \(error)")
}
```

### Enhanced Event Tracking
```swift
do {
    let event = try Event(
        events: [
            "purchase": [
                "amount": 99.99,
                "currency": "USD",
                "product_id": "prod_123"
            ]
        ],
        customerId: "customer_123"
    )

    GameballApp.getInstance().sendEvent(event) { success, errorMessage in
        // Handle response
    }
} catch {
    print("Validation error: \(error)")
}
```

### Flexible Customer Attributes
```swift
let attributes = CustomerAttributes(
    displayName: "John Doe",
    firstName: "John",
    lastName: "Doe",
    email: "john@example.com",
    mobile: "1234567890",
    gender: "M",
    dateOfBirth: "1990-01-15",
    preferredLanguage: "en",
    customAttributes: [
        "tier": "premium",
        "city": "New York"
    ],
    additionalAttributes: [
        "segment": "vip",
        "source": "mobile_app"
    ]
)
```

---

## ⚠️ Breaking Changes

**This is a major release with breaking changes**. Migration is required for existing v2.x users.

### API Changes
- `GameballApp.shared()` → `GameballApp.getInstance()` singleton pattern
- `registerPlayer()` → `initializeCustomer()` with throwing initializer
- Method signatures updated to use throwing initializers for requests
- All request models now require `try` keyword for construction

### Model Changes
- Player terminology → Customer terminology throughout SDK
- `PlayerAttributes` → `CustomerAttributes`
- `playerUniqueId` → `customerId`
- `mobileNumber` → `mobile` in CustomerAttributes
- Enhanced validation with `GameballError` enum
- New throwing initializers for `InitializeCustomerRequest`, `Event`, `ShowProfileRequest`

### Removed Features
- Legacy Player-based API methods
- Deprecated v2.x UI components (ChallengesViewController, MissionsViewController, etc.)
- Multiple method overloads (replaced with single throwing initializer pattern)
- View models (ChallengesViewModel, LeaderboardsViewModel, etc.)
- Custom parent view controller

---

## 📈 Performance Improvements

### Optimized Architecture
- **Reduced Memory Usage**: Eliminated duplicate object creation with Codable encoding
- **Faster Initialization**: Streamlined SDK initialization process
- **Better Network Efficiency**: Optimized request handling with object-based communication
- **Improved Validation**: Enhanced input validation prevents invalid API calls

### Code Quality
- **Comprehensive Refactoring**: Complete architecture overhaul
- **Eliminated Data Duplication**: Fixed issues where request data was copied multiple times
- **Better Error Handling**: Proper throwing-based error reporting instead of silent failures
- **Type Safety**: Swift's type system prevents common runtime errors
- **Thread Safety**: Serial dispatch queue prevents race conditions

---

## 🔧 Technical Details

### Requirements
- **Minimum iOS**: 12.0
- **Target iOS**: Latest
- **Swift**: 5.0+
- **Xcode**: 12.0+
- **CocoaPods**: 1.10+ or Swift Package Manager

### Dependencies
- Firebase/Core: Latest compatible version
- Firebase/Messaging: For push notification support
- Firebase/Analytics: For analytics tracking

### Internal Improvements
- Unified request/response handling with Codable
- Enhanced UserDefaults management for language preferences
- Improved callback-based async handling
- Better separation of concerns in architecture
- Centralized SDK info with `SDKInfo` enum
- Enhanced language resolution with priority system

---

## 🛡️ Security & Reliability

### Enhanced Validation
- Comprehensive input validation with proper error messages via throwing initializers
- Better API key management and validation
- Improved customer ID validation
- Enhanced request data validation

### Error Handling
- Specific `GameballError` enum types for different error scenarios
- Proper throwing-based error reporting
- Better error logging and debugging support
- Fail-fast validation to catch issues at construction time

### Data Protection
- Improved request data handling with Codable
- Better memory management with weak self references
- Enhanced null safety with Swift optionals
- Proper error message sanitization

---

## 📚 Migration Support

### Migration Resources
- **[Migration Guide](MIGRATION.md)**: Step-by-step migration instructions
- **[README](README.md)**: Complete usage documentation with examples
- **[Changelog](CHANGELOG.md)**: Detailed list of all changes

### Breaking Changes Summary
1. Update SDK access from `GameballApp.shared()` to `GameballApp.getInstance()`
2. Replace `registerPlayer` with `initializeCustomer` + throwing initializer
3. Update customer attributes to use CustomerAttributes (with `mobile` instead of `mobileNumber`)
4. Migrate event tracking to new `Event` throwing initializer
5. Update profile widget to use `ShowProfileRequest` throwing initializer
6. Replace all Player terminology with Customer
7. Wrap request model creation in `do-catch` blocks

### Support
- 📧 **Email**: support@gameball.co
- 📖 **Documentation**: [https://developer.gameball.co/](https://developer.gameball.co/)
- 🐛 **Issues**: [GitHub Issues](https://github.com/gameballers/gameball-ios/issues)

---

## 🎯 What's Next

### Future Enhancements
- Swift Concurrency (async/await) support
- Enhanced analytics capabilities
- Additional customization options
- Performance optimizations

### Roadmap
- Version 3.1.0: GB Token authentication for enhanced security
- Version 3.2.0: Swift Concurrency integration
- Future: Advanced personalization features

---

## 📦 Installation

### CocoaPods
```ruby
pod 'Gameball', '~> 3.0.0'
```

Then run:
```bash
pod install
```

### Swift Package Manager
Add to your `Package.swift`:
```swift
dependencies: [
    .package(url: "https://github.com/gameballers/gameball-ios.git", from: "3.0.0")
]
```

Or via Xcode: File > Add Packages > Enter repository URL:
```
https://github.com/gameballers/gameball-ios.git
```

---

## 🏆 Benefits Summary

✅ **Modern Architecture**: Swift-first design with throwing initializers
✅ **Better Developer Experience**: Compile-time validation with throwing initializers
✅ **Enhanced Performance**: Optimized internal architecture with Codable
✅ **Improved Reliability**: Better error handling and validation
✅ **Type Safety**: Compile-time validation prevents runtime errors
✅ **Future-Ready**: Modern foundation for upcoming features
✅ **Comprehensive Documentation**: Complete guides and examples
✅ **Customer-Centric**: Clear, business-focused terminology

---

## ⭐ Acknowledgments

We thank our development community for their feedback and contributions that made this release possible.

---

**Ready to upgrade?** Start with our [Migration Guide](MIGRATION.md).

*For technical support during migration, contact support@gameball.co*
