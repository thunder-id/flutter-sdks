// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../../models/management/json_reader.dart';
import '../../models/management/management_page.dart';
import '../../models/management/project.dart';
import 'management_collection.dart';
import 'management_transport.dart';
import 'thunderid_management_client.dart';

/// Project operations: `/projects`.
///
/// URLs resolve like every other operation: the `url` passed to the call, the
/// [ManagementEndpointKeys.projects] override, then `{baseUrl}/projects`.
extension ProjectOperations on ThunderIDManagementClient {
  Future<ManagementPage<Project>> getProjects({
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagementPage.fromJson(
        await _send(
          'getProjects',
          'Failed to fetch projects',
          query: {'limit': limit, 'offset': offset},
          url: url,
          fetcher: fetcher,
        ),
        'projects',
        (item) => Project.fromJson(readMap(item)),
      );

  Future<Project> getProject(String projectId, {String? url, ManagementFetcher? fetcher}) async => Project.fromJson(
        readMap(await _send('getProject', 'Failed to fetch project', segments: [projectId], url: url, fetcher: fetcher)),
      );

  Future<Project> createProject(CreateProjectRequest payload, {String? url, ManagementFetcher? fetcher}) async =>
      Project.fromJson(
        readMap(
          await _send(
            'createProject',
            'Failed to create project',
            method: 'POST',
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<Project> updateProject(
    String projectId,
    UpdateProjectRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      Project.fromJson(
        readMap(
          await _send(
            'updateProject',
            'Failed to update project',
            method: 'PUT',
            segments: [projectId],
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<void> deleteProject(String projectId, {String? url, ManagementFetcher? fetcher}) => _send(
        'deleteProject',
        'Failed to delete project',
        method: 'DELETE',
        segments: [projectId],
        url: url,
        fetcher: fetcher,
      );

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
        endpointKey: ManagementEndpointKeys.projects,
        collection: 'projects',
        method: method,
        segments: segments,
        query: query,
        body: body,
        url: url,
        fetcher: fetcher,
      );
}
