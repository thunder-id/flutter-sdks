// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'json_reader.dart';

/// A user record administered through the management API.
///
/// This is a server record, not the signed-in user: that is [User]. The two deliberately do not
/// share a type (spec "Management operations", requirement 6).
class ManagedUser {
  final String id;
  final String ouId;
  final String? ouHandle;

  /// The user type (schema) handle, e.g. `customer`.
  final String type;

  /// A label the server resolved for the user, when requested with `include=display`.
  final String? display;
  final bool isReadOnly;
  final Map<String, dynamic> attributes;

  const ManagedUser({
    required this.id,
    required this.ouId,
    required this.type,
    this.ouHandle,
    this.display,
    this.isReadOnly = false,
    this.attributes = const {},
  });

  factory ManagedUser.fromJson(Map<String, dynamic> json) => ManagedUser(
        id: readString(json, 'id'),
        ouId: readString(json, 'ouId'),
        ouHandle: readOptionalString(json, 'ouHandle'),
        type: readString(json, 'type'),
        display: readOptionalString(json, 'display'),
        isReadOnly: readOptionalBool(json, 'isReadOnly') ?? false,
        attributes: readMap(json['attributes']),
      );
}

/// A user type (user schema) a [ManagedUser] can be created as.
class ManagedUserType {
  final String id;
  final String handle;
  final String? displayName;
  final String? ouId;
  final String? ouHandle;
  final bool? allowSelfRegistration;
  final bool isReadOnly;

  const ManagedUserType({
    required this.id,
    required this.handle,
    this.displayName,
    this.ouId,
    this.ouHandle,
    this.allowSelfRegistration,
    this.isReadOnly = false,
  });

  factory ManagedUserType.fromJson(Map<String, dynamic> json) => ManagedUserType(
        id: readString(json, 'id'),
        handle: readString(json, 'handle'),
        displayName: readOptionalString(json, 'displayName'),
        ouId: readOptionalString(json, 'ouId'),
        ouHandle: readOptionalString(json, 'ouHandle'),
        allowSelfRegistration: readOptionalBool(json, 'allowSelfRegistration'),
        isReadOnly: readOptionalBool(json, 'isReadOnly') ?? false,
      );
}

/// Payload for creating a [ManagedUser].
class CreateManagedUserRequest {
  final String ouId;
  final String type;
  final Map<String, dynamic>? attributes;

  /// Identifiers of groups to add the new user to.
  final List<String>? groups;

  const CreateManagedUserRequest({
    required this.ouId,
    required this.type,
    this.attributes,
    this.groups,
  });

  Map<String, dynamic> toJson() => {
        'ouId': ouId,
        'type': type,
        if (attributes != null) 'attributes': attributes,
        if (groups != null) 'groups': groups,
      };
}

/// Payload for updating a [ManagedUser]. The server replaces the attribute set, so pass every
/// attribute the user should keep.
class UpdateManagedUserRequest {
  final String? ouId;
  final String? type;
  final Map<String, dynamic>? attributes;
  final List<String>? groups;

  const UpdateManagedUserRequest({this.ouId, this.type, this.attributes, this.groups});

  Map<String, dynamic> toJson() => {
        if (ouId != null) 'ouId': ouId,
        if (type != null) 'type': type,
        if (attributes != null) 'attributes': attributes,
        if (groups != null) 'groups': groups,
      };
}
