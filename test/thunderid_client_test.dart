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

import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/thunderid_client.dart';
import 'package:thunderid_flutter/src/models/thunderid_config.dart';
import 'package:thunderid_flutter/src/models/thunderid_error.dart';
import 'package:thunderid_flutter/src/channel/thunderid_channel.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ThunderIDClient client;
  final List<MethodCall> log = [];

  setUp(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.thunderid/sdk'),
      (call) async {
        log.add(call);
        switch (call.method) {
          case 'initialize':
            return true;
          case 'isSignedIn':
            return false;
          case 'signOut':
            return '/';
          case 'getAccessToken':
            return 'mock-access-token';
          default:
            return null;
        }
      },
    );
    client = ThunderIDClient();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dev.thunderid/sdk'), null);
  });

  group('initialization', () {
    test('initialize calls native channel with config', () async {
      const config = ThunderIDConfig(
        baseUrl: 'https://localhost:8090',
        clientId: 'test-client',
      );
      final result = await client.initialize(config);
      expect(result, true);
      expect(log.any((c) => c.method == 'initialize'), true);
    });

    test('initialize throws ALREADY_INITIALIZED when called twice', () async {
      const config = ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'test');
      await client.initialize(config);
      expect(
        () => client.initialize(config),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.alreadyInitialized)),
      );
    });

    test('operations before init throw SDK_NOT_INITIALIZED', () {
      expect(
        () => client.isSignedIn(),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.sdkNotInitialized)),
      );
    });
  });

  group('isLoading', () {
    test('isLoading returns false when not active', () async {
      const config = ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'test');
      await client.initialize(config);
      expect(client.isLoading(), false);
    });
  });

  group('ThunderIDErrorCode', () {
    test('fromString parses known codes', () {
      expect(ThunderIDErrorCode.fromString('AUTHENTICATION_FAILED'), ThunderIDErrorCode.authenticationFailed);
      expect(ThunderIDErrorCode.fromString('SESSION_EXPIRED'), ThunderIDErrorCode.sessionExpired);
      expect(ThunderIDErrorCode.fromString('SDK_NOT_INITIALIZED'), ThunderIDErrorCode.sdkNotInitialized);
    });

    test('fromString returns unknownError for unknown code', () {
      expect(ThunderIDErrorCode.fromString('NOT_REAL'), ThunderIDErrorCode.unknownError);
    });

    test('IAMException toString includes code', () {
      final e = IAMException(ThunderIDErrorCode.networkError, 'connection refused');
      expect(e.toString(), contains('NETWORK_ERROR'));
    });
  });

  group('ThunderIDConfig', () {
    test('toMap includes required fields', () {
      const config = ThunderIDConfig(
        baseUrl: 'https://localhost:8090',
        clientId: 'client-123',
        scopes: ['openid', 'profile'],
      );
      final map = config.toMap();
      expect(map['baseUrl'], 'https://localhost:8090');
      expect(map['clientId'], 'client-123');
      expect(map['scopes'], ['openid', 'profile']);
    });

    test('toMap omits null optional fields', () {
      const config = ThunderIDConfig(baseUrl: 'https://localhost:8090');
      final map = config.toMap();
      expect(map.containsKey('clientId'), false);
      expect(map.containsKey('afterSignInUrl'), false);
    });
  });

  group('sign-out', () {
    test('signOut delegates to native and returns afterSignOutUrl', () async {
      const config = ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'test');
      await client.initialize(config);
      final result = await client.signOut();
      expect(result, '/');
    });
  });

  group('getAccessToken', () {
    test('returns token from native layer', () async {
      const config = ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'test');
      await client.initialize(config);
      final token = await client.getAccessToken();
      expect(token, 'mock-access-token');
    });
  });
}
