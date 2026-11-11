// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/models/flow_models.dart';
import 'package:thunderid_flutter/src/models/thunderid_config.dart';
import 'package:thunderid_flutter/src/models/thunderid_error.dart';
import 'package:thunderid_flutter/src/widgets/auth/flow/flow_expiry.dart';
import 'package:thunderid_flutter/src/widgets/auth/sign_in.dart';
import 'package:thunderid_flutter/src/widgets/auth/sign_up.dart';
import 'package:thunderid_flutter/src/widgets/thunderid_provider.dart';

const _sdkChannel = MethodChannel('dev.thunderid/sdk');
const _restarted = 'Your session expired, so we started again.';

Map<String, dynamic> _step({int? expiresIn}) => {
      'flowId': 'f-1',
      'flowStatus': 'INCOMPLETE',
      if (expiresIn != null) 'expiresIn': expiresIn,
      'data': {
        'inputs': [
          {'name': 'username', 'type': 'TEXT_INPUT', 'required': true},
        ],
        'actions': [
          {'id': 'next', 'label': 'Next'},
        ],
      },
    };

EmbeddedFlowResponse _response(String status, {int? expiresIn}) =>
    EmbeddedFlowResponse.fromMap({'flowStatus': status, if (expiresIn != null) 'expiresIn': expiresIn});

/// Answers the SDK channel: each flow request gets the next of [steps], and a step that is an exception is thrown.
List<String> _mockChannel(String method, List<Object> steps) {
  final calls = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    _sdkChannel,
    (call) async {
      if (call.method != method) {
        return switch (call.method) {
          'initialize' => true,
          'isSignedIn' => false,
          _ => null,
        };
      }
      calls.add(call.method);
      final next = steps.removeAt(0);
      if (next is Exception) throw next;
      return next;
    },
  );
  return calls;
}

Widget _app(Widget child) => MaterialApp(
      home: Scaffold(
        body: ThunderIDProvider(
          config: const ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'test'),
          child: child,
        ),
      ),
    );

void main() {
  group('FlowExpiry', () {
    late DateTime now;
    late int restarts;
    late FlowExpiry expiry;

    setUp(() {
      now = DateTime(2026);
      restarts = 0;
      expiry = FlowExpiry(restart: () => restarts++, now: () => now);
    });

    tearDown(() => expiry.dispose());

    test('reads the expiry of a step', () {
      expect(_response('INCOMPLETE', expiresIn: 3540).expiresIn, 3540);
      expect(_response('COMPLETE').expiresIn, isNull);
    });

    test('maps the expired flow error from the native SDKs', () {
      expect(ThunderIDErrorCode.fromString('FLOW_EXPIRED'), ThunderIDErrorCode.flowExpired);
    });

    testWidgets('starts again once the step expires', (tester) async {
      expiry.track(_response('INCOMPLETE', expiresIn: 60));

      await tester.pump(const Duration(seconds: 59));
      expect(restarts, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(restarts, 1);
    });

    test('starts again when the server refuses the step as expired', () {
      expiry.expire();
      expect(restarts, 1);
    });

    test('waits for the app to be resumed before starting again', () {
      expiry.setActive(false);
      expiry.expire();
      expect(restarts, 0);

      expiry.setActive(true);
      expect(restarts, 1);
      expiry.setActive(true);
      expect(restarts, 1, reason: 'starts again only once');
    });

    test('checks the deadline when the app is resumed again', () {
      expiry.track(_response('INCOMPLETE', expiresIn: 60));
      expiry.setActive(false);

      // The clock moves past the deadline without the timer firing, as in the background.
      now = now.add(const Duration(seconds: 61));
      expiry.setActive(true);

      expect(restarts, 1);
    });

    test('stops tracking a flow that ended', () {
      expiry.track(_response('INCOMPLETE', expiresIn: 60));
      expiry.track(_response('COMPLETE'));
      now = now.add(const Duration(seconds: 61));
      expiry.setActive(true);
      expect(restarts, 0);
    });
  });

  testWidgets('SignIn starts again once the step expires and says so', (tester) async {
    final calls = _mockChannel('signIn', [_step(expiresIn: 60), _step(expiresIn: 60)]);
    await tester.pumpWidget(_app(const SignIn(applicationId: 'app-1')));
    await tester.pumpAndSettle();
    expect(find.text(_restarted), findsNothing);

    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();

    expect(calls, hasLength(2));
    expect(find.text(_restarted), findsOneWidget);
  });

  testWidgets('SignIn starts again when the server refuses a step as expired, until the user acts', (tester) async {
    final calls = _mockChannel('signIn', [
      _step(),
      PlatformException(code: 'FLOW_EXPIRED', message: 'The flow execution expired'),
      _step(),
      _step(),
    ]);
    await tester.pumpWidget(_app(const SignIn(applicationId: 'app-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(calls, hasLength(3));
    expect(find.text(_restarted), findsOneWidget);
    expect(find.textContaining('FLOW_EXPIRED'), findsNothing);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text(_restarted), findsNothing);
  });

  testWidgets('BaseSignUp tells a custom render that the flow started again', (tester) async {
    _mockChannel('signUp', [
      _step(),
      PlatformException(code: 'FLOW_EXPIRED', message: 'The flow execution expired'),
      _step(),
    ]);
    await tester.pumpWidget(
      _app(
        BaseSignUp(
          applicationId: 'app-1',
          builder: (context, state) => Column(
            children: [
              Text('restarted: ${state.isFlowRestarted}'),
              TextButton(onPressed: () => state.submit('next', const {}), child: const Text('Go')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('restarted: false'), findsOneWidget);

    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();

    expect(find.text('restarted: true'), findsOneWidget);
  });
}
