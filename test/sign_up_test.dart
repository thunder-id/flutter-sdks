// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/models/thunderid_config.dart';
import 'package:thunderid_flutter/src/widgets/sign_up.dart';
import 'package:thunderid_flutter/src/widgets/thunderid_provider.dart';

const _config = ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'test');
const _sdkChannel = MethodChannel('dev.thunderid/sdk');

Map<String, dynamic> _redirection(String token, {String? url = 'https://accounts.example.com/authorize'}) =>
    <String, dynamic>{
      'flowId': 'flow-1',
      'flowStatus': 'INCOMPLETE',
      'type': 'REDIRECTION',
      'challengeToken': token,
      'data': {if (url != null) 'redirectURL': url},
    };

final Map<String, dynamic> _linkingPrompt = <String, dynamic>{
  'flowId': 'flow-1',
  'flowStatus': 'INCOMPLETE',
  'type': 'VIEW',
  'challengeToken': 'token-final',
  'data': {
    'actions': [
      {'id': 'action_confirm', 'ref': 'action_confirm'},
      {'id': 'action_reject', 'ref': 'action_reject'},
    ],
    'additionalData': {'linkingPromptDetails': '[{"label":"Email","value":"alice@example.com"}]'},
    'meta': {
      'components': [
        {'category': 'DISPLAY', 'id': 'kv', 'type': 'KEY_VALUE_LIST', 'source': 'linkingPromptDetails'},
        {'category': 'ACTION', 'id': 'action_confirm', 'type': 'ACTION', 'variant': 'PRIMARY', 'label': 'Link'},
        {'category': 'ACTION', 'id': 'action_reject', 'type': 'ACTION', 'variant': 'SECONDARY', 'label': 'Skip'},
      ],
    },
  },
};

/// Pumps [SignUp] whose first step is [initial], answering each `continueFederatedAuth` call with
/// the next entry of [federated] (a map is returned, anything else is thrown). Returns the
/// arguments of every `continueFederatedAuth` call.
Future<List<Map<Object?, Object?>>> _pumpSignUp(
  WidgetTester tester, {
  required Map<String, dynamic> initial,
  List<Object> federated = const [],
}) async {
  final calls = <Map<Object?, Object?>>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    _sdkChannel,
    (call) async {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'isSignedIn':
          return false;
        case 'signUp':
          return initial;
        case 'continueFederatedAuth':
          calls.add(call.arguments as Map<Object?, Object?>);
          final next = federated[calls.length - 1];
          if (next is Map) return next;
          throw next;
        default:
          return null;
      }
    },
  );
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: ThunderIDProvider(config: _config, child: SignUp(applicationId: 'app-1')),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return calls;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_sdkChannel, null);
  });

  testWidgets('follows a federated sign-up redirect into the account-linking prompt', (tester) async {
    final calls = await _pumpSignUp(tester, initial: _redirection('token-1'), federated: [_linkingPrompt]);

    expect(calls.single['redirectUrl'], 'https://accounts.example.com/authorize');
    expect(calls.single['flowId'], 'flow-1');
    expect(calls.single['challengeToken'], 'token-1');
    expect(find.text('alice@example.com'), findsOneWidget);
    expect(tester.widget(find.byKey(const Key('thunderid-action-action_confirm'))), isA<FilledButton>());
    expect(tester.widget(find.byKey(const Key('thunderid-action-action_reject'))), isA<OutlinedButton>());
  });

  testWidgets('follows a redirect that resumes straight into another one', (tester) async {
    final calls = await _pumpSignUp(
      tester,
      initial: _redirection('token-1'),
      federated: [_redirection('token-2'), _linkingPrompt],
    );

    expect(calls.map((c) => c['challengeToken']), ['token-1', 'token-2']);
    expect(find.text('alice@example.com'), findsOneWidget);
  });

  testWidgets('shows no error when the user dismisses the browser', (tester) async {
    await _pumpSignUp(
      tester,
      initial: _redirection('token-1'),
      federated: [PlatformException(code: 'FEDERATED_AUTH_CANCELLED', message: 'dismissed')],
    );

    expect(find.textContaining('FEDERATED_AUTH_CANCELLED'), findsNothing);
    expect(find.textContaining('dismissed'), findsNothing);
  });

  testWidgets('reports an error when a redirect step carries no URL', (tester) async {
    final calls = await _pumpSignUp(tester, initial: _redirection('token-1', url: null));

    expect(calls, isEmpty);
    expect(find.textContaining('did not return a redirect URL'), findsOneWidget);
  });
}
