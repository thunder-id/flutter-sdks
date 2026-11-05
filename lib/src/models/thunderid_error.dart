// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

/// All ThunderID SDK error codes (spec §10.2).
enum ThunderIDErrorCode {
  // Configuration
  sdkNotInitialized,
  alreadyInitialized,
  invalidConfiguration,
  invalidRedirectUri,

  /// The operation has no meaning in the configured mode, such as a token operation while sign-in
  /// runs on a backend that keeps the tokens.
  operationNotSupported,

  // Authentication
  authenticationFailed,
  userAccountLocked,
  userAccountDisabled,
  sessionExpired,
  mfaRequired,
  mfaFailed,
  invalidGrant,
  consentRequired,

  // Registration
  userAlreadyExists,
  invalidInput,
  invitationCodeInvalid,
  invitationCodeExpired,
  registrationDisabled,

  // Recovery
  recoveryFailed,
  confirmationCodeInvalid,
  confirmationCodeExpired,

  // Verification
  /// The server refused a self user attribute verification: an `ERROR` step or an HTTP 4xx.
  verificationFailed,

  // Network & Server
  networkError,
  requestTimeout,
  serverError,
  unknownError,

  /// A request to a URL outside the API base and the bypass URLs while sign-in runs on a backend.
  /// It is refused before anything is sent.
  backendUnsupportedUrl,

  // Federated / social login (TRIGGER actions)
  federatedAuthCancelled,

  // Passkey / WebAuthn
  passkeyNotSupported,
  passkeyCancelled,
  passkeyNoCredential,
  passkeyFailed,

  // Management operations
  /// The server refused a management request because the access token lacks the permission
  /// (HTTP 403). Distinct from [notFound], so a caller can tell the two apart.
  forbidden,

  /// The management resource does not exist (HTTP 404).
  notFound,

  /// An administration flow did not complete: a step refused, the flow asked for input the caller
  /// cannot give, or the flow the server configures for the operation no longer exists. Raised as
  /// an [AdministrationFlowError].
  administrationFlowFailed;

  static const _codeMap = {
    'SDK_NOT_INITIALIZED': ThunderIDErrorCode.sdkNotInitialized,
    'ALREADY_INITIALIZED': ThunderIDErrorCode.alreadyInitialized,
    'INVALID_CONFIGURATION': ThunderIDErrorCode.invalidConfiguration,
    'INVALID_REDIRECT_URI': ThunderIDErrorCode.invalidRedirectUri,
    'OPERATION_NOT_SUPPORTED': ThunderIDErrorCode.operationNotSupported,
    'AUTHENTICATION_FAILED': ThunderIDErrorCode.authenticationFailed,
    'USER_ACCOUNT_LOCKED': ThunderIDErrorCode.userAccountLocked,
    'USER_ACCOUNT_DISABLED': ThunderIDErrorCode.userAccountDisabled,
    'SESSION_EXPIRED': ThunderIDErrorCode.sessionExpired,
    'MFA_REQUIRED': ThunderIDErrorCode.mfaRequired,
    'MFA_FAILED': ThunderIDErrorCode.mfaFailed,
    'INVALID_GRANT': ThunderIDErrorCode.invalidGrant,
    'CONSENT_REQUIRED': ThunderIDErrorCode.consentRequired,
    'USER_ALREADY_EXISTS': ThunderIDErrorCode.userAlreadyExists,
    'INVALID_INPUT': ThunderIDErrorCode.invalidInput,
    'INVITATION_CODE_INVALID': ThunderIDErrorCode.invitationCodeInvalid,
    'INVITATION_CODE_EXPIRED': ThunderIDErrorCode.invitationCodeExpired,
    'REGISTRATION_DISABLED': ThunderIDErrorCode.registrationDisabled,
    'RECOVERY_FAILED': ThunderIDErrorCode.recoveryFailed,
    'CONFIRMATION_CODE_INVALID': ThunderIDErrorCode.confirmationCodeInvalid,
    'CONFIRMATION_CODE_EXPIRED': ThunderIDErrorCode.confirmationCodeExpired,
    'VERIFICATION_FAILED': ThunderIDErrorCode.verificationFailed,
    'NETWORK_ERROR': ThunderIDErrorCode.networkError,
    'REQUEST_TIMEOUT': ThunderIDErrorCode.requestTimeout,
    'SERVER_ERROR': ThunderIDErrorCode.serverError,
    'UNKNOWN_ERROR': ThunderIDErrorCode.unknownError,
    'BACKEND_UNSUPPORTED_URL': ThunderIDErrorCode.backendUnsupportedUrl,
    'FEDERATED_AUTH_CANCELLED': ThunderIDErrorCode.federatedAuthCancelled,
    'PASSKEY_NOT_SUPPORTED': ThunderIDErrorCode.passkeyNotSupported,
    'PASSKEY_CANCELLED': ThunderIDErrorCode.passkeyCancelled,
    'PASSKEY_NO_CREDENTIAL': ThunderIDErrorCode.passkeyNoCredential,
    'PASSKEY_FAILED': ThunderIDErrorCode.passkeyFailed,
    'FORBIDDEN': ThunderIDErrorCode.forbidden,
    'NOT_FOUND': ThunderIDErrorCode.notFound,
    'ADMINISTRATION_FLOW_FAILED': ThunderIDErrorCode.administrationFlowFailed,
  };

  static ThunderIDErrorCode fromString(String code) =>
      _codeMap[code] ?? ThunderIDErrorCode.unknownError;

  String get value => name
      .replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m[0]}')
      .toUpperCase()
      .replaceFirst(RegExp(r'^_'), '');
}

class IAMException implements Exception {
  final ThunderIDErrorCode code;
  final String message;
  final Object? cause;

  const IAMException(this.code, this.message, {this.cause});

  @override
  String toString() => '[${code.value}] $message';
}

/// An [IAMException] raised from an HTTP response, carrying the status the server answered with
/// (spec "Error model": the API error type).
///
/// Raised by the management operations. [message] is built by the SDK and never contains the
/// server's response body, which may carry personal data; the body is kept separately in
/// [responseBody] for diagnostics and MUST NOT be shown to end users.
class IAMApiException extends IAMException {
  /// HTTP status code, or `0` when the request never reached the server.
  final int statusCode;

  /// HTTP reason phrase, e.g. `Forbidden`.
  final String statusText;

  /// Name of the operation that raised the error, e.g. `getRoles`.
  final String operation;

  /// The raw response body, for diagnostics only.
  final String? responseBody;

  /// The error the server returned, when [responseBody] is the server's error envelope: the
  /// server's own error code (such as `USR-1027`), and its message and description with their
  /// translation keys and parameters. Use it to show a message specific to the server's code.
  /// `null` when the body is not an envelope.
  ServerError? get serverError => ServerError.tryParse(responseBody);

  const IAMApiException(
    super.code,
    super.message, {
    required this.statusCode,
    required this.operation,
    this.statusText = '',
    this.responseBody,
    super.cause,
  });

  @override
  String toString() => '[${code.value}] $operation: $message (HTTP $statusCode)';
}

/// A localizable message in a [ServerError] or an [AdministrationFlowStepError]: its translation
/// key, its English text, and the values its placeholders take.
class ServerErrorMessage {
  final String? key;
  final String? defaultValue;
  final Map<String, String> params;

  const ServerErrorMessage({this.key, this.defaultValue, this.params = const {}});

  /// Reads a message object, or a plain string as its [defaultValue]. Returns `null` for anything
  /// else.
  static ServerErrorMessage? tryParse(Object? value) {
    if (value is String) return ServerErrorMessage(defaultValue: value);
    if (value is! Map) return null;
    final key = value['key'];
    final defaultValue = value['defaultValue'];
    final params = value['params'];
    return ServerErrorMessage(
      key: key is String ? key : null,
      defaultValue: defaultValue is String ? defaultValue : null,
      params: params is Map
          ? {
              for (final entry in params.entries)
                if (entry.value != null) entry.key.toString(): entry.value.toString(),
            }
          : const {},
    );
  }
}

/// The error envelope the ThunderID server returns with a failed request. See
/// [IAMApiException.serverError].
class ServerError {
  /// The server's error code, such as `USR-1027`.
  final String code;
  final ServerErrorMessage? message;
  final ServerErrorMessage? description;

  const ServerError({required this.code, this.message, this.description});

  /// Reads the envelope from a raw response body. Lenient: returns `null` when the body is not
  /// JSON, or not an object with a string `code`.
  static ServerError? tryParse(String? body) {
    if (body == null || body.trim().isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final code = decoded['code'];
    if (code is! String) return null;
    return ServerError(
      code: code,
      message: ServerErrorMessage.tryParse(decoded['message']),
      description: ServerErrorMessage.tryParse(decoded['description']),
    );
  }
}

/// The error a refused administration flow step carries: the step's own code and reason.
class AdministrationFlowStepError {
  final String? code;
  final ServerErrorMessage? message;
  final ServerErrorMessage? description;

  const AdministrationFlowStepError({this.code, this.message, this.description});

  /// Reads a step error leniently; anything that is not an object reads as an empty error.
  factory AdministrationFlowStepError.fromJson(Object? value) {
    if (value is! Map) return const AdministrationFlowStepError();
    final code = value['code'];
    return AdministrationFlowStepError(
      code: code is String ? code : null,
      message: ServerErrorMessage.tryParse(value['message']),
      description: ServerErrorMessage.tryParse(value['description']),
    );
  }
}

/// Raised when an administration flow does not complete: a step refused (its code and reason are
/// in [flowError]), the flow asked for input the caller cannot give, or the flow the server
/// configures for the operation no longer exists.
///
/// A refusal arrives as a completed HTTP request with a failed step rather than as an HTTP error,
/// so [code] is always [ThunderIDErrorCode.administrationFlowFailed] and [flowCode] says why.
class AdministrationFlowError extends IAMException {
  /// Why the flow did not complete: the refused step's own code (such as `FLW-4001`), or one of
  /// `executeAdministrationFlow-IncompleteError-001` (the flow asked for more input),
  /// `executeAdministrationFlow-FlowError-001` (the flow failed without a step code),
  /// `resolveAdministrationFlowId-NotFoundError-001` (the configured flow no longer exists),
  /// `regenerateClientSecret-FlowError-001` (the regeneration flow returned no secret) and
  /// `{operation}-NotConfiguredError-001` (a flow-only operation, such as `suspendUser`, has no
  /// flow configured).
  final String flowCode;

  /// The error of the step that refused, when one did; empty otherwise.
  final AdministrationFlowStepError flowError;

  const AdministrationFlowError(
    String message,
    this.flowCode, {
    this.flowError = const AdministrationFlowStepError(),
  }) : super(ThunderIDErrorCode.administrationFlowFailed, message);

  @override
  String toString() => '[${code.value}] $flowCode: $message';
}
