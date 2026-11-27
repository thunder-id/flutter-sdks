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

## Management capabilities

`ThunderIDProvider.of(context).capabilities` reports which management actions the signed-in user's
access token allows, read once from `GET /capabilities` and shared by every widget under the provider.
`CapabilityGuard` and the admin widgets use it to offer only those actions. It decides what is
offered, not what is allowed: it is not an authorization decision, the server authorizes every
management request, and the SDK never blocks a request because of it.

```dart
CapabilityGuard(resource: 'user', action: 'create', child: MyInviteButton())
```

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
