// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/backend/http_transport.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

const _channel = MethodChannel('dev.thunderid/sdk');
const _config = ThunderIDConfig(baseUrl: 'https://auth.example.com', clientId: 'tv-app', applicationId: 'app-1');

const _tokens = {'accessToken': 'at', 'tokenType': 'Bearer', 'expiresIn': 3600, 'refreshToken': 'rt', 'idToken': 'it'};

class _Sent {
  final String method;
  final Uri url;
  final Map<String, dynamic> body;

  _Sent(this.method, this.url, this.body);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];
  var nativeHas = true;

  setUp(() {
    calls.clear();
    nativeHas = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
          return true;
        case 'initiateCIBA':
          if (!nativeHas) throw MissingPluginException();
          return {'authReqId': 'req-1', 'expiresIn': 90, 'interval': 3};
        case 'pollCIBA':
        case 'pollDeviceAuthorization':
          return _tokens;
        case 'startDeviceAuthorization':
          if (!nativeHas) throw MissingPluginException();
          return {
            'deviceCode': 'secret-device-code',
            'userCode': 'WDJB-MJHT',
            'verificationUri': 'https://auth.example.com/device',
            'verificationUriComplete': 'https://auth.example.com/device?user_code=WDJB-MJHT',
            'expiresIn': 600,
          };
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
  });

  Future<ThunderIDClient> client({HttpTransport? transport}) async {
    final client = ThunderIDClient(httpTransport: transport);
    await client.initialize(_config);
    return client;
  }

  Map<dynamic, dynamic> argsOf(String method) => calls.firstWhere((c) => c.method == method).arguments as Map;

  group('CIBA', () {
    test('initiateCIBA hands the request to the native SDK and reads the answer', () async {
      final response = await (await client()).initiateCIBA(
        const CIBAInitiateOptions(
          loginHint: 'ada@example.com',
          bindingMessage: 'Approve 42',
          requestedExpiry: 120,
          authorizationDetails: [
            {'type': 'payment_initiation', 'amount': '10'},
          ],
        ),
      );
      expect(response.authReqId, 'req-1');
      expect(response.expiresIn, 90);
      expect(response.interval, 3);
      final options = argsOf('initiateCIBA')['options'] as Map;
      expect(options['loginHint'], 'ada@example.com');
      expect(options['bindingMessage'], 'Approve 42');
      expect(options['requestedExpiry'], 120);
      expect((options['authorizationDetails'] as List).single, {'type': 'payment_initiation', 'amount': '10'});
    });

    test('needs exactly one hint', () async {
      final c = await client();
      for (final options in const [
        CIBAInitiateOptions(),
        CIBAInitiateOptions(loginHint: 'ada', idTokenHint: 'token'),
      ]) {
        await expectLater(
          c.initiateCIBA(options),
          throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.invalidInput)),
        );
      }
      expect(calls.map((c) => c.method), isNot(contains('initiateCIBA')));
    });

    test('a response with no auth_req_id is a server error', () {
      expect(
        () => CIBAInitiateResponse.fromMap(const {'expiresIn': 1}),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.serverError)),
      );
      final defaults = CIBAInitiateResponse.fromMap(const {'authReqId': 'r'});
      expect([defaults.expiresIn, defaults.interval], [120, 5]);
    });

    test('pollCIBA polls through the native SDK, which stores the tokens', () async {
      final tokens = await (await client()).pollCIBA('req-1', 0, expiresIn: 90);
      expect(tokens.accessToken, 'at');
      expect(argsOf('pollCIBA'), {'authReqId': 'req-1', 'interval': 1, 'expiresIn': 90});
    });

    test('a native SDK without CIBA reports it unsupported', () async {
      nativeHas = false;
      await expectLater(
        (await client()).initiateCIBA(const CIBAInitiateOptions(loginHint: 'ada')),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.operationNotSupported)),
      );
    });
  });

  group('device authorization, device side', () {
    test('startDeviceAuthorization returns the codes and never prints the device code', () async {
      final authorization = await (await client()).startDeviceAuthorization(scopes: const ['openid', 'tv']);
      expect(argsOf('startDeviceAuthorization'), {
        'scopes': ['openid', 'tv'],
      });
      expect(authorization.userCode, 'WDJB-MJHT');
      expect(authorization.verificationUriComplete, contains('user_code=WDJB-MJHT'));
      expect(authorization.interval, 5);
      expect(authorization.toString(), isNot(contains('secret-device-code')));
    });

    test('pollDeviceAuthorization polls with the device code', () async {
      final c = await client();
      final authorization = await c.startDeviceAuthorization();
      final tokens = await c.pollDeviceAuthorization(authorization);
      expect(tokens.refreshToken, 'rt');
      expect(argsOf('pollDeviceAuthorization'), {'deviceCode': 'secret-device-code', 'interval': 5, 'expiresIn': 600});
    });

    test('a response without the codes is a server error', () {
      expect(
        () => DeviceAuthorization.fromMap(const {'userCode': 'X'}),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.serverError)),
      );
    });

    test('a native SDK without device authorization reports it unsupported', () async {
      nativeHas = false;
      await expectLater(
        (await client()).startDeviceAuthorization(),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.operationNotSupported)),
      );
    });
  });

  group('verifyDeviceCode', () {
    late List<_Sent> sent;
    late List<HttpResponseData> flowAnswers;
    late HttpResponseData callbackAnswer;

    HttpResponseData json(int status, Object body) => HttpResponseData(statusCode: status, body: jsonEncode(body));

    Future<HttpResponseData> transport(String method, Uri url, Map<String, String> headers, String? body) async {
      sent.add(_Sent(method, url, body == null ? const {} : jsonDecode(body) as Map<String, dynamic>));
      expect(headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
      if (url.path == '/oauth2/auth/callback') return callbackAnswer;
      return flowAnswers.removeAt(0);
    }

    setUp(() {
      sent = [];
      callbackAnswer = json(200, {'redirect_uri': 'https://auth.example.com/device/done'});
      flowAnswers = [];
    });

    test('starts the DEVICE_GRANT flow with the user code', () async {
      flowAnswers.add(
        json(200, {
          'executionId': 'exec-1',
          'flowStatus': 'INCOMPLETE',
          'challengeToken': 'ct-1',
          'data': {
            'inputs': [
              {'identifier': 'username', 'type': 'TEXT_INPUT'},
            ],
          },
        }),
      );
      final step = await (await client(transport: transport)).verifyDeviceCode(userCode: ' WDJB-MJHT ');
      expect(sent.single.url.toString(), 'https://auth.example.com/flow/execute');
      expect(sent.single.body, {
        'applicationId': 'app-1',
        'flowType': 'DEVICE_GRANT',
        'inputs': {'user_code': 'WDJB-MJHT'},
        'verbose': true,
      });
      expect(step.flowId, 'exec-1');
      expect(step.challengeToken, 'ct-1');
      expect(step.flowStatus, FlowStatus.promptOnly);
    });

    test('continues the flow and relays a completed flow to the callback', () async {
      flowAnswers.add(
        json(200, {
          'executionId': 'exec-1',
          'flowStatus': 'COMPLETE',
          'assertion': 'jwt-assertion',
          'data': {
            'additionalData': {'authId': 'auth-1', 'callbackType': 'device'},
          },
        }),
      );
      final step = await (await client(transport: transport)).verifyDeviceCode(
        flowId: 'exec-1',
        actionId: 'approve',
        inputs: const {'consent': 'yes'},
        challengeToken: 'ct-1',
      );
      expect(sent.first.body, {
        'executionId': 'exec-1',
        'action': 'approve',
        'inputs': {'consent': 'yes'},
        'challengeToken': 'ct-1',
      });
      expect(sent.last.url.toString(), 'https://auth.example.com/oauth2/auth/callback');
      expect(sent.last.body, {'assertion': 'jwt-assertion', 'authId': 'auth-1', 'type': 'device'});
      expect(step.flowStatus, FlowStatus.complete);
    });

    test('a refused flow tells the device and comes back as an error step', () async {
      callbackAnswer = json(400, {'error': 'access_denied'});
      flowAnswers.add(
        json(200, {
          'executionId': 'exec-1',
          'flowStatus': 'ERROR',
          'errorAssertion': 'jwt-error',
          'failureReason': 'Denied',
          'data': {
            'additionalData': {'authId': 'auth-1', 'callbackType': 'device'},
          },
        }),
      );
      final step = await (await client(transport: transport)).verifyDeviceCode(flowId: 'exec-1', actionId: 'deny');
      expect(sent.last.body['assertion'], 'jwt-error');
      expect(step.flowStatus, FlowStatus.error);
      expect(step.failureReason, 'Denied');
    });

    test('an HTTP error that carries an error assertion is relayed as an error step', () async {
      callbackAnswer = json(400, {'error': 'access_denied'});
      flowAnswers.add(
        json(400, {
          'executionId': 'exec-1',
          'errorAssertion': 'jwt-error',
          'data': {
            'additionalData': {'authId': 'auth-1', 'callbackType': 'device'},
          },
        }),
      );
      final step = await (await client(transport: transport)).verifyDeviceCode(flowId: 'exec-1', actionId: 'deny');
      expect(step.flowStatus, FlowStatus.error);
      expect(sent.last.url.path, '/oauth2/auth/callback');
    });

    test('any other HTTP error is an API error with the server envelope', () async {
      flowAnswers.add(json(400, {'code': 'FES-1001', 'message': 'Invalid code'}));
      await expectLater(
        (await client(transport: transport)).verifyDeviceCode(userCode: 'NOPE'),
        throwsA(
          isA<IAMApiException>()
              .having((e) => e.code, 'code', ThunderIDErrorCode.invalidInput)
              .having((e) => e.serverError?.code, 'serverError', 'FES-1001'),
        ),
      );
    });

    test('a completed flow without callback data fails', () async {
      flowAnswers.add(json(200, {'executionId': 'exec-1', 'flowStatus': 'COMPLETE', 'assertion': 'jwt'}));
      await expectLater(
        (await client(transport: transport)).verifyDeviceCode(flowId: 'exec-1'),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.serverError)),
      );
    });

    test('a failed callback for a completed flow fails', () async {
      callbackAnswer = json(400, {'error': 'access_denied'});
      flowAnswers.add(
        json(200, {
          'executionId': 'exec-1',
          'flowStatus': 'COMPLETE',
          'assertion': 'jwt',
          'data': {
            'additionalData': {'authId': 'auth-1', 'callbackType': 'device'},
          },
        }),
      );
      await expectLater(
        (await client(transport: transport)).verifyDeviceCode(flowId: 'exec-1'),
        throwsA(isA<IAMApiException>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('starting needs an application id', () async {
      final c = ThunderIDClient(httpTransport: transport);
      await c.initialize(const ThunderIDConfig(baseUrl: 'https://auth.example.com'));
      await expectLater(
        c.verifyDeviceCode(userCode: 'X'),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.invalidInput)),
      );
      expect(sent, isEmpty);
    });
  });
}
