// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'preferences.dart';

/// Configuration for the ThunderID Flutter SDK (spec §5.2).
class ThunderIDConfig {
  /// Default vendor/brand namespace used when [vendor] is not overridden.
  static const String defaultVendor = 'thunderid';

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

  // User Profile
  /// Whether profile attributes come from `GET /users/me`, or only from the claims
  /// already carried by the sign-in token.
  ///
  /// When false, [UserProfile] renders read-only: there is no attribute schema to
  /// validate against and no endpoint to save to.
  final bool fetchUserProfile;

  // Transport
  /// Disables TLS certificate and hostname verification on Android.
  ///
  /// Intended only for local development against a self-signed ThunderID instance;
  /// gate it on a debug flag and never ship it enabled. Ignored on iOS, where the
  /// native SDK already trusts a locally-served certificate on its own.
  final bool allowInsecureConnections;

  // Platform Attestation
  /// When true, the native SDK sends a platform attestation token (Apple App Attest /
  /// Google Play Integrity) on native flow-initiate requests.
  final bool attestationEnabled;

  /// Google Cloud project number, required by Play Integrity on Android.
  final int? cloudProjectNumber;

  // Token Validation
  final TokenValidationConfig tokenValidation;

  // UI Preferences (theme + i18n) — ignored by the protocol layer
  final ThunderIDPreferences? preferences;

  /// Vendor/brand namespace used by the native SDK layer to derive default storage identifiers.
  /// Override this when white-labeling the SDK under a different brand. Defaults to
  /// [defaultVendor].
  final String vendor;

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
    this.fetchUserProfile = true,
    this.allowInsecureConnections = false,
    this.attestationEnabled = false,
    this.cloudProjectNumber,
    this.tokenValidation = const TokenValidationConfig(),
    this.preferences,
    this.vendor = defaultVendor,
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
        'fetchUserProfile': fetchUserProfile,
        'allowInsecureConnections': allowInsecureConnections,
        'attestationEnabled': attestationEnabled,
        if (cloudProjectNumber != null) 'cloudProjectNumber': cloudProjectNumber,
        'tokenValidation': tokenValidation.toMap(),
        if (preferences != null) 'preferences': preferences!.toMap(),
        'vendor': vendor,
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
