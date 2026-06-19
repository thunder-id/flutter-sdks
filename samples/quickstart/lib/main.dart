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
        clientId: dotenv.env['THUNDERID_CLIENT_ID'],
        applicationId: dotenv.env['THUNDERID_APP_ID'],
        afterSignInUrl: dotenv.env['THUNDERID_AFTER_SIGN_IN_URL'],
        afterSignOutUrl: dotenv.env['THUNDERID_AFTER_SIGN_OUT_URL'],
        scopes: const ['openid', 'profile', 'email'],
      ),
      child: const QuickstartApp(),
    ),
  );
}
