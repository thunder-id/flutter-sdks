// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

import '../../models/management/administration.dart';
import '../../models/management/agent.dart';
import '../../models/management/application.dart';
import '../../models/management/group.dart';
import '../../models/management/managed_user.dart';
import '../../models/management/role.dart';
import 'identity_candidate.dart';
import 'user_create.dart';

/// Builds custom UI for an admin widget from the state it hands over, in place of the default UI.
typedef AdminWidgetBuilder<T> = Widget Function(BuildContext context, T state);

/// Runs an account lifecycle action, with the operator's note on a suspension (`null` for none).
typedef AccountLifecycleCallback = void Function(AccountLifecycleAction action, String? operatorNote);

/// A search an admin list applies on the server: the attribute to match and the value it must equal.
class AdminSearch {
  final String attribute;
  final String value;

  const AdminSearch({required this.attribute, required this.value});

  @override
  bool operator ==(Object other) => other is AdminSearch && other.attribute == attribute && other.value == value;

  @override
  int get hashCode => Object.hash(attribute, value);
}

/// What an admin list hands its `builder`, so the rows can be shown with any UI.
class AdminListState<T> {
  final List<T> rows;
  final bool isLoading;

  /// A translated message, or `null` when there is nothing to report.
  final String? error;
  final int limit;
  final int offset;

  /// The total on the server, or the number of rows given when it is unknown.
  final int totalResults;
  final String? selectedId;

  /// Shows the page that starts at the given offset. `null` when the list is not paginated.
  final ValueChanged<int>? onPageChange;

  /// Chooses a row. `null` when rows are not selectable.
  final ValueChanged<T>? onSelect;

  /// The search currently applied, if any.
  final AdminSearch? search;

  /// The attributes that can be searched, with translated labels.
  final List<AdminSelectOption> searchAttributes;

  /// Applies a search on the server, or clears it with `null`. `null` when the list cannot be searched.
  final ValueChanged<AdminSearch?>? onSearch;

  const AdminListState({
    required this.rows,
    required this.isLoading,
    required this.error,
    required this.limit,
    required this.offset,
    required this.totalResults,
    required this.selectedId,
    required this.onPageChange,
    required this.onSelect,
    this.search,
    this.searchAttributes = const [],
    this.onSearch,
  });
}

/// What [BaseGroupCreate] and [BaseRoleCreate] hand their `builder`.
class NamedResourceFormState {
  final String name;
  final ValueChanged<String> onNameChanged;
  final String description;
  final ValueChanged<String> onDescriptionChanged;

  /// Whether the values can be submitted.
  final bool isValid;
  final bool isSubmitting;
  final String? error;

  /// Submits the current values. Does nothing while they are not valid or a submission is in flight.
  final VoidCallback submit;
  final VoidCallback? onCancel;

  const NamedResourceFormState({
    required this.name,
    required this.onNameChanged,
    required this.description,
    required this.onDescriptionChanged,
    required this.isValid,
    required this.isSubmitting,
    required this.error,
    required this.submit,
    required this.onCancel,
  });
}

/// What [BaseUserCreate] hands its `builder`.
class UserCreateFormState {
  final List<AdminSelectOption> userTypes;
  final List<UserCreateField> fields;

  /// The chosen user type. The first one is chosen until another is set.
  final String type;
  final ValueChanged<String> onTypeChanged;

  /// The attribute values, keyed by attribute name.
  final Map<String, String> values;

  /// Sets one attribute's value.
  final void Function(String name, String value) onValueChanged;

  /// Whether a type is chosen and every required attribute has a value.
  final bool isValid;
  final bool isSubmitting;
  final String? error;

  /// Submits the chosen type and the non-empty attributes. Does nothing while they are not valid.
  final VoidCallback submit;
  final VoidCallback? onCancel;

  const UserCreateFormState({
    required this.userTypes,
    required this.fields,
    required this.type,
    required this.onTypeChanged,
    required this.values,
    required this.onValueChanged,
    required this.isValid,
    required this.isSubmitting,
    required this.error,
    required this.submit,
    required this.onCancel,
  });
}

/// What [BaseAgentCreate] hands its `builder`.
class AgentCreateFormState {
  final List<AdminSelectOption> agentTypes;
  final String name;
  final ValueChanged<String> onNameChanged;

  /// The chosen agent type. The first one is chosen until another is set.
  final String type;
  final ValueChanged<String> onTypeChanged;
  final String description;
  final ValueChanged<String> onDescriptionChanged;
  final bool isValid;
  final bool isSubmitting;
  final String? error;

  /// Submits the current values. Does nothing while they are not valid or a submission is in flight.
  final VoidCallback submit;
  final VoidCallback? onCancel;

  const AgentCreateFormState({
    required this.agentTypes,
    required this.name,
    required this.onNameChanged,
    required this.type,
    required this.onTypeChanged,
    required this.description,
    required this.onDescriptionChanged,
    required this.isValid,
    required this.isSubmitting,
    required this.error,
    required this.submit,
    required this.onCancel,
  });
}

/// What [BaseApplicationCreate] hands its `builder`.
///
/// Once the application is created and the server returned a client secret, [clientSecret]
/// holds it until [onSecretDismissed] is called; it is never available again after that.
class ApplicationCreateFormState {
  final String name;
  final ValueChanged<String> onNameChanged;
  final String description;
  final ValueChanged<String> onDescriptionChanged;
  final String url;
  final ValueChanged<String> onUrlChanged;
  final String logoUrl;
  final ValueChanged<String> onLogoUrlChanged;

  /// The application types, with translated labels.
  final List<AdminSelectOption> applicationTypes;

  /// The chosen application type; `browser` until another is set.
  final String type;
  final ValueChanged<String> onTypeChanged;

  /// The grant types that can be chosen, with translated labels.
  final List<AdminSelectOption> availableGrantTypes;

  /// The chosen grant types; the authorization code and refresh token grants until changed.
  final List<String> grantTypes;

  /// Adds (`true`) or removes (`false`) a grant type.
  final void Function(String grantType, bool selected) onGrantTypeChanged;

  /// The redirect URIs as typed, one per line.
  final String redirectUris;
  final ValueChanged<String> onRedirectUrisChanged;

  /// Whether the client is public: it has no secret and must use PKCE.
  final bool publicClient;
  final ValueChanged<bool> onPublicClientChanged;

  /// Whether a name, at least one grant type, valid redirect URIs (one is required for the
  /// authorization code grant) are set, and a public client does not ask for client credentials.
  final bool isValid;
  final bool isSubmitting;
  final String? error;

  /// Submits the current values. Does nothing while they are not valid or a submission is in flight.
  final VoidCallback submit;
  final VoidCallback? onCancel;

  /// The created application's client secret, shown once. `null` when there is none to show.
  final String? clientSecret;

  /// Forgets [clientSecret]. `null` when there is none.
  final VoidCallback? onSecretDismissed;

  const ApplicationCreateFormState({
    required this.name,
    required this.onNameChanged,
    required this.description,
    required this.onDescriptionChanged,
    required this.url,
    required this.onUrlChanged,
    required this.logoUrl,
    required this.onLogoUrlChanged,
    required this.applicationTypes,
    required this.type,
    required this.onTypeChanged,
    required this.availableGrantTypes,
    required this.grantTypes,
    required this.onGrantTypeChanged,
    required this.redirectUris,
    required this.onRedirectUrisChanged,
    required this.publicClient,
    required this.onPublicClientChanged,
    required this.isValid,
    required this.isSubmitting,
    required this.error,
    required this.submit,
    required this.onCancel,
    required this.clientSecret,
    required this.onSecretDismissed,
  });
}

/// The changes [BaseApplicationDetails] saves: the general fields and the OAuth client's redirect
/// URIs and grant types. Empty text fields are saved as absent.
class ApplicationEdit {
  final String name;
  final String? description;
  final String? url;
  final String? logoUrl;
  final List<String> redirectUris;
  final List<String> grantTypes;

  const ApplicationEdit({
    required this.name,
    this.description,
    this.url,
    this.logoUrl,
    this.redirectUris = const [],
    this.grantTypes = const [],
  });

  /// [application] with these changes, as a full update: every other field, including the ones
  /// this SDK does not model, is kept. The OAuth client's response types follow the grant types.
  UpdateApplicationRequest applyTo(Application application) {
    final json = application.toJson();
    json['name'] = name;
    void setOrRemove(String key, String? value) =>
        value == null || value.isEmpty ? json.remove(key) : json[key] = value;
    setOrRemove('description', description);
    setOrRemove('url', url);
    setOrRemove('logoUrl', logoUrl);
    final inbound = json['inboundAuthConfig'];
    if (inbound is List) {
      json['inboundAuthConfig'] = [
        for (final entry in inbound)
          if (entry is Map && entry['type'] == InboundAuthTypes.oauth2)
            {
              ...entry,
              'config': {
                ...(entry['config'] is Map ? entry['config'] as Map : const {}),
                'redirectUris': redirectUris,
                'grantTypes': grantTypes,
                'responseTypes': grantTypes.contains(OAuth2GrantTypes.authorizationCode) ? [OAuth2ResponseTypes.code] : <String>[],
              },
            }
          else
            entry,
      ];
    }
    return UpdateApplicationRequest.fromJson(json);
  }
}

/// What [BaseApplicationDetails] hands its `builder`.
class ApplicationDetailsState {
  final Application? application;
  final bool isLoading;
  final String? error;
  final bool isDeleting;
  final bool isUpdating;
  final bool isRegeneratingSecret;

  /// A regenerated client secret, shown once: `null` after [onSecretDismissed].
  final String? clientSecret;

  /// Deletes the application. `null` when deletion is not allowed, including for read-only
  /// applications. A custom UI must ask for confirmation first.
  final VoidCallback? onDelete;

  /// Saves the given changes. `null` when editing is not allowed, including for read-only
  /// applications.
  final ValueChanged<ApplicationEdit>? onUpdate;

  /// Regenerates the client secret. `null` when not allowed, including for read-only
  /// applications and those without a confidential OAuth client. A custom UI must ask for
  /// confirmation first.
  final VoidCallback? onRegenerateSecret;

  /// Forgets [clientSecret]. `null` when there is none.
  final VoidCallback? onSecretDismissed;

  /// The account lifecycle actions offered for the application, most expected first. Empty when none is
  /// allowed.
  final List<AccountLifecycleAction> lifecycleActions;

  /// Runs an account lifecycle action. `null` when the actions are off. A custom UI must ask for
  /// confirmation before suspending or unsuspending.
  final AccountLifecycleCallback? onLifecycleAction;
  final bool isRunningLifecycleAction;

  const ApplicationDetailsState({
    required this.application,
    required this.isLoading,
    required this.error,
    required this.isDeleting,
    required this.isUpdating,
    required this.isRegeneratingSecret,
    required this.clientSecret,
    required this.onDelete,
    required this.onUpdate,
    required this.onRegenerateSecret,
    required this.onSecretDismissed,
    this.lifecycleActions = const [],
    this.onLifecycleAction,
    this.isRunningLifecycleAction = false,
  });
}

/// What [BaseUserDetails] hands its `builder`.
class UserDetailsState {
  final ManagedUser? user;

  /// The user's display name, or an empty string while there is no user.
  final String displayName;

  /// The user's attributes, without the hidden ones.
  final Map<String, dynamic> attributes;
  final List<MembershipGroup> groups;
  final bool isLoading;
  final String? error;
  final bool isDeleting;
  final bool isUpdating;

  /// Deletes the user. `null` when deletion is not allowed, including for read-only users.
  final VoidCallback? onDelete;

  /// Saves the given attributes. `null` when editing is not allowed, including for read-only users.
  final ValueChanged<Map<String, dynamic>>? onUpdate;

  /// The account lifecycle actions offered for the user, most expected first. Empty when none is
  /// allowed.
  final List<AccountLifecycleAction> lifecycleActions;

  /// Runs an account lifecycle action. `null` when the actions are off. A custom UI must ask for
  /// confirmation before suspending or unsuspending.
  final AccountLifecycleCallback? onLifecycleAction;
  final bool isRunningLifecycleAction;

  const UserDetailsState({
    required this.user,
    required this.displayName,
    required this.attributes,
    required this.groups,
    required this.isLoading,
    required this.error,
    required this.isDeleting,
    required this.isUpdating,
    required this.onDelete,
    required this.onUpdate,
    this.lifecycleActions = const [],
    this.onLifecycleAction,
    this.isRunningLifecycleAction = false,
  });
}

/// What [BaseAgentDetails] hands its `builder`.
class AgentDetailsState {
  final Agent? agent;
  final List<MembershipGroup> groups;
  final List<String> roles;
  final bool isLoading;
  final String? error;
  final bool isDeleting;

  /// Deletes the agent. `null` when deletion is not allowed, including for read-only agents.
  final VoidCallback? onDelete;

  /// The account lifecycle actions offered for the agent, most expected first. Empty when none is
  /// allowed.
  final List<AccountLifecycleAction> lifecycleActions;

  /// Runs an account lifecycle action. `null` when the actions are off. A custom UI must ask for
  /// confirmation before suspending or unsuspending.
  final AccountLifecycleCallback? onLifecycleAction;
  final bool isRunningLifecycleAction;

  const AgentDetailsState({
    required this.agent,
    required this.groups,
    required this.roles,
    required this.isLoading,
    required this.error,
    required this.isDeleting,
    required this.onDelete,
    this.lifecycleActions = const [],
    this.onLifecycleAction,
    this.isRunningLifecycleAction = false,
  });
}

/// What [BaseGroupMembers] hands its `builder`.
class GroupMembersState {
  final List<GroupMember> members;

  /// The identities that can be added, by member type. `null` when adding is not allowed.
  final Map<GroupMemberType, List<IdentityCandidate>>? candidates;
  final bool isLoading;
  final String? error;
  final bool isMutating;

  /// Adds a member. `null` when adding is not allowed.
  final ValueChanged<GroupMember>? onAdd;

  /// Removes a member. `null` when removing is not allowed.
  final ValueChanged<GroupMember>? onRemove;

  const GroupMembersState({
    required this.members,
    required this.candidates,
    required this.isLoading,
    required this.error,
    required this.isMutating,
    required this.onAdd,
    required this.onRemove,
  });
}

/// What [BaseRoleAssignments] hands its `builder`.
class RoleAssignmentsState {
  final List<RoleAssignment> assignments;

  /// The identities the role can be assigned to, by type. `null` when assigning is not allowed.
  final Map<RoleAssigneeType, List<IdentityCandidate>>? candidates;
  final bool isLoading;
  final String? error;
  final bool isMutating;

  /// Assigns the role. `null` when assigning is not allowed.
  final ValueChanged<RoleAssignment>? onAssign;

  /// Removes an assignment. `null` when unassigning is not allowed.
  final ValueChanged<RoleAssignment>? onUnassign;

  /// The assignee type the list is narrowed to, or `null` for every type.
  final RoleAssigneeType? typeFilter;

  /// Narrows the list to one assignee type on the server, or back to every type with `null`.
  /// `null` when the list cannot be filtered.
  final ValueChanged<RoleAssigneeType?>? onTypeFilterChange;

  const RoleAssignmentsState({
    required this.assignments,
    required this.candidates,
    required this.isLoading,
    required this.error,
    required this.isMutating,
    required this.onAssign,
    required this.onUnassign,
    this.typeFilter,
    this.onTypeFilterChange,
  });
}

/// What [BaseRolePermissions] hands its `builder`.
class RolePermissionsState {
  /// The resource servers the role grants at least one permission on, with those permissions.
  final List<RoleResourcePermissions> permissions;
  final bool isLoading;
  final String? error;
  final Map<String, String> _resourceServerNames;

  const RolePermissionsState({
    required this.permissions,
    required this.isLoading,
    required this.error,
    required Map<String, String> resourceServerNames,
  }) : _resourceServerNames = resourceServerNames;

  /// A resource server's display name, or its identifier when the name is missing.
  String resourceServerName(String resourceServerId) => _resourceServerNames[resourceServerId] ?? resourceServerId;
}
