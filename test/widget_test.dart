/*
 * Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:thunderid_flutter/src/thunderid_client.dart';
import 'package:thunderid_flutter/src/models/thunderid_config.dart';
import 'package:thunderid_flutter/src/models/user.dart';
import 'package:thunderid_flutter/src/models/organization.dart';
import 'package:thunderid_flutter/src/widgets/thunderid_provider.dart';
import 'package:thunderid_flutter/src/widgets/thunderid_signed_in.dart';
import 'package:thunderid_flutter/src/widgets/thunderid_signed_out.dart';
import 'package:thunderid_flutter/src/widgets/thunderid_loading.dart';
import 'package:thunderid_flutter/src/widgets/thunderid_user.dart';
import 'package:thunderid_flutter/src/widgets/thunderid_organization_list.dart';
import 'package:thunderid_flutter/src/widgets/thunderid_organization_switcher.dart';
import 'package:thunderid_flutter/src/widgets/thunderid_language_switcher.dart';

// ── Test helpers ──────────────────────────────────────────────────────────────

const _config = ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'test');

final _mockUser = User(
  sub: 'u1',
  username: 'alice',
  email: 'alice@example.com',
  displayName: 'Alice Doe',
);

final _mockOrgs = [
  Organization(id: 'o1', name: 'Org One', handle: 'org-one'),
  Organization(id: 'o2', name: 'Org Two', handle: 'org-two'),
];

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
      case 'getMyOrganizations':
        return _mockOrgs.map((o) => o.toMap()).toList();
      case 'getCurrentOrganization':
        return _mockOrgs.first.toMap();
      case 'switchOrganization':
        return {'accessToken': 'tok', 'refreshToken': 'ref', 'idToken': 'id', 'expiresIn': 3600};
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

  group('ThunderIDSignedIn', () {
    testWidgets('renders child when signed in', (tester) async {
      await tester.pumpWidget(_providerWidget(
        signedIn: true,
        child: const ThunderIDSignedIn(child: Text('hello', textDirection: TextDirection.ltr)),
      ));
      await tester.pumpAndSettle();
      expect(find.text('hello'), findsOneWidget);
    });

    testWidgets('hides child when signed out', (tester) async {
      await tester.pumpWidget(_providerWidget(
        signedIn: false,
        child: const ThunderIDSignedIn(child: Text('hello', textDirection: TextDirection.ltr)),
      ));
      await tester.pumpAndSettle();
      expect(find.text('hello'), findsNothing);
    });

    testWidgets('shows fallback when signed out', (tester) async {
      await tester.pumpWidget(_providerWidget(
        signedIn: false,
        child: const ThunderIDSignedIn(
          child: Text('hello', textDirection: TextDirection.ltr),
          fallback: Text('sign in please', textDirection: TextDirection.ltr),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('sign in please'), findsOneWidget);
    });
  });

  group('ThunderIDSignedOut', () {
    testWidgets('renders child when signed out', (tester) async {
      await tester.pumpWidget(_providerWidget(
        signedIn: false,
        child: const ThunderIDSignedOut(child: Text('signed out', textDirection: TextDirection.ltr)),
      ));
      await tester.pumpAndSettle();
      expect(find.text('signed out'), findsOneWidget);
    });

    testWidgets('hides child when signed in', (tester) async {
      await tester.pumpWidget(_providerWidget(
        signedIn: true,
        child: const ThunderIDSignedOut(child: Text('signed out', textDirection: TextDirection.ltr)),
      ));
      await tester.pumpAndSettle();
      expect(find.text('signed out'), findsNothing);
    });
  });

  group('ThunderIDLoading', () {
    testWidgets('renders indicator while loading', (tester) async {
      // Loading state only exists transiently during init; pump once to catch it.
      await tester.pumpWidget(_providerWidget(
        signedIn: false,
        child: ThunderIDLoading(
          indicator: const Text('loading...', textDirection: TextDirection.ltr),
        ),
      ));
      // First pump shows loading state before async init completes.
      expect(find.text('loading...'), findsOneWidget);
      await tester.pumpAndSettle();
      // After init, loading is done.
      expect(find.text('loading...'), findsNothing);
    });
  });

  group('ThunderIDUser', () {
    testWidgets('BaseThunderIDUser receives signed-in user', (tester) async {
      String? displayedName;
      await tester.pumpWidget(_providerWidget(
        signedIn: true,
        child: BaseThunderIDUser(
          builder: (_, user) {
            displayedName = user?.displayName;
            return const SizedBox();
          },
        ),
      ));
      await tester.pumpAndSettle();
      expect(displayedName, 'Alice Doe');
    });

    testWidgets('BaseThunderIDUser receives null when signed out', (tester) async {
      User? capturedUser = User(sub: 'placeholder', username: 'x');
      await tester.pumpWidget(_providerWidget(
        signedIn: false,
        child: BaseThunderIDUser(
          builder: (_, user) {
            capturedUser = user;
            return const SizedBox();
          },
        ),
      ));
      await tester.pumpAndSettle();
      expect(capturedUser, isNull);
    });
  });

  group('ThunderIDOrganizationList', () {
    testWidgets('BaseThunderIDOrganizationList fetches and exposes org list', (tester) async {
      List<Organization>? captured;
      await tester.pumpWidget(_providerWidget(
        signedIn: true,
        child: BaseThunderIDOrganizationList(
          builder: (_, orgs, isLoading, error) {
            if (!isLoading) captured = orgs;
            return const SizedBox();
          },
        ),
      ));
      await tester.pumpAndSettle();
      expect(captured, isNotNull);
      expect(captured!.length, 2);
      expect(captured!.first.name, 'Org One');
    });
  });

  group('ThunderIDOrganizationSwitcher', () {
    testWidgets('BaseThunderIDOrganizationSwitcher calls switchOrganization on select', (tester) async {
      Organization? switched;
      await tester.pumpWidget(_providerWidget(
        signedIn: true,
        child: BaseThunderIDOrganizationSwitcher(
          builder: (_, orgs, current, isSwitching, error, switchOrg) {
            if (orgs.isEmpty || isSwitching) return const SizedBox();
            return GestureDetector(
              onTap: () async {
                await switchOrg(orgs.last);
                switched = orgs.last;
              },
              child: const Text('switch', textDirection: TextDirection.ltr),
            );
          },
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('switch'));
      await tester.pumpAndSettle();
      expect(switched?.name, 'Org Two');
    });
  });

  group('ThunderIDLanguageSwitcher', () {
    testWidgets('BaseThunderIDLanguageSwitcher exposes active locale and select callback', (tester) async {
      String? activeBefore;
      String? activeAfter;
      await tester.pumpWidget(_providerWidget(
        signedIn: false,
        child: BaseThunderIDLanguageSwitcher(
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
      ));
      await tester.pumpAndSettle();
      expect(activeBefore, 'en-US');
      await tester.tap(find.text('fr'));
      await tester.pumpAndSettle();
      expect(activeAfter, 'fr-FR');
    });
  });
}
