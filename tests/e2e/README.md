# Quickstart E2E

Maestro flows that drive the Quickstart sample through real authentication against a real
ThunderID server on an iOS Simulator. The flows live in [`flows/`](./flows); the
scripts alongside them get a server into the right state to run against.

## Running locally

```bash
# Everything: start a server, provision it, build and install the sample, run the flows
./run-e2e.sh

# Iterate faster once the server is up and the sample is installed
./run-e2e.sh --skip-server --skip-build

# Run a single flow
./run-e2e.sh flows/signin.yaml
```

Every stage is idempotent. A server that is already serving on `:8090` is reused rather than
restarted, and provisioning re-applies cleanly over an existing application and user.

## What gets provisioned

| Resource | Value |
|---|---|
| Application | `019e5b10-1001-7a2b-9c3d-4e5f60718293` (`Mobile Quickstart E2E App`) |
| Test user | `e2e_mobile_user` / `TestPassword@123` |

The application is declared in
[`samples/quickstart/thunderid-config/thunderid-config.yaml`](../../samples/quickstart/thunderid-config/thunderid-config.yaml),
alongside the sample it configures. The sign-up flow
registers an additional throwaway user per run, named `e2e_signup_<timestamp>`.

## Things worth knowing

**The application must be `type: mobile` with `attestation.devMode: true`.** A mobile application
normally has to prove its binary identity through platform attestation before it can initiate a
flow directly, and `/flow/execute` rejects it with `FES-1016` otherwise. Apple App Attest does not
exist in the Simulator, so the check can never be satisfied on the device these flows run on.
`devMode` is test-only and must never be enabled on a real tenant.

**`POST /import` silently drops the `attestation` block.** It reports the import as successful and
then stores `attestation: null`, which is why `run-e2e.sh` re-applies it over
`PUT /applications/{id}`. Once the import path preserves it, that step can be removed.

**Sign-up does not sign the user in.** The registration flow completes without issuing an
assertion, so the app returns to the landing screen with the account created but no session. The
sign-up flow therefore signs in afterwards with the credentials it just registered, which is also
what proves the new account actually works.

**Tokens survive `clearState`.** They are stored in the Keychain, which lives outside the app
container and outlives both a state reset and a reinstall. A previous run can leave the app
signed in, so every flow starts with the `ensure-signed-out` subflow rather than assuming a clean
device.

**These flows run on iOS, not Android.** The sample's iOS target carries an
`NSAllowsArbitraryLoads` exemption so it accepts the server's self-signed localhost certificate.
Its Android target has no equivalent, and the Flutter SDK exposes no `allowInsecureConnections`
option of its own (the native Android SDK has one, but the plugin never forwards it), so the
Android side cannot currently reach a self-signed local server at all. Running these flows on
Android needs that gap closed first.

**Identifiers reach the accessibility tree through `Semantics`, not `Key`.** A Flutter widget key
is internal to the framework tree and invisible to anything driving the app from outside, so the
SDK sets `Semantics.identifier` alongside the key. It resolves the field's server-side
`identifier` rather than its `ref`, which is what keeps one set of selectors working across iOS,
Android and Flutter.

**`npx thunderid` cannot be used in CI.** It renders an interactive TUI and aborts with
`bubbletea: could not open TTY` whenever stdout is not a terminal. `run-e2e.sh` downloads the
release directly and calls the distribution's own `setup.sh` and `start.sh`, which take the same
arguments non-interactively.
