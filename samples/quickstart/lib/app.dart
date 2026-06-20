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

import 'package:flutter/material.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';

class QuickstartApp extends StatelessWidget {
  const QuickstartApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ACME Booking',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFFF5A5F),
        useMaterial3: true,
      ),
      home: const _RootScreen(),
    );
  }
}

class _RootScreen extends StatelessWidget {
  const _RootScreen();

  @override
  Widget build(BuildContext context) {
    final thunder = ThunderIDProvider.of(context);

    if (thunder.isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Starting ACME Booking\u2026'),
            ],
          ),
        ),
      );
    }

    if (thunder.error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Configuration error: ${thunder.error}\n\nCheck your .env values.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return thunder.isSignedIn ? const HomeScreen() : const AuthScreen();
  }
}
