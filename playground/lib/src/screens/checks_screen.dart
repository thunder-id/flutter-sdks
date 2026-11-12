// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

import '../checks.dart';
import '../config.dart';
import '../server_health.dart';
import '../theme.dart';
import '../widgets/thunderid_mark.dart';
import '../widgets/ui.dart';

/// Capability checks: run one or all, pass/fail with a reason, summary ring, server health.
class ChecksScreen extends StatelessWidget {
  final PlaygroundConfig config;
  final ChecksController checks;
  final ServerHealthProbe health;
  final VoidCallback onOpenSession;

  const ChecksScreen({
    super.key,
    required this.config,
    required this.checks,
    required this.health,
    required this.onOpenSession,
  });

  @override
  Widget build(BuildContext context) {
    final sdk = ThunderIDProvider.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([checks, health]),
      builder: (context, _) {
        final sections = <String, List<CheckDef>>{};
        for (final def in checkDefs) {
          sections.putIfAbsent(def.section, () => []).add(def);
        }
        return Column(
          children: [
            _Header(sdk: sdk, onOpenSession: onOpenSession),
            Expanded(
              child: RefreshIndicator(
                onRefresh: health.check,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  children: [
                    _Summary(
                      checks: checks,
                      health: health,
                      config: config,
                      onRunAll: () {
                        health.check();
                        checks.runAll(sdk);
                      },
                    ),
                    for (final entry in sections.entries) ...[
                      const SizedBox(height: 14),
                      SectionLabel(entry.key),
                      ListCard(
                        children: [
                          for (final def in entry.value)
                            _CheckRow(
                              def: def,
                              state: checks.stateOf(def.id),
                              onRun: () => checks.runOne(sdk, def),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final ThunderIDState sdk;
  final VoidCallback onOpenSession;

  const _Header({required this.sdk, required this.onOpenSession});

  @override
  Widget build(BuildContext context) {
    final platform = Platform.isIOS ? 'iOS' : (Platform.isAndroid ? 'Android' : Platform.operatingSystem);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [PlaygroundColors.primary.withValues(alpha: 0.10), PlaygroundColors.background.withValues(alpha: 0)],
        ),
      ),
      child: Row(
        children: [
          const ThunderIDMark(height: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Playground', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
                const SizedBox(height: 2),
                Text(
                  'thunderid_flutter (source) · $platform',
                  style: PlaygroundTheme.monoStyle(size: 11.5, color: PlaygroundColors.accent, weight: FontWeight.w500),
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: sdk.isSignedIn ? 'Open session' : 'Signed out, open session',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onOpenSession,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  // Real SDK widget: BaseUserAvatar renders initials or an anonymous badge.
                  child: BaseUserAvatar(user: sdk.user, size: 40, anonymousSeed: 'playground'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final ChecksController checks;
  final ServerHealthProbe health;
  final PlaygroundConfig config;
  final VoidCallback onRunAll;

  const _Summary({required this.checks, required this.health, required this.config, required this.onRunAll});

  @override
  Widget build(BuildContext context) {
    final total = checks.runnableCount;
    final pass = checks.passCount;
    final pct = total == 0 ? 0 : (pass * 100 / total).round();
    final healthColor = switch (health.status) {
      ServerHealth.healthy => PlaygroundColors.pass,
      ServerHealth.checking || ServerHealth.unknown => PlaygroundColors.idle,
      ServerHealth.unhealthy => PlaygroundColors.warn,
      ServerHealth.unreachable => PlaygroundColors.fail,
    };
    return HeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Semantics(
                label: '$pct percent of checks passing',
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: CustomPaint(
                    painter: _RingPainter(pct / 100),
                    child: Center(
                      child: Text('$pct%', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$pass of $total passing', style: const TextStyle(fontSize: 15)),
                    if (checks.unavailableCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${checks.unavailableCount} unavailable in this SDK',
                          style: TextStyle(fontSize: 12, color: PlaygroundColors.white(0.5)),
                        ),
                      ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(color: healthColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '${config.serverLabel} · ${health.detail}',
                            overflow: TextOverflow.ellipsis,
                            style: PlaygroundTheme.monoStyle(size: 11.5, weight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GradientButton(
            label: checks.runningAll ? 'Running checks' : 'Run all checks',
            leading: checks.runningAll
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : const Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white),
            onPressed: checks.runningAll ? null : onRunAll,
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double fraction;

  const _RingPainter(this.fraction);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final track = Paint()
      ..color = PlaygroundColors.white(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    final arc = Paint()
      ..color = PlaygroundColors.primary
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5;
    final inset = rect.deflate(2.5);
    canvas.drawArc(inset, 0, math.pi * 2, false, track);
    if (fraction > 0) canvas.drawArc(inset, -math.pi / 2, math.pi * 2 * fraction, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.fraction != fraction;
}

class _CheckRow extends StatelessWidget {
  final CheckDef def;
  final CheckState state;
  final VoidCallback onRun;

  const _CheckRow({required this.def, required this.state, required this.onRun});

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, Widget icon) = switch (state.status) {
      CheckStatus.pass => (PlaygroundColors.pass, PlaygroundColors.passSoft, const Icon(Icons.check_rounded, size: 15)),
      CheckStatus.fail => (PlaygroundColors.fail, PlaygroundColors.failSoft, const Icon(Icons.close_rounded, size: 15)),
      CheckStatus.running => (
          PlaygroundColors.primary,
          PlaygroundColors.primarySoft,
          const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2.5, color: PlaygroundColors.primarySoft)),
        ),
      CheckStatus.idle => (PlaygroundColors.idle, PlaygroundColors.white(0.55), const Icon(Icons.remove_rounded, size: 15)),
      CheckStatus.unavailable => (PlaygroundColors.warn, PlaygroundColors.warnSoft, const Icon(Icons.block_rounded, size: 13)),
    };
    final unavailable = state.status == CheckStatus.unavailable;
    final noteColor = switch (state.status) {
      CheckStatus.fail => PlaygroundColors.failSoft,
      CheckStatus.unavailable => PlaygroundColors.warnSoft,
      _ => PlaygroundColors.passSoft.withValues(alpha: 0.85),
    };
    return Semantics(
      button: !unavailable,
      label: '${def.name}, ${state.status.name}${state.note.isEmpty ? '' : ', ${state.note}'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: unavailable ? null : onRun,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(color: bg.withValues(alpha: 0.14), shape: BoxShape.circle),
                  child: Center(child: IconTheme(data: IconThemeData(color: fg), child: icon)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(def.name, style: TextStyle(fontSize: 14, color: PlaygroundColors.white(unavailable ? 0.6 : 0.92))),
                      const SizedBox(height: 3),
                      Text(
                        def.api,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PlaygroundTheme.monoStyle(size: 11, color: PlaygroundColors.white(0.45)),
                      ),
                      if (state.note.isNotEmpty && state.status != CheckStatus.running) ...[
                        const SizedBox(height: 3),
                        Text(state.note, style: TextStyle(fontSize: 11.5, color: noteColor)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  unavailable ? Icons.info_outline_rounded : Icons.replay_rounded,
                  size: 16,
                  color: PlaygroundColors.white(0.35),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
