// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../models/flow_models.dart';
import '../models/thunderid_error.dart';
import '../thunderid_client.dart';

/// Follows flow-execution `REDIRECTION` steps (federated sign-in or sign-up) through the native
/// browser session, including one that resumes straight into another, and returns the first
/// non-redirect response. Returns [response] unchanged when it is not a redirection, and null when
/// the user dismissed the browser — callers reset silently.
Future<EmbeddedFlowResponse?> followFederatedRedirect(
  ThunderIDClient client,
  EmbeddedFlowResponse response, {
  required String actionId,
  required String applicationId,
  required String flowId,
  String? challengeToken,
}) async {
  var current = response;
  while (current.type == 'REDIRECTION') {
    final redirectUrl = current.data?['redirectURL'] as String?;
    if (redirectUrl == null || redirectUrl.isEmpty) {
      throw const IAMException(ThunderIDErrorCode.serverError, 'Federated flow step did not return a redirect URL');
    }
    flowId = current.flowId ?? flowId;
    challengeToken = current.challengeToken ?? challengeToken;
    try {
      current = await client.continueFederatedAuth(
        redirectUrl: redirectUrl,
        actionId: actionId,
        applicationId: applicationId,
        flowId: flowId,
        challengeToken: challengeToken,
      );
    } on IAMException catch (e) {
      if (e.code == ThunderIDErrorCode.federatedAuthCancelled) return null;
      rethrow;
    }
  }
  return current;
}
