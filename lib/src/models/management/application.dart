// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'access_status.dart';
import 'json_reader.dart';

// Applications administered through the management API. Every model reads leniently: a field of
// the wrong type reads as absent.

Map<String, dynamic>? _optionalMap(Object? value) => value is Map ? readMap(value) : null;

T? _optional<T>(Object? value, T Function(Map<String, dynamic> json) parse) =>
    value is Map ? parse(readMap(value)) : null;

/// The keys of [json] that [known] does not list, kept so an update can send them back.
Map<String, dynamic> _unknownFields(Map<String, dynamic> json, Set<String> known) => {
      for (final entry in json.entries)
        if (!known.contains(entry.key)) entry.key: entry.value,
    };

/// OAuth 2.0 grant type values.
abstract final class OAuth2GrantTypes {
  static const String authorizationCode = 'authorization_code';
  static const String ciba = 'urn:openid:params:grant-type:ciba';
  static const String clientCredentials = 'client_credentials';
  static const String implicit = 'implicit';
  static const String jwtBearer = 'urn:ietf:params:oauth:grant-type:jwt-bearer';
  static const String password = 'password';
  static const String refreshToken = 'refresh_token';
  static const String tokenExchange = 'urn:ietf:params:oauth:grant-type:token-exchange';
}

/// OAuth 2.0 response type values.
abstract final class OAuth2ResponseTypes {
  static const String code = 'code';
  static const String codeIdToken = 'code id_token';
  static const String codeToken = 'code token';
  static const String idToken = 'id_token';
  static const String token = 'token';
  static const String tokenIdToken = 'token id_token';
}

/// Token endpoint authentication method values.
abstract final class TokenEndpointAuthMethods {
  static const String clientSecretBasic = 'client_secret_basic';
  static const String clientSecretJwt = 'client_secret_jwt';
  static const String clientSecretPost = 'client_secret_post';
  static const String none = 'none';
  static const String privateKeyJwt = 'private_key_jwt';
}

/// Inbound authentication protocol values.
abstract final class InboundAuthTypes {
  static const String oauth2 = 'oauth2';
}

/// Base token configuration shared by the tokens an application issues, also used for the
/// application's assertion.
class TokenConfig {
  /// Validity period, in seconds.
  final int validityPeriod;

  /// User attributes to include in the token.
  final List<String> userAttributes;

  const TokenConfig({required this.validityPeriod, this.userAttributes = const []});

  factory TokenConfig.fromJson(Map<String, dynamic> json) => TokenConfig(
        validityPeriod: readInt(json, 'validityPeriod'),
        userAttributes: readStringList(json, 'userAttributes'),
      );

  Map<String, dynamic> toJson() => {'validityPeriod': validityPeriod, 'userAttributes': userAttributes};
}

/// Access token settings for one kind of subject (a user or the client itself).
class AccessTokenSubConfig {
  final int? validityPeriod;
  final List<String>? attributes;

  const AccessTokenSubConfig({this.validityPeriod, this.attributes});

  factory AccessTokenSubConfig.fromJson(Map<String, dynamic> json) => AccessTokenSubConfig(
        validityPeriod: readOptionalInt(json, 'validityPeriod'),
        attributes: readOptionalStringList(json, 'attributes'),
      );

  Map<String, dynamic> toJson() => {
        if (validityPeriod != null) 'validityPeriod': validityPeriod,
        if (attributes != null) 'attributes': attributes,
      };
}

/// Access token configuration.
class AccessTokenConfig {
  final AccessTokenSubConfig? userConfig;
  final AccessTokenSubConfig? clientConfig;
  final String? defaultAudience;

  const AccessTokenConfig({this.userConfig, this.clientConfig, this.defaultAudience});

  factory AccessTokenConfig.fromJson(Map<String, dynamic> json) => AccessTokenConfig(
        userConfig: _optional(json['userConfig'], AccessTokenSubConfig.fromJson),
        clientConfig: _optional(json['clientConfig'], AccessTokenSubConfig.fromJson),
        defaultAudience: readOptionalString(json, 'defaultAudience'),
      );

  Map<String, dynamic> toJson() => {
        if (userConfig != null) 'userConfig': userConfig!.toJson(),
        if (clientConfig != null) 'clientConfig': clientConfig!.toJson(),
        if (defaultAudience != null) 'defaultAudience': defaultAudience,
      };
}

/// ID token configuration.
class IDTokenConfig {
  final int? validityPeriod;
  final List<String>? userAttributes;

  /// One of `JWT`, `JWE`, `NESTED_JWT`.
  final String? responseType;
  final String? encryptionAlg;
  final String? encryptionEnc;

  const IDTokenConfig({
    this.validityPeriod,
    this.userAttributes,
    this.responseType,
    this.encryptionAlg,
    this.encryptionEnc,
  });

  factory IDTokenConfig.fromJson(Map<String, dynamic> json) => IDTokenConfig(
        validityPeriod: readOptionalInt(json, 'validityPeriod'),
        userAttributes: readOptionalStringList(json, 'userAttributes'),
        responseType: readOptionalString(json, 'responseType'),
        encryptionAlg: readOptionalString(json, 'encryptionAlg'),
        encryptionEnc: readOptionalString(json, 'encryptionEnc'),
      );

  Map<String, dynamic> toJson() => {
        if (validityPeriod != null) 'validityPeriod': validityPeriod,
        if (userAttributes != null) 'userAttributes': userAttributes,
        if (responseType != null) 'responseType': responseType,
        if (encryptionAlg != null) 'encryptionAlg': encryptionAlg,
        if (encryptionEnc != null) 'encryptionEnc': encryptionEnc,
      };
}

/// Refresh token configuration.
class RefreshTokenConfig {
  final int validityPeriod;

  const RefreshTokenConfig({required this.validityPeriod});

  factory RefreshTokenConfig.fromJson(Map<String, dynamic> json) =>
      RefreshTokenConfig(validityPeriod: readInt(json, 'validityPeriod'));

  Map<String, dynamic> toJson() => {'validityPeriod': validityPeriod};
}

/// Identity assertion JWT authorization grant (ID-JAG) configuration.
class IDJAGConfig {
  final bool enabled;
  final List<String>? allowedAudiences;
  final int? validityPeriod;

  const IDJAGConfig({required this.enabled, this.allowedAudiences, this.validityPeriod});

  factory IDJAGConfig.fromJson(Map<String, dynamic> json) => IDJAGConfig(
        enabled: readOptionalBool(json, 'enabled') ?? false,
        allowedAudiences: readOptionalStringList(json, 'allowedAudiences'),
        validityPeriod: readOptionalInt(json, 'validityPeriod'),
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        if (allowedAudiences != null) 'allowedAudiences': allowedAudiences,
        if (validityPeriod != null) 'validityPeriod': validityPeriod,
      };
}

/// Token settings of an OAuth 2.0 application.
class OAuth2TokenConfig {
  final AccessTokenConfig? accessToken;
  final IDTokenConfig? idToken;
  final RefreshTokenConfig? refreshToken;
  final IDJAGConfig? idJag;
  final int? validityPeriod;
  final List<String>? userAttributes;

  const OAuth2TokenConfig({
    this.accessToken,
    this.idToken,
    this.refreshToken,
    this.idJag,
    this.validityPeriod,
    this.userAttributes,
  });

  factory OAuth2TokenConfig.fromJson(Map<String, dynamic> json) => OAuth2TokenConfig(
        accessToken: _optional(json['accessToken'], AccessTokenConfig.fromJson),
        idToken: _optional(json['idToken'], IDTokenConfig.fromJson),
        refreshToken: _optional(json['refreshToken'], RefreshTokenConfig.fromJson),
        idJag: _optional(json['idJag'], IDJAGConfig.fromJson),
        validityPeriod: readOptionalInt(json, 'validityPeriod'),
        userAttributes: readOptionalStringList(json, 'userAttributes'),
      );

  Map<String, dynamic> toJson() => {
        if (accessToken != null) 'accessToken': accessToken!.toJson(),
        if (idToken != null) 'idToken': idToken!.toJson(),
        if (refreshToken != null) 'refreshToken': refreshToken!.toJson(),
        if (idJag != null) 'idJag': idJag!.toJson(),
        if (validityPeriod != null) 'validityPeriod': validityPeriod,
        if (userAttributes != null) 'userAttributes': userAttributes,
      };
}

/// Userinfo endpoint configuration.
class UserInfoConfig {
  final List<String>? userAttributes;

  /// One of `JSON`, `JWS`, `JWE`, `NESTED_JWT`.
  final String? responseType;
  final String? signingAlg;
  final String? encryptionAlg;
  final String? encryptionEnc;

  const UserInfoConfig({
    this.userAttributes,
    this.responseType,
    this.signingAlg,
    this.encryptionAlg,
    this.encryptionEnc,
  });

  factory UserInfoConfig.fromJson(Map<String, dynamic> json) => UserInfoConfig(
        userAttributes: readOptionalStringList(json, 'userAttributes'),
        responseType: readOptionalString(json, 'responseType'),
        signingAlg: readOptionalString(json, 'signingAlg'),
        encryptionAlg: readOptionalString(json, 'encryptionAlg'),
        encryptionEnc: readOptionalString(json, 'encryptionEnc'),
      );

  Map<String, dynamic> toJson() => {
        if (userAttributes != null) 'userAttributes': userAttributes,
        if (responseType != null) 'responseType': responseType,
        if (signingAlg != null) 'signingAlg': signingAlg,
        if (encryptionAlg != null) 'encryptionAlg': encryptionAlg,
        if (encryptionEnc != null) 'encryptionEnc': encryptionEnc,
      };
}

/// A certificate attached to an OAuth 2.0 application, e.g. a JWKS URI.
class ApplicationCertificate {
  final String type;
  final String? value;

  const ApplicationCertificate({required this.type, this.value});

  factory ApplicationCertificate.fromJson(Map<String, dynamic> json) =>
      ApplicationCertificate(type: readString(json, 'type'), value: readOptionalString(json, 'value'));

  Map<String, dynamic> toJson() => {'type': type, if (value != null) 'value': value};
}

/// OAuth 2.0 / OIDC configuration of an application.
class OAuth2Config {
  final String? clientId;

  /// Write-only on the server: sent to set a secret, never returned.
  final String? clientSecret;
  final List<String>? redirectUris;
  final List<String>? postLogoutRedirectUris;

  /// See [OAuth2GrantTypes].
  final List<String> grantTypes;

  /// See [OAuth2ResponseTypes].
  final List<String> responseTypes;

  /// See [TokenEndpointAuthMethods].
  final String? tokenEndpointAuthMethod;
  final bool? pkceRequired;
  final bool? publicClient;
  final List<String>? scopes;
  final OAuth2TokenConfig? token;
  final UserInfoConfig? userInfo;

  /// The claims released for each scope.
  final Map<String, List<String>>? scopeClaims;
  final bool? requirePushedAuthorizationRequests;
  final ApplicationCertificate? certificate;
  final List<String>? acrValues;

  /// Fields the server returned that this SDK does not model. They are sent back unchanged.
  final Map<String, dynamic> additionalFields;

  const OAuth2Config({
    this.grantTypes = const [],
    this.responseTypes = const [],
    this.clientId,
    this.clientSecret,
    this.redirectUris,
    this.postLogoutRedirectUris,
    this.tokenEndpointAuthMethod,
    this.pkceRequired,
    this.publicClient,
    this.scopes,
    this.token,
    this.userInfo,
    this.scopeClaims,
    this.requirePushedAuthorizationRequests,
    this.certificate,
    this.acrValues,
    this.additionalFields = const {},
  });

  static const Set<String> _known = {
    'clientId',
    'clientSecret',
    'redirectUris',
    'postLogoutRedirectUris',
    'grantTypes',
    'responseTypes',
    'tokenEndpointAuthMethod',
    'pkceRequired',
    'publicClient',
    'scopes',
    'token',
    'userInfo',
    'scopeClaims',
    'requirePushedAuthorizationRequests',
    'certificate',
    'acrValues',
  };

  factory OAuth2Config.fromJson(Map<String, dynamic> json) {
    final scopeClaims = _optionalMap(json['scopeClaims']);
    return OAuth2Config(
      clientId: readOptionalString(json, 'clientId'),
      clientSecret: readOptionalString(json, 'clientSecret'),
      redirectUris: readOptionalStringList(json, 'redirectUris'),
      postLogoutRedirectUris: readOptionalStringList(json, 'postLogoutRedirectUris'),
      grantTypes: readStringList(json, 'grantTypes'),
      responseTypes: readStringList(json, 'responseTypes'),
      tokenEndpointAuthMethod: readOptionalString(json, 'tokenEndpointAuthMethod'),
      pkceRequired: readOptionalBool(json, 'pkceRequired'),
      publicClient: readOptionalBool(json, 'publicClient'),
      scopes: readOptionalStringList(json, 'scopes'),
      token: _optional(json['token'], OAuth2TokenConfig.fromJson),
      userInfo: _optional(json['userInfo'], UserInfoConfig.fromJson),
      scopeClaims: scopeClaims == null
          ? null
          : {
              for (final key in scopeClaims.keys)
                if (scopeClaims[key] is List) key: readStringList(scopeClaims, key),
            },
      requirePushedAuthorizationRequests: readOptionalBool(json, 'requirePushedAuthorizationRequests'),
      certificate: _optional(json['certificate'], ApplicationCertificate.fromJson),
      acrValues: readOptionalStringList(json, 'acrValues'),
      additionalFields: _unknownFields(json, _known),
    );
  }

  Map<String, dynamic> toJson() => {
        ...additionalFields,
        if (clientId != null) 'clientId': clientId,
        if (clientSecret != null) 'clientSecret': clientSecret,
        if (redirectUris != null) 'redirectUris': redirectUris,
        if (postLogoutRedirectUris != null) 'postLogoutRedirectUris': postLogoutRedirectUris,
        'grantTypes': grantTypes,
        'responseTypes': responseTypes,
        if (tokenEndpointAuthMethod != null) 'tokenEndpointAuthMethod': tokenEndpointAuthMethod,
        if (pkceRequired != null) 'pkceRequired': pkceRequired,
        if (publicClient != null) 'publicClient': publicClient,
        if (scopes != null) 'scopes': scopes,
        if (token != null) 'token': token!.toJson(),
        if (userInfo != null) 'userInfo': userInfo!.toJson(),
        if (scopeClaims != null) 'scopeClaims': scopeClaims,
        if (requirePushedAuthorizationRequests != null)
          'requirePushedAuthorizationRequests': requirePushedAuthorizationRequests,
        if (certificate != null) 'certificate': certificate!.toJson(),
        if (acrValues != null) 'acrValues': acrValues,
      };
}

/// Inbound authentication configuration of an application.
class InboundAuthConfig {
  /// See [InboundAuthTypes]; currently always `oauth2`.
  final String type;
  final OAuth2Config config;

  const InboundAuthConfig({this.type = InboundAuthTypes.oauth2, required this.config});

  factory InboundAuthConfig.fromJson(Map<String, dynamic> json) => InboundAuthConfig(
        type: readString(json, 'type'),
        config: OAuth2Config.fromJson(readMap(json['config'])),
      );

  Map<String, dynamic> toJson() => {'type': type, 'config': config.toJson()};
}

/// Android app attestation configuration.
class AndroidAttestationConfig {
  final String? packageName;
  final List<String>? certificateSha256Digests;
  final String? serviceAccountCredentials;

  const AndroidAttestationConfig({this.packageName, this.certificateSha256Digests, this.serviceAccountCredentials});

  factory AndroidAttestationConfig.fromJson(Map<String, dynamic> json) => AndroidAttestationConfig(
        packageName: readOptionalString(json, 'packageName'),
        certificateSha256Digests: readOptionalStringList(json, 'certificateSha256Digests'),
        serviceAccountCredentials: readOptionalString(json, 'serviceAccountCredentials'),
      );

  Map<String, dynamic> toJson() => {
        if (packageName != null) 'packageName': packageName,
        if (certificateSha256Digests != null) 'certificateSha256Digests': certificateSha256Digests,
        if (serviceAccountCredentials != null) 'serviceAccountCredentials': serviceAccountCredentials,
      };
}

/// Apple app attestation configuration.
class AppleAttestationConfig {
  final String teamId;
  final String bundleId;

  const AppleAttestationConfig({required this.teamId, required this.bundleId});

  factory AppleAttestationConfig.fromJson(Map<String, dynamic> json) =>
      AppleAttestationConfig(teamId: readString(json, 'teamId'), bundleId: readString(json, 'bundleId'));

  Map<String, dynamic> toJson() => {'teamId': teamId, 'bundleId': bundleId};
}

/// App attestation configuration. At most one platform can be configured.
class AttestationConfig {
  final bool? devMode;
  final AndroidAttestationConfig? android;
  final AppleAttestationConfig? apple;

  const AttestationConfig({this.devMode, this.android, this.apple})
      : assert(android == null || apple == null, 'At most one attestation platform can be configured.');

  factory AttestationConfig.fromJson(Map<String, dynamic> json) => AttestationConfig(
        devMode: readOptionalBool(json, 'devMode'),
        android: _optional(json['android'], AndroidAttestationConfig.fromJson),
        apple: json['android'] is Map ? null : _optional(json['apple'], AppleAttestationConfig.fromJson),
      );

  Map<String, dynamic> toJson() => {
        if (devMode != null) 'devMode': devMode,
        if (android != null) 'android': android!.toJson(),
        if (apple != null) 'apple': apple!.toJson(),
      };
}

/// The fields of an application a caller can set. Used to create and to update an application.
///
/// An [Application] is one, so an application read from the server can be sent back through
/// `updateApplication` as it is; its [toJson] leaves out the server-set `id`, `createdAt` and
/// `updatedAt`.
class ApplicationRequest {
  final String name;
  final String? description;
  final String? url;
  final String? logoUrl;
  final String? tosUri;
  final String? policyUri;
  final List<String>? contacts;
  final String? authFlowId;
  final String? registrationFlowId;
  final bool? isRegistrationFlowEnabled;
  final String? recoveryFlowId;
  final bool? isRecoveryFlowEnabled;
  final String? signOutFlowId;
  final List<String>? userAttributes;
  final List<String>? allowedUserTypes;
  final List<String>? allowedAgentTypes;
  final String? themeId;
  final String? layoutId;

  /// One of `browser`, `fullstack`, `mobile`, `m2m`, `mcp`, `custom`.
  final String? type;
  final String? template;

  /// Write-only on the server: sent to set a flow secret.
  final String? flowSecret;
  final List<InboundAuthConfig>? inboundAuthConfig;
  final String? ouId;
  final TokenConfig? assertion;
  final AttestationConfig? attestation;
  final List<String>? passkeyAllowedOrigins;
  final bool? isReadOnly;

  /// Fields the server returned that this SDK does not model. They are sent back unchanged.
  final Map<String, dynamic> additionalFields;

  const ApplicationRequest({
    required this.name,
    this.description,
    this.url,
    this.logoUrl,
    this.tosUri,
    this.policyUri,
    this.contacts,
    this.authFlowId,
    this.registrationFlowId,
    this.isRegistrationFlowEnabled,
    this.recoveryFlowId,
    this.isRecoveryFlowEnabled,
    this.signOutFlowId,
    this.userAttributes,
    this.allowedUserTypes,
    this.allowedAgentTypes,
    this.themeId,
    this.layoutId,
    this.type,
    this.template,
    this.flowSecret,
    this.inboundAuthConfig,
    this.ouId,
    this.assertion,
    this.attestation,
    this.passkeyAllowedOrigins,
    this.isReadOnly,
    this.additionalFields = const {},
  });

  static const Set<String> _known = {
    'id',
    'createdAt',
    'updatedAt',
    'name',
    'description',
    'url',
    'logoUrl',
    'tosUri',
    'policyUri',
    'contacts',
    'authFlowId',
    'registrationFlowId',
    'isRegistrationFlowEnabled',
    'recoveryFlowId',
    'isRecoveryFlowEnabled',
    'signOutFlowId',
    'userAttributes',
    'allowedUserTypes',
    'allowedAgentTypes',
    'themeId',
    'layoutId',
    'type',
    'template',
    'flowSecret',
    'inboundAuthConfig',
    'ouId',
    'assertion',
    'attestation',
    'passkeyAllowedOrigins',
    'isReadOnly',
  };

  factory ApplicationRequest.fromJson(Map<String, dynamic> json) => ApplicationRequest(
        name: readString(json, 'name'),
        description: readOptionalString(json, 'description'),
        url: readOptionalString(json, 'url'),
        logoUrl: readOptionalString(json, 'logoUrl'),
        tosUri: readOptionalString(json, 'tosUri'),
        policyUri: readOptionalString(json, 'policyUri'),
        contacts: readOptionalStringList(json, 'contacts'),
        authFlowId: readOptionalString(json, 'authFlowId'),
        registrationFlowId: readOptionalString(json, 'registrationFlowId'),
        isRegistrationFlowEnabled: readOptionalBool(json, 'isRegistrationFlowEnabled'),
        recoveryFlowId: readOptionalString(json, 'recoveryFlowId'),
        isRecoveryFlowEnabled: readOptionalBool(json, 'isRecoveryFlowEnabled'),
        signOutFlowId: readOptionalString(json, 'signOutFlowId'),
        userAttributes: readOptionalStringList(json, 'userAttributes'),
        allowedUserTypes: readOptionalStringList(json, 'allowedUserTypes'),
        allowedAgentTypes: readOptionalStringList(json, 'allowedAgentTypes'),
        themeId: readOptionalString(json, 'themeId'),
        layoutId: readOptionalString(json, 'layoutId'),
        type: readOptionalString(json, 'type'),
        template: readOptionalString(json, 'template'),
        flowSecret: readOptionalString(json, 'flowSecret'),
        inboundAuthConfig: _readInboundAuthConfig(json),
        ouId: readOptionalString(json, 'ouId'),
        assertion: _optional(json['assertion'], TokenConfig.fromJson),
        attestation: _optional(json['attestation'], AttestationConfig.fromJson),
        passkeyAllowedOrigins: readOptionalStringList(json, 'passkeyAllowedOrigins'),
        isReadOnly: readOptionalBool(json, 'isReadOnly'),
        additionalFields: _unknownFields(json, _known),
      );

  /// The request body: the settable fields that are set, plus [additionalFields].
  Map<String, dynamic> toJson() => {
        ...additionalFields,
        'name': name,
        if (description != null) 'description': description,
        if (url != null) 'url': url,
        if (logoUrl != null) 'logoUrl': logoUrl,
        if (tosUri != null) 'tosUri': tosUri,
        if (policyUri != null) 'policyUri': policyUri,
        if (contacts != null) 'contacts': contacts,
        if (authFlowId != null) 'authFlowId': authFlowId,
        if (registrationFlowId != null) 'registrationFlowId': registrationFlowId,
        if (isRegistrationFlowEnabled != null) 'isRegistrationFlowEnabled': isRegistrationFlowEnabled,
        if (recoveryFlowId != null) 'recoveryFlowId': recoveryFlowId,
        if (isRecoveryFlowEnabled != null) 'isRecoveryFlowEnabled': isRecoveryFlowEnabled,
        if (signOutFlowId != null) 'signOutFlowId': signOutFlowId,
        if (userAttributes != null) 'userAttributes': userAttributes,
        if (allowedUserTypes != null) 'allowedUserTypes': allowedUserTypes,
        if (allowedAgentTypes != null) 'allowedAgentTypes': allowedAgentTypes,
        if (themeId != null) 'themeId': themeId,
        if (layoutId != null) 'layoutId': layoutId,
        if (type != null) 'type': type,
        if (template != null) 'template': template,
        if (flowSecret != null) 'flowSecret': flowSecret,
        if (inboundAuthConfig != null) 'inboundAuthConfig': inboundAuthConfig!.map((entry) => entry.toJson()).toList(),
        if (ouId != null) 'ouId': ouId,
        if (assertion != null) 'assertion': assertion!.toJson(),
        if (attestation != null) 'attestation': attestation!.toJson(),
        if (passkeyAllowedOrigins != null) 'passkeyAllowedOrigins': passkeyAllowedOrigins,
        if (isReadOnly != null) 'isReadOnly': isReadOnly,
      };
}

/// The payload used to create an application. The server generates `id` and the timestamps.
typedef CreateApplicationRequest = ApplicationRequest;

/// The payload used to update an application.
typedef UpdateApplicationRequest = ApplicationRequest;

List<InboundAuthConfig>? _readInboundAuthConfig(Map<String, dynamic> json) => json['inboundAuthConfig'] is List
    ? readList(json, 'inboundAuthConfig')
        .whereType<Map<Object?, Object?>>()
        .map((entry) => InboundAuthConfig.fromJson(readMap(entry)))
        .toList(growable: false)
    : null;

/// An application registered in ThunderID: its server-set [id] and timestamps, and every
/// [ApplicationRequest] field.
class Application extends ApplicationRequest {
  final String id;
  final String? createdAt;
  final String? updatedAt;

  /// The effective access status, set by the server on a read. Applications are never locked.
  /// It is never sent back in a write.
  final AccessStatus? status;

  const Application({
    required this.id,
    required super.name,
    this.createdAt,
    this.updatedAt,
    this.status,
    super.description,
    super.url,
    super.logoUrl,
    super.tosUri,
    super.policyUri,
    super.contacts,
    super.authFlowId,
    super.registrationFlowId,
    super.isRegistrationFlowEnabled,
    super.recoveryFlowId,
    super.isRecoveryFlowEnabled,
    super.signOutFlowId,
    super.userAttributes,
    super.allowedUserTypes,
    super.allowedAgentTypes,
    super.themeId,
    super.layoutId,
    super.type,
    super.template,
    super.flowSecret,
    super.inboundAuthConfig,
    super.ouId,
    super.assertion,
    super.attestation,
    super.passkeyAllowedOrigins,
    super.isReadOnly,
    super.additionalFields,
  });

  factory Application.fromJson(Map<String, dynamic> json) {
    final fields = ApplicationRequest.fromJson(json);
    return Application(
      id: readString(json, 'id'),
      createdAt: readOptionalString(json, 'createdAt'),
      updatedAt: readOptionalString(json, 'updatedAt'),
      status: AccessStatus.maybeFromJson(json['status']),
      name: fields.name,
      description: fields.description,
      url: fields.url,
      logoUrl: fields.logoUrl,
      tosUri: fields.tosUri,
      policyUri: fields.policyUri,
      contacts: fields.contacts,
      authFlowId: fields.authFlowId,
      registrationFlowId: fields.registrationFlowId,
      isRegistrationFlowEnabled: fields.isRegistrationFlowEnabled,
      recoveryFlowId: fields.recoveryFlowId,
      isRecoveryFlowEnabled: fields.isRecoveryFlowEnabled,
      signOutFlowId: fields.signOutFlowId,
      userAttributes: fields.userAttributes,
      allowedUserTypes: fields.allowedUserTypes,
      allowedAgentTypes: fields.allowedAgentTypes,
      themeId: fields.themeId,
      layoutId: fields.layoutId,
      type: fields.type,
      template: fields.template,
      flowSecret: fields.flowSecret,
      inboundAuthConfig: fields.inboundAuthConfig,
      ouId: fields.ouId,
      assertion: fields.assertion,
      attestation: fields.attestation,
      passkeyAllowedOrigins: fields.passkeyAllowedOrigins,
      isReadOnly: fields.isReadOnly,
      // The server computes the status and refuses it on a write, so it is not kept to send back.
      additionalFields: Map.of(fields.additionalFields)..remove('status'),
    );
  }

  /// The OAuth client, when the application has one.
  OAuth2Config? get oauth2Config {
    for (final inbound in inboundAuthConfig ?? const <InboundAuthConfig>[]) {
      if (inbound.type == InboundAuthTypes.oauth2) return inbound.config;
    }
    return null;
  }
}

/// The summary of an application returned in list responses.
class BasicApplication {
  final String id;
  final String name;
  final String? description;
  final String? logoUrl;
  final String? authFlowId;
  final String? registrationFlowId;
  final bool? isRegistrationFlowEnabled;
  final String? type;
  final String? template;
  final bool isReadOnly;
  final String? clientId;

  /// The application's access status, such as `ACTIVE` or `SUSPENDED`, when the server reports it.
  final String? status;

  const BasicApplication({
    required this.id,
    required this.name,
    this.description,
    this.logoUrl,
    this.authFlowId,
    this.registrationFlowId,
    this.isRegistrationFlowEnabled,
    this.type,
    this.template,
    this.isReadOnly = false,
    this.clientId,
    this.status,
  });

  factory BasicApplication.fromJson(Map<String, dynamic> json) => BasicApplication(
        id: readString(json, 'id'),
        name: readString(json, 'name'),
        description: readOptionalString(json, 'description'),
        logoUrl: readOptionalString(json, 'logoUrl'),
        authFlowId: readOptionalString(json, 'authFlowId'),
        registrationFlowId: readOptionalString(json, 'registrationFlowId'),
        isRegistrationFlowEnabled: readOptionalBool(json, 'isRegistrationFlowEnabled'),
        type: readOptionalString(json, 'type'),
        template: readOptionalString(json, 'template'),
        isReadOnly: readOptionalBool(json, 'isReadOnly') ?? false,
        clientId: readOptionalString(json, 'clientId'),
        status: readOptionalString(readMap(json['status']), 'value'),
      );
}

/// What the server read from a client ID metadata document (CIMD): the client's name and links,
/// and the OAuth configuration it declares.
class CimdPreviewResponse {
  final String name;
  final List<InboundAuthConfig> inboundAuthConfig;
  final List<String>? contacts;
  final String? policyUri;
  final String? tosUri;
  final String? url;

  const CimdPreviewResponse({
    required this.name,
    this.inboundAuthConfig = const [],
    this.contacts,
    this.policyUri,
    this.tosUri,
    this.url,
  });

  factory CimdPreviewResponse.fromJson(Map<String, dynamic> json) => CimdPreviewResponse(
        name: readString(json, 'name'),
        inboundAuthConfig: _readInboundAuthConfig(json) ?? const [],
        contacts: readOptionalStringList(json, 'contacts'),
        policyUri: readOptionalString(json, 'policyUri'),
        tosUri: readOptionalString(json, 'tosUri'),
        url: readOptionalString(json, 'url'),
      );
}

/// The result of `regenerateClientSecret`.
class RegenerateClientSecretResult {
  /// The new client secret. This is the only time it can be read.
  final String clientSecret;

  /// The application after the change. `null` when a flow rotated the secret, since the flow does
  /// not return the application.
  final Application? application;

  const RegenerateClientSecretResult({required this.clientSecret, this.application});
}

/// The result of `regenerateFlowSecret`.
class RegenerateFlowSecretResult {
  /// The new flow secret. This is the only time it can be read.
  final String flowSecret;

  /// The application after the change.
  final Application application;

  const RegenerateFlowSecretResult({required this.flowSecret, required this.application});
}
