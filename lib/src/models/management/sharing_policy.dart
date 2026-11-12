// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'json_reader.dart';

/// A policy that shares a user or an application from the organization unit that owns it into
/// other units.
///
/// The unit selections are kept as the server describes them: [childUnits] and [otherTreeRoots]
/// are either `{'mode': 'all', 'excludedOuIds': [...]}` or `{'mode': 'selected', 'units': [...]}`,
/// and [allUnits] is `{'excludedOuIds': [...]}`.
class SharingPolicy {
  final String id;
  final String? initiatingOuId;

  /// `share` or `reshare`.
  final String? stage;
  final String? parentPolicyId;
  final bool isReadOnly;

  /// Incremented on every change; an update must name the version it changes.
  final int? version;
  final Map<String, dynamic>? allUnits;
  final Map<String, dynamic>? childUnits;
  final Map<String, dynamic>? otherTreeRoots;

  const SharingPolicy({
    required this.id,
    this.initiatingOuId,
    this.stage,
    this.parentPolicyId,
    this.isReadOnly = false,
    this.version,
    this.allUnits,
    this.childUnits,
    this.otherTreeRoots,
  });

  factory SharingPolicy.fromJson(Map<String, dynamic> json) => SharingPolicy(
        id: readString(json, 'id'),
        initiatingOuId: readOptionalString(json, 'initiatingOuId'),
        stage: readOptionalString(json, 'stage'),
        parentPolicyId: readOptionalString(json, 'parentPolicyId'),
        isReadOnly: readOptionalBool(json, 'isReadOnly') ?? false,
        version: readOptionalInt(json, 'version'),
        allUnits: readOptionalMap(json['allUnits']),
        childUnits: readOptionalMap(json['childUnits']),
        otherTreeRoots: readOptionalMap(json['otherTreeRoots']),
      );
}

/// Payload for creating a sharing policy. See [SharingPolicy] for the unit selections.
class CreateSharingPolicyRequest {
  final String? initiatingOuId;
  final Map<String, dynamic>? childUnits;

  /// Only the `selected` mode applies on create.
  final Map<String, dynamic>? otherTreeRoots;
  final int? version;

  const CreateSharingPolicyRequest({this.initiatingOuId, this.childUnits, this.otherTreeRoots, this.version});

  Map<String, dynamic> toJson() => {
        if (initiatingOuId != null) 'initiatingOuId': initiatingOuId,
        if (childUnits != null) 'childUnits': childUnits,
        if (otherTreeRoots != null) 'otherTreeRoots': otherTreeRoots,
        if (version != null) 'version': version,
      };
}

/// Payload for updating a sharing policy. [version] is the version being changed, so a
/// concurrent change is refused rather than overwritten.
class UpdateSharingPolicyRequest {
  final int version;
  final Map<String, dynamic>? allUnits;
  final Map<String, dynamic>? childUnits;
  final Map<String, dynamic>? otherTreeRoots;

  const UpdateSharingPolicyRequest({required this.version, this.allUnits, this.childUnits, this.otherTreeRoots});

  Map<String, dynamic> toJson() => {
        'version': version,
        if (allUnits != null) 'allUnits': allUnits,
        if (childUnits != null) 'childUnits': childUnits,
        if (otherTreeRoots != null) 'otherTreeRoots': otherTreeRoots,
      };
}

/// What a sharing overlay allows for one attribute in an organization unit.
class OverlayRule {
  final bool? editable;
  final List<String>? value;
  final List<String>? allowedValues;
  final List<String>? excludedValues;

  const OverlayRule({this.editable, this.value, this.allowedValues, this.excludedValues});

  factory OverlayRule.fromJson(Map<String, dynamic> json) => OverlayRule(
        editable: readOptionalBool(json, 'editable'),
        value: readOptionalStringList(json, 'value'),
        allowedValues: readOptionalStringList(json, 'allowedValues'),
        excludedValues: readOptionalStringList(json, 'excludedValues'),
      );
}

/// How a shared user, application or flow appears in one organization unit: whether it is
/// visible there, the policies that put it there, and the rule for each attribute. A flow's rules
/// are keyed `variables.<identifier>`.
class ResolvedOverlay {
  final String? ouId;

  /// Whether the unit owns the resource. The server names it `isOwnedByOU` for every resource, flows
  /// included.
  final bool? isOwnedByOU;
  final bool? visible;
  final List<String> policyIds;
  final Map<String, OverlayRule> rules;

  const ResolvedOverlay({this.ouId, this.isOwnedByOU, this.visible, this.policyIds = const [], this.rules = const {}});

  factory ResolvedOverlay.fromJson(Map<String, dynamic> json) => ResolvedOverlay(
        ouId: readOptionalString(json, 'ouId'),
        isOwnedByOU: readOptionalBool(json, 'isOwnedByOU'),
        visible: readOptionalBool(json, 'visible'),
        policyIds: readStringList(json, 'policyIds'),
        rules: {
          for (final entry in readMap(json['rules']).entries)
            if (entry.value is Map) entry.key: OverlayRule.fromJson(readMap(entry.value)),
        },
      );
}
