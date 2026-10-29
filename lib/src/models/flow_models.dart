// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

enum FlowType {
  authentication,
  registration,
  passwordRecovery,
  invitedUserRegistration,

  /// An operation the signed-in user runs on their own account, such as verifying an attribute.
  /// The flow is named by its handle, and the server takes the user from the access token.
  selfService;

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
      case FlowType.selfService:
        return 'SELF_SERVICE';
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

  /// The `error.message` object: the key to translate before showing [failureReason].
  final FlowErrorText? errorMessage;

  const EmbeddedFlowResponse({
    this.flowId,
    required this.flowStatus,
    this.stepId,
    this.type,
    this.data,
    this.assertion,
    this.failureReason,
    this.challengeToken,
    this.errorMessage,
  });

  /// The `data.additionalData` block, if present. Carries the WebAuthn/passkey ceremony
  /// options (`passkeyChallenge`/`passkeyCreationOptions`, each a JSON-encoded string) that
  /// drive an automatic passkey resubmit, alongside any other server-provided metadata.
  Map<String, dynamic>? get additionalData => (data?['additionalData'] as Map?)?.cast<String, dynamic>();

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
      errorMessage: FlowErrorText.fromMap((map['error'] as Map?)?['message']),
    );
  }
}

/// A translatable flow error text: an i18n [key], its English [defaultValue], and the values for
/// the `{{param(name)}}` placeholders a translation of [key] keeps.
class FlowErrorText {
  final String? key;
  final String? defaultValue;
  final Map<String, String> params;

  const FlowErrorText({this.key, this.defaultValue, this.params = const {}});

  static FlowErrorText? fromMap(Object? map) => map is Map
      ? FlowErrorText(
          key: map['key'] as String?,
          defaultValue: map['defaultValue'] as String?,
          params: {
            for (final e in ((map['params'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}',
          },
        )
      : null;
}

/// One row of a `KEY_VALUE_LIST` component, read from the `additionalData` key named in its `source`.
class KeyValuePair {
  final String label;
  final String value;

  const KeyValuePair({required this.label, required this.value});

  /// Reads the pairs a `KEY_VALUE_LIST` renders from the raw value found under its `source` key.
  /// The server publishes them as a JSON-encoded array, since additional data carries strings, so
  /// both an array and its encoding are accepted.
  ///
  /// Entries that are not objects, or that carry no value, are dropped, since an empty row tells the
  /// user nothing. Anything that is not a list of pairs yields none.
  static List<KeyValuePair> list(Object? raw) {
    Object? parsed = raw;
    if (raw is String) {
      try {
        parsed = jsonDecode(raw);
      } on FormatException {
        return const [];
      }
    }
    if (parsed is! List) return const [];
    return [
      for (final entry in parsed)
        if (entry is Map && entry['value'] is String && (entry['value'] as String).isNotEmpty)
          KeyValuePair(
            label: entry['label'] is String ? entry['label'] as String : '',
            value: entry['value'] as String,
          ),
    ];
  }

  @override
  bool operator ==(Object other) => other is KeyValuePair && other.label == label && other.value == value;

  @override
  int get hashCode => Object.hash(label, value);

  @override
  String toString() => 'KeyValuePair($label, $value)';
}
