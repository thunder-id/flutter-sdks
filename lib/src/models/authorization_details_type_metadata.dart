// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'management/json_reader.dart';

/// A change a client may make to a granted authorization detail at the token endpoint.
class AuthorizationDetailsModification {
  /// The dot-separated path of the field.
  final String field;

  /// `decrease`, `increase`, `removeItems`, or `addItems`.
  final String modification;

  const AuthorizationDetailsModification({required this.field, required this.modification});

  factory AuthorizationDetailsModification.fromJson(Map<String, dynamic> json) => AuthorizationDetailsModification(
        field: readString(json, 'field'),
        modification: readString(json, 'modification'),
      );
}

/// The public, request view of one RFC 9396 authorization details type a client may request
/// (`/oauth2/authorization-details-types`): the fields it may send and the changes it may make
/// to a granted detail. Processor, consent, and reuse settings are never part of it.
class AuthorizationDetailsTypeMetadata {
  /// The value a client sends as `type` in `authorization_details`.
  final String type;
  final String name;
  final String? description;
  final int version;

  /// The JSON Schema 2020-12 of the fields a client may send.
  final Map<String, dynamic> schema;
  final List<AuthorizationDetailsModification> modifications;

  const AuthorizationDetailsTypeMetadata({
    required this.type,
    required this.name,
    required this.version,
    this.description,
    this.schema = const {},
    this.modifications = const [],
  });

  factory AuthorizationDetailsTypeMetadata.fromJson(Map<String, dynamic> json) => AuthorizationDetailsTypeMetadata(
        type: readString(json, 'type'),
        name: readString(json, 'name'),
        description: readOptionalString(json, 'description'),
        version: readInt(json, 'version'),
        schema: readMap(json['schema']),
        modifications: [
          for (final item in readList(json, 'modifications'))
            if (item is Map) AuthorizationDetailsModification.fromJson(readMap(item)),
        ],
      );
}
