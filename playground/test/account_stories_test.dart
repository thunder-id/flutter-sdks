// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';
import 'package:thunderid_flutter_playground/src/checks.dart';
import 'package:thunderid_flutter_playground/src/stories.dart';

/// Answers `/users/me/ous` with two units, so the Connected story renders offline.
Future<ManagementResponse> _units(ManagementRequest request) async => const ManagementResponse(
      statusCode: 200,
      body: '{"current":"ou-1","totalResults":2,"startIndex":1,"count":2,"organizationUnits":['
          '{"id":"ou-1","handle":"east","name":"East"},{"id":"ou-2","handle":"west","name":"West"}],"links":[]}',
    );

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

  final def = componentDefs.singleWhere((def) => def.id == 'organizationUnitSwitcher');

  for (final story in def.stories) {
    testWidgets('OrganizationUnitSwitcher / ${story.name} renders and has a snippet', (tester) async {
      final actions = <String>[];
      final storyContext = StoryContext(story: story.id, values: {...def.defaults, ...story.preset}, emit: actions.add);
      await tester.pumpWidget(
        MaterialApp(
          home: ThunderIDProvider(
            config: const ThunderIDConfig(
              baseUrl: 'https://localhost:8090',
              clientId: 'playground',
              http: ThunderIDHttpConfig(fetcher: _units),
            ),
            child: Scaffold(body: Builder(builder: (context) => def.build(context, storyContext))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(def.code(storyContext), contains('OrganizationUnitSwitcher'));
      expect(find.text('Current'), findsOneWidget);
      if (story.id == 'base') {
        await tester.tap(find.text('Switch'));
        expect(actions, ['onSwitch acme-west']);
      }
    });
  }

  test('the organization and device checks are runnable', () {
    for (final id in ['orgs', 'deviceAuthorization', 'deviceVerification']) {
      final check = checkDefs.singleWhere((def) => def.id == id);
      expect(check.run, isNotNull, reason: id);
      expect(check.unavailableReason, isNull, reason: id);
    }
  });
}
