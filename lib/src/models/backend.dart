// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

/// The app backend's auth endpoints, set under [EndpointsConfig.backend]. Setting them hands
/// sign-in to a backend the app owns (the Backend for Frontend pattern of RFC 10017): the backend
/// runs the OAuth flow and keeps the tokens. The app only holds an opaque session handle in the
/// platform's secure store, and its API calls go through the backend, which attaches the access
/// token.
///
/// Every endpoint is a path under [baseUrl]. Any endpoint left unset defaults to a fixed path
/// under `/api/auth`.
///
/// ```dart
/// endpoints: EndpointsConfig(
///   backend: BackendEndpoints(baseUrl: 'https://app.example.com'),
/// ),
/// ```
class BackendEndpoints {
  /// Base URL of the backend. Required, and must use HTTPS: every backend call goes to it.
  final String baseUrl;

  /// Starts sign-in. Defaults to `/api/auth/signin`.
  final String? signIn;

  /// Starts the session from the sign-in's one-time code, and reports the signed-in user.
  /// Defaults to `/api/auth/session`.
  final String? session;

  /// Reports only whether the session is still live, without refreshing it or counting as
  /// activity, so the SDK can poll it. Defaults to `/api/auth/checksession`.
  final String? checkSession;

  /// Refreshes the session. Defaults to `/api/auth/refresh`.
  final String? refresh;

  /// Ends the session. Defaults to `/api/auth/signout`.
  final String? signOut;

  /// Prefix of the API proxy. Requests under [ThunderIDConfig.baseUrl] are sent through it.
  /// Defaults to `/api/auth/proxy`.
  final String? proxy;

  /// Issues the access token for [bypass], as an OAuth token response without a refresh token.
  /// Defaults to `/api/auth/token`.
  final String? token;

  /// Requests that skip the proxy and go straight from the app.
  final BackendBypass? bypass;

  const BackendEndpoints({
    required this.baseUrl,
    this.signIn,
    this.session,
    this.checkSession,
    this.refresh,
    this.signOut,
    this.proxy,
    this.token,
    this.bypass,
  });
}

/// Requests the app sends directly rather than through the proxy, such as calls to a data plane
/// on another origin.
///
/// ```dart
/// bypass: BackendBypass(urls: ['https://dp.example.com/api']),
/// ```
class BackendBypass {
  /// Base URLs whose requests skip the proxy. A request matches its own base URL or anything under
  /// it. Every entry must use HTTPS.
  final List<String> urls;

  /// Attach the access token from [BackendEndpoints.token] as `Authorization: Bearer`, and get a
  /// new one and retry once on a 401. Defaults to `true`. With `false`, requests go out with no
  /// credentials and the token endpoint is never called for them.
  final bool attachToken;

  const BackendBypass({this.urls = const [], this.attachToken = true});
}

/// What the backend's session endpoint reports.
class BackendSession {
  final bool isSignedIn;

  /// The ID token's user claims, without the protocol claims.
  final Map<String, dynamic>? user;

  /// When the access token expires, in seconds since the epoch.
  final int? expiresAt;

  const BackendSession({required this.isSignedIn, this.user, this.expiresAt});

  const BackendSession.signedOut()
      : isSignedIn = false,
        user = null,
        expiresAt = null;

  factory BackendSession.fromMap(Map<String, dynamic> map) {
    final Object? user = map['user'];
    final Object? expiresAt = map['expiresAt'];
    return BackendSession(
      isSignedIn: map['isSignedIn'] == true,
      user: user is Map ? user.cast<String, dynamic>() : null,
      expiresAt: expiresAt is num ? expiresAt.toInt() : null,
    );
  }
}
