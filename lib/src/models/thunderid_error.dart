// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

/// All ThunderID SDK error codes (spec §10.2).
enum ThunderIDErrorCode {
  // Configuration
  sdkNotInitialized,
  alreadyInitialized,
  invalidConfiguration,
  invalidRedirectUri,

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

  // Management
  forbidden,
  notFound,

  // Network & Server
  networkError,
  requestTimeout,
  serverError,
  unknownError,

  // Federated / social login (TRIGGER actions)
  federatedAuthCancelled,

  // Passkey / WebAuthn
  passkeyNotSupported,
  passkeyCancelled,
  passkeyNoCredential,
  passkeyFailed;

  static const _codeMap = {
    'SDK_NOT_INITIALIZED': ThunderIDErrorCode.sdkNotInitialized,
    'ALREADY_INITIALIZED': ThunderIDErrorCode.alreadyInitialized,
    'INVALID_CONFIGURATION': ThunderIDErrorCode.invalidConfiguration,
    'INVALID_REDIRECT_URI': ThunderIDErrorCode.invalidRedirectUri,
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
    'FORBIDDEN': ThunderIDErrorCode.forbidden,
    'NOT_FOUND': ThunderIDErrorCode.notFound,
    'NETWORK_ERROR': ThunderIDErrorCode.networkError,
    'REQUEST_TIMEOUT': ThunderIDErrorCode.requestTimeout,
    'SERVER_ERROR': ThunderIDErrorCode.serverError,
    'UNKNOWN_ERROR': ThunderIDErrorCode.unknownError,
    'FEDERATED_AUTH_CANCELLED': ThunderIDErrorCode.federatedAuthCancelled,
    'PASSKEY_NOT_SUPPORTED': ThunderIDErrorCode.passkeyNotSupported,
    'PASSKEY_CANCELLED': ThunderIDErrorCode.passkeyCancelled,
    'PASSKEY_NO_CREDENTIAL': ThunderIDErrorCode.passkeyNoCredential,
    'PASSKEY_FAILED': ThunderIDErrorCode.passkeyFailed,
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
