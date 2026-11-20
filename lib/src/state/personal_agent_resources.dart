// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../models/management/agent.dart';
import '../models/management/management_page.dart';
import '../models/personal_agent.dart';
import '../thunderid_client.dart';
import 'management_resources.dart';
import 'resource_notifiers.dart';

/// Variables of [PersonalAgentResources.updateMeAgentMutation].
typedef UpdateMeAgentVariables = ({String agentId, UpdateMeAgentRequest data});

/// Variables of [PersonalAgentResources.meAgentSuspensionMutation].
typedef MeAgentSuspensionVariables = ({String agentId, MeAgentSuspensionAction action});

/// Queries and mutations over the signed-in user's own agents (`/users/me/agents`). These are the
/// user's own requests, so they take no fetcher: they go through [ThunderIDClient] like the other
/// `/users/me` operations.
///
/// They share the provider's [invalidator] with [ManagementResources], so a write reloads every live
/// read it affects. Callers own what they create and must dispose it. Obtain the provider's
/// instance from `ThunderIDProvider.of(context).personalAgentResources`.
class PersonalAgentResources {
  final ThunderIDClient client;
  final ResourceInvalidator invalidator;

  PersonalAgentResources(this.client, {ResourceInvalidator? invalidator})
      : invalidator = invalidator ?? ResourceInvalidator();

  ResourceQuery<ManagementPage<Agent>> meAgentsQuery({String? kind, int? limit, int? offset, bool enabled = true}) =>
      ResourceQuery(
        () => client.getMeAgents(kind: kind, limit: limit, offset: offset),
        key: [
          ManagementQueryKeys.meAgents,
          {'kind': kind, 'limit': limit, 'offset': offset},
        ],
        invalidator: invalidator,
        enabled: enabled,
      );

  ResourceQuery<Agent> meAgentQuery(String? agentId, {bool enabled = true}) => ResourceQuery(
        () => client.getMeAgent(agentId!),
        key: [ManagementQueryKeys.meAgent, agentId],
        invalidator: invalidator,
        enabled: enabled && agentId != null,
      );

  ResourceMutation<UpdateMeAgentVariables, Agent> updateMeAgentMutation({
    void Function(Agent data, UpdateMeAgentVariables variables)? onSuccess,
    void Function(Object error, UpdateMeAgentVariables variables)? onError,
  }) =>
      ResourceMutation(
        (variables) => client.updateMeAgent(variables.agentId, variables.data),
        invalidates: (variables) => _changed(variables.agentId),
        invalidator: invalidator,
        onSuccess: onSuccess,
        onError: onError,
      );

  ResourceMutation<String, void> deleteMeAgentMutation({
    void Function(void data, String agentId)? onSuccess,
    void Function(Object error, String agentId)? onError,
  }) =>
      ResourceMutation(
        client.deleteMeAgent,
        invalidates: _changed,
        invalidator: invalidator,
        onSuccess: onSuccess,
        onError: onError,
      );

  /// Places or lifts the signed-in user's own suspension of one of their agents.
  ResourceMutation<MeAgentSuspensionVariables, void> meAgentSuspensionMutation({
    void Function(void data, MeAgentSuspensionVariables variables)? onSuccess,
    void Function(Object error, MeAgentSuspensionVariables variables)? onError,
  }) =>
      ResourceMutation(
        (variables) => switch (variables.action) {
          MeAgentSuspensionAction.suspend => client.suspendMeAgent(variables.agentId),
          MeAgentSuspensionAction.unsuspend => client.unsuspendMeAgent(variables.agentId),
        },
        invalidates: (variables) => _changed(variables.agentId),
        invalidator: invalidator,
        onSuccess: onSuccess,
        onError: onError,
      );

  /// Places the signed-in user's own suspension on every agent they own.
  ResourceMutation<void, SuspendAllMeAgentsResponse> suspendAllMeAgentsMutation({
    void Function(SuspendAllMeAgentsResponse data, void variables)? onSuccess,
    void Function(Object error, void variables)? onError,
  }) =>
      ResourceMutation(
        (_) => client.suspendAllMeAgents(),
        invalidates: (_) => [
          [ManagementQueryKeys.meAgent],
          [ManagementQueryKeys.meAgents],
          [ManagementQueryKeys.agent],
          [ManagementQueryKeys.agents],
        ],
        invalidator: invalidator,
        onSuccess: onSuccess,
        onError: onError,
      );

  /// The queries a change to the agent [agentId] makes stale: the owner's view of it and of their
  /// agents, and the admin views of it and of every agent list.
  static List<ResourceQueryKey> _changed(String agentId) => [
        [ManagementQueryKeys.meAgent, agentId],
        [ManagementQueryKeys.meAgents],
        [ManagementQueryKeys.agent, agentId],
        [ManagementQueryKeys.agents],
      ];
}
