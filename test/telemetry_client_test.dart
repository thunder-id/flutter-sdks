// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/management/administration_flows.dart';
import 'package:thunderid_flutter/src/management/management_transport.dart';
import 'package:thunderid_flutter/src/models/backend.dart';
import 'package:thunderid_flutter/src/models/flow_models.dart';
import 'package:thunderid_flutter/src/models/http_request.dart';
import 'package:thunderid_flutter/src/models/management/group.dart';
import 'package:thunderid_flutter/src/models/thunderid_config.dart';
import 'package:thunderid_flutter/src/models/user.dart';
import 'package:thunderid_flutter/src/telemetry/client_telemetry.dart';
import 'package:thunderid_flutter/src/telemetry/telemetry_config.dart';
import 'package:thunderid_flutter/src/thunderid_client.dart';

const _base = 'https://api.example.com';
const _claims = {
  'sub': '11111111-1111-4111-8111-111111111111',
  'ouId': '22222222-2222-4222-8222-222222222222',
  'auth_time': 1700000000,
};

class _Sent {
  final Uri url;
  final Map<String, String> headers;
  final List<Map<String, Object?>> events;

  _Sent(this.url, this.headers, String body) : events = (jsonDecode(body) as List).cast<Map<String, Object?>>();

  List<String> get names => events.map((event) => event['name']! as String).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> secureStore;
  late Map<String, Object?> signInResult;
  late List<_Sent> sent;
  late ThunderIDClient client;

  ThunderIDClient build(TelemetryConfig telemetry) {
    final config = ThunderIDConfig(
      baseUrl: _base,
      clientId: 'app',
      telemetry: telemetry,
      http: ThunderIDHttpConfig(
        fetcher: (request) async => switch (request.method) {
          'POST' => const ManagementResponse(statusCode: 409, body: '{"code":"GRP-1004","message":"Group exists"}'),
          _ => const ManagementResponse(statusCode: 204, headers: {'x-telemetry-event': 'role.remove'}),
        },
      ),
    );
    final built = ThunderIDClient(
      httpTransport: (method, url, headers, body) async {
        sent.add(_Sent(url, headers, body!));
        return const HttpResponseData(statusCode: 204);
      },
    );
    return built..initialize(config);
  }

  setUp(() {
    secureStore = {};
    sent = [];
    signInResult = const {'flowStatus': 'COMPLETE'};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.thunderid/sdk'),
      (call) async {
        final args = (call.arguments as Map<Object?, Object?>?) ?? const {};
        switch (call.method) {
          case 'initialize':
          case 'isSignedIn':
            return true;
          case 'getUser':
          case 'handleRedirectCallback':
            return _claims;
          case 'signIn':
            return signInResult;
          case 'getAccessToken':
            return 'app-token';
          case 'signOut':
            return '/';
          case 'readSecureValue':
            return secureStore[args['key']];
          case 'writeSecureValue':
            secureStore[args['key']! as String] = args['value']! as String;
            return null;
          case 'deleteSecureValue':
            secureStore.remove(args['key']);
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

  test(
      'reports management calls, named by the API when it says, sign-ins once, sign-outs and app events, with the app token',
      () async {
    client = build(const TelemetryConfig(endpoint: '$_base/telemetry', format: TelemetryFormat.json, prefix: 'acme'));
    await Future<void>.delayed(Duration.zero);

    await client.handleRedirectCallback('com.example.app://callback?code=c1');
    await client.handleRedirectCallback('com.example.app://callback?code=c2');
    await expectLater(
      client.management.createGroup(const CreateGroupRequest(name: 'g', ouId: 'ou1')),
      throwsA(anything),
    );
    await client.management.deleteRole('r1');
    client
      ..trackPageView('/applications/:id')
      ..track('application.template-pick', {'type': 'spa'});
    await client.flushTelemetry();
    await client.signOut();

    final names = sent.expand((batch) => batch.names).toList();
    expect(names, [
      'acme.auth.sign-in',
      'acme.group.create-failed',
      'acme.role.remove',
      'acme.application.detail-view',
      'acme.application.template-pick',
      'acme.auth.sign-out',
    ]);
    final failed = sent.first.events[1]['attributes']! as Map;
    expect(failed['data'], {'resource_type': 'group', 'status': '409', 'error_code': 'GRP-1004'});
    expect(failed['user'], {'id': _claims['sub']});
    expect(failed['organization'], {'id': _claims['ouId']});
    expect(sent.first.headers['Authorization'], 'Bearer app-token');
  });

  test('never reports the flow-execution requests of the SDK', () async {
    client = build(const TelemetryConfig(endpoint: '$_base/telemetry', format: TelemetryFormat.json));
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      client.management.executeAdministrationFlow('f1', const {'subject': 'u1'}, action: 'user suspension'),
      throwsA(anything),
    );
    await client.management.deleteRole('r1');
    await client.flushTelemetry();
    // The role delete is reported, named by the API's header; the flow execution is not.
    expect(sent.expand((batch) => batch.names).toList(), ['role.remove']);
  });

  test('never reports the token request behind a backend call, only the call itself', () async {
    final calls = <String>[];
    final backendClient = ThunderIDClient(
      httpTransport: (method, url, headers, body) async {
        if (url.path == '/telemetry') {
          sent.add(_Sent(url, headers, body!));
          return const HttpResponseData(statusCode: 204);
        }
        calls.add('$method ${url.path}');
        return switch (url.path) {
          '/api/auth/session' => HttpResponseData(
              statusCode: 200,
              body: jsonEncode({'isSignedIn': true, 'user': _claims, 'expiresAt': 1800000000}),
            ),
          '/api/auth/token' => HttpResponseData(
              statusCode: 200,
              body: jsonEncode({'access_token': 'token-1', 'token_type': 'Bearer', 'expires_in': 300}),
            ),
          _ => const HttpResponseData(statusCode: 201, body: '{}'),
        };
      },
    );
    secureStore['backend_session_handle'] = 'handle-1';
    // The backend and its token endpoint sit under the watched API, so a reported token request
    // would show up as an event.
    await backendClient.initialize(
      const ThunderIDConfig(
        baseUrl: _base,
        afterSignInUrl: 'com.example.app://callback',
        telemetry: TelemetryConfig(endpoint: '$_base/telemetry', format: TelemetryFormat.json),
        endpoints: EndpointsConfig(
          backend: BackendEndpoints(baseUrl: _base, bypass: BackendBypass(urls: ['$_base/applications'])),
        ),
      ),
    );
    await backendClient.httpRequest(const HttpRequestConfig(url: '$_base/applications', method: 'POST', data: {}));
    await backendClient.flushTelemetry();
    backendClient.dispose();

    expect(calls, containsAll(['POST /api/auth/token', 'POST /applications']));
    expect(sent.expand((batch) => batch.names).toList(), ['application.create']);
  });

  test('reports an embedded sign-in that ends in ERROR, with only a well-formed error code', () async {
    client = build(const TelemetryConfig(endpoint: '$_base/telemetry', format: TelemetryFormat.json));
    await Future<void>.delayed(Duration.zero);
    const payload = EmbeddedSignInPayload(actionId: 'a1', inputs: {'username': 'u'});
    const request = EmbeddedFlowRequestConfig(applicationId: 'app');
    signInResult = {
      'flowStatus': 'ERROR',
      'failureReason': 'Wrong password for alice',
      'error': {
        'code': 'AUTH-1001',
        'message': {'defaultValue': 'Wrong password for alice'},
      },
    };
    await client.signIn(payload: payload, request: request);
    signInResult = {
      'flowStatus': 'ERROR',
      'error': {'code': 'wrong password for alice'},
    };
    await client.signIn(payload: payload, request: request);
    // The shape the native layers send when the flow error has a code and no message.
    signInResult = {
      'flowStatus': 'ERROR',
      'error': {'code': 'AUTH-1002', 'message': null},
    };
    final response = await client.signIn(payload: payload, request: request);
    expect(response.errorMessage, isNull);
    await client.flushTelemetry();

    final events = sent.expand((batch) => batch.events).toList();
    expect(events.map((event) => event['name']).toSet(), {'auth.sign-in-failed'});
    expect(events.map((event) => (event['attributes']! as Map)['data']).toList(), [
      {'error_code': 'AUTH-1001'},
      <String, String>{},
      {'error_code': 'AUTH-1002'},
    ]);
  });

  test('sends no token to another origin, and only a configured one when set', () async {
    client =
        build(const TelemetryConfig(endpoint: 'https://collector.example.com/v1/logs', format: TelemetryFormat.json));
    await Future<void>.delayed(Duration.zero);
    client.track('a.b');
    await client.flushTelemetry();
    expect(sent.single.headers.containsKey('Authorization'), isFalse);

    sent.clear();
    client = build(
      const TelemetryConfig(
        endpoint: 'https://collector.example.com/v1/logs',
        format: TelemetryFormat.json,
        token: TelemetryToken.value('collector-token'),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    client.track('a.b');
    await client.flushTelemetry();
    expect(sent.single.headers['Authorization'], 'Bearer collector-token');
  });

  test('stays off without an endpoint, or with one that does not use HTTPS', () async {
    for (final telemetry in const [TelemetryConfig(), TelemetryConfig(endpoint: 'http://collector.example.com/x')]) {
      client = build(telemetry);
      await Future<void>.delayed(Duration.zero);
      client.track('a.b');
      await client.flushTelemetry();
    }
    expect(sent, isEmpty);
  });

  group('ClientTelemetry', () {
    ClientTelemetry create({
      required Future<User?> Function() currentUser,
      required Map<String, String> store,
      Duration? identityTimeout,
      Future<String> Function()? accessToken,
      Duration? sendTimeout,
    }) =>
        ClientTelemetry.create(
          const TelemetryConfig(endpoint: '$_base/telemetry', format: TelemetryFormat.json),
          baseUrl: _base,
          backend: false,
          allowLoopback: false,
          transport: (method, url, headers, body) async {
            sent.add(_Sent(url, headers, body!));
            return const HttpResponseData(statusCode: 204);
          },
          accessToken: accessToken ?? () async => '',
          currentUser: currentUser,
          store: (
            read: (key) async {
              // Each step of the store waits, so overlapping calls interleave as they would on a device.
              await Future<void>.delayed(const Duration(milliseconds: 1));
              return store[key];
            },
            write: (key, value) async {
              await Future<void>.delayed(const Duration(milliseconds: 1));
              value == null ? store.remove(key) : store[key] = value;
            },
          ),
          identityTimeout: identityTimeout,
          sendTimeout: sendTimeout,
        )!;

    test('completes a sign-out while the identity read never settles, sending the event without it', () async {
      final telemetry = create(
        currentUser: () => Completer<User?>().future,
        store: {},
        identityTimeout: const Duration(milliseconds: 20),
      );
      await expectLater(telemetry.signedOut(), completes);
      final event = sent.single.events.single;
      expect(event['name'], 'auth.sign-out');
      expect((event['attributes']! as Map).containsKey('user'), isFalse);
    });

    test('starts no request when the token arrives after the send timed out', () async {
      final token = Completer<String>();
      final telemetry = create(
        currentUser: () async => null,
        store: {},
        accessToken: () => token.future,
        sendTimeout: const Duration(milliseconds: 20),
      );
      telemetry.telemetry.track('item.a');
      await expectLater(telemetry.telemetry.flush(), completes);
      token.complete('late-token');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(sent, isEmpty);
    });

    test('sends when the token arrives within the send time limit', () async {
      final telemetry = create(
        currentUser: () async => null,
        store: {},
        accessToken: () async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return 'app-token';
        },
        sendTimeout: const Duration(seconds: 2),
      );
      telemetry.telemetry.track('item.a');
      await telemetry.telemetry.flush();
      expect(sent.single.names, ['item.a']);
      expect(sent.single.headers['Authorization'], 'Bearer app-token');
    });

    test('reports a sign-in once when two calls for the same session overlap', () async {
      final store = <String, String>{};
      final telemetry = create(currentUser: () async => const User(_claims), store: store);
      await Future.wait([telemetry.signedIn(), telemetry.signedIn()]);
      await telemetry.telemetry.flush();
      expect(sent.expand((batch) => batch.names).toList(), ['auth.sign-in']);
      expect(store.values.single, '${_claims['sub']}:${_claims['auth_time']}');
    });
  });
}
