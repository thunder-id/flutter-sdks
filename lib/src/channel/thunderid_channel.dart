// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/services.dart';
import '../models/thunderid_error.dart';

/// Method channel bridge to the native iOS and Android ThunderID Platform SDKs.
/// All protocol operations (OAuth2/OIDC, token management, flow orchestration)
/// are delegated to the native SDK via this channel.
class ThunderIDChannel {
  static const MethodChannel _channel = MethodChannel('dev.thunderid/sdk');

  Future<T?> invoke<T>(String method, [Map<String, dynamic>? args]) async {
    try {
      final result = await _channel.invokeMethod<T>(method, args);
      return result;
    } on PlatformException catch (e) {
      throw toIAMException(e);
    }
  }

  Future<Map<dynamic, dynamic>> invokeMap(String method, [Map<String, dynamic>? args]) async {
    try {
      final result = await _channel.invokeMethod<Map>(method, args);
      return result ?? {};
    } on PlatformException catch (e) {
      throw toIAMException(e);
    }
  }

  Future<List<dynamic>> invokeList(String method, [Map<String, dynamic>? args]) async {
    try {
      final result = await _channel.invokeMethod<List>(method, args);
      return result ?? [];
    } on PlatformException catch (e) {
      throw toIAMException(e);
    }
  }
}

/// Converts a native SDK error into an [IAMException].
///
/// The native SDK sends the server's error envelope and any authentication challenge in
/// `details` (`serverError`, `authenticationChallenge`). The message is the envelope's readable
/// text when there is one, and the challenge falls back to the envelope's `AUTH-4011` parameters.
/// An error with a challenge is [ThunderIDErrorCode.stepUpRequired].
IAMException toIAMException(PlatformException e) {
  final details = e.details;
  final serverError = details is Map ? ServerError.fromMap(details['serverError']) : null;
  final challenge = (details is Map ? AuthenticationChallenge.fromMap(details['authenticationChallenge']) : null) ??
      AuthenticationChallenge.resolve(serverError: serverError);
  return IAMException(
    challenge != null ? ThunderIDErrorCode.stepUpRequired : ThunderIDErrorCode.fromString(e.code),
    serverError?.readableMessage ?? e.message ?? 'Platform error',
    cause: e,
    serverError: serverError,
    authenticationChallenge: challenge,
    isReauthenticationByAnotherAccount: details is Map && details['anotherAccount'] == true,
  );
}
