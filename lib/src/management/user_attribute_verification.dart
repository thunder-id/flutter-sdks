// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../models/attribute_verification.dart';
import '../models/flow_models.dart';
import '../models/management/administration.dart';
import '../models/management/json_reader.dart';
import '../models/thunderid_error.dart';
import 'administration_flows.dart';
import 'management_request.dart';
import 'management_transport.dart';
import 'thunderid_management_client.dart';

const String _operation = 'sendUserAttributeVerification';

/// Administrator-initiated attribute verification: sending a user a link to verify an attribute.
///
/// It runs the server's `ADMIN_INITIATED` flow at `{baseUrl}/flow/execute` with the
/// administrator's token. The flow pauses once the link is sent, and the user finishes it from the
/// link, without the administrator.
extension UserAttributeVerificationOperations on ThunderIDManagementClient {
  /// Sends [userId] a link to verify their [attribute], such as `email`, through the
  /// administrator-initiated verification flow [handle]. Without a [handle], the one the server
  /// configures (`adminAttributeVerificationFlow`, see
  /// [AdministrationFlowConfigKey.adminAttributeVerification]) is used, which needs a token that
  /// may read server configuration. With none configured it raises [AdministrationFlowError]
  /// (`sendUserAttributeVerification-NotConfiguredError-001`) and sends nothing.
  ///
  /// Returns the channel and the masked destination the link was sent to. Raises
  /// [ThunderIDErrorCode.invalidInput] before any request when [userId] or [attribute] is blank,
  /// and the usual [IAMApiException] when the server refuses the request. A refused step raises
  /// [AdministrationFlowError] with the step's code (such as `FET-1114` for a suspended user), and
  /// a flow that reports no sent link raises it with
  /// `sendUserAttributeVerification-UnexpectedStateError-001`.
  Future<UserAttributeVerificationResult> sendUserAttributeVerification(
    String userId,
    String attribute, {
    String? handle,
    ManagementFetcher? fetcher,
  }) async {
    if (userId.trim().isEmpty || attribute.trim().isEmpty) {
      throw const IAMException(
        ThunderIDErrorCode.invalidInput,
        '$_operation: a user identifier and an attribute are required.',
      );
    }
    const configKey = AdministrationFlowConfigKey.adminAttributeVerification;
    final flowHandle = handle != null && handle.trim().isNotEmpty
        ? handle
        : (await resolveAdministrationFlowHandles(const [configKey], fetcher: fetcher))[configKey];
    if (flowHandle == null) {
      throw const AdministrationFlowError(
        'No attribute verification flow is configured, so no link was sent. '
        'Configure the "adminAttributeVerificationFlow" handle in the server configuration.',
        '$_operation-NotConfiguredError-001',
      );
    }
    final result = readMap(
      await sendManagementRequest(
        fetcher: fetcher ?? this.fetcher,
        operation: _operation,
        failureMessage: 'Failed to send the verification link',
        method: 'POST',
        url: buildServerUrl(_operation, baseUrl, 'flow', id: 'execute'),
        body: {
          'flowType': FlowType.adminInitiated.value,
          'handle': flowHandle,
          'inputs': {
            AdministrationFlowInput.subject: userId,
            AttributeVerification.attributeInput: attribute,
          },
          'verbose': true,
        },
      ),
    );
    final status = readOptionalString(result, 'flowStatus');
    final data = readMap(readMap(result['data'])['additionalData']);
    final channel = data[AttributeVerification.channelKey]?.toString() ?? '';

    if (status == 'INCOMPLETE' && channel.isNotEmpty) {
      final masked = data[AttributeVerification.maskedDestinationKey]?.toString() ?? '';
      return UserAttributeVerificationResult(
        channel: channel,
        emailSent: switch (data[AdministrationFlowData.emailSent]?.toString()) {
          'true' => true,
          'false' => false,
          _ => null,
        },
        maskedDestination: masked.isEmpty ? null : masked,
      );
    }

    if (status == 'ERROR') {
      final flowError = AdministrationFlowStepError.fromJson(result['error']);
      throw AdministrationFlowError(
        flowError.message?.defaultValue ?? flowError.description?.defaultValue ?? 'The verification link was not sent.',
        flowError.code ?? '$_operation-FlowError-001',
        flowError: flowError,
      );
    }

    throw const AdministrationFlowError(
      'The verification flow did not report a sent link.',
      '$_operation-UnexpectedStateError-001',
    );
  }
}
