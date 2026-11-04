// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'json_reader.dart';

Map<String, List<String>> _readClaimValues(Object? value) {
  final map = readMap(value);
  return {
    for (final key in map.keys)
      if (map[key] is List) key: readStringList(map, key),
  };
}

/// An OpenID4VP presentation definition: what the verifier asks a wallet to present.
///
/// A listing returns each definition's `id`, `handle`, `ouId`, `ouHandle`, `name`, `vct` and
/// `format` only; the claim lists, [claimValues] and the trusted issuer settings come with a
/// single definition.
class PresentationDefinition {
  final String id;

  /// Unique handle of the definition.
  final String handle;

  /// The organization unit that owns the definition.
  final String ouId;

  /// The owning organization unit's handle, resolved by the server for display.
  final String? ouHandle;
  final String? name;
  final String? description;

  /// The verifiable credential type URI.
  final String vct;

  /// See `CredentialFormats`.
  final String format;
  final List<String> requestedClaims;
  final List<String> mandatoryClaims;
  final List<String> optionalClaims;

  /// The values each claim must hold, keyed by claim name.
  final Map<String, List<String>> claimValues;
  final bool? enforceTrustedIssuer;
  final List<String> trustedAuthorities;

  const PresentationDefinition({
    required this.id,
    required this.handle,
    required this.ouId,
    required this.vct,
    required this.format,
    this.ouHandle,
    this.name,
    this.description,
    this.requestedClaims = const [],
    this.mandatoryClaims = const [],
    this.optionalClaims = const [],
    this.claimValues = const {},
    this.enforceTrustedIssuer,
    this.trustedAuthorities = const [],
  });

  factory PresentationDefinition.fromJson(Map<String, dynamic> json) => PresentationDefinition(
        id: readString(json, 'id'),
        handle: readString(json, 'handle'),
        ouId: readString(json, 'ouId'),
        ouHandle: readOptionalString(json, 'ouHandle'),
        name: readOptionalString(json, 'name'),
        description: readOptionalString(json, 'description'),
        vct: readString(json, 'vct'),
        format: readString(json, 'format'),
        requestedClaims: readStringList(json, 'requestedClaims'),
        mandatoryClaims: readStringList(json, 'mandatoryClaims'),
        optionalClaims: readStringList(json, 'optionalClaims'),
        claimValues: _readClaimValues(json['claimValues']),
        enforceTrustedIssuer: readOptionalBool(json, 'enforceTrustedIssuer'),
        trustedAuthorities: readStringList(json, 'trustedAuthorities'),
      );
}

/// Payload for creating or replacing a presentation definition. An update is a full
/// replacement: fields left out are not kept.
class PresentationDefinitionRequest {
  final String handle;
  final String ouId;
  final String vct;
  final String? name;
  final String? description;

  /// See `CredentialFormats`; the server defaults to `dc+sd-jwt`.
  final String? format;
  final List<String>? requestedClaims;
  final List<String>? mandatoryClaims;
  final List<String>? optionalClaims;
  final Map<String, List<String>>? claimValues;
  final bool? enforceTrustedIssuer;
  final List<String>? trustedAuthorities;

  const PresentationDefinitionRequest({
    required this.handle,
    required this.ouId,
    required this.vct,
    this.name,
    this.description,
    this.format,
    this.requestedClaims,
    this.mandatoryClaims,
    this.optionalClaims,
    this.claimValues,
    this.enforceTrustedIssuer,
    this.trustedAuthorities,
  });

  Map<String, dynamic> toJson() => {
        'handle': handle,
        'ouId': ouId,
        'vct': vct,
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (format != null) 'format': format,
        if (requestedClaims != null) 'requestedClaims': requestedClaims,
        if (mandatoryClaims != null) 'mandatoryClaims': mandatoryClaims,
        if (optionalClaims != null) 'optionalClaims': optionalClaims,
        if (claimValues != null) 'claimValues': claimValues,
        if (enforceTrustedIssuer != null) 'enforceTrustedIssuer': enforceTrustedIssuer,
        if (trustedAuthorities != null) 'trustedAuthorities': trustedAuthorities,
      };
}
