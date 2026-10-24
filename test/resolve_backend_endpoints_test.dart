// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/backend/resolve_backend_endpoints.dart';
import 'package:thunderid_flutter/src/models/backend.dart';
import 'package:thunderid_flutter/src/models/thunderid_config.dart';
import 'package:thunderid_flutter/src/models/thunderid_error.dart';

ThunderIDConfig _config(BackendEndpoints backend, {String? afterSignInUrl = 'com.example.app://callback'}) =>
    ThunderIDConfig(
      baseUrl: 'https://api.example.com/',
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

  test('defaults every endpoint under /api/auth on the backend base URL', () {
    final endpoints = resolveBackendEndpoints(_config(const BackendEndpoints(baseUrl: 'https://app.example.com/')))!;

    expect(endpoints.signIn.toString(), 'https://app.example.com/api/auth/signin');
    expect(endpoints.session.toString(), 'https://app.example.com/api/auth/session');
    expect(endpoints.checkSession.toString(), 'https://app.example.com/api/auth/checksession');
    expect(endpoints.refresh.toString(), 'https://app.example.com/api/auth/refresh');
    expect(endpoints.signOut.toString(), 'https://app.example.com/api/auth/signout');
    expect(endpoints.proxy, 'https://app.example.com/api/auth/proxy');
    expect(endpoints.token.toString(), 'https://app.example.com/api/auth/token');
    expect(endpoints.apiBaseUrl, 'https://api.example.com');
    expect(endpoints.redirectUri, 'com.example.app://callback');
    expect(endpoints.bypassUrls, isEmpty);
    expect(endpoints.attachToken, true);
  });

  test('honours overrides and trims trailing slashes', () {
    final endpoints = resolveBackendEndpoints(
      _config(
        const BackendEndpoints(
          baseUrl: 'https://app.example.com',
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

  test('requires an HTTPS backend base URL', () {
    expect(
      () => resolveBackendEndpoints(_config(const BackendEndpoints(baseUrl: 'http://app.example.com'))),
      _invalidConfiguration(),
    );
    expect(
      () => resolveBackendEndpoints(_config(const BackendEndpoints(baseUrl: 'app.example.com'))),
      _invalidConfiguration(),
    );
  });

  test('requires HTTPS bypass URLs', () {
    expect(
      () => resolveBackendEndpoints(
        _config(
          const BackendEndpoints(
            baseUrl: 'https://app.example.com',
            bypass: BackendBypass(urls: ['http://dp.example.com']),
          ),
        ),
      ),
      _invalidConfiguration(),
    );
  });

  test('keeps every endpoint on the backend: an absolute URL is rejected', () {
    expect(
      () => resolveBackendEndpoints(
        _config(const BackendEndpoints(baseUrl: 'https://app.example.com', token: 'https://evil.example/token')),
      ),
      _invalidConfiguration(),
    );
    expect(
      () => resolveBackendEndpoints(
        _config(const BackendEndpoints(baseUrl: 'https://app.example.com', proxy: '//evil.example/proxy')),
      ),
      _invalidConfiguration(),
    );
  });

  test('requires afterSignInUrl as the redirect URI', () {
    expect(
      () => resolveBackendEndpoints(
        _config(const BackendEndpoints(baseUrl: 'https://app.example.com'), afterSignInUrl: null),
      ),
      _invalidConfiguration(),
    );
  });

  test('toMap keeps the backend and session settings away from the native SDK', () {
    const config = ThunderIDConfig(
      baseUrl: 'https://api.example.com',
      endpoints: EndpointsConfig(backend: BackendEndpoints(baseUrl: 'https://app.example.com')),
      session: SessionConfig(checkInterval: 30),
    );
    final map = config.toMap();

    expect(map.containsKey('endpoints'), false);
    expect(map.containsKey('session'), false);
    expect(map.values.whereType<String>().any((v) => v.contains('app.example.com')), false);
  });
}
