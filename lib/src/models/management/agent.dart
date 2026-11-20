// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'access_status.dart';
import 'json_reader.dart';

/// The kind of an agent: a category set when the agent is created and never changed, which can add
/// rules of its own to the agent. `null` on an agent means an ordinary agent. A kind this SDK does
/// not know keeps its raw value.
abstract final class AgentKind {
  /// A personal agent: one that acts only for its owner, a user.
  static const String personal = 'personal-assistant';
}

/// What an [AgentOwner.id] holds. A type this SDK does not know keeps its raw value.
abstract final class AgentOwnerIdType {
  static const String uuid = 'uuid';
  static const String email = 'email';
  static const String mobile = 'mobile';
}

/// The person accountable for an agent. A local owner is an entity of the same deployment and is
/// named by its entity ID. An owner managed in another identity system is not looked up.
class AgentOwner {
  final String id;

  /// One of [AgentOwnerIdType]. `null` reads as [AgentOwnerIdType.uuid], and a local owner must be
  /// one.
  final String? idType;

  /// Whether the owner is an entity of this deployment. `null` reads as `true`.
  final bool? isLocal;

  const AgentOwner({required this.id, this.idType, this.isLocal});

  /// Reads an `owner` object, or returns `null` when [json] is not one or carries no ID.
  static AgentOwner? maybeFromJson(Object? json) {
    if (json is! Map) return null;
    final map = readMap(json);
    final id = readOptionalString(map, 'id');
    if (id == null || id.isEmpty) return null;
    return AgentOwner(id: id, idType: readOptionalString(map, 'idType'), isLocal: readOptionalBool(map, 'isLocal'));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (idType != null) 'idType': idType,
        if (isLocal != null) 'isLocal': isLocal,
      };
}

/// An agent record administered through the management API.
///
/// A record read from a list carries only the basic fields (id, name, type, OU, client id,
/// description); read it by id for the rest.
class Agent {
  final String id;

  /// The agent's name: its display attribute when the server resolves one, otherwise its `name`
  /// attribute. Empty when it has neither.
  final String name;
  final String ouId;

  /// The agent type handle.
  final String type;
  final String? ouHandle;
  final String? description;
  final String? clientId;
  final AgentOwner? owner;

  /// One of [AgentKind], set when the agent is created and never changed. `null` for an ordinary
  /// agent.
  final String? kind;
  final String? logoUrl;
  final bool isReadOnly;
  final Map<String, dynamic> attributes;
  final List<String>? allowedAgentTypes;
  final List<String>? allowedUserTypes;
  final String? authFlowId;
  final String? registrationFlowId;
  final bool? isRegistrationFlowEnabled;

  /// Inbound authentication configuration exactly as the server returned it.
  final List<Map<String, dynamic>> inboundAuthConfig;

  /// The effective access status, set by the server on a read.
  final AccessStatus? status;

  const Agent({
    required this.id,
    required this.name,
    required this.ouId,
    required this.type,
    this.ouHandle,
    this.description,
    this.clientId,
    this.owner,
    this.kind,
    this.logoUrl,
    this.isReadOnly = false,
    this.attributes = const {},
    this.allowedAgentTypes,
    this.allowedUserTypes,
    this.authFlowId,
    this.registrationFlowId,
    this.isRegistrationFlowEnabled,
    this.inboundAuthConfig = const [],
    this.status,
  });

  factory Agent.fromJson(Map<String, dynamic> json) => Agent(
        id: readString(json, 'id'),
        name: [
              readOptionalString(json, 'display'),
              readOptionalString(readMap(json['attributes']), 'name'),
              readOptionalString(json, 'name'),
            ].firstWhere((name) => name != null && name.isNotEmpty, orElse: () => null) ??
            readString(json, 'id'),
        ouId: readString(json, 'ouId'),
        type: readString(json, 'type'),
        ouHandle: readOptionalString(json, 'ouHandle'),
        description: readOptionalString(json, 'description'),
        clientId: readOptionalString(json, 'clientId'),
        owner: AgentOwner.maybeFromJson(json['owner']),
        kind: readOptionalString(json, 'kind'),
        logoUrl: readOptionalString(json, 'logoUrl'),
        isReadOnly: readOptionalBool(json, 'isReadOnly') ?? false,
        attributes: readMap(json['attributes']),
        allowedAgentTypes: readOptionalStringList(json, 'allowedAgentTypes'),
        allowedUserTypes: readOptionalStringList(json, 'allowedUserTypes'),
        authFlowId: readOptionalString(json, 'authFlowId'),
        registrationFlowId: readOptionalString(json, 'registrationFlowId'),
        isRegistrationFlowEnabled: readOptionalBool(json, 'isRegistrationFlowEnabled'),
        inboundAuthConfig: readList(json, 'inboundAuthConfig').map(readMap).toList(growable: false),
        status: AccessStatus.maybeFromJson(json['status']),
      );
}

/// An agent type an [Agent] can be registered as.
class AgentType {
  final String id;
  final String handle;
  final String displayName;
  final String ouId;
  final String? ouHandle;
  final bool? allowSelfRegistration;

  const AgentType({
    required this.id,
    required this.handle,
    required this.displayName,
    required this.ouId,
    this.ouHandle,
    this.allowSelfRegistration,
  });

  factory AgentType.fromJson(Map<String, dynamic> json) => AgentType(
        id: readString(json, 'id'),
        handle: readString(json, 'handle'),
        displayName: readOptionalString(json, 'displayName') ?? readString(json, 'handle'),
        ouId: readString(json, 'ouId'),
        ouHandle: readOptionalString(json, 'ouHandle'),
        allowSelfRegistration: readOptionalBool(json, 'allowSelfRegistration'),
      );
}

/// Payload for registering an [Agent].
class CreateAgentRequest {
  final String name;
  final String ouId;
  final String type;
  final String? description;
  final AgentOwner? owner;

  /// One of [AgentKind], fixed once the agent is created. Leave it `null` for an ordinary agent. A
  /// kind can add requirements of its own: [AgentKind.personal] requires [owner] to name a local
  /// user.
  final String? kind;
  final String? logoUrl;
  final Map<String, dynamic>? attributes;
  final List<Map<String, dynamic>>? inboundAuthConfig;

  const CreateAgentRequest({
    required this.name,
    required this.ouId,
    required this.type,
    this.description,
    this.owner,
    this.kind,
    this.logoUrl,
    this.attributes,
    this.inboundAuthConfig,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'ouId': ouId,
        'type': type,
        if (description != null) 'description': description,
        if (owner != null) 'owner': owner!.toJson(),
        if (kind != null) 'kind': kind,
        if (logoUrl != null) 'logoUrl': logoUrl,
        if (attributes != null) 'attributes': attributes,
        if (inboundAuthConfig != null) 'inboundAuthConfig': inboundAuthConfig,
      };
}

/// Payload for updating an [Agent]. Only the fields that are set are sent.
class UpdateAgentRequest {
  final String? name;
  final String? ouId;
  final String? type;
  final String? description;
  final AgentOwner? owner;
  final String? logoUrl;
  final Map<String, dynamic>? attributes;
  final List<String>? allowedAgentTypes;
  final List<String>? allowedUserTypes;
  final String? authFlowId;
  final String? registrationFlowId;
  final bool? isRegistrationFlowEnabled;
  final List<Map<String, dynamic>>? inboundAuthConfig;

  /// Whether the agent acts on behalf of a signed-in user. The server does not store it, so a full
  /// update sends it for the agent to be held to the delegated grant rules.
  final bool? delegated;

  const UpdateAgentRequest({
    this.name,
    this.ouId,
    this.type,
    this.description,
    this.owner,
    this.logoUrl,
    this.attributes,
    this.allowedAgentTypes,
    this.allowedUserTypes,
    this.authFlowId,
    this.registrationFlowId,
    this.isRegistrationFlowEnabled,
    this.inboundAuthConfig,
    this.delegated,
  });

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (ouId != null) 'ouId': ouId,
        if (type != null) 'type': type,
        if (description != null) 'description': description,
        if (owner != null) 'owner': owner!.toJson(),
        if (logoUrl != null) 'logoUrl': logoUrl,
        if (attributes != null) 'attributes': attributes,
        if (allowedAgentTypes != null) 'allowedAgentTypes': allowedAgentTypes,
        if (allowedUserTypes != null) 'allowedUserTypes': allowedUserTypes,
        if (authFlowId != null) 'authFlowId': authFlowId,
        if (registrationFlowId != null) 'registrationFlowId': registrationFlowId,
        if (isRegistrationFlowEnabled != null) 'isRegistrationFlowEnabled': isRegistrationFlowEnabled,
        if (inboundAuthConfig != null) 'inboundAuthConfig': inboundAuthConfig,
        if (delegated != null) 'delegated': delegated,
      };
}

/// The result of `regenerateAgentSecret`.
class RegenerateAgentSecretResult {
  /// The agent after the change.
  final Agent agent;

  /// The new client secret. This is the only time it can be read.
  final String clientSecret;

  const RegenerateAgentSecretResult({required this.agent, required this.clientSecret});
}
