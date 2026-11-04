// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'json_reader.dart';

// Dynamic client registration (RFC 7591 / RFC 7592). The wire format is snake_case; these models
// expose camelCase fields and map them both ways.

/// The client metadata fields shared by a registration request and a registration.
abstract class _ClientMetadata {
  final List<String>? postLogoutRedirectUris;
  final String? backchannelLogoutUri;

  /// See `OAuth2GrantTypes`.
  final List<String>? grantTypes;

  /// See `OAuth2ResponseTypes`.
  final List<String>? responseTypes;
  final String? clientName;
  final String? clientUri;
  final String? logoUri;

  /// See `TokenEndpointAuthMethods`.
  final String? tokenEndpointAuthMethod;
  final String? jwksUri;
  final Map<String, dynamic>? jwks;

  /// Space-separated scopes.
  final String? scope;
  final List<String>? contacts;
  final String? tosUri;
  final String? policyUri;
  final bool? requirePushedAuthorizationRequests;
  final String? userinfoSignedResponseAlg;
  final String? userinfoEncryptedResponseAlg;
  final String? userinfoEncryptedResponseEnc;
  final String? idTokenSignedResponseAlg;
  final String? idTokenEncryptedResponseAlg;
  final String? idTokenEncryptedResponseEnc;

  /// Metadata this SDK does not model, by its wire name, such as a language-tagged
  /// `client_name#fr`. Sent and read as is.
  final Map<String, dynamic> additionalFields;

  const _ClientMetadata({
    this.postLogoutRedirectUris,
    this.backchannelLogoutUri,
    this.grantTypes,
    this.responseTypes,
    this.clientName,
    this.clientUri,
    this.logoUri,
    this.tokenEndpointAuthMethod,
    this.jwksUri,
    this.jwks,
    this.scope,
    this.contacts,
    this.tosUri,
    this.policyUri,
    this.requirePushedAuthorizationRequests,
    this.userinfoSignedResponseAlg,
    this.userinfoEncryptedResponseAlg,
    this.userinfoEncryptedResponseEnc,
    this.idTokenSignedResponseAlg,
    this.idTokenEncryptedResponseAlg,
    this.idTokenEncryptedResponseEnc,
    this.additionalFields = const {},
  });

  Map<String, dynamic> _metadataJson() => {
        ...additionalFields,
        if (postLogoutRedirectUris != null) 'post_logout_redirect_uris': postLogoutRedirectUris,
        if (backchannelLogoutUri != null) 'backchannel_logout_uri': backchannelLogoutUri,
        if (grantTypes != null) 'grant_types': grantTypes,
        if (responseTypes != null) 'response_types': responseTypes,
        if (clientName != null) 'client_name': clientName,
        if (clientUri != null) 'client_uri': clientUri,
        if (logoUri != null) 'logo_uri': logoUri,
        if (tokenEndpointAuthMethod != null) 'token_endpoint_auth_method': tokenEndpointAuthMethod,
        if (jwksUri != null) 'jwks_uri': jwksUri,
        if (jwks != null) 'jwks': jwks,
        if (scope != null) 'scope': scope,
        if (contacts != null) 'contacts': contacts,
        if (tosUri != null) 'tos_uri': tosUri,
        if (policyUri != null) 'policy_uri': policyUri,
        if (requirePushedAuthorizationRequests != null)
          'require_pushed_authorization_requests': requirePushedAuthorizationRequests,
        if (userinfoSignedResponseAlg != null) 'userinfo_signed_response_alg': userinfoSignedResponseAlg,
        if (userinfoEncryptedResponseAlg != null) 'userinfo_encrypted_response_alg': userinfoEncryptedResponseAlg,
        if (userinfoEncryptedResponseEnc != null) 'userinfo_encrypted_response_enc': userinfoEncryptedResponseEnc,
        if (idTokenSignedResponseAlg != null) 'id_token_signed_response_alg': idTokenSignedResponseAlg,
        if (idTokenEncryptedResponseAlg != null) 'id_token_encrypted_response_alg': idTokenEncryptedResponseAlg,
        if (idTokenEncryptedResponseEnc != null) 'id_token_encrypted_response_enc': idTokenEncryptedResponseEnc,
      };
}

const Set<String> _metadataKeys = {
  'redirect_uris',
  'post_logout_redirect_uris',
  'backchannel_logout_uri',
  'grant_types',
  'response_types',
  'client_name',
  'client_uri',
  'logo_uri',
  'token_endpoint_auth_method',
  'jwks_uri',
  'jwks',
  'scope',
  'contacts',
  'tos_uri',
  'policy_uri',
  'require_pushed_authorization_requests',
  'userinfo_signed_response_alg',
  'userinfo_encrypted_response_alg',
  'userinfo_encrypted_response_enc',
  'id_token_signed_response_alg',
  'id_token_encrypted_response_alg',
  'id_token_encrypted_response_enc',
};

/// Payload for registering a client (RFC 7591). The server issues the `client_id` and, for a
/// confidential client, the `client_secret`.
class ClientRegistrationRequest extends _ClientMetadata {
  final List<String> redirectUris;

  /// The organization unit to register the client in.
  final String? ouId;

  const ClientRegistrationRequest({
    required this.redirectUris,
    this.ouId,
    super.postLogoutRedirectUris,
    super.backchannelLogoutUri,
    super.grantTypes,
    super.responseTypes,
    super.clientName,
    super.clientUri,
    super.logoUri,
    super.tokenEndpointAuthMethod,
    super.jwksUri,
    super.jwks,
    super.scope,
    super.contacts,
    super.tosUri,
    super.policyUri,
    super.requirePushedAuthorizationRequests,
    super.userinfoSignedResponseAlg,
    super.userinfoEncryptedResponseAlg,
    super.userinfoEncryptedResponseEnc,
    super.idTokenSignedResponseAlg,
    super.idTokenEncryptedResponseAlg,
    super.idTokenEncryptedResponseEnc,
    super.additionalFields,
  });

  /// The request body, in the RFC 7591 wire format.
  Map<String, dynamic> toJson() => {
        ..._metadataJson(),
        'redirect_uris': redirectUris,
        if (ouId != null) 'ou_id': ouId,
      };
}

/// Payload for replacing a client's registration (RFC 7592). The update is a full replacement:
/// metadata left out is not kept. `updateClientRegistration` sets the body's `client_id` from
/// its argument. [toString] never includes [clientSecret].
class UpdateClientRegistrationRequest extends ClientRegistrationRequest {
  /// Optional. When set, the server checks it against the client's current secret and refuses
  /// the update when they differ; it never changes the secret.
  final String? clientSecret;

  const UpdateClientRegistrationRequest({
    required super.redirectUris,
    this.clientSecret,
    super.ouId,
    super.postLogoutRedirectUris,
    super.backchannelLogoutUri,
    super.grantTypes,
    super.responseTypes,
    super.clientName,
    super.clientUri,
    super.logoUri,
    super.tokenEndpointAuthMethod,
    super.jwksUri,
    super.jwks,
    super.scope,
    super.contacts,
    super.tosUri,
    super.policyUri,
    super.requirePushedAuthorizationRequests,
    super.userinfoSignedResponseAlg,
    super.userinfoEncryptedResponseAlg,
    super.userinfoEncryptedResponseEnc,
    super.idTokenSignedResponseAlg,
    super.idTokenEncryptedResponseAlg,
    super.idTokenEncryptedResponseEnc,
    super.additionalFields,
  });

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (clientSecret != null) 'client_secret': clientSecret,
      };

  @override
  String toString() => 'UpdateClientRegistrationRequest(clientName: $clientName)';
}

/// A dynamically registered client, as the server returns it (RFC 7591 / RFC 7592).
///
/// [clientSecret] is set only in the result of `registerClient`: the server stores it
/// write-only, so this is the only time it can be read. [toString] never includes it.
class ClientRegistration extends _ClientMetadata {
  final String clientId;

  /// The issued client secret. Returned by `registerClient` only, and only for a client that has
  /// one; `null` everywhere else.
  final String? clientSecret;

  /// When the secret expires, in seconds since the epoch; `0` when it never does.
  final int clientSecretExpiresAt;

  /// The server's internal application id for the client.
  final String? appId;
  final List<String> redirectUris;

  const ClientRegistration({
    required this.clientId,
    this.clientSecret,
    this.clientSecretExpiresAt = 0,
    this.appId,
    this.redirectUris = const [],
    super.postLogoutRedirectUris,
    super.backchannelLogoutUri,
    super.grantTypes,
    super.responseTypes,
    super.clientName,
    super.clientUri,
    super.logoUri,
    super.tokenEndpointAuthMethod,
    super.jwksUri,
    super.jwks,
    super.scope,
    super.contacts,
    super.tosUri,
    super.policyUri,
    super.requirePushedAuthorizationRequests,
    super.userinfoSignedResponseAlg,
    super.userinfoEncryptedResponseAlg,
    super.userinfoEncryptedResponseEnc,
    super.idTokenSignedResponseAlg,
    super.idTokenEncryptedResponseAlg,
    super.idTokenEncryptedResponseEnc,
    super.additionalFields,
  });

  static const Set<String> _known = {
    ..._metadataKeys,
    'client_id',
    'client_secret',
    'client_secret_expires_at',
    'app_id',
  };

  /// Reads a registration from its RFC 7591 wire format.
  factory ClientRegistration.fromJson(Map<String, dynamic> json) => ClientRegistration(
        clientId: readString(json, 'client_id'),
        clientSecret: readOptionalString(json, 'client_secret'),
        clientSecretExpiresAt: readInt(json, 'client_secret_expires_at'),
        appId: readOptionalString(json, 'app_id'),
        redirectUris: readStringList(json, 'redirect_uris'),
        postLogoutRedirectUris: readOptionalStringList(json, 'post_logout_redirect_uris'),
        backchannelLogoutUri: readOptionalString(json, 'backchannel_logout_uri'),
        grantTypes: readOptionalStringList(json, 'grant_types'),
        responseTypes: readOptionalStringList(json, 'response_types'),
        clientName: readOptionalString(json, 'client_name'),
        clientUri: readOptionalString(json, 'client_uri'),
        logoUri: readOptionalString(json, 'logo_uri'),
        tokenEndpointAuthMethod: readOptionalString(json, 'token_endpoint_auth_method'),
        jwksUri: readOptionalString(json, 'jwks_uri'),
        jwks: readOptionalMap(json['jwks']),
        scope: readOptionalString(json, 'scope'),
        contacts: readOptionalStringList(json, 'contacts'),
        tosUri: readOptionalString(json, 'tos_uri'),
        policyUri: readOptionalString(json, 'policy_uri'),
        requirePushedAuthorizationRequests: readOptionalBool(json, 'require_pushed_authorization_requests'),
        userinfoSignedResponseAlg: readOptionalString(json, 'userinfo_signed_response_alg'),
        userinfoEncryptedResponseAlg: readOptionalString(json, 'userinfo_encrypted_response_alg'),
        userinfoEncryptedResponseEnc: readOptionalString(json, 'userinfo_encrypted_response_enc'),
        idTokenSignedResponseAlg: readOptionalString(json, 'id_token_signed_response_alg'),
        idTokenEncryptedResponseAlg: readOptionalString(json, 'id_token_encrypted_response_alg'),
        idTokenEncryptedResponseEnc: readOptionalString(json, 'id_token_encrypted_response_enc'),
        additionalFields: readUnmodeled(json, _known),
      );

  @override
  String toString() => 'ClientRegistration(clientId: $clientId, clientName: $clientName)';
}
