// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:material_ui/material_ui.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

import 'stories.dart';

/// Sample personal agents for the sample stories.
final List<Agent> _sampleAgents = [
  Agent.fromJson(const {
    'id': 'pa-spend',
    'ouId': 'ou-1',
    'type': 'assistant',
    'kind': AgentKind.personal,
    'clientId': 'spend-assistant',
    'attributes': {'name': 'Spending assistant'},
    'status': {'value': AccessStatusValue.active},
  }),
  Agent.fromJson(const {
    'id': 'pa-mail',
    'ouId': 'ou-1',
    'type': 'assistant',
    'kind': AgentKind.personal,
    'clientId': 'mail-assistant',
    'attributes': {'name': 'Mail assistant'},
    'status': {
      'value': AccessStatusValue.suspended,
      'details': {
        'appliedBy': [SuspensionAppliedBy.owner],
      },
    },
  }),
];

/// The sample agent of the details stories, suspended by [party] unless it is `none`.
Agent _sampleAgent(String party) => Agent.fromJson({
      'id': 'pa-spend',
      'ouId': 'ou-1',
      'type': 'assistant',
      'kind': AgentKind.personal,
      'description': 'Pays recurring bills within a monthly limit',
      'clientId': 'spend-assistant',
      'owner': {'id': 'usr-liam'},
      'attributes': {'name': 'Spending assistant', 'model': 'planner-v1'},
      'inboundAuthConfig': [
        {
          'type': 'oauth2',
          'config': {
            'grantTypes': [PersonalAgentGrantTypes.authorizationCode, PersonalAgentGrantTypes.refreshToken],
            'redirectUris': ['https://assistant.example.com/callback'],
          },
        },
      ],
      'status': party == 'none'
          ? {'value': AccessStatusValue.active}
          : {
              'value': AccessStatusValue.suspended,
              'details': {
                'appliedBy': [party],
              },
            },
    });

/// The agent last picked in a personal agent list story, which the live details story shows.
String? _picked;

ThunderIDPreferences _prefs(StoryContext s) =>
    ThunderIDPreferences(theme: ThemePreferences(mode: s.dark ? 'dark' : 'light'));

Widget _hint(String text) => Padding(
      padding: const EdgeInsets.all(12),
      child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
    );

ValueChanged<Agent> _select(StoryContext s) => (agent) {
      if (s.story == 'connected') _picked = agent.id;
      s.emit('onSelect(${agent.name})');
    };

final List<ComponentDef> personalAgentComponentDefs = [
  ComponentDef(
    id: 'personalAgentList',
    name: 'PersonalAgentList',
    category: 'Presentation',
    defaults: const {'suspendable': true, 'state': 'data'},
    controls: const [ControlDef.toggle('suspendable')],
    stories: const [
      StoryDef(
        'base',
        'Sample',
        controls: [ControlDef.toggle('suspendable'), ControlDef.choice('state', ['data', 'loading', 'empty', 'error'])],
      ),
      StoryDef('connected', 'Signed-in user'),
      StoryDef('custom', 'Custom rendering'),
    ],
    build: (context, s) {
      final suspendAll = s.flag('suspendable') ? () => s.emit('onSuspendAll') : null;
      if (s.story == 'connected') {
        if (!ThunderIDProvider.of(context).isSignedIn) return _hint("Sign in to show the signed-in user's own agents.");
        return PersonalAgentList(onSelect: _select(s), suspendable: s.flag('suspendable'), preferences: _prefs(s));
      }
      if (s.story == 'custom') {
        return BasePersonalAgentList(
          agents: _sampleAgents,
          onSelect: _select(s),
          onSuspendAll: suspendAll,
          builder: (context, list) => _CustomPersonalAgentList(list: list),
        );
      }
      final state = s.text('state');
      return BasePersonalAgentList(
        agents: state == 'data' ? _sampleAgents : const [],
        isLoading: state == 'loading',
        error: state == 'error' ? 'Could not load your agents. Please try again.' : null,
        onPageChange: (offset) => s.emit('onPageChange($offset)'),
        onSelect: _select(s),
        onSuspendAll: suspendAll,
        preferences: _prefs(s),
      );
    },
    code: (s) {
      if (s.story == 'base') {
        final state = s.text('state');
        return 'BasePersonalAgentList(\n'
            '  agents: ${state == 'data' ? 'agents' : 'const []'},\n'
            '${state == 'loading' ? '  isLoading: true,\n' : ''}'
            '${state == 'error' ? "  error: 'Could not load your agents. Please try again.',\n" : ''}'
            '  onSelect: (agent) => agentId = agent.id,\n'
            '${s.flag('suspendable') ? '  onSuspendAll: () {},\n' : ''}'
            ')';
      }
      final call =
          'PersonalAgentList(\n  onSelect: (agent) => agentId = agent.id,\n${s.flag('suspendable') ? '  suspendable: true,\n' : ''}';
      return s.story == 'custom'
          ? '$call  builder: (context, list) => Column(\n'
              '    children: [\n'
              '      for (final agent in list.agents)\n'
              '        ListTile(title: Text(agent.name), onTap: () => list.onSelect?.call(agent)),\n'
              '    ],\n'
              '  ),\n'
              ')'
          : '$call)';
    },
  ),
  ComponentDef(
    id: 'personalAgentDetails',
    name: 'PersonalAgentDetails',
    category: 'Presentation',
    defaults: const {
      'agentId': '',
      'suspension': 'none',
      'editable': true,
      'deletable': true,
      'suspendable': true,
      'state': 'data',
    },
    controls: const [
      ControlDef.text('agentId'),
      ControlDef.toggle('editable'),
      ControlDef.toggle('deletable'),
      ControlDef.toggle('suspendable'),
    ],
    stories: const [
      StoryDef(
        'base',
        'Sample',
        controls: [
          ControlDef.choice('suspension', ['none', 'owner', 'organization', 'cascade']),
          ControlDef.choice('state', ['data', 'loading', 'error']),
          ControlDef.toggle('editable'),
          ControlDef.toggle('deletable'),
          ControlDef.toggle('suspendable'),
        ],
      ),
      StoryDef('connected', 'Signed-in user'),
      StoryDef(
        'custom',
        'Custom rendering',
        controls: [
          ControlDef.choice('suspension', ['none', 'owner', 'organization', 'cascade']),
          ControlDef.toggle('suspendable'),
        ],
      ),
    ],
    build: (context, s) {
      if (s.story == 'connected') {
        if (!ThunderIDProvider.of(context).isSignedIn) return _hint("Sign in to show the signed-in user's own agents.");
        final agentId = s.text('agentId').isNotEmpty ? s.text('agentId') : _picked ?? '';
        if (agentId.isEmpty) {
          return _hint('Set agentId in Controls, or select an agent in the Signed-in user story of PersonalAgentList.');
        }
        return PersonalAgentDetails(
          key: ValueKey('personalAgentDetails/$agentId'),
          agentId: agentId,
          editable: s.flag('editable'),
          deletable: s.flag('deletable'),
          suspendable: s.flag('suspendable'),
          onDeleted: () => s.emit('onDeleted'),
          preferences: _prefs(s),
        );
      }
      final agent = _sampleAgent(s.text('suspension'));
      if (s.story == 'custom') {
        return BasePersonalAgentDetails(
          agent: agent,
          onSuspend: s.flag('suspendable') ? () => s.emit('onSuspend') : null,
          onUnsuspend: s.flag('suspendable') ? () => s.emit('onUnsuspend') : null,
          builder: (context, details) => _CustomPersonalAgentDetails(details: details),
        );
      }
      final state = s.text('state');
      return BasePersonalAgentDetails(
        agent: state == 'loading' ? null : agent,
        isLoading: state == 'loading',
        error: state == 'error' ? 'The action could not be completed. Please try again.' : null,
        onUpdate: s.flag('editable')
            ? (request) async {
                s.emit('onUpdate(${request.grantTypes.length} grant types)');
                return true;
              }
            : null,
        onDelete: s.flag('deletable') ? () => s.emit('onDelete') : null,
        onSuspend: s.flag('suspendable') ? () => s.emit('onSuspend') : null,
        onUnsuspend: s.flag('suspendable') ? () => s.emit('onUnsuspend') : null,
        preferences: _prefs(s),
      );
    },
    code: (s) {
      if (s.story == 'base') {
        final state = s.text('state');
        return 'BasePersonalAgentDetails(\n'
            '  agent: ${state == 'loading' ? 'null' : 'agent'},\n'
            '${state == 'loading' ? '  isLoading: true,\n' : ''}'
            '${state == 'error' ? "  error: 'The action could not be completed. Please try again.',\n" : ''}'
            '${s.flag('editable') ? '  onUpdate: (request) async => true,\n' : ''}'
            '${s.flag('deletable') ? '  onDelete: () {},\n' : ''}'
            '${s.flag('suspendable') ? '  onSuspend: () {},\n  onUnsuspend: () {},\n' : ''}'
            ')';
      }
      final flags = [
        for (final flag in ['editable', 'deletable', 'suspendable'])
          if (s.flag(flag)) '  $flag: true,\n',
      ].join();
      final call = 'PersonalAgentDetails(\n  agentId: agentId,\n$flags';
      return s.story == 'custom'
          ? '$call  builder: (context, details) => Column(\n'
              '    children: [\n'
              "      Text(details.agent?.name ?? ''),\n"
              "      if (details.onUnsuspend != null) TextButton(onPressed: details.onUnsuspend, child: const Text('Resume')),\n"
              '    ],\n'
              '  ),\n'
              ')'
          : '$call)';
    },
  ),
];

/// The custom rendering of the list story: one row per agent with a status dot, drawn with
/// Material widgets.
class _CustomPersonalAgentList extends StatelessWidget {
  final PersonalAgentListState list;

  const _CustomPersonalAgentList({required this.list});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final suspendAll = list.onSuspendAll;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final agent in list.agents)
          ListTile(
            leading: Icon(
              Icons.circle,
              size: 12,
              color: agent.status?.value == AccessStatusValue.suspended ? Colors.amber : Colors.green,
            ),
            title: Text(agent.name, style: TextStyle(color: scheme.onSurface)),
            subtitle: Text(agent.clientId ?? '', style: TextStyle(color: scheme.onSurfaceVariant)),
            onTap: () => list.onSelect?.call(agent),
          ),
        if (suspendAll != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () async {
                final confirmed = await _confirm(context, 'Pause every agent?');
                if (confirmed) suspendAll();
              },
              child: const Text('Pause all'),
            ),
          ),
      ],
    );
  }
}

/// The custom rendering of the details story: the name, the client and the owner's suspension,
/// drawn with Material widgets. Pausing asks for confirmation first.
class _CustomPersonalAgentDetails extends StatelessWidget {
  final PersonalAgentDetailsState details;

  const _CustomPersonalAgentDetails({required this.details});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final agent = details.agent;
    if (agent == null) return const SizedBox.shrink();
    final suspend = details.onSuspend;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(agent.name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: scheme.onSurface)),
            const SizedBox(height: 4),
            Text(
              '${agent.clientId ?? ''} · ${(details.oauth?.grantTypes ?? const []).length} grant types',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (suspend != null)
                  TextButton(
                    onPressed: () async {
                      if (await _confirm(context, 'Pause ${agent.name}?')) suspend();
                    },
                    child: const Text('Pause'),
                  ),
                if (details.onUnsuspend != null)
                  TextButton(onPressed: details.onUnsuspend, child: const Text('Resume')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> _confirm(BuildContext context, String question) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(question),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    ) ??
    false;
