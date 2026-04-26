<!-- SHARED:START (do not edit between these markers — managed by gameball-sdk-tooling) -->

# Gameball SDK — Shared Standards

These rules apply to all Gameball mobile SDKs (iOS, Android, Flutter, React Native).

## Public API Contract

All SDKs must expose the following public methods on `GameballApp`:

| Method | Parameters | Returns | Description |
|--------|-----------|---------|-------------|
| `getInstance()` | Platform-specific (e.g., `Context` on Android) | `GameballApp` | Singleton accessor |
| `init(config)` | `GameballConfig` | void / Promise | Initialize SDK with API key and settings |
| `initializeCustomer(request, callback)` | `InitializeCustomerRequest`, callback, optional `sessionToken` | void / Promise | Register or initialize a customer |
| `sendEvent(event, callback)` | `Event`, callback, optional `sessionToken` | void / Promise | Track a user event |
| `showProfile(request)` | `ShowProfileRequest`, optional `sessionToken` | void | Display the profile/loyalty widget |

When adding a new public method, it must be added to all 4 SDKs to maintain feature parity.

## Singleton Pattern

- All SDKs use a private constructor + `getInstance()` static method
- Only one instance of `GameballApp` exists per app lifecycle
- No public constructors — consumers must use `getInstance()`

## GameballConfig

All SDKs accept a `GameballConfig` with these fields:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `apiKey` | String | Yes | Gameball API key |
| `lang` | String | No | Language code (e.g., "en", "ar") |
| `platform` | String | No | Platform identifier |
| `shop` | String | No | Shop identifier |
| `apiPrefix` | String | No | Custom API base URL |
| `sessionToken` | String | No | Global session token for authentication |

## Session Token Convention

- `sessionToken` is an **optional** parameter on `initializeCustomer`, `sendEvent`, and `showProfile`
- When provided on a method call, it **overrides** the global `sessionToken` from `GameballConfig` for that call only
- When omitted, the global `sessionToken` is used (or null if none was set)

## Request Models

All request models (`InitializeCustomerRequest`, `ShowProfileRequest`, `Event`) must:
- Use builder pattern (Android/iOS) or typed objects/interfaces (RN/Flutter)
- Have clear, documented fields
- Validate required fields and throw/return meaningful errors on invalid input
- Support optional `customerId` on `ShowProfileRequest` for guest mode

## Callback Convention

All async operations take a callback with success and error paths:
- **Android**: `Callback<T>` interface with `onSuccess(T)` and `onError(Throwable)`
- **iOS**: Completion handler `((Result?, Error?) -> Void)`
- **React Native**: Promise-based (`async/await`) with optional callback parameter
- **Flutter**: Callback function parameter (e.g., `RegisterCallback`, `SendEventCallback`)

## Error Handling

- Validate `apiKey` is set before any API call — fail fast with a clear error message
- Never silently swallow errors — always surface them through the callback/completion
- Use platform-idiomatic error types (exceptions on Android, `Error` on iOS, thrown errors on RN, `Exception` on Flutter)

## SDK Initialization Flow

All SDKs follow the same init sequence:
1. Store config (API key, language, etc.)
2. Register API key with the network layer
3. Fetch bot settings in the background (fire-and-forget)
4. Mark SDK as initialized

## Versioning

Follow **Semantic Versioning** (MAJOR.MINOR.PATCH):
- **MAJOR** (X.0.0): Removed features, changed existing APIs, requires migration — breaking changes
- **MINOR** (0.Y.0): New features, new endpoints, backward compatible
- **PATCH** (0.0.Z): Bug fixes, security patches, small improvements

When determining version:
- Removed or changed existing functionality? → MAJOR
- Added new features or options? → MINOR
- Fixed bugs only? → PATCH

## Documentation Standards

**Full reference documents** (synced to `.claude/docs/` in each SDK repo):
- `.claude/docs/SDK_DOCUMENTATION_STANDARD.md` — Master reference for all SDK documentation structure, templates, and quality standards
- `.claude/docs/VERSIONING_AND_CHANGELOG_GUIDE.md` — Complete versioning decision tree, changelog writing guidelines, and release checklist

**You MUST read and follow these documents** when working on any documentation task (changelog entries, release notes, migration guides, README updates). They are the authoritative source for templates, formatting, emoji conventions, and quality standards.

All SDKs must maintain 4 documentation files:
1. **README.md** — Primary usage guide with installation, quick start, API reference
2. **CHANGELOG.md** — Version history with semantic categorization
3. **MIGRATION.md** — Upgrade guides for major versions
4. **RELEASE_NOTES.md** — Detailed information about the current release

### Changelog Emoji Format

Use these exact categories and emojis in CHANGELOG.md:

- Release type emojis: `🎉` Major, `📱` Minor, `🔧` Patch
- `### ✨ Added` — New features (`🏗️` Architecture, `⚙️` Configuration, `🔧` Developer experience)
- `### 🔄 Changed` — Modifications (`💥 **BREAKING**` prefix for breaking changes, `🚀` Performance, `📦` Dependencies)
- `### 🗑️ Removed` — Deleted features (`💥 **BREAKING**` prefix when applicable)
- `### 🐛 Fixed` — Bug fixes
- `### 🔒 Security` — Security improvements (`🛡️` prefix)

### Changelog Entry Quality

- Be specific and user-impact focused: "Fixed product image zoom not working on mobile Safari" not "Fixed bugs"
- Start with action verbs (Added, Fixed, Improved, Enhanced, Updated)
- Use past tense consistently
- Group related changes
- Mark breaking changes with `💥 **BREAKING**` prefix

Refer to `.claude/docs/VERSIONING_AND_CHANGELOG_GUIDE.md` for the full decision tree, templates, and examples.

### Version Entry Format

```markdown
## [X.Y.Z] - YYYY-MM-DD <release-emoji>

> **Release Type**: Brief description

### ✨ Added
- 🏗️ **Feature Name**: Description

### 🐛 Fixed
- 🔧 **Fix Name**: Description
```

### README, MIGRATION, and RELEASE_NOTES Structure

Refer to `.claude/docs/SDK_DOCUMENTATION_STANDARD.md` for the complete templates and structure requirements for each file.

## Cross-SDK Coordination

- Major releases should align across platforms when possible
- Breaking changes must be coordinated — all SDKs should release the same breaking change in the same version cycle
- Feature parity: when a feature is added to one SDK, track it for implementation in all others
- Use identical terminology for the same concepts across all SDKs

<!-- SHARED:END -->


## iOS-Specific Rules

### Language & Style
- Swift only — no Objective-C in new code
- Use `DispatchQueue` for thread safety (`queue.async { [weak self] in ... }`)
- Always use `[weak self]` in closures that capture `self` to avoid retain cycles
- Use `guard let self = self else { return }` pattern inside closures
- Prefer `is null` / `is not null` equivalents: optional binding (`if let`, `guard let`)

### Architecture
- Singleton via `private static let shared` + `public static func getInstance()`
- `NetworkManager.shared()` is the networking layer — all API calls go through it
- Bot settings stored in `GameballApp.clientBotStyle` static property
- Thread-safe access via `DispatchQueue(label: "com.gameball.sdk", qos: .utility)`

### Async Pattern
- Completion handlers: `((Error?) -> Void)?` for operations that can fail
- Success/error callbacks: `(Bool, String?) -> Void` for operations with status
- Fire-and-forget pattern for background operations (bot settings fetch)
- Always dispatch completion handlers to main queue: `DispatchQueue.main.async { completion?(nil) }`

### Distribution
- **CocoaPods**: `Gameball.podspec` — update `s.version` on release
- **Swift Package Manager**: `Package.swift` — update version tag on release
- Both must stay in sync

### Project Structure
```
Sources/Gameball/
├── GameballApp.swift          # Main SDK entry point
├── Constants.swift            # SDK constants
├── Errors/                    # Error types
├── Helpers/                   # Utility extensions
├── Models/                    # Data models
├── Network Layer/             # API client, endpoints
├── Assets/                    # Bundled resources
├── Classes/                   # UI components
└── Resources/                 # Plists, configs
```

### Naming Conventions
- No prefix on class names (Swift convention) — `GameballApp`, `GameballConfig`
- Request models: `InitializeCustomerRequest`, `ShowProfileRequest`
- Use `MARK: -` comments to organize code sections (`// MARK: - Public API`)

### Version Source Files
- `Gameball.podspec` → `s.version`
- `Package.swift` → git tag
