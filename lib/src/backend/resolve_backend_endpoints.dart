// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../models/backend.dart';
import '../models/thunderid_config.dart';
import '../models/thunderid_error.dart';

const String _defaultBackendBasePath = '/api/auth';

/// The backend endpoints, fully resolved against the backend's base URL.
class ResolvedBackendEndpoints {
  final Uri signIn;
  final Uri session;
  final Uri checkSession;
  final Uri refresh;
  final Uri signOut;

  /// The proxy prefix as an absolute URL, without a trailing slash: the app's API base.
  final String proxy;

  final Uri token;

  /// Where the backend sends the browser back to after sign-in: the app's registered scheme.
  final String redirectUri;

  /// Base URLs whose requests skip the proxy, without trailing slashes.
  final List<String> bypassUrls;

  /// Whether requests that skip the proxy carry the access token.
  final bool attachToken;

  const ResolvedBackendEndpoints({
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
/// [ThunderIDConfig.baseUrl] is the backend's base URL. An endpoint given as a path resolves
/// against it, and one given as an absolute HTTPS URL is used as it is.
///
/// Fails with [ThunderIDErrorCode.invalidConfiguration], before any network call, when the
/// backend's base URL, an absolute endpoint, or a bypass URL does not use HTTPS, an
/// endpoint is neither a path nor an absolute URL, or [ThunderIDConfig.afterSignInUrl] (the
/// redirect URI the backend returns to) is missing.
///
/// ```dart
/// resolveBackendEndpoints(config)?.signIn; // https://app.example.com/api/auth/signin
/// ```
ResolvedBackendEndpoints? resolveBackendEndpoints(ThunderIDConfig config) {
  final endpoints = config.endpoints?.backend;
  if (endpoints == null) return null;

  if (!_isHttpsUrl(config.baseUrl)) {
    throw const IAMException(
      ThunderIDErrorCode.invalidConfiguration,
      'baseUrl must be an HTTPS URL when sign-in runs on a backend (endpoints.backend): it is the backend',
    );
  }
  final baseUrl = _trimTrailingSlashes(config.baseUrl);

  Uri resolve(String name, String? value, String fallback) =>
      Uri.parse(_resolveEndpoint(baseUrl, name, value, fallback));

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
    if (!_isHttpsUrl(url)) {
      throw const IAMException(
        ThunderIDErrorCode.invalidConfiguration,
        'Every endpoints.backend.bypass.urls entry must be an HTTPS URL',
      );
    }
  }

  return ResolvedBackendEndpoints(
    signIn: resolve('signIn', endpoints.signIn, '/signin'),
    session: resolve('session', endpoints.session, '/session'),
    checkSession: resolve('checkSession', endpoints.checkSession, '/checksession'),
    refresh: resolve('refresh', endpoints.refresh, '/refresh'),
    signOut: resolve('signOut', endpoints.signOut, '/signout'),
    proxy: _trimTrailingSlashes(_resolveEndpoint(baseUrl, 'proxy', endpoints.proxy, '/proxy')),
    token: resolve('token', endpoints.token, '/token'),
    redirectUri: redirectUri!,
    bypassUrls: bypass.urls.map(_trimTrailingSlashes).toList(growable: false),
    attachToken: bypass.attachToken,
  );
}

/// Resolves an endpoint: a path (starting with a single `/`) against the backend's base URL, and
/// an absolute HTTPS URL as it is. Anything else, including `//host/path`, is refused.
String _resolveEndpoint(String baseUrl, String name, String? value, String fallback) {
  final endpoint = value ?? '$_defaultBackendBasePath$fallback';
  if (endpoint.startsWith('/') && !endpoint.startsWith('//')) return '$baseUrl$endpoint';
  if (_isHttpsUrl(endpoint)) return endpoint;
  throw IAMException(
    ThunderIDErrorCode.invalidConfiguration,
    'endpoints.backend.$name must be a path starting with "/" or an HTTPS URL',
  );
}

bool _isHttpsUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
}

String _trimTrailingSlashes(String url) => url.replaceFirst(RegExp(r'/+$'), '');
