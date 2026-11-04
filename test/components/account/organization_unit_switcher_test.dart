// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

const _channel = MethodChannel('dev.thunderid/sdk');

Map<String, Object> _page(int offset) => {
      'current': 'ou-1',
      'totalResults': 3,
      'startIndex': offset + 1,
      'count': offset == 0 ? 2 : 1,
      'organizationUnits': offset == 0
          ? [
              {'id': 'ou-1', 'handle': 'east', 'name': 'East'},
              {'id': 'ou-2', 'handle': 'west', 'name': 'West'},
            ]
          : [
              {'id': 'ou-3', 'handle': 'north', 'name': 'North'},
            ],
      'links': <Object>[],
    };

void main() {
  final calls = <MethodCall>[];
  final requests = <ManagementRequest>[];
  late String callbackUrl;
  late int listStatus;

  setUp(() {
    calls.clear();
    requests.clear();
    callbackUrl = 'com.example.app://callback?code=abc';
    listStatus = 200;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
        case 'isSignedIn':
          return true;
        case 'getAccessToken':
          return 'token';
        case 'getUser':
        case 'handleRedirectCallback':
          return {'sub': 'u-1', 'ouId': 'ou-1'};
        case 'buildSignInUrl':
          return 'https://auth.example.com/ou/ou-2/oauth2/authorize';
        case 'openAuthSession':
          return callbackUrl;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
  });

  Widget wrap(Widget child) => MaterialApp(
        home: ThunderIDProvider(
          config: ThunderIDConfig(
            baseUrl: 'https://auth.example.com',
            clientId: 'app',
            fetchUserProfile: false,
            http: ThunderIDHttpConfig(
              fetcher: (request) async {
                requests.add(request);
                final offset = int.tryParse(request.url.queryParameters['offset'] ?? '') ?? 0;
                return listStatus == 200
                    ? ManagementResponse(statusCode: 200, body: jsonEncode(_page(offset)))
                    : ManagementResponse(statusCode: listStatus, body: '{"code":"USR-1"}');
              },
            ),
          ),
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );

  testWidgets('lists the accessible units and marks the current one', (tester) async {
    await tester.pumpWidget(wrap(const OrganizationUnitSwitcher(limit: 2, scope: AccessibleOrganizationUnitScope.siblings)));
    await tester.pumpAndSettle();

    expect(requests.first.url.queryParameters, {'scope': 'siblings', 'limit': '2', 'offset': '0'});
    expect(find.text('Switch Organization'), findsOneWidget);
    expect(find.text('East'), findsOneWidget);
    expect(find.text('West'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
    expect(find.byKey(const Key('thunderid-ou-switch-ou-1')), findsNothing);
    expect(find.byKey(const Key('thunderid-ou-switch-ou-2')), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(requests.last.url.queryParameters['offset'], '2');
    expect(find.text('North'), findsOneWidget);
  });

  testWidgets('switching signs in again bounded to the unit and reports the new user', (tester) async {
    User? switched;
    await tester.pumpWidget(wrap(OrganizationUnitSwitcher(onSwitched: (user) => switched = user)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('thunderid-ou-switch-ou-2')));
    await tester.pumpAndSettle();

    final buildUrl = calls.firstWhere((c) => c.method == 'buildSignInUrl');
    expect(((buildUrl.arguments as Map)['options'] as Map)['organizationUnitId'], 'ou-2');
    expect(calls.map((c) => c.method), contains('handleRedirectCallback'));
    expect(switched?.sub, 'u-1');
  });

  testWidgets('a refused switch shows a translated message and keeps the session', (tester) async {
    callbackUrl = 'com.example.app://callback?error=unauthorized_client';
    Object? reported;
    await tester.pumpWidget(wrap(OrganizationUnitSwitcher(onError: (e) => reported = e)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('thunderid-ou-switch-ou-2')));
    await tester.pumpAndSettle();

    expect(find.text('This organization unit is not available to this application.'), findsOneWidget);
    expect(calls.map((c) => c.method), isNot(contains('handleRedirectCallback')));
    expect((reported as IAMException?)?.code, ThunderIDErrorCode.organizationUnitUnavailable);
  });

  testWidgets('a failed load shows a translated message, not the server text', (tester) async {
    listStatus = 403;
    await tester.pumpWidget(wrap(const OrganizationUnitSwitcher()));
    await tester.pumpAndSettle();
    expect(find.text('Could not load your organization units. Please try again.'), findsOneWidget);
    expect(find.textContaining('USR-1'), findsNothing);
  });

  testWidgets('onSelect lets the app take the switch over', (tester) async {
    AccessibleOrganizationUnit? selected;
    await tester.pumpWidget(wrap(OrganizationUnitSwitcher(onSelect: (unit) => selected = unit)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('thunderid-ou-switch-ou-2')));
    await tester.pumpAndSettle();
    expect(selected?.id, 'ou-2');
    expect(calls.map((c) => c.method), isNot(contains('buildSignInUrl')));
  });

  testWidgets('a custom render gets the units, current, paging and onSwitch', (tester) async {
    OrganizationUnitSwitcherState? seen;
    await tester.pumpWidget(
      wrap(
        OrganizationUnitSwitcher(
          limit: 2,
          onSelect: (_) {},
          builder: (context, state) {
            seen = state;
            return Column(
              children: [
                for (final unit in state.units)
                  TextButton(
                    onPressed: () => state.onSwitch?.call(unit),
                    child: Text('${unit.handle}${unit.id == state.currentId ? ' *' : ''}'),
                  ),
              ],
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('east *'), findsOneWidget);
    expect(find.text('west'), findsOneWidget);
    expect(seen?.totalResults, 3);
    expect(seen?.limit, 2);
    expect(seen?.offset, 0);
    expect(seen?.isLoading, isFalse);
    seen?.onPageChange?.call(2);
    await tester.pumpAndSettle();
    expect(find.text('north'), findsOneWidget);
  });

  testWidgets('the base variant draws the units it is given with no SDK state', (tester) async {
    final switched = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BaseOrganizationUnitSwitcher(
            units: const [
              AccessibleOrganizationUnit(id: 'a', handle: 'alpha', name: 'Alpha'),
              AccessibleOrganizationUnit(id: 'b', handle: 'beta', name: 'Beta'),
            ],
            currentId: 'a',
            onSwitch: (unit) => switched.add(unit.id),
          ),
        ),
      ),
    );
    expect(find.text('Current'), findsOneWidget);
    await tester.tap(find.text('Switch'));
    expect(switched, ['b']);
  });

  testWidgets('the base variant disables switching while one runs and shows errors as given', (tester) async {
    OrganizationUnitSwitcherState? seen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BaseOrganizationUnitSwitcher(
            units: const [AccessibleOrganizationUnit(id: 'b', handle: 'beta', name: 'Beta')],
            switchingId: 'b',
            error: 'Translated',
            onSwitch: (_) {},
            builder: (context, state) {
              seen = state;
              return Text(state.error ?? '');
            },
          ),
        ),
      ),
    );
    expect(find.text('Translated'), findsOneWidget);
    expect(seen?.onSwitch, isNull);
    expect(seen?.switchingId, 'b');
  });

  testWidgets('an empty list says so', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: BaseOrganizationUnitSwitcher(units: []))));
    expect(find.text('No organizations found.'), findsOneWidget);
  });
}
