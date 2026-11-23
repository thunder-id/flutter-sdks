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

## Usage telemetry

Set `telemetry` to report how the app is used: screen views, the changes made through the SDK
(creates, updates, deletes and other changes, and their failures), sign-ins and sign-outs, and
links opened outside the app. It is off until `endpoint` is set. The names and path templates the
SDK builds never carry a URL query or a request or response body. Route patterns given to the
navigator observer and values passed to `track` are sent as given (a `track` value that looks
personal is dropped), so pass patterns rather than concrete paths, and never pass user input.

```dart
ThunderIDConfig(
  baseUrl: 'https://auth.example.com',
  clientId: '<client-id>',
  telemetry: TelemetryConfig(
    endpoint: 'https://collector.example.com/v1/logs', // OTLP by default
    prefix: 'acme',
    consent: () => analyticsAllowed,
  ),
);

MaterialApp(navigatorObservers: [TelemetryNavigatorObserver(client)], ...);
client.openExternalLink(Uri.parse('https://example.com/pricing'));
client.track('application.template-pick', {'type': 'spa'});
```

`format: TelemetryFormat.mapping` with a `TelemetryMapping` template reshapes events for an API
that does not take OpenTelemetry.

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
