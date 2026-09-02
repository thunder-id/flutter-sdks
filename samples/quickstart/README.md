# ThunderID Flutter Quickstart

ThunderID Flutter Quickstart demonstrates the full authentication lifecycle using the `thunderid_flutter` SDK on iOS and Android.

**Flow demonstrated:**
1. App opens → unauthenticated state (sign-in screen)
2. User initiates sign-in / sign-up → SDK starts app-native Flow Execution
3. User completes the flow
4. Sign-in → authenticated state with profile information, token debugging, and sign-out button.
   Sign-up creates the account but does not start a session, so it returns to the landing screen
   and the new credentials have to be used to sign in.
5. User taps Sign Out → session terminated, returns to sign-in screen

## Setup & Run

See [Try the Flutter Sample App](https://thunderid.dev/docs/v1.0.x/sdks/flutter/guides/try-the-sample-app)
in the Flutter SDK docs for prerequisites, configuration, attestation, passkeys, and run instructions.
