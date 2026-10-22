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
);

const _memberships = [
  MembershipGroup(id: 'g-eng', name: 'Engineering', ouId: _ou),
  MembershipGroup(id: 'g-support', name: 'Support', ouId: _ou),
];

const _stories = [StoryDef('base', 'Base (sample data)'), StoryDef('connected', 'Connected')];

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
                onDeleted: () => s.emit('onDeleted'),
                builder: (context, details) => _UserCard(details: details),
              )
            : BaseUserDetails(
                user: _detailUser,
                groups: _memberships,
                onDelete: () => s.emit('onDelete'),
                builder: (context, details) => _UserCard(details: details),
              ),
      );
    },
    code: (s) => '''
${s.story == 'connected' ? "UserDetails(userId: '${s.text('userId')}', deletable: true," : 'BaseUserDetails(user: user, groups: groups, onDelete: () {},'}
  builder: (context, details) => Card(
    child: Column(children: [
      ListTile(title: Text(details.displayName), subtitle: Text(details.user?.type ?? '')),
      for (final entry in details.attributes.entries) Text('\${entry.key}: \${entry.value}'),
      Wrap(children: [for (final group in details.groups) Chip(label: Text(group.name))]),
      if (details.onDelete != null) TextButton(onPressed: details.onDelete, child: const Text('Delete')),
    ]),
  ),
)''',
  ),
];

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
              subtitle: Text(user == null ? '' : '${user.type} · ${user.ouHandle ?? user.ouId}'),
            ),
            for (final entry in details.attributes.entries) Text('${entry.key}: ${entry.value}'),
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [for (final group in details.groups) Chip(label: Text(group.name))]),
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
}
