// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/components/account/user_object.dart';
import 'package:thunderid_flutter/src/components/auth/guards/loading.dart';
import 'package:thunderid_flutter/src/components/auth/guards/signed_in.dart';
import 'package:thunderid_flutter/src/components/auth/guards/signed_out.dart';
import 'package:thunderid_flutter/src/components/common/language_switcher.dart';
import 'package:thunderid_flutter/src/components/thunderid_provider.dart';
import 'package:thunderid_flutter/src/models/thunderid_config.dart';
import 'package:thunderid_flutter/src/models/user.dart';
import 'package:thunderid_flutter/src/thunderid_client.dart';

// ── Test helpers ──────────────────────────────────────────────────────────────

const _config = ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'test');

const _mockUser = User({
  'sub': 'u1',
  'username': 'alice',
  'email': 'alice@example.com',
  'displayName': 'Alice Doe',
});

/// Sets up a mock MethodChannel for dev.thunderid/sdk.
void _setHandler(MethodChannel channel, Future<dynamic> Function(MethodCall) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, handler);
}

void _clearHandler(MethodChannel channel) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null);
}

const _sdkChannel = MethodChannel('dev.thunderid/sdk');

/// Builds a [ThunderIDProvider] with a pre-configured [ThunderIDClient] under test.
Widget _providerWidget({
  required Widget child,
  bool signedIn = false,
}) {
  _setHandler(_sdkChannel, (call) async {
    switch (call.method) {
      case 'initialize':
        return true;
      case 'isSignedIn':
        return signedIn;
      case 'getUser':
        return signedIn ? _mockUser.toMap() : null;
      default:
        return null;
    }
  });

  return WidgetsApp(
    color: const Color(0xFFFFFFFF),
    builder: (_, __) => ThunderIDProvider(
      config: _config,
      child: child,
    ),
  );
}

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => _clearHandler(_sdkChannel));

  group('SignedIn', () {
    testWidgets('renders child when signed in', (tester) async {
      await tester.pumpWidget(_providerWidget(
        signedIn: true,
        child: const SignedIn(child: Text('hello', textDirection: TextDirection.ltr)),
      ),);
      await tester.pumpAndSettle();
      expect(find.text('hello'), findsOneWidget);
    });

    testWidgets('hides child when signed out', (tester) async {
      await tester.pumpWidget(_providerWidget(
        signedIn: false,
        child: const SignedIn(child: Text('hello', textDirection: TextDirection.ltr)),
      ),);
      await tester.pumpAndSettle();
      expect(find.text('hello'), findsNothing);
    });

    testWidgets('shows fallback when signed out', (tester) async {
      await tester.pumpWidget(_providerWidget(
        signedIn: false,
        child: const SignedIn(
          fallback: Text('sign in please', textDirection: TextDirection.ltr),
          child: Text('hello', textDirection: TextDirection.ltr),
        ),
      ),);
      await tester.pumpAndSettle();
      expect(find.text('sign in please'), findsOneWidget);
    });
  });

  group('SignedOut', () {
    testWidgets('renders child when signed out', (tester) async {
      await tester.pumpWidget(_providerWidget(
        signedIn: false,
        child: const SignedOut(child: Text('signed out', textDirection: TextDirection.ltr)),
      ),);
      await tester.pumpAndSettle();
      expect(find.text('signed out'), findsOneWidget);
    });

    testWidgets('hides child when signed in', (tester) async {
      await tester.pumpWidget(_providerWidget(
        signedIn: true,
        child: const SignedOut(child: Text('signed out', textDirection: TextDirection.ltr)),
      ),);
      await tester.pumpAndSettle();
      expect(find.text('signed out'), findsNothing);
    });
  });

  group('Loading', () {
    testWidgets('renders indicator while loading', (tester) async {
      // Loading state only exists transiently during init; pump once to catch it.
      await tester.pumpWidget(_providerWidget(
        signedIn: false,
        child: const Loading(
          indicator: Text('loading...', textDirection: TextDirection.ltr),
        ),
      ),);
      // First pump shows loading state before async init completes.
      expect(find.text('loading...'), findsOneWidget);
      await tester.pumpAndSettle();
      // After init, loading is done.
      expect(find.text('loading...'), findsNothing);
    });
  });

  group('UserObject', () {
    testWidgets('BaseUserObject receives signed-in user', (tester) async {
      String? displayedName;
      await tester.pumpWidget(_providerWidget(
        signedIn: true,
        child: BaseUserObject(
          builder: (_, user) {
            displayedName = user?.displayName;
            return const SizedBox();
          },
        ),
      ),);
      await tester.pumpAndSettle();
      expect(displayedName, 'Alice Doe');
    });

    testWidgets('BaseUserObject receives null when signed out', (tester) async {
      User? capturedUser = const User({'sub': 'placeholder', 'username': 'x'});
      await tester.pumpWidget(_providerWidget(
        signedIn: false,
        child: BaseUserObject(
          builder: (_, user) {
            capturedUser = user;
            return const SizedBox();
          },
        ),
      ),);
      await tester.pumpAndSettle();
      expect(capturedUser, isNull);
    });
  });

  group('LanguageSwitcher', () {
    testWidgets('BaseLanguageSwitcher exposes active locale and select callback', (tester) async {
      String? activeBefore;
      String? activeAfter;
      await tester.pumpWidget(_providerWidget(
        signedIn: false,
        child: BaseLanguageSwitcher(
          locales: const ['en-US', 'fr-FR'],
          builder: (_, active, select) {
            activeBefore ??= active;
            return GestureDetector(
              onTap: () {
                select('fr-FR');
                activeAfter = 'fr-FR';
              },
              child: const Text('fr', textDirection: TextDirection.ltr),
            );
          },
        ),
      ),);
      await tester.pumpAndSettle();
      expect(activeBefore, 'en-US');
      await tester.tap(find.text('fr'));
      await tester.pumpAndSettle();
      expect(activeAfter, 'fr-FR');
    });
  });
}
