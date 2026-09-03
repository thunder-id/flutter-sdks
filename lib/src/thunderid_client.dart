// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'channel/thunderid_channel.dart';
import 'models/flow_models.dart';
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
class ThunderIDClient {
  final ThunderIDChannel _channel;
  bool _initialized = false;
  bool _isLoading = false;

  ThunderIDClient({ThunderIDChannel? channel}) : _channel = channel ?? ThunderIDChannel();

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Initializes the SDK. Must be called once before any other method (spec §5.1).
  Future<bool> initialize(ThunderIDConfig config) async {
    if (_initialized) {
      throw const IAMException(ThunderIDErrorCode.alreadyInitialized, 'SDK is already initialized');
    }
    final result = await _channel.invoke<bool>('initialize', config.toMap());
    _initialized = result ?? false;
    return _initialized;
  }

  Future<bool> reInitialize({String? baseUrl, String? clientId}) async {
    _requireInitialized();
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
    final result = await _channel.invokeMap('performPasskeyRegistration', {
      'creationOptionsJson': creationOptionsJson,
    });
    return result.cast<String, String>();
  }

  /// Builds the redirect-based sign-in URL. Open this in an in-app browser or
  /// custom tab, then call [handleRedirectCallback] with the callback URL.
  Future<String> buildSignInUrl({SignInOptions? options}) async {
    _requireInitialized();
    final result = await _channel.invoke<String>('buildSignInUrl', {
      if (options != null) 'options': options.toMap(),
    });
    return result ?? '';
  }

  /// Handles the callback URL after a redirect-based sign-in (spec §6.1).
  Future<User> handleRedirectCallback(String url) async {
    _requireInitialized();
    _isLoading = true;
    try {
      final result = await _channel.invokeMap('handleRedirectCallback', {'url': url});
      return User.fromMap(result);
    } finally {
      _isLoading = false;
    }
  }

  Future<String> signOut({SignOutOptions? options, String? sessionId}) async {
    _requireInitialized();
    _isLoading = true;
    try {
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
    final result = await _channel.invoke<bool>('isSignedIn', {
      if (sessionId != null) 'sessionId': sessionId,
    });
    return result ?? false;
  }

  /// Synchronous — reflects whether the SDK is mid-initialization or mid-token-refresh (spec §7.1).
  bool isLoading() => _isLoading;

  // ── Registration ──────────────────────────────────────────────────────────

  Future<EmbeddedFlowResponse> signUp({
    EmbeddedSignInPayload? payload,
    EmbeddedFlowRequestConfig? request,
  }) async {
    _requireInitialized();
    final result = await _channel.invokeMap('signUp', {
      if (payload != null) 'payload': payload.toMap(),
      if (request != null) 'request': request.toMap(),
    });
    return EmbeddedFlowResponse.fromMap(result);
  }

  // ── Token & Session ───────────────────────────────────────────────────────

  Future<String> getAccessToken({String? sessionId}) async {
    _requireInitialized();
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
    final result = await _channel.invokeMap('exchangeToken', {
      'config': config.toMap(),
      if (sessionId != null) 'sessionId': sessionId,
    });
    return TokenResponse.fromMap(result);
  }

  void clearSession({String? sessionId}) {
    if (!_initialized) return;
    _channel.invoke<void>('clearSession', {
      if (sessionId != null) 'sessionId': sessionId,
    });
  }

  // ── User & Profile ────────────────────────────────────────────────────────

  Future<User> getUser({Map<String, dynamic>? options}) async {
    _requireInitialized();
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
    await _channel.invoke<void>('setCachedUser', {'user': user.toMap()});
  }

  /// The signed-in user's full profile, from `GET /users/me`.
  Future<UserProfile> getUserProfile({Map<String, dynamic>? options}) async {
    _requireInitialized();
    final result = await _channel.invokeMap('getUserProfile', options);
    return UserProfile.fromMap(result);
  }

  /// Attribute schema describing which profile fields exist and how they validate,
  /// from `GET /users/me/meta`.
  Future<Map<String, AttributeSchema>> getUserSchema() async {
    _requireInitialized();
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
    final result = await _channel.invokeMap('updateUserProfile', {
      'payload': payload,
    });
    return UserProfile.fromMap(result);
  }

  // ── Flow Meta ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getFlowMeta(
    String applicationId, {
    String language = 'en-US',
  }) async {
    _requireInitialized();
    final result = await _channel.invokeMap('getFlowMeta', {
      'applicationId': applicationId,
      'language': language,
    });
    return result.cast<String, dynamic>();
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  void _requireInitialized() {
    if (!_initialized) {
      throw const IAMException(
        ThunderIDErrorCode.sdkNotInitialized,
        'Call initialize() before using the SDK',
      );
    }
  }
}
