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

import 'preferences.dart';

/// Configuration for the ThunderID Flutter SDK (spec §5.2).
class ThunderIDConfig {
  // Core
  final String baseUrl;
  final String? clientId;

  // Redirect URIs
  final String? afterSignInUrl;
  final String? afterSignOutUrl;
  final String? signInUrl;
  final String? signUpUrl;

  // OAuth2 / OIDC
  final List<String> scopes;
  final Map<String, dynamic> signInOptions;
  final Map<String, dynamic> signOutOptions;
  final Map<String, dynamic> signUpOptions;

  // Application Identity
  final String? applicationId;
  final String? organizationHandle;

  // Token Validation
  final TokenValidationConfig tokenValidation;

  // UI Preferences (theme + i18n) — ignored by the protocol layer
  final ThunderIDPreferences? preferences;

  const ThunderIDConfig({
    required this.baseUrl,
    this.clientId,
    this.afterSignInUrl,
    this.afterSignOutUrl,
    this.signInUrl,
    this.signUpUrl,
    this.scopes = const ['openid'],
    this.signInOptions = const {},
    this.signOutOptions = const {},
    this.signUpOptions = const {},
    this.applicationId,
    this.organizationHandle,
    this.tokenValidation = const TokenValidationConfig(),
    this.preferences,
  });

  Map<String, dynamic> toMap() => {
        'baseUrl': baseUrl,
        if (clientId != null) 'clientId': clientId,
        if (afterSignInUrl != null) 'afterSignInUrl': afterSignInUrl,
        if (afterSignOutUrl != null) 'afterSignOutUrl': afterSignOutUrl,
        if (signInUrl != null) 'signInUrl': signInUrl,
        if (signUpUrl != null) 'signUpUrl': signUpUrl,
        'scopes': scopes,
        'signInOptions': signInOptions,
        'signOutOptions': signOutOptions,
        'signUpOptions': signUpOptions,
        if (applicationId != null) 'applicationId': applicationId,
        if (organizationHandle != null) 'organizationHandle': organizationHandle,
        'tokenValidation': tokenValidation.toMap(),
        if (preferences != null) 'preferences': preferences!.toMap(),
      };
}

class TokenValidationConfig {
  final bool validate;
  final bool validateIssuer;
  final int clockTolerance;

  const TokenValidationConfig({
    this.validate = true,
    this.validateIssuer = true,
    this.clockTolerance = 0,
  });

  Map<String, dynamic> toMap() => {
        'validate': validate,
        'validateIssuer': validateIssuer,
        'clockTolerance': clockTolerance,
      };
}
