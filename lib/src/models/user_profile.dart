// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

/// The signed-in user's profile, as returned by `GET /users/me`.
class UserProfile {
  final String id;
  final String? ouId;
  final String? type;
  final Map<String, dynamic> attributes;
  final String? display;
  final bool isReadOnly;

  const UserProfile({
    required this.id,
    this.ouId,
    this.type,
    this.attributes = const {},
    this.display,
    this.isReadOnly = false,
  });

  factory UserProfile.fromMap(Map<dynamic, dynamic> map) => UserProfile(
        id: map['id'] as String? ?? '',
        ouId: map['ouId'] as String?,
        type: map['type'] as String?,
        attributes: _normalizeAttributes(map['attributes']),
        display: map['display'] as String?,
        isReadOnly: map['isReadOnly'] as bool? ?? false,
      );
}

/// Attribute schema metadata returned by `GET /users/me/meta`.
class AttributeSchema {
  final bool? credential;
  final String? description;
  final String? displayName;
  final String? mutability;
  final bool? readOnly;
  final String? regex;
  final bool? required;
  final List<AttributeSchema>? subAttributes;
  final String? type;
  final bool? unique;

  const AttributeSchema({
    this.credential,
    this.description,
    this.displayName,
    this.mutability,
    this.readOnly,
    this.regex,
    this.required,
    this.subAttributes,
    this.type,
    this.unique,
  });

  factory AttributeSchema.fromMap(Map<dynamic, dynamic> map) => AttributeSchema(
        credential: map['credential'] as bool?,
        description: map['description'] as String?,
        displayName: map['displayName'] as String?,
        mutability: map['mutability'] as String?,
        readOnly: map['readOnly'] as bool?,
        regex: map['regex'] as String?,
        required: map['required'] as bool?,
        subAttributes: (map['subAttributes'] as List?)
            ?.map((e) => AttributeSchema.fromMap(e as Map))
            .toList(),
        type: map['type'] as String?,
        unique: map['unique'] as bool?,
      );
}

/// The platform channel decodes nested containers as `Map<Object?, Object?>`, so a
/// plain `cast` only fixes the outermost level. Normalizing once on the way in lets
/// every downstream reader treat attributes as `Map<String, dynamic>`.
Map<String, dynamic> _normalizeAttributes(Object? value) {
  final normalized = _normalize(value);
  return normalized is Map<String, dynamic> ? normalized : <String, dynamic>{};
}

dynamic _normalize(Object? value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _normalize(entry.value),
    };
  }
  if (value is List) {
    return value.map(_normalize).toList();
  }
  return value;
}
