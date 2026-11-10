// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import '../../i18n/thunderid_i18n.dart';
import '../../models/attribute_verification.dart';
import '../../models/user_profile.dart' as model;

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

/// Whether saving [name] opens its verification by itself: only for a changed `email` the saved
/// profile stores and reports unverified. An absent `verifiedAttributes` leaves the status unknown,
/// so nothing opens on that basis; a mobile number is verified on request only.
bool shouldVerifyAfterSave({
  required String name,
  required Map<String, model.AttributeSchema> schema,
  required Object? previousValue,
  required model.UserProfile saved,
}) {
  final stored = saved.attributes[name];
  final verified = saved.verifiedAttributes;
  return AttributeVerification.opensAfterSave(schema[name]?.type) &&
      AttributeVerification.isVerifiableAttribute(name, schema) &&
      stored is String &&
      stored.trim().isNotEmpty &&
      stored != previousValue &&
      verified != null &&
      !verified.containsKey(name);
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
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final verified = status == AttributeVerificationStatus.verified;
    final label = i18n.resolve(
      verified
          ? 'userProfile.verification.verified'
          : 'userProfile.verification.unverified',
    );
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
