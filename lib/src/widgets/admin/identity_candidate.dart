// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

/// An identity an admin component offers to add, e.g. a user to add to a group.
class IdentityCandidate {
  final String id;
  final String label;

  const IdentityCandidate({required this.id, required this.label});
}

/// An option in an admin component's select field, e.g. a user type.
class AdminSelectOption {
  final String value;
  final String label;

  const AdminSelectOption({required this.value, required this.label});
}
