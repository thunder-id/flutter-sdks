// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/models/backend.dart';
import 'package:thunderid_flutter/src/models/flow_models.dart';
import 'package:thunderid_flutter/src/models/http_request.dart';
import 'package:thunderid_flutter/src/models/thunderid_config.dart';
import 'package:thunderid_flutter/src/models/thunderid_error.dart';
import 'package:thunderid_flutter/src/models/token_exchange_config.dart';
import 'package:thunderid_flutter/src/thunderid_client.dart';

const _backend = 'https://app.example.com';
const _dataPlane = 'https://dp.example.com/api';

const _config = ThunderIDConfig(
  baseUrl: 'https://api.example.com',
  afterSignInUrl: 'com.example.app://callback',
  afterSignOutUrl: 'com.example.app://signout',
  endpoints: EndpointsConfig(
    backend: BackendEndpoints(
      baseUrl: _backend,
      bypass: BackendBypass(urls: [_dataPlane]),
    ),
  ),
);

class _Request {
  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String? body;

  _Request(this.method, this.url, this.headers, this.body);

  String? header(String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase()) return entry.value;
    }
    return null;
  }
}

HttpResponseData _json(int statusCode, Object body) => HttpResponseData(statusCode: statusCode, body: jsonEncode(body));

/// A fake app backend and data plane: answers each `METHOD url` from a queue, repeating the last
/// response, and records every request.
class _FakeServer {
  final List<_Request> requests = [];
  final Map<String, List<HttpResponseData>> _responses = {};
  Completer<void>? tokenGate;

  void on(String method, String url, List<HttpResponseData> responses) {
    _responses['$method $url'] = [...responses];
  }

  List<_Request> to(String url) => requests.where((r) => '${r.url.origin}${r.url.path}' == url).toList();

  Future<HttpResponseData> send(String method, Uri url, Map<String, String> headers, String? body) async {
    requests.add(_Request(method, url, headers, body));
    if (url.path == '/api/auth/token') await tokenGate?.future;
    final queue = _responses['$method ${url.origin}${url.path}'];
    if (queue == null || queue.isEmpty) return const HttpResponseData(statusCode: 404);
    return queue.length > 1 ? queue.removeAt(0) : queue.first;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ThunderIDClient client;
  late _FakeServer server;
  late Map<String, String> secureStore;
  late DateTime now;
  late String callbackUrl;
  final List<MethodCall> log = [];

  final signedInSession = _json(200, {
    'isSignedIn': true,
    'user': {'sub': 'user-1', 'email': 'ada@example.com'},
    'expiresAt': 1800000000,
  });

  setUp(() {
    log.clear();
    server = _FakeServer();
    secureStore = {};
    now = DateTime(2026, 10, 24, 12);
    callbackUrl = 'com.example.app://callback?session_code=code-1';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.thunderid/sdk'),
      (call) async {
        log.add(call);
        final args = (call.arguments as Map<Object?, Object?>?) ?? const {};
        switch (call.method) {
          case 'initialize':
            return true;
          case 'generatePkce':
            return <String, String>{'verifier': 'verifier-1', 'challenge': 'challenge-1'};
          case 'openAuthSession':
            return callbackUrl;
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
    server.on('GET', '$_backend/api/auth/session', [signedInSession]);
    server.on('POST', '$_backend/api/auth/session', [
      _json(200, {
        'handle': 'handle-1',
        'isSignedIn': true,
        'user': {'sub': 'user-1'},
        'expiresAt': 1800000000,
      }),
    ]);
    server.on('POST', '$_backend/api/auth/refresh', [const HttpResponseData(statusCode: 204)]);
    server.on('POST', '$_backend/api/auth/token', [
      _json(200, {'access_token': 'token-1', 'token_type': 'Bearer', 'expires_in': 300, 'scope': 'dp'}),
    ]);
    client = ThunderIDClient(httpTransport: server.send, clock: () => now);
  });

  tearDown(() {
    client.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dev.thunderid/sdk'), null);
  });

  /// Initializes with a handle already in the secure store, as after a restart.
  Future<void> signedIn() async {
    secureStore['backend_session_handle'] = 'handle-1';
    await client.initialize(_config);
    expect(await client.isSignedIn(), true);
  }

  Matcher throwsCode(ThunderIDErrorCode code) => throwsA(isA<IAMException>().having((e) => e.code, 'code', code));

  group('initialization', () {
    test('does not initialize the native SDK or reach the ThunderID server', () async {
      expect(await client.initialize(_config), true);
      await client.isSignedIn();

      expect(client.isBackendMode(), true);
      expect(log.any((c) => c.method == 'initialize'), false);
      expect(server.requests.any((r) => r.url.host != 'app.example.com'), false);
    });

    test('rejects a non-HTTPS backend before any call', () async {
      const config = ThunderIDConfig(
        baseUrl: 'https://api.example.com',
        afterSignInUrl: 'com.example.app://callback',
        endpoints: EndpointsConfig(backend: BackendEndpoints(baseUrl: 'http://app.example.com')),
      );

      await expectLater(client.initialize(config), throwsCode(ThunderIDErrorCode.invalidConfiguration));
      expect(log, isEmpty);
      expect(server.requests, isEmpty);
    });

    test('isLoading stays true until the first session read settles', () async {
      secureStore['backend_session_handle'] = 'handle-1';
      final gate = Completer<HttpResponseData>();
      client = ThunderIDClient(
        httpTransport: (method, url, headers, body) => gate.future,
        clock: () => now,
      );

      await client.initialize(_config);
      expect(client.isLoading(), true);

      gate.complete(signedInSession);
      expect(await client.isSignedIn(), true);
      expect(client.isLoading(), false);
    });

    test('a client without a stored handle is signed out without calling the backend', () async {
      await client.initialize(_config);

      expect(await client.isSignedIn(), false);
      expect(client.isLoading(), false);
      expect(server.requests, isEmpty);
    });
  });

  group('sign-in handoff', () {
    test('binds the sign-in URL to a PKCE challenge and the redirect URI', () async {
      await client.initialize(_config);
      final uri = Uri.parse(await client.buildSignInUrl());

      expect('${uri.origin}${uri.path}', '$_backend/api/auth/signin');
      expect(uri.queryParameters['redirect_uri'], 'com.example.app://callback');
      expect(uri.queryParameters['code_challenge'], 'challenge-1');
      expect(uri.queryParameters['code_challenge_method'], 'S256');
    });

    test('posts the session code with the verifier, stores the handle, and sends it after', () async {
      await client.initialize(_config);
      final user = await client.signInWithRedirect();

      final open = log.firstWhere((c) => c.method == 'openAuthSession');
      expect((open.arguments as Map<Object?, Object?>)['url'], startsWith('$_backend/api/auth/signin?'));

      final exchange = server.to('$_backend/api/auth/session').single;
      expect(exchange.method, 'POST');
      expect(exchange.header('X-Session-Handle'), isNull);
      final body = jsonDecode(exchange.body!) as Map<String, dynamic>;
      expect(body['session_code'], 'code-1');
      expect(body['code_verifier'], 'verifier-1');

      expect(user.sub, 'user-1');
      expect(secureStore.values, contains('handle-1'));
      expect(await client.isSignedIn(), true);

      server.on('GET', '$_backend/api/auth/proxy/orders', [_json(200, [])]);
      await client.httpRequest(const HttpRequestConfig(url: 'https://api.example.com/orders'));
      expect(server.to('$_backend/api/auth/proxy/orders').single.header('X-Session-Handle'), 'handle-1');
    });

    test('refuses a callback for a sign-in this client did not start', () async {
      await client.initialize(_config);

      await expectLater(
        client.handleRedirectCallback('com.example.app://callback?session_code=code-1'),
        throwsCode(ThunderIDErrorCode.invalidGrant),
      );
      expect(server.requests, isEmpty);
    });

    test('refuses a callback with no session code', () async {
      callbackUrl = 'com.example.app://callback';
      await client.initialize(_config);

      await expectLater(client.signInWithRedirect(), throwsCode(ThunderIDErrorCode.invalidGrant));
      expect(server.requests, isEmpty);
    });

    test('refuses a callback to another redirect URI', () async {
      callbackUrl = 'com.evil.app://callback?session_code=code-1';
      await client.initialize(_config);

      await expectLater(client.signInWithRedirect(), throwsCode(ThunderIDErrorCode.invalidRedirectUri));
      expect(server.requests, isEmpty);
    });

    test('reports an error the backend returns', () async {
      callbackUrl = 'com.example.app://callback?error=access_denied';
      await client.initialize(_config);

      await expectLater(client.signInWithRedirect(), throwsCode(ThunderIDErrorCode.authenticationFailed));
      expect(secureStore, isEmpty);
    });
  });

  group('401 handling', () {
    const ordersUrl = '$_backend/api/auth/proxy/orders';
    const request = HttpRequestConfig(url: 'https://api.example.com/orders');

    test('session_expired refreshes once and retries', () async {
      await signedIn();
      server.on('GET', ordersUrl, [
        _json(401, {'error': 'session_expired'}),
        _json(200, {'orders': []}),
      ]);

      final response = await client.httpRequest(request);

      expect(response.statusCode, 200);
      expect(server.to('$_backend/api/auth/refresh'), hasLength(1));
      expect(server.to(ordersUrl), hasLength(2));
    });

    test('a refresh that fails means signed out', () async {
      await signedIn();
      var signOuts = 0;
      client.onSignOut(() => signOuts++);
      server.on('GET', ordersUrl, [_json(401, {'error': 'session_expired'})]);
      server.on('POST', '$_backend/api/auth/refresh', [_json(401, {'error': 'login_required'})]);

      final response = await client.httpRequest(request);
      await pumpEventQueue();

      expect(response.statusCode, 401);
      expect(server.to(ordersUrl), hasLength(1));
      expect(await client.isSignedIn(), false);
      expect(signOuts, 1);
    });

    test('a second session_expired after a refresh means signed out', () async {
      await signedIn();
      server.on('GET', ordersUrl, [_json(401, {'error': 'session_expired'})]);

      final response = await client.httpRequest(request);

      expect(response.statusCode, 401);
      expect(server.to(ordersUrl), hasLength(2));
      expect(await client.isSignedIn(), false);
    });

    test('login_required signs out, fires the notification, and clears the store', () async {
      await signedIn();
      await client.getAccessToken();
      var signOuts = 0;
      client.onSignOut(() => signOuts++);
      server.on('GET', ordersUrl, [_json(401, {'error': 'login_required'})]);

      final response = await client.httpRequest(request);
      await pumpEventQueue();

      expect(response.statusCode, 401);
      expect(server.to('$_backend/api/auth/refresh'), isEmpty);
      expect(signOuts, 1);
      expect(await client.isSignedIn(), false);
      expect(secureStore, isEmpty);
    });

    test('any other 401 is returned untouched, with no refresh', () async {
      await signedIn();
      server.on('GET', ordersUrl, [_json(401, {'error': 'insufficient_scope'})]);

      final response = await client.httpRequest(request);

      expect(response.statusCode, 401);
      expect(response.body, jsonEncode({'error': 'insufficient_scope'}));
      expect(server.to('$_backend/api/auth/refresh'), isEmpty);
      expect(await client.isSignedIn(), true);
    });
  });

  group('requests', () {
    test('a relative path goes through the proxy', () async {
      await signedIn();
      server.on('POST', '$_backend/api/auth/proxy/orders', [_json(201, {})]);

      final response = await client.httpRequest(
        const HttpRequestConfig(url: '/orders?x=1', method: 'POST', data: {'item': 'a'}),
      );

      expect(response.statusCode, 201);
      final sent = server.to('$_backend/api/auth/proxy/orders').single;
      expect(sent.url.query, 'x=1');
      expect(sent.body, jsonEncode({'item': 'a'}));
      expect(sent.header('Authorization'), isNull);
    });

    test('a URL outside the API base and the bypass URLs is refused, not sent', () async {
      await signedIn();
      final before = server.requests.length;

      for (final url in ['https://evil.example/orders', 'https://api.example.com.evil.example/x', '//evil/x']) {
        await expectLater(
          client.httpRequest(HttpRequestConfig(url: url)),
          throwsCode(ThunderIDErrorCode.backendUnsupportedUrl),
        );
      }
      expect(server.requests.length, before);
    });

    test('httpRequest is refused when sign-in does not run on a backend', () async {
      final native = ThunderIDClient(httpTransport: server.send);
      await native.initialize(const ThunderIDConfig(baseUrl: 'https://localhost:8090'));

      await expectLater(
        native.httpRequest(const HttpRequestConfig(url: 'https://localhost:8090/x')),
        throwsCode(ThunderIDErrorCode.operationNotSupported),
      );
      expect(server.requests, isEmpty);
    });
  });

  group('bypass', () {
    const dpUrl = '$_dataPlane/items';
    const request = HttpRequestConfig(url: dpUrl);

    test('goes straight to the URL with the bearer token and no session handle', () async {
      await signedIn();
      server.on('GET', dpUrl, [_json(200, [])]);

      await client.httpRequest(const HttpRequestConfig(url: dpUrl, headers: {'X-Session-Handle': 'forged'}));

      final sent = server.to(dpUrl).single;
      expect(sent.header('Authorization'), 'Bearer token-1');
      expect(sent.header('X-Session-Handle'), isNull);
      expect(server.to('$_backend/api/auth/token').single.header('X-Session-Handle'), 'handle-1');
    });

    test('matches only at a path or query boundary', () async {
      await signedIn();

      await expectLater(
        client.httpRequest(const HttpRequestConfig(url: '${_dataPlane}x/items')),
        throwsCode(ThunderIDErrorCode.backendUnsupportedUrl),
      );
      server.on('GET', _dataPlane, [_json(200, [])]);
      await client.httpRequest(const HttpRequestConfig(url: '$_dataPlane?page=2'));
      expect(server.to(_dataPlane), hasLength(1));
    });

    test('reuses the stored token, and renews it 30 seconds before expiry', () async {
      await signedIn();
      server.on('GET', dpUrl, [_json(200, [])]);
      server.on('POST', '$_backend/api/auth/token', [
        _json(200, {'access_token': 'token-1', 'token_type': 'Bearer', 'expires_in': 300}),
        _json(200, {'access_token': 'token-2', 'token_type': 'Bearer', 'expires_in': 300}),
      ]);

      await client.httpRequest(request);
      now = now.add(const Duration(seconds: 200));
      await client.httpRequest(request);
      expect(server.to('$_backend/api/auth/token'), hasLength(1));

      now = now.add(const Duration(seconds: 75));
      await client.httpRequest(request);
      expect(server.to('$_backend/api/auth/token'), hasLength(2));
      expect(server.to(dpUrl).map((r) => r.header('Authorization')), [
        'Bearer token-1',
        'Bearer token-1',
        'Bearer token-2',
      ]);
    });

    test('stores the token with its issue time and without a refresh token', () async {
      await signedIn();
      server.on('POST', '$_backend/api/auth/token', [
        _json(200, {'access_token': 'token-1', 'expires_in': 300, 'refresh_token': 'never-kept'}),
      ]);

      await client.getAccessToken();

      final stored = jsonDecode(secureStore['backend_access_token']!) as Map<String, dynamic>;
      expect(stored['access_token'], 'token-1');
      expect(stored['created_at'], now.millisecondsSinceEpoch);
      expect(stored.containsKey('refresh_token'), false);
    });

    test('concurrent callers share one token request', () async {
      await signedIn();
      server.tokenGate = Completer<void>();

      final first = client.getAccessToken();
      final second = client.getAccessToken();
      await pumpEventQueue();
      server.tokenGate!.complete();

      expect(await Future.wait([first, second]), ['token-1', 'token-1']);
      expect(server.to('$_backend/api/auth/token'), hasLength(1));
    });

    test('gets a new token and retries once on a 401 from the API', () async {
      await signedIn();
      server.on('GET', dpUrl, [const HttpResponseData(statusCode: 401), _json(200, [])]);
      server.on('POST', '$_backend/api/auth/token', [
        _json(200, {'access_token': 'token-1', 'expires_in': 300}),
        _json(200, {'access_token': 'token-2', 'expires_in': 300}),
      ]);

      final response = await client.httpRequest(request);

      expect(response.statusCode, 200);
      expect(server.to(dpUrl).map((r) => r.header('Authorization')), ['Bearer token-1', 'Bearer token-2']);
    });

    test('a second 401 from the API goes back to the caller', () async {
      await signedIn();
      server.on('GET', dpUrl, [const HttpResponseData(statusCode: 401, body: 'denied')]);

      final response = await client.httpRequest(request);

      expect(response.statusCode, 401);
      expect(response.body, 'denied');
      expect(server.to(dpUrl), hasLength(2));
      expect(server.to('$_backend/api/auth/token'), hasLength(2));
      expect(await client.isSignedIn(), true);
    });

    test('session_expired from the token endpoint refreshes the session and asks again', () async {
      await signedIn();
      server.on('POST', '$_backend/api/auth/token', [
        _json(401, {'error': 'session_expired'}),
        _json(200, {'access_token': 'token-2', 'expires_in': 300}),
      ]);

      expect(await client.getAccessToken(), 'token-2');
      expect(server.to('$_backend/api/auth/refresh'), hasLength(1));
    });

    test('login_required from the token endpoint signs out', () async {
      await signedIn();
      var signOuts = 0;
      client.onSignOut(() => signOuts++);
      server.on('POST', '$_backend/api/auth/token', [_json(401, {'error': 'login_required'})]);

      await expectLater(client.getAccessToken(), throwsCode(ThunderIDErrorCode.sessionExpired));
      await pumpEventQueue();

      expect(signOuts, 1);
      expect(await client.isSignedIn(), false);
    });

    test('with attachToken off, carries no token and never calls the token endpoint', () async {
      const config = ThunderIDConfig(
        baseUrl: 'https://api.example.com',
        afterSignInUrl: 'com.example.app://callback',
        endpoints: EndpointsConfig(
          backend: BackendEndpoints(
            baseUrl: _backend,
            bypass: BackendBypass(urls: [_dataPlane], attachToken: false),
          ),
        ),
      );
      secureStore['backend_session_handle'] = 'handle-1';
      await client.initialize(config);
      server.on('GET', dpUrl, [const HttpResponseData(statusCode: 401)]);

      final response = await client.httpRequest(request);

      expect(response.statusCode, 401);
      expect(server.to(dpUrl).single.header('Authorization'), isNull);
      expect(server.to('$_backend/api/auth/token'), isEmpty);
    });
  });

  group('sign-out', () {
    test('ends the backend session, clears the handle and token, and returns its URL', () async {
      await signedIn();
      await client.getAccessToken();
      var signOuts = 0;
      client.onSignOut(() => signOuts++);
      server.on('POST', '$_backend/api/auth/signout', [
        _json(200, {'redirectUrl': 'https://idp.example.com/oidc/logout?x=1'}),
      ]);

      final url = await client.signOut();

      expect(url, 'https://idp.example.com/oidc/logout?x=1');
      expect(server.to('$_backend/api/auth/signout').single.header('X-Session-Handle'), 'handle-1');
      expect(secureStore, isEmpty);
      expect(await client.isSignedIn(), false);
      expect(signOuts, 0);
    });

    test('clears local state and reports the failure when the backend refuses', () async {
      await signedIn();
      server.on('POST', '$_backend/api/auth/signout', [const HttpResponseData(statusCode: 500)]);

      await expectLater(client.signOut(), throwsCode(ThunderIDErrorCode.serverError));
      expect(secureStore, isEmpty);
      expect(await client.isSignedIn(), false);
    });

    test('falls back to afterSignOutUrl when the backend sends no URL', () async {
      await signedIn();
      server.on('POST', '$_backend/api/auth/signout', [_json(200, {})]);

      expect(await client.signOut(), 'com.example.app://signout');
    });
  });

  group('client surface', () {
    test('user and claims come from the backend session', () async {
      await signedIn();

      final user = await client.getUser();
      expect(user.sub, 'user-1');
      expect(user.email, 'ada@example.com');
    });

    test('getAccessToken returns the token from the token endpoint', () async {
      await signedIn();

      expect(await client.getAccessToken(), 'token-1');
      expect(server.to('$_backend/api/auth/token').single.method, 'POST');
    });

    test('token, profile, and embedded operations are refused', () async {
      await signedIn();
      final notSupported = throwsCode(ThunderIDErrorCode.operationNotSupported);

      await expectLater(
        client.exchangeToken(const TokenExchangeRequestConfig(subjectToken: 's', subjectTokenType: 't')),
        notSupported,
      );
      await expectLater(
        client.signIn(
          payload: const EmbeddedSignInPayload(actionId: 'init'),
          request: const EmbeddedFlowRequestConfig(applicationId: 'app-1'),
        ),
        notSupported,
      );
      await expectLater(client.signUp(), notSupported);
      await expectLater(client.getUserProfile(), notSupported);
      await expectLater(client.reInitialize(baseUrl: 'https://other.example.com'), notSupported);
      expect(log.any((c) => const {'signIn', 'signUp', 'exchangeToken', 'getUserProfile'}.contains(c.method)), false);
    });
  });
}
