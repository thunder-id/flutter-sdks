// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/models/user_profile.dart' as model;
import 'package:thunderid_flutter/thunderid_flutter.dart';

const _channel = MethodChannel('dev.thunderid/sdk');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];
  Object? Function(MethodCall call)? verifyHandler;

  setUp(() {
    calls.clear();
    verifyHandler = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
          return true;
        case 'verifyAttribute':
          return verifyHandler?.call(call) ??
              <Object?, Object?>{
                'flowId': 'exec-1',
                'flowStatus': 'PROMPT_ONLY',
              };
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  Future<ThunderIDClient> initialized() async {
    final client = ThunderIDClient();
    await client.initialize(
      const ThunderIDConfig(
        baseUrl: 'https://localhost:8090',
        clientId: 'test',
      ),
    );
    calls.clear();
    return client;
  }

  group('ThunderIDClient.verifyAttribute', () {
    test(
        'a start sends the attribute and the default handle, and no user or application ID',
        () async {
      final client = await initialized();
      await client.verifyAttribute(attribute: 'email');
      expect(calls.single.method, 'verifyAttribute');
      expect(calls.single.arguments, {
        'attribute': 'email',
        'handle': 'default-self-attribute-verification-flow',
      });
    });

    test('a start names another handle', () async {
      final client = await initialized();
      await client.verifyAttribute(
        attribute: 'mobile_number',
        handle: 'custom',
      );
      expect(calls.single.arguments, {
        'attribute': 'mobile_number',
        'handle': 'custom',
      });
    });

    test('a blank handle is passed through for the native SDK to refuse',
        () async {
      verifyHandler = (call) => throw PlatformException(
            code: 'INVALID_INPUT',
            message: 'needs a handle',
          );
      final client = await initialized();
      await expectLater(
        client.verifyAttribute(attribute: 'email', handle: ''),
        throwsA(
          isA<IAMException>()
              .having((e) => e.code, 'code', ThunderIDErrorCode.invalidInput),
        ),
      );
      expect((calls.single.arguments as Map)['handle'], '');
    });

    test('a continuation sends only the payload', () async {
      final client = await initialized();
      await client.verifyAttribute(
        payload: const EmbeddedSignInPayload(
          flowId: 'exec-1',
          actionId: 'action_email_verify',
          inputs: {'otp': '123456'},
          challengeToken: 'ct-1',
        ),
      );
      expect(calls.single.arguments, {
        'payload': {
          'flowId': 'exec-1',
          'actionId': 'action_email_verify',
          'inputs': {'otp': '123456'},
          'challengeToken': 'ct-1',
        },
      });
    });

    test('decodes the step the native SDK returns', () async {
      verifyHandler = (_) => <Object?, Object?>{
            'flowId': 'exec-1',
            'flowStatus': 'COMPLETE',
          };
      final client = await initialized();
      final response = await client.verifyAttribute(attribute: 'email');
      expect(response.flowStatus, FlowStatus.complete);
      expect(response.flowId, 'exec-1');
    });

    test('a server refusal is VERIFICATION_FAILED', () async {
      verifyHandler = (_) => throw PlatformException(
            code: 'VERIFICATION_FAILED',
            message: 'refused',
          );
      final client = await initialized();
      await expectLater(
        client.verifyAttribute(attribute: 'email'),
        throwsA(
          isA<IAMException>().having(
            (e) => e.code,
            'code',
            ThunderIDErrorCode.verificationFailed,
          ),
        ),
      );
      expect(
        ThunderIDErrorCode.verificationFailed.value,
        'VERIFICATION_FAILED',
      );
    });

    test('fails before initialization without a channel call', () async {
      final client = ThunderIDClient();
      await expectLater(
        client.verifyAttribute(attribute: 'email'),
        throwsA(
          isA<IAMException>().having(
            (e) => e.code,
            'code',
            ThunderIDErrorCode.sdkNotInitialized,
          ),
        ),
      );
      expect(calls, isEmpty);
    });
  });

  group('FlowType', () {
    test('FlowType.selfService is SELF_SERVICE', () {
      expect(FlowType.selfService.value, 'SELF_SERVICE');
    });
  });

  group('UserProfile.verifiedAttributes', () {
    test('absent means unknown, an empty map means none verified', () {
      expect(model.UserProfile.fromMap({'id': 'u'}).verifiedAttributes, isNull);
      expect(
        model.UserProfile.fromMap(
          {'id': 'u', 'verifiedAttributes': <Object?, Object?>{}},
        ).verifiedAttributes,
        isEmpty,
      );
    });

    test('decodes each record', () {
      final profile = model.UserProfile.fromMap({
        'id': 'u',
        'verifiedAttributes': <Object?, Object?>{
          'email': <Object?, Object?>{'verifiedAt': '2026-10-25T10:00:00Z'},
        },
      });
      expect(profile.verifiedAttributes, {
        'email': const VerifiedAttribute(verifiedAt: '2026-10-25T10:00:00Z'),
      });
    });
  });

  group('AttributeVerification', () {
    const schema = {
      'email': model.AttributeSchema(type: 'email'),
      'mobile_number': model.AttributeSchema(type: 'MOBILE'),
      'emails': model.AttributeSchema(type: 'array'),
      'name': model.AttributeSchema(type: 'string'),
    };

    test('only top-level email and mobile properties are verifiable', () {
      expect(
        AttributeVerification.isVerifiableAttribute('email', schema),
        isTrue,
      );
      expect(
        AttributeVerification.isVerifiableAttribute('mobile_number', schema),
        isTrue,
      );
      expect(
        AttributeVerification.isVerifiableAttribute('emails', schema),
        isFalse,
      );
      expect(
        AttributeVerification.isVerifiableAttribute('name', schema),
        isFalse,
      );
      expect(
        AttributeVerification.isVerifiableAttribute('missing', schema),
        isFalse,
      );
      expect(
        AttributeVerification.isVerifiableAttribute('email', null),
        isFalse,
      );
    });

    test('only an email opens verification after a save', () {
      expect(AttributeVerification.opensAfterSave('email'), isTrue);
      expect(AttributeVerification.opensAfterSave('mobile'), isFalse);
    });
  });

  group('verificationStatusOf', () {
    AttributeVerificationStatus? status({
      Object? value = 'ada@example.com',
      String? type = 'email',
      Map<String, VerifiedAttribute>? verified = const {},
      bool isEditing = false,
    }) =>
        verificationStatusOf(
          name: 'email',
          schemaType: type,
          storedValue: value,
          verified: verified,
          isEditing: isEditing,
        );

    test('reads the status from verifiedAttributes only', () {
      expect(status(), AttributeVerificationStatus.unverified);
      expect(
        status(verified: const {'email': VerifiedAttribute()}),
        AttributeVerificationStatus.verified,
      );
    });

    test('shows nothing when the server does not report verification', () {
      expect(status(verified: null), isNull);
    });

    test('shows nothing while the value is edited or saved', () {
      expect(status(isEditing: true), isNull);
    });

    test('shows nothing for another type or an empty value', () {
      expect(status(type: 'string'), isNull);
      expect(status(value: ''), isNull);
      expect(status(value: ['a@example.com']), isNull);
    });
  });

  group('shouldVerifyAfterSave', () {
    const schema = {
      'email': model.AttributeSchema(type: 'email'),
      'mobile_number': model.AttributeSchema(type: 'mobile'),
    };

    model.UserProfile saved(
      Map<String, dynamic> attributes,
      Map<String, VerifiedAttribute>? verified,
    ) =>
        model.UserProfile(
          id: 'u',
          attributes: attributes,
          verifiedAttributes: verified,
        );

    test('opens for a changed, unverified email', () {
      expect(
        shouldVerifyAfterSave(
          name: 'email',
          schema: schema,
          previousValue: 'old@example.com',
          saved: saved({'email': 'new@example.com'}, const {}),
        ),
        isTrue,
      );
    });

    test(
        'does not open for a mobile number, an unchanged value, a verified value or an unknown status',
        () {
      expect(
        shouldVerifyAfterSave(
          name: 'mobile_number',
          schema: schema,
          previousValue: '+1',
          saved: saved({'mobile_number': '+2'}, const {}),
        ),
        isFalse,
      );
      expect(
        shouldVerifyAfterSave(
          name: 'email',
          schema: schema,
          previousValue: 'same@example.com',
          saved: saved({'email': 'same@example.com'}, const {}),
        ),
        isFalse,
      );
      expect(
        shouldVerifyAfterSave(
          name: 'email',
          schema: schema,
          previousValue: 'old@example.com',
          saved: saved(
            {'email': 'new@example.com'},
            const {'email': VerifiedAttribute()},
          ),
        ),
        isFalse,
      );
      expect(
        shouldVerifyAfterSave(
          name: 'email',
          schema: schema,
          previousValue: 'old@example.com',
          saved: saved({'email': 'new@example.com'}, null),
        ),
        isFalse,
      );
    });
  });

  group('splitHeadings', () {
    test('takes the first two top-level headings and leaves the rest', () {
      final result = splitHeadings([
        {'type': 'TEXT', 'variant': 'HEADING_1', 'label': 'Title'},
        {'type': 'TEXT', 'variant': 'HEADING_6', 'label': 'Subtitle'},
        {'type': 'BLOCK', 'components': <Object?>[]},
        {'type': 'TEXT', 'variant': 'HEADING_2', 'label': 'Third'},
      ]);
      expect(result.title, 'Title');
      expect(result.subtitle, 'Subtitle');
      expect(result.rest.map((c) => c['type']), ['BLOCK', 'TEXT']);
    });
  });
}
