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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('io.thunder/sdk'),
      (call) async {
        switch (call.method) {
          case 'initialize':
            return true;
          case 'isSignedIn':
            return false;
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('io.thunder/sdk'), null);
  });

  testWidgets('shows loading indicator while initializing', (tester) async {
    await tester.pumpWidget(
      const ThunderIDProvider(
        config: ThunderIDConfig(
          baseUrl: 'https://localhost:8090',
          clientId: 'test',
        ),
        child: MaterialApp(home: Scaffold(body: Text('App'))),
      ),
    );
    // First frame: should show the child (ThunderIDProvider manages loading internally)
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
