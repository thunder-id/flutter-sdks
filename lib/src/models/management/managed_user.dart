// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'access_status.dart';
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

  /// The effective access status, set by the server on a read.
  final AccessStatus? status;

  const ManagedUser({
    required this.id,
    required this.ouId,
    required this.type,
    this.ouHandle,
    this.display,
    this.isReadOnly = false,
    this.attributes = const {},
    this.status,
  });

  factory ManagedUser.fromJson(Map<String, dynamic> json) => ManagedUser(
        id: readString(json, 'id'),
        ouId: readString(json, 'ouId'),
        ouHandle: readOptionalString(json, 'ouHandle'),
        type: readString(json, 'type'),
        display: readOptionalString(json, 'display'),
        isReadOnly: readOptionalBool(json, 'isReadOnly') ?? false,
        attributes: readMap(json['attributes']),
        status: AccessStatus.maybeFromJson(json['status']),
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

/// Payload for creating a [ManagedUser] in the organization unit at a handle path; the path
/// gives the unit, so there is no `ouId`.
class CreateUserByPathRequest {
  final String type;
  final Map<String, dynamic>? attributes;

  const CreateUserByPathRequest({required this.type, this.attributes});

  Map<String, dynamic> toJson() => {'type': type, if (attributes != null) 'attributes': attributes};
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

/// What happens to a resource that references a user when the user is deleted.
enum UserUsageBehavior {
  fallback('fallback'),
  cascade('cascade'),
  restrict('restrict');

  /// The wire value.
  final String value;

  const UserUsageBehavior(this.value);

  /// Parses a wire value, or returns `null` for a behaviour this SDK does not know.
  static UserUsageBehavior? fromValue(String? value) {
    for (final behavior in values) {
      if (behavior.value == value) return behavior;
    }
    return null;
  }
}

/// A resource that references a user, such as an agent that names the user as its owner.
class UserUsage {
  final String id;
  final String displayName;

  /// The kind of resource, such as `agent`.
  final String resourceType;

  /// What happens to the resource when the user is deleted; `null` for a value this SDK does not
  /// know.
  final UserUsageBehavior? behaviorOnDelete;

  const UserUsage({
    required this.id,
    required this.displayName,
    required this.resourceType,
    this.behaviorOnDelete,
  });

  factory UserUsage.fromJson(Map<String, dynamic> json) => UserUsage(
        id: readString(json, 'id'),
        displayName: readString(json, 'displayName'),
        resourceType: readString(json, 'resourceType'),
        behaviorOnDelete: UserUsageBehavior.fromValue(readOptionalString(json, 'behaviorOnDelete')),
      );
}

/// The resources that reference a user. [totalResults] and [summary] are `null` when the server
/// could not tell; `0` means there are none.
class UserUsages {
  final List<UserUsage> usages;
  final int count;
  final int? totalResults;

  /// The number of usages of each resource type, such as `agent`.
  final Map<String, int>? summary;

  const UserUsages({required this.usages, required this.count, this.totalResults, this.summary});

  factory UserUsages.fromJson(Map<String, dynamic> json) {
    final usages = readList(json, 'usages').map((item) => UserUsage.fromJson(readMap(item))).toList(growable: false);
    final summary = json['summary'];
    return UserUsages(
      usages: usages,
      count: readInt(json, 'count', usages.length),
      totalResults: json['totalResults'] is num ? readInt(json, 'totalResults') : null,
      summary: summary is Map
          ? {
              for (final entry in summary.entries)
                if (entry.value is num) entry.key.toString(): (entry.value as num).toInt(),
            }
          : null,
    );
  }
}

/// New values for some of a user's credential attributes, keyed by attribute name.
class UpdateUserCredentialsRequest {
  final Map<String, String> credentials;

  const UpdateUserCredentialsRequest({required this.credentials});

  Map<String, dynamic> toJson() => {'credentials': credentials};
}
