// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// Shared outlined-button chrome for `eventType: TRIGGER` (federated login) actions: an
/// optional icon slot, a label, and a rounded-rect stroke — matching the "Continue with X"
/// buttons rendered below a SignIn form's "Or" divider. Mirrors `TriggerButtonStyle` (iOS) /
/// `OutlinedTriggerButton` (Android).
class OutlinedTriggerButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  /// Disables the button without showing a spinner, e.g. while a sibling
  /// button's submission is in flight.
  final bool disabled;
  final VoidCallback onPressed;
  final Widget? icon;

  const OutlinedTriggerButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.disabled = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Semantics(
        label: label,
        button: true,
        child: SizedBox(
          height: 48,
          child: OutlinedButton(
            onPressed: (isLoading || disabled) ? null : onPressed,
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: colorScheme.outline.withValues(alpha: 0.4),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              minimumSize: const Size.fromHeight(44),
            ),
            child: isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[icon!, const SizedBox(width: 10)],
                      Flexible(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
