// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'json_reader.dart';

/// Values of an identity's effective access status, with precedence [suspended] over [locked]
/// over [active]. Applications are never [locked].
///
/// The server may add values; an [AccessStatus.value] this SDK does not know is kept as sent.
abstract final class AccessStatusValue {
  static const String active = 'ACTIVE';
  static const String locked = 'LOCKED';
  static const String suspended = 'SUSPENDED';
}

/// What put an identity into the status it reports.
abstract final class AccessHoldReason {
  static const String administrativeSuspension = 'ADMINISTRATIVE_SUSPENSION';
  static const String failedAttempts = 'FAILED_ATTEMPTS';
  static const String suspensionReleaseLock = 'SUSPENSION_RELEASE_LOCK';

  /// A suspension carried from the identity this one depends on, such as a personal agent's owner.
  static const String cascadedSuspension = 'CASCADED_SUSPENSION';

  /// A suspension the identity's owner placed, such as the owner of a personal agent.
  static const String ownerSuspension = 'OWNER_SUSPENSION';
}

/// Who placed a suspension: the organization, the identity's owner (such as the owner of an agent),
/// or [cascade] for one carried from the identity it depends on, such as a personal agent's owner,
/// while that identity is suspended. Each suspension is independent and is lifted only by whoever
/// placed it. A party this SDK does not know keeps its raw value.
abstract final class SuspensionAppliedBy {
  static const String cascade = 'cascade';
  static const String organization = 'organization';
  static const String owner = 'owner';
}

/// One live automatic lock: the authentication method it holds, and when it lifts.
class AccessLockedMethod {
  /// The authentication method the lock holds, or `account` for all of them.
  final String method;

  /// When the lock lifts on its own. `null` when it lasts until released.
  final String? expiresAt;

  const AccessLockedMethod({required this.method, this.expiresAt});

  factory AccessLockedMethod.fromJson(Map<String, dynamic> json) => AccessLockedMethod(
        method: readString(json, 'method'),
        expiresAt: readOptionalString(json, 'expiresAt'),
      );
}

/// What a management read says about a status beyond its value.
class AccessStatusDetails {
  /// Every live automatic lock. `null` for a status that is not a lock.
  final List<AccessLockedMethod>? lockedMethods;

  /// The operator's note on an administrative hold. Show it as plain text, never as markup.
  final String? operatorNote;

  /// One of [AccessHoldReason], or a value this SDK does not know.
  final String? reason;

  /// When an administrative hold was placed. `null` for an automatic lock.
  final String? since;

  /// Who placed each suspension in force, each one of [SuspensionAppliedBy] or a value this SDK
  /// does not know. Present only when the status is [AccessStatusValue.suspended], and only for an
  /// identity that more than the organization can suspend, such as a personal agent. `null` means
  /// the organization's.
  final List<String>? appliedBy;

  const AccessStatusDetails({this.lockedMethods, this.operatorNote, this.reason, this.since, this.appliedBy});

  factory AccessStatusDetails.fromJson(Map<String, dynamic> json) => AccessStatusDetails(
        lockedMethods: json['lockedMethods'] is List
            ? readList(json, 'lockedMethods')
                .whereType<Map<Object?, Object?>>()
                .map((entry) => AccessLockedMethod.fromJson(readMap(entry)))
                .toList(growable: false)
            : null,
        operatorNote: readOptionalString(json, 'operatorNote'),
        reason: readOptionalString(json, 'reason'),
        since: readOptionalString(json, 'since'),
        appliedBy: readOptionalStringList(json, 'appliedBy'),
      );
}

/// The access status a management read of a user, an agent or an application carries. The server
/// computes it on read and never accepts it on a write.
class AccessStatus {
  /// One of [AccessStatusValue], or a value this SDK does not know.
  final String value;

  /// What produced the status. `null` when there is nothing to add.
  final AccessStatusDetails? details;

  const AccessStatus({required this.value, this.details});

  /// Who holds the identity suspended, from [AccessStatusDetails.appliedBy]. Empty unless the
  /// status is [AccessStatusValue.suspended].
  List<String> get suspendedBy => value == AccessStatusValue.suspended ? details?.appliedBy ?? const [] : const [];

  /// Reads a `status` object, or returns `null` when [json] is not one or carries no value.
  static AccessStatus? maybeFromJson(Object? json) {
    if (json is! Map) return null;
    final map = readMap(json);
    final value = readOptionalString(map, 'value');
    if (value == null || value.isEmpty) return null;
    final details = readOptionalMap(map['details']);
    return AccessStatus(value: value, details: details == null ? null : AccessStatusDetails.fromJson(details));
  }
}
