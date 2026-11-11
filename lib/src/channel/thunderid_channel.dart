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
      throw _toException(e);
    }
  }

  Future<Map<dynamic, dynamic>> invokeMap(String method, [Map<String, dynamic>? args]) async {
    try {
      final result = await _channel.invokeMethod<Map>(method, args);
      return result ?? {};
    } on PlatformException catch (e) {
      throw _toException(e);
    }
  }

  Future<List<dynamic>> invokeList(String method, [Map<String, dynamic>? args]) async {
    try {
      final result = await _channel.invokeMethod<List>(method, args);
      return result ?? [];
    } on PlatformException catch (e) {
      throw _toException(e);
    }
  }

  /// Converts a native failure, carrying the server's own error code when the native SDK sent one.
  static IAMException _toException(PlatformException e) {
    final details = e.details;
    final serverCode = details is Map ? details['serverCode'] as String? : null;
    return IAMException(
      ThunderIDErrorCode.fromString(e.code),
      e.message ?? 'Platform error',
      cause: e,
      serverCode: serverCode,
    );
  }
}
