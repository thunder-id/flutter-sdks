// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

import 'src/config.dart';
import 'src/event_log.dart';
import 'src/shell.dart';
import 'src/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  final config = PlaygroundConfig.fromEnv(dotenv.env);
  EventLog.instance.add('sdk:configured', config.baseUrl, kind: LogKind.info);
  runApp(
    ThunderIDProvider(
      config: config.toSdkConfig(),
      child: PlaygroundApp(config: config),
    ),
  );
}

class PlaygroundApp extends StatelessWidget {
  final PlaygroundConfig config;

  const PlaygroundApp({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ThunderID Playground',
      debugShowCheckedModeBanner: false,
      theme: PlaygroundTheme.app(),
      home: PlaygroundShell(config: config),
    );
  }
}
