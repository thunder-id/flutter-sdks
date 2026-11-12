// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:material_ui/material_ui.dart';

import '../event_log.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Full SDK event log with kind filters.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  LogKind? _filter;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: EventLog.instance,
      builder: (context, _) {
        final count = EventLog.instance.entries.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenTitle(
              title: 'Logs',
              trailing: TextButton.icon(
                onPressed: count == 0 ? null : EventLog.instance.clear,
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text('Clear'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  foregroundColor: PlaygroundColors.white(0.75),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Segmented<LogKind?>(
                options: const [(null, 'All'), (LogKind.ok, 'OK'), (LogKind.info, 'Info'), (LogKind.error, 'Error')],
                value: _filter,
                onChanged: (k) => setState(() => _filter = k),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                children: [EventList(filter: _filter)],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Event rows from [EventLog], newest first.
class EventList extends StatelessWidget {
  final LogKind? filter;
  final int? limit;
  final VoidCallback? onOpenAll;

  const EventList({super.key, this.filter, this.limit, this.onOpenAll});

  static Color colorOf(LogKind kind) => switch (kind) {
        LogKind.ok => PlaygroundColors.passSoft,
        LogKind.info => PlaygroundColors.primarySoft,
        LogKind.error => PlaygroundColors.failSoft,
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: EventLog.instance,
      builder: (context, _) {
        var entries = EventLog.instance.entries.where((e) => filter == null || e.kind == filter).toList();
        final total = entries.length;
        if (limit != null && entries.length > limit!) entries = entries.sublist(0, limit);
        if (entries.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('No events yet.', style: TextStyle(fontSize: 13, color: PlaygroundColors.white(0.55))),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListCard(
              children: [
                for (final e in entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                e.name,
                                style: PlaygroundTheme.monoStyle(size: 12.5, color: colorOf(e.kind), weight: FontWeight.w500),
                              ),
                            ),
                            Text(e.clock, style: PlaygroundTheme.monoStyle(size: 11.5, color: PlaygroundColors.white(0.4))),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(e.detail, style: PlaygroundTheme.monoStyle(size: 11.5)),
                      ],
                    ),
                  ),
              ],
            ),
            if (onOpenAll != null && total > entries.length)
              TextButton(onPressed: onOpenAll, child: Text('Show all $total events in Logs')),
          ],
        );
      },
    );
  }
}
