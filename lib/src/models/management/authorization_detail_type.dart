// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'json_reader.dart';

/// How the server authenticates itself to an authorization details processor: `none`, `bearer`,
/// `basic`, or `api_key` in [type], with that method's fields in [properties]. The server returns
/// credential values masked (`******`); sending a masked value back keeps the stored one.
class ProcessorAuthentication {
  final String type;
  final Map<String, String> properties;

  const ProcessorAuthentication({required this.type, this.properties = const {}});

  factory ProcessorAuthentication.fromJson(Map<String, dynamic> json) => ProcessorAuthentication(
        type: readString(json, 'type'),
        properties: {
          for (final entry in readMap(json['properties']).entries)
            if (entry.value is String) entry.key: entry.value as String,
        },
      );

  Map<String, dynamic> toJson() => {'type': type, if (properties.isNotEmpty) 'properties': properties};
}

/// The endpoint that authorizes and enriches the details of one type.
class AuthorizationDetailProcessor {
  /// Absolute HTTPS URL (plain HTTP on a loopback host only).
  final String endpoint;
  final ProcessorAuthentication? authentication;

  const AuthorizationDetailProcessor({required this.endpoint, this.authentication});

  factory AuthorizationDetailProcessor.fromJson(Map<String, dynamic> json) => AuthorizationDetailProcessor(
        endpoint: readString(json, 'endpoint'),
        authentication: switch (json['authentication']) {
          final Map<dynamic, dynamic> auth => ProcessorAuthentication.fromJson(readMap(auth)),
          _ => null,
        },
      );

  Map<String, dynamic> toJson() => {
        'endpoint': endpoint,
        if (authentication != null) 'authentication': authentication!.toJson(),
      };
}

/// A registered RFC 9396 authorization details type (`/authorization-detail-types`).
class AuthorizationDetailType {
  final String id;

  /// The `type` value clients send in `authorization_details`, such as a URI. Immutable.
  final String type;
  final String name;
  final String? description;

  /// Increments when an update changes the schema, the consent template, [reuse], or adds or
  /// removes the processor.
  final int version;

  /// The JSON Schema 2020-12 every requested detail of this type must conform to.
  final Map<String, dynamic> schema;
  final String? consentTemplate;
  final AuthorizationDetailProcessor? processor;

  /// Whether an earlier approval may stand in for the consent prompt.
  final bool reuse;

  /// Declared in a resource file; cannot be updated or deleted through the API.
  final bool isReadOnly;

  const AuthorizationDetailType({
    required this.id,
    required this.type,
    required this.name,
    required this.version,
    this.description,
    this.schema = const {},
    this.consentTemplate,
    this.processor,
    this.reuse = false,
    this.isReadOnly = false,
  });

  factory AuthorizationDetailType.fromJson(Map<String, dynamic> json) => AuthorizationDetailType(
        id: readString(json, 'id'),
        type: readString(json, 'type'),
        name: readString(json, 'name'),
        description: readOptionalString(json, 'description'),
        version: readInt(json, 'version'),
        schema: readMap(json['schema']),
        consentTemplate: readOptionalString(json, 'consentTemplate'),
        processor: switch (json['processor']) {
          final Map<dynamic, dynamic> processor => AuthorizationDetailProcessor.fromJson(readMap(processor)),
          _ => null,
        },
        reuse: readOptionalBool(json, 'reuse') ?? false,
        isReadOnly: readOptionalBool(json, 'isReadOnly') ?? false,
      );
}

/// Payload for creating or updating an [AuthorizationDetailType]. On update, [type] must be the
/// current value: it cannot change.
class AuthorizationDetailTypeRequest {
  final String type;
  final String name;
  final Map<String, dynamic> schema;
  final String? description;
  final String? consentTemplate;
  final AuthorizationDetailProcessor? processor;
  final bool? reuse;

  const AuthorizationDetailTypeRequest({
    required this.type,
    required this.name,
    required this.schema,
    this.description,
    this.consentTemplate,
    this.processor,
    this.reuse,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'name': name,
        if (description != null) 'description': description,
        'schema': schema,
        if (consentTemplate != null) 'consentTemplate': consentTemplate,
        if (processor != null) 'processor': processor!.toJson(),
        if (reuse != null) 'reuse': reuse,
      };
}
