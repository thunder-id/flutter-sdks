// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../../models/management/administration.dart';
import '../../models/management/json_reader.dart';
import '../../models/management/management_page.dart';
import '../../models/management/resource_server.dart';
import 'administration_flows.dart';
import 'management_collection.dart';
import 'management_transport.dart';
import 'thunderid_management_client.dart';

/// Resource server operations: `/resource-servers`, their resources
/// (`/resource-servers/{id}/resources`), and their actions, which belong either to the server
/// itself (`/resource-servers/{id}/actions`) or, when a `resourceId` is given, to one resource
/// (`/resource-servers/{id}/resources/{resourceId}/actions`).
///
/// URLs resolve like every other operation: the `url` passed to the call, the
/// [ManagementEndpointKeys.resourceServers] override, then `{baseUrl}/resource-servers`.
extension ResourceServerOperations on ThunderIDManagementClient {
  // ── Resource servers ───────────────────────────────────────────────────

  Future<ManagementPage<ResourceServer>> getResourceServers({
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagementPage.fromJson(
        await _send(
          'getResourceServers',
          'Failed to fetch resource servers',
          query: {'limit': limit, 'offset': offset},
          url: url,
          fetcher: fetcher,
        ),
        'resourceServers',
        (item) => ResourceServer.fromJson(readMap(item)),
      );

  Future<ResourceServer> getResourceServer(String resourceServerId, {String? url, ManagementFetcher? fetcher}) async =>
      ResourceServer.fromJson(
        readMap(
          await _send(
            'getResourceServer',
            'Failed to fetch resource server',
            segments: [resourceServerId],
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<ResourceServer> createResourceServer(
    CreateResourceServerRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ResourceServer.fromJson(
        readMap(
          await _send(
            'createResourceServer',
            'Failed to create resource server',
            method: 'POST',
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<ResourceServer> updateResourceServer(
    String resourceServerId,
    UpdateResourceServerRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ResourceServer.fromJson(
        readMap(
          await _send(
            'updateResourceServer',
            'Failed to update resource server',
            method: 'PUT',
            segments: [resourceServerId],
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<void> deleteResourceServer(String resourceServerId, {String? url, ManagementFetcher? fetcher}) => _send(
        'deleteResourceServer',
        'Failed to delete resource server',
        method: 'DELETE',
        segments: [resourceServerId],
        url: url,
        fetcher: fetcher,
      );

  // ── Resources ──────────────────────────────────────────────────────────

  /// Lists [resourceServerId]'s resources; [parentId] narrows the page to one resource's children.
  Future<ManagementPage<ManagedResource>> getResources(
    String resourceServerId, {
    String? parentId,
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagementPage.fromJson(
        await _send(
          'getResources',
          'Failed to fetch resources',
          segments: [resourceServerId, 'resources'],
          query: {'parentId': parentId, 'limit': limit, 'offset': offset},
          url: url,
          fetcher: fetcher,
        ),
        'resources',
        (item) => ManagedResource.fromJson(readMap(item)),
      );

  Future<ManagedResource> getResource(
    String resourceServerId,
    String resourceId, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagedResource.fromJson(
        readMap(
          await _send(
            'getResource',
            'Failed to fetch resource',
            segments: [resourceServerId, 'resources', resourceId],
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<ManagedResource> createResource(
    String resourceServerId,
    CreateResourceRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagedResource.fromJson(
        readMap(
          await _send(
            'createResource',
            'Failed to create resource',
            method: 'POST',
            segments: [resourceServerId, 'resources'],
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<ManagedResource> updateResource(
    String resourceServerId,
    String resourceId,
    UpdateResourceRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagedResource.fromJson(
        readMap(
          await _send(
            'updateResource',
            'Failed to update resource',
            method: 'PUT',
            segments: [resourceServerId, 'resources', resourceId],
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<void> deleteResource(
    String resourceServerId,
    String resourceId, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _send(
        'deleteResource',
        'Failed to delete resource',
        method: 'DELETE',
        segments: [resourceServerId, 'resources', resourceId],
        url: url,
        fetcher: fetcher,
      );

  // ── Actions ────────────────────────────────────────────────────────────

  /// Lists the actions of [resourceServerId], or of its resource [resourceId] when given.
  /// [kind] narrows the page to one [ResourceActionKinds] value.
  Future<ManagementPage<ResourceAction>> getActions(
    String resourceServerId, {
    String? resourceId,
    String? kind,
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagementPage.fromJson(
        await _send(
          'getActions',
          'Failed to fetch actions',
          segments: _actionSegments(resourceServerId, resourceId),
          query: {'kind': kind, 'limit': limit, 'offset': offset},
          url: url,
          fetcher: fetcher,
        ),
        'actions',
        (item) => ResourceAction.fromJson(readMap(item)),
      );

  Future<ResourceAction> getAction(
    String resourceServerId,
    String actionId, {
    String? resourceId,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ResourceAction.fromJson(
        readMap(
          await _send(
            'getAction',
            'Failed to fetch action',
            segments: [..._actionSegments(resourceServerId, resourceId), actionId],
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<ResourceAction> createAction(
    String resourceServerId,
    CreateActionRequest payload, {
    String? resourceId,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ResourceAction.fromJson(
        readMap(
          await _send(
            'createAction',
            'Failed to create action',
            method: 'POST',
            segments: _actionSegments(resourceServerId, resourceId),
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<ResourceAction> updateAction(
    String resourceServerId,
    String actionId,
    UpdateActionRequest payload, {
    String? resourceId,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ResourceAction.fromJson(
        readMap(
          await _send(
            'updateAction',
            'Failed to update action',
            method: 'PUT',
            segments: [..._actionSegments(resourceServerId, resourceId), actionId],
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  /// Deletes an action of [resourceServerId], or of its resource [resourceId] when given.
  ///
  /// In [AdministrationMode.flow] the configured action deletion flow runs instead, revoking
  /// the permission the action granted before it goes; when no flow is configured, the action is
  /// deleted directly.
  Future<void> deleteAction(
    String resourceServerId,
    String actionId, {
    String? resourceId,
    AdministrationMode administrationMode = AdministrationMode.native,
    String? url,
    ManagementFetcher? fetcher,
  }) async {
    if (administrationMode == AdministrationMode.flow &&
        await runAdministrationFlow(
              AdministrationFlowConfigKey.actionDeletion,
              {
                AdministrationFlowInput.action: actionId,
                AdministrationFlowInput.resourceServer: resourceServerId,
                if (resourceId != null) AdministrationFlowInput.resource: resourceId,
              },
              action: 'action deletion',
              fetcher: fetcher,
            ) !=
            null) {
      return;
    }
    await _send(
      'deleteAction',
      'Failed to delete action',
      method: 'DELETE',
      segments: [..._actionSegments(resourceServerId, resourceId), actionId],
      url: url,
      fetcher: fetcher,
    );
  }

  static List<String> _actionSegments(String resourceServerId, String? resourceId) => [
        resourceServerId,
        if (resourceId != null) ...['resources', resourceId],
        'actions',
      ];

  Future<Object?> _send(
    String operation,
    String failureMessage, {
    String method = 'GET',
    List<String> segments = const [],
    Map<String, Object?> query = const {},
    Object? body,
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      sendCollectionRequest(
        this,
        operation: operation,
        failureMessage: failureMessage,
        endpointKey: ManagementEndpointKeys.resourceServers,
        collection: 'resource-servers',
        method: method,
        segments: segments,
        query: query,
        body: body,
        url: url,
        fetcher: fetcher,
      );
}
