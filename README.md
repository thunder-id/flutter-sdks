![ThunderID Flutter SDK](https://raw.githubusercontent.com/thunder-id/thunderid/refs/heads/main/docs/static/assets/images/readme/repo-banner-flutter-sdk.png)

Flutter SDK for ThunderID. Provides authentication and user management for cross-platform iOS and Android applications.

## Installation

### pub.dev

```yaml
# pubspec.yaml
dependencies:
  thunder_flutter: ^0.1.0
```

```bash
flutter pub get
```

Make sure your native platforms include the ThunderID SDKs:

**iOS** — add to your `Package.swift` or via Xcode's Swift Package Manager:

```swift
.package(url: "https://github.com/thunder-id/thunderid-swift", from: "0.1.0")
```

**Android** — add to your `settings.gradle.kts`:

```kotlin
dependencyResolutionManagement {
    repositories {
        maven("https://maven.thunderid.dev/releases")
    }
}
```

And in `build.gradle.kts`:

```kotlin
dependencies {
    implementation("dev.thunderid:android:0.1.0")
}
```

## License

This project is licensed under the [Apache License 2.0](https://github.com/thunder-id/thunderid/blob/main/LICENSE)
