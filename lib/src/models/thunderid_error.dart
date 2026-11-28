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

  /// The operation needs a more recent sign-in: the server answered `401` with an
  /// `insufficient_user_authentication` challenge or code `AUTH-4011`. The exception's
  /// [IAMException.authenticationChallenge] carries the `maxAge`; sign the user in again with
  /// `ThunderIDClient.reauthenticate` and retry.
  stepUpRequired,

  /// The embedded flow execution expired, or already ended, so the server refused the step. The flow has to
  /// start again.
  flowExpired,

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
    'UNSUPPORTED_OPERATION': ThunderIDErrorCode.operationNotSupported,
    'AUTHENTICATION_FAILED': ThunderIDErrorCode.authenticationFailed,
    'USER_ACCOUNT_LOCKED': ThunderIDErrorCode.userAccountLocked,
    'USER_ACCOUNT_DISABLED': ThunderIDErrorCode.userAccountDisabled,
    'SESSION_EXPIRED': ThunderIDErrorCode.sessionExpired,
    'MFA_REQUIRED': ThunderIDErrorCode.mfaRequired,
    'MFA_FAILED': ThunderIDErrorCode.mfaFailed,
    'INVALID_GRANT': ThunderIDErrorCode.invalidGrant,
    'CONSENT_REQUIRED': ThunderIDErrorCode.consentRequired,
    'STEP_UP_REQUIRED': ThunderIDErrorCode.stepUpRequired,
    'FLOW_EXPIRED': ThunderIDErrorCode.flowExpired,
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
  final ServerError? _serverError;
  final AuthenticationChallenge? _authenticationChallenge;

  const IAMException(
    this.code,
    this.message, {
    this.cause,
    ServerError? serverError,
    AuthenticationChallenge? authenticationChallenge,
    this.isReauthenticationByAnotherAccount = false,
  })  : _serverError = serverError,
        _authenticationChallenge = authenticationChallenge;

  /// Whether a re-sign-in failed because another account signed in. The session stays as it was.
  final bool isReauthenticationByAnotherAccount;

  /// The error envelope the server returned with a failed request, when its body was one: the
  /// server's own error code (such as `USR-1048`), and its message and description with their
  /// translation keys and parameters. `null` otherwise.
  ServerError? get serverError => _serverError;

  /// Set when the server answered `401` because the operation needs a more recent sign-in. The SDK
  /// does not sign in again or retry by itself.
  AuthenticationChallenge? get authenticationChallenge => _authenticationChallenge;

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
  @override
  ServerError? get serverError => super.serverError ?? ServerError.tryParse(responseBody);

  /// On a `401` with code `AUTH-4011` and no challenge given, read from the body's
  /// `description.params.maxAge`.
  @override
  AuthenticationChallenge? get authenticationChallenge =>
      super.authenticationChallenge ??
      (statusCode == 401 ? AuthenticationChallenge.resolve(serverError: serverError) : null);

  const IAMApiException(
    super.code,
    super.message, {
    required this.statusCode,
    required this.operation,
    this.statusText = '',
    this.responseBody,
    super.cause,
    super.serverError,
    super.authenticationChallenge,
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

  /// The envelope's English text: the message's `defaultValue`, else the description's.
  String? get readableMessage {
    final text = message?.defaultValue;
    if (text != null && text.trim().isNotEmpty) return text;
    final detail = description?.defaultValue;
    if (detail != null && detail.trim().isNotEmpty) return detail;
    return null;
  }

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
    return fromMap(decoded);
  }

  /// Reads the envelope from a decoded object, such as the one a native SDK sends across the
  /// platform channel. Returns `null` when it is not an object with a string `code`.
  static ServerError? fromMap(Object? value) {
    if (value is! Map) return null;
    final code = value['code'];
    if (code is! String) return null;
    return ServerError(
      code: code,
      message: ServerErrorMessage.tryParse(value['message']),
      description: ServerErrorMessage.tryParse(value['description']),
    );
  }
}

/// How the signed-in user signs in again after [ThunderIDErrorCode.stepUpRequired].
enum ReauthenticationMethod {
  /// In the browser, with `ThunderIDClient.reauthenticate`: a session from a redirect sign-in.
  browser,

  /// By running the sign-in flow again with `EmbeddedFlowRequestConfig.reauthentication`: a session
  /// from an embedded (app-native) sign-in.
  flow,

  /// Not in the app: sign-in runs on a backend.
  unavailable,
}

/// A `401` that asks for a more recent sign-in (RFC 9470): the server's `WWW-Authenticate: Bearer`
/// challenge with `error="insufficient_user_authentication"`. Sign the user in again and retry.
class AuthenticationChallenge {
  /// The `error` of a challenge that asks for a more recent sign-in.
  static const insufficientUserAuthentication = 'insufficient_user_authentication';

  /// The server's code for a sign-in older than the operation allows.
  static const recentAuthenticationRequiredCode = 'AUTH-4011';

  static final _scheme = RegExp(r'(?:^|[\s,])Bearer(?:\s+|$)', caseSensitive: false);
  static final _param = RegExp(r'''([A-Za-z0-9_!#$%&'*+.^`|~-]+)\s*=\s*(?:"((?:[^"\\]|\\.)*)"|([^\s,]*))''');
  static final _escape = RegExp(r'\\(.)');

  /// The challenge's `error`, `insufficient_user_authentication`.
  final String error;

  /// The challenge's `error_description`, when sent.
  final String? errorDescription;

  /// The challenge's `max_age`: the sign-in must be at most this many seconds old.
  final int? maxAge;

  const AuthenticationChallenge({required this.error, this.errorDescription, this.maxAge});

  /// Reads the challenge of a `401`: from its `WWW-Authenticate` header, else from the body's
  /// `description.params.maxAge` when the server's code is `AUTH-4011`. Returns `null` when the
  /// response does not ask for a more recent sign-in.
  static AuthenticationChallenge? resolve({String? wwwAuthenticate, ServerError? serverError}) {
    final fromHeader = parse(wwwAuthenticate);
    if (fromHeader != null) return fromHeader;
    if (serverError == null || serverError.code != recentAuthenticationRequiredCode) return null;
    return AuthenticationChallenge(
      error: insufficientUserAuthentication,
      maxAge: _nonNegativeInt(serverError.description?.params['maxAge']),
    );
  }

  /// Reads a `WWW-Authenticate` header value. Returns `null` when it has no `Bearer` challenge with
  /// `error="insufficient_user_authentication"`.
  static AuthenticationChallenge? parse(String? wwwAuthenticate) {
    if (wwwAuthenticate == null || wwwAuthenticate.trim().isEmpty) return null;
    final scheme = _scheme.firstMatch(wwwAuthenticate);
    if (scheme == null) return null;
    final rest = wwwAuthenticate.substring(scheme.end);
    final params = <String, String>{};
    var end = 0;
    // Reads the Bearer challenge's parameters up to the next scheme.
    for (final match in _param.allMatches(rest)) {
      if (rest.substring(end, match.start).trim().replaceAll(',', '').isNotEmpty) break;
      end = match.end;
      final quoted = match.group(2)?.replaceAllMapped(_escape, (m) => m.group(1)!);
      params.putIfAbsent(match.group(1)!.toLowerCase(), () => quoted ?? match.group(3) ?? '');
    }
    if (params['error'] != insufficientUserAuthentication) return null;
    final description = params['error_description'];
    return AuthenticationChallenge(
      error: insufficientUserAuthentication,
      errorDescription: description == null || description.isEmpty ? null : description,
      maxAge: _nonNegativeInt(params['max_age']),
    );
  }

  /// Reads the challenge a native SDK sends across the platform channel.
  static AuthenticationChallenge? fromMap(Object? value) {
    if (value is! Map) return null;
    final Object? error = value['error'];
    if (error is! String || error.isEmpty) return null;
    final Object? description = value['errorDescription'];
    final Object? maxAge = value['maxAge'];
    return AuthenticationChallenge(
      error: error,
      errorDescription: description is String && description.isNotEmpty ? description : null,
      maxAge: maxAge is int ? (maxAge >= 0 ? maxAge : null) : _nonNegativeInt(maxAge?.toString()),
    );
  }

  static int? _nonNegativeInt(String? value) {
    final parsed = value == null ? null : int.tryParse(value.trim());
    return parsed != null && parsed >= 0 ? parsed : null;
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
  /// `regenerateClientSecret-FlowError-001` (the regeneration flow returned no secret),
  /// `{operation}-NotConfiguredError-001` (a flow-only operation, such as `suspendUser`, has no
  /// flow configured), and `sendUserAttributeVerification-FlowError-001` and
  /// `sendUserAttributeVerification-UnexpectedStateError-001` (the verification flow failed
  /// without a step code, or reported no sent link).
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
