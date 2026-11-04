// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

void main() {
  group('evaluateCredentialForm', () {
    test('invalid when either value is empty', () {
      expect(evaluateCredentialForm('', '', null).isValid, false);
      expect(evaluateCredentialForm('abc', '', null).isValid, false);
      expect(evaluateCredentialForm('', 'abc', null).isValid, false);
    });

    test('invalid when the values do not match', () {
      final evaluation = evaluateCredentialForm('abc', 'xyz', null);
      expect(evaluation.confirmMatches, false);
      expect(evaluation.isValid, false);
    });

    test('valid with no policy once both values match and are non-empty', () {
      final evaluation = evaluateCredentialForm('abc', 'abc', null);
      expect(evaluation.patternChecked, false);
      expect(evaluation.meetsPolicy, true);
      expect(evaluation.isValid, true);
    });

    test('enforces a regex policy when present', () {
      final passing = evaluateCredentialForm('Abc123!', 'Abc123!', r'^(?=.*[A-Z])(?=.*\d).+$');
      expect(passing.patternChecked, true);
      expect(passing.patternPassed, true);
      expect(passing.isValid, true);

      final failing = evaluateCredentialForm('abc', 'abc', r'^(?=.*[A-Z])(?=.*\d).+$');
      expect(failing.patternPassed, false);
      expect(failing.isValid, false);
    });

    test('an uncompilable pattern is treated as passing', () {
      final evaluation = evaluateCredentialForm('abc', 'abc', '(unterminated');
      expect(evaluation.patternChecked, true);
      expect(evaluation.patternPassed, true);
      expect(evaluation.isValid, true);
    });
  });

  group('mapCredentialError', () {
    test('invalidInput maps to the new-value field', () {
      expect(mapCredentialError(ThunderIDErrorCode.invalidInput), CredentialField.newValue);
    });

    test('every other code maps to the form field', () {
      expect(mapCredentialError(ThunderIDErrorCode.serverError), CredentialField.form);
      expect(mapCredentialError(ThunderIDErrorCode.networkError), CredentialField.form);
    });
  });

  group('substituteCredential', () {
    test('substitutes both credential tokens', () {
      expect(
        substituteCredential('Change {credential}, not {credentialLower}!', 'PIN'),
        'Change PIN, not pin!',
      );
    });

    test('leaves a template with no tokens unchanged', () {
      expect(substituteCredential('Save', 'Password'), 'Save');
    });
  });

  group('titleCaseCredential', () {
    test('capitalizes the first letter only', () {
      expect(titleCaseCredential('pin'), 'Pin');
      expect(titleCaseCredential('backupCode'), 'BackupCode');
    });

    test('handles an empty string', () {
      expect(titleCaseCredential(''), '');
    });
  });

  group('BaseChangeCredential', () {
    Widget wrap(Widget child) => MaterialApp(
          home: ThunderIDProvider(
            config: const ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'test'),
            child: child,
          ),
        );

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.thunderid/sdk'),
        (call) async {
          switch (call.method) {
            case 'initialize':
              return true;
            case 'isSignedIn':
              return false;
            case 'getUserSchema':
              return <Object?, Object?>{
                'password': <Object?, Object?>{'credential': true, 'displayName': 'Password'},
              };
            case 'updateUserCredentials':
              return null;
            default:
              return null;
          }
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('dev.thunderid/sdk'), null);
    });

    testWidgets('marks the credential unavailable when the schema omits it', (tester) async {
      late ChangeCredentialState latest;
      await tester.pumpWidget(
        wrap(
          BaseChangeCredential(
            attribute: 'pin',
            builder: (context, state) {
              latest = state;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(latest.unavailable, true);
    });

    testWidgets('submit sends the attribute and new value to the channel', (tester) async {
      final log = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.thunderid/sdk'),
        (call) async {
          log.add(call);
          switch (call.method) {
            case 'initialize':
              return true;
            case 'isSignedIn':
              return false;
            case 'getUserSchema':
              return <Object?, Object?>{
                'password': <Object?, Object?>{'credential': true, 'displayName': 'Password'},
              };
            case 'updateUserCredentials':
              return null;
            default:
              return null;
          }
        },
      );

      late ChangeCredentialState latest;
      await tester.pumpWidget(
        wrap(
          BaseChangeCredential(
            builder: (context, state) {
              latest = state;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      latest.onNewValueChanged('n3wP@ss');
      await tester.pump();
      latest.onConfirmValueChanged('n3wP@ss');
      await tester.pump();
      await latest.submit();
      await tester.pumpAndSettle();

      final call = log.firstWhere((c) => c.method == 'updateUserCredentials');
      final args = call.arguments as Map<Object?, Object?>;
      expect(args['attribute'], 'password');
      expect(args['newValue'], 'n3wP@ss');
      expect(latest.success, true);
      expect(latest.newValue, '');
    });
  });
}
