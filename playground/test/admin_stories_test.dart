// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';
import 'package:thunderid_flutter_playground/src/config.dart';
import 'package:thunderid_flutter_playground/src/management_endpoints.dart';
import 'package:thunderid_flutter_playground/src/stories.dart';

/// Answers every management request with an empty page, so Connected stories render offline.
Future<ManagementResponse> _emptyPages(ManagementRequest request) async =>
    const ManagementResponse(statusCode: 200, body: '{"totalResults":0}');

void main() {
  const channel = MethodChannel('dev.thunderid/sdk');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => switch (call.method) {
        'initialize' => true,
        'isSignedIn' => false,
        _ => null,
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('endpoint overrides come from the per-collection .env variables', () {
    final config = PlaygroundConfig.fromEnv({
      'THUNDERID_BASE_URL': 'https://auth.example.com',
      'THUNDERID_ENDPOINT_ROLES': 'https://roles.example.com/v2/roles',
      'THUNDERID_SCOPES': 'openid system',
    });
    expect(config.endpoints.keys, [ManagementEndpointKeys.roles]);
    expect(config.endpoints[ManagementEndpointKeys.roles], 'https://roles.example.com/v2/roles');
    expect(config.scopes, ['openid', 'system']);
    expect(PlaygroundConfig.fromEnv(const {}).endpoints, isEmpty);
  });

  test('resolved endpoints are the URLs the SDK would call, with no network', () async {
    final resolved = await resolveManagementEndpoints(
      ThunderIDManagementClient(
        baseUrl: 'https://auth.example.com/',
        endpoints: const {
          ManagementEndpointKeys.groups: 'https://api.example.com/groups',
          ManagementEndpointKeys.roles: 'http://api.example.com/roles',
        },
      ),
    );
    final byKey = {for (final e in resolved) e.key: e};
    expect(byKey[ManagementEndpointKeys.users]?.url, 'https://auth.example.com/users');
    expect(byKey[ManagementEndpointKeys.agentTypes]?.url, 'https://auth.example.com/agent-types');
    expect(byKey[ManagementEndpointKeys.groups]?.url, 'https://api.example.com/groups');
    // Plain HTTP is refused for a non-loopback host before anything is sent.
    expect(byKey[ManagementEndpointKeys.roles]?.error, startsWith('INVALID_CONFIGURATION'));
  });

  final admin = componentDefs.where((def) => def.category == 'Admin').toList();

  test('every admin widget has a story', () {
    expect(admin.map((def) => def.name), hasLength(13));
  });

  for (final def in admin) {
    for (final story in def.stories) {
      testWidgets('${def.name} / ${story.name} renders and has a snippet', (tester) async {
        final values = {...def.defaults, ...story.preset};
        final storyContext = StoryContext(story: story.id, values: values, emit: (_) {});
        await tester.pumpWidget(
          MaterialApp(
            home: ThunderIDProvider(
              config: const ThunderIDConfig(
                baseUrl: 'https://localhost:8090',
                clientId: 'playground',
                http: ThunderIDHttpConfig(fetcher: _emptyPages),
              ),
              child: Scaffold(
                body: SingleChildScrollView(child: Builder(builder: (context) => def.build(context, storyContext))),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(def.code(storyContext), contains(def.name));
      });
    }
  }

  final custom = componentDefs.where((def) => def.category == 'Custom rendering').toList();

  for (final def in custom) {
    for (final story in def.stories) {
      testWidgets('${def.name} / ${story.name} renders through the builder', (tester) async {
        final actions = <String>[];
        final values = {...def.defaults, ...story.preset};
        final storyContext = StoryContext(story: story.id, values: values, emit: actions.add);
        await tester.pumpWidget(
          MaterialApp(
            home: ThunderIDProvider(
              config: const ThunderIDConfig(
                baseUrl: 'https://localhost:8090',
                clientId: 'playground',
                http: ThunderIDHttpConfig(fetcher: _emptyPages),
              ),
              child: Scaffold(
                body: SingleChildScrollView(child: Builder(builder: (context) => def.build(context, storyContext))),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        if (def.id == 'customUserList' && story.id == 'base') {
          expect(find.text('Ada Lovelace'), findsOneWidget);
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
          expect(find.text('Alan Turing'), findsOneWidget);
          expect(actions, contains('onPageChange 2'));
        }
        if (def.id == 'customGroupCreate' && story.id == 'base') {
          await tester.enterText(find.byKey(const Key('playground-custom-group-name')), 'Engineering');
          await tester.pump();
          await tester.tap(find.text('Create group'));
          expect(actions, contains('onSubmit Engineering'));
        }
        if (def.id == 'customUserDetails' && story.id == 'base') {
          expect(find.text('username: ada'), findsOneWidget);
          expect(find.textContaining('password'), findsNothing);
        }
      });
    }
  }
}
