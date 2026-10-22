// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

import 'stories.dart';

// Stories for the admin components. Each has a Connected story (the real widget, talking to the
// management API with the signed-in user's token) and a Base story (the presentational variant
// fed the sample records below, so it renders without a server).

/// Ids picked in a Connected list story, used by the detail stories when their id control is
/// empty: select a row in GroupList, then open GroupMembers.
final Map<String, String> _picked = {};

const _ou = 'ou-default';

const _sampleUsers = [
  ManagedUser(
    id: 'u-ada',
    ouId: _ou,
    ouHandle: 'default',
    type: 'customer',
    attributes: {'username': 'ada', 'email': 'ada@example.com', 'given_name': 'Ada', 'family_name': 'Lovelace'},
  ),
  ManagedUser(id: 'u-grace', ouId: _ou, ouHandle: 'default', type: 'employee', display: 'Grace Hopper'),
  ManagedUser(id: 'u-alan', ouId: _ou, ouHandle: 'default', type: 'employee', isReadOnly: true, display: 'Alan Turing'),
];

const _sampleGroups = [
  Group(id: 'g-eng', name: 'Engineering', ouId: _ou, ouHandle: 'default', description: 'Builds the product'),
  Group(id: 'g-support', name: 'Support', ouId: _ou, ouHandle: 'default', description: 'Answers customers'),
];

const _sampleMemberships = [
  MembershipGroup(id: 'g-eng', name: 'Engineering', ouId: _ou),
  MembershipGroup(id: 'g-support', name: 'Support', ouId: _ou),
];

const _sampleRoles = [
  Role(
    id: 'r-admin',
    name: 'Administrator',
    ouId: _ou,
    description: 'Manages everything',
    permissions: [
      RoleResourcePermissions(resourceServerId: 'rs-system', permissions: ['system']),
      RoleResourcePermissions(resourceServerId: 'rs-orders', permissions: ['orders:read', 'orders:write']),
    ],
  ),
  Role(id: 'r-viewer', name: 'Viewer', ouId: _ou, description: 'Read-only access', isReadOnly: true),
];

const _sampleAgents = [
  Agent(
    id: 'a-concierge',
    name: 'Concierge',
    ouId: _ou,
    ouHandle: 'default',
    type: 'assistant',
    description: 'Books travel for employees',
    clientId: 'concierge-client',
    owner: 'u-ada',
  ),
  Agent(id: 'a-triage', name: 'Ticket triage', ouId: _ou, type: 'worker', clientId: 'triage-client'),
];

const _sampleMembers = [
  GroupMember(id: 'u-ada', type: GroupMemberType.user, display: 'Ada Lovelace'),
  GroupMember(id: 'a-concierge', type: GroupMemberType.agent, display: 'Concierge'),
];

const _sampleMemberCandidates = {
  GroupMemberType.user: [IdentityCandidate(id: 'u-grace', label: 'Grace Hopper')],
  GroupMemberType.agent: [IdentityCandidate(id: 'a-triage', label: 'Ticket triage')],
};

const _sampleAssignments = [
  RoleAssignment(id: 'u-ada', type: RoleAssigneeType.user, display: 'Ada Lovelace'),
  RoleAssignment(id: 'g-eng', type: RoleAssigneeType.group, display: 'Engineering'),
];

const _sampleAssigneeCandidates = {
  RoleAssigneeType.user: [IdentityCandidate(id: 'u-grace', label: 'Grace Hopper')],
  RoleAssigneeType.group: [IdentityCandidate(id: 'g-support', label: 'Support')],
  RoleAssigneeType.agent: [IdentityCandidate(id: 'a-concierge', label: 'Concierge')],
};

const _sampleTypes = [
  AdminSelectOption(value: 'customer', label: 'Customer'),
  AdminSelectOption(value: 'employee', label: 'Employee'),
];

const _sampleAgentTypes = [
  AdminSelectOption(value: 'assistant', label: 'Assistant'),
  AdminSelectOption(value: 'worker', label: 'Worker'),
];

// ── Controls ──────────────────────────────────────────────────────────────

const _states = ['data', 'loading', 'empty', 'forbidden'];
const _detailStates = ['data', 'loading', 'forbidden'];

const _listDefaults = {'title': '', 'limit': '10', 'state': 'data'};
const _connectedListControls = [ControlDef.text('title'), ControlDef.choice('limit', ['5', '10', '20'])];
const _baseListControls = [ControlDef.text('title'), ControlDef.choice('state', _states)];

const _createDefaults = {'title': '', 'submitting': false, 'showError': false};
const _connectedCreateControls = [ControlDef.text('ouId'), ControlDef.text('title')];
const _baseCreateControls = [ControlDef.text('title'), ControlDef.toggle('submitting'), ControlDef.toggle('showError')];

// ── Helpers ───────────────────────────────────────────────────────────────

/// Follows the preview's light/dark toggle; admin components theme from preferences.
ThunderIDPreferences _prefs(StoryContext s) =>
    ThunderIDPreferences(theme: ThemePreferences(mode: s.dark ? 'dark' : 'light'));

String? _opt(StoryContext s, String key) => s.text(key).isEmpty ? null : s.text(key);

/// The id a detail story renders: its control, else the row last picked in a list story.
String _id(StoryContext s, String control, String kind) => _opt(s, control) ?? _picked[kind] ?? '';

/// Flutter snippet: one named argument per line, empty entries dropped.
String _snippet(String widget, List<String?> args) {
  final lines = args.whereType<String>();
  return lines.isEmpty ? 'const $widget()' : '$widget(\n${lines.map((a) => '  $a,\n').join()})';
}

String? _litArg(StoryContext s, String key) => _opt(s, key) == null ? null : '$key: ${lit(s.text(key))}';

/// A forbidden error translated by the SDK, the way a Base component should receive it.
String? _error(BuildContext context, StoryContext s, String fallbackKey) => s.text('state') != 'forbidden'
    ? null
    : toManagementErrorMessage(
        ThunderIDProvider.of(context).i18n.resolve,
        const IAMApiException(ThunderIDErrorCode.forbidden, 'sample', statusCode: 403, operation: 'sample'),
        fallbackKey,
      );

String? _stateArgs(StoryContext s, String fallbackKey) => switch (s.text('state')) {
      'loading' => 'isLoading: true',
      'forbidden' => "error: toManagementErrorMessage(i18n.resolve, error, '$fallbackKey')",
      _ => null,
    };

Widget _needsId(String control, String list) => Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        'Set $control in Controls, or select a row in the Connected $list story.',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13),
      ),
    );

ValueChanged<T> _select<T>(StoryContext s, String kind, String Function(T item) id) => (item) {
      _picked[kind] = id(item);
      s.emit('onSelect(${id(item)})');
    };

/// A list component: Connected (paged from the server) and Base (sample rows).
ComponentDef _list<T>({
  required String id,
  required String name,
  required String kind,
  required String itemsArg,
  required String errorKey,
  required List<T> sample,
  required String Function(T item) itemId,
  required Widget Function(StoryContext s, int limit, ValueChanged<T> onSelect) connected,
  required Widget Function(StoryContext s, List<T> items, String? error, ValueChanged<T> onSelect) base,
  List<ControlDef> extraConnected = const [],
  List<String? Function(StoryContext s)> extraArgs = const [],
}) =>
    ComponentDef(
      id: id,
      name: name,
      category: 'Admin',
      defaults: _listDefaults,
      controls: [..._connectedListControls, ...extraConnected],
      stories: const [
        StoryDef('connected', 'Connected'),
        StoryDef('base', 'Base (sample data)', controls: _baseListControls),
      ],
      build: (context, s) {
        final onSelect = _select<T>(s, kind, itemId);
        if (s.story == 'base') {
          return base(s, s.text('state') == 'empty' ? <T>[] : sample, _error(context, s, errorKey), onSelect);
        }
        final limit = int.tryParse(s.text('limit')) ?? 10;
        return KeyedSubtree(
          key: ValueKey('$id/$limit/${extraArgs.map((a) => a(s)).join()}'),
          child: connected(s, limit, onSelect),
        );
      },
      code: (s) => s.story == 'base'
          ? _snippet('Base$name', [
              '$itemsArg: ${s.text('state') == 'empty' ? 'const []' : itemsArg}',
              _stateArgs(s, errorKey),
              _litArg(s, 'title'),
              'onSelect: (item) {}',
            ])
          : _snippet(name, [
              if (s.text('limit') != '20') 'limit: ${s.text('limit')}',
              for (final arg in extraArgs) arg(s),
              _litArg(s, 'title'),
              'onSelect: (item) {}',
            ]),
    );

/// A create form: Connected (creates through the API in ouId) and Base (hands back the form).
ComponentDef _create({
  required String id,
  required String name,
  required String errorKey,
  required Widget Function(StoryContext s) connected,
  required Widget Function(BuildContext context, StoryContext s, String? error) base,
  List<String> baseArgs = const [],
  List<ControlDef> extraConnected = const [],
}) =>
    ComponentDef(
      id: id,
      name: name,
      category: 'Admin',
      defaults: _createDefaults,
      controls: [..._connectedCreateControls, ...extraConnected],
      stories: const [
        StoryDef('connected', 'Connected'),
        StoryDef('base', 'Base (no request)', controls: _baseCreateControls),
      ],
      build: (context, s) => s.story == 'base'
          ? base(
              context,
              s,
              s.flag('showError') ? ThunderIDProvider.of(context).i18n.resolve(errorKey) : null,
            )
          : KeyedSubtree(key: ValueKey('$id/${s.text('ouId')}'), child: connected(s)),
      code: (s) => s.story == 'base'
          ? _snippet('Base$name', [
              ...baseArgs,
              if (s.flag('submitting')) 'isSubmitting: true',
              if (s.flag('showError')) "error: i18n.resolve('$errorKey')",
              _litArg(s, 'title'),
              'onSubmit: (submission) {}',
              'onCancel: () {}',
            ])
          : _snippet(name, [
              _litArg(s, 'ouId'),
              if (id == 'agentCreate') _litArg(s, 'owner'),
              _litArg(s, 'title'),
              'onCreated: (created) {}',
              'onCancel: () {}',
            ]),
    );

void Function(T) _emitWith<T>(StoryContext s, String action, String Function(T value) describe) =>
    (value) => s.emit('$action(${describe(value)})');

// ── Components ────────────────────────────────────────────────────────────

final List<ComponentDef> adminComponentDefs = [
  _list<ManagedUser>(
    id: 'userList',
    name: 'UserList',
    kind: 'user',
    itemsArg: 'users',
    errorKey: 'admin.users.list.error',
    sample: _sampleUsers,
    itemId: (u) => u.id,
    extraConnected: const [ControlDef.text('filter')],
    extraArgs: [(s) => _litArg(s, 'filter')],
    connected: (s, limit, onSelect) =>
        UserList(limit: limit, filter: _opt(s, 'filter'), title: _opt(s, 'title'), onSelect: onSelect, preferences: _prefs(s)),
    base: (s, items, error, onSelect) => BaseUserList(
      users: items,
      isLoading: s.text('state') == 'loading',
      error: error,
      title: _opt(s, 'title'),
      onSelect: onSelect,
      totalResults: items.length,
      preferences: _prefs(s),
    ),
  ),
  _create(
    id: 'userCreate',
    name: 'UserCreate',
    errorKey: 'admin.users.create.error',
    baseArgs: const ['userTypes: userTypes'],
    connected: (s) => UserCreate(
      ouId: _opt(s, 'ouId'),
      title: _opt(s, 'title'),
      onCreated: _emitWith(s, 'onCreated', (u) => u.id),
      onCancel: () => s.emit('onCancel'),
      preferences: _prefs(s),
    ),
    base: (context, s, error) => BaseUserCreate(
      userTypes: _sampleTypes,
      isSubmitting: s.flag('submitting'),
      error: error,
      title: _opt(s, 'title'),
      onSubmit: _emitWith(s, 'onSubmit', (sub) => '${sub.type}, ${sub.attributes.keys.join('/')}'),
      onCancel: () => s.emit('onCancel'),
      preferences: _prefs(s),
    ),
  ),
  ComponentDef(
    id: 'userDetails',
    name: 'UserDetails',
    category: 'Admin',
    defaults: const {'userId': '', 'deletable': false, 'editable': true, 'state': 'data'},
    controls: const [ControlDef.text('userId'), ControlDef.toggle('deletable'), ControlDef.toggle('editable')],
    stories: const [
      StoryDef('connected', 'Connected'),
      StoryDef(
        'base',
        'Base (sample data)',
        controls: [ControlDef.choice('state', _detailStates), ControlDef.toggle('deletable'), ControlDef.toggle('editable')],
      ),
    ],
    build: (context, s) {
      if (s.story == 'base') {
        return BaseUserDetails(
          user: s.text('state') == 'data' ? _sampleUsers.first : null,
          groups: _sampleMemberships,
          isLoading: s.text('state') == 'loading',
          error: _error(context, s, 'admin.users.details.error'),
          onDelete: s.flag('deletable') ? () => s.emit('onDelete') : null,
          onUpdate: s.flag('editable') ? _emitWith(s, 'onUpdate', (a) => '${a.length} attributes') : null,
          preferences: _prefs(s),
        );
      }
      final userId = _id(s, 'userId', 'user');
      if (userId.isEmpty) return _needsId('userId', 'UserList');
      return UserDetails(
        key: ValueKey('userDetails/$userId'),
        userId: userId,
        deletable: s.flag('deletable'),
        editable: s.flag('editable'),
        onDeleted: () => s.emit('onDeleted'),
        preferences: _prefs(s),
      );
    },
    code: (s) => s.story == 'base'
        ? _snippet('BaseUserDetails', [
            'user: user',
            'groups: groups',
            _stateArgs(s, 'admin.users.details.error'),
            if (s.flag('deletable')) 'onDelete: () {}',
            if (s.flag('editable')) 'onUpdate: (attributes) {}',
          ])
        : _snippet('UserDetails', [
            'userId: ${lit(_id(s, 'userId', 'user').isEmpty ? 'user-id' : _id(s, 'userId', 'user'))}',
            if (s.flag('deletable')) 'deletable: true',
            if (s.flag('editable')) 'editable: true',
            'onDeleted: () {}',
          ]),
  ),
  _list<Group>(
    id: 'groupList',
    name: 'GroupList',
    kind: 'group',
    itemsArg: 'groups',
    errorKey: 'admin.groups.list.error',
    sample: _sampleGroups,
    itemId: (g) => g.id,
    connected: (s, limit, onSelect) =>
        GroupList(limit: limit, title: _opt(s, 'title'), onSelect: onSelect, preferences: _prefs(s)),
    base: (s, items, error, onSelect) => BaseGroupList(
      groups: items,
      isLoading: s.text('state') == 'loading',
      error: error,
      title: _opt(s, 'title'),
      onSelect: onSelect,
      totalResults: items.length,
      preferences: _prefs(s),
    ),
  ),
  _create(
    id: 'groupCreate',
    name: 'GroupCreate',
    errorKey: 'admin.groups.create.error',
    connected: (s) => GroupCreate(
      ouId: _opt(s, 'ouId'),
      title: _opt(s, 'title'),
      onCreated: _emitWith(s, 'onCreated', (g) => g.id),
      onCancel: () => s.emit('onCancel'),
      preferences: _prefs(s),
    ),
    base: (context, s, error) => BaseGroupCreate(
      isSubmitting: s.flag('submitting'),
      error: error,
      title: _opt(s, 'title'),
      onSubmit: _emitWith(s, 'onSubmit', (sub) => sub.name),
      onCancel: () => s.emit('onCancel'),
      preferences: _prefs(s),
    ),
  ),
  ComponentDef(
    id: 'groupMembers',
    name: 'GroupMembers',
    category: 'Admin',
    defaults: const {'groupId': '', 'editable': true, 'state': 'data'},
    controls: const [ControlDef.text('groupId'), ControlDef.toggle('editable')],
    stories: const [
      StoryDef('connected', 'Connected'),
      StoryDef('base', 'Base (sample data)', controls: [ControlDef.choice('state', _states), ControlDef.toggle('editable')]),
    ],
    build: (context, s) {
      if (s.story == 'base') {
        final editable = s.flag('editable');
        return BaseGroupMembers(
          members: s.text('state') == 'empty' ? const [] : _sampleMembers,
          candidates: editable ? _sampleMemberCandidates : null,
          onAdd: editable ? _emitWith(s, 'onAdd', (m) => '${m.type.value}:${m.id}') : null,
          onRemove: editable ? _emitWith(s, 'onRemove', (m) => '${m.type.value}:${m.id}') : null,
          isLoading: s.text('state') == 'loading',
          error: _error(context, s, 'admin.groups.members.error'),
          preferences: _prefs(s),
        );
      }
      final groupId = _id(s, 'groupId', 'group');
      if (groupId.isEmpty) return _needsId('groupId', 'GroupList');
      return GroupMembers(
        key: ValueKey('groupMembers/$groupId/${s.flag('editable')}'),
        groupId: groupId,
        editable: s.flag('editable'),
        preferences: _prefs(s),
      );
    },
    code: (s) => s.story == 'base'
        ? _snippet('BaseGroupMembers', [
            'members: ${s.text('state') == 'empty' ? 'const []' : 'members'}',
            if (s.flag('editable')) 'candidates: {GroupMemberType.user: userCandidates}',
            if (s.flag('editable')) 'onAdd: (member) {}',
            if (s.flag('editable')) 'onRemove: (member) {}',
            _stateArgs(s, 'admin.groups.members.error'),
          ])
        : _snippet('GroupMembers', [
            'groupId: ${lit(_id(s, 'groupId', 'group').isEmpty ? 'group-id' : _id(s, 'groupId', 'group'))}',
            if (s.flag('editable')) 'editable: true',
          ]),
  ),
  _list<Role>(
    id: 'roleList',
    name: 'RoleList',
    kind: 'role',
    itemsArg: 'roles',
    errorKey: 'admin.roles.list.error',
    sample: _sampleRoles,
    itemId: (r) => r.id,
    connected: (s, limit, onSelect) =>
        RoleList(limit: limit, title: _opt(s, 'title'), onSelect: onSelect, preferences: _prefs(s)),
    base: (s, items, error, onSelect) => BaseRoleList(
      roles: items,
      isLoading: s.text('state') == 'loading',
      error: error,
      title: _opt(s, 'title'),
      onSelect: onSelect,
      totalResults: items.length,
      preferences: _prefs(s),
    ),
  ),
  _create(
    id: 'roleCreate',
    name: 'RoleCreate',
    errorKey: 'admin.roles.create.error',
    connected: (s) => RoleCreate(
      ouId: _opt(s, 'ouId'),
      title: _opt(s, 'title'),
      onCreated: _emitWith(s, 'onCreated', (r) => r.id),
      onCancel: () => s.emit('onCancel'),
      preferences: _prefs(s),
    ),
    base: (context, s, error) => BaseRoleCreate(
      isSubmitting: s.flag('submitting'),
      error: error,
      title: _opt(s, 'title'),
      onSubmit: _emitWith(s, 'onSubmit', (sub) => sub.name),
      onCancel: () => s.emit('onCancel'),
      preferences: _prefs(s),
    ),
  ),
  ComponentDef(
    id: 'rolePermissions',
    name: 'RolePermissions',
    category: 'Admin',
    defaults: const {'roleId': '', 'state': 'data', 'resourceNames': true},
    controls: const [ControlDef.text('roleId')],
    stories: const [
      StoryDef('connected', 'Connected'),
      StoryDef(
        'base',
        'Base (sample data)',
        controls: [ControlDef.choice('state', _states), ControlDef.toggle('resourceNames')],
      ),
    ],
    build: (context, s) {
      if (s.story == 'base') {
        return BaseRolePermissions(
          permissions: s.text('state') == 'empty' ? const [] : _sampleRoles.first.permissions,
          resourceServerNames: s.flag('resourceNames') ? const {'rs-system': 'System API', 'rs-orders': 'Orders API'} : const {},
          isLoading: s.text('state') == 'loading',
          error: _error(context, s, 'admin.roles.permissions.error'),
          preferences: _prefs(s),
        );
      }
      final roleId = _id(s, 'roleId', 'role');
      if (roleId.isEmpty) return _needsId('roleId', 'RoleList');
      return RolePermissions(key: ValueKey('rolePermissions/$roleId'), roleId: roleId, preferences: _prefs(s));
    },
    code: (s) => s.story == 'base'
        ? _snippet('BaseRolePermissions', [
            'permissions: ${s.text('state') == 'empty' ? 'const []' : 'role.permissions'}',
            if (s.flag('resourceNames')) "resourceServerNames: const {'rs-system': 'System API'}",
            _stateArgs(s, 'admin.roles.permissions.error'),
          ])
        : _snippet('RolePermissions', [
            'roleId: ${lit(_id(s, 'roleId', 'role').isEmpty ? 'role-id' : _id(s, 'roleId', 'role'))}',
          ]),
  ),
  ComponentDef(
    id: 'roleAssignments',
    name: 'RoleAssignments',
    category: 'Admin',
    defaults: const {'roleId': '', 'editable': true, 'state': 'data'},
    controls: const [ControlDef.text('roleId'), ControlDef.toggle('editable')],
    stories: const [
      StoryDef('connected', 'Connected'),
      StoryDef('base', 'Base (sample data)', controls: [ControlDef.choice('state', _states), ControlDef.toggle('editable')]),
    ],
    build: (context, s) {
      if (s.story == 'base') {
        final editable = s.flag('editable');
        return BaseRoleAssignments(
          assignments: s.text('state') == 'empty' ? const [] : _sampleAssignments,
          candidates: editable ? _sampleAssigneeCandidates : null,
          onAssign: editable ? _emitWith(s, 'onAssign', (a) => '${a.type.value}:${a.id}') : null,
          onUnassign: editable ? _emitWith(s, 'onUnassign', (a) => '${a.type.value}:${a.id}') : null,
          isLoading: s.text('state') == 'loading',
          error: _error(context, s, 'admin.roles.assignments.error'),
          preferences: _prefs(s),
        );
      }
      final roleId = _id(s, 'roleId', 'role');
      if (roleId.isEmpty) return _needsId('roleId', 'RoleList');
      return RoleAssignments(
        key: ValueKey('roleAssignments/$roleId/${s.flag('editable')}'),
        roleId: roleId,
        editable: s.flag('editable'),
        preferences: _prefs(s),
      );
    },
    code: (s) => s.story == 'base'
        ? _snippet('BaseRoleAssignments', [
            'assignments: ${s.text('state') == 'empty' ? 'const []' : 'assignments'}',
            if (s.flag('editable')) 'candidates: {RoleAssigneeType.user: userCandidates}',
            if (s.flag('editable')) 'onAssign: (assignment) {}',
            if (s.flag('editable')) 'onUnassign: (assignment) {}',
            _stateArgs(s, 'admin.roles.assignments.error'),
          ])
        : _snippet('RoleAssignments', [
            'roleId: ${lit(_id(s, 'roleId', 'role').isEmpty ? 'role-id' : _id(s, 'roleId', 'role'))}',
            if (s.flag('editable')) 'editable: true',
          ]),
  ),
  _list<Agent>(
    id: 'agentList',
    name: 'AgentList',
    kind: 'agent',
    itemsArg: 'agents',
    errorKey: 'admin.agents.list.error',
    sample: _sampleAgents,
    itemId: (a) => a.id,
    connected: (s, limit, onSelect) =>
        AgentList(limit: limit, title: _opt(s, 'title'), onSelect: onSelect, preferences: _prefs(s)),
    base: (s, items, error, onSelect) => BaseAgentList(
      agents: items,
      isLoading: s.text('state') == 'loading',
      error: error,
      title: _opt(s, 'title'),
      onSelect: onSelect,
      totalResults: items.length,
      preferences: _prefs(s),
    ),
  ),
  _create(
    id: 'agentCreate',
    name: 'AgentCreate',
    errorKey: 'admin.agents.create.error',
    baseArgs: const ['agentTypes: agentTypes'],
    extraConnected: const [ControlDef.text('owner')],
    connected: (s) => AgentCreate(
      ouId: _opt(s, 'ouId'),
      owner: _opt(s, 'owner'),
      title: _opt(s, 'title'),
      onCreated: _emitWith(s, 'onCreated', (a) => a.id),
      onCancel: () => s.emit('onCancel'),
      preferences: _prefs(s),
    ),
    base: (context, s, error) => BaseAgentCreate(
      agentTypes: _sampleAgentTypes,
      isSubmitting: s.flag('submitting'),
      error: error,
      title: _opt(s, 'title'),
      onSubmit: _emitWith(s, 'onSubmit', (sub) => '${sub.name}, ${sub.type}'),
      onCancel: () => s.emit('onCancel'),
      preferences: _prefs(s),
    ),
  ),
  ComponentDef(
    id: 'agentDetails',
    name: 'AgentDetails',
    category: 'Admin',
    defaults: const {'agentId': '', 'deletable': false, 'state': 'data'},
    controls: const [ControlDef.text('agentId'), ControlDef.toggle('deletable')],
    stories: const [
      StoryDef('connected', 'Connected'),
      StoryDef('base', 'Base (sample data)', controls: [ControlDef.choice('state', _detailStates), ControlDef.toggle('deletable')]),
    ],
    build: (context, s) {
      if (s.story == 'base') {
        return BaseAgentDetails(
          agent: s.text('state') == 'data' ? _sampleAgents.first : null,
          groups: _sampleMemberships.take(1).toList(),
          roles: const ['Administrator'],
          isLoading: s.text('state') == 'loading',
          error: _error(context, s, 'admin.agents.details.error'),
          onDelete: s.flag('deletable') ? () => s.emit('onDelete') : null,
          preferences: _prefs(s),
        );
      }
      final agentId = _id(s, 'agentId', 'agent');
      if (agentId.isEmpty) return _needsId('agentId', 'AgentList');
      return AgentDetails(
        key: ValueKey('agentDetails/$agentId'),
        agentId: agentId,
        deletable: s.flag('deletable'),
        onDeleted: () => s.emit('onDeleted'),
        preferences: _prefs(s),
      );
    },
    code: (s) => s.story == 'base'
        ? _snippet('BaseAgentDetails', [
            'agent: agent',
            'groups: groups',
            'roles: roleNames',
            _stateArgs(s, 'admin.agents.details.error'),
            if (s.flag('deletable')) 'onDelete: () {}',
          ])
        : _snippet('AgentDetails', [
            'agentId: ${lit(_id(s, 'agentId', 'agent').isEmpty ? 'agent-id' : _id(s, 'agentId', 'agent'))}',
            if (s.flag('deletable')) 'deletable: true',
            'onDeleted: () {}',
          ]),
  ),
];
