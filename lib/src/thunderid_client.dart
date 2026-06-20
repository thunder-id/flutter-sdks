/*
 * Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

import 'channel/thunderid_channel.dart';
import 'models/thunderid_error.dart';
import 'models/thunderid_config.dart';
import 'models/user.dart';
import 'models/user_profile.dart';
import 'models/token_response.dart';
import 'models/flow_models.dart';
import 'models/sign_in_options.dart';
import 'models/sign_out_options.dart';
import 'models/token_exchange_config.dart';

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

  Future<UserProfile> getUserProfile({Map<String, dynamic>? options}) async {
    _requireInitialized();
    final result = await _channel.invokeMap('getUserProfile', options);
    return UserProfile.fromMap(result);
  }

  Future<User> updateUserProfile(Map<String, dynamic> payload, {String? userId}) async {
    _requireInitialized();
    final result = await _channel.invokeMap('updateUserProfile', {
      'payload': payload,
      if (userId != null) 'userId': userId,
    });
    return User.fromMap(result);
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
