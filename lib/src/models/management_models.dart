// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

/// The fields of an application that a caller can set. Used to create and to update
/// an application.
///
/// Fields without a named parameter, such as `inboundAuthConfig`, go in [extra] with
/// the same JSON shape the management API uses.
class ApplicationRequest {
  final Map<String, dynamic> fields;

  ApplicationRequest({
    required String name,
    String? description,
    String? url,
    String? logoUrl,
    String? type,
    String? template,
    String? ouId,
    Map<String, dynamic> extra = const {},
  }) : fields = {
          ...extra,
          'name': name,
          if (description != null) 'description': description,
          if (url != null) 'url': url,
          if (logoUrl != null) 'logoUrl': logoUrl,
          if (type != null) 'type': type,
          if (template != null) 'template': template,
          if (ouId != null) 'ouId': ouId,
        };

  const ApplicationRequest.fromFields(this.fields);

  Map<String, dynamic> toMap() => fields;
}

/// An application registered in ThunderID.
class Application {
  final String id;
  final String name;
  final String? description;
  final String? url;
  final String? logoUrl;
  final String? type;
  final String? template;
  final String? ouId;
  final bool isReadOnly;
  final String? createdAt;
  final String? updatedAt;

  /// Every field the server returned, including nested configuration.
  final Map<String, dynamic> data;

  const Application({
    required this.id,
    required this.name,
    this.description,
    this.url,
    this.logoUrl,
    this.type,
    this.template,
    this.ouId,
    this.isReadOnly = false,
    this.createdAt,
    this.updatedAt,
    this.data = const {},
  });

  factory Application.fromMap(Map<dynamic, dynamic> map) {
    final data = _normalizeMap(map);
    return Application(
      id: data['id'] as String? ?? '',
      name: data['name'] as String? ?? '',
      description: data['description'] as String?,
      url: data['url'] as String?,
      logoUrl: data['logoUrl'] as String?,
      type: data['type'] as String?,
      template: data['template'] as String?,
      ouId: data['ouId'] as String?,
      isReadOnly: data['isReadOnly'] as bool? ?? false,
      createdAt: data['createdAt'] as String?,
      updatedAt: data['updatedAt'] as String?,
      data: data,
    );
  }

  /// The caller-settable fields of this application, ready to send back through
  /// `ApplicationsClient.update`. An update replaces the application's mutable fields.
  ApplicationRequest toRequest() => ApplicationRequest.fromFields(
        Map.of(data)..removeWhere((key, _) => key == 'id' || key == 'createdAt' || key == 'updatedAt'),
      );
}

/// The summary of an application returned in list responses.
class BasicApplication {
  final String id;
  final String name;
  final String? description;
  final String? logoUrl;
  final String? type;
  final String? template;
  final String? clientId;
  final bool isReadOnly;

  const BasicApplication({
    required this.id,
    required this.name,
    this.description,
    this.logoUrl,
    this.type,
    this.template,
    this.clientId,
    this.isReadOnly = false,
  });

  factory BasicApplication.fromMap(Map<dynamic, dynamic> map) => BasicApplication(
        id: map['id'] as String? ?? '',
        name: map['name'] as String? ?? '',
        description: map['description'] as String?,
        logoUrl: map['logoUrl'] as String?,
        type: map['type'] as String?,
        template: map['template'] as String?,
        clientId: map['clientId'] as String?,
        isReadOnly: map['isReadOnly'] as bool? ?? false,
      );
}

/// A page of applications.
class ApplicationListResponse {
  final int totalResults;
  final int count;
  final List<BasicApplication> applications;

  const ApplicationListResponse({required this.totalResults, required this.count, required this.applications});

  factory ApplicationListResponse.fromMap(Map<dynamic, dynamic> map) => ApplicationListResponse(
        totalResults: _asInt(map['totalResults']),
        count: _asInt(map['count']),
        applications: _asList(map['applications']).map(BasicApplication.fromMap).toList(),
      );
}

/// A user record managed through the ThunderID management API.
///
/// This is a server record, distinct from `User`, which describes the signed-in user.
class ManagedUser {
  final String id;
  final String ouId;
  final String type;
  final String? ouHandle;
  final Map<String, dynamic> attributes;
  final String? display;
  final bool isReadOnly;

  const ManagedUser({
    required this.id,
    required this.ouId,
    required this.type,
    this.ouHandle,
    this.attributes = const {},
    this.display,
    this.isReadOnly = false,
  });

  factory ManagedUser.fromMap(Map<dynamic, dynamic> map) => ManagedUser(
        id: map['id'] as String? ?? '',
        ouId: map['ouId'] as String? ?? '',
        type: map['type'] as String? ?? '',
        ouHandle: map['ouHandle'] as String?,
        attributes: _normalizeMap(map['attributes']),
        display: map['display'] as String?,
        isReadOnly: map['isReadOnly'] as bool? ?? false,
      );
}

/// A page of users.
class ManagedUserListResponse {
  final int totalResults;
  final int startIndex;
  final int count;
  final List<ManagedUser> users;

  const ManagedUserListResponse({
    required this.totalResults,
    required this.startIndex,
    required this.count,
    required this.users,
  });

  factory ManagedUserListResponse.fromMap(Map<dynamic, dynamic> map) => ManagedUserListResponse(
        totalResults: _asInt(map['totalResults']),
        startIndex: _asInt(map['startIndex']),
        count: _asInt(map['count']),
        users: _asList(map['users']).map(ManagedUser.fromMap).toList(),
      );
}

/// The payload used to create a user.
class CreateManagedUserRequest {
  final String ouId;
  final String type;
  final List<String>? groups;
  final Map<String, dynamic>? attributes;

  const CreateManagedUserRequest({required this.ouId, required this.type, this.groups, this.attributes});

  Map<String, dynamic> toMap() => {
        'ouId': ouId,
        'type': type,
        if (groups != null) 'groups': groups,
        if (attributes != null) 'attributes': attributes,
      };
}

/// The payload used to update a user.
class UpdateManagedUserRequest {
  final String? ouId;
  final String? type;
  final List<String>? groups;
  final Map<String, dynamic>? attributes;

  const UpdateManagedUserRequest({this.ouId, this.type, this.groups, this.attributes});

  Map<String, dynamic> toMap() => {
        if (ouId != null) 'ouId': ouId,
        if (type != null) 'type': type,
        if (groups != null) 'groups': groups,
        if (attributes != null) 'attributes': attributes,
      };
}

/// An agent registered in ThunderID.
class Agent {
  final String id;
  final String ouId;
  final String type;
  final String name;
  final String? description;
  final String? logoUrl;
  final String? owner;
  final String? clientId;
  final Map<String, dynamic> attributes;
  final bool isReadOnly;

  /// Every field the server returned, including nested configuration.
  final Map<String, dynamic> data;

  const Agent({
    required this.id,
    required this.ouId,
    required this.type,
    required this.name,
    this.description,
    this.logoUrl,
    this.owner,
    this.clientId,
    this.attributes = const {},
    this.isReadOnly = false,
    this.data = const {},
  });

  factory Agent.fromMap(Map<dynamic, dynamic> map) {
    final data = _normalizeMap(map);
    return Agent(
      id: data['id'] as String? ?? '',
      ouId: data['ouId'] as String? ?? '',
      type: data['type'] as String? ?? '',
      name: data['name'] as String? ?? '',
      description: data['description'] as String?,
      logoUrl: data['logoUrl'] as String?,
      owner: data['owner'] as String?,
      clientId: data['clientId'] as String?,
      attributes: _normalizeMap(data['attributes']),
      isReadOnly: data['isReadOnly'] as bool? ?? false,
      data: data,
    );
  }
}

/// The summary of an agent returned in list responses.
class BasicAgent {
  final String id;
  final String ouId;
  final String type;
  final String name;
  final String? description;
  final String? logoUrl;
  final String? clientId;
  final bool isReadOnly;

  const BasicAgent({
    required this.id,
    required this.ouId,
    required this.type,
    required this.name,
    this.description,
    this.logoUrl,
    this.clientId,
    this.isReadOnly = false,
  });

  factory BasicAgent.fromMap(Map<dynamic, dynamic> map) => BasicAgent(
        id: map['id'] as String? ?? '',
        ouId: map['ouId'] as String? ?? '',
        type: map['type'] as String? ?? '',
        name: map['name'] as String? ?? '',
        description: map['description'] as String?,
        logoUrl: map['logoUrl'] as String?,
        clientId: map['clientId'] as String?,
        isReadOnly: map['isReadOnly'] as bool? ?? false,
      );
}

/// A page of agents.
class AgentListResponse {
  final int totalResults;
  final int startIndex;
  final int count;
  final List<BasicAgent> agents;

  const AgentListResponse({
    required this.totalResults,
    required this.startIndex,
    required this.count,
    required this.agents,
  });

  factory AgentListResponse.fromMap(Map<dynamic, dynamic> map) => AgentListResponse(
        totalResults: _asInt(map['totalResults']),
        startIndex: _asInt(map['startIndex']),
        count: _asInt(map['count']),
        agents: _asList(map['agents']).map(BasicAgent.fromMap).toList(),
      );
}

/// The payload used to create an agent.
///
/// Fields without a named parameter, such as `inboundAuthConfig`, go in [extra].
class CreateAgentRequest {
  final Map<String, dynamic> fields;

  CreateAgentRequest({
    required String ouId,
    required String type,
    required String name,
    String? description,
    String? logoUrl,
    String? owner,
    Map<String, dynamic>? attributes,
    Map<String, dynamic> extra = const {},
  }) : fields = {
          ...extra,
          'ouId': ouId,
          'type': type,
          'name': name,
          if (description != null) 'description': description,
          if (logoUrl != null) 'logoUrl': logoUrl,
          if (owner != null) 'owner': owner,
          if (attributes != null) 'attributes': attributes,
        };

  Map<String, dynamic> toMap() => fields;
}

/// The payload used to update an agent.
///
/// Fields without a named parameter, such as `allowedUserTypes`, go in [extra].
class UpdateAgentRequest {
  final Map<String, dynamic> fields;

  UpdateAgentRequest({
    String? ouId,
    String? type,
    String? name,
    String? description,
    String? logoUrl,
    String? owner,
    Map<String, dynamic>? attributes,
    Map<String, dynamic> extra = const {},
  }) : fields = {
          ...extra,
          if (ouId != null) 'ouId': ouId,
          if (type != null) 'type': type,
          if (name != null) 'name': name,
          if (description != null) 'description': description,
          if (logoUrl != null) 'logoUrl': logoUrl,
          if (owner != null) 'owner': owner,
          if (attributes != null) 'attributes': attributes,
        };

  Map<String, dynamic> toMap() => fields;
}

// The platform channel decodes nested containers as `Map<Object?, Object?>`, and the
// Android bridge passes JSON numbers as doubles, so values are normalized on the way in.

int _asInt(Object? value) => value is num ? value.toInt() : 0;

List<Map<dynamic, dynamic>> _asList(Object? value) =>
    value is List ? value.whereType<Map<dynamic, dynamic>>().toList() : const [];

Map<String, dynamic> _normalizeMap(Object? value) {
  final normalized = _normalize(value);
  return normalized is Map<String, dynamic> ? normalized : <String, dynamic>{};
}

dynamic _normalize(Object? value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries) entry.key.toString(): _normalize(entry.value),
    };
  }
  if (value is List) {
    return value.map(_normalize).toList();
  }
  return value;
}
