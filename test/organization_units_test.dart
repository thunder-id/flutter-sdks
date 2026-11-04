// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

const _channel = MethodChannel('dev.thunderid/sdk');

const _page = {
  'current': 'ou-1',
  'totalResults': 3,
  'startIndex': 1,
  'count': 2,
  'organizationUnits': [
    {'id': 'ou-1', 'handle': 'acme-1', 'name': 'Acme OU 1'},
    {'id': 'ou-2', 'handle': 'acme-2', 'name': 'Acme OU 2', 'logoUrl': 'https://cdn.example.com/2.png'},
  ],
  'links': <Object>[],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];
  final requests = <ManagementRequest>[];
  var claims = <String, Object?>{'sub': 'u-1', 'ouId': 'ou-1', 'ouHandle': 'acme-1', 'ouName': 'Acme OU 1'};
  var signedIn = true;
  var callbackUrl = 'com.example.app://callback?code=abc&state=xyz';
  PlatformException? buildUrlError;
  ManagementResponse Function(ManagementRequest request) answer =
      (_) => ManagementResponse(statusCode: 200, body: jsonEncode(_page));

  ThunderIDConfig config() => ThunderIDConfig(
        baseUrl: 'https://auth.example.com/',
        clientId: 'app',
        http: ThunderIDHttpConfig(
          fetcher: (request) async {
            requests.add(request);
            return answer(request);
          },
        ),
      );

  setUp(() {
    calls.clear();
    requests.clear();
    signedIn = true;
    buildUrlError = null;
    claims = {'sub': 'u-1', 'ouId': 'ou-1', 'ouHandle': 'acme-1', 'ouName': 'Acme OU 1'};
    callbackUrl = 'com.example.app://callback?code=abc&state=xyz';
    answer = (_) => ManagementResponse(statusCode: 200, body: jsonEncode(_page));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
          return true;
        case 'isSignedIn':
          return signedIn;
        case 'getAccessToken':
          return 'token';
        case 'getUser':
        case 'handleRedirectCallback':
          return claims;
        case 'buildSignInUrl':
          if (buildUrlError != null) throw buildUrlError!;
          return 'https://auth.example.com/ou/ou-2/oauth2/authorize?client_id=app';
        case 'openAuthSession':
          return callbackUrl;
        case 'signIn':
          return {'flowId': 'flow-1', 'flowStatus': 'INCOMPLETE'};
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
  });

  Future<ThunderIDClient> client() async {
    final client = ThunderIDClient();
    await client.initialize(config());
    return client;
  }

  Iterable<String> methods() => calls.map((c) => c.method);

  group('getAccessibleOrganizationUnits', () {
    test('reads /users/me/ous with the scope and paging', () async {
      final page = await (await client()).getAccessibleOrganizationUnits(
        scope: AccessibleOrganizationUnitScope.siblings,
        limit: 2,
        offset: 0,
      );
      expect(requests.single.method, 'GET');
      expect(
        requests.single.url.toString(),
        'https://auth.example.com/users/me/ous?scope=siblings&limit=2&offset=0',
      );
      expect(page.current, 'ou-1');
      expect(page.totalResults, 3);
      expect(page.startIndex, 1);
      expect(page.count, 2);
      expect(page.organizationUnits.map((u) => u.handle), ['acme-1', 'acme-2']);
      expect(page.organizationUnits[1].logoUrl, 'https://cdn.example.com/2.png');
    });

    test('sends no query when none is given', () async {
      await (await client()).getAccessibleOrganizationUnits();
      expect(requests.single.url.toString(), 'https://auth.example.com/users/me/ous');
    });

    test('keeps 401, 403 and 404 distinct and carries the server error', () async {
      final c = await client();
      for (final (status, code) in [
        (401, ThunderIDErrorCode.sessionExpired),
        (403, ThunderIDErrorCode.forbidden),
        (404, ThunderIDErrorCode.notFound),
        (400, ThunderIDErrorCode.invalidInput),
      ]) {
        answer = (_) => ManagementResponse(
              statusCode: status,
              body: jsonEncode({'code': 'USR-1036', 'message': 'Invalid scope'}),
            );
        await expectLater(
          c.getAccessibleOrganizationUnits(),
          throwsA(
            isA<IAMApiException>()
                .having((e) => e.code, 'code', code)
                .having((e) => e.statusCode, 'statusCode', status)
                .having((e) => e.serverError?.code, 'serverError', 'USR-1036'),
          ),
        );
      }
    });

    test('refuses invalid paging before sending', () async {
      final c = await client();
      await expectLater(
        c.getAccessibleOrganizationUnits(limit: 0),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.invalidInput)),
      );
      expect(requests, isEmpty);
    });

    test('the data-layer function works with any fetcher', () async {
      final page = await getAccessibleOrganizationUnits(
        baseUrl: 'https://auth.example.com',
        fetcher: (request) async {
          requests.add(request);
          return ManagementResponse(statusCode: 200, body: jsonEncode(_page));
        },
      );
      expect(page.organizationUnits, hasLength(2));
      expect(requests.single.url.path, '/users/me/ous');
    });
  });

  group('getCurrentOrganizationUnit', () {
    test('reads the ouId, ouHandle and ouName claims', () async {
      final current = await (await client()).getCurrentOrganizationUnit();
      expect(current, const CurrentOrganizationUnit(id: 'ou-1', handle: 'acme-1', name: 'Acme OU 1'));
    });

    test('is null without the claims or a session', () async {
      final c = await client();
      claims = {'sub': 'u-1'};
      expect(await c.getCurrentOrganizationUnit(), isNull);
      signedIn = false;
      expect(await c.getCurrentOrganizationUnit(), isNull);
    });
  });

  group('sign-in bounded to a unit', () {
    test('redirect mode hands the unit to the native SDK', () async {
      await (await client()).buildSignInUrl(options: const SignInOptions(organizationUnitId: 'ou/2'));
      final args = calls.firstWhere((c) => c.method == 'buildSignInUrl').arguments as Map;
      expect((args['options'] as Map)['organizationUnitId'], 'ou/2');
    });

    test('an extra parameter cannot replace the unit', () {
      const options = SignInOptions(organizationUnitId: 'ou-2', extra: {'organizationUnitId': 'other'});
      expect(options.toMap()['organizationUnitId'], 'ou-2');
    });

    test('a blank unit is refused', () async {
      final c = await client();
      await expectLater(
        c.buildSignInUrl(options: const SignInOptions(organizationUnitId: ' ')),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.invalidInput)),
      );
    });

    test('embedded mode sends ouId when the flow starts, never on a continuation', () async {
      final c = await client();
      await c.signIn(
        payload: const EmbeddedSignInPayload(actionId: 'init'),
        request: const EmbeddedFlowRequestConfig(applicationId: 'app-1', organizationUnitId: 'ou-2'),
      );
      await c.signIn(
        payload: const EmbeddedSignInPayload(flowId: 'flow-1', actionId: 'submit'),
        request: const EmbeddedFlowRequestConfig(applicationId: 'app-1', organizationUnitId: 'ou-2'),
      );
      final requestsSent = calls.where((c) => c.method == 'signIn').map((c) => (c.arguments as Map)['request'] as Map);
      expect(requestsSent.first['ouId'], 'ou-2');
      expect(requestsSent.last.containsKey('ouId'), isFalse);
    });

    test('embedded mode bounds only an authentication flow', () async {
      final c = await client();
      await expectLater(
        c.signIn(
          payload: const EmbeddedSignInPayload(actionId: 'init'),
          request: const EmbeddedFlowRequestConfig(
            applicationId: 'app-1',
            flowType: FlowType.registration,
            organizationUnitId: 'ou-2',
          ),
        ),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.invalidInput)),
      );
      expect(methods(), isNot(contains('signIn')));
    });

    test('without a unit nothing changes', () async {
      final c = await client();
      await c.buildSignInUrl();
      await c.signIn(
        payload: const EmbeddedSignInPayload(actionId: 'init'),
        request: const EmbeddedFlowRequestConfig(applicationId: 'app-1'),
      );
      expect((calls.firstWhere((c) => c.method == 'buildSignInUrl').arguments as Map).containsKey('options'), isFalse);
      final request = (calls.firstWhere((c) => c.method == 'signIn').arguments as Map)['request'] as Map;
      expect(request, {'applicationId': 'app-1', 'flowType': 'AUTHENTICATION'});
    });
  });

  group('switchOrganizationUnit', () {
    test('signs in again bounded to the unit and returns the new user', () async {
      final c = await client();
      claims = {'sub': 'u-1', 'ouId': 'ou-2'};
      final user = await c.switchOrganizationUnit('ou-2');
      expect(user['ouId'], 'ou-2');
      expect(methods(), containsAllInOrder(['buildSignInUrl', 'openAuthSession', 'handleRedirectCallback']));
      final args = calls.firstWhere((c) => c.method == 'buildSignInUrl').arguments as Map;
      expect((args['options'] as Map)['organizationUnitId'], 'ou-2');
    });

    test('keeps the other sign-in options', () async {
      await (await client()).switchOrganizationUnit('ou-2', options: const SignInOptions(prompt: 'login'));
      final options = (calls.firstWhere((c) => c.method == 'buildSignInUrl').arguments as Map)['options'] as Map;
      expect(options, {'prompt': 'login', 'organizationUnitId': 'ou-2'});
    });

    test('unauthorized_client is a documented error and leaves the session alone', () async {
      final c = await client();
      callbackUrl = 'com.example.app://callback?error=unauthorized_client&state=xyz';
      await expectLater(
        c.switchOrganizationUnit('ou-9'),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.organizationUnitUnavailable)),
      );
      expect(methods(), isNot(contains('handleRedirectCallback')));
      expect(methods(), isNot(contains('clearSession')));
    });

    test('another error redirect fails without touching the session', () async {
      final c = await client();
      callbackUrl = 'com.example.app://callback?error=access_denied';
      await expectLater(
        c.switchOrganizationUnit('ou-2'),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.authenticationFailed)),
      );
      expect(methods(), isNot(contains('handleRedirectCallback')));
    });

    test('a native SDK without unit-bounded sign-in refuses before the browser opens', () async {
      final c = await client();
      buildUrlError = PlatformException(code: 'OPERATION_NOT_SUPPORTED', message: 'not supported');
      await expectLater(
        c.switchOrganizationUnit('ou-2'),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.operationNotSupported)),
      );
      expect(methods(), isNot(contains('openAuthSession')));
    });

    test('a blank unit is refused', () async {
      final c = await client();
      await expectLater(
        c.switchOrganizationUnit(''),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.invalidInput)),
      );
      expect(methods(), isNot(contains('buildSignInUrl')));
    });
  });

  test('pushedAuthorizationRequests reaches the native SDK only when set', () {
    expect(const ThunderIDConfig(baseUrl: 'https://a.example.com').toMap(), isNot(contains('pushedAuthorizationRequests')));
    expect(
      const ThunderIDConfig(baseUrl: 'https://a.example.com', pushedAuthorizationRequests: true)
          .toMap()['pushedAuthorizationRequests'],
      isTrue,
    );
  });

  test('the native SDKs\' UNSUPPORTED_OPERATION reads as operationNotSupported', () {
    expect(ThunderIDErrorCode.fromString('UNSUPPORTED_OPERATION'), ThunderIDErrorCode.operationNotSupported);
    expect(ThunderIDErrorCode.fromString('ORGANIZATION_UNIT_UNAVAILABLE'), ThunderIDErrorCode.organizationUnitUnavailable);
    expect(ThunderIDErrorCode.organizationUnitUnavailable.value, 'ORGANIZATION_UNIT_UNAVAILABLE');
  });
}
