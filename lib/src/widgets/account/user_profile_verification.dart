// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import '../../i18n/thunderid_i18n.dart';
import '../../models/attribute_verification.dart';
import '../internal/account_style.dart';

/// The verification status of a stored profile value, as the server reports it.
enum AttributeVerificationStatus { verified, unverified }

/// The status to show for a profile attribute, or null when none is shown.
///
/// Status comes only from [verified], the profile's `verifiedAttributes`: when the server does not
/// report it, the status is unknown and nothing is shown. It describes the stored value, so it is
/// shown only for a top-level `email` or `mobile` property with a non-empty stored value, and never
/// while that value is being edited or a save is about to replace it.
AttributeVerificationStatus? verificationStatusOf({
  required String name,
  required String? schemaType,
  required Object? storedValue,
  required Map<String, VerifiedAttribute>? verified,
  required bool isEditing,
}) {
  if (verified == null || isEditing) return null;
  if (!AttributeVerification.isVerifiableType(schemaType)) return null;
  if (storedValue is! String || storedValue.trim().isEmpty) return null;
  return verified.containsKey(name)
      ? AttributeVerificationStatus.verified
      : AttributeVerificationStatus.unverified;
}

/// A Verified or Unverified status: an icon and a colored label.
class VerificationStatusBadge extends StatelessWidget {
  final AttributeVerificationStatus status;
  final ThunderIDI18n i18n;

  /// Exposed to the platform accessibility tree, for an external driver.
  final String? identifier;

  const VerificationStatusBadge({
    super.key,
    required this.status,
    required this.i18n,
    this.identifier,
  });

  @override
  Widget build(BuildContext context) {
    final verified = status == AttributeVerificationStatus.verified;
    return VerificationStatusLabel(
      verified: verified,
      label: i18n.resolve(
        verified ? 'userProfile.verification.verified' : 'userProfile.verification.unverified',
      ),
      identifier: identifier,
    );
  }
}

class VerificationStatusLabel extends StatelessWidget {
  final bool verified;
  final String label;
  final String? identifier;

  const VerificationStatusLabel({
    super.key,
    required this.verified,
    required this.label,
    this.identifier,
  });

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final color = verified
        ? (dark ? const Color(0xFF4ADE80) : const Color(0xFF166534))
        : (dark ? const Color(0xFFF5B544) : const Color(0xFFB45309));
    final badge = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          verified ? Icons.check_circle_outline : Icons.error_outline,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color),
        ),
      ],
    );
    return Semantics(
      identifier: identifier,
      label: label,
      excludeSemantics: true,
      child: badge,
    );
  }
}

/// The full-width outlined action for a stored contact.
class VerificationActionButton extends StatelessWidget {
  final String label;
  final String identifier;
  final VoidCallback? onPressed;
  final bool isLoading;

  /// What assistive technology reads instead of [label], e.g. naming the attribute.
  final String? semanticsLabel;

  const VerificationActionButton({
    super.key,
    required this.label,
    required this.identifier,
    required this.onPressed,
    this.isLoading = false,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ThunderAccountColors.of(context);
    return Semantics(
      identifier: identifier,
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: OutlinedButton(
          key: Key(identifier),
          onPressed: isLoading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.text,
            side: BorderSide(color: colors.text, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: isLoading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.text,
                    semanticsLabel: semanticsLabel ?? label,
                  ),
                )
              : Text(
                  label,
                  semanticsLabel: semanticsLabel,
                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
                ),
        ),
      ),
    );
  }
}
