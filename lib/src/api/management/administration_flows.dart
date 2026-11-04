// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../../models/management/administration.dart';
import '../../models/management/json_reader.dart';
import '../../models/thunderid_error.dart';
import 'management_request.dart';
import 'management_transport.dart';
import 'thunderid_management_client.dart';

/// Page size used when walking the flow listing to find a handle. It matches the server's maximum
/// page size, so the usual handful of administration flows resolves in one request.
const int _flowPageSize = 100;

/// The generic administration flow operations behind `administrationMode: AdministrationMode.flow`.
///
/// The flows and their configuration live on the server at [ThunderIDManagementClient.baseUrl],
/// so these always call `{baseUrl}/server-config/flow`, `{baseUrl}/flows` and
/// `{baseUrl}/flow/execute`, whatever `url` or `endpoints` override the operation itself uses. A
/// client with an empty `baseUrl` cannot run a flow and raises
/// [ThunderIDErrorCode.invalidConfiguration] before anything is sent.
extension AdministrationFlowOperations on ThunderIDManagementClient {
  /// Reads the handle configured for each of [configKeys] (see [AdministrationFlowConfigKey]) in
  /// one request. A key with no handle is absent from the result.
  ///
  /// Read failures propagate: treating one as "no flow configured" would perform the operation
  /// through the API directly, which revokes nothing, and report it as a success.
  Future<Map<String, String>> resolveAdministrationFlowHandles(
    List<String> configKeys, {
    ManagementFetcher? fetcher,
  }) async {
    const operation = 'resolveAdministrationFlowHandles';
    final layers = readMap(
      await sendManagementRequest(
        fetcher: fetcher ?? this.fetcher,
        operation: operation,
        failureMessage: 'Failed to read the administration flow configuration',
        method: 'GET',
        url: _serverUrl(operation, 'server-config', id: 'flow'),
      ),
    );
    // The server returns the declarative, writable and merged layers; only the merged one applies.
    final section = readMap(layers['merged']);
    return {
      for (final key in configKeys)
        if (readOptionalString(readMap(section[key]), 'defaultHandle') case final handle? when handle.isNotEmpty)
          key: handle,
    };
  }

  /// Finds the administration flows carrying [handles], in one walk of the listing that stops
  /// once every handle is found. A handle with no flow is absent from the result.
  ///
  /// The listing is paged and newest first, which puts the bootstrap flows last, so pages are
  /// walked until the handles are found or the listing ends.
  Future<Map<String, ManagedFlow>> findAdministrationFlows(
    List<String> handles, {
    ManagementFetcher? fetcher,
  }) async {
    const operation = 'findAdministrationFlows';
    final wanted = handles.toSet();
    final found = <String, ManagedFlow>{};

    for (var offset = 0; wanted.isNotEmpty; offset += _flowPageSize) {
      // Sequential: a page is requested only when the previous one did not complete the set.
      final page = readMap(
        await sendManagementRequest(
          fetcher: fetcher ?? this.fetcher,
          operation: operation,
          failureMessage: 'Failed to list the administration flows',
          method: 'GET',
          url: _serverUrl(
            operation,
            'flows',
            query: {'flowType': administrationFlowType, 'limit': _flowPageSize, 'offset': offset},
          ),
        ),
      );
      final flows = readList(page, 'flows').map((item) => ManagedFlow.fromJson(readMap(item))).toList();

      for (final flow in flows) {
        if (wanted.contains(flow.handle) && flow.flowType == administrationFlowType) {
          found[flow.handle] = flow;
          wanted.remove(flow.handle);
        }
      }

      // A short page is the last one, so the handles still wanted do not exist.
      if (flows.length < _flowPageSize) break;
    }

    return found;
  }

  /// Resolves each of [configKeys] whose configured handle names an existing administration flow
  /// to that flow's identifier, in one configuration read and one listing walk. A key with no
  /// flow is absent.
  Future<Map<String, String>> resolveAdministrationFlows(
    List<String> configKeys, {
    ManagementFetcher? fetcher,
  }) async {
    final handles = await resolveAdministrationFlowHandles(configKeys, fetcher: fetcher);
    final flows = await findAdministrationFlows(handles.values.toList(), fetcher: fetcher);
    return {
      for (final entry in handles.entries)
        if (flows[entry.value] case final flow?) entry.key: flow.id,
    };
  }

  /// Finds the administration flow the server configures for [configKey], or returns `null` when
  /// none is configured so the caller calls the API directly. [action] names the operation in
  /// error messages, e.g. `user deletion`.
  ///
  /// Only an unset handle yields `null`: that is the deployment asking for the direct call. A
  /// handle that names a flow that no longer exists raises an [AdministrationFlowError]
  /// (`resolveAdministrationFlowId-NotFoundError-001`) instead, since falling back would make the
  /// change without the revocation the configuration asks for.
  Future<String?> resolveAdministrationFlowId(
    String configKey, {
    required String action,
    ManagementFetcher? fetcher,
  }) async {
    final handle = (await resolveAdministrationFlowHandles([configKey], fetcher: fetcher))[configKey];
    if (handle == null) return null;

    final flow = (await findAdministrationFlows([handle], fetcher: fetcher))[handle];
    if (flow == null) {
      throw AdministrationFlowError(
        'The configured $action flow "$handle" no longer exists, so the action was not performed. '
        'Restore the flow or clear the handle from the server configuration.',
        'resolveAdministrationFlowId-NotFoundError-001',
      );
    }
    return flow.id;
  }

  /// Runs the administration flow [flowId] to completion in one call and returns the values it
  /// produced (see [AdministrationFlowData]).
  ///
  /// Every input the flow needs is given up front in [inputs] (see [AdministrationFlowInput]), so
  /// it should finish without pausing. A flow that asks for more input, or a step that refuses,
  /// raises an [AdministrationFlowError].
  Future<Map<String, String>> executeAdministrationFlow(
    String flowId,
    Map<String, String> inputs, {
    required String action,
    ManagementFetcher? fetcher,
  }) async {
    const operation = 'executeAdministrationFlow';
    final result = readMap(
      await sendManagementRequest(
        fetcher: fetcher ?? this.fetcher,
        operation: operation,
        failureMessage: 'Failed to run the $action flow',
        method: 'POST',
        url: _serverUrl(operation, 'flow', id: 'execute'),
        body: {'flowId': flowId, 'inputs': inputs},
      ),
    );
    final status = readOptionalString(result, 'flowStatus');

    if (status == 'COMPLETE') {
      final data = readMap(readMap(result['data'])['additionalData']);
      return {
        for (final entry in data.entries)
          if (entry.value != null) entry.key: entry.value.toString(),
      };
    }

    if (status == 'INCOMPLETE') {
      throw AdministrationFlowError(
        'The $action flow requires additional input and could not be completed.',
        'executeAdministrationFlow-IncompleteError-001',
      );
    }

    final flowError = AdministrationFlowStepError.fromJson(result['error']);
    throw AdministrationFlowError(
      flowError.message?.defaultValue ?? flowError.description?.defaultValue ?? 'The $action flow did not complete.',
      flowError.code ?? 'executeAdministrationFlow-FlowError-001',
      flowError: flowError,
    );
  }

  /// Runs the administration flow the server configures for [configKey] and returns the values it
  /// produced, or returns `null` when none is configured so the caller calls the API directly.
  /// See [resolveAdministrationFlowId].
  Future<Map<String, String>?> runAdministrationFlow(
    String configKey,
    Map<String, String> inputs, {
    required String action,
    ManagementFetcher? fetcher,
  }) async {
    final flowId = await resolveAdministrationFlowId(configKey, action: action, fetcher: fetcher);
    return flowId == null ? null : executeAdministrationFlow(flowId, inputs, action: action, fetcher: fetcher);
  }

  /// A server-level URL under [ThunderIDManagementClient.baseUrl], never a collection override.
  Uri _serverUrl(String operation, String path, {String? id, Map<String, Object?> query = const {}}) {
    if (baseUrl.trim().isEmpty) {
      throw IAMException(
        ThunderIDErrorCode.invalidConfiguration,
        '$operation: a baseUrl is required to run an administration flow; a collection URL is not enough.',
      );
    }
    return buildManagementUrl(
      operation,
      '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/$path',
      id: id,
      query: query,
    );
  }
}
