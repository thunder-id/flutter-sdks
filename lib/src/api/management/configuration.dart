// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../../models/management/configuration.dart';
import '../../models/management/json_reader.dart';
import 'management_collection.dart';
import 'management_transport.dart';
import 'thunderid_management_client.dart';

/// Configuration versioning, export and import: `/configuration-versions`, `/export` and
/// `/import`.
///
/// Exported configuration and import variables can carry secrets; nothing here logs them.
///
/// URLs resolve like every other operation: the `url` passed to the call, the
/// [ManagementEndpointKeys.configurationVersions], [ManagementEndpointKeys.export] or
/// [ManagementEndpointKeys.import] override, then the path under `baseUrl`.
extension ConfigurationOperations on ThunderIDManagementClient {
  /// Lists the captured configuration versions, newest first.
  Future<List<ConfigurationVersion>> getConfigurationVersions({String? url, ManagementFetcher? fetcher}) async {
    final json = await _versions('getConfigurationVersions', 'Failed to fetch configuration versions', url, fetcher);
    return (json is List ? json : const <Object?>[])
        .map((item) => ConfigurationVersion.fromJson(readMap(item)))
        .toList(growable: false);
  }

  /// Reads one version; [version] is its number, its hash, or a prefix of the hash.
  Future<ConfigurationVersion> getConfigurationVersion(
    String version, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ConfigurationVersion.fromJson(
        readMap(
          await _versions(
            'getConfigurationVersion',
            'Failed to fetch configuration version',
            url,
            fetcher,
            segments: [version],
          ),
        ),
      );

  /// Captures the server's configuration as a new version. When nothing changed since the last
  /// version, that one is returned with `unchanged` set.
  Future<ConfigurationVersion> createConfigurationVersion(
    CreateConfigurationVersionRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ConfigurationVersion.fromJson(
        readMap(
          await _versions(
            'createConfigurationVersion',
            'Failed to create configuration version',
            url,
            fetcher,
            method: 'POST',
            body: payload.toJson(),
          ),
        ),
      );

  /// Exports the resources [payload] selects.
  Future<ConfigurationExport> exportConfiguration(
    ExportConfigurationRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ConfigurationExport.fromJson(
        readMap(
          await sendCollectionRequest(
            this,
            operation: 'exportConfiguration',
            failureMessage: 'Failed to export configuration',
            endpointKey: ManagementEndpointKeys.export,
            collection: 'export',
            method: 'POST',
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  /// Imports configuration, or with `dryRun` reports what an import would do.
  Future<ImportResult> importConfiguration(
    ImportConfigurationRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ImportResult.fromJson(
        readMap(
          await sendCollectionRequest(
            this,
            operation: 'importConfiguration',
            failureMessage: 'Failed to import configuration',
            endpointKey: ManagementEndpointKeys.import,
            collection: 'import',
            method: 'POST',
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  /// Deletes a resource that came from an imported file, and removes it from that file.
  Future<DeletedImportedConfiguration> deleteImportedConfiguration(
    DeleteImportedConfigurationRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      DeletedImportedConfiguration.fromJson(
        readMap(
          await sendCollectionRequest(
            this,
            operation: 'deleteImportedConfiguration',
            failureMessage: 'Failed to delete imported configuration',
            endpointKey: ManagementEndpointKeys.import,
            collection: 'import',
            method: 'POST',
            segments: const ['delete'],
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<Object?> _versions(
    String operation,
    String failureMessage,
    String? url,
    ManagementFetcher? fetcher, {
    String method = 'GET',
    List<String> segments = const [],
    Object? body,
  }) =>
      sendCollectionRequest(
        this,
        operation: operation,
        failureMessage: failureMessage,
        endpointKey: ManagementEndpointKeys.configurationVersions,
        collection: 'configuration-versions',
        method: method,
        segments: segments,
        body: body,
        url: url,
        fetcher: fetcher,
      );
}
