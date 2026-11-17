// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:material_ui/material_ui.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

import 'checks.dart';
import 'config.dart';
import 'event_log.dart';
import 'screens/checks_screen.dart';
import 'screens/components_screen.dart';
import 'screens/logs_screen.dart';
import 'screens/session_screen.dart';
import 'server_health.dart';
import 'theme.dart';

/// Root of the playground: four tabs (Checks, Components, Session, Logs).
class PlaygroundShell extends StatefulWidget {
  final PlaygroundConfig config;

  const PlaygroundShell({super.key, required this.config});

  @override
  State<PlaygroundShell> createState() => _PlaygroundShellState();
}

class _PlaygroundShellState extends State<PlaygroundShell> {
  late final ChecksController _checks = ChecksController(widget.config);
  late final ServerHealthProbe _health = ServerHealthProbe(widget.config.baseUrl);
  int _tab = 0;

  bool? _lastSignedIn;
  bool _lastInitialized = false;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _health.check();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _observe(ThunderIDProvider.of(context));
  }

  /// Logs provider state transitions, since the SDK has no event stream of its own.
  void _observe(ThunderIDState sdk) {
    final log = EventLog.instance;
    if (sdk.initialized && !_lastInitialized) {
      log.add('sdk:initialized', 'isSignedIn=${sdk.isSignedIn}', kind: LogKind.ok);
    }
    if (sdk.error != null && sdk.error != _lastError) {
      log.add('sdk:error', sdk.error!, kind: LogKind.error);
    }
    if (sdk.initialized && _lastSignedIn != null && _lastSignedIn != sdk.isSignedIn) {
      log.add(
        sdk.isSignedIn ? 'session:signedIn' : 'session:signedOut',
        sdk.isSignedIn ? 'sub=${sdk.user?.sub ?? '-'}' : 'session cleared',
        kind: LogKind.ok,
      );
    }
    _lastInitialized = sdk.initialized;
    _lastError = sdk.error;
    if (sdk.initialized) _lastSignedIn = sdk.isSignedIn;
  }

  @override
  void dispose() {
    _checks.dispose();
    _health.dispose();
    super.dispose();
  }

  void _go(int tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _tab,
          children: [
            ChecksScreen(
              config: widget.config,
              checks: _checks,
              health: _health,
              onOpenSession: () => _go(2),
            ),
            ComponentsScreen(config: widget.config),
            SessionScreen(config: widget.config, onOpenLogs: () => _go(3)),
            const LogsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: _TabBar(index: _tab, onSelect: _go),
    );
  }
}

class _TabBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;

  const _TabBar({required this.index, required this.onSelect});

  static const _items = [
    (Icons.check_circle_outline_rounded, 'Checks'),
    (Icons.grid_view_rounded, 'Components'),
    (Icons.key_rounded, 'Session'),
    (Icons.format_list_bulleted_rounded, 'Logs'),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xF5060D1C),
        border: Border(top: BorderSide(color: PlaygroundColors.white(0.08))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: Semantics(
                    selected: i == index,
                    button: true,
                    label: _items[i].$2,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onSelect(i),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 4),
                            Icon(
                              _items[i].$1,
                              size: 22,
                              color: i == index ? PlaygroundColors.primarySoft : PlaygroundColors.white(0.55),
                            ),
                            const SizedBox(height: 4),
                            ExcludeSemantics(
                              child: Text(
                                _items[i].$2,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: i == index ? PlaygroundColors.primarySoft : PlaygroundColors.white(0.55),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
