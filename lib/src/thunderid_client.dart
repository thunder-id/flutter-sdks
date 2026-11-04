// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/services.dart';

import 'api/account/organization_units.dart' as account;
import 'api/auth/device_grant_flow.dart';
import 'api/management/management_transport.dart';
import 'api/management/permissions.dart';
import 'api/management/thunderid_management_client.dart';
import 'backend/backend_client.dart';
import 'backend/backend_http_client.dart';
import 'backend/http_transport.dart';
import 'backend/resolve_backend_endpoints.dart';
import 'channel/thunderid_channel.dart';
import 'models/account/organization_unit.dart';
import 'models/ciba.dart';
import 'models/device_authorization.dart';
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
  final HttpTransport? _injectedTransport;
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
        _injectedTransport = httpTransport,
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
    final requestMap = request.toMap();
    final ouId = request.organizationUnitId;
    if (ouId != null) {
      // The unit bounds the flow from its first request; a continuation never carries it.
      if (payload.flowId != null) {
        requestMap.remove('ouId');
      } else {
        _requireOrganizationUnitId('signIn', ouId);
        if (request.flowType != FlowType.authentication) {
          throw const IAMException(
            ThunderIDErrorCode.invalidInput,
            'signIn: organizationUnitId bounds an AUTHENTICATION flow only.',
          );
        }
      }
    }
    _isLoading = true;
    try {
      final result = await _channel.invokeMap('signIn', {
        'payload': payload.toMap(),
        'request': requestMap,
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
  /// pair; of [options], only [SignInOptions.organizationUnitId] applies to it, as the `ouId`
  /// query parameter. [signInWithRedirect] opens it and completes sign-in.
  ///
  /// [SignInOptions.organizationUnitId] bounds the sign-in to that organization unit.
  Future<String> buildSignInUrl({SignInOptions? options}) async {
    _requireInitialized();
    final ouId = options?.organizationUnitId;
    if (ouId != null) _requireOrganizationUnitId('signIn', ouId);
    final backend = _backend;
    if (backend != null) return backend.buildSignInUrl(organizationUnitId: ouId);
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
      if (backend != null) return await backend.signOut() ?? _afterSignOutUrl ?? '/';
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

  // ── Organization units ────────────────────────────────────────────────────

  /// Signs in again bounded to the organization unit [organizationUnitId], and returns the user of
  /// the new session.
  ///
  /// The server reuses the single sign-on session when the user can sign in to that unit, so
  /// normally no credentials are asked for. On success the tokens are replaced (the refresh token
  /// is bound to the unit) and the user is read again; call [ThunderIDState.refresh] or let
  /// [OrganizationUnitSwitcher] do it to update the widgets.
  ///
  /// On failure the previous session stays as it was. A unit that does not exist and one the
  /// application cannot be used from both raise [ThunderIDErrorCode.organizationUnitUnavailable],
  /// since the server answers both with `unauthorized_client`; a closed browser raises
  /// [ThunderIDErrorCode.federatedAuthCancelled]. [options] carries any other sign-in parameter.
  Future<User> switchOrganizationUnit(String organizationUnitId, {SignInOptions? options}) async {
    _requireInitialized();
    final ouId = _requireOrganizationUnitId('switchOrganizationUnit', organizationUnitId);
    final url = await buildSignInUrl(
      options: (options ?? const SignInOptions()).copyWith(organizationUnitId: ouId),
    );
    final callbackUrl = await _channel.invoke<String>('openAuthSession', {'url': url});
    if (callbackUrl == null || callbackUrl.isEmpty) {
      throw const IAMException(ThunderIDErrorCode.invalidRedirectUri, 'The browser session returned no callback');
    }
    // A refused sign-in comes back as an error redirect. It is answered here, before anything
    // reaches the session, so the previous session is left untouched.
    final error = Uri.tryParse(callbackUrl)?.queryParameters['error'];
    if (error == 'unauthorized_client') {
      throw const IAMException(
        ThunderIDErrorCode.organizationUnitUnavailable,
        'The organization unit cannot be signed in to from this application',
      );
    }
    if (error != null) {
      throw IAMException(
        ThunderIDErrorCode.authenticationFailed,
        'The sign-in to the organization unit was refused: $error',
      );
    }
    return handleRedirectCallback(callbackUrl);
  }

  /// The organization units the signed-in user can access, from `GET /users/me/ous`, with the
  /// unit the list is relative to in [AccessibleOrganizationUnitList.current].
  ///
  /// [scope] narrows the list ([AccessibleOrganizationUnitScope.siblings]: the current unit and the
  /// accessible units that share its parent); [limit] and [offset] page it. Uses the same transport
  /// as [management], so [ThunderIDConfig.http]'s fetcher applies.
  Future<AccessibleOrganizationUnitList> getAccessibleOrganizationUnits({
    AccessibleOrganizationUnitScope? scope,
    int? limit,
    int? offset,
  }) async {
    _requireInitialized();
    _refuseOnBackend('getAccessibleOrganizationUnits');
    final client = management;
    return account.getAccessibleOrganizationUnits(
      baseUrl: client.baseUrl,
      fetcher: client.fetcher,
      scope: scope,
      limit: limit,
      offset: offset,
    );
  }

  /// The organization unit the signed-in session was issued for, from its `ouId`, `ouHandle` and
  /// `ouName` claims, or `null` when no one is signed in or the claims are absent.
  ///
  /// For display only: never base an authorization decision on it.
  Future<CurrentOrganizationUnit?> getCurrentOrganizationUnit() async {
    _requireInitialized();
    if (!await isSignedIn()) return null;
    return CurrentOrganizationUnit.fromClaims((await getUser()).claims);
  }

  // ── Backchannel and device authorization ──────────────────────────────────

  /// Starts a Client-Initiated Backchannel Authentication request (CIBA, poll mode) at the
  /// `backchannel_authentication_endpoint` the server's discovery metadata names, and returns the
  /// `authReqId` with its lifetime and polling interval. Poll it with [pollCIBA].
  ///
  /// The SDK holds no client secret, so this works only for an application registered as a public
  /// client (`token_endpoint_auth_method: none`); a confidential registration is unsupported and
  /// the server refuses it. A server whose metadata has no backchannel endpoint raises
  /// [ThunderIDErrorCode.operationNotSupported], as does a native SDK without CIBA.
  Future<CIBAInitiateResponse> initiateCIBA(CIBAInitiateOptions options) async {
    _requireInitialized();
    _refuseOnBackend('initiateCIBA');
    options.validate();
    return CIBAInitiateResponse.fromMap(await _invokeNativeOperation('initiateCIBA', {'options': options.toMap()}));
  }

  /// Polls the token endpoint with the `urn:openid:params:grant-type:ciba` grant for [authReqId],
  /// no more often than every [interval] seconds and slowing down on `slow_down`, until the user
  /// approves, denies or the request expires after [expiresIn] seconds. On approval the tokens are
  /// stored as a sign-in stores them, and returned.
  ///
  /// A denial or an expiry raises [IAMException] with the server's `error` in its message.
  Future<TokenResponse> pollCIBA(String authReqId, int interval, {int? expiresIn}) async {
    _requireInitialized();
    _refuseOnBackend('pollCIBA');
    if (authReqId.trim().isEmpty) {
      throw const IAMException(ThunderIDErrorCode.invalidInput, 'pollCIBA: an authReqId is required.');
    }
    return TokenResponse.fromMap(
      await _invokeNativeOperation('pollCIBA', {
        'authReqId': authReqId,
        'interval': interval < 1 ? 1 : interval,
        if (expiresIn != null) 'expiresIn': expiresIn,
      }),
    );
  }

  /// Starts a device authorization request (RFC 8628) at `/oauth2/device-authorize`, for an
  /// input-constrained device such as a TV. Show the returned user code and verification URI, and
  /// poll with [pollDeviceAuthorization]. [scopes] defaults to [ThunderIDConfig.scopes].
  ///
  /// The device code it returns is a credential: never show or log it.
  Future<DeviceAuthorization> startDeviceAuthorization({List<String>? scopes}) async {
    _requireInitialized();
    _refuseOnBackend('startDeviceAuthorization');
    return DeviceAuthorization.fromMap(
      await _invokeNativeOperation('startDeviceAuthorization', {if (scopes != null) 'scopes': scopes}),
    );
  }

  /// Polls the token endpoint with the `urn:ietf:params:oauth:grant-type:device_code` grant for
  /// [authorization], under the same rules as [pollCIBA], and stores the tokens on success.
  Future<TokenResponse> pollDeviceAuthorization(DeviceAuthorization authorization) async {
    _requireInitialized();
    _refuseOnBackend('pollDeviceAuthorization');
    return TokenResponse.fromMap(
      await _invokeNativeOperation('pollDeviceAuthorization', {
        'deviceCode': authorization.deviceCode,
        'interval': authorization.interval < 1 ? 1 : authorization.interval,
        'expiresIn': authorization.expiresIn,
      }),
    );
  }

  /// Runs one step of the server's `DEVICE_GRANT` flow, so the user approves a device by the code
  /// it shows. Driven like any embedded flow.
  ///
  /// The first call starts the flow for [applicationId] (defaulting to
  /// [ThunderIDConfig.applicationId]) with [userCode] when the user has typed it. Later calls pass
  /// the previous response's `flowId` as [flowId], with the step's [actionId], [inputs] and
  /// [challengeToken]. When the flow ends, the device is told the outcome; a refused flow comes
  /// back as a [FlowStatus.error] response.
  Future<EmbeddedFlowResponse> verifyDeviceCode({
    String? userCode,
    String? applicationId,
    String? flowId,
    String? actionId,
    Map<String, String> inputs = const {},
    String? challengeToken,
  }) async {
    _requireInitialized();
    _refuseOnBackend('verifyDeviceCode');
    final config = _config!;
    return executeDeviceGrantFlow(
      baseUrl: config.baseUrl,
      fetcher: _flowFetcher(config),
      applicationId: applicationId ?? config.applicationId,
      userCode: userCode,
      executionId: flowId,
      actionId: actionId,
      inputs: inputs,
      challengeToken: challengeToken,
    );
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
    if (backend != null) return User((await backend.getSession()).user ?? const {});
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

  /// The organization unit id, or [ThunderIDErrorCode.invalidInput] when it is blank.
  String _requireOrganizationUnitId(String operation, String organizationUnitId) {
    if (organizationUnitId.trim().isEmpty) {
      throw IAMException(ThunderIDErrorCode.invalidInput, '$operation: an organization unit id is required.');
    }
    return organizationUnitId;
  }

  /// Calls an operation the native SDK carries out. A native SDK that does not implement it raises
  /// [ThunderIDErrorCode.operationNotSupported] rather than the channel's missing plugin error.
  Future<Map<dynamic, dynamic>> _invokeNativeOperation(String method, Map<String, dynamic> args) async {
    try {
      return await _channel.invokeMap(method, args);
    } on MissingPluginException {
      throw IAMException(
        ThunderIDErrorCode.operationNotSupported,
        '$method is not supported by the native ThunderID SDK on this platform',
      );
    }
  }

  /// The transport for the flow requests the Dart layer sends itself. They carry no access token.
  ManagementFetcher _flowFetcher(ThunderIDConfig config) {
    final transport = _injectedTransport;
    if (transport == null) {
      return createAuthenticatedFetcher(
        () async => '',
        allowInsecureConnections: config.allowInsecureConnections,
      );
    }
    return (request) async {
      final response = await transport(request.method, request.url, request.headers, request.body);
      return ManagementResponse(statusCode: response.statusCode, body: response.body);
    };
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
