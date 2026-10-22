// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'json_reader.dart';

/// An agent record administered through the management API.
///
/// A record read from a list carries only the basic fields (id, name, type, OU, client id,
/// description); read it by id for the rest.
class Agent {
  final String id;
  final String name;
  final String ouId;

  /// The agent type handle.
  final String type;
  final String? ouHandle;
  final String? description;
  final String? clientId;
  final String? owner;
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

  const Agent({
    required this.id,
    required this.name,
    required this.ouId,
    required this.type,
    this.ouHandle,
    this.description,
    this.clientId,
    this.owner,
    this.logoUrl,
    this.isReadOnly = false,
    this.attributes = const {},
    this.allowedAgentTypes,
    this.allowedUserTypes,
    this.authFlowId,
    this.registrationFlowId,
    this.isRegistrationFlowEnabled,
    this.inboundAuthConfig = const [],
  });

  factory Agent.fromJson(Map<String, dynamic> json) => Agent(
        id: readString(json, 'id'),
        name: readString(json, 'name'),
        ouId: readString(json, 'ouId'),
        type: readString(json, 'type'),
        ouHandle: readOptionalString(json, 'ouHandle'),
        description: readOptionalString(json, 'description'),
        clientId: readOptionalString(json, 'clientId'),
        owner: readOptionalString(json, 'owner'),
        logoUrl: readOptionalString(json, 'logoUrl'),
        isReadOnly: readOptionalBool(json, 'isReadOnly') ?? false,
        attributes: readMap(json['attributes']),
        allowedAgentTypes: readOptionalStringList(json, 'allowedAgentTypes'),
        allowedUserTypes: readOptionalStringList(json, 'allowedUserTypes'),
        authFlowId: readOptionalString(json, 'authFlowId'),
        registrationFlowId: readOptionalString(json, 'registrationFlowId'),
        isRegistrationFlowEnabled: readOptionalBool(json, 'isRegistrationFlowEnabled'),
        inboundAuthConfig: readList(json, 'inboundAuthConfig').map(readMap).toList(growable: false),
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
  final String? owner;
  final String? logoUrl;
  final Map<String, dynamic>? attributes;
  final List<Map<String, dynamic>>? inboundAuthConfig;

  const CreateAgentRequest({
    required this.name,
    required this.ouId,
    required this.type,
    this.description,
    this.owner,
    this.logoUrl,
    this.attributes,
    this.inboundAuthConfig,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'ouId': ouId,
        'type': type,
        if (description != null) 'description': description,
        if (owner != null) 'owner': owner,
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
  final String? owner;
  final String? logoUrl;
  final Map<String, dynamic>? attributes;
  final List<String>? allowedAgentTypes;
  final List<String>? allowedUserTypes;
  final String? authFlowId;
  final String? registrationFlowId;
  final bool? isRegistrationFlowEnabled;
  final List<Map<String, dynamic>>? inboundAuthConfig;

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
  });

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (ouId != null) 'ouId': ouId,
        if (type != null) 'type': type,
        if (description != null) 'description': description,
        if (owner != null) 'owner': owner,
        if (logoUrl != null) 'logoUrl': logoUrl,
        if (attributes != null) 'attributes': attributes,
        if (allowedAgentTypes != null) 'allowedAgentTypes': allowedAgentTypes,
        if (allowedUserTypes != null) 'allowedUserTypes': allowedUserTypes,
        if (authFlowId != null) 'authFlowId': authFlowId,
        if (registrationFlowId != null) 'registrationFlowId': registrationFlowId,
        if (isRegistrationFlowEnabled != null) 'isRegistrationFlowEnabled': isRegistrationFlowEnabled,
        if (inboundAuthConfig != null) 'inboundAuthConfig': inboundAuthConfig,
      };
}
