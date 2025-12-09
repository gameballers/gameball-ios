# Gameball iOS SDK

[![Version](https://img.shields.io/badge/version-3.1.1-blue.svg)](https://github.com/gameballers/gameball-ios)
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
- **Swift Package Manager**: Required

## Installation

### Swift Package Manager

**Via Package.swift:**
```swift
dependencies: [
    .package(url: "https://github.com/gameballers/gameball-ios.git", from: "3.1.1")
]
```

**Via Xcode:**
1. File > Add Packages
2. Enter repository URL: `https://github.com/gameballers/gameball-ios.git`
3. Select version: `3.1.1` or later

## Quick Start

### 1. Initialize the SDK
```swift
import Gameball

let config = GameballConfig(
    apiKey: "your_api_key",
    lang: "en"
)

GameballApp.getInstance().`init`(config: config) { error in
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

do {
    let attributes = CustomerAttributes(
        displayName: "John Doe",
        firstName: "John",
        lastName: "Doe",
        email: "john@example.com",
        mobile: "1234567890",
        customAttributes: ["tier": "premium"]
    )

    let request = try InitializeCustomerRequest(
        customerId: "customer_id",
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
} catch {
    print("Validation error: \(error)")
}
```

### 3. Track Events
```swift
import Gameball

do {
    let event = try Event(
        events: [
            "purchase": [
                "amount": 100.00,
                "currency": "USD",
                "product_id": "prod_123",
                "category": "electronics",
                "quantity": 2
            ]
        ],
        customerId: "customer_id"
    )

    GameballApp.getInstance().sendEvent(event) { success, errorMessage in
        if success {
            print("Event sent successfully")
        } else if let errorMessage = errorMessage {
            print("Error sending event: \(errorMessage)")
        }
    }
} catch {
    print("Validation error: \(error)")
}
```

### 4. Show Profile Widget
```swift
import Gameball

// For authenticated customers
let profileRequest = ShowProfileRequest(
    customerId: "customer_id",
    showCloseButton: true,
    closeButtonColor: "#FF0000"
)

GameballApp.getInstance().showProfile(profileRequest)

// For guest mode (no customer ID required)
let guestProfileRequest = ShowProfileRequest(
    showCloseButton: true,
    closeButtonColor: "#FF0000"
)

GameballApp.getInstance().showProfile(guestProfileRequest)
```

#### UI Presentation
The SDK automatically handles view controller presentation. You can customize the modal presentation style:

**UIKit:**
```swift
// Full screen presentation (default)
GameballApp.getInstance().showProfile(profileRequest, presentationStyle: .fullScreen)

// Page sheet (iOS 13+)
GameballApp.getInstance().showProfile(profileRequest, presentationStyle: .pageSheet)

// Form sheet
GameballApp.getInstance().showProfile(profileRequest, presentationStyle: .formSheet)

// Automatic (adapts to device)
GameballApp.getInstance().showProfile(profileRequest, presentationStyle: .automatic)
```

**SwiftUI:**
```swift
import SwiftUI
import Gameball

struct ContentView: View {
    var body: some View {
        VStack {
            Button("Show Profile") {
                showProfileWidget()
            }

            Button("Show Guest Profile") {
                showGuestProfileWidget()
            }
        }
    }

    private func showProfileWidget() {
        let profileRequest = ShowProfileRequest(
            customerId: "customer_123",
            showCloseButton: true,
            closeButtonColor: "#FF6B6B"
        )

        // SDK automatically finds and presents on the root view controller
        GameballApp.getInstance().showProfile(profileRequest, presentationStyle: .fullScreen)
    }

    private func showGuestProfileWidget() {
        let guestRequest = ShowProfileRequest(
            showCloseButton: true,
            closeButtonColor: "#4CAF50"
        )

        GameballApp.getInstance().showProfile(guestRequest, presentationStyle: .pageSheet)
    }
}
```

**How It Works:**
- The SDK automatically finds your app's root view controller
- Works seamlessly with both UIKit and SwiftUI apps
- Presents the profile widget modally with animation
- No manual view controller management required

## API Methods

The SDK provides the following public methods:
- ``init`(config:completion:)` - Initialize the SDK with GameballConfig (completion is optional)
- `initializeCustomer(_:completion:sessionToken:)` - Register/initialize customer with optional token override
- `sendEvent(_:completion:sessionToken:)` - Track events with optional token override
- `showProfile(_:presentationStyle:sessionToken:)` - Show profile widget with optional token override

## Advanced Usage

### Guest Mode (v3.1.1+)

The profile widget now supports guest mode, allowing users to view it without authentication. This is useful for showcasing loyalty features before user registration.

#### Show Profile Widget in Guest Mode
```swift
// Guest mode - no customer ID required
let guestRequest = ShowProfileRequest(
    showCloseButton: true,
    closeButtonColor: "#4CAF50"
)

GameballApp.getInstance().showProfile(guestRequest, presentationStyle: .fullScreen)
```

#### Show Profile for Authenticated Customer
```swift
// Authenticated mode - with customer ID
let customerRequest = ShowProfileRequest(
    customerId: "customer_123",
    openDetail: "details_earn",  // Open the earn points section
    showCloseButton: true,
    closeButtonColor: "#FF6B6B"
)

GameballApp.getInstance().showProfile(customerRequest, presentationStyle: .fullScreen)
```

**Key Features:**
- **No Authentication Required**: Display widget without customer login
- **Seamless Experience**: Same widget UI for both guest and authenticated users
- **Easy Transition**: Users can register after exploring as guests

### UI Presentation Styles

The SDK provides flexible presentation options that work with both UIKit and SwiftUI applications.

#### Available Presentation Styles

**Full Screen (Default)**
```swift
// Covers the entire screen
GameballApp.getInstance().showProfile(profileRequest, presentationStyle: .fullScreen)
```

**Page Sheet (iOS 13+)**
```swift
// Card-like appearance with rounded corners
GameballApp.getInstance().showProfile(profileRequest, presentationStyle: .pageSheet)
```

**Form Sheet**
```swift
// Centered modal (useful for iPad)
GameballApp.getInstance().showProfile(profileRequest, presentationStyle: .formSheet)
```

**Automatic**
```swift
// System determines the best style for the device
GameballApp.getInstance().showProfile(profileRequest, presentationStyle: .automatic)
```

#### UIKit Integration Example

```swift
import UIKit
import Gameball

class ProfileViewController: UIViewController {
    @IBAction func showProfileTapped(_ sender: UIButton) {
        let profileRequest = ShowProfileRequest(
            customerId: "customer_123",
            showCloseButton: true,
            closeButtonColor: "#FF6B6B"
        )

        // SDK handles presentation automatically
        GameballApp.getInstance().showProfile(profileRequest, presentationStyle: .fullScreen)
    }

    @IBAction func showGuestProfileTapped(_ sender: UIButton) {
        let guestRequest = ShowProfileRequest(
            showCloseButton: true,
            closeButtonColor: "#4CAF50"
        )

        // Present as page sheet for guest mode
        GameballApp.getInstance().showProfile(guestRequest, presentationStyle: .pageSheet)
    }
}
```

#### SwiftUI Integration Example

```swift
import SwiftUI
import Gameball

struct ProfileView: View {
    @State private var showingProfile = false

    var body: some View {
        VStack(spacing: 20) {
            Button(action: {
                presentAuthenticatedProfile()
            }) {
                Text("View My Rewards")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }

            Button(action: {
                presentGuestProfile()
            }) {
                Text("Explore Loyalty Program")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(10)
            }
        }
    }

    private func presentAuthenticatedProfile() {
        let request = ShowProfileRequest(
            customerId: "customer_123",
            openDetail: "details_earn",  // Open the earn points section
            showCloseButton: true,
            closeButtonColor: "#007AFF"
        )

        GameballApp.getInstance().showProfile(request, presentationStyle: .fullScreen)
    }

    private func presentGuestProfile() {
        let request = ShowProfileRequest(
            showCloseButton: true,
            closeButtonColor: "#34C759"
        )

        GameballApp.getInstance().showProfile(request, presentationStyle: .pageSheet)
    }
}
```

**Implementation Notes:**
- The SDK automatically resolves your app's root view controller
- No need to pass view controller references manually
- Presentation happens on the main thread automatically
- Works with navigation controllers, tab bar controllers, and split view controllers
- The widget dismisses automatically when the close button is tapped

### Session Token Authentication (v3.1.0+)

The SDK supports optional token-based authentication for enhanced security. Session tokens are stored in-memory and automatically injected into API requests.

#### Initialize with Session Token
```swift
let config = GameballConfig(
    apiKey: "your_api_key",
    lang: "en",
    sessionToken: "your_session_token"  // Optional
)

GameballApp.getInstance().`init`(config: config)
```

#### Per-Request Token Override
You can override or clear the session token for individual API calls:

```swift
// Override token for this specific request
GameballApp.getInstance().initializeCustomer(
    request,
    completion: { response, error in
        // Handle response
    },
    sessionToken: "new_token"  // Overrides global token
)

// Clear token for this specific request
GameballApp.getInstance().sendEvent(
    event,
    completion: { success, error in
        // Handle response
    },
    sessionToken: nil  // Clears token for this request
)

// Use with showProfile
GameballApp.getInstance().showProfile(
    profileRequest,
    sessionToken: "specific_token"
)
```

#### How It Works
- **Without token**: Requests use `/api/v4.0/integrations/*` endpoints
- **With token**: Requests automatically route to `/api/v4.1/integrations/*` with `X-GB-TOKEN` header
- **In-memory storage**: Tokens are not persisted and cleared on app restart
- **Thread-safe**: All token operations are synchronized for multi-threaded access

### Customer Attributes
```swift
do {
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

    let request = try InitializeCustomerRequest(
        customerId: "customer_id",
        customerAttributes: attributes
    )

    GameballApp.getInstance().initializeCustomer(request) { response, error in
        // Handle response
    }
} catch {
    print("Validation error: \(error)")
}
```

### Push Notifications
```swift
do {
    // Firebase FCM
    let request = try InitializeCustomerRequest(
        customerId: "customer_id",
        deviceToken: "fcm_token",
        pushProvider: .firebase
    )

    GameballApp.getInstance().initializeCustomer(request) { response, error in
        // Handle response
    }
} catch {
    print("Validation error: \(error)")
}

do {
    // Huawei Push Kit
    let request = try InitializeCustomerRequest(
        customerId: "customer_id",
        deviceToken: "hms_token",
        pushProvider: .huawei
    )

    GameballApp.getInstance().initializeCustomer(request) { response, error in
        // Handle response
    }
} catch {
    print("Validation error: \(error)")
}
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
do {
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

    GameballApp.getInstance().initializeCustomer(request) { response, error in
        // Handle response
    }
} catch {
    print("Validation error: \(error)")
}
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
do {
    let event = try Event(
        events: [
            "purchase": [
                "amount": 99.99,
                "currency": "USD",
                "product_id": "prod_123",
                "category": "electronics",
                "quantity": 2,
                "discount": 10.00,
                "payment_method": "credit_card"
            ]
        ],
        customerId: "customer_123",
        email: "john@example.com",
        mobile: "1234567890"
    )

    GameballApp.getInstance().sendEvent(event) { success, error in
        // Handle response
    }
} catch {
    print("Validation error: \(error)")
}
```

### ShowProfileRequest
Request object for displaying the Gameball customer profile widget with customization options. Supports both authenticated and guest modes.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `customerId` | String? | ❌ | Customer identifier (optional - omit for guest mode) |
| `openDetail` | String | ❌ | Specific detail to open (e.g., "details_earn") |
| `hideNavigation` | Bool | ❌ | Hide navigation elements |
| `showCloseButton` | Bool | ❌ | Show close button (defaults to true) |
| `closeButtonColor` | String | ❌ | Close button color (hex format like "#FF0000") |
| `widgetUrlPrefix` | String | ❌ | Custom widget URL prefix |

**Guest Mode (v3.1.1+):**
- `customerId` is now optional - when `nil` or omitted, widget opens in guest mode
- Allows users to explore loyalty features without authentication

**Example (Authenticated):**
```swift
let profileRequest = ShowProfileRequest(
    customerId: "customer_123",
    openDetail: "details_earn",  // Open the earn points section
    hideNavigation: false,
    showCloseButton: true,
    closeButtonColor: "#FF6B6B",
    widgetUrlPrefix: "https://custom.example.com/widget"
)

GameballApp.getInstance().showProfile(profileRequest, presentationStyle: .fullScreen)
```

**Example (Guest Mode):**
```swift
// No customerId - opens in guest mode
let guestRequest = ShowProfileRequest(
    showCloseButton: true,
    closeButtonColor: "#4CAF50"
)

GameballApp.getInstance().showProfile(guestRequest, presentationStyle: .fullScreen)
```

## Troubleshooting

### Common Issues

**1. SDK Not Initialized**
```
Error: SDK not initialized
```
**Solution**: Ensure you call `GameballApp.getInstance().`init`(config:completion:)` before any other SDK methods.

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
