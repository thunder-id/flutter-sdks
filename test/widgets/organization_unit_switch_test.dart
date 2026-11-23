// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

const _channel = MethodChannel('dev.thunderid/sdk');
const _config = ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'client-1');

Map<String, Object?> _profile(String unitName) => {
      'id': 'user-1',
      'isReadOnly': false,
      'attributes': {'unitName': unitName},
    };

void main() {
  late List<Completer<Object?>> profileReads;
  late List<MethodCall> calls;

  setUp(() {
    profileReads = [];
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
        case 'isSignedIn':
          return Future.value(true);
        case 'getUser':
          return Future.value({'sub': 'user-1', 'ouId': 'ou-1'});
        case 'getUserProfile':
          final read = Completer<Object?>();
          profileReads.add(read);
          return read.future;
        case 'switchOrganizationUnit':
          return Future.value({
            'status': 'switched',
            'user': {'sub': 'user-1', 'ouId': 'ou-2'},
          });
        default:
          return Future.value();
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
  });

  testWidgets('a switch replaces the user and drops a profile read from the previous unit', (tester) async {
    final key = GlobalKey<ThunderIDState>();
    await tester.pumpWidget(ThunderIDProvider(key: key, config: _config, child: const SizedBox()));
    await tester.pumpAndSettle();
    final state = key.currentState!;
    expect(profileReads, hasLength(1));

    final result = await state.switchOrganizationUnit('ou-2');
    await tester.pump();

    expect(result, isA<OrganizationUnitSwitched>());
    expect(state.user!.claims['ouId'], 'ou-2');
    expect(profileReads, hasLength(2));

    // The read started before the switch answers late, with the previous unit's attributes.
    profileReads[0].complete(_profile('Unit 1'));
    await tester.pump();
    expect(state.user!.claims['unitName'], isNull);
    expect(calls.where((c) => c.method == 'setCachedUser'), isEmpty);

    profileReads[1].complete(_profile('Unit 2'));
    await tester.pump();
    expect(state.user!.claims['unitName'], 'Unit 2');
    expect(state.user!.claims['ouId'], 'ou-2');
    expect(calls.where((c) => c.method == 'setCachedUser'), hasLength(1));
  });
}
