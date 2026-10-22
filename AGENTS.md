# ThunderID Flutter SDK — Agent Instructions

## Project overview

Flutter plugin providing the ThunderID authentication SDK (`thunderid_flutter`). Bridges to native iOS (`ThunderID` Swift SDK) and Android (`dev.thunderid:android`) via a `MethodChannel`. The Quickstart demo app lives in the samples repository at [`quickstarts/flutter`](https://github.com/thunder-id/samples/tree/main/quickstarts/flutter). The [`playground/`](playground/README.md) app exercises every SDK capability and widget against this checkout (`thunderid_flutter: path: ..`).

## SDK development specification

Every change to this SDK goes through the ThunderID SDK development specification. It is
maintained in the product repository and governs all four SDK repositories, so it is linked
here rather than copied.

- [SDK development specification](https://github.com/thunder-id/thunderid/blob/main/docs-internals/sdk-development/spec.md):
  the contract this SDK implements. Layering, operational modes, configuration keys, client
  surface, error model, security floor, platform packaging, testing, and the cross-SDK parity
  rules.
- [SDK threat model](https://github.com/thunder-id/thunderid/blob/main/docs-internals/sdk-development/threat-model.md):
  the security posture the specification's floor comes from.
- [`sdk-development` skill](https://github.com/thunder-id/thunderid/blob/main/.agent/skills/sdk-development/SKILL.md):
  loads both documents and drives the work, from locating the SDK checkouts through validation
  to raising the linked pull requests.

Read the specification before adding or changing an operation, configuration key, error, or UI
component. A capability that lands here usually needs to land in the sibling SDKs too, and the
pull request has to answer that question either way, by linking the sibling pull requests or
by saying why they are not needed.

## Vendor naming rules

The SDK is white-labelable: a consuming app can override the brand/vendor namespace via `ThunderIDConfig.vendor`, so storage keys, log tags, and similar runtime names shouldn't be pinned to one brand.

- Do not hardcode the literal `thunderid`/`ThunderID`/`THUNDERID` (any casing) when building a runtime key/name that a consumer's `vendor` override should control — platform-channel storage keys, log tags, and the like.
- It's fine for **entry point file/package names** (e.g. `thunderid_flutter.dart`, `thunderid_client.dart`, `thunderid_provider.dart`) and types whose purpose IS to represent the SDK itself (e.g. `ThunderIDClient`, `ThunderIDProvider`) to carry the name. That's a fixed identity, not a per-tenant value. Don't flag those.
- Avoiding the vendor name entirely is the best outcome, when the brand prefix isn't actually load-bearing.
- When a brand-scoped namespace is genuinely required, resolve it from `config.vendor` (which already defaults to `'thunderid'`) instead of hardcoding a literal. If the same default-resolution logic starts appearing in more than one place, extract a small shared helper rather than repeating the literal default. Remember this may need bridging through the platform channel since this package delegates to native iOS/Android SDKs.

## Build & test

```bash
# Fetch dependencies
flutter pub get

# Run static analysis (must pass before any PR)
flutter analyze

# Run unit tests
flutter test

# Fetch the Quickstart sample into tests/e2e/.samples, pointed at this checkout,
# then build it (Android debug APK)
tests/e2e/scripts/prepare-sample.sh
cd tests/e2e/.samples/quickstarts/flutter && cp .env.example .env && flutter build apk --debug

# Analyze and build the playground app (it has its own pubspec and analysis_options,
# and the root analyzer excludes it)
cd playground && cp .env.example .env && flutter pub get && flutter analyze && flutter build apk --debug
```

When you add or change a public API or widget, update the playground too: add or adjust the
capability check in `playground/lib/src/checks.dart` or the story in `playground/lib/src/stories.dart`.

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
    management/                 Management operations (users, groups, roles, agents)
      thunderid_management_client.dart  CRUD + relationship operations over HTTP
      management_transport.dart         ManagementFetcher + default authenticated transport
      permissions.dart                  getTokenPermissions / hasPermission
      management_display.dart           toManagementErrorMessage / resolveManagedIdentityName
    models/management/          ManagedUser, Group, Role, Agent, ManagementPage
    state/                      ResourceQuery/ResourceMutation notifiers, ManagementResources
    widgets/
      thunderid_provider.dart   State provider (InheritedWidget root)
      sign_in_button.dart       SignInButton / BaseSignInButton
      sign_up_button.dart       SignUpButton / BaseSignUpButton
      sign_out_button.dart      SignOutButton / BaseSignOutButton
      sign_in.dart              Embedded sign-in form
      sign_up.dart              Embedded sign-up form
      signed_in.dart            Guard: renders child only when authenticated
      signed_out.dart           Guard: inverse of SignedIn
      loading.dart              Guard: renders while SDK is loading
      user_object.dart          User info display
      user_dropdown.dart        User dropdown menu
      user_profile.dart         Full profile view
      callback.dart             OAuth2 redirect handler
      language_switcher.dart    Locale selector
      flow_form.dart            Reusable form wrapper for flow steps
      admin/                    Admin components (UserList, GroupMembers, RoleAssignments, ...)
android/                        Kotlin method channel handler (JVM 17, minSdk 26)
ios/Classes/                    Swift method channel handler (iOS 16+)
test/                           Unit tests (flutter_test + mockito)
tests/e2e/                      Maestro E2E suite; fetches the Quickstart sample from thunder-id/samples
playground/                     Development app (checks, component explorer, session, logs) built from this checkout
pubspec.yaml                    SDK package manifest
analysis_options.yaml           Lint configuration
```

## Architecture

- **Layer 1 — Client** (`thunderid_client.dart`): public Dart API — initialization, auth flows, token management, user/profile access. Delegates all protocol logic to native SDKs. The one exception is management operations (`management/`), which call the management API from Dart with the access token the native SDK hands out, so `http.fetcher` can replace their transport.
- **Layer 2 — Channel** (`channel/thunderid_channel.dart`): `MethodChannel('dev.thunderid/sdk')` bridge. Converts `PlatformException` → `IAMException` and handles typed deserialization.
- **Layer 3 — Widgets** (`widgets/`): Flutter UI components built on `InheritedWidget` (`ThunderIDProvider`).
- **Layer 4 — Sample** ([`thunder-id/samples` `quickstarts/flutter`](https://github.com/thunder-id/samples/tree/main/quickstarts/flutter)): standalone demo app that depends on the published SDK. `tests/e2e/scripts/prepare-sample.sh` fetches it and overrides that dependency with this checkout.

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
