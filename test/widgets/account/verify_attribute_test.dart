// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/models/user_profile.dart' as model;
import 'package:thunderid_flutter/src/widgets/auth/flow/flow_form.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

const _channel = MethodChannel('dev.thunderid/sdk');
const _destination = 'a***@example.com';

Map<String, Object?> _heading(String id, String variant, String label) =>
    {'type': 'TEXT', 'id': id, 'variant': variant, 'label': label};

/// The email code step as the native SDKs encode it.
Map<String, Object?> _codeStep({
  bool withAdditionalData = true,
  String? failureReason,
}) =>
    {
      'flowId': 'exec-1',
      'flowStatus': 'PROMPT_ONLY',
      'challengeToken': 'ct-1',
      if (failureReason != null) 'failureReason': failureReason,
      'data': {
        'inputs': [
          {'name': 'otp', 'type': 'OTP_INPUT', 'required': true},
        ],
        'actions': [
          {
            'id': 'action_email_verify',
            'ref': 'action_email_verify',
            'nextNode': 'verify_email_otp',
          },
          {
            'id': 'action_email_resend',
            'ref': 'action_email_resend',
            'nextNode': 'prepare_verification',
          },
        ],
        'meta': {
          'components': [
            _heading(
              'email_code_heading',
              'HEADING_1',
              '{{ t(verification:self.email.title) }}',
            ),
            _heading(
              'email_code_message',
              'HEADING_6',
              '{{ t(verification:self.email.message) }}',
            ),
            {
              'type': 'BLOCK',
              'id': 'block_email_otp',
              'components': [
                {
                  'type': 'OTP_INPUT',
                  'id': 'input_email_otp',
                  'ref': 'otp',
                  'label': 'Code',
                },
                {
                  'type': 'ACTION',
                  'id': 'action_email_verify',
                  'label': 'Verify',
                  'eventType': 'SUBMIT',
                },
                {
                  'type': 'RESEND',
                  'id': 'action_email_resend',
                  'label': 'Resend',
                  'eventType': 'SUBMIT',
                },
              ],
            },
          ],
        },
        if (withAdditionalData)
          'additionalData': {
            'maskedDestination': _destination,
            'otpLength': '6',
          },
      },
    };

final Map<String, Object?> _linkStep = {
  'flowId': 'exec-1',
  'flowStatus': 'PROMPT_ONLY',
  'data': {
    'meta': {
      'components': [_heading('h', 'HEADING_1', 'Check your inbox')],
    },
    'additionalData': {'maskedDestination': _destination},
  },
};

const _complete = {'flowId': 'exec-1', 'flowStatus': 'COMPLETE'};

final Map<String, Object?> _flowMeta = {
  'i18n': {
    'translations': {
      'verification': {
        'self.email.title': 'Verify your email',
        'self.email.message': 'Enter the code we emailed you.',
        'self.code.invalid': 'That code is not right.',
      },
    },
  },
};

class _Harness {
  final calls = <MethodCall>[];
  final verifyResponses = <Object? Function(MethodCall call)>[];
  String schemaType = 'email';
  Completer<Object?>? schemaReply;
  Map<String, Object?>? verifiedAttributes = {};
  bool isReadOnly = false;
  Object? Function(MethodCall call)? onUpdateProfile;

  List<MethodCall> get verifyCalls =>
      calls.where((c) => c.method == 'verifyAttribute').toList();
  int get profileReads =>
      calls.where((c) => c.method == 'getUserProfile').length;

  Map<String, Object?> profile(String email) => {
        'id': 'user-1',
        'attributes': {'email': email, 'mobile_number': '+94770000000'},
        'isReadOnly': isReadOnly,
        if (verifiedAttributes != null)
          'verifiedAttributes': verifiedAttributes,
      };

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
          return true;
        case 'isSignedIn':
          return true;
        case 'getUser':
          return {'sub': 'user-1'};
        case 'getUserProfile':
          return profile('ada@example.com');
        case 'getUserSchema':
          if (schemaReply != null) return schemaReply!.future;
          return {
            'email': {'type': schemaType, 'displayName': 'Email'},
            'mobile_number': {'type': 'mobile', 'displayName': 'Mobile'},
          };
        case 'getFlowMeta':
          return _flowMeta;
        case 'updateUserProfile':
          return onUpdateProfile!(call);
        case 'verifyAttribute':
          if (verifyResponses.isEmpty) {
            throw StateError('unexpected verifyAttribute');
          }
          return verifyResponses.removeAt(0)(call);
        default:
          return null;
      }
    });
  }
}

Widget _app(Widget child, {String? applicationId = 'app-1'}) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ThunderIDProvider(
            config: ThunderIDConfig(
              baseUrl: 'https://localhost:8090',
              clientId: 'test',
              applicationId: applicationId,
            ),
            child: child,
          ),
        ),
      ),
    );

// Spinners never settle, so step the clock instead of pumpAndSettle.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Map<Object?, Object?> _payload(MethodCall call) =>
    (call.arguments as Map)['payload'] as Map;

/// A custom UI drawn only from the state a builder gets, with none of the SDK's widgets.
Widget _customStep(VerifyAttributeState state) => Column(
      children: [
        Text('custom ${state.title}'),
        if (state.destinationMessage != null)
          Text('custom ${state.destinationMessage}'),
        for (final name in state.inputNames)
          TextField(
            key: Key('custom-$name'),
            onChanged: (value) => state.onValueChanged(name, value),
          ),
        if (state.isLoading) const Text('custom loading'),
        if (state.error != null) Text('custom error ${state.error}'),
        if (state.successMessage != null)
          Text('custom ${state.successMessage}'),
        if (state.submitActionId != null)
          TextButton(
            key: const Key('custom-submit'),
            onPressed: () => state.submit(state.submitActionId!),
            child: const Text('Check'),
          ),
        if (state.resendActionId != null)
          TextButton(
            key: const Key('custom-resend'),
            onPressed: () => state.resend(state.resendActionId!),
            child: const Text('Again'),
          ),
        if (state.isAwaitingLink)
          TextButton(
            key: const Key('custom-done'),
            onPressed: state.done,
            child: const Text('Opened it'),
          ),
        if (state.onCancel != null)
          TextButton(
            key: const Key('custom-cancel'),
            onPressed: state.onCancel,
            child: const Text('Close'),
          ),
      ],
    );

void main() {
  late _Harness h;

  setUp(() {
    h = _Harness()..install();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('VerifyAttribute', () {
    testWidgets(
        'waits for the schema after provider initialization before starting',
        (tester) async {
      final schema = Completer<Object?>();
      h.schemaReply = schema;
      h.verifyResponses.add((_) => _codeStep());
      IAMException? error;
      await tester.pumpWidget(
        _app(VerifyAttribute(attribute: 'email', onError: (e) => error = e)),
      );
      await _settle(tester);
      expect(h.calls.any((call) => call.method == 'getUserSchema'), isTrue);
      expect(h.verifyCalls, isEmpty);
      expect(error, isNull);
      schema.complete({
        'email': {'type': 'email'},
      });
      await _settle(tester);
      expect(h.verifyCalls, hasLength(1));
      expect(error, isNull);
    });

    for (final firstAction in ['submit', 'resend']) {
      testWidgets(
          'ignores submit and resend while custom $firstAction is in flight',
          (tester) async {
        late VerifyAttributeState state;
        final reply = Completer<Object?>();
        h.verifyResponses
          ..add((_) => _codeStep())
          ..add((_) => reply.future)
          ..add((_) => _codeStep());
        await tester.pumpWidget(
          _app(
            VerifyAttribute(
              attribute: 'email',
              builder: (context, value) {
                state = value;
                return _customStep(value);
              },
            ),
          ),
        );
        await _settle(tester);
        state.onValueChanged('otp', '123456');
        final first = firstAction == 'submit'
            ? state.submit('action_email_verify')
            : state.resend('action_email_resend');
        await state.submit('action_email_verify', {'otp': '654321'});
        await state.resend('action_email_resend');
        // Even an invalid duplicate cannot change the error while the request is pending.
        await state.submit('action_email_verify', {});
        await tester.pump();
        expect(h.verifyCalls, hasLength(2));
        expect(state.isLoading, isTrue);
        expect(state.error, isNull);
        reply.complete({..._codeStep(), 'challengeToken': 'ct-2'});
        await first;
        await _settle(tester);
        await state.submit('action_email_verify', {'otp': '123456'});
        await _settle(tester);
        expect(h.verifyCalls, hasLength(3));
        expect(_payload(h.verifyCalls.last)['challengeToken'], 'ct-2');
      });
    }

    for (final custom in [false, true]) {
      testWidgets(
          'correcting an empty code allows submission with custom=$custom',
          (tester) async {
        h.verifyResponses
          ..add((_) => _codeStep())
          ..add((_) => _complete);
        await tester.pumpWidget(
          _app(
            VerifyAttribute(
              attribute: 'email',
              builder: custom ? (context, state) => _customStep(state) : null,
            ),
          ),
        );
        await _settle(tester);
        final submit = find.byKey(
          Key(
            custom ? 'custom-submit' : 'thunderid-action-action_email_verify',
          ),
        );
        await tester.tap(submit);
        await _settle(tester);
        expect(h.verifyCalls, hasLength(1));
        expect(
          find.textContaining('Enter the code to continue.'),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(Key(custom ? 'custom-otp' : 'thunderid-field-otp')),
          '123456',
        );
        await tester.tap(submit);
        await _settle(tester);
        expect(h.verifyCalls, hasLength(2));
        expect(_payload(h.verifyCalls.last)['inputs'], {'otp': '123456'});
        expect(find.textContaining('Email verified.'), findsOneWidget);
      });
    }

    testWidgets(
        'starts once per showing and renders the server step with its identifiers',
        (tester) async {
      h.verifyResponses.add((_) => _codeStep());
      await tester.pumpWidget(_app(const VerifyAttribute(attribute: 'email')));
      await _settle(tester);
      // A rebuild of the same showing, or the provider notifying it, does not start again.
      await tester.pumpWidget(_app(const VerifyAttribute(attribute: 'email')));
      await _settle(tester);
      ThunderIDProvider.of(tester.element(find.byType(BaseVerifyAttribute)))
          .mergeUserProfile(
        const model.UserProfile(
          id: 'user-1',
          attributes: {'email': 'ada@example.com'},
        ),
      );
      await _settle(tester);

      expect(h.verifyCalls, hasLength(1));
      expect(h.verifyCalls.single.arguments, {
        'attribute': 'email',
        'handle': AttributeVerification.defaultFlowHandle,
      });
      expect(find.byKey(const Key('thunderid-field-otp')), findsOneWidget);
      expect(
        find.byKey(const Key('thunderid-action-action_email_verify')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('thunderid-action-action_email_resend')),
        findsOneWidget,
      );
      final semantics = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .map((s) => s.properties.identifier);
      expect(
        semantics,
        containsAll(
          ['thunderid-field-otp', 'thunderid-action-action_email_resend'],
        ),
      );
    });

    testWidgets(
        'keeps the flow subtitle and shows the masked destination in addition',
        (tester) async {
      h.verifyResponses.add((_) => _codeStep());
      await tester.pumpWidget(_app(const VerifyAttribute(attribute: 'email')));
      await _settle(tester);

      expect(find.text('Verify your email'), findsOneWidget);
      expect(find.text('Enter the code we emailed you.'), findsOneWidget);
      expect(find.text('Sent to $_destination.'), findsOneWidget);
    });

    testWidgets(
        'without an application ID it reads no flow metadata and uses its own strings',
        (tester) async {
      h.verifyResponses.add((_) => _codeStep());
      await tester.pumpWidget(
        _app(const VerifyAttribute(attribute: 'email'), applicationId: null),
      );
      await _settle(tester);

      expect(h.calls.where((c) => c.method == 'getFlowMeta'), isEmpty);
      expect(find.text('Verify Email'), findsOneWidget);
      expect(find.text('Sent to $_destination.'), findsOneWidget);
    });

    testWidgets(
        'a refused start is reported with a generic message and not retried',
        (tester) async {
      h.verifyResponses.add(
        (_) => throw PlatformException(
          code: 'VERIFICATION_FAILED',
          message: 'body: secret',
        ),
      );
      IAMException? reported;
      await tester.pumpWidget(
        _app(
          VerifyAttribute(attribute: 'email', onError: (e) => reported = e),
        ),
      );
      await _settle(tester);
      await tester.pump(const Duration(seconds: 30));

      expect(h.verifyCalls, hasLength(1));
      expect(reported?.code, ThunderIDErrorCode.verificationFailed);
      expect(
        find.text('Verification failed. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('secret'), findsNothing);
    });

    testWidgets(
        'an attribute the schema does not declare verifiable starts nothing',
        (tester) async {
      h.schemaType = 'string';
      IAMException? reported;
      await tester.pumpWidget(
        _app(
          VerifyAttribute(attribute: 'email', onError: (e) => reported = e),
        ),
      );
      await _settle(tester);

      expect(h.verifyCalls, isEmpty);
      expect(reported?.code, ThunderIDErrorCode.invalidInput);
    });

    testWidgets('an empty code is caught before any request', (tester) async {
      h.verifyResponses.add((_) => _codeStep());
      await tester.pumpWidget(_app(const VerifyAttribute(attribute: 'email')));
      await _settle(tester);
      await tester
          .tap(find.byKey(const Key('thunderid-action-action_email_verify')));
      await _settle(tester);

      expect(h.verifyCalls, hasLength(1));
      expect(find.text('Enter the code to continue.'), findsOneWidget);
    });

    testWidgets('submits the code with the execution and challenge token',
        (tester) async {
      h.verifyResponses
        ..add((_) => _codeStep())
        ..add((_) => _complete);
      await tester.pumpWidget(_app(const VerifyAttribute(attribute: 'email')));
      await _settle(tester);
      await tester.enterText(
        find.byKey(const Key('thunderid-field-otp')),
        '123456',
      );
      await tester
          .tap(find.byKey(const Key('thunderid-action-action_email_verify')));
      await _settle(tester);

      expect(_payload(h.verifyCalls.last), {
        'flowId': 'exec-1',
        'actionId': 'action_email_verify',
        'inputs': {'otp': '123456'},
        'challengeToken': 'ct-1',
      });
    });

    testWidgets('resend submits no inputs and skips validation',
        (tester) async {
      h.verifyResponses
        ..add((_) => _codeStep())
        ..add((_) => _codeStep());
      await tester.pumpWidget(_app(const VerifyAttribute(attribute: 'email')));
      await _settle(tester);
      await tester.enterText(
        find.byKey(const Key('thunderid-field-otp')),
        '12',
      );
      await tester
          .tap(find.byKey(const Key('thunderid-action-action_email_resend')));
      await _settle(tester);

      expect(h.verifyCalls, hasLength(2));
      expect(_payload(h.verifyCalls.last)['actionId'], 'action_email_resend');
      expect(_payload(h.verifyCalls.last)['inputs'], isEmpty);
      expect(find.text('Enter the code to continue.'), findsNothing);
    });

    testWidgets(
        'a rejected code shows the error and keeps the destination and the form',
        (tester) async {
      h.verifyResponses
        ..add((_) => _codeStep())
        ..add(
          (_) => _codeStep(
            withAdditionalData: false,
            failureReason: 'Invalid code.',
          ),
        );
      await tester.pumpWidget(_app(const VerifyAttribute(attribute: 'email')));
      await _settle(tester);
      await tester.enterText(
        find.byKey(const Key('thunderid-field-otp')),
        '000000',
      );
      await tester
          .tap(find.byKey(const Key('thunderid-action-action_email_verify')));
      await _settle(tester);

      expect(find.text('Invalid code.'), findsNothing);
      expect(
        find.text('Verification failed. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Sent to $_destination.'), findsOneWidget);
      expect(find.byKey(const Key('thunderid-field-otp')), findsOneWidget);
      // The typed value is cleared for the next attempt.
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('thunderid-field-otp')))
            .controller
            ?.text,
        isEmpty,
      );
    });

    testWidgets(
        'a later step keeps only the destination, channel and code length from the step before',
        (tester) async {
      h.verifyResponses
        ..add((_) {
          final step = _codeStep();
          ((step['data'] as Map)['additionalData'] as Map)
            ..['channel'] = 'EMAIL'
            ..['stepOnly'] = 'x';
          return step;
        })
        ..add(
          (_) => _codeStep(
            withAdditionalData: false,
            failureReason: 'Invalid code.',
          ),
        );
      late VerifyAttributeState state;
      await tester.pumpWidget(
        _app(
          BaseVerifyAttribute(
            attribute: 'email',
            builder: (context, s) {
              state = s;
              return const SizedBox();
            },
          ),
        ),
      );
      await _settle(tester);
      expect(state.currentStep?.additionalData, containsPair('stepOnly', 'x'));

      await state.submit('action_email_verify', {'otp': '000000'});
      await _settle(tester);
      expect(state.error, 'Verification failed. Please try again.');
      expect(state.currentStep?.additionalData, {
        'maskedDestination': _destination,
        'otpLength': '6',
        'channel': 'EMAIL',
      });
    });

    testWidgets('COMPLETE re-reads the profile even without a callback',
        (tester) async {
      h.verifyResponses
        ..add((_) => _codeStep())
        ..add((_) => _complete);
      await tester.pumpWidget(_app(const VerifyAttribute(attribute: 'email')));
      await _settle(tester);
      final readsBefore = h.profileReads;
      await tester.enterText(
        find.byKey(const Key('thunderid-field-otp')),
        '123456',
      );
      await tester
          .tap(find.byKey(const Key('thunderid-action-action_email_verify')));
      await _settle(tester);

      expect(h.profileReads, readsBefore + 1);
      expect(find.text('Email verified.'), findsOneWidget);
    });

    testWidgets('onComplete runs once the profile was read again',
        (tester) async {
      h.verifyResponses.add((_) => _complete);
      int? readsAtComplete;
      await tester.pumpWidget(
        _app(
          VerifyAttribute(
            attribute: 'email',
            onComplete: () => readsAtComplete = h.profileReads,
          ),
        ),
      );
      final readsBefore = h.profileReads;
      await _settle(tester);

      expect(readsAtComplete, isNotNull);
      expect(readsAtComplete, greaterThan(readsBefore));
    });

    testWidgets(
        'a link step shows where it went and Done re-reads the profile once, without polling',
        (tester) async {
      h.verifyResponses.add((_) => _linkStep);
      await tester.pumpWidget(_app(const VerifyAttribute(attribute: 'email')));
      await _settle(tester);
      expect(
        find.text(
          'We sent a verification link to $_destination. Open it, then select Done.',
        ),
        findsOneWidget,
      );
      final readsBefore = h.profileReads;
      await tester.pump(const Duration(minutes: 1));
      expect(h.profileReads, readsBefore);
      expect(h.verifyCalls, hasLength(1));

      await tester
          .tap(find.byKey(const Key('thunderid-action-verificationDone')));
      await _settle(tester);
      expect(h.profileReads, readsBefore + 1);
      expect(h.verifyCalls, hasLength(1));
    });

    testWidgets('an ERROR step is a refusal reported without retrying',
        (tester) async {
      h.verifyResponses.add(
        (_) => {
          'flowId': 'exec-1',
          'flowStatus': 'ERROR',
          'failureReason': 'Too many attempts.',
        },
      );
      IAMException? reported;
      await tester.pumpWidget(
        _app(
          VerifyAttribute(attribute: 'email', onError: (e) => reported = e),
        ),
      );
      await _settle(tester);

      expect(find.text('Too many attempts.'), findsNothing);
      expect(
        find.text('Verification failed. Please try again.'),
        findsOneWidget,
      );
      expect(reported?.code, ThunderIDErrorCode.verificationFailed);
      expect(reported?.message, isNot(contains('Too many')));
      expect(h.verifyCalls, hasLength(1));
    });
  });

  group('UserProfile verification', () {
    Future<void> showProfile(WidgetTester tester) async {
      await tester.pumpWidget(_app(const UserProfile()));
      await _settle(tester);
    }

    for (final refusal in [
      'readonly',
      'verified',
      'unknown',
      'editing',
      'type',
    ]) {
      testWidgets('custom profile cannot open verification when $refusal',
          (tester) async {
        late UserProfileState state;
        if (refusal == 'readonly') h.isReadOnly = true;
        if (refusal == 'verified') {
          h.verifiedAttributes = {
            'email': {'verifiedAt': '2026-10-29T10:00:00Z'},
          };
        }
        if (refusal == 'unknown') h.verifiedAttributes = null;
        if (refusal == 'type') h.schemaType = 'string';
        await tester.pumpWidget(
          _app(
            BaseUserProfile(
              builder: (context, value) {
                state = value;
                return const SizedBox();
              },
            ),
          ),
        );
        await _settle(tester);
        if (refusal == 'editing') {
          state.edit('email');
          await tester.pump();
        }
        expect(state.canVerify('email'), isFalse);
        state.verify('email');
        await tester.pump();
        expect(state.verifyingField, isNull);
        expect(h.verifyCalls, isEmpty);
      });
    }

    testWidgets('shows Unverified and a Verify action for a stored email',
        (tester) async {
      await showProfile(tester);
      expect(find.bySemanticsLabel('Unverified'), findsNWidgets(2));
      expect(find.byKey(const Key('thunderid-verify-email')), findsOneWidget);
      final identifiers = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .map((s) => s.properties.identifier);
      expect(
        identifiers,
        containsAll([
          'thunderid-verify-email',
          'thunderid-verification-status-email',
        ]),
      );
      expect(h.verifyCalls, isEmpty);
    });

    testWidgets(
        'shows neither status nor Verify when the server does not report verification',
        (tester) async {
      h.verifiedAttributes = null;
      await showProfile(tester);
      expect(
        find.bySemanticsLabel(RegExp('verified', caseSensitive: false)),
        findsNothing,
      );
      expect(find.byKey(const Key('thunderid-verify-email')), findsNothing);
    });

    testWidgets('a read-only profile shows the status but offers no Verify',
        (tester) async {
      h.isReadOnly = true;
      await showProfile(tester);
      expect(find.bySemanticsLabel('Unverified'), findsNWidgets(2));
      expect(find.byKey(const Key('thunderid-verify-email')), findsNothing);
    });

    testWidgets('exposes when a value was verified to assistive technology',
        (tester) async {
      h.verifiedAttributes = {
        'email': {'verifiedAt': '2026-10-25T10:00:00Z'},
      };
      await showProfile(tester);
      expect(
        find.bySemanticsLabel(RegExp(r'^Verified\. Verified on .*2026')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('thunderid-verify-email')), findsNothing);
    });

    testWidgets('Verify opens the verification under the row', (tester) async {
      h.verifyResponses.add((_) => _codeStep());
      await showProfile(tester);
      await tester.tap(find.byKey(const Key('thunderid-verify-email')));
      await _settle(tester);
      expect(
        h.verifyCalls.single.arguments,
        containsPair('attribute', 'email'),
      );
      expect(find.byKey(const Key('thunderid-field-otp')), findsOneWidget);
    });

    testWidgets(
        'a completed verification shows Verified from the one profile read',
        (tester) async {
      h.verifyResponses
        ..add((_) => _codeStep())
        ..add((_) {
          h.verifiedAttributes = {
            'email': {'verifiedAt': '2026-10-26T10:00:00Z'},
          };
          return _complete;
        });
      await showProfile(tester);
      await tester.tap(find.byKey(const Key('thunderid-verify-email')));
      await _settle(tester);
      await tester.enterText(
        find.byKey(const Key('thunderid-field-otp')),
        '123456',
      );
      final readsBefore = h.profileReads;
      await tester
          .tap(find.byKey(const Key('thunderid-action-action_email_verify')));
      await _settle(tester);

      expect(h.profileReads, readsBefore + 1);
      expect(find.bySemanticsLabel(RegExp(r'^Verified\.')), findsOneWidget);
      expect(find.byKey(const Key('thunderid-verify-email')), findsNothing);
    });

    testWidgets(
        'status follows the stored value: none while a save is in flight or after it fails',
        (tester) async {
      late UserProfileState state;
      final save = Completer<Object?>();
      h.onUpdateProfile = (_) => save.future;
      await tester.pumpWidget(
        _app(
          BaseUserProfile(
            builder: (context, s) {
              state = s;
              return const SizedBox();
            },
          ),
        ),
      );
      await _settle(tester);
      expect(
        state.verificationStatus('email'),
        AttributeVerificationStatus.unverified,
      );

      state.edit('email');
      state.setFieldValue('email', 'new@example.com');
      await tester.pump();
      expect(state.verificationStatus('email'), isNull);
      expect(state.canVerify('email'), isFalse);

      unawaited(state.save('email'));
      await tester.pump();
      expect(state.verificationStatus('email'), isNull);

      save.completeError(
        PlatformException(
          code: 'SERVER_ERROR',
          message: 'PUT /users/me private detail',
        ),
      );
      await _settle(tester);
      expect(state.fieldError('email'), 'Failed to save changes.');
      expect(state.verificationStatus('email'), isNull);
      expect(state.canVerify('email'), isFalse);

      state.cancel('email');
      await tester.pump();
      expect(
        state.verificationStatus('email'),
        AttributeVerificationStatus.unverified,
      );
    });

    testWidgets(
        'saving a changed email opens its verification; a changed mobile does not',
        (tester) async {
      late UserProfileState state;
      h.onUpdateProfile = (call) {
        final attributes =
            ((call.arguments as Map)['payload'] as Map).cast<String, Object?>();
        return {
          'id': 'user-1',
          'attributes': attributes,
          'verifiedAttributes': <String, Object?>{},
        };
      };
      await tester.pumpWidget(
        _app(
          BaseUserProfile(
            builder: (context, s) {
              state = s;
              return const SizedBox();
            },
          ),
        ),
      );
      await _settle(tester);

      state.edit('mobile_number');
      state.setFieldValue('mobile_number', '+94771111111');
      await state.save('mobile_number');
      await _settle(tester);
      expect(state.verifyingField, isNull);

      state.edit('email');
      state.setFieldValue('email', 'new@example.com');
      await state.save('email');
      await _settle(tester);
      expect(state.verifyingField, 'email');

      // Editing the value again closes its verification.
      state.edit('email');
      await tester.pump();
      expect(state.verifyingField, isNull);
    });
  });

  group('builder (custom UI)', () {
    testWidgets(
        'BaseVerifyAttribute hands the step, its values, submit and resend to a builder',
        (tester) async {
      h.verifyResponses
        ..add((_) => _codeStep())
        ..add((_) => _codeStep())
        ..add((_) => _complete);
      await tester.pumpWidget(
        _app(
          BaseVerifyAttribute(
            attribute: 'email',
            builder: (context, state) => _customStep(state),
          ),
        ),
      );
      await _settle(tester);

      expect(h.verifyCalls, hasLength(1));
      expect(find.byType(FlowForm), findsNothing);
      expect(find.text('custom Verify your email'), findsOneWidget);
      expect(find.text('custom Sent to $_destination.'), findsOneWidget);
      expect(find.byKey(const Key('custom-cancel')), findsNothing);

      await tester.enterText(find.byKey(const Key('custom-otp')), '12');
      await tester.tap(find.byKey(const Key('custom-resend')));
      await _settle(tester);
      expect(
        _payload(h.verifyCalls.last),
        containsPair('actionId', 'action_email_resend'),
      );
      expect(_payload(h.verifyCalls.last)['inputs'], isEmpty);

      await tester.enterText(find.byKey(const Key('custom-otp')), '123456');
      await tester.tap(find.byKey(const Key('custom-submit')));
      await _settle(tester);
      expect(
        _payload(h.verifyCalls.last),
        containsPair('actionId', 'action_email_verify'),
      );
      expect(_payload(h.verifyCalls.last)['inputs'], {'otp': '123456'});
      expect(find.text('custom Email verified.'), findsOneWidget);
    });

    testWidgets(
        'a builder shows loading and the translated error of a rejected code',
        (tester) async {
      final reply = Completer<Object?>();
      h.verifyResponses
        ..add((_) => _codeStep())
        ..add((_) => reply.future);
      await tester.pumpWidget(
        _app(
          BaseVerifyAttribute(
            attribute: 'email',
            builder: (context, state) => _customStep(state),
          ),
        ),
      );
      await _settle(tester);
      await tester.enterText(find.byKey(const Key('custom-otp')), '000000');
      await tester.tap(find.byKey(const Key('custom-submit')));
      await tester.pump();
      expect(find.text('custom loading'), findsOneWidget);

      final rejected = _codeStep(withAdditionalData: false);
      rejected['error'] = {
        'message': {
          'key': 'verification.self.code.invalid',
          'defaultValue': 'Invalid OTP',
        },
      };
      reply.complete(rejected);
      await _settle(tester);

      expect(find.text('custom loading'), findsNothing);
      expect(find.text('custom error That code is not right.'), findsOneWidget);
      expect(find.text('custom Sent to $_destination.'), findsOneWidget);
    });

    testWidgets(
        'a connected VerifyAttribute hands the same state to a builder, with onCancel',
        (tester) async {
      h.verifyResponses.add((_) => _codeStep());
      var cancels = 0;
      await tester.pumpWidget(
        _app(
          VerifyAttribute(
            attribute: 'email',
            onCancel: () => cancels++,
            builder: (context, state) => _customStep(state),
          ),
        ),
      );
      await _settle(tester);

      expect(h.verifyCalls, hasLength(1));
      expect(find.byType(FlowForm), findsNothing);
      expect(
        find.byKey(const Key('thunderid-action-verificationCancel')),
        findsNothing,
      );
      expect(find.text('custom Verify your email'), findsOneWidget);
      await tester.tap(find.byKey(const Key('custom-cancel')));
      expect(cancels, 1);
    });

    testWidgets(
        'a connected builder gets the completed state once the profile was read again',
        (tester) async {
      h.verifyResponses
        ..add((_) => _codeStep())
        ..add((_) => _complete);
      int? readsAtComplete;
      await tester.pumpWidget(
        _app(
          VerifyAttribute(
            attribute: 'email',
            onComplete: () => readsAtComplete = h.profileReads,
            builder: (context, state) => _customStep(state),
          ),
        ),
      );
      await _settle(tester);
      final readsBefore = h.profileReads;
      await tester.enterText(find.byKey(const Key('custom-otp')), '123456');
      await tester.tap(find.byKey(const Key('custom-submit')));
      await _settle(tester);

      expect(readsAtComplete, readsBefore + 1);
      expect(find.text('custom Email verified.'), findsOneWidget);
      expect(find.byKey(const Key('custom-submit')), findsNothing);
    });

    testWidgets('a connected builder Done re-reads the profile once for a link',
        (tester) async {
      h.verifyResponses.add((_) => _linkStep);
      var dones = 0;
      await tester.pumpWidget(
        _app(
          VerifyAttribute(
            attribute: 'email',
            onDone: () => dones++,
            builder: (context, state) => _customStep(state),
          ),
        ),
      );
      await _settle(tester);
      final readsBefore = h.profileReads;
      await tester.tap(find.byKey(const Key('custom-done')));
      await _settle(tester);

      expect(h.profileReads, readsBefore + 1);
      expect(dones, 1);
      expect(h.verifyCalls, hasLength(1));
    });

    testWidgets(
        'a BaseUserProfile builder shows each status, starts verification and sees the new status',
        (tester) async {
      h.verifyResponses
        ..add((_) => _codeStep())
        ..add((_) {
          h.verifiedAttributes = {
            'email': {'verifiedAt': '2026-10-26T10:00:00Z'},
          };
          return _complete;
        });
      await tester.pumpWidget(
        _app(
          BaseUserProfile(
            builder: (context, state) => Column(
              children: [
                Text('email ${state.verificationStatus('email')?.name}'),
                if (state.canVerify('email'))
                  TextButton(
                    key: const Key('custom-verify'),
                    onPressed: () => state.verify('email'),
                    child: const Text('Check email'),
                  ),
                if (state.verifyingField == 'email')
                  VerifyAttribute(
                    attribute: 'email',
                    builder: (context, step) => _customStep(step),
                  ),
              ],
            ),
          ),
        ),
      );
      await _settle(tester);
      expect(find.text('email unverified'), findsOneWidget);
      expect(h.verifyCalls, isEmpty);

      await tester.tap(find.byKey(const Key('custom-verify')));
      await _settle(tester);
      expect(h.verifyCalls, hasLength(1));
      final readsBefore = h.profileReads;
      await tester.enterText(find.byKey(const Key('custom-otp')), '123456');
      await tester.tap(find.byKey(const Key('custom-submit')));
      await _settle(tester);

      expect(
        h.verifyCalls
            .where((c) => (c.arguments as Map).containsKey('attribute')),
        hasLength(1),
      );
      expect(h.profileReads, readsBefore + 1);
      expect(find.text('email verified'), findsOneWidget);
    });
  });
}
