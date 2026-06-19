/*
 * Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

enum FlowType {
  authentication,
  registration,
  passwordRecovery,
  invitedUserRegistration;

  String get value {
    switch (this) {
      case FlowType.authentication:
        return 'AUTHENTICATION';
      case FlowType.registration:
        return 'REGISTRATION';
      case FlowType.passwordRecovery:
        return 'PASSWORD_RECOVERY';
      case FlowType.invitedUserRegistration:
        return 'INVITED_USER_REGISTRATION';
    }
  }
}

enum FlowStatus { promptOnly, complete, error }

class EmbeddedSignInPayload {
  final String? flowId;
  final String actionId;
  final Map<String, String> inputs;
  final String? challengeToken;

  const EmbeddedSignInPayload({
    this.flowId,
    required this.actionId,
    this.inputs = const {},
    this.challengeToken,
  });

  Map<String, dynamic> toMap() => {
        if (flowId != null) 'flowId': flowId,
        'actionId': actionId,
        'inputs': inputs,
        if (challengeToken != null) 'challengeToken': challengeToken,
      };
}

class EmbeddedFlowRequestConfig {
  final String applicationId;
  final FlowType flowType;

  const EmbeddedFlowRequestConfig({
    required this.applicationId,
    this.flowType = FlowType.authentication,
  });

  Map<String, dynamic> toMap() => {
        'applicationId': applicationId,
        'flowType': flowType.value,
      };
}

class EmbeddedFlowResponse {
  final String? flowId;
  final FlowStatus flowStatus;
  final String? stepId;
  final String? type;
  final Map<String, dynamic>? data;
  final String? assertion;
  final String? failureReason;
  final String? challengeToken;

  const EmbeddedFlowResponse({
    this.flowId,
    required this.flowStatus,
    this.stepId,
    this.type,
    this.data,
    this.assertion,
    this.failureReason,
    this.challengeToken,
  });

  factory EmbeddedFlowResponse.fromMap(Map<dynamic, dynamic> map) {
    final rawStatus = map['flowStatus'] as String? ?? '';
    final normalizedStatus = rawStatus.trim().toUpperCase().split('.').last;
    final status = normalizedStatus == 'COMPLETE'
      ? FlowStatus.complete
      : normalizedStatus == 'ERROR'
        ? FlowStatus.error
        : FlowStatus.promptOnly;
    return EmbeddedFlowResponse(
      flowId: map['flowId'] as String?,
      flowStatus: status,
      stepId: map['stepId'] as String?,
      type: map['type'] as String?,
      data: (map['data'] as Map?)?.cast<String, dynamic>(),
      assertion: map['assertion'] as String?,
      failureReason: map['failureReason'] as String?,
      challengeToken: map['challengeToken'] as String?,
    );
  }
}
