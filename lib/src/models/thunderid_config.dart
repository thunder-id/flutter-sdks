// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../management/management_transport.dart';
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

  // Platform Attestation
  /// When true, the native SDK sends a platform attestation token (Apple App Attest /
  /// Google Play Integrity) on native flow-initiate requests.
  final bool attestationEnabled;

  /// Google Cloud project number, required by Play Integrity on Android.
  final int? cloudProjectNumber;

  // Transport
  /// When true, the native SDK accepts TLS certificates it cannot verify.
  ///
  /// This exists so a development build can talk to a ThunderID server using the self-signed
  /// certificate it generates for `localhost`. On iOS the same thing is achieved at the app
  /// level with an `NSAppTransportSecurity` exemption, so this flag only takes effect on
  /// Android, where it is forwarded to the native SDK's own `allowInsecureConnections`.
  ///
  /// Never enable it in a release build: it disables certificate validation entirely, which
  /// removes the guarantee that the server on the other end is the one you think it is. Gate it
  /// on a debug check, as the Quickstart sample does.
  final bool allowInsecureConnections;

  /// Per-endpoint URL overrides for the management collections. Unset, a collection resolves to
  /// `{baseUrl}/{collection}`. The keys are the management collections in `ManagementEndpointKeys`: `users`,
  /// `userTypes`, `groups`, `roles`, `agents`, and `agentTypes`. A value is the collection URL; a
  /// single resource is addressed as that URL followed by its identifier. Each URL must be HTTPS
  /// (plain HTTP is accepted for a loopback address only).
  ///
  /// Consumed by the Dart management layer only; not forwarded to the native SDKs.
  final Map<String, String> endpoints;

  /// HTTP options. [ThunderIDHttpConfig.fetcher] replaces the transport for management
  /// operations only. Not forwarded to the native SDKs.
  final ThunderIDHttpConfig? http;

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
    this.endpoints = const {},
    this.http,
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

/// HTTP options (spec "Configuration": `http`).
class ThunderIDHttpConfig {
  /// Replaces the SDK's authenticated transport for management operations. Authentication,
  /// token, and flow requests keep using the native SDK's transport. A fetcher passed to a single
  /// management call takes precedence over this one.
  final ManagementFetcher? fetcher;

  const ThunderIDHttpConfig({this.fetcher});
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
