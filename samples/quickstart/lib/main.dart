// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  runApp(
    ThunderIDProvider(
      config: ThunderIDConfig(
        baseUrl: dotenv.env['THUNDERID_BASE_URL']!,
        applicationId: dotenv.env['THUNDERID_APP_ID'],
        scopes: const ['openid', 'profile', 'email'],
        attestationEnabled:
            dotenv.env['THUNDERID_ATTESTATION_ENABLED']?.toLowerCase() == 'true',
        cloudProjectNumber:
            int.tryParse(dotenv.env['THUNDERID_CLOUD_PROJECT_NUMBER'] ?? ''),
        // Debug builds only, so the sample can reach a local server using the self-signed
        // certificate ThunderID generates for localhost. kDebugMode is compiled out of a
        // release build, so certificate validation is never disabled in one.
        allowInsecureConnections: kDebugMode,
      ),
      child: const QuickstartApp(),
    ),
  );
}
