# Migration Guide: Gameball iOS SDK v2.x → v3.0.0

This guide helps you migrate from v2.x to v3.0.0 with modern iOS architecture, throwing initializers, and enhanced type safety.

## Overview of Changes

### 🔧 What's New
- **Modern Swift Architecture** with enhanced type safety support
- **Throwing Initializers** with compile-time validation for better developer experience
- **Enhanced API Validation** for better error handling and debugging
- **Simplified Architecture** for improved performance and maintainability

### ⚠️ Breaking Changes
- Migration from direct instantiation to singleton pattern
- New throwing initializers for all request models
- Method signature changes across all SDK methods
- Player terminology replaced with Customer terminology
- Removed deprecated v2.x UI components

---

## Step-by-Step Migration

### 1. Update Dependencies

**Before (v2.x):**
```ruby
pod 'Gameball', '~> 2.2.3'
```

**After (v3.0.0):**
```ruby
pod 'Gameball', '~> 3.0.0'
```

Then run:
```bash
pod install
```

### 2. SDK Initialization

**Before (v2.x):**
```swift
import Gameball

GameballApp.shared().init(
    APIKey: "your_api_key",
    Language: "en"
) { error in
    // Handle completion
}
```

**After (v3.0.0):**
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

### 3. Customer Registration/Initialization

**Before (v2.x):**
```swift
import Gameball

// v2.x used "Player" terminology
let playerAttributes = PlayerAttributes(
    displayName: "John Doe",
    firstName: "John",
    lastName: "Doe",
    mobileNumber: "0123456789",
    preferredLanguage: "en",
    customAttributes: ["city": "New York"]
)

GameballApp.shared().registerPlayer(
    playerUniqueId: "player_123",
    email: "john@example.com",
    mobile: "1234567890",
    playerAttributes: playerAttributes,
    completion: { response, error in
        // Handle response
    }
)
```

**After (v3.0.0):**
```swift
import Gameball

do {
    // v3.0.0 uses "Customer" terminology
    let attributes = CustomerAttributes(
        displayName: "John Doe",
        firstName: "John",
        lastName: "Doe",
        mobile: "0123456789",
        preferredLanguage: "en",
        customAttributes: ["city": "New York"]
    )

    let request = try InitializeCustomerRequest(
        customerId: "customer_123",
        email: "john@example.com",
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
    print("Validation error: \(error.localizedDescription)")
}
```

### 4. Customer Attributes

**Before (v2.x):**
```swift
let playerAttributes = PlayerAttributes(
    displayName: "John Doe",
    mobileNumber: "0123456789",
    customAttributes: ["key": "value"]
)
```

**After (v3.0.0):**
```swift
let attributes = CustomerAttributes(
    displayName: "John Doe",
    mobile: "0123456789",
    customAttributes: ["key": "value"],
    additionalAttributes: ["flexible_field": "value"]  // New feature
)
```

### 5. Event Tracking

**Before (v2.x):**
```swift
GameballApp.shared().sendEvent(
    playerUniqueId: "player_123",
    eventName: "purchase",
    eventMetaData: [
        "amount": "100.00",
        "currency": "USD"
    ],
    completion: { success, error in
        // Handle response
    }
)
```

**After (v3.0.0):**
```swift
do {
    let event = try Event(
        events: [
            "purchase": [
                "amount": 100.00,
                "currency": "USD"
            ]
        ],
        customerId: "customer_123"
    )

    GameballApp.getInstance().sendEvent(event) { success, errorMessage in
        if success {
            print("Event sent successfully")
        } else if let errorMessage = errorMessage {
            print("Error sending event: \(errorMessage)")
        }
    }
} catch {
    print("Validation error: \(error.localizedDescription)")
}
```

### 6. Profile Widget

**Before (v2.x):**
```swift
GameballApp.shared().showProfile(
    playerUniqueId: "player_123",
    openDetail: "achievements",
    hideNavigation: false
)
```

**After (v3.0.0):**
```swift
do {
    let profileRequest = try ShowProfileRequest(
        customerId: "customer_123",
        openDetail: "achievements",
        hideNavigation: false,
        showCloseButton: true,
        closeButtonColor: "#FF0000"  // New customization option
    )

    GameballApp.getInstance().showProfile(profileRequest, presentationStyle: .fullScreen)
} catch {
    print("Validation error: \(error.localizedDescription)")
}
```

### 7. Push Notifications

**Before (v2.x):**
```swift
// Firebase setup (v2.x had different integration)
GameballApp.shared().registerPlayer(
    playerUniqueId: "player_123",
    deviceToken: "fcm_token",
    // ... other parameters
)
```

**After (v3.0.0):**
```swift
do {
    // Firebase FCM
    let request = try InitializeCustomerRequest(
        customerId: "customer_123",
        deviceToken: "fcm_token",
        pushProvider: .firebase
    )

    GameballApp.getInstance().initializeCustomer(request) { response, errorMessage in
        // Handle response
    }

    // Huawei Push Kit (new support)
    let huaweiRequest = try InitializeCustomerRequest(
        customerId: "customer_123",
        deviceToken: "hms_token",
        pushProvider: .huawei
    )
} catch {
    print("Validation error: \(error.localizedDescription)")
}
```

---

## Common Migration Patterns

### Error Handling Migration

**Before (v2.x):**
```swift
GameballApp.shared().registerPlayer(/*params*/) { response, error in
    if let error = error {
        // Handle error
    } else if let response = response {
        // Handle success
    }
}
```

**After (v3.0.0):**
```swift
do {
    let request = try InitializeCustomerRequest(/*params*/)

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

### Terminology Changes

| v2.x | v3.0.0 | Notes |
|------|--------|-------|
| `Player` | `Customer` | Terminology updated throughout SDK |
| `playerUniqueId` | `customerId` | More descriptive naming |
| `PlayerAttributes` | `CustomerAttributes` | Consistent with new terminology |
| `mobileNumber` | `mobile` | Simplified naming |
| `registerPlayer` | `initializeCustomer` | Clearer method name |

---

## Migration Checklist

### Pre-Migration
- [ ] Review current SDK usage in your app
- [ ] Identify all SDK method calls
- [ ] Plan for testing after migration
- [ ] Backup current implementation

### During Migration
- [ ] Update CocoaPods dependency to v3.0.0
- [ ] Convert initialization to use GameballConfig
- [ ] Replace `registerPlayer` calls with `initializeCustomer` + throwing initializer
- [ ] Update customer attributes to use CustomerAttributes (with `mobile` instead of `mobileNumber`)
- [ ] Migrate event tracking to new Event throwing initializer
- [ ] Update profile widget calls to use ShowProfileRequest
- [ ] Update push notification handling to use new pattern
- [ ] Replace all `Player` references with `Customer`
- [ ] Replace all `playerUniqueId` references with `customerId`
- [ ] Wrap request model creation in `do-catch` blocks

### Post-Migration
- [ ] Test all SDK functionality
- [ ] Verify error handling works correctly
- [ ] Test push notifications
- [ ] Verify profile widget displays correctly
- [ ] Test event tracking
- [ ] Run full integration tests
- [ ] Test on iOS 12.0 (minimum supported version)

---

## Troubleshooting

### Common Issues

1. **Build Errors After Update**
   ```
   Error: Value of type 'GameballApp' has no member 'shared'
   ```
   **Solution**: Replace `GameballApp.shared()` with `GameballApp.getInstance()`.

2. **Type Mismatch Errors**
   ```
   Error: Cannot convert value of type 'PlayerAttributes' to expected argument type 'CustomerAttributes'
   ```
   **Solution**: Replace `PlayerAttributes` with `CustomerAttributes`.

3. **Missing Required Fields**
   ```
   Error: GameballError.emptyCustomerId
   ```
   **Solution**: Ensure all required fields are set when creating request models. Wrap in do-catch block to handle validation errors.

4. **Method Not Found**
   ```
   Error: Value of type 'GameballApp' has no member 'registerPlayer'
   ```
   **Solution**: Replace `registerPlayer()` with `initializeCustomer()` and use throwing initializer pattern.

5. **MobileNumber Property Not Found**
   ```
   Error: Value of type 'CustomerAttributes' has no member 'mobileNumber'
   ```
   **Solution**: Replace `mobileNumber` with `mobile` in CustomerAttributes.

### Getting Help
For additional migration support, contact support@gameball.co or visit our documentation at https://developer.gameball.co/

---

## Benefits After Migration

✅ **Better Type Safety**: Swift's type system and throwing initializers prevent common integration errors

✅ **Improved Developer Experience**: Throwing initializers with IDE auto-completion support

✅ **Better Error Handling**: Enhanced validation with clear error messages at initialization time

✅ **Enhanced Performance**: Optimized internal architecture with reduced memory usage

✅ **Future-Proof**: Modern foundation ready for upcoming iOS features

✅ **Consistent API**: Unified design patterns across all SDK methods

✅ **Customer-Centric**: Clear, business-focused terminology throughout the SDK

---

## Removed Features in v3.0.0

The following v2.x features have been removed:

### Removed UI Components
- ❌ `ChallengesViewController` and related challenge views
- ❌ `MissionsViewController` and related mission views
- ❌ `LeaderboardViewController` and related leaderboard views
- ❌ `ProfileViewController` (old implementation)
- ❌ `NotificationsViewController`
- ❌ Custom parent view controller

**Reason**: These components were tightly coupled to specific UI patterns. v3.0.0 focuses on providing a simple, customizable profile widget while letting you build custom UI using the SDK's data methods.

**Alternative**: Use the `showProfile()` method to display the built-in widget, or build custom UI using SDK data methods.

### Removed View Models
- ❌ `ChallengesViewModel`
- ❌ `LeaderboardsViewModel`
- ❌ Other internal view models

**Reason**: v3.0.0 simplifies the architecture by removing view models that were specific to removed UI components.

---

## API Comparison Table

| Feature | v2.x | v3.0.0 |
|---------|------|--------|
| **SDK Access** | `GameballApp.shared()` | `GameballApp.getInstance()` |
| **Initialization** | `init(APIKey:Language:completion:)` | `init(config:completion:)` |
| **Customer Registration** | `registerPlayer(playerUniqueId:...)` | `initializeCustomer(InitializeCustomerRequest)` |
| **Event Tracking** | `sendEvent(playerUniqueId:eventName:...)` | `sendEvent(Event)` |
| **Profile Widget** | `showProfile(playerUniqueId:...)` | `showProfile(ShowProfileRequest)` |
| **Error Handling** | Callback-only | Throwing initializers + callbacks |
| **Validation** | Runtime only | Compile-time + runtime |

---

*For additional help with migration, contact support@gameball.co*
