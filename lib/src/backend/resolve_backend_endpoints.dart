// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../models/backend.dart';
import '../models/thunderid_config.dart';
import '../models/thunderid_error.dart';

const String _defaultBackendBasePath = '/api/auth';

/// The backend endpoints, fully resolved against the backend's base URL, with the API base whose
/// requests go through the proxy.
class ResolvedBackendEndpoints {
  /// The app's API base: requests under it are sent through [proxy].
  final String apiBaseUrl;

  final Uri signIn;
  final Uri session;
  final Uri checkSession;
  final Uri refresh;
  final Uri signOut;

  /// The proxy prefix as an absolute URL, without a trailing slash.
  final String proxy;

  final Uri token;

  /// Where the backend sends the browser back to after sign-in: the app's registered scheme.
  final String redirectUri;

  /// Base URLs whose requests skip the proxy, without trailing slashes.
  final List<String> bypassUrls;

  /// Whether requests that skip the proxy carry the access token.
  final bool attachToken;

  const ResolvedBackendEndpoints({
    required this.apiBaseUrl,
    required this.signIn,
    required this.session,
    required this.checkSession,
    required this.refresh,
    required this.signOut,
    required this.proxy,
    required this.token,
    required this.redirectUri,
    required this.bypassUrls,
    required this.attachToken,
  });
}

/// Resolves the backend endpoints from `endpoints.backend`, or returns `null` when it is not set
/// and sign-in does not run on a backend.
///
/// Fails with [ThunderIDErrorCode.invalidConfiguration], before any network call, when the
/// backend's base URL or a bypass URL does not use HTTPS, an endpoint is not a path, or
/// [ThunderIDConfig.afterSignInUrl] (the redirect URI the backend returns to) is missing.
///
/// ```dart
/// resolveBackendEndpoints(config)?.signIn; // https://app.example.com/api/auth/signin
/// ```
ResolvedBackendEndpoints? resolveBackendEndpoints(ThunderIDConfig config) {
  final endpoints = config.endpoints?.backend;
  if (endpoints == null) return null;

  final base = Uri.tryParse(endpoints.baseUrl);
  if (base == null || base.scheme != 'https' || base.host.isEmpty) {
    throw const IAMException(
      ThunderIDErrorCode.invalidConfiguration,
      'endpoints.backend.baseUrl must be an HTTPS URL',
    );
  }
  final baseUrl = _trimTrailingSlashes(endpoints.baseUrl);

  Uri resolve(String name, String? path, String fallback) => Uri.parse(_resolvePath(baseUrl, name, path, fallback));

  final redirectUri = config.afterSignInUrl;
  final redirect = redirectUri == null ? null : Uri.tryParse(redirectUri);
  if (redirect == null || !redirect.hasScheme) {
    throw const IAMException(
      ThunderIDErrorCode.invalidConfiguration,
      'afterSignInUrl is required when sign-in runs on a backend: it is the redirect URI the backend returns to',
    );
  }

  final bypass = endpoints.bypass ?? const BackendBypass();
  for (final url in bypass.urls) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const IAMException(
        ThunderIDErrorCode.invalidConfiguration,
        'Every endpoints.backend.bypass.urls entry must be an HTTPS URL',
      );
    }
  }

  return ResolvedBackendEndpoints(
    apiBaseUrl: _trimTrailingSlashes(config.baseUrl),
    signIn: resolve('signIn', endpoints.signIn, '/signin'),
    session: resolve('session', endpoints.session, '/session'),
    checkSession: resolve('checkSession', endpoints.checkSession, '/checksession'),
    refresh: resolve('refresh', endpoints.refresh, '/refresh'),
    signOut: resolve('signOut', endpoints.signOut, '/signout'),
    proxy: _trimTrailingSlashes(_resolvePath(baseUrl, 'proxy', endpoints.proxy, '/proxy')),
    token: resolve('token', endpoints.token, '/token'),
    redirectUri: redirectUri!,
    bypassUrls: bypass.urls.map(_trimTrailingSlashes).toList(growable: false),
    attachToken: bypass.attachToken,
  );
}

/// Resolves an endpoint path against the backend's base URL. A path has to start with a single
/// `/`, so every endpoint stays on the pinned backend.
String _resolvePath(String baseUrl, String name, String? path, String fallback) {
  final value = path ?? '$_defaultBackendBasePath$fallback';
  if (!value.startsWith('/') || value.startsWith('//')) {
    throw IAMException(
      ThunderIDErrorCode.invalidConfiguration,
      'endpoints.backend.$name must be a path starting with "/"',
    );
  }
  return '$baseUrl$value';
}

String _trimTrailingSlashes(String url) => url.replaceFirst(RegExp(r'/+$'), '');
