// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import '../../models/flow_models.dart';
import '../../models/management/json_reader.dart';
import '../../models/thunderid_error.dart';
import '../management/management_request.dart';
import '../management/management_transport.dart';

// Package-internal: the user side of device authorization, behind `ThunderIDClient.verifyDeviceCode`.

/// The flow type of the server's device authorization flow.
const String deviceGrantFlowType = 'DEVICE_GRANT';

const _operation = 'verifyDeviceCode';

/// Runs one step of the application's `DEVICE_GRANT` flow at `{baseUrl}/flow/execute`, so a user
/// approves a device by the code it shows.
///
/// Without [executionId] the flow starts, for [applicationId], with [userCode] as its `user_code`
/// input when given. With one, the flow continues with [actionId] and [inputs]. When the flow ends
/// (completed or refused), its assertion is relayed to `{baseUrl}/oauth2/auth/callback`, which
/// approves or denies the waiting device; a refused flow is returned as a [FlowStatus.error]
/// response, so the app can show the flow's own failure message.
Future<EmbeddedFlowResponse> executeDeviceGrantFlow({
  required String baseUrl,
  required ManagementFetcher fetcher,
  String? applicationId,
  String? userCode,
  String? executionId,
  String? actionId,
  Map<String, String> inputs = const {},
  String? challengeToken,
}) async {
  final isContinuation = executionId != null && executionId.isNotEmpty;
  if (!isContinuation && (applicationId == null || applicationId.trim().isEmpty)) {
    throw const IAMException(
      ThunderIDErrorCode.invalidInput,
      '$_operation: an applicationId is required to start the device authorization flow.',
    );
  }
  final root = baseUrl.replaceFirst(RegExp(r'/+$'), '');
  final body = isContinuation
      ? <String, Object?>{
          'executionId': executionId,
          if (actionId != null && actionId.isNotEmpty) 'action': actionId,
          'inputs': inputs,
          if (challengeToken != null && challengeToken.isNotEmpty) 'challengeToken': challengeToken,
        }
      : <String, Object?>{
          'applicationId': applicationId,
          'flowType': deviceGrantFlowType,
          'inputs': {
            ...inputs,
            if (userCode != null && userCode.trim().isNotEmpty) 'user_code': userCode.trim(),
          },
          // The SDK asks for component metadata when a flow starts, as the other embedded flows do.
          'verbose': true,
        };

  final response = await _post(fetcher, buildManagementUrl(_operation, '$root/flow', segments: const ['execute']), body);
  final json = _decode(response.body);

  if (!response.ok) {
    // A flow refused at its final step answers with an HTTP error that still carries the error
    // assertion: relay it so the device is told, and show the flow's own failure.
    final terminal = json == null ? null : _callbackData(json, json['errorAssertion']);
    if (terminal != null) {
      await _relayCallback(fetcher, root, terminal, allowAccessDenied: true);
      return EmbeddedFlowResponse.fromMap({..._asFlowMap(json!), 'flowStatus': 'ERROR'});
    }
    throw IAMApiException(
      managementErrorCodeForStatus(response.statusCode),
      'The device authorization flow could not continue',
      statusCode: response.statusCode,
      statusText: response.statusText,
      operation: _operation,
      responseBody: response.body,
    );
  }
  if (json == null) {
    throw IAMApiException(
      ThunderIDErrorCode.serverError,
      'The device authorization flow returned an unreadable response',
      statusCode: response.statusCode,
      statusText: response.statusText,
      operation: _operation,
    );
  }

  final flow = EmbeddedFlowResponse.fromMap(_asFlowMap(json));
  if (flow.flowStatus == FlowStatus.promptOnly) return flow;

  final assertion = flow.flowStatus == FlowStatus.complete ? json['assertion'] : json['errorAssertion'];
  final terminal = _callbackData(json, assertion);
  if (terminal == null) {
    throw const IAMException(
      ThunderIDErrorCode.serverError,
      '$_operation: the finished device authorization flow carries no callback data.',
    );
  }
  await _relayCallback(fetcher, root, terminal, allowAccessDenied: flow.flowStatus == FlowStatus.error);
  return flow;
}

Future<ManagementResponse> _post(ManagementFetcher fetcher, Uri url, Map<String, Object?> body) async {
  try {
    return await fetcher(
      ManagementRequest(
        method: 'POST',
        url: url,
        headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
  } on IAMException {
    rethrow;
  } catch (error) {
    throw IAMApiException(
      ThunderIDErrorCode.networkError,
      'The device authorization flow could not be reached',
      statusCode: 0,
      statusText: 'Network Error',
      operation: _operation,
      cause: error,
    );
  }
}

Map<String, dynamic>? _decode(String body) {
  if (body.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(body);
    return decoded is Map ? readMap(decoded) : null;
  } on FormatException {
    return null;
  }
}

/// The flow response in the shape [EmbeddedFlowResponse.fromMap] reads: the server's `executionId`
/// becomes the `flowId` the next step continues with.
Map<String, dynamic> _asFlowMap(Map<String, dynamic> json) => {
      ...json,
      'flowId': json['executionId'] ?? json['flowId'],
    };

/// The callback body for a finished flow, or `null` when the response does not carry one.
Map<String, String>? _callbackData(Map<String, dynamic> json, Object? assertion) {
  final additionalData = readMap(readMap(json['data'])['additionalData']);
  final authId = additionalData['authId'];
  final type = additionalData['callbackType'];
  if (assertion is! String || assertion.isEmpty || authId is! String || type is! String) return null;
  return {'assertion': assertion, 'authId': authId, 'type': type};
}

Future<void> _relayCallback(
  ManagementFetcher fetcher,
  String root,
  Map<String, String> data, {
  required bool allowAccessDenied,
}) async {
  final response = await _post(fetcher, buildManagementUrl(_operation, '$root/oauth2/auth', segments: const ['callback']), data);
  if (response.ok) return;
  // A refused flow is expected to be answered with access_denied: the device is told it was denied.
  if (allowAccessDenied && response.statusCode == 400 && _decode(response.body)?['error'] == 'access_denied') return;
  throw IAMApiException(
    managementErrorCodeForStatus(response.statusCode),
    'The device could not be told the outcome of the authorization',
    statusCode: response.statusCode,
    statusText: response.statusText,
    operation: _operation,
    responseBody: response.body,
  );
}
