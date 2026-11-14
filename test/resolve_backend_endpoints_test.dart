// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/backend/resolve_backend_endpoints.dart';
import 'package:thunderid_flutter/src/models/backend.dart';
import 'package:thunderid_flutter/src/models/thunderid_config.dart';
import 'package:thunderid_flutter/src/models/thunderid_error.dart';

ThunderIDConfig _config(
  BackendEndpoints backend, {
  String baseUrl = 'https://app.example.com/',
  String? afterSignInUrl = 'com.example.app://callback',
}) =>
    ThunderIDConfig(
      baseUrl: baseUrl,
      afterSignInUrl: afterSignInUrl,
      endpoints: EndpointsConfig(backend: backend),
    );

Matcher _invalidConfiguration() =>
    throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.invalidConfiguration));

void main() {
  test('returns null when endpoints.backend is not set', () {
    expect(resolveBackendEndpoints(const ThunderIDConfig(baseUrl: 'https://localhost:8090')), isNull);
    expect(
      resolveBackendEndpoints(const ThunderIDConfig(baseUrl: 'https://localhost:8090', endpoints: EndpointsConfig())),
      isNull,
    );
  });

  test('defaults every endpoint under /api/auth on baseUrl, the backend', () {
    final endpoints = resolveBackendEndpoints(_config(const BackendEndpoints()))!;

    expect(endpoints.signIn.toString(), 'https://app.example.com/api/auth/signin');
    expect(endpoints.session.toString(), 'https://app.example.com/api/auth/session');
    expect(endpoints.checkSession.toString(), 'https://app.example.com/api/auth/checksession');
    expect(endpoints.refresh.toString(), 'https://app.example.com/api/auth/refresh');
    expect(endpoints.signOut.toString(), 'https://app.example.com/api/auth/signout');
    expect(endpoints.proxy, 'https://app.example.com/api/auth/proxy');
    expect(endpoints.token.toString(), 'https://app.example.com/api/auth/token');
    expect(endpoints.redirectUri, 'com.example.app://callback');
    expect(endpoints.bypassUrls, isEmpty);
    expect(endpoints.attachToken, true);
  });

  test('honours overrides and trims trailing slashes', () {
    final endpoints = resolveBackendEndpoints(
      _config(
        const BackendEndpoints(
          signIn: '/auth/login',
          session: '/auth/me',
          checkSession: '/auth/alive',
          refresh: '/auth/renew',
          signOut: '/auth/logout',
          proxy: '/auth/api/',
          token: '/auth/dp-token',
          bypass: BackendBypass(urls: ['https://dp.example.com/api/'], attachToken: false),
        ),
      ),
    )!;

    expect(endpoints.signIn.toString(), 'https://app.example.com/auth/login');
    expect(endpoints.session.toString(), 'https://app.example.com/auth/me');
    expect(endpoints.checkSession.toString(), 'https://app.example.com/auth/alive');
    expect(endpoints.refresh.toString(), 'https://app.example.com/auth/renew');
    expect(endpoints.signOut.toString(), 'https://app.example.com/auth/logout');
    expect(endpoints.proxy, 'https://app.example.com/auth/api');
    expect(endpoints.token.toString(), 'https://app.example.com/auth/dp-token');
    expect(endpoints.bypassUrls, ['https://dp.example.com/api']);
    expect(endpoints.attachToken, false);
  });

  test('uses an absolute HTTPS endpoint as it is', () {
    final endpoints = resolveBackendEndpoints(
      _config(
        const BackendEndpoints(
          session: 'https://auth.example.com/session/app',
          proxy: 'https://gateway.example.com/app/api/',
        ),
      ),
    )!;

    expect(endpoints.session.toString(), 'https://auth.example.com/session/app');
    expect(endpoints.proxy, 'https://gateway.example.com/app/api');
    expect(endpoints.signIn.toString(), 'https://app.example.com/api/auth/signin');
  });

  test('requires an HTTPS baseUrl, the backend', () {
    expect(
      () => resolveBackendEndpoints(_config(const BackendEndpoints(), baseUrl: 'http://app.example.com')),
      _invalidConfiguration(),
    );
    expect(
      () => resolveBackendEndpoints(_config(const BackendEndpoints(), baseUrl: 'app.example.com')),
      _invalidConfiguration(),
    );
  });

  test('requires HTTPS bypass URLs', () {
    expect(
      () => resolveBackendEndpoints(
        _config(
          const BackendEndpoints(
            bypass: BackendBypass(urls: ['http://dp.example.com']),
          ),
        ),
      ),
      _invalidConfiguration(),
    );
  });

  test('refuses an endpoint that is neither a path nor an HTTPS URL', () {
    expect(
      () => resolveBackendEndpoints(_config(const BackendEndpoints(token: 'http://app.example.com/token'))),
      _invalidConfiguration(),
    );
    expect(
      () => resolveBackendEndpoints(_config(const BackendEndpoints(proxy: '//evil.example/proxy'))),
      _invalidConfiguration(),
    );
    expect(
      () => resolveBackendEndpoints(_config(const BackendEndpoints(session: 'api/auth/session'))),
      _invalidConfiguration(),
    );
  });

  test('requires afterSignInUrl as the redirect URI', () {
    expect(
      () => resolveBackendEndpoints(
        _config(const BackendEndpoints(), afterSignInUrl: null),
      ),
      _invalidConfiguration(),
    );
  });

  test('toMap keeps the backend and session settings away from the native SDK', () {
    const config = ThunderIDConfig(
      baseUrl: 'https://app.example.com',
      endpoints: EndpointsConfig(backend: BackendEndpoints(proxy: 'https://api.example.com/proxy')),
      session: SessionConfig(checkInterval: 30),
    );
    final map = config.toMap();

    expect(map.containsKey('endpoints'), false);
    expect(map.containsKey('session'), false);
    expect(map.values.whereType<String>().any((v) => v.contains('api.example.com')), false);
  });
}
