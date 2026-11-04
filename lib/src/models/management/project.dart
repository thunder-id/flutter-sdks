// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'json_reader.dart';

/// A project: a named grouping that applications can belong to (`/projects`).
class Project {
  final String id;

  /// Immutable, human-readable identifier, unique across projects.
  final String handle;
  final String displayName;
  final String? description;
  final String? createdAt;

  const Project({
    required this.id,
    required this.handle,
    required this.displayName,
    this.description,
    this.createdAt,
  });

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: readString(json, 'id'),
        handle: readString(json, 'handle'),
        displayName: readString(json, 'displayName'),
        description: readOptionalString(json, 'description'),
        createdAt: readOptionalString(json, 'createdAt'),
      );
}

/// Payload for creating a [Project]. [id] keeps an identifier another system already uses.
class CreateProjectRequest {
  final String handle;
  final String displayName;
  final String? description;
  final String? id;

  const CreateProjectRequest({required this.handle, required this.displayName, this.description, this.id});

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'handle': handle,
        'displayName': displayName,
        if (description != null) 'description': description,
      };
}

/// Payload for updating a [Project]. The handle cannot change; [handle], when given, must be the
/// current one.
class UpdateProjectRequest {
  final String displayName;
  final String? description;
  final String? handle;

  const UpdateProjectRequest({required this.displayName, this.description, this.handle});

  Map<String, dynamic> toJson() => {
        if (handle != null) 'handle': handle,
        'displayName': displayName,
        if (description != null) 'description': description,
      };
}
