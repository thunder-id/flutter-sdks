// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'json_reader.dart';

/// The kind of identity that can be a member of a group.
enum GroupMemberType {
  user('user'),
  group('group'),
  agent('agent');

  /// The wire value.
  final String value;

  const GroupMemberType(this.value);

  /// Parses a wire value, or returns `null` for a type this SDK does not know.
  static GroupMemberType? fromValue(String? value) {
    for (final type in values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// A member of a [Group]. Used both as a returned record and as the input to add or remove a
/// member, in which case only [id] and [type] are sent.
class GroupMember {
  final String id;
  final GroupMemberType type;

  /// A label the server resolved for the member, when requested with `include=display`.
  final String? display;

  const GroupMember({required this.id, required this.type, this.display});

  /// Parses a member, or returns `null` when its type is unknown.
  static GroupMember? tryFromJson(Object? value) {
    final json = readMap(value);
    final type = GroupMemberType.fromValue(readOptionalString(json, 'type'));
    if (type == null) return null;
    return GroupMember(
      id: readString(json, 'id'),
      type: type,
      display: readOptionalString(json, 'display'),
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'type': type.value};
}

/// A group record administered through the management API.
class Group {
  final String id;
  final String name;
  final String ouId;
  final String? ouHandle;
  final String? description;
  final List<GroupMember> members;

  const Group({
    required this.id,
    required this.name,
    required this.ouId,
    this.ouHandle,
    this.description,
    this.members = const [],
  });

  factory Group.fromJson(Map<String, dynamic> json) => Group(
        id: readString(json, 'id'),
        name: readString(json, 'name'),
        ouId: readString(json, 'ouId'),
        ouHandle: readOptionalString(json, 'ouHandle'),
        description: readOptionalString(json, 'description'),
        members: readList(json, 'members').map(GroupMember.tryFromJson).whereType<GroupMember>().toList(),
      );
}

/// A group a user or agent belongs to, as returned by the membership listings.
class MembershipGroup {
  final String id;
  final String name;
  final String ouId;

  const MembershipGroup({required this.id, required this.name, required this.ouId});

  factory MembershipGroup.fromJson(Map<String, dynamic> json) => MembershipGroup(
        id: readString(json, 'id'),
        name: readString(json, 'name'),
        ouId: readString(json, 'ouId'),
      );
}

/// Payload for creating a [Group].
class CreateGroupRequest {
  final String name;
  final String ouId;
  final String? description;
  final List<GroupMember>? members;

  const CreateGroupRequest({required this.name, required this.ouId, this.description, this.members});

  Map<String, dynamic> toJson() => {
        'name': name,
        'ouId': ouId,
        if (description != null) 'description': description,
        if (members != null) 'members': members!.map((member) => member.toJson()).toList(),
      };
}

/// Payload for updating a [Group]. Membership changes go through the member operations instead.
class UpdateGroupRequest {
  final String name;
  final String ouId;
  final String? description;

  const UpdateGroupRequest({required this.name, required this.ouId, this.description});

  Map<String, dynamic> toJson() => {
        'name': name,
        'ouId': ouId,
        if (description != null) 'description': description,
      };
}
