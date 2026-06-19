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
      final code = ThunderIDErrorCode.fromString(e.code);
      throw IAMException(code, e.message ?? 'Platform error', cause: e);
    }
  }

  Future<Map<dynamic, dynamic>> invokeMap(String method, [Map<String, dynamic>? args]) async {
    try {
      final result = await _channel.invokeMethod<Map>(method, args);
      return result ?? {};
    } on PlatformException catch (e) {
      final code = ThunderIDErrorCode.fromString(e.code);
      throw IAMException(code, e.message ?? 'Platform error', cause: e);
    }
  }

  Future<List<dynamic>> invokeList(String method, [Map<String, dynamic>? args]) async {
    try {
      final result = await _channel.invokeMethod<List>(method, args);
      return result ?? [];
    } on PlatformException catch (e) {
      final code = ThunderIDErrorCode.fromString(e.code);
      throw IAMException(code, e.message ?? 'Platform error', cause: e);
    }
  }
}
