# Gameball iOS SDK

[![Version](https://img.shields.io/badge/version-3.0.0-blue.svg)](https://github.com/gameballers/gameball-ios)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![iOS](https://img.shields.io/badge/iOS-12.0%2B-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.0%2B-orange.svg)](https://swift.org)

Gameball iOS SDK allows you to integrate customer engagement and loyalty features into your iOS applications with modern Swift patterns and type-safe request models.

## Features

- 🎯 **Customer Management** - Initialize and manage customer profiles
- 📊 **Event Tracking** - Track user actions and behaviors with flexible metadata
- 🎁 **Profile Widget** - Display customer loyalty information in customizable UI
- 🔧 **Modern Architecture** - Built with iOS best practices and Swift concurrency
- 🛡️ **Type Safety** - Compile-time validation with Swift's type system
- ⚡ **Async-Ready** - Modern async architecture with proper callback handling

## Requirements

- **Minimum iOS Version**: 12.0
- **Target iOS Version**: Latest
- **Swift**: 5.0+
- **Xcode**: 12.0+
- **CocoaPods**: 1.10+ or Swift Package Manager

## Installation

### CocoaPods
```ruby
pod 'Gameball', '~> 3.0.0'
```

Then run:
```bash
pod install
```

### Swift Package Manager
Add the following to your `Package.swift`:
```swift
dependencies: [
    .package(url: "https://github.com/gameballers/gameball-ios.git", from: "3.0.0")
]
```

Or add it via Xcode: File > Add Packages > Enter repository URL:
```
https://github.com/gameballers/gameball-ios.git
```

## Quick Start

### 1. Initialize the SDK
```swift
import Gameball

let config = GameballConfig(
    apiKey: "your_api_key",
    lang: "en"
)

GameballApp.getInstance().init(config: config) { error in
    if let error = error {
        print("SDK initialization failed: \(error.localizedDescription)")
    } else {
        print("SDK initialized successfully")
    }
}
```

### 2. Initialize Customer
```swift
import Gameball

let attributes = CustomerAttributes(
    displayName: "John Doe",
    firstName: "John",
    lastName: "Doe",
    email: "john@example.com",
    mobile: "1234567890",
    customAttributes: ["tier": "premium"]
)

let request = try InitializeCustomerRequest(
    customerId: "unique_customer_id",
    email: "customer@example.com",
    mobile: "1234567890",
    customerAttributes: attributes
)

GameballApp.getInstance().initializeCustomer(request) { response, errorMessage in
    if let errorMessage = errorMessage {
        print("Error: \(errorMessage)")
    } else {
        print("Customer initialized successfully")
    }
}
```

### 3. Track Events
```swift
import Gameball

let event = try Event(
    events: [
        "purchase": [
            "amount": 100.00,
            "currency": "USD",
            "product_id": "prod_123"
        ]
    ],
    customerId: "unique_customer_id"
)

GameballApp.getInstance().sendEvent(event) { success, errorMessage in
    if success {
        print("Event sent successfully")
    } else if let errorMessage = errorMessage {
        print("Error sending event: \(errorMessage)")
    }
}
```

### 4. Show Profile Widget
```swift
import Gameball

let profileRequest = try ShowProfileRequest(
    customerId: "unique_customer_id",
    showCloseButton: true,
    closeButtonColor: "#FF0000"
)

GameballApp.getInstance().showProfile(profileRequest)
```

## API Methods

The SDK provides the following public methods:
- `init(config:completion:)` - Initialize the SDK with GameballConfig
- `initializeCustomer(_:completion:)` - Register/initialize customer with throwing initializer
- `sendEvent(_:completion:)` - Track events with Event model
- `showProfile(_:presentationStyle:)` - Show profile widget with ShowProfileRequest

## Advanced Usage

### Customer Attributes
```swift
let attributes = CustomerAttributes(
    displayName: "John Doe",
    firstName: "John",
    lastName: "Doe",
    email: "john@example.com",
    mobile: "1234567890",
    gender: "M",
    dateOfBirth: "1990-01-01",
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

### Push Notifications
```swift
// Firebase FCM
let request = try InitializeCustomerRequest(
    customerId: "customer_id",
    deviceToken: "fcm_token",
    pushProvider: .firebase
)

// Huawei Push Kit
let request = try InitializeCustomerRequest(
    customerId: "customer_id",
    deviceToken: "hms_token",
    pushProvider: .huawei
)
```

### Error Handling
```swift
do {
    let request = try InitializeCustomerRequest(
        customerId: "customer_id",
        deviceToken: "token",
        pushProvider: .firebase
    )

    GameballApp.getInstance().initializeCustomer(request) { response, errorMessage in
        if let errorMessage = errorMessage {
            // Handle API error
            print("API Error: \(errorMessage)")
        } else {
            // Handle success
            print("Success: \(response?.gameballId ?? "")")
        }
    }
} catch GameballError.emptyCustomerId {
    // Handle validation error
    print("Customer ID cannot be empty")
} catch GameballError.missingDeviceToken {
    print("Device token is required when push provider is set")
} catch {
    // Handle other errors
    print("Error: \(error.localizedDescription)")
}
```

## ⚠️ Migration from v2.x

**Version 3.0.0 contains breaking changes**. See [Migration Guide](MIGRATION.md) for detailed upgrade instructions.

### Key Changes in v3.0.0:
- All request models now use throwing initializers with validation
- Immutable request objects with compile-time validation
- Enhanced API key and customer ID validation
- Simplified architecture with cleaner data flow
- Removed deprecated v2.x UI components

## Configuration Options

### GameballConfig
Configuration object for initializing the Gameball SDK.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `apiKey` | String | ✅ | Your Gameball API key |
| `lang` | String | ✅ | Language code (e.g., "en", "ar") |
| `platform` | String | ❌ | Platform identifier |
| `shop` | String | ❌ | Shop identifier |
| `apiPrefix` | String | ❌ | Custom API base URL |

**Validation Rules:**
- `apiKey` cannot be empty
- `lang` cannot be empty and should be 2-letter ISO code

**Example:**
```swift
let config = GameballConfig(
    apiKey: "your_api_key_here",
    lang: "en",
    platform: "ios",
    shop: "your_shop"
)
```

### InitializeCustomerRequest
Request object for initializing/registering customers with the Gameball platform.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `customerId` | String | ✅ | Unique customer identifier |
| `deviceToken` | String | ❌ | Push notification token |
| `pushProvider` | PushProvider | ❌ | Push notification provider (Firebase/Huawei) |
| `customerAttributes` | CustomerAttributes | ❌ | Additional customer data |
| `referralCode` | String | ❌ | Referral code for attribution |
| `email` | String | ❌ | Customer email address |
| `mobile` | String | ❌ | Customer mobile number |
| `isGuest` | Bool | ❌ | Guest status (defaults to false) |

**Validation Rules:**
- `customerId` cannot be empty
- If `pushProvider` is set, `deviceToken` must also be provided
- If `deviceToken` is provided, `pushProvider` must be specified
- Throws `GameballError` if validation fails

**Example:**
```swift
let request = try InitializeCustomerRequest(
    customerId: "customer_123",
    email: "john@example.com",
    mobile: "1234567890",
    deviceToken: "firebase_token",
    pushProvider: .firebase,
    customerAttributes: attributes,
    referralCode: "REF123",
    isGuest: false
)
```

### CustomerAttributes
Additional customer information for enriching customer profiles and personalization.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `displayName` | String | ❌ | Customer display name |
| `firstName` | String | ❌ | Customer first name |
| `lastName` | String | ❌ | Customer last name |
| `email` | String | ❌ | Customer email |
| `gender` | String | ❌ | Customer gender |
| `mobile` | String | ❌ | Customer mobile number |
| `dateOfBirth` | String | ❌ | Date of birth (YYYY-MM-DD format) |
| `joinDate` | String | ❌ | Join date (YYYY-MM-DD format) |
| `preferredLanguage` | String | ❌ | Preferred language (2-letter ISO code) |
| `customAttributes` | [String: String] | ❌ | Custom key-value pairs |
| `additionalAttributes` | [String: String] | ❌ | Additional flexible attributes |
| `channel` | String | 🔒 | Channel identifier (automatically set to "mobile") |

**Example:**
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
        "segment": "vip"
    ]
)
```

### Event
Event objects for tracking customer actions and behaviors for analytics and campaign triggers.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `customerId` | String | ✅ | Customer identifier |
| `events` | [String: [String: Any]] | ✅ | Event data with metadata |
| `email` | String | ❌ | Customer email |
| `mobile` | String | ❌ | Customer mobile number |

**Validation Rules:**
- `customerId` cannot be empty
- `events` dictionary cannot be empty
- Throws `GameballError` if validation fails

**Example:**
```swift
let event = try Event(
    events: [
        "purchase": [
            "amount": 99.99,
            "currency": "USD",
            "product_id": "prod_123",
            "category": "electronics"
        ]
    ],
    customerId: "customer_123",
    email: "john@example.com",
    mobile: "1234567890"
)

// Multiple events example
let multipleEvents = try Event(
    events: [
        "page_view": [
            "page": "product_detail",
            "product_id": "prod_123"
        ],
        "add_to_cart": [
            "product_id": "prod_123",
            "quantity": 1
        ]
    ],
    customerId: "customer_123"
)
```

### ShowProfileRequest
Request object for displaying the Gameball customer profile widget with customization options.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `customerId` | String | ✅ | Customer identifier |
| `openDetail` | String | ❌ | Specific detail to open (e.g., "achievements", "leaderboard") |
| `hideNavigation` | Bool | ❌ | Hide navigation elements |
| `showCloseButton` | Bool | ❌ | Show close button (defaults to true) |
| `closeButtonColor` | String | ❌ | Close button color (hex format like "#FF0000") |
| `widgetUrlPrefix` | String | ❌ | Custom widget URL prefix |

**Validation Rules:**
- `customerId` cannot be empty
- Throws `GameballError.emptyCustomerId` if validation fails

**Example:**
```swift
let profileRequest = try ShowProfileRequest(
    customerId: "customer_123",
    openDetail: "rewards",
    hideNavigation: false,
    showCloseButton: true,
    closeButtonColor: "#FF6B6B",
    widgetUrlPrefix: "https://custom.example.com/widget"
)

GameballApp.getInstance().showProfile(profileRequest, presentationStyle: .fullScreen)
```

## Troubleshooting

### Common Issues

**1. SDK Not Initialized**
```
Error: SDK not initialized
```
**Solution**: Ensure you call `GameballApp.getInstance().init(config:completion:)` before any other SDK methods.

**2. Empty Customer ID**
```
GameballError.emptyCustomerId
```
**Solution**: Provide a valid, non-empty customer ID in your requests.

**3. Push Provider Validation**
```
GameballError.missingDeviceToken
GameballError.missingPushProvider
```
**Solution**: When setting a push provider, ensure you also provide a valid device token, and vice versa.

**4. Widget Not Displaying**
```
Error: SDK not initialized
```
**Solution**: Initialize the SDK and customer before showing the profile widget.

### Debug Logging
The SDK provides console logging for debugging. Check Xcode's console for detailed logs when debugging integration issues.

## Documentation

- 📋 **[Changelog](CHANGELOG.md)** - Version history and changes
- 🔄 **[Migration Guide](MIGRATION.md)** - v2.x to v3.0.0 upgrade instructions
- 📝 **[Release Notes](RELEASE_NOTES.md)** - Latest release details

## Support

- 📧 **Email**: support@gameball.co
- 📖 **Documentation**: [https://developer.gameball.co/](https://developer.gameball.co/)
- 🐛 **Issues**: [GitHub Issues](https://github.com/gameballers/gameball-ios/issues)

## License

MIT License

Copyright (c) 2025 Gameball

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
