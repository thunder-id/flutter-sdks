// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// Gradient summary card (16px radius).
class HeroCard extends StatelessWidget {
  final Widget child;

  const HeroCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: PlaygroundColors.cardGradient,
          border: Border.all(color: PlaygroundColors.white(0.09)),
        ),
        child: child,
      );
}

/// Flat bordered list container.
class ListCard extends StatelessWidget {
  final List<Widget> children;

  const ListCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: PlaygroundColors.white(0.025),
          border: Border.all(color: PlaygroundColors.white(0.08)),
        ),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: PlaygroundColors.white(0.06)),
              children[i],
            ],
          ],
        ),
      );
}

class SectionLabel extends StatelessWidget {
  final String text;

  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.9,
            color: PlaygroundColors.white(0.45),
          ),
        ),
      );
}

/// Segmented control matching the design's pill tabs.
class Segmented<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  const Segmented({super.key, required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: PlaygroundColors.white(0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            for (final (id, label) in options)
              Expanded(
                child: Semantics(
                  selected: id == value,
                  button: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onChanged(id),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 36),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: id == value ? PlaygroundColors.primary.withValues(alpha: 0.2) : null,
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: id == value ? Colors.white : PlaygroundColors.white(0.6),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// Rounded pill with a leading dot.
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const StatusPill({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color)),
          ],
        ),
      );
}

/// Small secondary button used for reveal/copy actions.
class ChipButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  const ChipButton({super.key, required this.label, this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: onPressed,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 14),
        label: Text(label),
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          backgroundColor: PlaygroundColors.white(0.06),
          foregroundColor: PlaygroundColors.white(0.85),
          textStyle: const TextStyle(fontSize: 12.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
}

/// Primary gradient button.
class GradientButton extends StatelessWidget {
  final String label;
  final Widget? leading;
  final VoidCallback? onPressed;

  const GradientButton({super.key, required this.label, this.leading, this.onPressed});

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onPressed == null ? 0.6 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: PlaygroundColors.primaryGradient,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onPressed,
              child: Container(
                constraints: const BoxConstraints(minHeight: 46),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (leading != null) ...[leading!, const SizedBox(width: 8)],
                    Text(
                      label,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

/// Monospace code block with a copy action.
class CodeBlock extends StatelessWidget {
  final String code;
  final String language;

  const CodeBlock({super.key, required this.code, required this.language});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(language, style: PlaygroundTheme.monoStyle(size: 11.5, color: PlaygroundColors.white(0.5)))),
              ChipButton(
                label: 'Copy',
                icon: Icons.copy_rounded,
                onPressed: () => copyToClipboard(context, code, 'Snippet copied'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PlaygroundColors.white(0.08)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                code,
                style: PlaygroundTheme.monoStyle(size: 12.5, color: const Color(0xFFCFE3FF)).copyWith(height: 1.65),
              ),
            ),
          ),
        ],
      );
}

Future<void> copyToClipboard(BuildContext context, String text, String message) async {
  final messenger = ScaffoldMessenger.of(context);
  await Clipboard.setData(ClipboardData(text: text));
  messenger.showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
}

/// Dotted grid background used behind the component preview.
class DotGridPainter extends CustomPainter {
  final Color color;

  const DotGridPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (double y = 8; y < size.height; y += 16) {
      for (double x = 8; x < size.width; x += 16) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(DotGridPainter oldDelegate) => oldDelegate.color != color;
}

/// Screen title row used by Session and Logs.
class ScreenTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const ScreenTitle({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w400, letterSpacing: -0.5),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}
