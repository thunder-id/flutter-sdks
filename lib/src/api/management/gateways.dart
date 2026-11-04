// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../../models/management/gateway.dart';
import '../../models/management/json_reader.dart';
import '../../models/management/management_page.dart';
import '../../models/management/variable.dart';
import 'management_collection.dart';
import 'management_transport.dart';
import 'thunderid_management_client.dart';

/// Gateway operations: `/gateways`, applying configuration versions to a gateway, what a gateway
/// holds resource by resource (its master, `/gateways/{id}/master`), and the variables and
/// secrets a gateway holds (`/gateways/{id}/variables`, `/gateways/{id}/secrets`), which the
/// server passes through to the gateway and answers in the variable store's shapes.
///
/// A gateway's key and its secrets' values are write-only; nothing here logs them.
///
/// URLs resolve like every other operation: the `url` passed to the call, the
/// [ManagementEndpointKeys.gateways] override, then `{baseUrl}/gateways`.
extension GatewayOperations on ThunderIDManagementClient {
  // ── Gateways ───────────────────────────────────────────────────────────

  /// Lists the registered gateways. The server does not page this list.
  Future<List<Gateway>> getGateways({String? url, ManagementFetcher? fetcher}) async {
    final json = await _send('getGateways', 'Failed to fetch gateways', url: url, fetcher: fetcher);
    return (json is List ? json : const <Object?>[]).map((item) => Gateway.fromJson(readMap(item))).toList(growable: false);
  }

  Future<Gateway> getGateway(String gatewayId, {String? url, ManagementFetcher? fetcher}) async => Gateway.fromJson(
        readMap(await _send('getGateway', 'Failed to fetch gateway', segments: [gatewayId], url: url, fetcher: fetcher)),
      );

  /// Registers a gateway. The result carries the gateway's key, readable only now.
  Future<GatewayRegistration> createGateway(
    RegisterGatewayRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      GatewayRegistration.fromJson(
        readMap(
          await _send(
            'createGateway',
            'Failed to register gateway',
            method: 'POST',
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<Gateway> updateGateway(
    String gatewayId,
    UpdateGatewayRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      Gateway.fromJson(
        readMap(
          await _send(
            'updateGateway',
            'Failed to update gateway',
            method: 'PUT',
            segments: [gatewayId],
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<void> deleteGateway(String gatewayId, {String? url, ManagementFetcher? fetcher}) => _send(
        'deleteGateway',
        'Failed to delete gateway',
        method: 'DELETE',
        segments: [gatewayId],
        url: url,
        fetcher: fetcher,
      );

  // ── Configuration ──────────────────────────────────────────────────────

  /// Applies a configuration version to [gatewayId]: the current one, or the one [payload]
  /// names. With `dryRun` it only reports what would change.
  Future<GatewayApplyResult> applyGatewayConfiguration(
    String gatewayId, {
    ApplyGatewayConfigurationRequest? payload,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      GatewayApplyResult.fromJson(
        readMap(
          await _send(
            'applyGatewayConfiguration',
            'Failed to apply the gateway configuration',
            method: 'POST',
            segments: [gatewayId, 'apply'],
            body: payload?.toJson() ?? const <String, dynamic>{},
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  /// Puts [gatewayId] back on the version it held before the last apply.
  Future<GatewayApplyResult> revertGatewayConfiguration(
    String gatewayId, {
    RevertGatewayConfigurationRequest? payload,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      GatewayApplyResult.fromJson(
        readMap(
          await _send(
            'revertGatewayConfiguration',
            'Failed to revert the gateway configuration',
            method: 'POST',
            segments: [gatewayId, 'revert'],
            body: payload?.toJson() ?? const <String, dynamic>{},
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  /// Compares what [gatewayId] holds with [version] (its hash, a prefix of at least seven
  /// characters, or `latest`, the default).
  Future<GatewayConfigurationDiff> getGatewayConfigurationDiff(
    String gatewayId, {
    String? version,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      GatewayConfigurationDiff.fromJson(
        readMap(
          await _send(
            'getGatewayConfigurationDiff',
            'Failed to compare the gateway configuration',
            segments: [gatewayId, 'diff'],
            query: {'version': version},
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<GatewayAppliedConfiguration> getGatewayAppliedConfiguration(
    String gatewayId, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      GatewayAppliedConfiguration.fromJson(
        readMap(
          await _send(
            'getGatewayAppliedConfiguration',
            'Failed to fetch the gateway configuration',
            segments: [gatewayId, 'applied-configuration'],
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<GatewayAppliedVersion> getGatewayAppliedVersion(
    String gatewayId, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      GatewayAppliedVersion.fromJson(
        readMap(
          await _send(
            'getGatewayAppliedVersion',
            'Failed to fetch the gateway version',
            segments: [gatewayId, 'applied-version'],
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  // ── Master ─────────────────────────────────────────────────────────────

  /// Reads [gatewayId]'s latest master: every resource deployed to it, as the gateway last
  /// accepted it. A gateway nothing was applied to returns the empty master (`number` 0).
  Future<GatewayMaster> getGatewayMaster(String gatewayId, {String? url, ManagementFetcher? fetcher}) async =>
      GatewayMaster.fromJson(
        readMap(
          await _send(
            'getGatewayMaster',
            'Failed to fetch the gateway master',
            segments: [gatewayId, 'master'],
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  /// Lists the masters kept for [gatewayId], newest first, each with its summary but without its
  /// entries or resources. The server does not page this list.
  Future<List<GatewayMaster>> getGatewayMasterHistory(
    String gatewayId, {
    String? url,
    ManagementFetcher? fetcher,
  }) async {
    final json = await _send(
      'getGatewayMasterHistory',
      'Failed to fetch the gateway master history',
      segments: [gatewayId, 'master', 'history'],
      url: url,
      fetcher: fetcher,
    );
    return (json is List ? json : const <Object?>[])
        .map((item) => GatewayMaster.fromJson(readMap(item)))
        .toList(growable: false);
  }

  /// Reads one resource's entry in each kept master of [gatewayId] that records it, newest
  /// first. [resourceType] and [resourceId] are the two halves of a master entry's `key`.
  Future<GatewayResourceHistory> getGatewayMasterResource(
    String gatewayId,
    String resourceType,
    String resourceId, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      GatewayResourceHistory.fromJson(
        readMap(
          await _send(
            'getGatewayMasterResource',
            'Failed to fetch the gateway resource history',
            segments: [gatewayId, 'master', 'resources', resourceType, resourceId],
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  // ── Gateway variables ──────────────────────────────────────────────────

  Future<ManagementPage<Variable>> getGatewayVariables(
    String gatewayId, {
    List<String>? names,
    String? filter,
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagementPage.fromJson(
        await _send(
          'getGatewayVariables',
          'Failed to fetch gateway variables',
          segments: [gatewayId, 'variables'],
          query: {'names': names, 'filter': filter, 'limit': limit, 'offset': offset},
          url: url,
          fetcher: fetcher,
        ),
        'variables',
        (item) => Variable.fromJson(readMap(item)),
      );

  Future<Variable> getGatewayVariable(
    String gatewayId,
    String name, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      Variable.fromJson(
        readMap(
          await _send(
            'getGatewayVariable',
            'Failed to fetch gateway variable',
            segments: [gatewayId, 'variables', name],
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<Variable> createGatewayVariable(
    String gatewayId,
    CreateVariableRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      Variable.fromJson(
        readMap(
          await _send(
            'createGatewayVariable',
            'Failed to create gateway variable',
            method: 'POST',
            segments: [gatewayId, 'variables'],
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  /// Sets [name]'s value on [gatewayId], creating the variable when it does not exist.
  Future<Variable> updateGatewayVariable(
    String gatewayId,
    String name,
    UpdateVariableRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      Variable.fromJson(
        readMap(
          await _send(
            'updateGatewayVariable',
            'Failed to update gateway variable',
            method: 'PUT',
            segments: [gatewayId, 'variables', name],
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<void> deleteGatewayVariable(
    String gatewayId,
    String name, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _send(
        'deleteGatewayVariable',
        'Failed to delete gateway variable',
        method: 'DELETE',
        segments: [gatewayId, 'variables', name],
        url: url,
        fetcher: fetcher,
      );

  // ── Gateway secrets ────────────────────────────────────────────────────

  Future<ManagementPage<Secret>> getGatewaySecrets(
    String gatewayId, {
    List<String>? names,
    String? filter,
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagementPage.fromJson(
        await _send(
          'getGatewaySecrets',
          'Failed to fetch gateway secrets',
          segments: [gatewayId, 'secrets'],
          query: {'names': names, 'filter': filter, 'limit': limit, 'offset': offset},
          url: url,
          fetcher: fetcher,
        ),
        'secrets',
        (item) => Secret.fromJson(readMap(item)),
      );

  Future<Secret> getGatewaySecret(
    String gatewayId,
    String name, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      Secret.fromJson(
        readMap(
          await _send(
            'getGatewaySecret',
            'Failed to fetch gateway secret',
            segments: [gatewayId, 'secrets', name],
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<Secret> createGatewaySecret(
    String gatewayId,
    CreateSecretRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      Secret.fromJson(
        readMap(
          await _send(
            'createGatewaySecret',
            'Failed to create gateway secret',
            method: 'POST',
            segments: [gatewayId, 'secrets'],
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  /// Sets [name]'s value on [gatewayId], creating the secret when it does not exist.
  Future<Secret> updateGatewaySecret(
    String gatewayId,
    String name,
    UpdateSecretRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      Secret.fromJson(
        readMap(
          await _send(
            'updateGatewaySecret',
            'Failed to update gateway secret',
            method: 'PUT',
            segments: [gatewayId, 'secrets', name],
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<void> deleteGatewaySecret(
    String gatewayId,
    String name, {
    String? url,
    ManagementFetcher? fetcher,
  }) =>
      _send(
        'deleteGatewaySecret',
        'Failed to delete gateway secret',
        method: 'DELETE',
        segments: [gatewayId, 'secrets', name],
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
        endpointKey: ManagementEndpointKeys.gateways,
        collection: 'gateways',
        method: method,
        segments: segments,
        query: query,
        body: body,
        url: url,
        fetcher: fetcher,
      );
}
