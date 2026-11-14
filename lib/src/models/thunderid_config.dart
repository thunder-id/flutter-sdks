// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../management/management_transport.dart';
import 'backend.dart';
import 'preferences.dart';

/// Configuration for the ThunderID Flutter SDK (spec §5.2).
class ThunderIDConfig {
  /// Default vendor/brand namespace used when [vendor] is not overridden.
  static const String defaultVendor = 'thunderid';

  // Core
  /// Base URL of the ThunderID server.
  ///
  /// When sign-in runs on a backend ([EndpointsConfig.backend]), the SDK never talks to the
  /// ThunderID server, and this is instead the backend's base URL, which must use HTTPS. Backend
  /// endpoints given as paths resolve against it, and the app's API is reached through the
  /// backend's proxy ([BackendEndpoints.proxy]).
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

  /// HTTP options. [ThunderIDHttpConfig.fetcher] replaces the transport for management
  /// operations only. Not forwarded to the native SDKs.
  final ThunderIDHttpConfig? http;

  // Token Validation
  final TokenValidationConfig tokenValidation;

  // Endpoints
  /// Endpoint overrides: the management collection URLs, and [EndpointsConfig.backend], which
  /// hands sign-in to a backend the app owns. Kept out of [toMap], so none of it reaches the native
  /// SDK or the OIDC provider metadata.
  final EndpointsConfig? endpoints;

  // Session
  /// Behaviour around the session. Kept out of [toMap]: it only applies to sign-in on a backend.
  final SessionConfig session;

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
    this.http,
    this.tokenValidation = const TokenValidationConfig(),
    this.endpoints,
    this.session = const SessionConfig(),
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

/// Per-endpoint overrides (spec "Configuration").
class EndpointsConfig {
  /// Management collection URL overrides. Unset, a collection resolves to
  /// `{baseUrl}/{collection}`. A value is the collection URL; a single resource is addressed as
  /// that URL followed by its identifier. Each URL must be HTTPS (plain HTTP is accepted for a
  /// loopback address only). Consumed by the Dart management layer only.
  final String? users;
  final String? userTypes;
  final String? groups;
  final String? roles;
  final String? agents;
  final String? agentTypes;
  final String? applications;
  final String? organizationUnits;
  final String? resourceServers;
  final String? connections;
  final String? flows;
  final String? notificationTemplates;
  final String? design;
  final String? i18n;
  final String? serverConfig;
  final String? gateways;
  final String? variables;
  final String? secrets;
  final String? configurationVersions;
  final String? import;
  final String? export;

  /// The app backend's auth endpoints. Setting them hands sign-in to the backend: the SDK then
  /// signs in, reads the session, and sends API calls through the backend, and the embedded
  /// flows are refused. Never inferred, and fixed for the life of the client.
  final BackendEndpoints? backend;

  const EndpointsConfig({
    this.users,
    this.userTypes,
    this.groups,
    this.roles,
    this.agents,
    this.agentTypes,
    this.applications,
    this.organizationUnits,
    this.resourceServers,
    this.connections,
    this.flows,
    this.notificationTemplates,
    this.design,
    this.i18n,
    this.serverConfig,
    this.gateways,
    this.variables,
    this.secrets,
    this.configurationVersions,
    this.import,
    this.export,
    this.backend,
  });

  /// The management collection overrides that are set, keyed by `ManagementEndpointKeys`.
  Map<String, String> get collections => {
        if (users case final url?) 'users': url,
        if (userTypes case final url?) 'userTypes': url,
        if (groups case final url?) 'groups': url,
        if (roles case final url?) 'roles': url,
        if (agents case final url?) 'agents': url,
        if (agentTypes case final url?) 'agentTypes': url,
        if (applications case final url?) 'applications': url,
        if (organizationUnits case final url?) 'organizationUnits': url,
        if (resourceServers case final url?) 'resourceServers': url,
        if (connections case final url?) 'connections': url,
        if (flows case final url?) 'flows': url,
        if (notificationTemplates case final url?) 'notificationTemplates': url,
        if (design case final url?) 'design': url,
        if (i18n case final url?) 'i18n': url,
        if (serverConfig case final url?) 'serverConfig': url,
        if (gateways case final url?) 'gateways': url,
        if (variables case final url?) 'variables': url,
        if (secrets case final url?) 'secrets': url,
        if (configurationVersions case final url?) 'configurationVersions': url,
        if (import case final url?) 'import': url,
        if (export case final url?) 'export': url,
      };
}

/// Behaviour around the session.
class SessionConfig {
  /// How often to ask the app's backend whether the session is still live, in seconds. Only
  /// applies when sign-in runs on a backend: the backend's check endpoint reports liveness without
  /// refreshing the session or counting as activity, so polling it does not keep an idle session
  /// alive. `0` leaves only the check that runs when the app comes back to the foreground.
  final int checkInterval;

  const SessionConfig({this.checkInterval = 0});
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
