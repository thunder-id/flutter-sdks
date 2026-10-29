// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import '../account/user_avatar.dart';

/// Shared visual language for the styled `UserProfile` and `ChangeCredential` widgets.
///
/// These widgets deliberately do not use Material or Cupertino chrome: ThunderID is a
/// cross-platform SDK, and a screen that looks native to one platform looks foreign on the
/// other. This is package-internal (not exported from `thunderid_flutter.dart`) — the
/// unstyled `Base*` variants are the public customization surface; an app that wants a
/// different look builds its own presentation on top of those instead of overriding this one.
class ThunderAccountColors {
  final Color pageBackground;
  final Color text;
  final Color textSecondary;
  final Color divider;
  final Color accent;
  final Color inputBorder;
  final Color error;
  final Color pillBackground;
  final Color pillText;
  final Color avatarRingStart;
  final Color avatarRingEnd;

  const ThunderAccountColors({
    required this.pageBackground,
    required this.text,
    required this.textSecondary,
    required this.divider,
    required this.accent,
    required this.inputBorder,
    required this.error,
    required this.pillBackground,
    required this.pillText,
    required this.avatarRingStart,
    required this.avatarRingEnd,
  });

  static const light = ThunderAccountColors(
    pageBackground: Color(0xFFFFFFFF),
    text: Color(0xFF222222),
    textSecondary: Color(0xFF717171),
    divider: Color(0xFFEBEBEB),
    accent: Color(0xFFE31C5A),
    inputBorder: Color(0xFFB0B0B0),
    error: Color(0xFFC13515),
    pillBackground: Color(0xFF222222),
    pillText: Color(0xFFFFFFFF),
    avatarRingStart: Color(0xFF2D5BE3),
    avatarRingEnd: Color(0xFFE31C5A),
  );

  static const dark = ThunderAccountColors(
    pageBackground: Color(0xFF121212),
    text: Color(0xFFF2F2F2),
    textSecondary: Color(0xFFA8A8A8),
    divider: Color(0xFF2A2A2A),
    accent: Color(0xFFFF7A90),
    inputBorder: Color(0xFF484848),
    error: Color(0xFFFF8A8A),
    pillBackground: Color(0xFFF2F2F2),
    pillText: Color(0xFF121212),
    avatarRingStart: Color(0xFF8AB4FF),
    avatarRingEnd: Color(0xFFFF7A90),
  );

  /// Follows the OS-level brightness directly rather than the app's `Theme`, so these
  /// components support dark mode even in an app that never configured a `darkTheme`.
  factory ThunderAccountColors.of(BuildContext context) =>
      MediaQuery.platformBrightnessOf(context) == Brightness.dark ? dark : light;
}

/// A label/value row with a trailing "Edit" link and a bottom divider, matching the design's
/// settings-list pattern. Used for both profile fields and the credential row.
class ThunderAccountRow extends StatelessWidget {
  final String label;
  final String value;
  final String editLabel;
  final VoidCallback? onEdit;
  final bool showDivider;

  /// Distinguishes this row's tap target for an external driver like Maestro. Every row's
  /// [editLabel] text reads "Edit", so a row that end-to-end coverage needs to target
  /// individually (unlike the generic, currently-untested profile field rows) needs its own id
  /// rather than relying on that ambiguous text.
  final String? identifier;

  /// Shown under the value, such as the value's verification status.
  final Widget? detail;

  const ThunderAccountRow({
    super.key,
    required this.label,
    required this.value,
    required this.editLabel,
    required this.onEdit,
    this.showDivider = true,
    this.identifier,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ThunderAccountColors.of(context);
    // Only the "Edit" link itself is tappable, not the whole row - the label/value text isn't
    // an affordance, so it shouldn't read as one. [identifier] is scoped to that same link (not
    // the whole row), so an external driver's tap actually lands on the hit-testable area.
    final editLink = InkWell(
      key: identifier != null ? Key(identifier!) : null,
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
        child: Text(
          editLabel,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: colors.text,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: showDivider ? Border(bottom: BorderSide(color: colors.divider)) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 15, color: colors.textSecondary)),
                  if (value.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: TextStyle(fontSize: 16, color: colors.text),
                    ),
                  ],
                  if (detail != null) ...[
                    const SizedBox(height: 6),
                    detail!,
                  ],
                ],
              ),
            ),
            if (onEdit != null)
              identifier == null ? editLink : Semantics(identifier: identifier, child: editLink),
          ],
        ),
      ),
    );
  }
}

/// Bordered box holding a small label above a bare `TextField`, matching the design's
/// floating-field style. A field created with [obscureText] gets a show/hide toggle in its
/// trailing corner rather than being permanently masked.
class ThunderAccountField extends StatefulWidget {
  final String label;
  final String identifier;
  final bool obscureText;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  const ThunderAccountField({
    super.key,
    required this.label,
    required this.identifier,
    required this.onChanged,
    this.obscureText = false,
    this.controller,
  });

  @override
  State<ThunderAccountField> createState() => _ThunderAccountFieldState();
}

class _ThunderAccountFieldState extends State<ThunderAccountField> {
  late bool _obscured = widget.obscureText;

  @override
  Widget build(BuildContext context) {
    final colors = ThunderAccountColors.of(context);
    // The label sits where the typed value goes when the field is empty, and floats up to a
    // small label once it is focused or has a value - staying inside the border, not cutting
    // through it. That rules out InputDecoration's own OutlineInputBorder, which always paints
    // a gap in the border stroke behind a floated label: the border here is this Container's
    // own, and the TextField's decoration draws no border of its own (InputBorder.none), so
    // floating never touches it.
    return Semantics(
      identifier: widget.identifier,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: colors.inputBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: TextField(
          key: Key(widget.identifier),
          controller: widget.controller,
          obscureText: widget.obscureText && _obscured,
          onChanged: widget.onChanged,
          style: TextStyle(fontSize: 16, color: colors.text),
          decoration: InputDecoration(
            labelText: widget.label,
            labelStyle: TextStyle(fontSize: 16, color: colors.textSecondary),
            floatingLabelStyle: TextStyle(fontSize: 12, color: colors.textSecondary),
            floatingLabelBehavior: FloatingLabelBehavior.auto,
            isDense: true,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            suffixIcon: widget.obscureText
                ? Semantics(
                    identifier: '${widget.identifier}-toggleVisibility',
                    child: IconButton(
                      key: Key('${widget.identifier}-toggleVisibility'),
                      onPressed: () => setState(() => _obscured = !_obscured),
                      icon: Icon(
                        _obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        size: 20,
                        color: colors.textSecondary,
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class ThunderPillButton extends StatelessWidget {
  final String label;
  final String identifier;
  final VoidCallback? onPressed;

  const ThunderPillButton({
    super.key,
    required this.label,
    required this.identifier,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ThunderAccountColors.of(context);
    return Expanded(
      child: Semantics(
        identifier: identifier,
        child: SizedBox(
          height: 50,
          child: ElevatedButton(
            key: Key(identifier),
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.pillBackground,
              foregroundColor: colors.pillText,
              disabledBackgroundColor: colors.pillBackground.withValues(alpha: 0.4),
              disabledForegroundColor: colors.pillText.withValues(alpha: 0.7),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ThunderOutlineButton extends StatelessWidget {
  final String label;
  final String identifier;
  final VoidCallback? onPressed;

  const ThunderOutlineButton({
    super.key,
    required this.label,
    required this.identifier,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ThunderAccountColors.of(context);
    return Expanded(
      child: Semantics(
        identifier: identifier,
        child: SizedBox(
          height: 50,
          child: OutlinedButton(
            key: Key(identifier),
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.accent,
              side: BorderSide(color: colors.accent, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Avatar with the design's gradient ring. Rendering (picture vs. initials fallback) is
/// delegated to the existing [UserAvatar] so both places share one avatar implementation.
///
/// [onEdit], when supplied, renders a camera badge in the ring's bottom-right corner. There is
/// no built-in default for it: whether a picture can be edited at all depends on the user type
/// schema declaring an attribute for it, which only the caller knows.
class ThunderAccountAvatar extends StatelessWidget {
  final double size;
  final VoidCallback? onEdit;

  const ThunderAccountAvatar({super.key, this.size = 96, this.onEdit});

  @override
  Widget build(BuildContext context) {
    final colors = ThunderAccountColors.of(context);
    final badgeSize = size * 0.32;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colors.avatarRingStart, colors.avatarRingEnd],
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(shape: BoxShape.circle, color: colors.pageBackground),
              child: UserAvatar(size: size - 10),
            ),
          ),
          if (onEdit != null)
            Positioned(
              right: -2,
              bottom: -2,
              child: Semantics(
                identifier: 'thunderid-action-editAvatar',
                child: Material(
                  color: colors.text,
                  shape: CircleBorder(side: BorderSide(color: colors.pageBackground, width: 2)),
                  child: InkWell(
                    key: const Key('thunderid-action-editAvatar'),
                    customBorder: const CircleBorder(),
                    onTap: onEdit,
                    child: SizedBox(
                      width: badgeSize,
                      height: badgeSize,
                      child: Icon(
                        Icons.photo_camera_outlined,
                        size: badgeSize * 0.55,
                        color: colors.pageBackground,
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
}

/// Full-screen edit page: back button, title, description, then whatever [child] the caller
/// supplies (one or more [ThunderAccountField]s), with a Cancel/Save button row pinned to the
/// bottom. Matches the design's edit-overlay pattern, shared by profile field edits and the
/// change-credential form.
class ThunderAccountEditPage extends StatelessWidget {
  final String title;
  final String description;
  final Widget child;
  final String cancelLabel;
  final String saveLabel;
  final String cancelIdentifier;
  final String saveIdentifier;
  final VoidCallback onCancel;
  final VoidCallback? onSave;
  final String? errorText;

  /// Name of the page this page returns to, shown next to the back chevron - matches the
  /// Android/iOS SDKs' back-label convention.
  final String backLabel;

  const ThunderAccountEditPage({
    super.key,
    required this.title,
    required this.description,
    required this.child,
    required this.cancelLabel,
    required this.saveLabel,
    required this.cancelIdentifier,
    required this.saveIdentifier,
    required this.onCancel,
    required this.onSave,
    required this.backLabel,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ThunderAccountColors.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onCancel();
      },
      // This page is pushed via a plain PageRouteBuilder (so its transition is a fade, not
      // either platform's native push animation), which unlike MaterialPageRoute does not wrap
      // its content in a Material ancestor. TextField and InkWell both require one, and Scaffold
      // (rather than a bare Material) also resizes the body for the keyboard, keeping the fixed
      // Save/Cancel row above it instead of leaving it obscured once a field is focused.
      child: Scaffold(
        backgroundColor: colors.pageBackground,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The chevron glyph carries its own built-in padding, so its box's left
                      // edge doesn't line up with the title/description below it. Shifting the
                      // whole control left compensates, rather than a negative Padding, which
                      // Flutter rejects.
                      Transform.translate(
                        offset: const Offset(-6, 0),
                        child: InkWell(
                          onTap: onCancel,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6, bottom: 6, right: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.chevron_left, color: colors.text, size: 26),
                                const SizedBox(width: 2),
                                Text(
                                  backLabel,
                                  style: TextStyle(
                                    color: colors.text,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: colors.text,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        description,
                        style: TextStyle(fontSize: 14, color: colors.textSecondary, height: 1.4),
                      ),
                      const SizedBox(height: 28),
                      child,
                      if (errorText != null) ...[
                        const SizedBox(height: 8),
                        Text(errorText!, style: TextStyle(fontSize: 13, color: colors.error)),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Row(
                  children: [
                    ThunderOutlineButton(
                      label: cancelLabel,
                      identifier: cancelIdentifier,
                      onPressed: onCancel,
                    ),
                    const SizedBox(width: 10),
                    ThunderPillButton(
                      label: saveLabel,
                      identifier: saveIdentifier,
                      onPressed: onSave,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
