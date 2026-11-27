// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'json_reader.dart';

/// Answers whether the signed-in user may perform [action] (`view` when omitted) on [resource].
typedef CanPerform = bool Function(String resource, [String action]);

/// What the capabilities apply to: the whole deployment, or one organization unit.
class CapabilityScope {
  /// `deployment` or `ou`. A value the SDK does not know is kept as the server sent it.
  final String type;

  /// The organization unit, when [type] is `ou`.
  final String? ouId;

  const CapabilityScope({required this.type, this.ouId});

  factory CapabilityScope.fromJson(Map<String, dynamic> json) =>
      CapabilityScope(type: readString(json, 'type'), ouId: readOptionalString(json, 'ouId'));
}

/// The management actions the signed-in user's access token allows, from `GET /capabilities`
/// (spec "Management capabilities").
///
/// They decide what an application offers, not what is allowed: they are not an authorization
/// decision. The server authorizes every management request, and the SDK never skips or blocks
/// a request because of them.
class Capabilities {
  final CapabilityScope scope;

  /// Each resource (such as `app`, `user` or `serverconfig`) mapped to each of its actions
  /// (`view`, `create`, `update`, `delete`) and whether the user may perform it.
  final Map<String, Map<String, bool>> resources;

  const Capabilities({required this.scope, this.resources = const {}});

  /// Whether the user may perform [action] on [resource]: false for anything not reported.
  bool can(String resource, [String action = 'view']) => resources[resource]?[action] == true;

  /// Lenient: a resource or action whose value is not a map or a boolean is left out.
  factory Capabilities.fromJson(Map<String, dynamic> json) => Capabilities(
        scope: CapabilityScope.fromJson(readMap(json['scope'])),
        resources: {
          for (final resource in readMap(json['resources']).entries)
            if (resource.value is Map)
              resource.key: {
                for (final action in readMap(resource.value).entries)
                  if (action.value is bool) action.key: action.value as bool,
              },
        },
      );
}

/// What a management component may offer for one record (spec "Management capabilities",
/// requirement 6).
///
/// A record is locked when the server marks it `isReadOnly` or it is shared into the user's
/// organization unit by another one (`isOwnedByOU: false`). Pass `null` for a flag the record's
/// model does not carry.
class RecordAccess {
  /// Locked, shared in, or the user may not `update` the resource.
  final bool readOnly;

  /// Neither locked nor shared in, and the user may `delete` the resource.
  final bool canDelete;

  /// Runtime state (active, suspended) may change: not shared in and the user may `update`,
  /// whatever `isReadOnly` says.
  final bool canChangeState;

  const RecordAccess({required this.readOnly, required this.canDelete, required this.canChangeState});

  factory RecordAccess.from(String resource, {bool? isReadOnly, bool? isOwnedByOU, required CanPerform can}) {
    final sharedIn = isOwnedByOU == false;
    final locked = isReadOnly == true || sharedIn;
    final canUpdate = can(resource, 'update');
    return RecordAccess(
      readOnly: locked || !canUpdate,
      canDelete: !locked && can(resource, 'delete'),
      canChangeState: !sharedIn && canUpdate,
    );
  }
}
