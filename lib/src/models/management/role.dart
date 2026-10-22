// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'json_reader.dart';

/// The kind of identity a role can be assigned to.
enum RoleAssigneeType {
  user('user'),
  group('group'),
  app('app'),
  agent('agent');

  /// The wire value.
  final String value;

  const RoleAssigneeType(this.value);

  /// Parses a wire value, or returns `null` for a type this SDK does not know.
  static RoleAssigneeType? fromValue(String? value) {
    for (final type in values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// The permissions a role grants on one resource server.
class RoleResourcePermissions {
  final String resourceServerId;
  final List<String> permissions;

  const RoleResourcePermissions({required this.resourceServerId, this.permissions = const []});

  factory RoleResourcePermissions.fromJson(Map<String, dynamic> json) => RoleResourcePermissions(
        resourceServerId: readString(json, 'resourceServerId'),
        permissions: readStringList(json, 'permissions'),
      );

  Map<String, dynamic> toJson() => {'resourceServerId': resourceServerId, 'permissions': permissions};
}

/// An identity a role is assigned to. Used both as a returned record and as the input to add or
/// remove an assignment, in which case only [id] and [type] are sent.
class RoleAssignment {
  final String id;
  final RoleAssigneeType type;

  /// A label the server resolved for the assignee, when requested with `include=display`.
  final String? display;

  const RoleAssignment({required this.id, required this.type, this.display});

  /// Parses an assignment, or returns `null` when its type is unknown.
  static RoleAssignment? tryFromJson(Object? value) {
    final json = readMap(value);
    final type = RoleAssigneeType.fromValue(readOptionalString(json, 'type'));
    if (type == null) return null;
    return RoleAssignment(
      id: readString(json, 'id'),
      type: type,
      display: readOptionalString(json, 'display'),
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'type': type.value};
}

/// A role record administered through the management API.
///
/// A role read from a list carries no [permissions]; read it by id to get them.
class Role {
  final String id;
  final String name;
  final String ouId;
  final String? ouHandle;
  final String? description;
  final bool isReadOnly;
  final List<RoleResourcePermissions> permissions;

  const Role({
    required this.id,
    required this.name,
    required this.ouId,
    this.ouHandle,
    this.description,
    this.isReadOnly = false,
    this.permissions = const [],
  });

  factory Role.fromJson(Map<String, dynamic> json) => Role(
        id: readString(json, 'id'),
        name: readString(json, 'name'),
        ouId: readString(json, 'ouId'),
        ouHandle: readOptionalString(json, 'ouHandle'),
        description: readOptionalString(json, 'description'),
        isReadOnly: readOptionalBool(json, 'isReadOnly') ?? false,
        permissions: readList(json, 'permissions')
            .map((entry) => RoleResourcePermissions.fromJson(readMap(entry)))
            .toList(growable: false),
      );
}

/// Payload for creating a [Role].
class CreateRoleRequest {
  final String name;
  final String ouId;
  final String? description;
  final List<RoleResourcePermissions>? permissions;
  final List<RoleAssignment>? assignments;

  const CreateRoleRequest({
    required this.name,
    required this.ouId,
    this.description,
    this.permissions,
    this.assignments,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'ouId': ouId,
        if (description != null) 'description': description,
        if (permissions != null) 'permissions': permissions!.map((entry) => entry.toJson()).toList(),
        if (assignments != null) 'assignments': assignments!.map((entry) => entry.toJson()).toList(),
      };
}

/// Payload for updating a [Role]. Assignment changes go through the assignment operations.
class UpdateRoleRequest {
  final String name;
  final String ouId;
  final String? description;
  final List<RoleResourcePermissions> permissions;

  const UpdateRoleRequest({
    required this.name,
    required this.ouId,
    this.description,
    this.permissions = const [],
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'ouId': ouId,
        if (description != null) 'description': description,
        'permissions': permissions.map((entry) => entry.toJson()).toList(),
      };
}
