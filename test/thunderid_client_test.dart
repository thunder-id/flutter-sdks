// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/channel/thunderid_channel.dart';
import 'package:thunderid_flutter/src/models/flow_models.dart';
import 'package:thunderid_flutter/src/models/thunderid_config.dart';
import 'package:thunderid_flutter/src/models/thunderid_error.dart';
import 'package:thunderid_flutter/src/models/user.dart';
import 'package:thunderid_flutter/src/thunderid_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ThunderIDClient client;
  final List<MethodCall> log = [];

  setUp(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.thunderid/sdk'),
      (call) async {
        log.add(call);
        switch (call.method) {
          case 'initialize':
            return true;
          case 'isSignedIn':
            return false;
          case 'signOut':
            return '/';
          case 'getAccessToken':
            return 'mock-access-token';
          case 'getUserProfile':
            return <Object?, Object?>{
              'id': 'user-1',
              'isReadOnly': false,
              'attributes': <Object?, Object?>{
                'email': 'ada@example.com',
                'name': <Object?, Object?>{'givenName': 'Ada'},
              },
            };
          case 'getUserSchema':
            return <Object?, Object?>{
              'email': <Object?, Object?>{
                'type': 'STRING',
                'required': true,
                'displayName': 'Email',
              },
            };
          case 'updateUserProfile':
            final updateArgs = call.arguments as Map<Object?, Object?>;
            return <Object?, Object?>{
              'id': 'user-1',
              'isReadOnly': false,
              'attributes': updateArgs['payload'],
            };
          case 'updateUserCredentials':
            return null;
          case 'continueFederatedAuth':
            final args = call.arguments as Map<Object?, Object?>;
            if (args['redirectUrl'] == 'https://cancel.example') {
              throw PlatformException(code: 'FEDERATED_AUTH_CANCELLED', message: 'cancelled');
            }
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
    client = ThunderIDClient();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dev.thunderid/sdk'), null);
  });

  group('initialization', () {
    test('initialize calls native channel with config', () async {
      const config = ThunderIDConfig(
        baseUrl: 'https://localhost:8090',
        clientId: 'test-client',
      );
      final result = await client.initialize(config);
      expect(result, true);
      expect(log.any((c) => c.method == 'initialize'), true);
    });

    test('initialize defaults transport and profile flags safely', () async {
      const config = ThunderIDConfig(baseUrl: 'https://localhost:8090');
      await client.initialize(config);

      final args = log.firstWhere((c) => c.method == 'initialize').arguments
          as Map<Object?, Object?>;
      expect(args['fetchUserProfile'], true);
      expect(args['allowInsecureConnections'], false);
    });

    test('initialize forwards allowInsecureConnections when opted in', () async {
      const config = ThunderIDConfig(
        baseUrl: 'https://localhost:8090',
        allowInsecureConnections: true,
      );
      await client.initialize(config);

      final args = log.firstWhere((c) => c.method == 'initialize').arguments
          as Map<Object?, Object?>;
      expect(args['allowInsecureConnections'], true);
    });

    test('initialize throws ALREADY_INITIALIZED when called twice', () async {
      const config = ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'test');
      await client.initialize(config);
      expect(
        () => client.initialize(config),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.alreadyInitialized)),
      );
    });

    test('operations before init throw SDK_NOT_INITIALIZED', () {
      expect(
        () => client.isSignedIn(),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.sdkNotInitialized)),
      );
    });
  });

  group('isLoading', () {
    test('isLoading returns false when not active', () async {
      const config = ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'test');
      await client.initialize(config);
      expect(client.isLoading(), false);
    });
  });

  group('user profile', () {
    const config = ThunderIDConfig(baseUrl: 'https://localhost:8090');

    test('getUserProfile decodes the /users/me envelope', () async {
      await client.initialize(config);
      final profile = await client.getUserProfile();

      expect(profile.id, 'user-1');
      expect(profile.isReadOnly, false);
      expect(profile.attributes['email'], 'ada@example.com');
      // Nested channel maps arrive as Map<Object?, Object?> and must be deep-cast.
      expect(profile.attributes['name'], isA<Map<String, dynamic>>());
    });

    test('getUserSchema decodes the attribute map', () async {
      await client.initialize(config);
      final schema = await client.getUserSchema();

      expect(schema.keys, ['email']);
      expect(schema['email']?.required, true);
      expect(schema['email']?.displayName, 'Email');
    });

    test('updateUserProfile wraps the payload and returns the saved profile', () async {
      await client.initialize(config);
      final profile = await client.updateUserProfile({'displayName': 'Grace'});

      final call = log.firstWhere((c) => c.method == 'updateUserProfile');
      final args = call.arguments as Map<Object?, Object?>;
      expect(args['payload'], {'displayName': 'Grace'});
      expect(args.containsKey('userId'), false);
      expect(profile.attributes['displayName'], 'Grace');
    });

    test('updateUserCredentials sends the attribute and new value', () async {
      await client.initialize(config);
      await client.updateUserCredentials(attribute: 'pin', newValue: '4242');

      final call = log.firstWhere((c) => c.method == 'updateUserCredentials');
      final args = call.arguments as Map<Object?, Object?>;
      expect(args['attribute'], 'pin');
      expect(args['newValue'], '4242');
    });

    test('updateUserCredentials defaults attribute to password', () async {
      await client.initialize(config);
      await client.updateUserCredentials(newValue: 'n3wP@ss');

      final call = log.firstWhere((c) => c.method == 'updateUserCredentials');
      final args = call.arguments as Map<Object?, Object?>;
      expect(args['attribute'], 'password');
      expect(args.containsKey('currentValue'), false);
    });

    test('updateUserCredentials sends the current value only when it is not empty', () async {
      await client.initialize(config);
      await client.updateUserCredentials(currentValue: '0ldP@ss', newValue: 'n3wP@ss');
      await client.updateUserCredentials(currentValue: '', newValue: 'n3wP@ss');

      final calls = log.where((c) => c.method == 'updateUserCredentials').toList();
      final withCurrent = calls[0].arguments as Map<Object?, Object?>;
      expect(withCurrent['currentValue'], '0ldP@ss');
      expect(withCurrent['newValue'], 'n3wP@ss');
      expect(withCurrent.containsKey('attributes'), false);
      final withoutCurrent = calls[1].arguments as Map<Object?, Object?>;
      expect(withoutCurrent.containsKey('currentValue'), false);
    });

    test('updateUserCredentials refuses a blank name or new value before any request', () async {
      await client.initialize(config);

      await expectLater(
        client.updateUserCredentials(attribute: ' ', newValue: 'n3wP@ss'),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.invalidInput)),
      );
      await expectLater(
        client.updateUserCredentials(currentValue: '0ldP@ss', newValue: ''),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.invalidInput)),
      );
      expect(log.where((c) => c.method == 'updateUserCredentials'), isEmpty);
    });

    test('a refused updateUserCredentials carries the server error and challenge', () async {
      await client.initialize(config);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.thunderid/sdk'),
        (call) async => throw PlatformException(
          code: 'AUTHENTICATION_FAILED',
          message: '[AUTHENTICATION_FAILED] Unauthorized',
          details: <String, Object?>{
            'serverError': <String, Object?>{
              'code': 'AUTH-4011',
              'message': <String, Object?>{
                'key': 'error.security.recent_authentication_required',
                'defaultValue': 'Recent authentication required',
              },
            },
            'authenticationChallenge': <String, Object?>{
              'error': 'insufficient_user_authentication',
              'errorDescription': 'A more recent authentication is required',
              'maxAge': 300,
            },
          },
        ),
      );

      await expectLater(
        client.updateUserCredentials(newValue: 'n3wP@ss'),
        throwsA(
          isA<IAMException>()
              .having((e) => e.code, 'code', ThunderIDErrorCode.stepUpRequired)
              .having((e) => e.message, 'message', 'Recent authentication required')
              .having((e) => e.serverError?.code, 'serverError.code', 'AUTH-4011')
              .having((e) => e.authenticationChallenge?.maxAge, 'maxAge', 300)
              .having(
                (e) => e.authenticationChallenge?.errorDescription,
                'errorDescription',
                'A more recent authentication is required',
              ),
        ),
      );
    });

    test('setCachedUser writes merged claims back to the native cache', () async {
      await client.initialize(config);
      await client.setCachedUser(
        const User({'sub': 'user-1', 'displayName': 'Grace'}),
      );

      final call = log.firstWhere((c) => c.method == 'setCachedUser');
      final args = call.arguments as Map<Object?, Object?>;
      expect(args['user'], {'sub': 'user-1', 'displayName': 'Grace'});
    });

    test('profile calls before init throw SDK_NOT_INITIALIZED', () {
      expect(
        () => client.getUserSchema(),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.sdkNotInitialized)),
      );
    });
  });

  group('ThunderIDErrorCode', () {
    test('fromString parses known codes', () {
      expect(ThunderIDErrorCode.fromString('AUTHENTICATION_FAILED'), ThunderIDErrorCode.authenticationFailed);
      expect(ThunderIDErrorCode.fromString('SESSION_EXPIRED'), ThunderIDErrorCode.sessionExpired);
      expect(ThunderIDErrorCode.fromString('SDK_NOT_INITIALIZED'), ThunderIDErrorCode.sdkNotInitialized);
      expect(ThunderIDErrorCode.fromString('STEP_UP_REQUIRED'), ThunderIDErrorCode.stepUpRequired);
      expect(ThunderIDErrorCode.stepUpRequired.value, 'STEP_UP_REQUIRED');
    });

    test('fromString returns unknownError for unknown code', () {
      expect(ThunderIDErrorCode.fromString('NOT_REAL'), ThunderIDErrorCode.unknownError);
    });

    test('IAMException toString includes code', () {
      const e = IAMException(ThunderIDErrorCode.networkError, 'connection refused');
      expect(e.toString(), contains('NETWORK_ERROR'));
    });
  });

  group('ThunderIDConfig', () {
    test('toMap includes required fields', () {
      const config = ThunderIDConfig(
        baseUrl: 'https://localhost:8090',
        clientId: 'client-123',
        scopes: ['openid', 'profile'],
      );
      final map = config.toMap();
      expect(map['baseUrl'], 'https://localhost:8090');
      expect(map['clientId'], 'client-123');
      expect(map['scopes'], ['openid', 'profile']);
    });

    test('toMap omits null optional fields', () {
      const config = ThunderIDConfig(baseUrl: 'https://localhost:8090');
      final map = config.toMap();
      expect(map.containsKey('clientId'), false);
      expect(map.containsKey('afterSignInUrl'), false);
    });

    test('attestation defaults to disabled', () {
      const config = ThunderIDConfig(baseUrl: 'https://localhost:8090');
      final map = config.toMap();
      expect(map['attestationEnabled'], false);
      expect(map.containsKey('cloudProjectNumber'), false);
    });

    test('toMap includes attestation fields when set', () {
      const config = ThunderIDConfig(
        baseUrl: 'https://localhost:8090',
        attestationEnabled: true,
        cloudProjectNumber: 123456789,
      );
      final map = config.toMap();
      expect(map['attestationEnabled'], true);
      expect(map['cloudProjectNumber'], 123456789);
    });
  });

  group('sign-out', () {
    test('signOut delegates to native and returns afterSignOutUrl', () async {
      const config = ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'test');
      await client.initialize(config);
      final result = await client.signOut();
      expect(result, '/');
    });
  });

  group('getAccessToken', () {
    test('returns token from native layer', () async {
      const config = ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'test');
      await client.initialize(config);
      final token = await client.getAccessToken();
      expect(token, 'mock-access-token');
    });
  });

  group('continueFederatedAuth', () {
    test('resubmits the flow with the native-extracted code and returns the response', () async {
      const config = ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'test');
      await client.initialize(config);
      final response = await client.continueFederatedAuth(
        redirectUrl: 'https://idp.example/authorize?state=abc',
        actionId: 'action_2',
        applicationId: 'app-1',
        flowId: 'flow-1',
        challengeToken: 'challenge-1',
      );
      expect(response.flowStatus, FlowStatus.complete);
      expect(response.assertion, 'mock-assertion');
      final call = log.firstWhere((c) => c.method == 'continueFederatedAuth');
      final args = call.arguments as Map<Object?, Object?>;
      expect(args['redirectUrl'], 'https://idp.example/authorize?state=abc');
      expect(args['actionId'], 'action_2');
      expect(args['applicationId'], 'app-1');
      expect(args['flowId'], 'flow-1');
      expect(args['challengeToken'], 'challenge-1');
    });

    test('surfaces user cancellation as federatedAuthCancelled', () async {
      const config = ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'test');
      await client.initialize(config);
      expect(
        () => client.continueFederatedAuth(
          redirectUrl: 'https://cancel.example',
          actionId: 'action_2',
          applicationId: 'app-1',
        ),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.federatedAuthCancelled)),
      );
    });
  });

  group('toIAMException', () {
    test('keeps the native message when there is no server error', () {
      final error = toIAMException(PlatformException(code: 'NETWORK_ERROR', message: 'offline'));
      expect(error.code, ThunderIDErrorCode.networkError);
      expect(error.message, 'offline');
      expect(error.serverError, isNull);
      expect(error.authenticationChallenge, isNull);
    });

    test('uses the description when the server error has no message text', () {
      final error = toIAMException(
        PlatformException(
          code: 'INVALID_INPUT',
          message: 'Bad request',
          details: <String, Object?>{
            'serverError': <String, Object?>{
              'code': 'USR-1047',
              'description': <String, Object?>{'defaultValue': 'Give the current value'},
            },
          },
        ),
      );
      expect(error.message, 'Give the current value');
      expect(error.serverError?.code, 'USR-1047');
      expect(error.authenticationChallenge, isNull);
    });

    test('reads the challenge from the AUTH-4011 body when the native SDK sent none', () {
      final error = toIAMException(
        PlatformException(
          code: 'AUTHENTICATION_FAILED',
          details: <String, Object?>{
            'serverError': <String, Object?>{
              'code': 'AUTH-4011',
              'description': <String, Object?>{
                'params': <String, Object?>{'maxAge': '300'},
              },
            },
          },
        ),
      );
      expect(error.code, ThunderIDErrorCode.stepUpRequired);
      expect(error.authenticationChallenge?.error, 'insufficient_user_authentication');
      expect(error.authenticationChallenge?.maxAge, 300);
    });

    test('keeps the native code for a 401 that is not a step-up', () {
      final error = toIAMException(
        PlatformException(
          code: 'AUTHENTICATION_FAILED',
          details: <String, Object?>{
            'serverError': <String, Object?>{'code': 'AUTH-4010'},
          },
        ),
      );
      expect(error.code, ThunderIDErrorCode.authenticationFailed);
      expect(error.authenticationChallenge, isNull);
    });
  });

  group('step-up', () {
    const config = ThunderIDConfig(baseUrl: 'https://localhost:8090');
    final headerChallenge = PlatformException(
      code: 'STEP_UP_REQUIRED',
      details: <String, Object?>{
        'serverError': <String, Object?>{'code': 'AUTH-4011'},
        'authenticationChallenge': <String, Object?>{
          'error': 'insufficient_user_authentication',
          'maxAge': 300,
        },
      },
    );
    final bodyOnly = PlatformException(
      code: 'AUTHENTICATION_FAILED',
      details: <String, Object?>{
        'serverError': <String, Object?>{
          'code': 'AUTH-4011',
          'description': <String, Object?>{
            'params': <String, Object?>{'maxAge': '120'},
          },
        },
      },
    );

    void refuseWith(String method, PlatformException refusal) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.thunderid/sdk'),
        (call) async {
          log.add(call);
          if (call.method == method) throw refusal;
          return call.method == 'initialize' ? true : null;
        },
      );
    }

    Matcher stepUp(int maxAge) => throwsA(
          isA<IAMException>()
              .having((e) => e.code, 'code', ThunderIDErrorCode.stepUpRequired)
              .having((e) => e.authenticationChallenge?.maxAge, 'maxAge', maxAge),
        );

    test('updateUserProfile raises stepUpRequired from the challenge', () async {
      await client.initialize(config);
      refuseWith('updateUserProfile', headerChallenge);
      await expectLater(client.updateUserProfile({'email': 'new@example.com'}), stepUp(300));
    });

    test('updateUserProfile raises stepUpRequired from the AUTH-4011 body', () async {
      await client.initialize(config);
      refuseWith('updateUserProfile', bodyOnly);
      await expectLater(client.updateUserProfile({'email': 'new@example.com'}), stepUp(120));
    });

    test('updateUserCredentials raises stepUpRequired from the challenge', () async {
      await client.initialize(config);
      refuseWith('updateUserCredentials', headerChallenge);
      await expectLater(client.updateUserCredentials(newValue: 'n3wP@ss'), stepUp(300));
    });

    test('updateUserCredentials raises stepUpRequired from the AUTH-4011 body', () async {
      await client.initialize(config);
      refuseWith('updateUserCredentials', bodyOnly);
      await expectLater(client.updateUserCredentials(newValue: 'n3wP@ss'), stepUp(120));
    });

    test('reauthenticate sends the max age to the native SDK and never refreshes', () async {
      await client.initialize(config);
      await client.reauthenticate(maxAge: 300);
      await client.reauthenticate();

      final calls = log.where((c) => c.method == 'reauthenticate').toList();
      expect(calls, hasLength(2));
      expect((calls[0].arguments as Map<Object?, Object?>)['maxAge'], 300);
      expect((calls[1].arguments as Map<Object?, Object?>).containsKey('maxAge'), false);
      expect(log.where((c) => c.method.toLowerCase().contains('refresh')), isEmpty);
    });

    test('reauthenticate passes on a failed or canceled sign-in', () async {
      await client.initialize(config);
      refuseWith('reauthenticate', PlatformException(code: 'FEDERATED_AUTH_CANCELLED'));
      await expectLater(
        client.reauthenticate(maxAge: 300),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.federatedAuthCancelled)),
      );
    });

    test('reauthenticationMethod maps the native answer', () async {
      await client.initialize(config);
      for (final entry in {
        'browser': ReauthenticationMethod.browser,
        'flow': ReauthenticationMethod.flow,
        'unavailable': ReauthenticationMethod.unavailable,
        null: ReauthenticationMethod.unavailable,
      }.entries) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('dev.thunderid/sdk'),
          (call) async => call.method == 'reauthenticationMethod' ? entry.key : null,
        );
        expect(await client.reauthenticationMethod(), entry.value);
      }
    });

    test('a re-sign-in flow sends reauthentication and the max age with every step', () async {
      await client.initialize(config);
      for (final request in const [
        EmbeddedFlowRequestConfig(applicationId: 'app-1', reauthentication: true, maxAge: 300),
        EmbeddedFlowRequestConfig(applicationId: 'app-1'),
      ]) {
        // The mock answers nothing, so only the request matters here.
        await client.signIn(payload: const EmbeddedSignInPayload(actionId: 'init'), request: request).then(
              (_) {},
              onError: (Object _) {},
            );
      }

      final requests =
          log.where((c) => c.method == 'signIn').map((c) => (c.arguments as Map<Object?, Object?>)['request']).toList();
      expect(requests[0], {'applicationId': 'app-1', 'flowType': 'AUTHENTICATION', 'reauthentication': true, 'maxAge': 300});
      expect(requests[1], {'applicationId': 'app-1', 'flowType': 'AUTHENTICATION'});
    });

    test('a re-sign-in by another account is marked on the exception', () async {
      await client.initialize(config);
      refuseWith(
        'reauthenticate',
        PlatformException(code: 'AUTHENTICATION_FAILED', details: <String, Object?>{'anotherAccount': true}),
      );
      await expectLater(
        client.reauthenticate(maxAge: 300),
        throwsA(isA<IAMException>().having((e) => e.isReauthenticationByAnotherAccount, 'another account', true)),
      );
    });

    test('reauthenticate is refused before initialization', () async {
      await expectLater(
        client.reauthenticate(maxAge: 300),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.sdkNotInitialized)),
      );
    });
  });

  group('AuthenticationChallenge', () {
    test('parses an insufficient_user_authentication Bearer challenge', () {
      final challenge = AuthenticationChallenge.parse(
        'Bearer error="insufficient_user_authentication", '
        'error_description="A more recent authentication is required", max_age="300"',
      );
      expect(challenge?.error, 'insufficient_user_authentication');
      expect(challenge?.errorDescription, 'A more recent authentication is required');
      expect(challenge?.maxAge, 300);
    });

    test('reads unquoted values, any scheme case and escaped quotes', () {
      final challenge = AuthenticationChallenge.parse(
        r'bearer realm="api", error=insufficient_user_authentication, error_description="say \"again\"", max_age=60',
      );
      expect(challenge?.maxAge, 60);
      expect(challenge?.errorDescription, 'say "again"');
    });

    test('reads only the Bearer challenge when other challenges follow', () {
      final challenge = AuthenticationChallenge.parse(
        'Bearer error="insufficient_user_authentication", max_age=300, Bearer error="invalid_token"',
      );
      expect(challenge?.maxAge, 300);
      final other = AuthenticationChallenge.parse(
        'Bearer error="insufficient_user_authentication", DPoP error_description="x", max_age=0',
      );
      expect(other?.maxAge, isNull);
      expect(other?.errorDescription, isNull);
    });

    test('ignores other errors, other schemes and a missing header', () {
      expect(AuthenticationChallenge.parse('Bearer error="invalid_token"'), isNull);
      expect(AuthenticationChallenge.parse('Basic realm="api"'), isNull);
      expect(AuthenticationChallenge.parse(null), isNull);
      expect(AuthenticationChallenge.parse(''), isNull);
    });

    test('leaves max age empty when it is not a non-negative number', () {
      expect(
        AuthenticationChallenge.parse('Bearer error="insufficient_user_authentication", max_age="soon"')?.maxAge,
        isNull,
      );
      expect(
        AuthenticationChallenge.parse('Bearer error="insufficient_user_authentication", max_age="-5"')?.maxAge,
        isNull,
      );
    });

    test('resolve prefers the header, then falls back to the AUTH-4011 body', () {
      final body = ServerError.tryParse(
        '{"code":"AUTH-4011","description":{"defaultValue":"x","params":{"maxAge":"120"}}}',
      );
      expect(
        AuthenticationChallenge.resolve(
          wwwAuthenticate: 'Bearer error="insufficient_user_authentication", max_age="300"',
          serverError: body,
        )?.maxAge,
        300,
      );
      expect(AuthenticationChallenge.resolve(serverError: body)?.maxAge, 120);
      expect(AuthenticationChallenge.resolve(serverError: ServerError.tryParse('{"code":"AUTH-4010"}')), isNull);
    });

    test('an IAMApiException 401 with AUTH-4011 carries the challenge from its body', () {
      const error = IAMApiException(
        ThunderIDErrorCode.authenticationFailed,
        'Failed',
        statusCode: 401,
        operation: 'updateUserCredentials',
        responseBody: '{"code":"AUTH-4011","description":{"params":{"maxAge":"300"}}}',
      );
      expect(error.authenticationChallenge?.maxAge, 300);
    });
  });
}
