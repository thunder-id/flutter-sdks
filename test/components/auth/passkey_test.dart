// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/components/auth/sign_in.dart';
import 'package:thunderid_flutter/src/components/thunderid_provider.dart';
import 'package:thunderid_flutter/src/models/thunderid_config.dart';
import 'package:thunderid_flutter/src/models/user.dart';

const _config = ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'test');
const _sdkChannel = MethodChannel('dev.thunderid/sdk');
const _mockUser = User({'sub': 'u1', 'username': 'brion'});

Widget _providerWidget({
  required Widget child,
}) =>
    WidgetsApp(
      color: const Color(0xFFFFFFFF),
      builder: (_, __) => ThunderIDProvider(config: _config, child: child),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sdkChannel, null);
  });

  testWidgets(
    'auto-resubmits with the native passkey ceremony result and completes sign-in',
    (tester) async {
      final log = <MethodCall>[];
      var signInCallCount = 0;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        _sdkChannel,
        (call) async {
          log.add(call);
          switch (call.method) {
            case 'initialize':
              return true;
            case 'isSignedIn':
              return signInCallCount > 1;
            case 'getUser':
              return signInCallCount > 1 ? _mockUser.toMap() : null;
            case 'performPasskeyAuthentication':
              return <String, String>{
                'credentialId': 'cred-123',
                'clientDataJSON': 'client-data',
                'authenticatorData': 'auth-data',
                'signature': 'sig',
              };
            case 'signIn':
              signInCallCount++;
              if (signInCallCount == 1) {
                return <String, dynamic>{
                  'flowId': 'flow-1',
                  'flowStatus': 'PROMPT_ONLY',
                  'challengeToken': 'token-1',
                  'data': {
                    'additionalData': {
                      'passkeyChallenge': '{"challenge":"abc","rpId":"localhost"}',
                    },
                  },
                };
              }
              final args = call.arguments as Map<Object?, Object?>;
              final payload = (args['payload'] as Map<Object?, Object?>).cast<String, Object?>();
              final inputs = (payload['inputs'] as Map<Object?, Object?>).cast<String, Object?>();
              expect(inputs['credentialId'], 'cred-123');
              return <String, dynamic>{
                'flowId': 'flow-1',
                'flowStatus': 'COMPLETE',
                'assertion': 'mock-assertion',
              };
            default:
              return null;
          }
        },
      );

      String? successUsername;
      await tester.pumpWidget(_providerWidget(
        child: BaseSignIn(
          applicationId: 'app-1',
          onSuccess: (user) => successUsername = user.username,
          builder: (_, __) => const SizedBox(),
        ),
      ),);
      await tester.pumpAndSettle();

      expect(log.where((c) => c.method == 'signIn').length, 2);
      expect(log.any((c) => c.method == 'performPasskeyAuthentication'), true);
      expect(successUsername, 'brion');
    },
  );

  testWidgets(
    'surfaces a native passkey error instead of hanging on a stale form',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        _sdkChannel,
        (call) async {
          switch (call.method) {
            case 'initialize':
              return true;
            case 'isSignedIn':
              return false;
            case 'performPasskeyAuthentication':
              throw PlatformException(
                code: 'PASSKEY_NOT_SUPPORTED',
                message: 'Passkey ceremonies are not yet available on this platform',
              );
            case 'signIn':
              return <String, dynamic>{
                'flowId': 'flow-1',
                'flowStatus': 'PROMPT_ONLY',
                'challengeToken': 'token-1',
                'data': {
                  'additionalData': {
                    'passkeyChallenge': '{"challenge":"abc","rpId":"localhost"}',
                  },
                },
              };
            default:
              return null;
          }
        },
      );

      var errorCalled = false;
      String? capturedError;
      await tester.pumpWidget(_providerWidget(
        child: BaseSignIn(
          applicationId: 'app-1',
          onError: () => errorCalled = true,
          builder: (_, state) {
            capturedError = state.error;
            return const SizedBox();
          },
        ),
      ),);
      await tester.pumpAndSettle();

      expect(errorCalled, true);
      expect(capturedError, contains('PASSKEY_NOT_SUPPORTED'));
    },
  );
}
