![ThunderID Flutter SDK](https://raw.githubusercontent.com/thunder-id/thunderid/refs/heads/main/docs/static/assets/images/readme/repo-banner-flutter-sdk.png)

Flutter SDK for ThunderID. Provides authentication and user management for cross-platform iOS and Android applications.

- [Quickstart](https://thunderid.dev/docs/next/getting-started/connect-your-application/flutter/)
- [Quickstart sample](https://github.com/thunder-id/samples/tree/main/quickstarts/quickstart-flutter)
- [API reference](https://thunderid.dev/docs/next/sdks/flutter/overview/)

## Installation

### pub.dev

![pub version](https://img.shields.io/pub/v/thunderid_flutter)

```bash
flutter pub add thunderid_flutter
```

Or add it to your `pubspec.yaml` directly:

```yaml
dependencies:
  thunderid_flutter: ^<latest-version>
```

> [!NOTE]
> Replace `<latest-version>` with the version shown in the badge above, then run `flutter pub get`.

The native iOS and Android ThunderID SDKs are pulled in automatically as transitive dependencies, no extra setup needed.

## App-native sign-in

`SignIn` and `ThunderIDClient.signIn` run the application's flow in the app, through the native ThunderID Android and iOS SDKs. Set both `applicationId` and `clientId`: when a flow completes, the native SDK exchanges its assertion at the token endpoint (`urn:ietf:params:oauth:grant-type:token-exchange`, no scope) for the access token it keeps, and keeps the assertion as the ID token. The application needs that grant type. Sign-in, sign-up and the embedded organization unit switch do not start a flow without a `clientId`. An application without the grant fails with `INVALID_CONFIGURATION`, and the previous session, if any, stays.

## Playground

[`playground/`](playground/README.md) is a Flutter app that runs every SDK capability and widget against
this checkout: capability checks, a component explorer, a session inspector, and an SDK event log.

```bash
cd playground
cp .env.example .env   # point it at your ThunderID server
flutter pub get
flutter run
```

## Contributing

Please refer to the [Contributing Guide](https://thunderid.dev/community/overview) for the different ways to contribute to this project and the relevant guidelines.

For code contributions, refer to the [Contributing Code](https://thunderid.dev/community/contributing/contributing-code/prerequisites) section for details on the prerequisites and instructions for running ThunderID in development mode.

## License

This project is licensed under the [Apache License 2.0](https://github.com/thunder-id/thunderid/blob/main/LICENSE)
