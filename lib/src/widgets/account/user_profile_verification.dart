// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import '../../i18n/thunderid_i18n.dart';
import '../../models/attribute_verification.dart';
import '../../models/user_profile.dart' as model;
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

/// [verifiedAt] in the active locale's date and time, or as it came when it is not a timestamp.
String formatVerifiedAt(BuildContext context, String verifiedAt) {
  final parsed = DateTime.tryParse(verifiedAt);
  final localizations =
      Localizations.of<MaterialLocalizations>(context, MaterialLocalizations);
  if (parsed == null || localizations == null) return verifiedAt;
  final local = parsed.toLocal();
  return '${localizations.formatFullDate(local)} ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

/// A Verified or Unverified badge. When the server reports when the value was verified, the time is
/// part of the badge's accessible label, so a screen reader announces it, and a long press shows it.
class VerificationStatusBadge extends StatelessWidget {
  final AttributeVerificationStatus status;
  final String? verifiedAt;
  final ThunderIDI18n i18n;

  /// Exposed to the platform accessibility tree, for an external driver.
  final String? identifier;

  const VerificationStatusBadge({
    super.key,
    required this.status,
    required this.i18n,
    this.verifiedAt,
    this.identifier,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ThunderAccountColors.of(context);
    final verified = status == AttributeVerificationStatus.verified;
    final label = i18n.resolve(
      verified
          ? 'userProfile.verification.verified'
          : 'userProfile.verification.unverified',
    );
    final at = verifiedAt;
    final atText = verified && at != null
        ? i18n
            .resolve('userProfile.verification.verifiedAt')
            .replaceAll('{date}', formatVerifiedAt(context, at))
        : null;
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: verified ? colors.pillBackground : null,
        border: Border.all(
          color: verified ? colors.pillBackground : colors.inputBorder,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: verified ? colors.pillText : colors.textSecondary,
        ),
      ),
    );
    return Semantics(
      identifier: identifier,
      label: atText == null ? label : '$label. $atText',
      excludeSemantics: true,
      child: atText == null ? badge : Tooltip(message: atText, child: badge),
    );
  }
}
