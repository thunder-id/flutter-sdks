// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'json_reader.dart';

/// How a management operation that changes state is carried out.
enum AdministrationMode {
  /// Run the administration flow the server configures for the operation, which handles the
  /// consequences of the change (revoking grants, ending sessions, notifying). When no flow is
  /// configured, the API is called directly. Reading that configuration needs a token that may
  /// read server configuration.
  flow('flow'),

  /// Call the management API directly, with no flow. The default.
  native('native');

  /// The wire value.
  final String value;

  const AdministrationMode(this.value);
}

/// Keys of the `flow` server-config section that name the administration flow for each
/// operation. An unset key is the opt-out: the operation calls the management API directly.
abstract final class AdministrationFlowConfigKey {
  static const String actionDeletion = 'actionDeletionFlow';
  static const String agentSuspend = 'agentSuspendFlow';
  static const String agentUnlock = 'agentUnlockFlow';
  static const String agentUnsuspend = 'agentUnsuspendFlow';
  static const String applicationDeletion = 'applicationDeletionFlow';
  static const String applicationSuspend = 'applicationSuspendFlow';
  static const String applicationUnsuspend = 'applicationUnsuspendFlow';
  static const String groupDeletion = 'groupDeletionFlow';
  static const String groupMembershipRemoval = 'groupMembershipRemovalFlow';
  static const String roleAssignmentRemoval = 'roleAssignmentRemovalFlow';
  static const String roleDeletion = 'roleDeletionFlow';
  static const String rolePermissionRemoval = 'rolePermissionRemovalFlow';
  static const String secretRegeneration = 'secretRegenerationFlow';
  static const String userDeletion = 'userDeletionFlow';
  static const String userSuspend = 'userSuspendFlow';
  static const String userUnlock = 'userUnlockFlow';
  static const String userUnsuspend = 'userUnsuspendFlow';

  /// Every key, in the order above.
  static const List<String> values = [
    actionDeletion,
    agentSuspend,
    agentUnlock,
    agentUnsuspend,
    applicationDeletion,
    applicationSuspend,
    applicationUnsuspend,
    groupDeletion,
    groupMembershipRemoval,
    roleAssignmentRemoval,
    roleDeletion,
    rolePermissionRemoval,
    secretRegeneration,
    userDeletion,
    userSuspend,
    userUnlock,
    userUnsuspend,
  ];
}

/// Names of the inputs an administration flow reads. They avoid the execution request's top-level
/// names so a value cannot land in the wrong place.
abstract final class AdministrationFlowInput {
  static const String action = 'targetActionId';
  static const String application = 'targetApplicationId';
  static const String assignee = 'targetAssigneeId';
  static const String group = 'targetGroupId';
  static const String member = 'targetMemberId';
  static const String operatorNote = 'operatorNote';
  static const String permissions = 'targetPermissions';
  static const String resource = 'targetResourceId';
  static const String resourceServer = 'targetResourceServerId';
  static const String role = 'targetRoleId';
  static const String subject = 'subject';
}

/// Keys of the values an administration flow returns. A regenerated client secret is readable
/// only here. `emailSent` is `"false"` when a best-effort email step sent nothing.
abstract final class AdministrationFlowData {
  static const String clientSecret = 'clientSecret';
  static const String emailSent = 'emailSent';
}

/// Flow type of every administration flow.
const String administrationFlowType = 'ADMINISTRATION';

/// A flow definition as listed by the management API.
class ManagedFlow {
  final String id;
  final String handle;
  final String name;
  final String flowType;
  final int activeVersion;
  final bool isReadOnly;
  final String? createdAt;
  final String? updatedAt;

  const ManagedFlow({
    required this.id,
    required this.handle,
    required this.flowType,
    this.name = '',
    this.activeVersion = 0,
    this.isReadOnly = false,
    this.createdAt,
    this.updatedAt,
  });

  factory ManagedFlow.fromJson(Map<String, dynamic> json) => ManagedFlow(
        id: readString(json, 'id'),
        handle: readString(json, 'handle'),
        name: readString(json, 'name'),
        flowType: readString(json, 'flowType'),
        activeVersion: readInt(json, 'activeVersion'),
        isReadOnly: readOptionalBool(json, 'isReadOnly') ?? false,
        createdAt: readOptionalString(json, 'createdAt'),
        updatedAt: readOptionalString(json, 'updatedAt'),
      );
}

/// The result of an account lifecycle operation (suspend, unsuspend, unlock).
class AccountLifecycleResult {
  /// Whether the flow's email step sent its email: `false` when a best-effort step sent nothing,
  /// `null` when the flow has no email step.
  final bool? emailSent;

  const AccountLifecycleResult({this.emailSent});

  /// Reads [AdministrationFlowData.emailSent] from the values a flow produced.
  factory AccountLifecycleResult.fromFlowData(Map<String, String> data) => AccountLifecycleResult(
        emailSent: switch (data[AdministrationFlowData.emailSent]) { 'true' => true, 'false' => false, _ => null },
      );
}

/// An account lifecycle operation an operator can run. Locking is automatic only, so there is no
/// lock.
enum AccountLifecycleAction { suspend, unlock, unsuspend }

/// A kind of identity the account lifecycle operations act on, with the `flow` server-config key
/// that names the flow of each action it supports.
enum AccountLifecycleSubjectKind {
  agent({
    AccountLifecycleAction.suspend: AdministrationFlowConfigKey.agentSuspend,
    AccountLifecycleAction.unlock: AdministrationFlowConfigKey.agentUnlock,
    AccountLifecycleAction.unsuspend: AdministrationFlowConfigKey.agentUnsuspend,
  }),

  /// Applications are never locked, so they have no unlock.
  application({
    AccountLifecycleAction.suspend: AdministrationFlowConfigKey.applicationSuspend,
    AccountLifecycleAction.unsuspend: AdministrationFlowConfigKey.applicationUnsuspend,
  }),
  user({
    AccountLifecycleAction.suspend: AdministrationFlowConfigKey.userSuspend,
    AccountLifecycleAction.unlock: AdministrationFlowConfigKey.userUnlock,
    AccountLifecycleAction.unsuspend: AdministrationFlowConfigKey.userUnsuspend,
  });

  /// The [AdministrationFlowConfigKey] of the flow behind each action this kind supports.
  final Map<AccountLifecycleAction, String> flowConfigKeys;

  const AccountLifecycleSubjectKind(this.flowConfigKeys);
}
