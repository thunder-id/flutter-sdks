// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../../models/management/json_reader.dart';
import '../../models/management/management_page.dart';
import '../../models/management/variable.dart';
import 'management_collection.dart';
import 'management_transport.dart';
import 'thunderid_management_client.dart';

/// Server-level variable and secret operations: `/variables` and `/secrets`.
///
/// A secret's value is write-only: it is sent when set and never comes back, and nothing here
/// logs it.
///
/// URLs resolve like every other operation: the `url` passed to the call, the
/// [ManagementEndpointKeys.variables] or [ManagementEndpointKeys.secrets] override, then
/// `{baseUrl}/variables` or `{baseUrl}/secrets`.
extension VariableOperations on ThunderIDManagementClient {
  // ── Variables ──────────────────────────────────────────────────────────

  /// Lists the variables; [names] narrows the page to those names, and [filter] to a filter
  /// expression.
  Future<ManagementPage<Variable>> getVariables({
    List<String>? names,
    String? filter,
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagementPage.fromJson(
        await _variables(
          'getVariables',
          'Failed to fetch variables',
          query: {'names': names, 'filter': filter, 'limit': limit, 'offset': offset},
          url: url,
          fetcher: fetcher,
        ),
        'variables',
        (item) => Variable.fromJson(readMap(item)),
      );

  Future<Variable> getVariable(String name, {String? url, ManagementFetcher? fetcher}) async => Variable.fromJson(
        readMap(await _variables('getVariable', 'Failed to fetch variable', segments: [name], url: url, fetcher: fetcher)),
      );

  Future<Variable> createVariable(CreateVariableRequest payload, {String? url, ManagementFetcher? fetcher}) async =>
      Variable.fromJson(
        readMap(
          await _variables(
            'createVariable',
            'Failed to create variable',
            method: 'POST',
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  /// Sets [name]'s value, creating the variable when it does not exist.
  Future<Variable> updateVariable(
    String name,
    UpdateVariableRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      Variable.fromJson(
        readMap(
          await _variables(
            'updateVariable',
            'Failed to update variable',
            method: 'PUT',
            segments: [name],
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<void> deleteVariable(String name, {String? url, ManagementFetcher? fetcher}) => _variables(
        'deleteVariable',
        'Failed to delete variable',
        method: 'DELETE',
        segments: [name],
        url: url,
        fetcher: fetcher,
      );

  // ── Secrets ────────────────────────────────────────────────────────────

  /// Lists the secrets, without their values; [names] narrows the page to those names, and
  /// [filter] to a filter expression.
  Future<ManagementPage<Secret>> getSecrets({
    List<String>? names,
    String? filter,
    int? limit,
    int? offset,
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      ManagementPage.fromJson(
        await _secrets(
          'getSecrets',
          'Failed to fetch secrets',
          query: {'names': names, 'filter': filter, 'limit': limit, 'offset': offset},
          url: url,
          fetcher: fetcher,
        ),
        'secrets',
        (item) => Secret.fromJson(readMap(item)),
      );

  /// Reads a secret's description and whether it is set; never its value.
  Future<Secret> getSecret(String name, {String? url, ManagementFetcher? fetcher}) async => Secret.fromJson(
        readMap(await _secrets('getSecret', 'Failed to fetch secret', segments: [name], url: url, fetcher: fetcher)),
      );

  Future<Secret> createSecret(CreateSecretRequest payload, {String? url, ManagementFetcher? fetcher}) async =>
      Secret.fromJson(
        readMap(
          await _secrets(
            'createSecret',
            'Failed to create secret',
            method: 'POST',
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  /// Sets [name]'s value, creating the secret when it does not exist.
  Future<Secret> updateSecret(
    String name,
    UpdateSecretRequest payload, {
    String? url,
    ManagementFetcher? fetcher,
  }) async =>
      Secret.fromJson(
        readMap(
          await _secrets(
            'updateSecret',
            'Failed to update secret',
            method: 'PUT',
            segments: [name],
            body: payload.toJson(),
            url: url,
            fetcher: fetcher,
          ),
        ),
      );

  Future<void> deleteSecret(String name, {String? url, ManagementFetcher? fetcher}) => _secrets(
        'deleteSecret',
        'Failed to delete secret',
        method: 'DELETE',
        segments: [name],
        url: url,
        fetcher: fetcher,
      );

  Future<Object?> _variables(
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
        endpointKey: ManagementEndpointKeys.variables,
        collection: 'variables',
        method: method,
        segments: segments,
        query: query,
        body: body,
        url: url,
        fetcher: fetcher,
      );

  Future<Object?> _secrets(
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
        endpointKey: ManagementEndpointKeys.secrets,
        collection: 'secrets',
        method: method,
        segments: segments,
        query: query,
        body: body,
        url: url,
        fetcher: fetcher,
      );
}
