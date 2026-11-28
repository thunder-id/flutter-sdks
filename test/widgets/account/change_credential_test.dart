// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
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

    test('USR-1047 and USR-1048 map to the current-value field', () {
      expect(
        mapCredentialError(ThunderIDErrorCode.invalidInput, serverCode: 'USR-1047'),
        CredentialField.currentValue,
      );
      expect(
        mapCredentialError(ThunderIDErrorCode.forbidden, serverCode: 'USR-1048'),
        CredentialField.currentValue,
      );
    });

    test('AUTH-4011 maps to the form field', () {
      expect(
        mapCredentialError(ThunderIDErrorCode.authenticationFailed, serverCode: 'AUTH-4011'),
        CredentialField.form,
      );
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
            config: const ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'test', applicationId: 'app-1'),
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
      expect(args.containsKey('currentValue'), false, reason: 'an empty current value is not sent');
      expect(latest.success, true);
      expect(latest.newValue, '');
    });

    group('with a current value and server refusals', () {
      late List<MethodCall> log;
      Object? Function()? onUpdate;
      Object? Function()? onReauthenticate;
      late String method;
      late bool signedIn;
      Object? Function(MethodCall call)? onSignIn;

      setUp(() {
        log = <MethodCall>[];
        onUpdate = null;
        onReauthenticate = null;
        method = 'browser';
        onSignIn = null;
        signedIn = false;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('dev.thunderid/sdk'),
          (call) async {
            log.add(call);
            switch (call.method) {
              case 'initialize':
                return true;
              case 'isSignedIn':
                return signedIn;
              case 'getUser':
                return <Object?, Object?>{'sub': 'u1'};
              case 'getUserSchema':
                return <Object?, Object?>{
                  'password': <Object?, Object?>{'credential': true, 'displayName': 'Password'},
                };
              case 'updateUserCredentials':
                return onUpdate?.call();
              case 'reauthenticate':
                return onReauthenticate?.call();
              case 'reauthenticationMethod':
                return method;
              case 'signIn':
                return onSignIn?.call(call);
              default:
                return null;
            }
          },
        );
      });

      PlatformException refusal(String nativeCode, String serverCode, {Map<String, Object?>? extra}) =>
          PlatformException(
            code: nativeCode,
            message: 'refused',
            details: <String, Object?>{
              'serverError': <String, Object?>{
                'code': serverCode,
                'message': <String, Object?>{'defaultValue': 'Refused by the server'},
                ...?extra,
              },
            },
          );

      Future<ChangeCredentialState> fill(
        WidgetTester tester, {
        String current = '',
        void Function(int? maxAge)? onReauthenticationRequired,
      }) async {
        late ChangeCredentialState latest;
        await tester.pumpWidget(
          wrap(
            BaseChangeCredential(
              onReauthenticationRequired: onReauthenticationRequired,
              builder: (context, state) {
                latest = state;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (current.isNotEmpty) latest.onCurrentValueChanged(current);
        latest.onNewValueChanged('n3wP@ss');
        latest.onConfirmValueChanged('n3wP@ss');
        await tester.pump();
        return latest;
      }

      testWidgets('sends the current value when filled', (tester) async {
        final state = await fill(tester, current: '0ldP@ss');
        await state.submit();
        await tester.pumpAndSettle();

        final args = log.firstWhere((c) => c.method == 'updateUserCredentials').arguments as Map<Object?, Object?>;
        expect(args['currentValue'], '0ldP@ss');
        expect(args['newValue'], 'n3wP@ss');
        expect(state.currentValue, '', reason: 'cleared after a successful submit');
      });

      testWidgets('USR-1047 shows the required message on the current field', (tester) async {
        onUpdate = () => throw refusal('INVALID_INPUT', 'USR-1047');
        final state = await fill(tester);
        await state.submit();
        await tester.pumpAndSettle();

        expect(state.fieldError(CredentialField.currentValue), 'Enter your current password.');
        expect(state.fieldError(CredentialField.newValue), isNull);
        expect(state.error, isNull);
      });

      testWidgets('USR-1048 shows the incorrect message on the current field', (tester) async {
        onUpdate = () => throw refusal('FORBIDDEN', 'USR-1048');
        final state = await fill(tester, current: 'wrong');
        await state.submit();
        await tester.pumpAndSettle();

        expect(state.fieldError(CredentialField.currentValue), 'The current password is incorrect.');
        expect(state.error, isNull);
      });

      testWidgets('AUTH-4011 asks to sign in again and reports the challenge max age', (tester) async {
        onUpdate = () => throw PlatformException(
              code: 'AUTHENTICATION_FAILED',
              message: 'Unauthorized',
              details: <String, Object?>{
                'serverError': <String, Object?>{'code': 'AUTH-4011'},
                'authenticationChallenge': <String, Object?>{
                  'error': 'insufficient_user_authentication',
                  'maxAge': 300,
                },
              },
            );
        int? reportedMaxAge;
        var calls = 0;
        final state = await fill(
          tester,
          onReauthenticationRequired: (maxAge) {
            calls++;
            reportedMaxAge = maxAge;
          },
        );
        await state.submit();
        await tester.pumpAndSettle();

        expect(state.error, 'Sign in again to set your password.');
        expect(state.authenticationChallenge?.maxAge, 300);
        expect(calls, 1);
        expect(reportedMaxAge, 300);
        expect(log.where((c) => c.method == 'updateUserCredentials'), hasLength(1), reason: 'no retry');
      });

      testWidgets('AUTH-4011 without a challenge reads the max age from the error body', (tester) async {
        onUpdate = () => throw refusal(
              'AUTHENTICATION_FAILED',
              'AUTH-4011',
              extra: {
                'description': <String, Object?>{
                  'defaultValue': 'Authenticate again',
                  'params': <String, Object?>{'maxAge': '120'},
                },
              },
            );
        int? reportedMaxAge;
        final state = await fill(tester, onReauthenticationRequired: (maxAge) => reportedMaxAge = maxAge);
        await state.submit();
        await tester.pumpAndSettle();

        expect(state.error, 'Sign in again to set your password.');
        expect(reportedMaxAge, 120);
      });

      testWidgets('any other refusal shows the server message at form level', (tester) async {
        onUpdate = () => throw refusal('SERVER_ERROR', 'USR-5000');
        final state = await fill(tester);
        await state.submit();
        await tester.pumpAndSettle();

        expect(state.error, 'Refused by the server');
        expect(state.authenticationChallenge, isNull);
      });

      final stepUp = PlatformException(
        code: 'STEP_UP_REQUIRED',
        details: <String, Object?>{
          'serverError': <String, Object?>{'code': 'AUTH-4011'},
          'authenticationChallenge': <String, Object?>{
            'error': 'insufficient_user_authentication',
            'maxAge': 300,
          },
        },
      );

      List<MethodCall> callsTo(String method) => log.where((c) => c.method == method).toList();

      testWidgets('signs in again with the max age and retries the same change once', (tester) async {
        var attempts = 0;
        onUpdate = () {
          attempts++;
          if (attempts == 1) throw stepUp;
          return null;
        };
        final state = await fill(tester);
        await state.submit();
        await tester.pumpAndSettle();

        final reauth = callsTo('reauthenticate');
        expect(reauth, hasLength(1));
        expect((reauth.single.arguments as Map<Object?, Object?>)['maxAge'], 300);
        final updates = callsTo('updateUserCredentials');
        expect(updates, hasLength(2));
        expect((updates[1].arguments as Map<Object?, Object?>)['newValue'], 'n3wP@ss');
        expect(state.success, true);
        expect(state.error, isNull);
        expect(log.where((c) => c.method.toLowerCase().contains('refresh')), isEmpty);
      });

      testWidgets('shows the sign-in error when the retry is refused again', (tester) async {
        onUpdate = () => throw stepUp;
        final state = await fill(tester);
        await state.submit();
        await tester.pumpAndSettle();

        expect(callsTo('reauthenticate'), hasLength(1));
        expect(callsTo('updateUserCredentials'), hasLength(2), reason: 'one retry only');
        expect(state.success, false);
        expect(state.error, 'Sign in again to set your password.');
      });

      testWidgets('an app-native session signs in again in a dialog running the flow, then retries', (tester) async {
        var attempts = 0;
        onUpdate = () {
          attempts++;
          if (attempts == 1) throw stepUp;
          return null;
        };
        method = 'flow';
        onSignIn = (_) => <String, Object?>{'flowId': 'f1', 'flowStatus': 'COMPLETE'};
        final state = await fill(tester);
        signedIn = true;
        final submitted = state.submit();
        await pumpFrames(tester);
        await submitted;
        await pumpFrames(tester);

        final signIn = callsTo('signIn').single.arguments as Map<Object?, Object?>;
        final request = signIn['request'] as Map<Object?, Object?>;
        expect(request['reauthentication'], true);
        expect(request['maxAge'], 300);
        expect(callsTo('reauthenticate'), isEmpty);
        expect(callsTo('updateUserCredentials'), hasLength(2));
        expect(state.success, true);
        expect(find.byType(Dialog), findsNothing);
      });

      testWidgets('cancelling the in-app re-sign-in shows the sign-in error without a retry', (tester) async {
        onUpdate = () => throw stepUp;
        method = 'flow';
        onSignIn = (_) => <String, Object?>{'flowId': 'f1', 'flowStatus': 'INCOMPLETE', 'data': <String, Object?>{}};
        final state = await fill(tester);
        final submitted = state.submit();
        await pumpFrames(tester);
        expect(find.byType(Dialog), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await pumpFrames(tester);
        await submitted;

        expect(callsTo('updateUserCredentials'), hasLength(1));
        expect(state.error, 'Sign in again to set your password.');
      });

      testWidgets('another account signing in to the dialog says so, without a retry', (tester) async {
        onUpdate = () => throw stepUp;
        method = 'flow';
        onSignIn = (_) => throw PlatformException(
              code: 'AUTHENTICATION_FAILED',
              details: <String, Object?>{'anotherAccount': true},
            );
        final state = await fill(tester);
        final submitted = state.submit();
        await pumpFrames(tester);
        await submitted;

        expect(callsTo('updateUserCredentials'), hasLength(1));
        expect(state.error, 'You signed in with a different account. Sign in as yourself and try again.');
      });

      testWidgets('a step that fails after Cancel does not close anything again', (tester) async {
        onUpdate = () => throw stepUp;
        method = 'flow';
        final pending = Completer<Object?>();
        onSignIn = (_) => pending.future;
        final state = await fill(tester);
        final submitted = state.submit();
        await pumpFrames(tester);
        await tester.tap(find.text('Cancel'));
        await pumpFrames(tester);
        pending.completeError(PlatformException(code: 'NETWORK_ERROR'));
        await pumpFrames(tester);
        await submitted;

        expect(tester.takeException(), isNull);
        expect(find.byType(Dialog), findsNothing);
        expect(callsTo('updateUserCredentials'), hasLength(1));
        expect(state.error, 'Sign in again to set your password.');
      });

      testWidgets('another account signing in through the browser says so', (tester) async {
        onUpdate = () => throw stepUp;
        onReauthenticate = () => throw PlatformException(
              code: 'AUTHENTICATION_FAILED',
              details: <String, Object?>{'anotherAccount': true},
            );
        final state = await fill(tester);
        await state.submit();
        await tester.pumpAndSettle();

        expect(callsTo('updateUserCredentials'), hasLength(1));
        expect(state.error, 'You signed in with a different account. Sign in as yourself and try again.');
      });

      testWidgets('a session that cannot sign in again in the app gets no retry', (tester) async {
        onUpdate = () => throw stepUp;
        method = 'unavailable';
        final state = await fill(tester);
        await state.submit();
        await tester.pumpAndSettle();

        expect(callsTo('reauthenticate'), isEmpty);
        expect(callsTo('updateUserCredentials'), hasLength(1));
      });

      testWidgets('shows the sign-in error when the re-sign-in fails or is canceled', (tester) async {
        onUpdate = () => throw stepUp;
        onReauthenticate = () => throw PlatformException(code: 'FEDERATED_AUTH_CANCELLED');
        final state = await fill(tester);
        await state.submit();
        await tester.pumpAndSettle();

        expect(callsTo('updateUserCredentials'), hasLength(1), reason: 'no retry without a new sign-in');
        expect(state.success, false);
        expect(state.error, 'Sign in again to set your password.');
      });

      testWidgets('shows the sign-in error when the re-sign-in returns another user', (tester) async {
        onUpdate = () => throw stepUp;
        onReauthenticate = () => throw PlatformException(code: 'AUTHENTICATION_FAILED');
        final state = await fill(tester);
        await state.submit();
        await tester.pumpAndSettle();

        expect(callsTo('updateUserCredentials'), hasLength(1));
        expect(state.error, 'Sign in again to set your password.');
      });

      testWidgets('calls onReauthenticationRequired instead of signing in again', (tester) async {
        onUpdate = () => throw stepUp;
        int? reportedMaxAge;
        final state = await fill(tester, onReauthenticationRequired: (maxAge) => reportedMaxAge = maxAge);
        await state.submit();
        await tester.pumpAndSettle();

        expect(reportedMaxAge, 300);
        expect(callsTo('reauthenticate'), isEmpty);
        expect(callsTo('updateUserCredentials'), hasLength(1));
      });
    });
  });
}

/// Pumps a few frames: the sign-in form's progress indicator never settles.
Future<void> pumpFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
