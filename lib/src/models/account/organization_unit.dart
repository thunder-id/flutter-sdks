// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../management/json_reader.dart';

/// Narrows [ThunderIDClient.getAccessibleOrganizationUnits] relative to the current unit.
enum AccessibleOrganizationUnitScope {
  /// The current unit and the accessible units that share its parent. The parent itself is not
  /// listed; for a top-level unit, its siblings are the other accessible top-level units.
  siblings;

  /// The `scope` query value the server expects.
  String get value => name;
}

/// An organization unit the signed-in user can access: the one the user lives in, or one the user
/// is shared into.
class AccessibleOrganizationUnit {
  final String id;

  /// The unit's handle, unique among its siblings.
  final String handle;
  final String name;
  final String? logoUrl;

  const AccessibleOrganizationUnit({required this.id, required this.handle, required this.name, this.logoUrl});

  factory AccessibleOrganizationUnit.fromJson(Map<String, dynamic> json) => AccessibleOrganizationUnit(
        id: readString(json, 'id'),
        handle: readString(json, 'handle'),
        name: readString(json, 'name'),
        logoUrl: readOptionalString(json, 'logoUrl'),
      );

  @override
  bool operator ==(Object other) =>
      other is AccessibleOrganizationUnit &&
      other.id == id &&
      other.handle == handle &&
      other.name == name &&
      other.logoUrl == logoUrl;

  @override
  int get hashCode => Object.hash(id, handle, name, logoUrl);
}

/// A page of the organization units the signed-in user can access, from `GET /users/me/ous`.
class AccessibleOrganizationUnitList {
  /// The unit the list is relative to: the one the access token was issued for, or the user's own
  /// when the token names none. Returned whatever the scope or page.
  final String current;
  final List<AccessibleOrganizationUnit> organizationUnits;
  final int totalResults;

  /// The 1-based index of the first unit on the page (`offset + 1`).
  final int startIndex;

  /// The number of units on the page.
  final int count;

  const AccessibleOrganizationUnitList({
    required this.current,
    required this.organizationUnits,
    required this.totalResults,
    required this.startIndex,
    required this.count,
  });

  factory AccessibleOrganizationUnitList.fromJson(Map<String, dynamic> json) {
    final units = readList(json, 'organizationUnits')
        .map((item) => AccessibleOrganizationUnit.fromJson(readMap(item)))
        .toList(growable: false);
    return AccessibleOrganizationUnitList(
      current: readString(json, 'current'),
      organizationUnits: units,
      totalResults: readInt(json, 'totalResults', units.length),
      startIndex: readInt(json, 'startIndex', 1),
      count: readInt(json, 'count', units.length),
    );
  }
}

/// The organization unit the signed-in session was issued for, read from its `ouId`, `ouHandle`
/// and `ouName` claims.
///
/// For display only: the claims are decoded, not verified, so never base an authorization decision
/// on them.
class CurrentOrganizationUnit {
  final String id;
  final String? handle;
  final String? name;

  const CurrentOrganizationUnit({required this.id, this.handle, this.name});

  /// Reads the unit from a claim set, or `null` when it carries no `ouId`.
  static CurrentOrganizationUnit? fromClaims(Map<String, dynamic> claims) {
    final id = claims['ouId'];
    if (id is! String || id.isEmpty) return null;
    final handle = claims['ouHandle'];
    final name = claims['ouName'];
    return CurrentOrganizationUnit(
      id: id,
      handle: handle is String && handle.isNotEmpty ? handle : null,
      name: name is String && name.isNotEmpty ? name : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CurrentOrganizationUnit && other.id == id && other.handle == handle && other.name == name;

  @override
  int get hashCode => Object.hash(id, handle, name);
}
