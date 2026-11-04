// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'thunderid_error.dart';

/// Options for [ThunderIDClient.initiateCIBA], a Client-Initiated Backchannel Authentication
/// request (CIBA Core 1.0 section 7.1).
///
/// Exactly one of [loginHint], [loginHintToken] and [idTokenHint] identifies the user.
class CIBAInitiateOptions {
  /// A hint about the user to authenticate, such as an email address or username. Sent as
  /// `login_hint`.
  final String? loginHint;

  /// An opaque token that identifies the user. Sent as `login_hint_token`; the ThunderID server
  /// does not support it and refuses the request with `invalid_request`.
  final String? loginHintToken;

  /// A previously issued ID token that identifies the user. Sent as `id_token_hint`.
  final String? idTokenHint;

  /// A short text shown on both devices so the user can tell the two interactions belong
  /// together. Sent as `binding_message`.
  final String? bindingMessage;

  /// The requested lifetime of the request, in seconds. The server may grant a shorter one.
  final int? requestedExpiry;

  /// Space-separated Authentication Context Class Reference values.
  final String? acrValues;

  /// RFC 9396 authorization details to request, sent JSON-encoded as `authorization_details`.
  final List<Map<String, dynamic>>? authorizationDetails;

  /// Scopes to request. Defaults to [ThunderIDConfig.scopes].
  final List<String>? scopes;

  const CIBAInitiateOptions({
    this.loginHint,
    this.loginHintToken,
    this.idTokenHint,
    this.bindingMessage,
    this.requestedExpiry,
    this.acrValues,
    this.authorizationDetails,
    this.scopes,
  });

  /// Raises [ThunderIDErrorCode.invalidInput] unless exactly one hint is set.
  void validate() {
    final hints = [loginHint, loginHintToken, idTokenHint].where((hint) => hint != null && hint.trim().isNotEmpty);
    if (hints.isEmpty) {
      throw const IAMException(
        ThunderIDErrorCode.invalidInput,
        'initiateCIBA: provide one of loginHint, loginHintToken or idTokenHint.',
      );
    }
    if (hints.length > 1) {
      throw const IAMException(
        ThunderIDErrorCode.invalidInput,
        'initiateCIBA: only one of loginHint, loginHintToken or idTokenHint may be set.',
      );
    }
  }

  Map<String, dynamic> toMap() => {
        if (loginHint != null) 'loginHint': loginHint,
        if (loginHintToken != null) 'loginHintToken': loginHintToken,
        if (idTokenHint != null) 'idTokenHint': idTokenHint,
        if (bindingMessage != null) 'bindingMessage': bindingMessage,
        if (requestedExpiry != null) 'requestedExpiry': requestedExpiry,
        if (acrValues != null) 'acrValues': acrValues,
        if (authorizationDetails != null) 'authorizationDetails': authorizationDetails,
        if (scopes != null) 'scopes': scopes,
      };
}

/// The server's answer to [ThunderIDClient.initiateCIBA] (CIBA Core 1.0 section 7.3).
class CIBAInitiateResponse {
  /// Identifies the request; [ThunderIDClient.pollCIBA] polls the token endpoint with it.
  final String authReqId;

  /// The lifetime of [authReqId], in seconds. Polling stops once it has passed.
  final int expiresIn;

  /// The minimum wait between two polls, in seconds.
  final int interval;

  const CIBAInitiateResponse({required this.authReqId, required this.expiresIn, required this.interval});

  /// Reads the native SDK's answer. A missing lifetime or interval takes the CIBA defaults (120 and
  /// 5 seconds); a missing `authReqId` is a protocol error.
  factory CIBAInitiateResponse.fromMap(Map<dynamic, dynamic> map) {
    final authReqId = map['authReqId'];
    if (authReqId is! String || authReqId.isEmpty) {
      throw const IAMException(ThunderIDErrorCode.serverError, 'initiateCIBA: the response carries no auth_req_id.');
    }
    final expiresIn = map['expiresIn'];
    final interval = map['interval'];
    return CIBAInitiateResponse(
      authReqId: authReqId,
      expiresIn: expiresIn is num ? expiresIn.toInt() : 120,
      interval: interval is num ? interval.toInt() : 5,
    );
  }
}
