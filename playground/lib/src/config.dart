// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

/// Locales shipped with the playground, used by the translations check and the
/// LanguageSwitcher story.
const Map<String, Map<String, String>> playgroundBundles = {
  'en-US': {
    'signIn.button': 'Sign In',
    'signOut.button': 'Sign Out',
    'signUp.button': 'Sign Up',
  },
  'fr-FR': {
    'signIn.button': 'Se connecter',
    'signOut.button': 'Se déconnecter',
    'signUp.button': "S'inscrire",
    'signIn.title': 'Connexion',
    'userProfile.title': 'Informations personnelles',
  },
  'es-ES': {
    'signIn.button': 'Iniciar sesión',
    'signOut.button': 'Cerrar sesión',
    'signUp.button': 'Registrarse',
    'signIn.title': 'Iniciar sesión',
    'userProfile.title': 'Información personal',
  },
};

/// `.env` variables that override one management collection URL, keyed by the SDK's
/// [ManagementEndpointKeys]. Each value becomes an entry of [ThunderIDConfig.endpoints].
const Map<String, String> endpointEnvKeys = {
  ManagementEndpointKeys.users: 'THUNDERID_ENDPOINT_USERS',
  ManagementEndpointKeys.userTypes: 'THUNDERID_ENDPOINT_USER_TYPES',
  ManagementEndpointKeys.groups: 'THUNDERID_ENDPOINT_GROUPS',
  ManagementEndpointKeys.roles: 'THUNDERID_ENDPOINT_ROLES',
  ManagementEndpointKeys.agents: 'THUNDERID_ENDPOINT_AGENTS',
  ManagementEndpointKeys.agentTypes: 'THUNDERID_ENDPOINT_AGENT_TYPES',
  ManagementEndpointKeys.applications: 'THUNDERID_ENDPOINT_APPLICATIONS',
  ManagementEndpointKeys.organizationUnits: 'THUNDERID_ENDPOINT_ORGANIZATION_UNITS',
  ManagementEndpointKeys.resourceServers: 'THUNDERID_ENDPOINT_RESOURCE_SERVERS',
  ManagementEndpointKeys.connections: 'THUNDERID_ENDPOINT_CONNECTIONS',
  ManagementEndpointKeys.flows: 'THUNDERID_ENDPOINT_FLOWS',
  ManagementEndpointKeys.notificationTemplates: 'THUNDERID_ENDPOINT_NOTIFICATION_TEMPLATES',
  ManagementEndpointKeys.design: 'THUNDERID_ENDPOINT_DESIGN',
  ManagementEndpointKeys.i18n: 'THUNDERID_ENDPOINT_I18N',
  ManagementEndpointKeys.serverConfig: 'THUNDERID_ENDPOINT_SERVER_CONFIG',
  ManagementEndpointKeys.gateways: 'THUNDERID_ENDPOINT_GATEWAYS',
  ManagementEndpointKeys.variables: 'THUNDERID_ENDPOINT_VARIABLES',
  ManagementEndpointKeys.secrets: 'THUNDERID_ENDPOINT_SECRETS',
  ManagementEndpointKeys.configurationVersions: 'THUNDERID_ENDPOINT_CONFIGURATION_VERSIONS',
  ManagementEndpointKeys.import: 'THUNDERID_ENDPOINT_IMPORT',
  ManagementEndpointKeys.export: 'THUNDERID_ENDPOINT_EXPORT',
};

const _defaultScopes = ['openid', 'profile', 'email'];

/// Playground settings read from `.env`.
class PlaygroundConfig {
  final String baseUrl;
  final String? applicationId;
  final String? clientId;
  final String? afterSignInUrl;
  final String? afterSignOutUrl;
  final bool attestationEnabled;
  final int? cloudProjectNumber;

  /// Scopes requested at sign-in. Management calls need the server's admin permissions in the
  /// token, so add them here (`THUNDERID_SCOPES`) to exercise the admin checks and components.
  final List<String> scopes;

  /// Management collection URL overrides, passed as [ThunderIDConfig.endpoints]. Empty means
  /// every collection resolves under [baseUrl].
  final Map<String, String> endpoints;

  /// Organization unit the admin create components use (`THUNDERID_OU_ID`). When unset they
  /// fall back to the signed-in user's `ouId` claim.
  final String? ouId;

  /// Base URL of an app backend that runs sign-in (`endpoints.backend`). When set, it becomes the
  /// SDK's `baseUrl`, and the backend's proxy fronts the ThunderID server at [baseUrl].
  final String? backendUrl;

  const PlaygroundConfig({
    required this.baseUrl,
    this.applicationId,
    this.clientId,
    this.afterSignInUrl,
    this.afterSignOutUrl,
    this.attestationEnabled = false,
    this.cloudProjectNumber,
    this.scopes = _defaultScopes,
    this.endpoints = const {},
    this.ouId,
    this.backendUrl,
  });

  factory PlaygroundConfig.fromEnv(Map<String, String> env) {
    String? read(String key) {
      final value = env[key]?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    final endpoints = <String, String>{
      for (final key in endpointEnvKeys.keys)
        if (read(endpointEnvKeys[key]!) case final url?) key: url,
    };
    final scopes = read('THUNDERID_SCOPES')?.split(RegExp(r'[\s,]+')).where((s) => s.isNotEmpty).toList();

    return PlaygroundConfig(
      baseUrl: read('THUNDERID_BASE_URL') ?? 'https://localhost:8090',
      applicationId: read('THUNDERID_APP_ID'),
      clientId: read('THUNDERID_CLIENT_ID'),
      afterSignInUrl: read('THUNDERID_AFTER_SIGN_IN_URL'),
      afterSignOutUrl: read('THUNDERID_AFTER_SIGN_OUT_URL'),
      attestationEnabled: read('THUNDERID_ATTESTATION_ENABLED')?.toLowerCase() == 'true',
      cloudProjectNumber: int.tryParse(read('THUNDERID_CLOUD_PROJECT_NUMBER') ?? ''),
      scopes: scopes == null || scopes.isEmpty ? _defaultScopes : scopes,
      endpoints: endpoints,
      ouId: read('THUNDERID_OU_ID'),
      backendUrl: read('THUNDERID_BACKEND_URL'),
    );
  }

  /// Host and port shown next to the server health indicator.
  String get serverLabel {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || uri.host.isEmpty) return baseUrl;
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }

  ThunderIDConfig toSdkConfig() => ThunderIDConfig(
        baseUrl: backendUrl ?? baseUrl,
        clientId: clientId,
        applicationId: applicationId,
        afterSignInUrl: afterSignInUrl,
        afterSignOutUrl: afterSignOutUrl,
        scopes: scopes,
        attestationEnabled: attestationEnabled,
        cloudProjectNumber: cloudProjectNumber,
        // Local ThunderID servers serve a self-signed certificate, which Android rejects.
        // Debug builds only; release builds keep strict TLS.
        allowInsecureConnections: kDebugMode,
        endpoints: EndpointsConfig(
          users: endpoints[ManagementEndpointKeys.users],
          userTypes: endpoints[ManagementEndpointKeys.userTypes],
          groups: endpoints[ManagementEndpointKeys.groups],
          roles: endpoints[ManagementEndpointKeys.roles],
          agents: endpoints[ManagementEndpointKeys.agents],
          agentTypes: endpoints[ManagementEndpointKeys.agentTypes],
          applications: endpoints[ManagementEndpointKeys.applications],
          backend: backendUrl == null ? null : const BackendEndpoints(),
        ),
        preferences: const ThunderIDPreferences(
          theme: ThemePreferences(mode: 'dark'),
          i18n: I18nPreferences(bundles: playgroundBundles),
        ),
      );
}
