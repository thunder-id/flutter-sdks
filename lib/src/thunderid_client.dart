// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'backend/backend_client.dart';
import 'backend/backend_http_client.dart';
import 'backend/http_transport.dart';
import 'backend/resolve_backend_endpoints.dart';
import 'channel/thunderid_channel.dart';
import 'management/permissions.dart';
import 'management/thunderid_management_client.dart';
import 'models/attribute_verification.dart';
import 'models/flow_models.dart';
import 'models/http_request.dart';
import 'models/sign_in_options.dart';
import 'models/sign_out_options.dart';
import 'models/thunderid_config.dart';
import 'models/thunderid_error.dart';
import 'models/token_exchange_config.dart';
import 'models/token_response.dart';
import 'models/user.dart';
import 'models/user_profile.dart';

/// Flutter SDK client — Core Lib layer, delegates all protocol operations to
/// the native iOS and Android Platform SDKs via [ThunderIDChannel] (spec §7.1).
///
/// When [ThunderIDConfig.endpoints] sets a backend, sign-in runs on that backend instead, and the
/// native SDKs are used only for the system browser session and the secure store.
class ThunderIDClient {
  final ThunderIDChannel _channel;
  final HttpTransport _httpTransport;
  final DateTime Function() _now;
  bool _initialized = false;
  bool _isLoading = false;
  String? _afterSignOutUrl;
  ThunderIDConfig? _config;
  ThunderIDManagementClient? _management;

  BackendClient? _backend;
  BackendHttpClient? _backendHttp;
  void Function()? _stopBackendWatch;
  final List<void Function()> _signOutListeners = [];

  /// [httpTransport] and [clock] replace the HTTP transport and the clock used when sign-in runs
  /// on a backend. They exist for tests.
  ThunderIDClient({
    ThunderIDChannel? channel,
    HttpTransport? httpTransport,
    DateTime Function()? clock,
  })  : _channel = channel ?? ThunderIDChannel(),
        _httpTransport = httpTransport ?? ioHttpTransport,
        _now = clock ?? DateTime.now;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Initializes the SDK. Must be called once before any other method (spec §5.1).
  Future<bool> initialize(ThunderIDConfig config) async {
    if (_initialized) {
      throw const IAMException(ThunderIDErrorCode.alreadyInitialized, 'SDK is already initialized');
    }
    // Validated before anything else, so a malformed backend fails before any network call.
    final backendEndpoints = resolveBackendEndpoints(config);
    if (backendEndpoints != null) {
      _initializeBackend(backendEndpoints, config);
      return true;
    }
    final result = await _channel.invoke<bool>('initialize', config.toMap());
    _initialized = result ?? false;
    if (_initialized) _config = config;
    return _initialized;
  }

  Future<bool> reInitialize({String? baseUrl, String? clientId}) async {
    _requireInitialized();
    _refuseOnBackend('reInitialize');
    final result = await _channel.invoke<bool>('reInitialize', {
      if (baseUrl != null) 'baseUrl': baseUrl,
      if (clientId != null) 'clientId': clientId,
    });
    return result ?? false;
  }

  // ── Authentication ────────────────────────────────────────────────────────

  /// App-native sign-in via Flow Execution API (spec §6.1).
  Future<EmbeddedFlowResponse> signIn({
    required EmbeddedSignInPayload payload,
    required EmbeddedFlowRequestConfig request,
    String? sessionId,
  }) async {
    _requireInitialized();
    _refuseOnBackend('The embedded sign-in flow');
    _isLoading = true;
    try {
      final result = await _channel.invokeMap('signIn', {
        'payload': payload.toMap(),
        'request': request.toMap(),
        if (sessionId != null) 'sessionId': sessionId,
      });
      return EmbeddedFlowResponse.fromMap(result);
    } finally {
      _isLoading = false;
    }
  }

  /// Resumes a TRIGGER action (federated/social login) after the server
  /// responded with `type: "REDIRECTION"` (spec §6.1 embedded flow, federated
  /// sign-in extension). The native layer opens [redirectUrl] in a system
  /// browser (Custom Tabs on Android, `ASWebAuthenticationSession` on iOS),
  /// waits for the provider to redirect back to the app's registered
  /// callback scheme, extracts the `code` query parameter, and resubmits the
  /// same flow with `inputs: {"code": code}` — mirroring the exact resubmit
  /// pattern used by the native Android/iOS SDKs.
  ///
  /// Throws [IAMException] with [ThunderIDErrorCode.federatedAuthCancelled]
  /// if the user dismisses the browser without completing sign-in; callers
  /// should treat this as a silent reset rather than an error.
  Future<EmbeddedFlowResponse> continueFederatedAuth({
    required String redirectUrl,
    required String actionId,
    required String applicationId,
    String? flowId,
    String? challengeToken,
  }) async {
    _requireInitialized();
    _refuseOnBackend('continueFederatedAuth');
    _isLoading = true;
    try {
      final result = await _channel.invokeMap('continueFederatedAuth', {
        'redirectUrl': redirectUrl,
        'actionId': actionId,
        'applicationId': applicationId,
        if (flowId != null) 'flowId': flowId,
        if (challengeToken != null) 'challengeToken': challengeToken,
      });
      return EmbeddedFlowResponse.fromMap(result);
    } finally {
      _isLoading = false;
    }
  }

  /// Performs a native WebAuthn assertion ceremony (sign-in with an existing passkey) after
  /// the server responded with a `passkeyChallenge` in `data.additionalData`, and returns the
  /// flat `credentialId`/`clientDataJSON`/`authenticatorData`/`signature`/`userHandle` input map
  /// to resubmit via [signIn].
  Future<Map<String, String>> performPasskeyAuthentication({required String requestOptionsJson}) async {
    _requireInitialized();
    _refuseOnBackend('performPasskeyAuthentication');
    final result = await _channel.invokeMap('performPasskeyAuthentication', {
      'requestOptionsJson': requestOptionsJson,
    });
    return result.cast<String, String>();
  }

  /// Performs a native WebAuthn attestation ceremony (registers a new passkey) after the server
  /// responded with `passkeyCreationOptions` in `data.additionalData`, and returns the flat
  /// `credentialId`/`clientDataJSON`/`attestationObject` input map to resubmit via [signIn].
  Future<Map<String, String>> performPasskeyRegistration({required String creationOptionsJson}) async {
    _requireInitialized();
    _refuseOnBackend('performPasskeyRegistration');
    final result = await _channel.invokeMap('performPasskeyRegistration', {
      'creationOptionsJson': creationOptionsJson,
    });
    return result.cast<String, String>();
  }

  /// Builds the redirect-based sign-in URL. Open this in an in-app browser or
  /// custom tab, then call [handleRedirectCallback] with the callback URL.
  ///
  /// When sign-in runs on a backend, this is the backend's sign-in URL, bound to a fresh PKCE
  /// pair; [options] do not apply to it. [signInWithRedirect] opens it and completes sign-in.
  Future<String> buildSignInUrl({SignInOptions? options}) async {
    _requireInitialized();
    final backend = _backend;
    if (backend != null) return backend.buildSignInUrl();
    final result = await _channel.invoke<String>('buildSignInUrl', {
      if (options != null) 'options': options.toMap(),
    });
    return result ?? '';
  }

  /// Handles the callback URL after a redirect-based sign-in (spec §6.1).
  ///
  /// When sign-in runs on a backend, the callback carries a one-time `session_code`, which is
  /// exchanged with the PKCE verifier of the sign-in [buildSignInUrl] started.
  Future<User> handleRedirectCallback(String url) async {
    _requireInitialized();
    _isLoading = true;
    try {
      final backend = _backend;
      if (backend != null) return await backend.handleRedirectCallback(url);
      final result = await _channel.invokeMap('handleRedirectCallback', {'url': url});
      return User.fromMap(result);
    } finally {
      _isLoading = false;
    }
  }

  /// Opens [buildSignInUrl] in a system browser session (`ASWebAuthenticationSession` on iOS, a
  /// Custom Tab on Android), waits for the redirect back to the app's registered scheme, and
  /// completes sign-in with [handleRedirectCallback].
  ///
  /// Throws [IAMException] with [ThunderIDErrorCode.federatedAuthCancelled] when the user closes
  /// the browser without signing in.
  Future<User> signInWithRedirect({SignInOptions? options}) async {
    _requireInitialized();
    final url = await buildSignInUrl(options: options);
    final callbackUrl = await _channel.invoke<String>('openAuthSession', {'url': url});
    if (callbackUrl == null || callbackUrl.isEmpty) {
      throw const IAMException(ThunderIDErrorCode.invalidRedirectUri, 'The browser session returned no callback');
    }
    return handleRedirectCallback(callbackUrl);
  }

  /// Signs out. When sign-in runs on a backend, the backend ends the session, the session handle
  /// and the stored access token are removed, and the returned URL is the one that ends the session
  /// at the authorization server, falling back to [ThunderIDConfig.afterSignOutUrl].
  Future<String> signOut({SignOutOptions? options, String? sessionId}) async {
    _requireInitialized();
    _isLoading = true;
    try {
      final backend = _backend;
      if (backend != null) {
        return await backend.signOut() ?? _afterSignOutUrl ?? '/';
      }
      final result = await _channel.invoke<String>('signOut', {
        if (options != null) 'options': options.toMap(),
        if (sessionId != null) 'sessionId': sessionId,
      });
      return result ?? '/';
    } finally {
      _isLoading = false;
    }
  }

  Future<bool> isSignedIn({String? sessionId}) async {
    _requireInitialized();
    final backend = _backend;
    if (backend != null) return (await backend.getSession()).isSignedIn;
    final result = await _channel.invoke<bool>('isSignedIn', {
      if (sessionId != null) 'sessionId': sessionId,
    });
    return result ?? false;
  }

  /// Synchronous — reflects whether the SDK is mid-initialization or mid-token-refresh (spec §7.1).
  ///
  /// When sign-in runs on a backend, it stays true until the first session read settles, so a
  /// route guard does not start a sign-in before it is known whether the user is signed in.
  bool isLoading() => _isLoading || (_backend?.isLoading() ?? false);

  /// Whether sign-in runs on the app's backend, which holds the tokens so the app never does.
  bool isBackendMode() => _backend != null;

  /// Calls [listener] when a signed-in session ends without the app signing out: the backend
  /// reports `login_required`, or a session check finds it gone. A sign-out the app starts itself
  /// does not call it.
  ///
  /// Returns a function that removes the listener.
  void Function() onSignOut(void Function() listener) {
    _signOutListeners.add(listener);
    return () => _signOutListeners.remove(listener);
  }

  // ── Registration ──────────────────────────────────────────────────────────

  Future<EmbeddedFlowResponse> signUp({
    EmbeddedSignInPayload? payload,
    EmbeddedFlowRequestConfig? request,
  }) async {
    _requireInitialized();
    _refuseOnBackend('signUp');
    final result = await _channel.invokeMap('signUp', {
      if (payload != null) 'payload': payload.toMap(),
      if (request != null) 'request': request.toMap(),
    });
    return EmbeddedFlowResponse.fromMap(result);
  }

  // ── Token & Session ───────────────────────────────────────────────────────

  /// Returns a valid access token.
  ///
  /// When sign-in runs on a backend, this is the token for requests under
  /// `endpoints.backend.bypass`, from the backend's token endpoint: it carries no refresh token and
  /// is requested again shortly before it expires.
  Future<String> getAccessToken({String? sessionId}) async {
    _requireInitialized();
    final backend = _backend;
    if (backend != null) return backend.getAccessToken();
    final result = await _channel.invoke<String>('getAccessToken', {
      if (sessionId != null) 'sessionId': sessionId,
    });
    return result ?? '';
  }

  Future<Map<String, dynamic>> decodeJwtToken(String token) async {
    _requireInitialized();
    final result = await _channel.invokeMap('decodeJwtToken', {'token': token});
    return result.cast<String, dynamic>();
  }

  Future<TokenResponse> exchangeToken(TokenExchangeRequestConfig config, {String? sessionId}) async {
    _requireInitialized();
    _refuseOnBackend('exchangeToken');
    final result = await _channel.invokeMap('exchangeToken', {
      'config': config.toMap(),
      if (sessionId != null) 'sessionId': sessionId,
    });
    return TokenResponse.fromMap(result);
  }

  void clearSession({String? sessionId}) {
    if (!_initialized) return;
    final backend = _backend;
    if (backend != null) {
      unawaited(backend.clearLocalSession());
      return;
    }
    _channel.invoke<void>('clearSession', {
      if (sessionId != null) 'sessionId': sessionId,
    });
  }

  // ── User & Profile ────────────────────────────────────────────────────────

  /// Returns the signed-in user. When sign-in runs on a backend, these are the ID token's user
  /// claims as the backend's session reports them.
  Future<User> getUser({Map<String, dynamic>? options}) async {
    _requireInitialized();
    final backend = _backend;
    if (backend != null) {
      return User((await backend.getSession()).user ?? const {});
    }
    final result = await _channel.invokeMap('getUser', options);
    return User.fromMap(result);
  }

  /// Overrides the user cached by the native SDK.
  ///
  /// [getUser] returns that cache when it is populated, so a merge of freshly
  /// fetched `/users/me` attributes has to be written back through here, or the
  /// next [getUser] would hand back the pre-merge claims.
  Future<void> setCachedUser(User user) async {
    _requireInitialized();
    _refuseOnBackend('setCachedUser');
    await _channel.invoke<void>('setCachedUser', {'user': user.toMap()});
  }

  /// The signed-in user's full profile, from `GET /users/me`.
  Future<UserProfile> getUserProfile({Map<String, dynamic>? options}) async {
    _requireInitialized();
    _refuseOnBackend('getUserProfile');
    final result = await _channel.invokeMap('getUserProfile', options);
    return UserProfile.fromMap(result);
  }

  /// Attribute schema describing which profile fields exist and how they validate,
  /// from `GET /users/me/meta`.
  Future<Map<String, AttributeSchema>> getUserSchema() async {
    _requireInitialized();
    _refuseOnBackend('getUserSchema');
    final result = await _channel.invokeMap('getUserSchema');
    return {
      for (final entry in result.entries)
        entry.key.toString(): AttributeSchema.fromMap(entry.value as Map),
    };
  }

  /// Saves [payload] as the signed-in user's attributes via `PUT /users/me`.
  ///
  /// The server replaces the whole attribute set, so [payload] must carry every
  /// attribute the profile should keep, not just the edited one.
  Future<UserProfile> updateUserProfile(Map<String, dynamic> payload) async {
    _requireInitialized();
    _refuseOnBackend('updateUserProfile');
    final result = await _channel.invokeMap('updateUserProfile', {
      'payload': payload,
    });
    return UserProfile.fromMap(result);
  }

  /// Changes one of the signed-in user's own credentials via
  /// `POST /users/me/update-credentials`.
  ///
  /// The self-service write path does not verify the account's existing value today, so this
  /// call collects only the new value, matching the Android/iOS/React/Vue SDKs.
  Future<void> updateUserCredentials({
    String attribute = 'password',
    required String newValue,
  }) async {
    _requireInitialized();
    _refuseOnBackend('updateUserCredentials');
    await _channel.invoke<void>('updateUserCredentials', {
      'attribute': attribute,
      'newValue': newValue,
    });
  }

  // ── Self user attribute verification ────────────────────────────────────

  /// Runs one step of self user attribute verification, a `SELF_SERVICE` flow the native SDK sends
  /// with the signed-in user's access token, from which the server takes the user.
  ///
  /// Without [payload], starts verifying [attribute], such as `email`, with the flow named by
  /// [handle]; the flow sends a code or a link to the attribute's stored value. With [payload],
  /// continues that execution: [EmbeddedSignInPayload.flowId] is the step's execution ID, and a
  /// resend submits its action with no inputs. `COMPLETE` means the server recorded the
  /// verification, so read [UserProfile.verifiedAttributes] again to see it.
  ///
  /// The request goes to `{baseUrl}/flow/execute`. The native SDK refuses, before any request and
  /// with [ThunderIDErrorCode.invalidInput], a start without a handle or attribute and a
  /// continuation without an execution ID. A refusal from the server, an `ERROR` step or an HTTP
  /// 4xx, is [ThunderIDErrorCode.verificationFailed], without the response body.
  Future<EmbeddedFlowResponse> verifyAttribute({
    String? attribute,
    String handle = AttributeVerification.defaultFlowHandle,
    EmbeddedSignInPayload? payload,
  }) async {
    _requireInitialized();
    _refuseOnBackend('verifyAttribute');
    final result = await _channel.invokeMap('verifyAttribute', {
      if (payload != null)
        'payload': payload.toMap()
      else ...{
        'attribute': attribute ?? '',
        'handle': handle,
      },
    });
    return EmbeddedFlowResponse.fromMap(result);
  }

  // ── Flow Meta ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getFlowMeta(
    String applicationId, {
    String language = 'en-US',
  }) async {
    _requireInitialized();
    _refuseOnBackend('getFlowMeta');
    final result = await _channel.invokeMap('getFlowMeta', {
      'applicationId': applicationId,
      'language': language,
    });
    return result.cast<String, dynamic>();
  }

  /// Stops the session checks that run while sign-in runs on a backend. Call it once the client is
  /// no longer used; [ThunderIDProvider] does so for the client it creates.
  void dispose() {
    _stopBackendWatch?.call();
    _stopBackendWatch = null;
  }

  // ── HTTP ──────────────────────────────────────────────────────────────────

  /// Sends a request to the app's API when sign-in runs on a backend.
  ///
  /// A URL under [ThunderIDConfig.baseUrl] (or a path starting with `/`) goes through the
  /// backend's proxy with the session handle; the backend attaches the access token. A URL under
  /// one of `endpoints.backend.bypass.urls` goes straight there, with the access token unless
  /// `attachToken` is off. Any other URL is refused with
  /// [ThunderIDErrorCode.backendUnsupportedUrl] and nothing is sent.
  ///
  /// Every status comes back as a response; a `401` that is not the backend's `session_expired`
  /// or `login_required` is the API's own answer and is returned untouched.
  Future<HttpResponseData> httpRequest(HttpRequestConfig request) async {
    _requireInitialized();
    final backendHttp = _backendHttp;
    if (backendHttp == null) {
      throw const IAMException(
        ThunderIDErrorCode.operationNotSupported,
        'httpRequest is only available when sign-in runs on a backend (endpoints.backend)',
      );
    }
    return backendHttp.request(request);
  }

  // ── Management ────────────────────────────────────────────────────────────

  /// Management operations for users, user types, groups, roles, agents, agent types, and
  /// applications, authorized with the signed-in user's access token (spec "Management
  /// operations").
  ///
  /// Uses [ThunderIDConfig.endpoints] for collection URL overrides and
  /// [ThunderIDConfig.http]'s fetcher, when set, as the transport.
  ThunderIDManagementClient get management {
    _requireInitialized();
    final config = _config!;
    return _management ??= ThunderIDManagementClient(
      baseUrl: config.baseUrl,
      endpoints: config.endpoints?.collections ?? const {},
      fetcher: config.http?.fetcher,
      accessTokenProvider: getAccessToken,
      allowInsecureConnections: config.allowInsecureConnections,
    );
  }

  /// The permissions the signed-in user's access token carries, read from its `scope`/`scopes`
  /// claim. Decoded, not verified: use it only to decide what to show, and test a requirement
  /// against it with [hasPermission].
  Future<List<String>> getGrantedPermissions({String? sessionId}) async =>
      getTokenPermissions(await getAccessToken(sessionId: sessionId));

  // ── Private helpers ───────────────────────────────────────────────────────

  void _initializeBackend(ResolvedBackendEndpoints endpoints, ThunderIDConfig config) {
    // The native SDK is not initialized: the backend runs the OAuth flow, so nothing here talks to
    // the ThunderID server or reads its discovery metadata.
    final backend = BackendClient(
      endpoints,
      channel: _channel,
      vendor: config.vendor,
      transport: _httpTransport,
      now: _now,
      onSignedOut: _notifySignedOut,
    );
    _backend = backend;
    _backendHttp = BackendHttpClient(backend, _httpTransport);
    _afterSignOutUrl = config.afterSignOutUrl;
    // Checks on returning to the foreground run either way; polling only when asked for.
    _stopBackendWatch = backend.watch(config.session.checkInterval);
    _initialized = true;
    // Read the session now, so the client reports loading until it is known whether the user is
    // signed in. A failed read is retried by the next call that needs the session.
    unawaited(backend.getSession().then<void>((_) {}, onError: (Object _) {}));
  }

  void _notifySignedOut() {
    for (final listener in List.of(_signOutListeners)) {
      listener();
    }
  }

  /// The operations that drive an embedded flow, hand out a token, or depend on the native SDK's
  /// session are refused while sign-in runs on a backend: the backend holds the session and the
  /// tokens.
  void _refuseOnBackend(String operation) {
    if (_backend == null) return;
    throw IAMException(
      ThunderIDErrorCode.operationNotSupported,
      '$operation is not available when sign-in runs on a backend',
    );
  }

  void _requireInitialized() {
    if (!_initialized) {
      throw const IAMException(
        ThunderIDErrorCode.sdkNotInitialized,
        'Call initialize() before using the SDK',
      );
    }
  }
}
