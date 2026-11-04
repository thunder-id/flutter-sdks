// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import '../../thunderid_provider.dart';

// Package-internal (not exported): where ApplicationCreate and AgentCreate place a new resource.

/// Where a new application or agent goes: an organization unit, or a project (whose root
/// organization unit the server places it in). Exactly one of [ouId] and [projectId] is set.
class CreatePlacement {
  final String? ouId;
  final String? projectId;

  const CreatePlacement._({this.ouId, this.projectId});

  /// The organization unit the app passed; else the current project, when one is chosen; else the
  /// signed-in user's own organization unit. `null` when there is none of them.
  ///
  /// A project is not an organization unit: its id is only ever sent as `projectId`.
  static CreatePlacement? of(String? ouId, ThunderIDState? thunder) {
    if (ouId != null) return CreatePlacement._(ouId: ouId);
    final projectId = thunder?.currentProject?.id;
    if (projectId != null) return CreatePlacement._(projectId: projectId);
    final userOuId = thunder?.defaultOuId;
    return userOuId == null ? null : CreatePlacement._(ouId: userOuId);
  }
}
