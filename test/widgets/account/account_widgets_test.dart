// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

// Smoke tests for the styled UserProfile/ChangeCredential widgets themselves (the pure
// evaluation/mapping logic and BaseChangeCredential's headless behavior are covered by
// change_credential_test.dart and user_profile_fields_test.dart). These exist to catch
// widget-assembly bugs - missing ancestors, layout overflow, broken navigation - that
// `flutter analyze` cannot.

Widget _wrap(Widget child) => MaterialApp(
      home: ThunderIDProvider(
        config: const ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'test'),
        child: Scaffold(body: child),
      ),
    );

Future<Object?> Function(MethodCall) _handler() => (call) async {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'isSignedIn':
          return false;
        case 'getUserSchema':
          return <Object?, Object?>{
            'password': <Object?, Object?>{'credential': true, 'displayName': 'Password'},
            'email': <Object?, Object?>{'type': 'STRING', 'displayName': 'Email'},
            'username': <Object?, Object?>{
              'type': 'STRING',
              'displayName': 'Username',
              'readOnly': true,
            },
            'address': <Object?, Object?>{'type': 'COMPLEX', 'displayName': 'Address'},
          };
        case 'getUserProfile':
          return <Object?, Object?>{
            'id': 'user-1',
            'isReadOnly': false,
            'attributes': <Object?, Object?>{
              'email': 'ada@example.com',
              'username': 'ada',
              'address': <Object?, Object?>{'city': 'NYC'},
            },
          };
        case 'updateUserCredentials':
        case 'setCachedUser':
          return null;
        default:
          return null;
      }
    };

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dev.thunderid/sdk'), _handler());
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dev.thunderid/sdk'), null);
  });

  group('ChangeCredential (styled)', () {
    testWidgets('renders a row and opens the full-screen form on tap', (tester) async {
      await tester.pumpWidget(_wrap(const ChangeCredential()));
      await tester.pumpAndSettle();

      expect(find.text('Password'), findsOneWidget);
      expect(find.byKey(const Key('thunderid-field-newCredential')), findsNothing);

      await tester.tap(find.byKey(const Key('thunderid-action-openCredential-password')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('thunderid-field-newCredential')), findsOneWidget);
      expect(find.byKey(const Key('thunderid-field-confirmCredential')), findsOneWidget);

      // Regression test: this used to share UserProfile's own "Personal info" back label, even
      // though the row this page returns to lives under the "Security" section in the sample.
      expect(find.text('Security'), findsOneWidget);
      expect(find.text('Personal info'), findsNothing);

      await tester.tap(find.byKey(const Key('thunderid-action-cancelCredential')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('thunderid-field-newCredential')), findsNothing);
    });

    testWidgets('the Save button enables live as the pushed page is typed into, and submits',
        (tester) async {
      // Regression test: ChangeCredentialState used to be an immutable snapshot captured once
      // when the full-screen page was pushed, so typing into the fields (which mutates
      // BaseChangeCredential's own state, outside the pushed page's rebuild scope) never made
      // the Save button's `evaluation.isValid` reflect the new text - it stayed permanently
      // disabled no matter what was typed.
      final log = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.thunderid/sdk'),
        (call) async {
          log.add(call);
          return _handler()(call);
        },
      );

      await tester.pumpWidget(_wrap(const ChangeCredential()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('thunderid-action-openCredential-password')));
      await tester.pumpAndSettle();

      ElevatedButton saveButton() => tester
          .widget<ElevatedButton>(find.byKey(const Key('thunderid-action-submitCredential')));
      expect(
        saveButton().onPressed,
        isNull,
        reason: 'disabled until both fields hold a matching value',
      );

      await tester.enterText(find.byKey(const Key('thunderid-field-newCredential')), 'n3wP@ss');
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('thunderid-field-confirmCredential')),
        'n3wP@ss',
      );
      await tester.pump();

      expect(
        saveButton().onPressed,
        isNotNull,
        reason: 'both fields now hold a matching value',
      );

      await tester.tap(find.byKey(const Key('thunderid-action-submitCredential')));
      await tester.pumpAndSettle();

      final call = log.firstWhere((c) => c.method == 'updateUserCredentials');
      final args = call.arguments as Map<Object?, Object?>;
      expect(args['newValue'], 'n3wP@ss');
      // A successful submit pops the page back to the row.
      expect(find.byKey(const Key('thunderid-field-newCredential')), findsNothing);
    });

    testWidgets('the mismatch error substitutes the credential name, not the raw template',
        (tester) async {
      // Regression test: this error used to be read via a plain i18n.resolve() call that skipped
      // substituteCredential, so it rendered the literal template "{credential}s do not match."
      // instead of "Passwords do not match."
      await tester.pumpWidget(_wrap(const ChangeCredential()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('thunderid-action-openCredential-password')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('thunderid-field-newCredential')), 'n3wP@ss');
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('thunderid-field-confirmCredential')),
        'different',
      );
      await tester.pump();

      expect(find.text('Passwords do not match.'), findsOneWidget);
      expect(find.textContaining('{credential}'), findsNothing);
    });

    testWidgets('cancel clears the typed values so reopening starts blank', (tester) async {
      // Regression test: BaseChangeCredential's state used to persist for the row's whole
      // lifetime with nothing clearing it on Cancel, so a value typed then abandoned stayed live
      // internally even though the (uncontrolled) fields render blank on reopen - risking a
      // stale-value submit if a later partial edit happened to make the form valid again.
      await tester.pumpWidget(_wrap(const ChangeCredential()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('thunderid-action-openCredential-password')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('thunderid-field-newCredential')), 'n3wP@ss');
      await tester.pump();

      await tester.tap(find.byKey(const Key('thunderid-action-cancelCredential')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('thunderid-action-openCredential-password')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('thunderid-field-confirmCredential')),
        'n3wP@ss',
      );
      await tester.pump();

      final saveButton = tester
          .widget<ElevatedButton>(find.byKey(const Key('thunderid-action-submitCredential')));
      expect(
        saveButton.onPressed,
        isNull,
        reason: 'the abandoned New value must not still be live after cancel',
      );
    });

    testWidgets('shows an optional current field above the new value and sends it when filled',
        (tester) async {
      final log = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.thunderid/sdk'),
        (call) async {
          log.add(call);
          return _handler()(call);
        },
      );

      await tester.pumpWidget(_wrap(const ChangeCredential()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('thunderid-action-openCredential-password')));
      await tester.pumpAndSettle();

      final current = find.byKey(const Key('thunderid-field-currentCredential'));
      expect(current, findsOneWidget);
      expect(find.text('Current Password'), findsOneWidget);
      expect(find.text('Leave this empty if you have not set one yet.'), findsOneWidget);
      expect(
        tester.getTopLeft(current).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('thunderid-field-newCredential'))).dy),
      );

      await tester.enterText(current, '0ldP@ss');
      await tester.enterText(find.byKey(const Key('thunderid-field-newCredential')), 'n3wP@ss');
      await tester.enterText(find.byKey(const Key('thunderid-field-confirmCredential')), 'n3wP@ss');
      await tester.pump();
      await tester.tap(find.byKey(const Key('thunderid-action-submitCredential')));
      await tester.pumpAndSettle();

      final args = log.firstWhere((c) => c.method == 'updateUserCredentials').arguments as Map<Object?, Object?>;
      expect(args['currentValue'], '0ldP@ss');
    });

    testWidgets('shows an incorrect current value on the current field', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.thunderid/sdk'),
        (call) async {
          if (call.method == 'updateUserCredentials') {
            throw PlatformException(
              code: 'FORBIDDEN',
              details: <String, Object?>{
                'serverError': <String, Object?>{'code': 'USR-1048'},
              },
            );
          }
          return _handler()(call);
        },
      );

      await tester.pumpWidget(_wrap(const ChangeCredential()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('thunderid-action-openCredential-password')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('thunderid-field-currentCredential')), 'wrong');
      await tester.enterText(find.byKey(const Key('thunderid-field-newCredential')), 'n3wP@ss');
      await tester.enterText(find.byKey(const Key('thunderid-field-confirmCredential')), 'n3wP@ss');
      await tester.pump();
      await tester.tap(find.byKey(const Key('thunderid-action-submitCredential')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('thunderid-field-currentCredential-error')), findsOneWidget);
      expect(find.text('The current password is incorrect.'), findsOneWidget);
      expect(find.byKey(const Key('thunderid-field-newCredential')), findsOneWidget, reason: 'the page stays open');
    });

    testWidgets('asks to sign in again and calls onReauthenticationRequired', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.thunderid/sdk'),
        (call) async {
          if (call.method == 'updateUserCredentials') {
            throw PlatformException(
              code: 'AUTHENTICATION_FAILED',
              details: <String, Object?>{
                'serverError': <String, Object?>{'code': 'AUTH-4011'},
                'authenticationChallenge': <String, Object?>{
                  'error': 'insufficient_user_authentication',
                  'maxAge': 300,
                },
              },
            );
          }
          return _handler()(call);
        },
      );
      int? reportedMaxAge;

      await tester.pumpWidget(
        _wrap(ChangeCredential(onReauthenticationRequired: (maxAge) => reportedMaxAge = maxAge)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('thunderid-action-openCredential-password')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('thunderid-field-newCredential')), 'n3wP@ss');
      await tester.enterText(find.byKey(const Key('thunderid-field-confirmCredential')), 'n3wP@ss');
      await tester.pump();
      await tester.tap(find.byKey(const Key('thunderid-action-submitCredential')));
      await tester.pumpAndSettle();

      expect(find.text('Sign in again to set your password.'), findsOneWidget);
      expect(reportedMaxAge, 300);
    });
  });

  group('UserProfile step-up', () {
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

    Future<List<MethodCall>> saveEmail(
      WidgetTester tester, {
      required Object? Function(int attempt) onUpdate,
      Object? Function()? onReauthenticate,
    }) async {
      final log = <MethodCall>[];
      var attempts = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.thunderid/sdk'),
        (call) async {
          log.add(call);
          if (call.method == 'updateUserProfile') return onUpdate(++attempts);
          if (call.method == 'reauthenticate') return onReauthenticate?.call();
          if (call.method == 'reauthenticationMethod') return 'browser';
          return _handler()(call);
        },
      );
      await tester.pumpWidget(_wrap(const UserProfile()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('thunderid-field-profile-email')), 'new@example.com');
      await tester.pump();
      await tester.tap(find.byKey(const Key('thunderid-action-saveProfileField')));
      await tester.pumpAndSettle();
      return log;
    }

    Map<Object?, Object?> savedProfile() => <Object?, Object?>{
          'id': 'user-1',
          'isReadOnly': false,
          'attributes': <Object?, Object?>{'email': 'new@example.com', 'username': 'ada'},
        };

    testWidgets('signs in again with the max age and saves the same change once more', (tester) async {
      final log = await saveEmail(
        tester,
        onUpdate: (attempt) {
          if (attempt == 1) throw stepUp;
          return savedProfile();
        },
      );

      final reauth = log.where((c) => c.method == 'reauthenticate').toList();
      expect(reauth, hasLength(1));
      expect((reauth.single.arguments as Map<Object?, Object?>)['maxAge'], 300);
      final updates = log.where((c) => c.method == 'updateUserProfile').toList();
      expect(updates, hasLength(2));
      final payload = (updates[1].arguments as Map<Object?, Object?>)['payload'] as Map<Object?, Object?>;
      expect(payload['email'], 'new@example.com');
      expect(find.text('Sign in again to save this change.'), findsNothing);
      expect(log.where((c) => c.method.toLowerCase().contains('refresh')), isEmpty);
    });

    testWidgets('shows the sign-in error when the retry is refused again', (tester) async {
      final log = await saveEmail(tester, onUpdate: (_) => throw stepUp);

      expect(log.where((c) => c.method == 'reauthenticate'), hasLength(1));
      expect(log.where((c) => c.method == 'updateUserProfile'), hasLength(2));
      expect(find.text('Sign in again to save this change.'), findsOneWidget);
    });

    testWidgets('shows the sign-in error when the re-sign-in fails', (tester) async {
      final log = await saveEmail(
        tester,
        onUpdate: (_) => throw stepUp,
        onReauthenticate: () => throw PlatformException(code: 'FEDERATED_AUTH_CANCELLED'),
      );

      expect(log.where((c) => c.method == 'updateUserProfile'), hasLength(1));
      expect(find.text('Sign in again to save this change.'), findsOneWidget);
    });
  });

  group('UserProfile (styled)', () {
    testWidgets('renders a row per editable field and opens its edit page on tap', (tester) async {
      await tester.pumpWidget(_wrap(const UserProfile()));
      await tester.pumpAndSettle();

      expect(find.text('Email'), findsOneWidget);
      // Appears twice: once as the avatar header's subtitle, once as the Email row's value.
      expect(find.text('ada@example.com'), findsWidgets);

      // Regression test: a read-only field like username used to be dropped from the row list
      // entirely rather than shown without an Edit link.
      expect(find.text('Username'), findsOneWidget);
      // Appears twice: once as the avatar header's display name (falls back to username when
      // no first/last name is mapped), once as the Username row's value.
      expect(find.text('ada'), findsWidgets);
      expect(find.text('Edit'), findsOneWidget, reason: 'only the editable Email row gets one');

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('thunderid-field-profile-email')), findsOneWidget);

      await tester.tap(find.byKey(const Key('thunderid-action-cancelProfileField')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('thunderid-field-profile-email')), findsNothing);
    });

    testWidgets('a COMPLEX field renders its entries and gets no Edit link', (tester) async {
      // Regression test: the redesign used to drop the schema's COMPLEX-type check entirely, so
      // a Map-valued field rendered blank with a working Edit link that would have written a
      // plain string over a structured attribute on save.
      await tester.pumpWidget(_wrap(const UserProfile()));
      await tester.pumpAndSettle();

      expect(find.text('Address'), findsOneWidget);
      expect(find.text('city: NYC'), findsOneWidget);

      final addressRow = find.ancestor(
        of: find.text('Address'),
        matching: find.byType(Row),
      );
      expect(find.descendant(of: addressRow, matching: find.text('Edit')), findsNothing);
    });
  });
}
