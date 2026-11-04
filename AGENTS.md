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
      thunderid_error.dart      ThunderIDErrorCode enum, IAMException, IAMApiException (+ serverError),
                                AdministrationFlowError
      user.dart                 OAuth2 user claims
      user_profile.dart         Detailed profile
      token_response.dart       Token exchange result
      token_exchange_config.dart Token swap config
      flow_models.dart          FlowType, FlowStatus, embedded-flow types
      sign_in_options.dart      Optional sign-in customization (incl. organizationUnitId)
      ciba.dart                 CIBA request options and response
      device_authorization.dart Device authorization (RFC 8628) device-side result
      account/organization_unit.dart  Accessible and current organization units
      sign_out_options.dart     Optional sign-out customization
      preferences.dart          ThemePreferences + I18nPreferences
    i18n/
      thunderid_i18n.dart       Locale resolution chain
      default_strings.dart      Built-in English strings (the key set every locale translates)
      built_in_strings.dart     Shipped locales (the JS SDK's set) and the built-in bundle lookup
      translations/             One bundle per shipped non-English locale (fr_fr.dart, ja_jp.dart, ...)
    flow_template_resolver.dart Embedded-flow URL builder
    api/account/                The signed-in user's own data over HTTP (organization_units.dart: /users/me/ous)
    api/auth/                   Auth flows and reads the Dart layer runs itself (device_grant_flow.dart:
                                verifyDeviceCode; authorization_details_types.dart: the RFC 9396 types)
    api/management/             Management operations (users, user types, groups, roles, agents,
                                agent types, applications, and the resource families below)
      thunderid_management_client.dart  CRUD + relationship operations over HTTP, administrationMode
      management_collection.dart        URL resolution + send shared by the client and its extensions
      administration_flows.dart         Administration flow operations (resolve, find, execute, run)
      account_lifecycle.dart            Flow-only suspend/unsuspend/unlock for users, agents, applications
      organization_units.dart, resource_servers.dart, connections.dart, flows.dart,
      notification_templates.dart, design.dart, translations.dart, server_config.dart,
      gateways.dart, variables.dart, configuration.dart, sharing.dart,
      credential_configurations.dart, presentation_definitions.dart, client_registrations.dart,
      projects.dart, authorization_detail_types.dart
                                        One extension on ThunderIDManagementClient per resource family
      secrets.dart                      Secret generation + delegated-agent rule (package-internal)
      management_transport.dart         ManagementFetcher + default authenticated transport
      permissions.dart                  getTokenPermissions / hasPermission
      management_display.dart           toManagementErrorMessage / resolveManagedIdentityName
    models/management/          ManagedUser, Group, Role, Agent, Application, entity types,
                                administration constants, ManagementPage, and one model file per
                                resource family (organization_unit.dart, connection.dart, ...)
    state/                      ResourceQuery/ResourceMutation notifiers, ManagementResources
      hierarchy_resources.dart  Project, organization unit and sharing policy queries and mutations
    components/                 Grouped by function; test/components/ mirrors this layout
      thunderid_provider.dart   State provider (InheritedWidget root), shared by every group; holds the
                                current project (currentProject / setCurrentProject, in memory)
      auth/                     Sign-in, sign-up and redirect handling
        sign_in.dart            Embedded sign-in form
        sign_up.dart            Embedded sign-up form
        callback.dart           OAuth2 redirect handler
        federated_redirect.dart Federated (social) redirect step shared by SignIn and SignUp
        device_grant.dart       DeviceGrant: the user side of device authorization (verifyDeviceCode)
        buttons/                SignIn/SignUp/SignOutButton and the social/passkey provider buttons
        flow/                   Flow-step rendering (FlowForm: fields, error banner, key-value list, ...)
        guards/                 SignedIn, SignedOut, Loading
      account/                  The signed-in user's own widgets (UserObject, UserAvatar,
                                UserDropdown, UserProfile, ChangeCredential, OrganizationUnitSwitcher)
      management/               Management components (UserList, GroupMembers, RoleAssignments, ...)
        projects/               ProjectList, ProjectCreate, ProjectDetails, ProjectSwitcher
        organization_units/     OrganizationUnitList, OrganizationUnitCreate, OrganizationUnitDetails
        sharing/                SharingPolicies (users, applications, roles, flows) and its parts
        internal/               Plumbing shared only by the management components
      common/                   LanguageSwitcher and the logo/ branding widgets (ThunderIDLogo, AvatarLogo)
      internal/                 Plumbing shared by more than one widget (account_style.dart)
android/                        Kotlin method channel handler (JVM 17, minSdk 26)
ios/Classes/                    Swift method channel handler (iOS 16+)
test/                           Unit tests (flutter_test + mockito); widget tests live under test/components/
tests/e2e/                      Maestro E2E suite; fetches the Quickstart sample from thunder-id/samples
playground/                     Development app (checks, component explorer, session, logs) built from this checkout
pubspec.yaml                    SDK package manifest
analysis_options.yaml           Lint configuration
```

## Architecture

- **Layer 1 — Client** (`thunderid_client.dart`): public Dart API — initialization, auth flows, token management, user/profile access. Delegates all protocol logic to native SDKs. The exceptions are the management operations (`api/management/`) and the account data layer (`api/account/`), which call the server from Dart with the access token the native SDK hands out, so `http.fetcher` can replace their transport, and the user side of device authorization (`api/auth/`), which runs the `DEVICE_GRANT` flow from Dart without a token. An operation that needs a native capability the pinned native SDK lacks is refused in the channel handler with `OPERATION_NOT_SUPPORTED`, never silently dropped.
- **Layer 2 — Channel** (`channel/thunderid_channel.dart`): `MethodChannel('dev.thunderid/sdk')` bridge. Converts `PlatformException` → `IAMException` and handles typed deserialization.
- **Layer 3 — Widgets** (`components/`): Flutter UI components built on `InheritedWidget` (`ThunderIDProvider`).
- **Layer 4 — Sample** ([`thunder-id/samples` `quickstarts/flutter`](https://github.com/thunder-id/samples/tree/main/quickstarts/flutter)): standalone demo app that depends on the published SDK. `tests/e2e/scripts/prepare-sample.sh` fetches it and overrides that dependency with this checkout.

Every widget ships in two variants:
- **Styled** — opinionated Material 3 defaults (e.g. `SignInButton`).
- **Base** — takes its data and callbacks as parameters, with no SDK state (e.g. `BaseSignInButton`).

Both variants also accept a custom render. See [Adding or changing a component](#adding-or-changing-a-component).

## Adding or changing a component

The [SDK development specification](https://github.com/thunder-id/thunderid/blob/main/docs-internals/sdk-development/spec.md) (UI) is the contract. In practice, every component:

1. **Lives in its functional group:** `auth/` (sign-in, sign-up, recovery, invites, callback, with `buttons/`, `flow/` and `guards/` inside), `account/` (the signed-in user's own data), `admin/` (management), or `common/` (shared across groups, such as the language switcher and branding). Primitives and the data layer keep their own folders.
2. **Ships a styled variant and a `Base` variant.** `Base` takes its data and callbacks as parameters, with no SDK state, so an app can drive it itself (e.g. `BaseUserList`).
3. **Accepts a custom render on both variants.** Passing it replaces the built-in UI, while the component keeps its data loading, state and actions. The mechanism is the platform's own:
   - Flutter: an optional `builder`, the same pattern as `BaseSignIn`.
   It receives everything needed to draw the component: rows, columns, paging (`limit`, `offset`, `totalResults`, page change) and selection for a list; values, setters, submit and validity for a form; the record and the actions the app has allowed for a details, members, assignments or permissions view; plus loading and error state. Behaviour the specification requires still holds under a custom render: data-changing actions are off unless the app turns them on, a delete asks for confirmation, and server errors appear as translated messages.
4. **Takes every string from the translation bundle**, in every shipped locale: add the English
   string to `i18n/default_strings.dart` and its translation to every bundle under
   `i18n/translations/` (reuse the JavaScript SDK's translation when it has the same key or the
   same English text). `test/i18n_test.dart` fails on a key a locale lacks.
5. **Tags elements rendered from a server-described flow step** with `thunderid-field-<id>` and `thunderid-action-<ref>`.
6. **Has tests** for the built-in UI and for a custom render (`flutter test` widget tests).
7. **Has a playground story,** including a **Custom rendering** variant drawn with the platform's own UI toolkit, and a capability check if it calls the server.

A component that changes here usually needs the same change in the sibling SDKs. See the parity rules in the specification.

## Samples

The quickstarts and integration samples live in [thunder-id/samples](https://github.com/thunder-id/samples), and each one pins a released version of this SDK. A change here therefore can't break a sample until the sample bumps its version, which is exactly when a break would surface for a real app. Before raising a pull request, check every sample that uses this SDK:

- **A sample stops compiling or behaving the same** (a renamed type or package, a changed signature, a moved default): raise a samples pull request that bumps the SDK version and fixes the sample. Keep it as a draft until the SDK release it needs is out.
- **The change adds something a sample exists to show** (a self-care capability for `self-care/account`, a management component or operation for `management/admin`, a new sign-in option for the quickstarts): update that sample in the same samples pull request, so it demonstrates the new capability rather than working around its absence.
- Link the samples pull request from this pull request's **Related PRs**, or say why no sample is affected.

## Code style

- Dart 3.2+, Flutter 3.16+; full null safety (`?`, `??`, `!`).
- No external state management framework — use `InheritedWidget` (`ThunderIDProvider.of(context)`) for state access.
- All async methods return `Future`; no `Stream`s in the public API.
- Error handling uses the typed `ThunderIDErrorCode` enum and `IAMException`.
- Mark implementation details `_private`; expose only intentional public API.
- Minimum tap targets: 44×44 logical pixels (WCAG 2.1 AA).
- All widgets must include `Semantics` labels for accessibility.
- iOS native: Swift 5.9, `@MainActor` for UI-thread safety.
- Android native: Kotlin, JVM 17, coroutines for async channel calls.
