// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

import '../../../models/attribute_verification.dart';
import '../../../models/management/administration.dart';
import '../../../models/management/entity_type.dart';
import '../../../models/management/managed_user.dart';
import '../../account/user_profile_verification.dart';
import 'admin_context.dart';
import 'admin_parts.dart';

// Package-internal (not exported): the administrator-initiated verification parts of the user
// details.

/// The schema type of [name] in [schema], lower-cased, or `null` when the schema does not define it.
String? _schemaType(EntityTypeSchema? schema, String name) {
  final property = schema?[name];
  final type = property is Map ? property['type'] : null;
  return type is String ? type.toLowerCase() : null;
}

bool _isCredential(EntityTypeSchema? schema, String name) {
  final property = schema?[name];
  return property is Map && property['credential'] == true;
}

/// The visible, non-credential attributes of [user] with a non-empty text value that already have a
/// verification record or whose [schema] type is email or mobile, sorted. Empty unless the server
/// reports the user's verified attributes.
List<String> adminVerifiableAttributes(ManagedUser? user, EntityTypeSchema? schema, Set<String> hiddenAttributes) {
  final records = user?.verifiedAttributes;
  if (user == null || records == null) return const [];
  return [
    for (final entry in user.attributes.entries)
      if (!hiddenAttributes.contains(entry.key) &&
          !_isCredential(schema, entry.key) &&
          entry.value is String &&
          (entry.value as String).trim().isNotEmpty &&
          (records.containsKey(entry.key) ||
              AttributeVerification.verifiableAttributeTypes.contains(_schemaType(schema, entry.key))))
        entry.key,
  ]..sort();
}

/// The [verifiable] attributes of [user] a link can be sent for: email-typed in [schema] and not yet
/// verified. Empty for a read-only user or when [canSend] is false.
Set<String> adminSendableAttributes(
  ManagedUser? user,
  EntityTypeSchema? schema,
  List<String> verifiable, {
  required bool canSend,
}) {
  if (user == null || user.isReadOnly || !canSend) return const {};
  return {
    for (final name in verifiable)
      if (_schemaType(schema, name) == 'email' && user.verifiedAttributes?[name] == null) name,
  };
}

/// The handle of the administrator-initiated verification flow to send a link through, or `null`
/// when the action is off or the server names none.
String? adminVerificationFlowHandle({required bool enabled, Map<String, String>? configuredFlows}) {
  final handle = configuredFlows?[AdministrationFlowConfigKey.adminAttributeVerification];
  return enabled && handle != null && handle.isNotEmpty ? handle : null;
}

/// The user type to read for verification status, only while the verification action is on and the
/// server reports the user's verified attributes.
String? verificationUserTypeHandle(ManagedUser? user, {required bool attributeVerification}) =>
    attributeVerification && user != null && user.verifiedAttributes != null ? user.type : null;

/// The message for a sent verification link, naming its masked destination when the flow reports
/// one.
String verificationSentMessage(AdminContext ac, UserAttributeVerificationResult result) {
  final destination = result.maskedDestination;
  return destination == null || destination.isEmpty
      ? ac.t('admin.users.details.verification.sent_generic')
      : ac.t('admin.users.details.verification.sent', {'destination': destination});
}

/// A translated success message, announced to assistive technology when it appears.
class AdminNotice extends StatelessWidget {
  final AdminContext ac;
  final String message;

  /// The notice's identifier, also its widget key.
  final String identifier;

  const AdminNotice({super.key, required this.ac, required this.message, required this.identifier});

  @override
  Widget build(BuildContext context) => Semantics(
        identifier: identifier,
        liveRegion: true,
        child: Container(
          key: Key(identifier),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: ac.colors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: ac.colors.primary.withValues(alpha: 0.4)),
          ),
          child: Text(message, style: TextStyle(color: ac.colors.text)),
        ),
      );
}

/// An attribute with its verification status and, when [onSend] is set, the action that sends the
/// user a verification link. Identified `thunderid-admin-<block>-verification-status-<name>` and
/// `thunderid-action-<block>-verification-send-<name>`.
class AdminAttributeVerificationRow extends StatelessWidget {
  final AdminContext ac;
  final String block;
  final String name;
  final String value;
  final bool isVerified;
  final bool isSending;
  final bool isUpdating;
  final VoidCallback? onSend;

  const AdminAttributeVerificationRow({
    super.key,
    required this.ac,
    required this.block,
    required this.name,
    required this.value,
    required this.isVerified,
    this.isSending = false,
    this.isUpdating = false,
    this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final status = 'thunderid-admin-$block-verification-status-$name';
    final onSend = this.onSend;
    final verify = ac.t('admin.users.details.verification.verify');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AdminDetailList(ac: ac, items: [(name, Text(value))]),
        VerificationStatusLabel(
          key: Key(status),
          verified: isVerified,
          label: ac.t(
            isVerified
                ? 'admin.users.details.verification.status.verified'
                : 'admin.users.details.verification.status.unverified',
          ),
          identifier: status,
        ),
        if (onSend != null) ...[
          const SizedBox(height: 8),
          VerificationActionButton(
            label: verify,
            semanticsLabel: '$verify $name',
            identifier: 'thunderid-action-$block-verification-send-$name',
            isLoading: isSending,
            onPressed: isUpdating ? null : onSend,
          ),
        ],
      ],
    );
  }
}
