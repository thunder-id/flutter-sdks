# ThunderID Flutter SDK — Agent Instructions

## Project overview

Flutter plugin providing the ThunderID authentication SDK (`thunderid_flutter`). Bridges to native iOS (`ThunderID` Swift SDK) and Android (`dev.thunderid:android`) via a `MethodChannel`. The `samples/quickstart` directory contains a standalone demo app.

## Build & test

```bash
# Fetch dependencies
flutter pub get

# Run static analysis (must pass before any PR)
flutter analyze

# Run unit tests
flutter test

# Build sample app (Android debug APK)
cd samples/quickstart && flutter build apk --debug
```

## `flutter analyze` compliance (required)

All code **must pass `flutter analyze` with zero errors**. The CI `lint` job runs this check on every PR and treats any violation as a build failure.

Configuration: `flutter_lints` ^3.0.0 via `analysis_options.yaml`. Key rules enforced:

| Rule | What to do |
|---|---|
| `require_trailing_commas` | Trailing comma required on the last element of multi-line argument lists and declarations. |
| `prefer_const_constructors` | Use `const` constructors wherever possible. |
| `prefer_single_quotes` | Use single quotes for string literals. |
| `prefer_final_fields` | Declare fields `final` unless mutation is required. |
| `avoid_dynamic_calls` | Do not call methods on `dynamic`-typed values without casting. |
| `always_declare_return_types` | Every function and method must have an explicit return type. |
| `directives_ordering` | Sort `import` directives alphabetically; dart: first, package: second, relative last. |

### Practical checklist before finishing any change

1. Run `flutter analyze` locally and fix every reported issue.
2. Add trailing commas to multi-line argument lists and declarations.
3. Prefer `const` constructors and `const` variables wherever the value is compile-time constant.
4. Use single quotes for all string literals.
5. Declare return types on every function and method.
6. Sort imports: `dart:` → `package:` → relative, each group alphabetically.
7. If a new file grows past ~400 lines, consider splitting it.

## File layout

```
lib/
  thunderid_flutter.dart        Public API barrel export
  src/
    thunderid_client.dart       Core SDK client
    channel/
      thunderid_channel.dart    MethodChannel bridge (dev.thunderid/sdk)
    models/                     Data models & error types
      thunderid_config.dart     SDK init config
      thunderid_error.dart      ThunderIDErrorCode enum + IAMException
      user.dart                 OAuth2 user claims
      user_profile.dart         Detailed profile
      token_response.dart       Token exchange result
      token_exchange_config.dart Token swap config
      flow_models.dart          FlowType, FlowStatus, embedded-flow types
      sign_in_options.dart      Optional sign-in customization
      sign_out_options.dart     Optional sign-out customization
      preferences.dart          ThemePreferences + I18nPreferences
    i18n/
      thunderid_i18n.dart       Locale resolution chain
      default_strings.dart      Built-in English strings
    flow_template_resolver.dart Embedded-flow URL builder
    widgets/
      thunderid_provider.dart   State provider (InheritedWidget root)
      thunderid_sign_in_button.dart   SignInButton / BaseSignInButton
      thunderid_sign_up_button.dart   SignUpButton / BaseSignUpButton
      thunderid_sign_out_button.dart  SignOutButton / BaseSignOutButton
      thunderid_sign_in.dart    Embedded sign-in form
      thunderid_sign_up.dart    Embedded sign-up form
      thunderid_signed_in.dart  Guard: renders child only when authenticated
      thunderid_signed_out.dart Guard: inverse of SignedIn
      thunderid_loading.dart    Guard: renders while SDK is loading
      thunderid_user.dart       User info display
      thunderid_user_dropdown.dart  User dropdown menu
      thunderid_user_profile.dart   Full profile view
      thunderid_callback.dart   OAuth2 redirect handler
      thunderid_language_switcher.dart  Locale selector
      flow_form.dart            Reusable form wrapper for flow steps
android/                        Kotlin method channel handler (JVM 17, minSdk 26)
ios/Classes/                    Swift method channel handler (iOS 16+)
test/                           Unit tests (flutter_test + mockito)
samples/quickstart/             Demo app (not part of the SDK package)
pubspec.yaml                    SDK package manifest
analysis_options.yaml           Lint configuration
```

## Architecture

- **Layer 1 — Client** (`thunderid_client.dart`): public Dart API — initialization, auth flows, token management, user/profile access. Delegates all logic to native SDKs; does not perform networking itself.
- **Layer 2 — Channel** (`channel/thunderid_channel.dart`): `MethodChannel('dev.thunderid/sdk')` bridge. Converts `PlatformException` → `IAMException` and handles typed deserialization.
- **Layer 3 — Widgets** (`widgets/`): Flutter UI components built on `InheritedWidget` (`ThunderIDProvider`).
- **Layer 4 — Sample** (`samples/quickstart/`): standalone demo app that depends on the SDK via path reference.

Every widget ships in two variants:
- **Styled** — opinionated Material 3 defaults (e.g. `SignInButton`).
- **Base** — unstyled slot-based variant for full customization (e.g. `BaseSignInButton`).

## Code style

- Dart 3.2+, Flutter 3.16+; full null safety (`?`, `??`, `!`).
- No external state management framework — use `InheritedWidget` (`ThunderIDProvider.of(context)`) for state access.
- All async methods return `Future`; no `Stream`s in the public API.
- Error handling uses typed `ThunderIDErrorCode` enum (23 codes) and `IAMException`.
- Mark implementation details `_private`; expose only intentional public API.
- Minimum tap targets: 44×44 logical pixels (WCAG 2.1 AA).
- All widgets must include `Semantics` labels for accessibility.
- iOS native: Swift 5.9, `@MainActor` for UI-thread safety.
- Android native: Kotlin, JVM 17, coroutines for async channel calls.
