// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'json_reader.dart';

/// Credential format values.
abstract final class CredentialFormats {
  /// SD-JWT VC, the server's default.
  static const String sdJwt = 'dc+sd-jwt';
}

/// A claim a credential carries, with the name a wallet shows for it.
class CredentialClaimMapping {
  final String name;
  final String? displayName;

  const CredentialClaimMapping({required this.name, this.displayName});

  factory CredentialClaimMapping.fromJson(Map<String, dynamic> json) => CredentialClaimMapping(
        name: readString(json, 'name'),
        displayName: readOptionalString(json, 'displayName'),
      );

  Map<String, dynamic> toJson() => {'name': name, if (displayName != null) 'displayName': displayName};
}

/// How a wallet displays a credential.
class CredentialDisplay {
  final String? locale;
  final String? logoUri;

  const CredentialDisplay({this.locale, this.logoUri});

  factory CredentialDisplay.fromJson(Map<String, dynamic> json) => CredentialDisplay(
        locale: readOptionalString(json, 'locale'),
        logoUri: readOptionalString(json, 'logoUri'),
      );

  Map<String, dynamic> toJson() => {
        if (locale != null) 'locale': locale,
        if (logoUri != null) 'logoUri': logoUri,
      };
}

/// An OpenID4VCI credential configuration: a type of verifiable credential the issuer offers.
///
/// A listing returns each configuration's `id`, `handle`, `ouId`, `ouHandle`, `format`, `vct`
/// and `name` only; [claims], [display], [description] and [validitySeconds] come with a single
/// configuration.
class CredentialConfiguration {
  final String id;

  /// Unique handle of the configuration.
  final String handle;

  /// The organization unit that owns the configuration.
  final String ouId;

  /// The owning organization unit's handle, resolved by the server for display.
  final String? ouHandle;
  final String? name;
  final String? description;

  /// See [CredentialFormats].
  final String format;

  /// The verifiable credential type URI.
  final String vct;
  final List<CredentialClaimMapping> claims;
  final CredentialDisplay? display;
  final int? validitySeconds;

  const CredentialConfiguration({
    required this.id,
    required this.handle,
    required this.ouId,
    required this.format,
    required this.vct,
    this.ouHandle,
    this.name,
    this.description,
    this.claims = const [],
    this.display,
    this.validitySeconds,
  });

  factory CredentialConfiguration.fromJson(Map<String, dynamic> json) => CredentialConfiguration(
        id: readString(json, 'id'),
        handle: readString(json, 'handle'),
        ouId: readString(json, 'ouId'),
        ouHandle: readOptionalString(json, 'ouHandle'),
        name: readOptionalString(json, 'name'),
        description: readOptionalString(json, 'description'),
        format: readString(json, 'format'),
        vct: readString(json, 'vct'),
        claims: readList(json, 'claims')
            .map((item) => CredentialClaimMapping.fromJson(readMap(item)))
            .toList(growable: false),
        display: json['display'] is Map ? CredentialDisplay.fromJson(readMap(json['display'])) : null,
        validitySeconds: readOptionalInt(json, 'validitySeconds'),
      );
}

/// Payload for creating or replacing a credential configuration. An update is a full
/// replacement: fields left out are not kept.
class CredentialConfigurationRequest {
  final String handle;
  final String ouId;
  final String vct;
  final String? name;
  final String? description;

  /// See [CredentialFormats]; the server defaults to [CredentialFormats.sdJwt].
  final String? format;
  final List<CredentialClaimMapping>? claims;
  final CredentialDisplay? display;
  final int? validitySeconds;

  const CredentialConfigurationRequest({
    required this.handle,
    required this.ouId,
    required this.vct,
    this.name,
    this.description,
    this.format,
    this.claims,
    this.display,
    this.validitySeconds,
  });

  Map<String, dynamic> toJson() => {
        'handle': handle,
        'ouId': ouId,
        'vct': vct,
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (format != null) 'format': format,
        if (claims != null) 'claims': [for (final claim in claims!) claim.toJson()],
        if (display != null) 'display': display!.toJson(),
        if (validitySeconds != null) 'validitySeconds': validitySeconds,
      };
}
