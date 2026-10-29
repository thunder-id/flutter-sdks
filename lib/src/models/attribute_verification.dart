// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'user_profile.dart';

/// Wire names and eligibility rules for self user attribute verification, which
/// [ThunderIDClient.verifyAttribute] runs as a `SELF_SERVICE` flow.
class AttributeVerification {
  AttributeVerification._();

  /// Handle of the self attribute verification flow the server ships, used unless the app names another.
  static const String defaultFlowHandle =
      'default-self-attribute-verification-flow';

  /// Flow input naming the attribute to verify on the initiating request.
  static const String attributeInput = 'attribute';

  /// `additionalData` key carrying the masked destination the code or link was sent to.
  static const String maskedDestinationKey = 'maskedDestination';

  /// `additionalData` key carrying the length of the code that was sent.
  static const String codeLengthKey = 'otpLength';

  /// `additionalData` key carrying the channel the code or link was sent on.
  static const String channelKey = 'channel';

  /// The `additionalData` keys a later step keeps from the step that sent the code, since a rejected code
  /// comes back without them. Every other key comes from the current step only.
  static const Set<String> carriedForwardKeys = {
    maskedDestinationKey,
    channelKey,
    codeLengthKey,
  };

  /// Schema property types whose verification status is shown, and which the user can verify.
  static const Set<String> verifiableAttributeTypes = {'email', 'mobile'};

  /// Schema property types whose changed value opens verification after a save. Mobile is verified on
  /// request only, since sending an SMS needs a provider the deployment may not have.
  static const Set<String> verifyAfterSaveAttributeTypes = {'email'};

  /// Whether [attribute] is a top-level, single-valued property of type `email` or `mobile` in the
  /// user schema from `GET /users/me/meta`.
  ///
  /// Schema keys are top-level properties, and a multi-valued property has type `array`, so the
  /// property's own type settles both. An absent schema, or one without the attribute, resolves to
  /// false, so no verification starts on missing information.
  static bool isVerifiableAttribute(
    String attribute,
    Map<String, AttributeSchema>? schema,
  ) =>
      isVerifiableType(schema?[attribute]?.type);

  /// Whether a schema property of [type] shows a verification status and can be verified.
  static bool isVerifiableType(String? type) =>
      type != null && verifiableAttributeTypes.contains(type.toLowerCase());

  /// Whether a saved change to a schema property of [type] opens verification by itself.
  static bool opensAfterSave(String? type) =>
      type != null &&
      verifyAfterSaveAttributeTypes.contains(type.toLowerCase());
}

/// The verification record of one of the user's attributes, as `GET /users/me` returns it.
class VerifiedAttribute {
  /// When the attribute's current value was verified, as an RFC 3339 timestamp.
  final String? verifiedAt;

  const VerifiedAttribute({this.verifiedAt});

  factory VerifiedAttribute.fromMap(Map<dynamic, dynamic> map) =>
      VerifiedAttribute(verifiedAt: map['verifiedAt'] as String?);

  @override
  bool operator ==(Object other) =>
      other is VerifiedAttribute && other.verifiedAt == verifiedAt;

  @override
  int get hashCode => verifiedAt.hashCode;
}
