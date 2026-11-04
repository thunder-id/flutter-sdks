// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

/// A fake management server: answers by `METHOD path` and records every request.
class _FakeServer {
  final Map<String, ManagementResponse> routes = {};
  final List<ManagementRequest> requests = [];

  void on(String method, String path, Object? body, {int status = 200}) {
    routes['$method $path'] = ManagementResponse(
      statusCode: status,
      statusText: status == 200 ? 'OK' : 'Error',
      body: body == null ? '' : jsonEncode(body),
    );
  }

  Future<ManagementResponse> fetch(ManagementRequest request) async {
    requests.add(request);
    return routes['${request.method} ${request.url.path}'] ??
        const ManagementResponse(statusCode: 404, statusText: 'Not Found');
  }

  Iterable<ManagementRequest> where(String method, String path) =>
      requests.where((r) => r.method == method && r.url.path == path);

  Object? lastBody(String method, String path) => jsonDecode(where(method, path).last.body!);
}

Widget _app(_FakeServer server, Widget child) => MaterialApp(
  home: ThunderIDProvider(
    config: ThunderIDConfig(
      baseUrl: 'https://idp.example.com',
      clientId: 'test',
      http: ThunderIDHttpConfig(fetcher: server.fetch),
    ),
    child: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

Finder _key(String key) => find.byKey(Key(key));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

const _policies = {
  'totalResults': 3,
  'policies': [
    {
      'id': 'pol-all',
      'initiatingOuId': 'ou-root',
      'version': 2,
      'childUnits': {
        'mode': 'all',
        'excludedOuIds': ['ou-x'],
      },
    },
    {
      'id': 'pol-chosen',
      'version': 1,
      'childUnits': {
        'mode': 'selected',
        'units': [
          {'ouId': 'ou-a', 'reach': 'subtree'},
          {'ouId': 'ou-b', 'reach': 'unit'},
        ],
      },
    },
    {'id': 'pol-locked', 'stage': 'reshare', 'isReadOnly': true, 'allUnits': <String, Object?>{}},
  ],
};

void main() {
  late _FakeServer server;

  setUp(() {
    server = _FakeServer();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.thunderid/sdk'),
      (call) async => call.method == 'initialize' ? true : (call.method == 'isSignedIn' ? false : null),
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.thunderid/sdk'),
      null,
    );
  });

  testWidgets('describes each policy as the server records it, read only by default', (tester) async {
    server.on('GET', '/applications/app1/sharing-policies', _policies);
    await tester.pumpWidget(
      _app(server, const SharingPolicies(resourceType: SharingResourceType.application, resourceId: 'app1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sharing'), findsWidgets);
    expect(find.text('All units beneath the issuer, except ou-x'), findsOneWidget);
    expect(find.text('Chosen units: ou-a and the units beneath it, ou-b'), findsOneWidget);
    expect(find.text('All organization units'), findsOneWidget);
    expect(find.text('Reshared · Read only'), findsOneWidget);
    expect(find.text('Issued by ou-root'), findsOneWidget);
    expect(_key('thunderid-action-sharing-policies-add'), findsNothing);
    expect(_key('thunderid-action-sharing-policies-edit-pol-all'), findsNothing);
    expect(_key('thunderid-action-sharing-policies-delete-pol-all'), findsNothing);
  });

  testWidgets('reads the policies of each resource type from its own collection', (tester) async {
    for (final (type, path) in [
      (SharingResourceType.user, '/users/r1/sharing-policies'),
      (SharingResourceType.role, '/roles/r1/sharing-policies'),
      (SharingResourceType.flow, '/flows/r1/sharing-policies'),
    ]) {
      server.on('GET', path, {'totalResults': 0, 'policies': <Object?>[]});
      await tester.pumpWidget(_app(server, SharingPolicies(key: ValueKey(type), resourceType: type, resourceId: 'r1')));
      await tester.pumpAndSettle();
      expect(server.where('GET', path), isNotEmpty, reason: type.value);
      expect(find.text('Not shared with other organization units.'), findsOneWidget);
    }
  });

  testWidgets('adds, edits and deletes policies only when editable, deleting after confirmation', (tester) async {
    server
      ..on('GET', '/roles/r1/sharing-policies', _policies)
      ..on('POST', '/roles/r1/sharing-policies', {'id': 'pol-new'})
      ..on('PUT', '/roles/r1/sharing-policies/pol-all', {'id': 'pol-all'})
      ..on('DELETE', '/roles/r1/sharing-policies/pol-chosen', null, status: 204);
    await tester.pumpWidget(
      _app(server, const SharingPolicies(resourceType: SharingResourceType.role, resourceId: 'r1', editable: true)),
    );
    await tester.pumpAndSettle();
    expect(_key('thunderid-action-sharing-policies-edit-pol-locked'), findsNothing, reason: 'read-only policy');

    await _tap(tester, _key('thunderid-action-sharing-policies-add'));
    await _tap(tester, _key('thunderid-field-sharing-policies-mode'));
    await tester.tap(find.text('Chosen units').last);
    await tester.pumpAndSettle();
    await tester.enterText(_key('thunderid-field-sharing-policies-units'), 'ou-a, ou-b');
    await _tap(tester, _key('thunderid-field-sharing-policies-subtree'));
    await _tap(tester, _key('thunderid-action-sharing-policies-save'));
    expect(server.lastBody('POST', '/roles/r1/sharing-policies'), {
      'childUnits': {
        'mode': 'selected',
        'units': [
          {'ouId': 'ou-a', 'reach': 'subtree'},
          {'ouId': 'ou-b', 'reach': 'subtree'},
        ],
      },
    });

    await _tap(tester, _key('thunderid-action-sharing-policies-edit-pol-all'));
    await tester.enterText(_key('thunderid-field-sharing-policies-excluded'), 'ou-x, ou-y');
    await _tap(tester, _key('thunderid-action-sharing-policies-save'));
    expect(server.lastBody('PUT', '/roles/r1/sharing-policies/pol-all'), {
      'version': 2,
      'childUnits': {
        'mode': 'all',
        'excludedOuIds': ['ou-x', 'ou-y'],
      },
    });

    await _tap(tester, _key('thunderid-action-sharing-policies-delete-pol-chosen'));
    expect(server.where('DELETE', '/roles/r1/sharing-policies/pol-chosen'), isEmpty, reason: 'only asks');
    expect(find.text('Delete this sharing policy?'), findsOneWidget);
    await _tap(tester, _key('thunderid-action-sharing-policies-delete-pol-chosen-confirm'));
    expect(server.where('DELETE', '/roles/r1/sharing-policies/pol-chosen'), hasLength(1));
  });

  testWidgets('maps a stale-version refusal to its own message', (tester) async {
    server
      ..on('GET', '/users/u1/sharing-policies', _policies)
      ..on('PUT', '/users/u1/sharing-policies/pol-all', {'code': 'USR-1032', 'message': 'server text'}, status: 409);
    await tester.pumpWidget(
      _app(server, const SharingPolicies(resourceType: SharingResourceType.user, resourceId: 'u1', editable: true)),
    );
    await tester.pumpAndSettle();

    await _tap(tester, _key('thunderid-action-sharing-policies-edit-pol-all'));
    await _tap(tester, _key('thunderid-action-sharing-policies-save'));
    expect(find.text('This policy changed since it was loaded. Reload it and try again.'), findsOneWidget);
    expect(find.textContaining('server text'), findsNothing);
  });

  testWidgets('shows the overlay rules for ouId, read only', (tester) async {
    server
      ..on('GET', '/flows/f1/sharing-policies', {'totalResults': 0, 'policies': <Object?>[]})
      ..on('GET', '/flows/f1/overlay-rules', {
        'ouId': 'ou-a',
        'owned': false,
        'visible': true,
        'rules': {
          'variables.color': {
            'editable': true,
            'allowedValues': ['red', 'blue'],
          },
        },
      });
    await tester.pumpWidget(
      _app(server, const SharingPolicies(resourceType: SharingResourceType.flow, resourceId: 'f1', ouId: 'ou-a')),
    );
    await tester.pumpAndSettle();

    expect(server.where('GET', '/flows/f1/overlay-rules').single.url.queryParameters, {'ouId': 'ou-a'});
    expect(find.text('Seen from ou-a'), findsOneWidget);
    expect(find.text('Shared into this unit'), findsOneWidget);
    expect(find.text('Editable · red, blue'), findsOneWidget);
  });

  testWidgets('a custom builder gets the policies, and the actions only when editable', (tester) async {
    server.on('GET', '/applications/app1/sharing-policies', _policies);
    final states = <SharingPoliciesState>[];
    Widget build({required bool editable}) => _app(
      server,
      SharingPolicies(
        resourceType: SharingResourceType.application,
        resourceId: 'app1',
        editable: editable,
        builder: (context, state) {
          states.add(state);
          return Column(children: [for (final p in state.policies) Text('custom ${state.describe(p)}')]);
        },
      ),
    );
    await tester.pumpWidget(build(editable: false));
    await tester.pumpAndSettle();
    expect(find.text('custom All organization units'), findsOneWidget);
    expect(states.last.totalResults, 3);
    expect(states.last.onCreate, isNull);
    expect(states.last.onUpdate, isNull);
    expect(states.last.onDelete, isNull);

    await tester.pumpWidget(build(editable: true));
    await tester.pumpAndSettle();
    expect(states.last.onCreate, isNotNull);
    expect(states.last.onDelete, isNotNull);
  });

  testWidgets('BaseSharingPolicies works without a provider', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BaseSharingPolicies(
            policies: [SharingPolicy.fromJson((_policies['policies']! as List)[1] as Map<String, dynamic>)],
          ),
        ),
      ),
    );
    expect(find.text('Chosen units: ou-a and the units beneath it, ou-b'), findsOneWidget);
  });
}
