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

/// Playground settings read from `.env`.
class PlaygroundConfig {
  final String baseUrl;
  final String? applicationId;
  final String? clientId;
  final String? afterSignInUrl;
  final String? afterSignOutUrl;
  final bool attestationEnabled;
  final int? cloudProjectNumber;

  /// Base URL of an app backend that runs sign-in (`endpoints.backend`). When set, the SDK signs
  /// in through it and [baseUrl] is the API base its proxy fronts.
  final String? backendUrl;

  const PlaygroundConfig({
    required this.baseUrl,
    this.applicationId,
    this.clientId,
    this.afterSignInUrl,
    this.afterSignOutUrl,
    this.attestationEnabled = false,
    this.cloudProjectNumber,
    this.backendUrl,
  });

  factory PlaygroundConfig.fromEnv(Map<String, String> env) {
    String? read(String key) {
      final value = env[key]?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    return PlaygroundConfig(
      baseUrl: read('THUNDERID_BASE_URL') ?? 'https://localhost:8090',
      applicationId: read('THUNDERID_APP_ID'),
      clientId: read('THUNDERID_CLIENT_ID'),
      afterSignInUrl: read('THUNDERID_AFTER_SIGN_IN_URL'),
      afterSignOutUrl: read('THUNDERID_AFTER_SIGN_OUT_URL'),
      attestationEnabled: read('THUNDERID_ATTESTATION_ENABLED')?.toLowerCase() == 'true',
      cloudProjectNumber: int.tryParse(read('THUNDERID_CLOUD_PROJECT_NUMBER') ?? ''),
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
        baseUrl: baseUrl,
        clientId: clientId,
        applicationId: applicationId,
        afterSignInUrl: afterSignInUrl,
        afterSignOutUrl: afterSignOutUrl,
        scopes: const ['openid', 'profile', 'email'],
        attestationEnabled: attestationEnabled,
        cloudProjectNumber: cloudProjectNumber,
        // Local ThunderID servers serve a self-signed certificate, which Android rejects.
        // Debug builds only; release builds keep strict TLS.
        allowInsecureConnections: kDebugMode,
        endpoints: backendUrl == null ? null : EndpointsConfig(backend: BackendEndpoints(baseUrl: backendUrl!)),
        preferences: const ThunderIDPreferences(
          theme: ThemePreferences(mode: 'dark'),
          i18n: I18nPreferences(bundles: playgroundBundles),
        ),
      );
}
