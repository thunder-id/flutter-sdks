// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

import 'stories.dart';

// Stories that replace an admin widget's default UI through its `builder`. The builder gets the
// widget's state (rows and paging, values and submit, or the loaded record), so any Flutter UI can
// draw it; here, Material's DataTable, TextFields and Card.

const _ou = 'ou-default';

const _users = [
  ManagedUser(id: 'u-ada', ouId: _ou, ouHandle: 'default', type: 'customer', display: 'Ada Lovelace'),
  ManagedUser(id: 'u-grace', ouId: _ou, ouHandle: 'default', type: 'employee', display: 'Grace Hopper'),
  ManagedUser(id: 'u-alan', ouId: _ou, ouHandle: 'default', type: 'employee', display: 'Alan Turing'),
  ManagedUser(id: 'u-katherine', ouId: _ou, ouHandle: 'default', type: 'employee', display: 'Katherine Johnson'),
  ManagedUser(id: 'u-margaret', ouId: _ou, ouHandle: 'default', type: 'customer', display: 'Margaret Hamilton'),
];

const _detailUser = ManagedUser(
  id: 'u-ada',
  ouId: _ou,
  ouHandle: 'default',
  type: 'customer',
  attributes: {'username': 'ada', 'email': 'ada@example.com', 'given_name': 'Ada', 'password': 'never shown'},
  status: AccessStatus(value: AccessStatusValue.locked),
);

const _memberships = [
  MembershipGroup(id: 'g-eng', name: 'Engineering', ouId: _ou),
  MembershipGroup(id: 'g-support', name: 'Support', ouId: _ou),
];

final _detailApplication = Application.fromJson({
  'id': 'app-shop',
  'ouId': _ou,
  'name': 'Shop',
  'type': 'browser',
  'inboundAuthConfig': [
    {
      'type': 'oauth2',
      'config': {
        'clientId': 'shop-client',
        'grantTypes': ['authorization_code'],
        'redirectUris': ['https://shop.example.com/callback'],
      },
    },
  ],
});

const _stories = [StoryDef('base', 'Base (sample data)'), StoryDef('connected', 'Connected')];

const _units = [
  AccessibleOrganizationUnit(id: 'ou-east', handle: 'acme-east', name: 'Acme East'),
  AccessibleOrganizationUnit(id: 'ou-west', handle: 'acme-west', name: 'Acme West'),
];

const _projects = [
  Project(id: 'p-storefront', handle: 'storefront', displayName: 'Storefront'),
  Project(id: 'p-backoffice', handle: 'backoffice', displayName: 'Back office'),
];

const _organizationUnits = [
  BasicOrganizationUnit(id: 'ou-eng', handle: 'engineering', name: 'Engineering'),
  BasicOrganizationUnit(id: 'ou-sales', handle: 'sales', name: 'Sales'),
];

final _policies = [
  SharingPolicy.fromJson(const {
    'id': 'pol-children',
    'version': 1,
    'childUnits': {'mode': 'all'},
  }),
];

final _deviceStep = EmbeddedFlowResponse.fromMap(const {
  'flowId': 'sample-execution',
  'flowStatus': 'INCOMPLETE',
  'data': {
    'inputs': [
      {'identifier': 'user_code', 'type': 'TEXT_INPUT'},
    ],
  },
});

String _name(ManagedUser user) =>
    resolveManagedIdentityName(id: user.id, display: user.display, attributes: user.attributes);

Widget _themed(StoryContext s, Widget child) => Theme(
      data: ThemeData(
        brightness: s.dark ? Brightness.dark : Brightness.light,
        colorSchemeSeed: const Color(0xFF3688FF),
        useMaterial3: true,
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );

final List<ComponentDef> customRenderComponentDefs = [
  ComponentDef(
    id: 'customUserList',
    name: 'UserList → DataTable',
    category: 'Custom rendering',
    stories: _stories,
    controls: const [ControlDef.choice('limit', ['2', '5', '20'])],
    defaults: const {'limit': '2'},
    build: (context, s) {
      final limit = int.tryParse(s.text('limit')) ?? 2;
      return _themed(
        s,
        s.story == 'connected'
            ? UserList(
                limit: limit,
                onSelect: (user) => s.emit('onSelect ${user.id}'),
                builder: (context, list) => _UserTable(list: list),
              )
            : _SampleUserList(key: ValueKey(limit), limit: limit, emit: s.emit),
      );
    },
    code: (s) => '''
${s.story == 'connected' ? 'UserList(limit: ${s.text('limit')},' : 'BaseUserList(users: page, totalResults: total,'}
  builder: (context, list) => Column(children: [
    DataTable(
      columns: const [DataColumn(label: Text('Name')), DataColumn(label: Text('Type'))],
      rows: [
        for (final user in list.rows)
          DataRow(
            selected: user.id == list.selectedId,
            onSelectChanged: (_) => list.onSelect?.call(user),
            cells: [DataCell(Text(user.display ?? user.id)), DataCell(Text(user.type))],
          ),
      ],
    ),
    Row(children: [
      TextButton(onPressed: () => list.onPageChange?.call(list.offset - list.limit), child: const Text('Previous')),
      TextButton(onPressed: () => list.onPageChange?.call(list.offset + list.limit), child: const Text('Next')),
    ]),
  ]),
)''',
  ),
  ComponentDef(
    id: 'customGroupCreate',
    name: 'GroupCreate → Material form',
    category: 'Custom rendering',
    stories: _stories,
    build: (context, s) => _themed(
      s,
      s.story == 'connected'
          ? GroupCreate(
              onCreated: (group) => s.emit('onCreated ${group.id}'),
              builder: (context, form) => _GroupForm(form: form),
            )
          : BaseGroupCreate(
              onSubmit: (submission) => s.emit('onSubmit ${submission.name}'),
              onCancel: () => s.emit('onCancel'),
              builder: (context, form) => _GroupForm(form: form),
            ),
    ),
    code: (s) => '''
${s.story == 'connected' ? 'GroupCreate(onCreated: (group) => open(group.id),' : 'BaseGroupCreate(onSubmit: (submission) {},'}
  builder: (context, form) => Column(children: [
    TextField(decoration: const InputDecoration(labelText: 'Name'), onChanged: form.onNameChanged),
    TextField(decoration: const InputDecoration(labelText: 'Description'), onChanged: form.onDescriptionChanged),
    if (form.error != null) Text(form.error!),
    FilledButton(onPressed: form.isValid && !form.isSubmitting ? form.submit : null, child: const Text('Create group')),
  ]),
)''',
  ),
  ComponentDef(
    id: 'customUserDetails',
    name: 'UserDetails → Card',
    category: 'Custom rendering',
    stories: _stories,
    controls: const [ControlDef.text('userId')],
    defaults: const {'userId': ''},
    build: (context, s) {
      if (s.story == 'connected' && s.text('userId').isEmpty) {
        return const Text('Set userId to an ID from your server.');
      }
      return _themed(
        s,
        s.story == 'connected'
            ? UserDetails(
                userId: s.text('userId'),
                deletable: true,
                lifecycleActions: true,
                onDeleted: () => s.emit('onDeleted'),
                builder: (context, details) => _UserCard(details: details),
              )
            : BaseUserDetails(
                user: _detailUser,
                groups: _memberships,
                onDelete: () => s.emit('onDelete'),
                lifecycleActions: const [AccountLifecycleAction.unlock, AccountLifecycleAction.suspend],
                onLifecycleAction: (action, note) => s.emit('onLifecycleAction: ${action.name}'),
                builder: (context, details) => _UserCard(details: details),
              ),
      );
    },
    code: (s) => '''
${s.story == 'connected' ? "UserDetails(userId: '${s.text('userId')}', deletable: true, lifecycleActions: true," : 'BaseUserDetails(user: user, groups: groups, onDelete: () {}, lifecycleActions: actions, onLifecycleAction: run,'}
  builder: (context, details) => Card(
    child: Column(children: [
      ListTile(title: Text(details.displayName), subtitle: Text(details.user?.status?.value ?? '')),
      for (final entry in details.attributes.entries) Text('\${entry.key}: \${entry.value}'),
      Wrap(children: [for (final group in details.groups) Chip(label: Text(group.name))]),
      // Ask before suspending or unsuspending; an unlock can run straight away.
      for (final action in details.lifecycleActions)
        TextButton(onPressed: () => details.onLifecycleAction!(action, null), child: Text(action.name)),
      if (details.onDelete != null) TextButton(onPressed: details.onDelete, child: const Text('Delete')),
    ]),
  ),
)''',
  ),
  ComponentDef(
    id: 'customApplicationDetails',
    name: 'ApplicationDetails → Card',
    category: 'Custom rendering',
    stories: _stories,
    controls: const [ControlDef.text('applicationId')],
    defaults: const {'applicationId': ''},
    build: (context, s) {
      if (s.story == 'connected' && s.text('applicationId').isEmpty) {
        return const Text('Set applicationId to an ID from your server.');
      }
      return _themed(
        s,
        s.story == 'connected'
            ? ApplicationDetails(
                applicationId: s.text('applicationId'),
                secretRegenerable: true,
                builder: (context, details) => _ApplicationCard(details: details),
              )
            : _SampleApplicationDetails(emit: s.emit),
      );
    },
    code: (s) => '''
${s.story == 'connected' ? "ApplicationDetails(applicationId: '${s.text('applicationId')}', secretRegenerable: true," : 'BaseApplicationDetails(application: application, clientSecret: secret, onRegenerateSecret: regenerate, onSecretDismissed: forget,'}
  builder: (context, details) => Card(
    child: Column(children: [
      ListTile(title: Text(details.application?.name ?? ''), subtitle: Text(details.application?.oauth2Config?.clientId ?? '')),
      if (details.clientSecret != null) ...[
        SelectableText(details.clientSecret!),
        TextButton(onPressed: details.onSecretDismissed, child: const Text('I have copied it')),
      ],
      // Ask for confirmation before calling onRegenerateSecret.
      if (details.onRegenerateSecret != null)
        TextButton(onPressed: () => confirmThen(details.onRegenerateSecret!), child: const Text('Regenerate secret')),
    ]),
  ),
)''',
  ),
  ComponentDef(
    id: 'customOrganizationUnitSwitcher',
    name: 'OrganizationUnitSwitcher → ChoiceChips',
    category: 'Custom rendering',
    stories: _stories,
    build: (context, s) => _themed(
      s,
      s.story == 'connected'
          ? OrganizationUnitSwitcher(
              onSwitched: (user) => s.emit('onSwitched ${user['ouId'] ?? '-'}'),
              builder: (context, state) => _UnitChips(state: state),
            )
          : BaseOrganizationUnitSwitcher(
              units: _units,
              currentId: _units.first.id,
              onSwitch: (unit) => s.emit('onSwitch ${unit.handle}'),
              builder: (context, state) => _UnitChips(state: state),
            ),
    ),
    code: (s) => '''
${s.story == 'connected' ? 'OrganizationUnitSwitcher(' : 'BaseOrganizationUnitSwitcher(units: units, currentId: currentId, onSwitch: switchTo,'}
  builder: (context, state) => Wrap(spacing: 8, children: [
    for (final unit in state.units)
      ChoiceChip(
        label: Text(unit.name),
        selected: unit.id == state.currentId,
        onSelected: state.onSwitch == null || unit.id == state.currentId ? null : (_) => state.onSwitch!(unit),
      ),
  ]),
)''',
  ),
  ComponentDef(
    id: 'customRolePermissions',
    name: 'RolePermissions → Material list',
    category: 'Custom rendering',
    stories: _stories,
    controls: const [ControlDef.text('roleId')],
    defaults: const {'roleId': ''},
    build: (context, s) {
      if (s.story == 'connected' && s.text('roleId').isEmpty) {
        return const Text('Set roleId to an ID from your server.');
      }
      return _themed(
        s,
        s.story == 'connected'
            ? RolePermissions(
                roleId: s.text('roleId'),
                editable: true,
                builder: (context, state) => _PermissionsCard(state: state),
              )
            : _SampleRolePermissions(emit: s.emit),
      );
    },
    code: (s) => '''
${s.story == 'connected' ? "RolePermissions(roleId: '${s.text('roleId')}', editable: true," : 'BaseRolePermissions(permissions: granted, availablePermissions: options, onAdd: add, onRemove: remove,'}
  builder: (context, state) => Card(
    child: Column(children: [
      for (final entry in state.permissions)
        for (final permission in entry.permissions)
          ListTile(
            title: Text(permission),
            subtitle: Text(state.resourceServerName(entry.resourceServerId)),
            // Ask for confirmation before calling onRemove.
            trailing: state.onRemove == null ? null : IconButton(icon: const Icon(Icons.delete), onPressed: () => confirmThen(() =>
                state.onRemove!(RolePermission(resourceServerId: entry.resourceServerId, permission: permission)))),
          ),
      if (state.onAdd != null)
        Wrap(children: [
          for (final option in state.availablePermissions!.entries)
            for (final permission in option.value)
              ActionChip(label: Text(permission), onPressed: () =>
                  state.onAdd!(RolePermission(resourceServerId: option.key, permission: permission))),
        ]),
    ]),
  ),
)''',
  ),
  ComponentDef(
    id: 'customProjectList',
    name: 'ProjectList → ListTiles',
    category: 'Custom rendering',
    stories: _stories,
    build: (context, s) => _themed(
      s,
      s.story == 'connected'
          ? ProjectList(
              onSelect: (project) => s.emit('onSelect ${project.handle}'),
              builder: (context, list) => _ProjectTiles(list: list),
            )
          : BaseProjectList(
              projects: _projects,
              onSelect: (project) => s.emit('onSelect ${project.handle}'),
              builder: (context, list) => _ProjectTiles(list: list),
            ),
    ),
    code: (s) => '''
${s.story == 'connected' ? 'ProjectList(' : 'BaseProjectList(projects: projects,'}
  onSelect: (project) => open(project.id),
  builder: (context, list) => Column(children: [
    for (final project in list.rows)
      ListTile(
        title: Text(project.displayName),
        subtitle: Text(project.handle),
        selected: project.id == list.selectedId,
        onTap: () => list.onSelect?.call(project),
      ),
  ]),
)''',
  ),
  ComponentDef(
    id: 'customProjectCreate',
    name: 'ProjectCreate → Material form',
    category: 'Custom rendering',
    stories: _stories,
    build: (context, s) => _themed(
      s,
      s.story == 'connected'
          ? ProjectCreate(
              onCreated: (project) => s.emit('onCreated ${project.id}'),
              builder: (context, form) => _ProjectForm(form: form),
            )
          : BaseProjectCreate(
              onSubmit: (request) => s.emit('onSubmit ${request.handle}'),
              builder: (context, form) => _ProjectForm(form: form),
            ),
    ),
    code: (s) => '''
${s.story == 'connected' ? 'ProjectCreate(onCreated: (project) => open(project.id),' : 'BaseProjectCreate(onSubmit: (request) {},'}
  builder: (context, form) => Column(children: [
    TextField(
      decoration: InputDecoration(labelText: 'Handle', errorText: form.handle.isEmpty || form.isHandleValid ? null : 'Invalid'),
      onChanged: form.onHandleChanged,
    ),
    TextField(decoration: const InputDecoration(labelText: 'Display name'), onChanged: form.onDisplayNameChanged),
    if (form.error != null) Text(form.error!),
    FilledButton(onPressed: form.isValid && !form.isSubmitting ? form.submit : null, child: const Text('Create project')),
  ]),
)''',
  ),
  ComponentDef(
    id: 'customProjectDetails',
    name: 'ProjectDetails → Card',
    category: 'Custom rendering',
    stories: _stories,
    controls: const [ControlDef.text('projectId')],
    defaults: const {'projectId': ''},
    build: (context, s) {
      if (s.story == 'connected' && s.text('projectId').isEmpty) {
        return const Text('Set projectId to an ID from your server.');
      }
      return _themed(
        s,
        s.story == 'connected'
            ? ProjectDetails(
                projectId: s.text('projectId'),
                deletable: true,
                onDeleted: () => s.emit('onDeleted'),
                builder: (context, state) => _ProjectCard(state: state),
              )
            : BaseProjectDetails(
                project: _projects.first,
                onDelete: () => s.emit('onDelete'),
                builder: (context, state) => _ProjectCard(state: state),
              ),
      );
    },
    code: (s) => '''
${s.story == 'connected' ? "ProjectDetails(projectId: '${s.text('projectId')}', deletable: true," : 'BaseProjectDetails(project: project, onDelete: delete,'}
  builder: (context, state) => Card(
    child: ListTile(
      title: Text(state.project?.displayName ?? ''),
      subtitle: Text(state.project?.handle ?? ''),
      // Ask for confirmation before calling onDelete.
      trailing: state.onDelete == null ? null : IconButton(icon: const Icon(Icons.delete), onPressed: () => confirmThen(state.onDelete!)),
    ),
  ),
)''',
  ),
  ComponentDef(
    id: 'customProjectSwitcher',
    name: 'ProjectSwitcher → ChoiceChips',
    category: 'Custom rendering',
    stories: _stories,
    build: (context, s) => _themed(
      s,
      s.story == 'connected'
          ? ProjectSwitcher(
              onSelect: (project) => s.emit('onSelect ${project.handle}'),
              builder: (context, state) => _ProjectChips(state: state),
            )
          : _SampleProjectSwitcher(emit: s.emit),
    ),
    code: (s) => '''
${s.story == 'connected' ? 'ProjectSwitcher(onSelect: (project) {},' : 'BaseProjectSwitcher(projects: projects, currentId: currentId, onSelect: select, onClear: clear,'}
  builder: (context, state) => Wrap(spacing: 8, children: [
    for (final project in state.projects)
      ChoiceChip(
        label: Text(project.displayName),
        selected: project.id == state.currentId,
        onSelected: (_) => state.onSelect(project),
      ),
    if (state.onClear != null && state.currentId != null) ActionChip(label: const Text('Clear'), onPressed: state.onClear),
  ]),
)''',
  ),
  ComponentDef(
    id: 'customOrganizationUnitList',
    name: 'OrganizationUnitList → ListTiles',
    category: 'Custom rendering',
    stories: _stories,
    build: (context, s) => _themed(
      s,
      s.story == 'connected'
          ? OrganizationUnitList(
              onSelect: (unit) => s.emit('onSelect ${unit.handle}'),
              builder: (context, list) => _UnitTiles(list: list),
            )
          : BaseOrganizationUnitList(
              units: _organizationUnits,
              onSelect: (unit) => s.emit('onSelect ${unit.handle}'),
              builder: (context, list) => _UnitTiles(list: list),
            ),
    ),
    code: (s) => '''
${s.story == 'connected' ? 'OrganizationUnitList(' : 'BaseOrganizationUnitList(units: units,'}
  onSelect: (unit) => open(unit.id),
  builder: (context, list) => Column(children: [
    for (final unit in list.rows)
      ListTile(leading: const Icon(Icons.account_tree), title: Text(unit.name), subtitle: Text(unit.handle),
          onTap: () => list.onSelect?.call(unit)),
  ]),
)''',
  ),
  ComponentDef(
    id: 'customOrganizationUnitCreate',
    name: 'OrganizationUnitCreate → Material form',
    category: 'Custom rendering',
    stories: _stories,
    build: (context, s) => _themed(
      s,
      s.story == 'connected'
          ? OrganizationUnitCreate(
              onCreated: (unit) => s.emit('onCreated ${unit.id}'),
              builder: (context, form) => _UnitForm(form: form),
            )
          : BaseOrganizationUnitCreate(
              parents: [for (final unit in _organizationUnits) AdminSelectOption(value: unit.id, label: unit.name)],
              onSubmit: (request) => s.emit('onSubmit ${request.handle} ${request.parent ?? '-'}'),
              builder: (context, form) => _UnitForm(form: form),
            ),
    ),
    code: (s) => '''
${s.story == 'connected' ? 'OrganizationUnitCreate(onCreated: (unit) {},' : 'BaseOrganizationUnitCreate(parents: parentOptions, onSubmit: (request) {},'}
  builder: (context, form) => Column(children: [
    TextField(decoration: const InputDecoration(labelText: 'Name'), onChanged: form.onNameChanged),
    TextField(decoration: const InputDecoration(labelText: 'Handle'), onChanged: form.onHandleChanged),
    if (form.onParentChanged != null)
      DropdownButton<String?>(
        value: form.parent,
        items: [
          const DropdownMenuItem(child: Text('Root unit')),
          for (final parent in form.parents) DropdownMenuItem(value: parent.value, child: Text(parent.label)),
        ],
        onChanged: form.onParentChanged,
      ),
    FilledButton(onPressed: form.isValid && !form.isSubmitting ? form.submit : null, child: const Text('Create unit')),
  ]),
)''',
  ),
  ComponentDef(
    id: 'customOrganizationUnitDetails',
    name: 'OrganizationUnitDetails → Card',
    category: 'Custom rendering',
    stories: _stories,
    controls: const [ControlDef.text('organizationUnitId')],
    defaults: const {'organizationUnitId': ''},
    build: (context, s) {
      if (s.story == 'connected' && s.text('organizationUnitId').isEmpty) {
        return const Text('Set organizationUnitId to an ID from your server.');
      }
      return _themed(
        s,
        s.story == 'connected'
            ? OrganizationUnitDetails(
                organizationUnitId: s.text('organizationUnitId'),
                onSelectChild: (unit) => s.emit('onSelectChild ${unit.id}'),
                builder: (context, state) => _UnitCard(state: state),
              )
            : BaseOrganizationUnitDetails(
                unit: const OrganizationUnit(id: 'ou-eng', handle: 'engineering', name: 'Engineering'),
                childUnits: const [BasicOrganizationUnit(id: 'ou-platform', handle: 'platform', name: 'Platform')],
                users: const [OrganizationUnitUser(id: 'u-ada', display: 'Ada Lovelace')],
                groups: const [OrganizationUnitGroup(id: 'g-eng', name: 'Builders')],
                roles: const [OrganizationUnitRole(id: 'r-admin', name: 'Administrator')],
                onSelectChild: (unit) => s.emit('onSelectChild ${unit.id}'),
                builder: (context, state) => _UnitCard(state: state),
              ),
      );
    },
    code: (s) => '''
${s.story == 'connected' ? "OrganizationUnitDetails(organizationUnitId: '${s.text('organizationUnitId')}'," : 'BaseOrganizationUnitDetails(unit: unit, childUnits: children, users: users, groups: groups, roles: roles,'}
  builder: (context, state) => Card(
    child: Column(children: [
      ListTile(title: Text(state.unit?.name ?? ''), subtitle: Text(state.unit?.handle ?? '')),
      Wrap(spacing: 8, children: [
        for (final child in state.children) ActionChip(label: Text(child.name), onPressed: () => state.onSelectChild?.call(child)),
      ]),
      Wrap(spacing: 8, children: [for (final user in state.users) Chip(label: Text(user.display ?? user.id))]),
    ]),
  ),
)''',
  ),
  ComponentDef(
    id: 'customSharingPolicies',
    name: 'SharingPolicies → Material list',
    category: 'Custom rendering',
    stories: _stories,
    controls: const [ControlDef.text('applicationId')],
    defaults: const {'applicationId': ''},
    build: (context, s) {
      if (s.story == 'connected' && s.text('applicationId').isEmpty) {
        return const Text('Set applicationId to an ID from your server.');
      }
      return _themed(
        s,
        s.story == 'connected'
            ? SharingPolicies(
                resourceType: SharingResourceType.application,
                resourceId: s.text('applicationId'),
                editable: true,
                builder: (context, state) => _PolicyList(state: state),
              )
            : BaseSharingPolicies(
                policies: _policies,
                onDelete: (policy) => s.emit('onDelete ${policy.id}'),
                builder: (context, state) => _PolicyList(state: state),
              ),
      );
    },
    code: (s) => '''
${s.story == 'connected' ? "SharingPolicies(resourceType: SharingResourceType.application, resourceId: '${s.text('applicationId')}', editable: true," : 'BaseSharingPolicies(policies: policies, onDelete: delete,'}
  builder: (context, state) => Column(children: [
    for (final policy in state.policies)
      ListTile(
        title: Text(state.describe(policy)),
        // Ask for confirmation before calling onDelete.
        trailing: state.onDelete == null || policy.isReadOnly
            ? null
            : IconButton(icon: const Icon(Icons.delete), onPressed: () => confirmThen(() => state.onDelete!(policy))),
      ),
  ]),
)''',
  ),
  ComponentDef(
    id: 'customDeviceGrant',
    name: 'DeviceGrant → Material form',
    category: 'Custom rendering',
    stories: _stories,
    build: (context, s) => _themed(
      s,
      s.story == 'connected'
          ? DeviceGrant(
              onComplete: (result) => s.emit('onComplete ${result.name}'),
              builder: (context, state) => _DeviceForm(state: state),
            )
          : BaseDeviceGrant(
              step: _deviceStep,
              onSubmit: (action, inputs) => s.emit('onSubmit ${inputs['user_code'] ?? ''}'),
              builder: (context, state) => _DeviceForm(state: state),
            ),
    ),
    code: (s) => '''
${s.story == 'connected' ? 'DeviceGrant(onComplete: (result) {},' : 'BaseDeviceGrant(step: step, onSubmit: (actionId, inputs) {},'}
  builder: (context, state) => state.result != null
      ? Text('Result: \${state.result!.name}')
      : Column(children: [
          for (final input in state.inputs)
            TextField(
              decoration: InputDecoration(labelText: input['identifier'] as String?),
              onChanged: (value) => state.onValueChanged(input['identifier'] as String, value),
            ),
          if (state.error != null) Text(state.error!),
          FilledButton(onPressed: state.isLoading ? null : () => state.submit(), child: const Text('Approve device')),
        ]),
)''',
  ),
];

/// Grants and revokes sample permissions, the way an application holding the data would.
class _SampleRolePermissions extends StatefulWidget {
  final void Function(String action) emit;

  const _SampleRolePermissions({required this.emit});

  @override
  State<_SampleRolePermissions> createState() => _SampleRolePermissionsState();
}

class _SampleRolePermissionsState extends State<_SampleRolePermissions> {
  static const _options = {
    'rs-orders': ['orders:read', 'orders:write', 'orders:delete'],
  };
  List<String> _granted = const ['orders:read'];

  @override
  Widget build(BuildContext context) => BaseRolePermissions(
        permissions: [RoleResourcePermissions(resourceServerId: 'rs-orders', permissions: _granted)],
        resourceServerNames: const {'rs-orders': 'Orders API'},
        availablePermissions: _options,
        onAdd: (permission) {
          setState(() => _granted = [..._granted, permission.permission]);
          widget.emit('onAdd ${permission.permission}');
        },
        onRemove: (permission) {
          setState(() => _granted = _granted.where((p) => p != permission.permission).toList());
          widget.emit('onRemove ${permission.permission}');
        },
        builder: (context, state) => _PermissionsCard(state: state),
      );
}

/// The permissions state drawn as a Material list, with a confirmation dialog before a permission
/// is removed and a chip per permission that can still be granted.
class _PermissionsCard extends StatelessWidget {
  final RolePermissionsState state;

  const _PermissionsCard({required this.state});

  Future<void> _confirmRemove(BuildContext context, String permission, VoidCallback remove) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove $permission?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('playground-custom-permissions-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) remove();
  }

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.permissions.isEmpty) return const Center(child: CircularProgressIndicator());
    final onAdd = state.onAdd;
    final onRemove = state.onRemove;
    final granted = {
      for (final entry in state.permissions)
        for (final permission in entry.permissions) (entry.resourceServerId, permission),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.error != null) Text(state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            for (final (serverId, permission) in granted)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.key),
                title: Text(permission),
                subtitle: Text(state.resourceServerName(serverId)),
                trailing: onRemove == null
                    ? null
                    : IconButton(
                        key: Key('playground-custom-permissions-remove-$permission'),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Remove $permission',
                        onPressed: state.isMutating
                            ? null
                            : () => _confirmRemove(
                                  context,
                                  permission,
                                  () => onRemove(RolePermission(resourceServerId: serverId, permission: permission)),
                                ),
                      ),
              ),
            if (onAdd != null)
              Wrap(
                spacing: 6,
                children: [
                  for (final option in state.availablePermissions!.entries)
                    for (final permission in option.value)
                      if (!granted.contains((option.key, permission)))
                        ActionChip(
                          key: Key('playground-custom-permissions-add-$permission'),
                          avatar: const Icon(Icons.add),
                          label: Text(permission),
                          onPressed: state.isMutating
                              ? null
                              : () => onAdd(RolePermission(resourceServerId: option.key, permission: permission)),
                        ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Regenerates a sample secret and forgets it once dismissed, the way an application holding the
/// data would.
class _SampleApplicationDetails extends StatefulWidget {
  final void Function(String action) emit;

  const _SampleApplicationDetails({required this.emit});

  @override
  State<_SampleApplicationDetails> createState() => _SampleApplicationDetailsState();
}

class _SampleApplicationDetailsState extends State<_SampleApplicationDetails> {
  String? _secret;

  @override
  Widget build(BuildContext context) => BaseApplicationDetails(
        application: _detailApplication,
        clientSecret: _secret,
        onRegenerateSecret: () {
          setState(() => _secret = 'sample-secret-${DateTime.now().millisecondsSinceEpoch % 10000}');
          widget.emit('onRegenerateSecret');
        },
        onSecretDismissed: () {
          setState(() => _secret = null);
          widget.emit('onSecretDismissed');
        },
        builder: (context, details) => _ApplicationCard(details: details),
      );
}

/// The application details state drawn as a Material card, with a confirmation dialog before the
/// secret is regenerated.
class _ApplicationCard extends StatelessWidget {
  final ApplicationDetailsState details;

  const _ApplicationCard({required this.details});

  Future<void> _confirmRegenerate(BuildContext context, VoidCallback regenerate) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Regenerate the client secret?'),
        content: const Text('Anything using the current secret stops working.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('playground-custom-application-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) regenerate();
  }

  @override
  Widget build(BuildContext context) {
    final application = details.application;
    if (details.isLoading && application == null) return const Center(child: CircularProgressIndicator());
    final oauth = application?.oauth2Config;
    final regenerate = details.onRegenerateSecret;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (details.error != null)
              Text(details.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.apps),
              title: Text(application?.name ?? ''),
              subtitle: Text(oauth?.clientId ?? ''),
            ),
            Wrap(spacing: 6, children: [for (final grant in oauth?.grantTypes ?? const <String>[]) Chip(label: Text(grant))]),
            for (final uri in oauth?.redirectUris ?? const <String>[]) Text(uri),
            if (details.clientSecret != null) ...[
              const SizedBox(height: 8),
              SelectableText(details.clientSecret!, key: const Key('playground-custom-application-secret')),
              TextButton(onPressed: details.onSecretDismissed, child: const Text('I have copied it')),
            ],
            if (regenerate != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('playground-custom-application-regenerate'),
                  onPressed: details.isRegeneratingSecret ? null : () => _confirmRegenerate(context, regenerate),
                  child: const Text('Regenerate secret'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pages and selects the sample users, the way an application holding the data would.
class _SampleUserList extends StatefulWidget {
  final int limit;
  final void Function(String action) emit;

  const _SampleUserList({super.key, required this.limit, required this.emit});

  @override
  State<_SampleUserList> createState() => _SampleUserListState();
}

class _SampleUserListState extends State<_SampleUserList> {
  int _offset = 0;
  String? _selected;

  @override
  Widget build(BuildContext context) => BaseUserList(
        users: _users.skip(_offset).take(widget.limit).toList(),
        totalResults: _users.length,
        limit: widget.limit,
        offset: _offset,
        selectedUserId: _selected,
        onPageChange: (offset) {
          setState(() => _offset = offset);
          widget.emit('onPageChange $offset');
        },
        onSelect: (user) {
          setState(() => _selected = user.id);
          widget.emit('onSelect ${user.id}');
        },
        builder: (context, list) => _UserTable(list: list),
      );
}

/// The list state drawn as a Material DataTable with a pager.
class _UserTable extends StatelessWidget {
  final AdminListState<ManagedUser> list;

  const _UserTable({required this.list});

  @override
  Widget build(BuildContext context) {
    final onPageChange = list.onPageChange;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (list.isLoading && list.rows.isEmpty) const LinearProgressIndicator(),
        if (list.error != null) Text(list.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        DataTable(
          key: const Key('playground-custom-user-table'),
          showCheckboxColumn: false,
          columns: const [DataColumn(label: Text('Name')), DataColumn(label: Text('Type'))],
          rows: [
            for (final user in list.rows)
              DataRow(
                selected: user.id == list.selectedId,
                onSelectChanged: list.onSelect == null ? null : (_) => list.onSelect!(user),
                cells: [DataCell(Text(_name(user))), DataCell(Text(user.type))],
              ),
          ],
        ),
        if (onPageChange != null)
          Row(
            children: [
              TextButton(
                onPressed: list.offset > 0 ? () => onPageChange(list.offset - list.limit) : null,
                child: const Text('Previous'),
              ),
              Expanded(
                child: Text(
                  '${list.offset + 1}–${list.offset + list.rows.length} of ${list.totalResults}',
                  textAlign: TextAlign.center,
                ),
              ),
              TextButton(
                onPressed:
                    list.offset + list.limit < list.totalResults ? () => onPageChange(list.offset + list.limit) : null,
                child: const Text('Next'),
              ),
            ],
          ),
      ],
    );
  }
}

/// The group form state drawn with Material text fields.
class _GroupForm extends StatelessWidget {
  final NamedResourceFormState form;

  const _GroupForm({required this.form});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('New group', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                key: const Key('playground-custom-group-name'),
                decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                onChanged: form.onNameChanged,
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                minLines: 2,
                maxLines: 4,
                onChanged: form.onDescriptionChanged,
              ),
              if (form.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(form.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (form.onCancel != null) TextButton(onPressed: form.onCancel, child: const Text('Cancel')),
                  FilledButton(
                    onPressed: form.isValid && !form.isSubmitting ? form.submit : null,
                    child: Text(form.isSubmitting ? 'Creating…' : 'Create group'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

/// The user details state drawn as a Material card with chips.
class _UserCard extends StatelessWidget {
  final UserDetailsState details;

  const _UserCard({required this.details});

  @override
  Widget build(BuildContext context) {
    final user = details.user;
    if (details.isLoading && user == null) return const Center(child: CircularProgressIndicator());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text(details.displayName.isEmpty ? '?' : details.displayName[0])),
              title: Text(details.displayName),
              subtitle: Text(
                user == null
                    ? ''
                    : [user.type, user.ouHandle ?? user.ouId, if (user.status != null) user.status!.value].join(' · '),
              ),
            ),
            for (final entry in details.attributes.entries) Text('${entry.key}: ${entry.value}'),
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [for (final group in details.groups) Chip(label: Text(group.name))]),
            if (details.lifecycleActions.isNotEmpty)
              Wrap(
                spacing: 6,
                children: [
                  for (final action in details.lifecycleActions)
                    OutlinedButton(
                      onPressed: details.isRunningLifecycleAction ? null : () => _runLifecycle(context, action),
                      child: Text(action.name),
                    ),
                ],
              ),
            if (details.onDelete != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: details.onDelete, child: const Text('Delete user')),
              ),
          ],
        ),
      ),
    );
  }

  /// Unlocks straight away; asks before suspending or unsuspending, as the specification requires.
  Future<void> _runLifecycle(BuildContext context, AccountLifecycleAction action) async {
    final run = details.onLifecycleAction;
    if (run == null) return;
    if (action == AccountLifecycleAction.unlock) return run(action, null);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text('${action.name} ${details.displayName}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action.name)),
        ],
      ),
    );
    if (confirmed == true) run(action, null);
  }
}

/// The accessible organization units as choice chips, the current one selected.
class _UnitChips extends StatelessWidget {
  final OrganizationUnitSwitcherState state;

  const _UnitChips({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.units.isEmpty) return const LinearProgressIndicator();
    final onSwitch = state.onSwitch;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.error != null) Text(state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        Wrap(
          spacing: 8,
          children: [
            for (final unit in state.units)
              ChoiceChip(
                key: Key('playground-custom-ou-${unit.id}'),
                label: Text(unit.name),
                selected: unit.id == state.currentId,
                onSelected: onSwitch == null || unit.id == state.currentId ? null : (_) => onSwitch(unit),
              ),
          ],
        ),
      ],
    );
  }
}

/// The projects as list tiles.
class _ProjectTiles extends StatelessWidget {
  final AdminListState<Project> list;

  const _ProjectTiles({required this.list});

  @override
  Widget build(BuildContext context) {
    if (list.isLoading && list.rows.isEmpty) return const LinearProgressIndicator();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (list.error != null) Text(list.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        for (final project in list.rows)
          ListTile(
            key: Key('playground-custom-project-${project.id}'),
            leading: const Icon(Icons.folder_outlined),
            title: Text(project.displayName),
            subtitle: Text(project.handle),
            selected: project.id == list.selectedId,
            onTap: list.onSelect == null ? null : () => list.onSelect!(project),
          ),
      ],
    );
  }
}

/// The project form as Material text fields.
class _ProjectForm extends StatelessWidget {
  final ProjectFormState form;

  const _ProjectForm({required this.form});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('playground-custom-project-handle'),
            decoration: InputDecoration(
              labelText: 'Handle',
              errorText: form.handle.isEmpty || form.isHandleValid ? null : 'Lowercase letters, numbers, - and _',
            ),
            onChanged: form.onHandleChanged,
          ),
          TextField(
            key: const Key('playground-custom-project-name'),
            decoration: const InputDecoration(labelText: 'Display name'),
            onChanged: form.onDisplayNameChanged,
          ),
          if (form.error != null) Text(form.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: form.isValid && !form.isSubmitting ? form.submit : null,
            child: const Text('Create project'),
          ),
        ],
      );
}

/// A button that asks for confirmation before it runs [onConfirm].
class _ConfirmIconButton extends StatefulWidget {
  final String id;
  final VoidCallback onConfirm;

  const _ConfirmIconButton({required this.id, required this.onConfirm});

  @override
  State<_ConfirmIconButton> createState() => _ConfirmIconButtonState();
}

class _ConfirmIconButtonState extends State<_ConfirmIconButton> {
  bool _asking = false;

  @override
  Widget build(BuildContext context) => _asking
      ? TextButton(
          key: Key('playground-custom-confirm-${widget.id}'),
          onPressed: () {
            setState(() => _asking = false);
            widget.onConfirm();
          },
          child: const Text('Confirm delete'),
        )
      : IconButton(
          key: Key('playground-custom-delete-${widget.id}'),
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => setState(() => _asking = true),
        );
}

/// The project as a card, with delete behind a confirmation.
class _ProjectCard extends StatelessWidget {
  final ProjectDetailsState state;

  const _ProjectCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final project = state.project;
    if (project == null) return state.isLoading ? const LinearProgressIndicator() : Text(state.error ?? '');
    final onDelete = state.onDelete;
    return Card(
      child: ListTile(
        title: Text(project.displayName),
        subtitle: Text(project.handle),
        trailing: onDelete == null ? null : _ConfirmIconButton(id: project.id, onConfirm: onDelete),
      ),
    );
  }
}

/// The projects as choice chips, the current one selected, with the sample's own current project.
class _SampleProjectSwitcher extends StatefulWidget {
  final void Function(String action) emit;

  const _SampleProjectSwitcher({required this.emit});

  @override
  State<_SampleProjectSwitcher> createState() => _SampleProjectSwitcherState();
}

class _SampleProjectSwitcherState extends State<_SampleProjectSwitcher> {
  String? _current;

  @override
  Widget build(BuildContext context) => BaseProjectSwitcher(
        projects: _projects,
        currentId: _current,
        onSelect: (project) {
          setState(() => _current = project.id);
          widget.emit('onSelect ${project.handle}');
        },
        onClear: () => setState(() => _current = null),
        builder: (context, state) => _ProjectChips(state: state),
      );
}

class _ProjectChips extends StatelessWidget {
  final ProjectSwitcherState state;

  const _ProjectChips({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.projects.isEmpty) return const LinearProgressIndicator();
    final onClear = state.onClear;
    return Wrap(
      spacing: 8,
      children: [
        for (final project in state.projects)
          ChoiceChip(
            key: Key('playground-custom-project-${project.id}'),
            label: Text(project.displayName),
            selected: project.id == state.currentId,
            onSelected: (_) => state.onSelect(project),
          ),
        if (onClear != null && state.currentId != null) ActionChip(label: const Text('Clear'), onPressed: onClear),
      ],
    );
  }
}

/// The organization units as list tiles.
class _UnitTiles extends StatelessWidget {
  final AdminListState<BasicOrganizationUnit> list;

  const _UnitTiles({required this.list});

  @override
  Widget build(BuildContext context) {
    if (list.isLoading && list.rows.isEmpty) return const LinearProgressIndicator();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (list.error != null) Text(list.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        for (final unit in list.rows)
          ListTile(
            key: Key('playground-custom-unit-${unit.id}'),
            leading: const Icon(Icons.account_tree_outlined),
            title: Text(unit.name),
            subtitle: Text(unit.handle),
            onTap: list.onSelect == null ? null : () => list.onSelect!(unit),
          ),
      ],
    );
  }
}

/// The organization unit form as Material fields, with a parent dropdown.
class _UnitForm extends StatelessWidget {
  final OrganizationUnitFormState form;

  const _UnitForm({required this.form});

  @override
  Widget build(BuildContext context) {
    final onParentChanged = form.onParentChanged;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('playground-custom-unit-name'),
          decoration: const InputDecoration(labelText: 'Name'),
          onChanged: form.onNameChanged,
        ),
        TextField(
          key: const Key('playground-custom-unit-handle'),
          decoration: const InputDecoration(labelText: 'Handle'),
          onChanged: form.onHandleChanged,
        ),
        if (onParentChanged != null)
          DropdownButton<String?>(
            value: form.parent,
            isExpanded: true,
            items: [
              const DropdownMenuItem<String?>(child: Text('Root unit')),
              for (final parent in form.parents)
                DropdownMenuItem<String?>(value: parent.value, child: Text(parent.label)),
            ],
            onChanged: onParentChanged,
          ),
        if (form.error != null) Text(form.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: form.isValid && !form.isSubmitting ? form.submit : null,
          child: const Text('Create unit'),
        ),
      ],
    );
  }
}

/// The organization unit as a card with its child units and members as chips.
class _UnitCard extends StatelessWidget {
  final OrganizationUnitDetailsState state;

  const _UnitCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final unit = state.unit;
    if (unit == null) return state.isLoading ? const LinearProgressIndicator() : Text(state.error ?? '');
    final onSelectChild = state.onSelectChild;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(contentPadding: EdgeInsets.zero, title: Text(unit.name), subtitle: Text(unit.handle)),
            Wrap(
              spacing: 8,
              children: [
                for (final child in state.children)
                  ActionChip(
                    key: Key('playground-custom-unit-child-${child.id}'),
                    avatar: const Icon(Icons.subdirectory_arrow_right, size: 16),
                    label: Text(child.name),
                    onPressed: onSelectChild == null ? null : () => onSelectChild(child),
                  ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final user in state.users) Chip(avatar: const Icon(Icons.person, size: 16), label: Text(user.display ?? user.id)),
                for (final group in state.groups) Chip(avatar: const Icon(Icons.group, size: 16), label: Text(group.name)),
                for (final role in state.roles) Chip(avatar: const Icon(Icons.badge, size: 16), label: Text(role.name)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The sharing policies as list tiles, with delete behind a confirmation.
class _PolicyList extends StatelessWidget {
  final SharingPoliciesState state;

  const _PolicyList({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.policies.isEmpty) return const LinearProgressIndicator();
    final onDelete = state.onDelete;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.error != null) Text(state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (state.policies.isEmpty) const Text('Not shared.'),
        for (final policy in state.policies)
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: Text(state.describe(policy)),
            trailing: onDelete == null || policy.isReadOnly
                ? null
                : _ConfirmIconButton(id: policy.id, onConfirm: () => onDelete(policy)),
          ),
      ],
    );
  }
}

/// The device code step as a Material form, and the outcome as a line of text.
class _DeviceForm extends StatelessWidget {
  final DeviceGrantState state;

  const _DeviceForm({required this.state});

  @override
  Widget build(BuildContext context) {
    final result = state.result;
    if (result != null) return Text('Result: ${result.name}', key: const Key('playground-custom-device-result'));
    if (state.isLoading && state.inputs.isEmpty) return const LinearProgressIndicator();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final input in state.inputs)
          TextField(
            key: Key('playground-custom-device-${input['identifier']}'),
            decoration: InputDecoration(labelText: '${input['identifier']}'),
            onChanged: (value) => state.onValueChanged('${input['identifier']}', value),
          ),
        if (state.error != null) Text(state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: state.isLoading ? null : () => state.submit(),
          child: const Text('Approve device'),
        ),
      ],
    );
  }
}
