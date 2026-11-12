// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'flow_variable.dart';
import 'json_reader.dart';

/// Flow type values a flow definition can have.
abstract final class FlowTypes {
  static const String authentication = 'AUTHENTICATION';
  static const String registration = 'REGISTRATION';
}

List<Map<String, dynamic>> _readNodes(Map<String, dynamic> json) =>
    readList(json, 'nodes').whereType<Map<Object?, Object?>>().map(readMap).toList(growable: false);

/// A flow definition with its graph. [nodes] are kept as the server describes them (`id`,
/// `type`, `prompts`, `executor`, `onSuccess`, ...), so they can be edited and sent back as they
/// are.
class FlowDefinition {
  final String id;
  final String name;
  final String handle;

  /// See [FlowTypes].
  final String flowType;
  final int activeVersion;
  final bool isReadOnly;
  final List<Map<String, dynamic>> nodes;
  final String? createdAt;
  final String? updatedAt;

  /// The organization unit the flow was requested for, when it was.
  final String? ouId;

  /// Whether the organization unit the flow was requested for owns it.
  final bool? isOwnedByOU;

  /// Set on a flow shared with the requested organization unit, which comes back as its variables
  /// only. A flow the unit owns declares them on its `VARIABLES` node instead; see
  /// `getFlowVariableDefinitions`.
  final List<FlowVariableDefinition>? variables;

  const FlowDefinition({
    required this.id,
    required this.name,
    required this.handle,
    required this.flowType,
    this.activeVersion = 0,
    this.isReadOnly = false,
    this.nodes = const [],
    this.createdAt,
    this.updatedAt,
    this.ouId,
    this.isOwnedByOU,
    this.variables,
  });

  factory FlowDefinition.fromJson(Map<String, dynamic> json) => FlowDefinition(
        id: readString(json, 'id'),
        name: readString(json, 'name'),
        handle: readString(json, 'handle'),
        flowType: readString(json, 'flowType'),
        activeVersion: readInt(json, 'activeVersion'),
        isReadOnly: readOptionalBool(json, 'isReadOnly') ?? false,
        nodes: _readNodes(json),
        createdAt: readOptionalString(json, 'createdAt'),
        updatedAt: readOptionalString(json, 'updatedAt'),
        ouId: readOptionalString(json, 'ouId'),
        isOwnedByOU: readOptionalBool(json, 'isOwnedByOU'),
        variables: json['variables'] is List
            ? readList(json, 'variables')
                .map(FlowVariableDefinition.tryParse)
                .whereType<FlowVariableDefinition>()
                .toList(growable: false)
            : null,
      );
}

/// Payload for creating or updating a flow definition. An update saves a new version.
class FlowDefinitionRequest {
  final String name;
  final String handle;

  /// See [FlowTypes].
  final String flowType;
  final List<Map<String, dynamic>> nodes;

  const FlowDefinitionRequest({
    required this.name,
    required this.handle,
    required this.flowType,
    required this.nodes,
  });

  Map<String, dynamic> toJson() => {'name': name, 'handle': handle, 'flowType': flowType, 'nodes': nodes};
}

/// The payload used to create a flow.
typedef CreateFlowRequest = FlowDefinitionRequest;

/// The payload used to update a flow.
typedef UpdateFlowRequest = FlowDefinitionRequest;

/// One saved version of a flow, as listed.
class FlowVersionInfo {
  final int version;
  final String? createdAt;
  final bool isActive;

  const FlowVersionInfo({required this.version, this.createdAt, this.isActive = false});

  factory FlowVersionInfo.fromJson(Map<String, dynamic> json) => FlowVersionInfo(
        version: readInt(json, 'version'),
        createdAt: readOptionalString(json, 'createdAt'),
        isActive: readOptionalBool(json, 'isActive') ?? false,
      );
}

/// A flow's version history.
class FlowVersions {
  final int totalVersions;
  final List<FlowVersionInfo> versions;

  const FlowVersions({required this.totalVersions, this.versions = const []});

  factory FlowVersions.fromJson(Map<String, dynamic> json) {
    final versions =
        readList(json, 'versions').map((item) => FlowVersionInfo.fromJson(readMap(item))).toList(growable: false);
    return FlowVersions(totalVersions: readInt(json, 'totalVersions', versions.length), versions: versions);
  }
}

/// One saved version of a flow, with its graph.
class FlowVersion {
  final String id;
  final String name;
  final String handle;
  final String flowType;
  final int version;
  final bool isActive;
  final List<Map<String, dynamic>> nodes;
  final String? createdAt;

  const FlowVersion({
    required this.id,
    required this.name,
    required this.handle,
    required this.flowType,
    required this.version,
    this.isActive = false,
    this.nodes = const [],
    this.createdAt,
  });

  factory FlowVersion.fromJson(Map<String, dynamic> json) => FlowVersion(
        id: readString(json, 'id'),
        name: readString(json, 'name'),
        handle: readString(json, 'handle'),
        flowType: readString(json, 'flowType'),
        version: readInt(json, 'version'),
        isActive: readOptionalBool(json, 'isActive') ?? false,
        nodes: _readNodes(json),
        createdAt: readOptionalString(json, 'createdAt'),
      );
}
