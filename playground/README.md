# ThunderID Flutter Playground

A development app for exercising every `thunderid_flutter` capability against the SDK source in this
repository. It depends on the plugin with `path: ..`, so changes to `lib/`, `android/` or `ios/` at the
repository root show up the next time you run it.

Looking for a minimal integration example instead? See the
[Flutter quickstart](https://github.com/thunder-id/samples/tree/main/quickstarts/flutter) in the samples
repository.

## What's inside

| Tab | What it does |
|---|---|
| **Checks** | Runs capability checks through the real SDK (system browser sign-in URL, app-native flow, passkey bridge, sign out, redirect callback, token refresh, secure storage, user info, theming, attribute verification, translations) and the management layer (management endpoints, forbidden vs not found errors, permission checks, groups, group members, roles and the shared state layer, role assignments, the signed-in user's groups and usages, user types, agent types, agent groups, agent roles, applications, administration flows, organization units, resource servers, connections and flows, design, translations and notification templates, server configuration, variables, secrets, gateways and configuration versions). Run one or run all, with pass/fail and the reason, a summary ring, and the server's health. Capabilities the SDK has no API for (biometric unlock, organizations) are listed as unavailable. |
| **Components** | Storybook-style explorer for the SDK widgets (`SignInButton`, `SignOutButton`, `SignUpButton`, `SignIn`, `SignUp`, `UserAvatar`, `UserObject`, `UserDropdown`, `UserProfile`, `VerifyAttribute`, `ChangeCredential`, `LanguageSwitcher`, `ThunderIDLogo`, `SignedIn` / `SignedOut` / `Loading`) and the admin widgets (`UserList`, `UserCreate`, `UserDetails`, `GroupList`, `GroupCreate`, `GroupMembers`, `RoleList`, `RoleCreate`, `RolePermissions`, `RoleAssignments`, `AgentList`, `AgentCreate`, `AgentDetails`, `ApplicationList`, `ApplicationCreate`, `ApplicationDetails`). Pick a story, edit props in Controls, copy the generated Flutter snippet from Code, and watch callbacks in Actions. Toggle the preview between light and dark. |
| **Session** | Signed-in user, access token countdown, refresh and sign out, the access token (reveal or copy), decoded claims, granted permissions, and recent events. When signed out, it opens the SDK's `SignIn` and `SignUp` widgets. |
| **Logs** | Every SDK call the playground makes and every session change it observes, filterable by outcome. |

### Management checks

The management checks call the management API with the signed-in user's access token, so sign in
first. They only read: listing, then reading the first record they find (the first group for its
members, the first role for its assignments, the first agent for its groups and roles, the first
user type and agent type for their attribute schema, the first application for its OAuth client). A check
with nothing to read says which Admin story creates the record. HTTP 403 means the token lacks the
permission: request it with `THUNDERID_SCOPES`.

Two checks need no session or server:

- **Management endpoints** prints where each management collection resolves.
  It sends every list call through a per-call fetcher that records the URL and answers with an
  empty page, so the URLs are exactly the ones the SDK would call, overrides included, and an
  override the SDK rejects (plain HTTP to a non-loopback host) fails with the SDK's reason.
- **Forbidden vs not found** feeds a `ThunderIDManagementClient` 403 and 404 answers and confirms
  they map to `forbidden` and `notFound`, and that `toManagementErrorMessage()` shows translated
  text, never the server's. It also confirms that a body in the server's error envelope
  (`{code, message, description}`) is kept as `IAMApiException.serverError`, with the server's code.

**Administration flows** lists which operations the server runs through an administration flow
(`resolveAdministrationFlows()` over every `AdministrationFlowConfigKey`), which is what
`administrationMode: AdministrationMode.flow` uses for deletes, member and assignment removal,
permission removal and client secret regeneration. It only reads, and needs a token that may read
server configuration and flows. Nothing in the playground deletes or regenerates a secret through
a check.

### Admin stories

Each admin widget has a **Connected** story (the real widget, talking to the management API) and a
**Base** story (the presentational `Base*` variant fed sample records, so it renders without a
server). Base stories cover the loading, empty and forbidden states; the forbidden message comes
from `toManagementErrorMessage()`. Detail stories (`UserDetails`, `GroupMembers`,
`RolePermissions`, `RoleAssignments`, `AgentDetails`, `ApplicationDetails`) take an id control; leave it empty and they
use the row you last selected in the matching Connected list story. Create stories use the
`ouId` control, which defaults to `THUNDERID_OU_ID` and then to the signed-in user's `ouId`
claim.

### Custom rendering

Every admin widget, `Base*` and connected, takes an optional `builder`, the same pattern as `BaseSignIn`, and renders
it in place of its own UI. The builder gets the widget's state: `AdminListState` (rows, paging and selection),
`NamedResourceFormState` and the other form states (values, setters and `submit`), or the details states (the record
and its actions). The **Custom rendering** stories draw `UserList` as a Material `DataTable` with a pager,
`GroupCreate` as Material text fields and `UserDetails` as a Material card.

`VerifyAttribute` and `BaseVerifyAttribute` take the same `builder`. Their `VerifyAttributeState` carries the step's
`inputNames`, `values` and `onValueChanged`, `submit` with `submitActionId`, `resend` with `resendActionId`, `done` for
a link, `onCancel`, where the code went, loading, the translated error and `successMessage`. The story draws a
verification as a Material card.

### Granted permissions

The Session tab's **Access** segment lists the permissions the access token carries, read by
`ThunderIDProvider.of(context).grantedPermissions()` (a `GrantedPermissionsNotifier`), and tests a
permission you type with `can()`, highlighting the granted permissions that cover it
(`system` covers `system:user:view`). The result is decoded, not verified; the server still
decides every request.

## Prerequisites

- Flutter 3.24 or later
- Android Studio with an emulator (API 26+), or Xcode with an iOS 16+ simulator
- A running ThunderID server. See [Get started](https://thunderid.dev/docs/next/getting-started/) to
  download and start one; by default it listens on `https://localhost:8090`.

## Set up ThunderID

1. Sign in to the ThunderID Console and create a **Mobile** application.
2. Copy its application ID.
3. Simulators and emulators cannot pass platform attestation (Apple App Attest or Play Integrity), so
   enable attestation **dev mode** on the application while you test locally. Never enable it on a real
   tenant.
4. Optional: to run the system browser and redirect callback checks, give the application an OAuth
   client ID and register the redirect URI from `.env` (`dev.thunderid.playground://callback` by
   default). These checks build the authorize URL and confirm forged callbacks are rejected; the app
   does not register the URL scheme, so it does not complete a full browser round trip.

## Configure

```bash
cp .env.example .env
```

| Variable | Description |
|---|---|
| `THUNDERID_BASE_URL` | ThunderID server URL. Use `https://localhost:8090` for the iOS simulator and `https://10.0.2.2:8090` for the Android emulator. |
| `THUNDERID_APP_ID` | Application ID for app-native sign-in and sign-up. |
| `THUNDERID_CLIENT_ID` | Optional OAuth client ID for redirect-based sign-in. |
| `THUNDERID_AFTER_SIGN_IN_URL` / `THUNDERID_AFTER_SIGN_OUT_URL` | Redirect URIs used with `THUNDERID_CLIENT_ID`. |
| `THUNDERID_ATTESTATION_ENABLED` | `true` to send an attestation token. Keep `false` on simulators and emulators. |
| `THUNDERID_CLOUD_PROJECT_NUMBER` | Google Cloud project number, required by Play Integrity when attestation is on. |
| `THUNDERID_SCOPES` | Scopes requested at sign-in, space separated. Defaults to `openid profile email`. Add the server's admin permissions (e.g. `system`) to exercise the management checks and Connected admin stories. |
| `THUNDERID_OU_ID` | Organization unit the Admin create stories use. Defaults to the signed-in user's `ouId` claim. |
| `THUNDERID_ENDPOINT_USERS`, `_USER_TYPES`, `_GROUPS`, `_ROLES`, `_AGENTS`, `_AGENT_TYPES`, `_APPLICATIONS`, `_ORGANIZATION_UNITS`, `_RESOURCE_SERVERS`, `_CONNECTIONS`, `_FLOWS`, `_NOTIFICATION_TEMPLATES`, `_DESIGN`, `_I18N`, `_SERVER_CONFIG`, `_GATEWAYS`, `_VARIABLES`, `_SECRETS`, `_CONFIGURATION_VERSIONS`, `_IMPORT`, `_EXPORT` | Optional per-collection URL. |

Unset, each collection resolves to the SDK default `<THUNDERID_BASE_URL>/<collection>`.
`THUNDERID_ENDPOINT_APPLICATIONS` applies to the application operations (list, get, create, update,
delete and secret regeneration). The CIMD preview (`previewCimdDocument`) and the administration flows
are server endpoints rather than collections, so they always go to `THUNDERID_BASE_URL`, whatever the
overrides.

### Management endpoints

Sign-in, tokens and flows always go to `THUNDERID_BASE_URL` through the native SDK. Management calls
resolve each collection from `ThunderIDConfig.endpoints`, then fall back to `THUNDERID_BASE_URL` plus
the collection path. The playground builds `endpoints` from the variables above, for example:

```bash
THUNDERID_BASE_URL=https://localhost:8090
THUNDERID_ENDPOINT_ROLES=https://localhost:9091/roles
```

Run the **Management endpoints** check to see where every collection resolves.
Each URL must be HTTPS; plain HTTP is accepted for a loopback address only. `endpoints` is consumed
by the Dart management layer and is not forwarded to the native SDKs.

`.env` is gitignored. Debug builds accept the local server's self-signed certificate (Android through
`allowInsecureConnections`, iOS through an App Transport Security exemption); release builds do not.

## Run

```bash
cd playground
flutter pub get
flutter run
```

Without a reachable server, checks that need one fail with the reason, and the health indicator on the
Checks tab reports the server as unreachable.

## Develop

```bash
flutter analyze
flutter test
flutter build apk --debug
```

`flutter test` renders every Admin story against a fake management server and checks the
`.env` endpoint parsing and the endpoint resolver.

The repository's PR builder runs the same commands, so keep the playground building when you change
the SDK's public API.

## Known SDK gaps

Found while adding the management features to the playground. They are worked around here, not
fixed in the SDK.

- **No public endpoint resolver.** The URL a management call uses is built by package-internal
  code, and the collection paths (`user-types`, `agent-types`, ...) are private. The endpoints
  check recovers the URLs by sending each call through a recording fetcher.
- **`GrantedPermissionsNotifier` does not follow the session.** It takes a `signedIn` snapshot and
  reads the token once; after sign-in, sign-out or a token refresh the caller has to create a new
  one or call `reload()`. The Session tab recreates it when the user changes.
- **No organization-unit API.** The create components need an `ouId`, which comes from the widget
  or the token's `ouId` claim; there is no way to list or pick organization units.
- **No resource-server lookup.** `RolePermissions` shows resource server ids unless the app passes
  `resourceServerNames` itself.
- **`getAgentRoles()` returns role names only,** not ids, so a role reached from an agent cannot be
  opened with `getRole()` or `RoleAssignments`.
