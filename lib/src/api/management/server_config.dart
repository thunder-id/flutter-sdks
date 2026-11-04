// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../../models/management/json_reader.dart';
import '../../models/management/server_config.dart';
import 'management_collection.dart';
import 'management_transport.dart';
import 'thunderid_management_client.dart';

/// Server configuration operations: `/server-config` and its named sections, such as `flow`.
///
/// URLs resolve like every other operation: the `url` passed to the call, the
/// [ManagementEndpointKeys.serverConfig] override, then `{baseUrl}/server-config`. The
/// administration flow lookups always read `{baseUrl}/server-config/flow`.
extension ServerConfigOperations on ThunderIDManagementClient {
  /// Lists the names of the configuration sections.
  Future<List<String>> getServerConfigs({String? url, ManagementFetcher? fetcher}) async {
    final json = await _send('getServerConfigs', 'Failed to fetch server configuration', url: url, fetcher: fetcher);
    return (json is List ? json : const <Object?>[]).whereType<String>().toList(growable: false);
  }

  Future<ServerConfigLayers> getServerConfig(String name, {String? url, ManagementFetcher? fetcher}) async =>
      ServerConfigLayers.fromJson(
        readMap(
          await _send(
            'getServerConfig',
            'Failed to fetch server configuration',
            segments: [name],
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  /// Writes the API-set values of the section [name]. [payload] has the section's own shape.
  Future<ServerConfigLayers> updateServerConfig(
    String name,
    Map<String, dynamic> payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ServerConfigLayers.fromJson(
        readMap(
          await _send(
            'updateServerConfig',
            'Failed to update server configuration',
            method: 'PUT',
            segments: [name],
            body: payload,
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<Object?> _send(
    String operation,
    String failureMessage, {
    String method = 'GET',
    List<String> segments = const [],
    Object? body,
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      sendCollectionRequest(
        this,
        operation: operation,
        failureMessage: failureMessage,
        endpointKey: ManagementEndpointKeys.serverConfig,
        collection: 'server-config',
        method: method,
        segments: segments,
        body: body,
        url: url,
        fetcher: fetcher,
      );
}
