// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../models/management/access_status.dart';
import '../models/management/administration.dart';
import '../models/thunderid_error.dart';
import 'administration_flows.dart';
import 'management_transport.dart';
import 'thunderid_management_client.dart';

/// Account lifecycle operations: suspending, unsuspending and unlocking users, agents and
/// applications.
///
/// These exist only as administration flows: each runs the flow the server configures for it
/// (see [AdministrationFlowConfigKey]) with the account as `subject` and the optional
/// `operatorNote`, through [AdministrationFlowOperations.runAdministrationFlow]. There is no
/// management endpoint to fall back on, so when no flow is configured the operation raises an
/// [AdministrationFlowError] whose `flowCode` is `{operation}-NotConfiguredError-001` (for
/// example `suspendUser-NotConfiguredError-001`) and nothing changes. Like every administration
/// flow, they read the server at [ThunderIDManagementClient.baseUrl].
extension AccountLifecycleOperations on ThunderIDManagementClient {
  /// Runs [action] against the [kind] of identity [subject], through the operation for that kind
  /// and action (for example [suspendUser]). Each raises its own errors, so a missing flow fails
  /// with that operation's `NotConfiguredError`. An action that does not apply to the kind, such
  /// as unlocking an application, raises [ThunderIDErrorCode.invalidInput] before anything is sent.
  Future<AccountLifecycleResult> runAccountLifecycleAction(
    AccountLifecycleSubjectKind kind,
    AccountLifecycleAction action,
    String subject, {
    String? operatorNote,
    ManagementFetcher? fetcher,
  }) =>
      switch ((kind, action)) {
        (AccountLifecycleSubjectKind.user, AccountLifecycleAction.suspend) =>
          suspendUser(subject, operatorNote: operatorNote, fetcher: fetcher),
        (AccountLifecycleSubjectKind.user, AccountLifecycleAction.unsuspend) =>
          unsuspendUser(subject, operatorNote: operatorNote, fetcher: fetcher),
        (AccountLifecycleSubjectKind.user, AccountLifecycleAction.unlock) =>
          unlockUser(subject, operatorNote: operatorNote, fetcher: fetcher),
        (AccountLifecycleSubjectKind.agent, AccountLifecycleAction.suspend) =>
          suspendAgent(subject, operatorNote: operatorNote, fetcher: fetcher),
        (AccountLifecycleSubjectKind.agent, AccountLifecycleAction.unsuspend) =>
          unsuspendAgent(subject, operatorNote: operatorNote, fetcher: fetcher),
        (AccountLifecycleSubjectKind.agent, AccountLifecycleAction.unlock) =>
          unlockAgent(subject, operatorNote: operatorNote, fetcher: fetcher),
        (AccountLifecycleSubjectKind.application, AccountLifecycleAction.suspend) =>
          suspendApplication(subject, operatorNote: operatorNote, fetcher: fetcher),
        (AccountLifecycleSubjectKind.application, AccountLifecycleAction.unsuspend) =>
          unsuspendApplication(subject, operatorNote: operatorNote, fetcher: fetcher),
        (AccountLifecycleSubjectKind.application, AccountLifecycleAction.unlock) => Future.error(
            const IAMException(
              ThunderIDErrorCode.invalidInput,
              'runAccountLifecycleAction: the unlock action does not apply to applications, which are never locked.',
            ),
          ),
      };

  /// Suspends [userId]: they cannot sign in until unsuspended.
  Future<AccountLifecycleResult> suspendUser(String userId, {String? operatorNote, ManagementFetcher? fetcher}) =>
      _run('suspendUser', AdministrationFlowConfigKey.userSuspend, 'user suspension', userId, operatorNote, fetcher);

  Future<AccountLifecycleResult> unsuspendUser(String userId, {String? operatorNote, ManagementFetcher? fetcher}) =>
      _run('unsuspendUser', AdministrationFlowConfigKey.userUnsuspend, 'user unsuspension', userId, operatorNote, fetcher);

  /// Lifts the lock that failed sign-in attempts put on [userId].
  Future<AccountLifecycleResult> unlockUser(String userId, {String? operatorNote, ManagementFetcher? fetcher}) =>
      _run('unlockUser', AdministrationFlowConfigKey.userUnlock, 'user unlock', userId, operatorNote, fetcher);

  Future<AccountLifecycleResult> suspendAgent(String agentId, {String? operatorNote, ManagementFetcher? fetcher}) =>
      _run('suspendAgent', AdministrationFlowConfigKey.agentSuspend, 'agent suspension', agentId, operatorNote, fetcher);

  Future<AccountLifecycleResult> unsuspendAgent(String agentId, {String? operatorNote, ManagementFetcher? fetcher}) =>
      _run(
        'unsuspendAgent',
        AdministrationFlowConfigKey.agentUnsuspend,
        'agent unsuspension',
        agentId,
        operatorNote,
        fetcher,
      );

  Future<AccountLifecycleResult> unlockAgent(String agentId, {String? operatorNote, ManagementFetcher? fetcher}) =>
      _run('unlockAgent', AdministrationFlowConfigKey.agentUnlock, 'agent unlock', agentId, operatorNote, fetcher);

  Future<AccountLifecycleResult> suspendApplication(
    String applicationId, {
    String? operatorNote,
    ManagementFetcher? fetcher,
  }) =>
      _run(
        'suspendApplication',
        AdministrationFlowConfigKey.applicationSuspend,
        'application suspension',
        applicationId,
        operatorNote,
        fetcher,
      );

  Future<AccountLifecycleResult> unsuspendApplication(
    String applicationId, {
    String? operatorNote,
    ManagementFetcher? fetcher,
  }) =>
      _run(
        'unsuspendApplication',
        AdministrationFlowConfigKey.applicationUnsuspend,
        'application unsuspension',
        applicationId,
        operatorNote,
        fetcher,
      );

  Future<AccountLifecycleResult> _run(
    String operation,
    String configKey,
    String action,
    String subject,
    String? operatorNote,
    ManagementFetcher? fetcher,
  ) async {
    if (subject.trim().isEmpty) {
      throw IAMException(ThunderIDErrorCode.invalidInput, '$operation: a resource identifier is required.');
    }
    final data = await runAdministrationFlow(
      configKey,
      {
        AdministrationFlowInput.subject: subject,
        if (operatorNote != null && operatorNote.isNotEmpty) AdministrationFlowInput.operatorNote: operatorNote,
      },
      action: action,
      fetcher: fetcher,
    );
    if (data == null) {
      throw AdministrationFlowError(
        'No $action flow is configured, and there is no direct API for it, so nothing was changed. '
        'Configure the "$configKey" handle in the server configuration.',
        '$operation-NotConfiguredError-001',
      );
    }
    return AccountLifecycleResult.fromFlowData(data);
  }
}

/// The actions each status offers, most expected first. A suspended identity offers no unlock,
/// since a read does not show a lock beneath the suspension: once unsuspended, a remaining lock
/// shows as [AccessStatusValue.locked].
const Map<String, List<AccountLifecycleAction>> _actionsByStatus = {
  AccessStatusValue.active: [AccountLifecycleAction.suspend],
  AccessStatusValue.locked: [AccountLifecycleAction.unlock, AccountLifecycleAction.suspend],
  AccessStatusValue.suspended: [AccountLifecycleAction.unsuspend],
};

/// The account lifecycle actions to offer for an identity: those its [status] allows, that apply
/// to its [kind], and whose administration flow is configured. These actions run only through
/// their flows, so one with no flow is never offered.
///
/// [status] is the identity's [AccessStatus.value]; an identity with none reads as
/// [AccessStatusValue.active], and a status this SDK does not know offers nothing.
/// [configuredFlows] are the flows the server configures, keyed by `flow` server-config key, as
/// [AdministrationFlowOperations.resolveAdministrationFlows] returns them for
/// `kind.flowConfigKeys.values`. Returns the actions most expected first.
List<AccountLifecycleAction> getAccountLifecycleActions(
  AccountLifecycleSubjectKind kind,
  String? status,
  Map<String, String> configuredFlows,
) =>
    [
      for (final action in _actionsByStatus[status ?? AccessStatusValue.active] ?? const <AccountLifecycleAction>[])
        if (kind.flowConfigKeys[action] case final configKey? when (configuredFlows[configKey] ?? '').isNotEmpty)
          action,
    ];
