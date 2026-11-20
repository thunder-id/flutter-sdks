// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'management/access_status.dart';
import 'management/agent.dart';
import 'management/application.dart';
import 'management/json_reader.dart';

/// The grant types a personal agent can use, in the order an edit form offers them.
abstract final class PersonalAgentGrantTypes {
  static const String authorizationCode = 'authorization_code';
  static const String ciba = 'urn:openid:params:grant-type:ciba';
  static const String refreshToken = 'refresh_token';

  /// Every grant type a personal agent can use.
  static const List<String> all = [authorizationCode, ciba, refreshToken];

  /// The translation key that labels each of [all].
  static const Map<String, String> labelKeys = {
    authorizationCode: 'user.agents.grant_types.authorization_code',
    ciba: 'user.agents.grant_types.ciba',
    refreshToken: 'user.agents.grant_types.refresh_token',
  };
}

/// The suspension action an agent's owner can take on it: [unsuspend] while the owner holds it
/// suspended, otherwise [suspend]. The owner's suspension is independent of any other party's, so
/// an agent the organization suspended, or one suspended while its owner's account is, can still
/// take the owner's own suspension, and lifting the owner's leaves the others in force.
enum MeAgentSuspensionAction {
  suspend,
  unsuspend;

  /// The action to offer for an agent with this status, from a read of the owner's agent.
  static MeAgentSuspensionAction available(AccessStatus? status) =>
      (status?.suspendedBy.contains(SuspensionAppliedBy.owner) ?? false) ? unsuspend : suspend;
}

/// What a personal agent record tells about itself.
extension PersonalAgentRecord on Agent {
  /// Whether this is a personal agent: one that acts only for its owner, a user.
  bool get isPersonal => kind == AgentKind.personal;

  /// The agent's OAuth settings, when it has an OAuth client.
  OAuth2Config? get oauthConfig {
    for (final inbound in inboundAuthConfig) {
      if (inbound['type'] == InboundAuthTypes.oauth2) return OAuth2Config.fromJson(readMap(inbound['config']));
    }
    return null;
  }
}

/// The part of a personal agent its owner may change, sent whole: an update replaces [attributes],
/// [grantTypes] and [redirectUris], and clears a [description] left out.
/// [PersonalAgentFormValues.updateRequest] builds one from an edit form.
class UpdateMeAgentRequest {
  /// The agent's attributes, as its agent type defines them, including `name`.
  final Map<String, dynamic> attributes;
  final String? description;

  /// A subset of [PersonalAgentGrantTypes.all]. An empty list removes every grant.
  final List<String> grantTypes;

  /// At least one when [grantTypes] holds the authorization code grant.
  final List<String> redirectUris;

  const UpdateMeAgentRequest({
    required this.attributes,
    this.description,
    required this.grantTypes,
    required this.redirectUris,
  });

  /// Always sends the three lists, even empty: the server requires them.
  Map<String, dynamic> toJson() => {
        'attributes': attributes,
        if (description != null) 'description': description,
        'grantTypes': grantTypes,
        'redirectUris': redirectUris,
      };
}

/// The result of `ThunderIDClient.suspendAllMeAgents`.
class SuspendAllMeAgentsResponse {
  /// How many agents the request suspended. Agents the owner had already suspended are not counted.
  final int suspendedCount;

  const SuspendAllMeAgentsResponse({required this.suspendedCount});

  factory SuspendAllMeAgentsResponse.fromJson(Map<String, dynamic> json) =>
      SuspendAllMeAgentsResponse(suspendedCount: readInt(json, 'suspendedCount'));
}

/// The values of a personal agent's edit form, starting from what the server holds.
class PersonalAgentFormValues {
  final String name;
  final String description;

  /// The agent's text attributes other than `name`, keyed by attribute name. Attributes that hold
  /// another kind of value are not edited, and are sent back unchanged.
  final Map<String, String> attributes;
  final List<String> grantTypes;

  /// The text of the redirect URI field: URIs separated by whitespace, one per line by default.
  final String redirectUris;

  const PersonalAgentFormValues({
    required this.name,
    required this.description,
    required this.attributes,
    required this.grantTypes,
    required this.redirectUris,
  });

  factory PersonalAgentFormValues.fromAgent(Agent agent) {
    final oauth = agent.oauthConfig;
    final name = agent.attributes['name'];
    return PersonalAgentFormValues(
      name: name is String ? name : '',
      description: agent.description ?? '',
      attributes: {
        for (final entry in agent.attributes.entries)
          if (entry.key != 'name' && entry.value is String) entry.key: entry.value as String,
      },
      grantTypes: oauth?.grantTypes ?? const [],
      redirectUris: (oauth?.redirectUris ?? const []).join('\n'),
    );
  }

  PersonalAgentFormValues copyWith({
    String? name,
    String? description,
    Map<String, String>? attributes,
    List<String>? grantTypes,
    String? redirectUris,
  }) =>
      PersonalAgentFormValues(
        name: name ?? this.name,
        description: description ?? this.description,
        attributes: attributes ?? this.attributes,
        grantTypes: grantTypes ?? this.grantTypes,
        redirectUris: redirectUris ?? this.redirectUris,
      );

  /// The redirect URIs the field holds.
  List<String> get redirectUriList =>
      redirectUris.split(RegExp(r'\s+')).where((uri) => uri.isNotEmpty).toList(growable: false);

  /// Whether the values can be saved: a name is required, and the authorization code grant needs a
  /// redirect URI.
  bool get isValid =>
      name.trim().isNotEmpty &&
      (!grantTypes.contains(PersonalAgentGrantTypes.authorizationCode) || redirectUriList.isNotEmpty);

  /// The update request for [agent]. Attributes the form does not edit are sent back unchanged,
  /// since an update replaces them all.
  UpdateMeAgentRequest updateRequest(Agent agent) => UpdateMeAgentRequest(
        attributes: {...agent.attributes, ...attributes, 'name': name.trim()},
        description: description.trim(),
        grantTypes: grantTypes,
        redirectUris: redirectUriList,
      );
}
