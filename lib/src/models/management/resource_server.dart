// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'json_reader.dart';

/// Resource server types.
abstract final class ResourceServerTypes {
  static const String api = 'API';
  static const String mcp = 'MCP';
  static const String custom = 'CUSTOM';
}

/// Action kinds.
abstract final class ResourceActionKinds {
  static const String tool = 'tool';
  static const String resource = 'resource';
}

/// How a resource server's access decisions are made.
class AuthorizationEngineConfig {
  /// `rbac` or `authzen_pdp`.
  final String? type;

  /// The AuthZEN PDP connection, for the `authzen_pdp` engine.
  final String? pdpConnectionId;

  const AuthorizationEngineConfig({this.type, this.pdpConnectionId});

  factory AuthorizationEngineConfig.fromJson(Map<String, dynamic> json) => AuthorizationEngineConfig(
        type: readOptionalString(json, 'type'),
        pdpConnectionId: readOptionalString(readMap(json['properties']), 'pdpConnectionId'),
      );

  Map<String, dynamic> toJson() => {
        if (type != null) 'type': type,
        if (pdpConnectionId != null) 'properties': {'pdpConnectionId': pdpConnectionId},
      };
}

/// A resource server: an API or MCP server whose resources and actions roles grant permissions on.
class ResourceServer {
  final String id;
  final String name;
  final String? description;

  /// The identifier tokens carry as their audience.
  final String identifier;

  /// See [ResourceServerTypes].
  final String type;
  final String ouId;

  /// The separator between the parts of a permission, such as `:`.
  final String delimiter;

  /// Whether a permission covers the permissions beneath it.
  final bool hierarchicalPermissions;
  final AuthorizationEngineConfig? authorizationEngine;
  final bool isReadOnly;

  const ResourceServer({
    required this.id,
    required this.name,
    required this.identifier,
    required this.type,
    required this.ouId,
    required this.delimiter,
    this.hierarchicalPermissions = false,
    this.description,
    this.authorizationEngine,
    this.isReadOnly = false,
  });

  factory ResourceServer.fromJson(Map<String, dynamic> json) => ResourceServer(
        id: readString(json, 'id'),
        name: readString(json, 'name'),
        description: readOptionalString(json, 'description'),
        identifier: readString(json, 'identifier'),
        type: readString(json, 'type'),
        ouId: readString(json, 'ouId'),
        delimiter: readString(json, 'delimiter'),
        hierarchicalPermissions: readOptionalBool(json, 'hierarchicalPermissions') ?? false,
        authorizationEngine: json['authorizationEngine'] is Map
            ? AuthorizationEngineConfig.fromJson(readMap(json['authorizationEngine']))
            : null,
        isReadOnly: readOptionalBool(json, 'isReadOnly') ?? false,
      );
}

/// Payload for creating a resource server.
class CreateResourceServerRequest {
  final String name;
  final String identifier;
  final String ouId;
  final String? description;

  /// See [ResourceServerTypes]. The server defaults it when omitted.
  final String? type;
  final String? delimiter;
  final bool? hierarchicalPermissions;

  const CreateResourceServerRequest({
    required this.name,
    required this.identifier,
    required this.ouId,
    this.description,
    this.type,
    this.delimiter,
    this.hierarchicalPermissions,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'identifier': identifier,
        'ouId': ouId,
        if (description != null) 'description': description,
        if (type != null) 'type': type,
        if (delimiter != null) 'delimiter': delimiter,
        if (hierarchicalPermissions != null) 'hierarchicalPermissions': hierarchicalPermissions,
      };
}

/// Payload for updating a resource server.
class UpdateResourceServerRequest {
  final String name;
  final String ouId;
  final String? description;
  final String? identifier;
  final AuthorizationEngineConfig? authorizationEngine;

  const UpdateResourceServerRequest({
    required this.name,
    required this.ouId,
    this.description,
    this.identifier,
    this.authorizationEngine,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'ouId': ouId,
        if (description != null) 'description': description,
        if (identifier != null) 'identifier': identifier,
        if (authorizationEngine != null) 'authorizationEngine': authorizationEngine!.toJson(),
      };
}

/// A resource of a resource server.
class ManagedResource {
  final String id;
  final String name;
  final String handle;
  final String? description;

  /// The parent resource, when the resource is nested.
  final String? parent;

  /// The permission the resource grants, built from the handles on its path.
  final String permission;

  const ManagedResource({
    required this.id,
    required this.name,
    required this.handle,
    required this.permission,
    this.description,
    this.parent,
  });

  factory ManagedResource.fromJson(Map<String, dynamic> json) => ManagedResource(
        id: readString(json, 'id'),
        name: readString(json, 'name'),
        handle: readString(json, 'handle'),
        description: readOptionalString(json, 'description'),
        parent: readOptionalString(json, 'parent'),
        permission: readString(json, 'permission'),
      );
}

/// Payload for creating a resource.
class CreateResourceRequest {
  final String name;
  final String handle;
  final String? description;
  final String? parent;

  const CreateResourceRequest({required this.name, required this.handle, this.description, this.parent});

  Map<String, dynamic> toJson() => {
        'name': name,
        'handle': handle,
        if (description != null) 'description': description,
        if (parent != null) 'parent': parent,
      };
}

/// Payload for updating a resource or an action: only the name and description can change.
class UpdateResourceRequest {
  final String? name;
  final String? description;

  const UpdateResourceRequest({this.name, this.description});

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (description != null) 'description': description,
      };
}

/// An action on a resource server or on one of its resources.
class ResourceAction {
  final String id;
  final String name;
  final String handle;
  final String? description;

  /// The permission the action grants.
  final String permission;

  /// See [ResourceActionKinds].
  final String? kind;

  const ResourceAction({
    required this.id,
    required this.name,
    required this.handle,
    required this.permission,
    this.description,
    this.kind,
  });

  factory ResourceAction.fromJson(Map<String, dynamic> json) => ResourceAction(
        id: readString(json, 'id'),
        name: readString(json, 'name'),
        handle: readString(json, 'handle'),
        description: readOptionalString(json, 'description'),
        permission: readString(json, 'permission'),
        kind: readOptionalString(json, 'kind'),
      );
}

/// Payload for creating an action.
class CreateActionRequest {
  final String name;
  final String handle;
  final String? description;

  /// See [ResourceActionKinds].
  final String? kind;

  const CreateActionRequest({required this.name, required this.handle, this.description, this.kind});

  Map<String, dynamic> toJson() => {
        'name': name,
        'handle': handle,
        if (description != null) 'description': description,
        if (kind != null) 'kind': kind,
      };
}

/// Payload for updating an action.
typedef UpdateActionRequest = UpdateResourceRequest;
