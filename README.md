![ThunderID Flutter SDK](https://raw.githubusercontent.com/thunder-id/thunderid/refs/heads/main/docs/static/assets/images/readme/repo-banner-flutter-sdk.png)

Flutter SDK for ThunderID. Provides authentication and user management for cross-platform iOS and Android applications.

- [Quickstart](https://thunderid.dev/docs/next/getting-started/connect-your-application/flutter/)
- [Quickstart sample](https://github.com/thunder-id/samples/tree/main/quickstarts/flutter)
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

## Sign-in through a backend

Setting `endpoints.backend` hands sign-in to a backend the app owns (the Backend for Frontend pattern of RFC 10017). The backend runs the OAuth flow and keeps the tokens, and the app's API calls go through its proxy.

```dart
ThunderIDConfig(
  baseUrl: 'https://app.example.com', // the backend
  afterSignInUrl: 'com.example.app://callback',
  endpoints: EndpointsConfig(
    backend: BackendEndpoints(proxy: '/api'),
  ),
)
```

- `baseUrl` is the backend, and must use HTTPS.
- Each endpoint (`signIn`, `session`, `checkSession`, `refresh`, `signOut`, `proxy`, `token`) is a path that resolves against `baseUrl`, and defaults to one under `/api/auth`. An absolute HTTPS URL is used as it is; `http://` is refused.
- `proxy` is the app's API base. A path the app sends with `httpRequest`, and every management operation, goes to `baseUrl` + `proxy` + the path, with no access token: the backend attaches it and decides which API the request reaches.

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
