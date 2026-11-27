// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

Map<String, Object?> _agentJson({
  String id = 'pa-1',
  String name = 'Spending',
  List<String>? suspendedBy,
  bool isReadOnly = false,
}) =>
    {
      'id': id,
      'ouId': 'ou-1',
      'type': 'assistant',
      'kind': 'personal-assistant',
      'clientId': 'spend',
      'isReadOnly': isReadOnly,
      'attributes': {
        'name': name,
        'model': 'planner-v1',
        'limits': {'monthly': 200},
      },
      'inboundAuthConfig': [
        {
          'type': 'oauth2',
          'config': {
            'grantTypes': ['urn:openid:params:grant-type:ciba', 'refresh_token'],
            'redirectUris': <String>[],
          },
        },
      ],
      'status': suspendedBy == null
          ? {'value': 'ACTIVE'}
          : {
              'value': 'SUSPENDED',
              'details': {'appliedBy': suspendedBy},
            },
    };

Agent _agent({String id = 'pa-1', String name = 'Spending', List<String>? suspendedBy, bool isReadOnly = false}) =>
    Agent.fromJson(_agentJson(id: id, name: name, suspendedBy: suspendedBy, isReadOnly: isReadOnly));

Widget _bare(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

Finder _key(String key) => find.byKey(Key(key));

Future<void> _openMenuItem(WidgetTester tester, String item) async {
  await tester.tap(_key('thunderid-action-personal-agent-details-menu'));
  await tester.pumpAndSettle();
  await tester.tap(_key('thunderid-action-personal-agent-details-$item'));
  await tester.pumpAndSettle();
}

void main() {
  group('BasePersonalAgentList', () {
    testWidgets('lists the agents with their status and reports selection', (tester) async {
      Agent? selected;
      await tester.pumpWidget(
        _bare(
          BasePersonalAgentList(
            agents: [_agent(), _agent(id: 'pa-2', name: 'Mail', suspendedBy: ['owner'])],
            onSelect: (agent) => selected = agent,
          ),
        ),
      );

      expect(find.text('Personal agents'), findsOneWidget);
      expect(find.text('Spending'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Suspended'), findsOneWidget);

      await tester.tap(find.text('Mail'));
      expect(selected?.id, 'pa-2');
    });

    testWidgets('asks for confirmation before suspending every agent, and shows how many it suspended',
        (tester) async {
      var suspended = 0;
      await tester.pumpWidget(
        _bare(BasePersonalAgentList(agents: [_agent()], onSuspendAll: () => suspended++, suspendedCount: 2)),
      );

      expect(find.text('Agents suspended: 2'), findsOneWidget);
      await tester.tap(_key('thunderid-action-personal-agent-list-suspendAll'));
      await tester.pumpAndSettle();
      expect(suspended, 0);
      expect(find.text('Suspend all your personal agents? They lose access until you unsuspend them.'), findsOneWidget);

      await tester.tap(_key('thunderid-action-personal-agent-list-suspendAll-confirm'));
      expect(suspended, 1);
    });

    testWidgets('offers no suspend-all without a handler or with no agents', (tester) async {
      await tester.pumpWidget(_bare(BasePersonalAgentList(agents: [_agent()])));
      expect(_key('thunderid-action-personal-agent-list-suspendAll'), findsNothing);

      await tester.pumpWidget(_bare(BasePersonalAgentList(agents: const [], onSuspendAll: () {})));
      expect(_key('thunderid-action-personal-agent-list-suspendAll'), findsNothing);
      expect(find.text("You don't have any personal agents."), findsOneWidget);
    });

    testWidgets('hands a builder the agents and the suspend-all action', (tester) async {
      PersonalAgentListState? state;
      await tester.pumpWidget(
        _bare(
          BasePersonalAgentList(
            agents: [_agent()],
            totalResults: 5,
            onSuspendAll: () {},
            builder: (context, s) {
              state = s;
              return Text(s.agents.single.name);
            },
          ),
        ),
      );

      expect(find.text('Spending'), findsOneWidget);
      expect(state?.totalResults, 5);
      expect(state?.onSuspendAll, isNotNull);
    });
  });

  group('BasePersonalAgentDetails', () {
    testWidgets('shows the overview, the attributes, and who holds the agent suspended', (tester) async {
      await tester.pumpWidget(
        _bare(BasePersonalAgentDetails(agent: _agent(suspendedBy: ['organization', 'owner', 'someone-else']))),
      );

      expect(find.text('Spending'), findsWidgets);
      expect(find.text('spend'), findsOneWidget);
      expect(find.text('Backchannel authentication (CIBA), Refresh token'), findsOneWidget);
      expect(find.text('None'), findsOneWidget);
      expect(find.text('planner-v1'), findsOneWidget);
      expect(find.text('{"monthly":200}'), findsOneWidget);
      expect(find.text('You suspended this agent.'), findsOneWidget);
      expect(
        find.text('Your organization suspended this agent. Only an administrator can lift that suspension.'),
        findsOneWidget,
      );
    });

    testWidgets('offers no action the app did not turn on', (tester) async {
      await tester.pumpWidget(_bare(BasePersonalAgentDetails(agent: _agent())));

      expect(_key('thunderid-action-personal-agent-details-edit'), findsNothing);
      expect(_key('thunderid-action-personal-agent-details-menu'), findsNothing);
    });

    testWidgets('edits the agent and saves the whole request', (tester) async {
      UpdateMeAgentRequest? saved;
      await tester.pumpWidget(
        _bare(
          BasePersonalAgentDetails(
            agent: _agent(),
            onUpdate: (r) async {
              saved = r;
              return true;
            },
          ),
        ),
      );

      await tester.tap(_key('thunderid-action-personal-agent-details-edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit agent'), findsOneWidget);

      await tester.enterText(_key('thunderid-field-personal-agent-details-name'), 'Spender');
      await tester.pump();
      await tester.ensureVisible(_key('thunderid-field-personal-agent-details-grantTypes-refresh_token'));
      await tester.tap(_key('thunderid-field-personal-agent-details-grantTypes-refresh_token'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_key('thunderid-action-personal-agent-details-edit-save'));
      await tester.tap(_key('thunderid-action-personal-agent-details-edit-save'));
      await tester.pumpAndSettle();

      expect(saved?.attributes['name'], 'Spender');
      expect(saved?.attributes['limits'], {'monthly': 200});
      expect(saved?.grantTypes, ['urn:openid:params:grant-type:ciba']);
      expect(saved?.redirectUris, isEmpty);
      expect(find.text('Edit agent'), findsNothing);
    });

    testWidgets('keeps the changes until the update succeeds', (tester) async {
      final results = [false, true];
      var calls = 0;
      await tester.pumpWidget(_bare(BasePersonalAgentDetails(agent: _agent(), onUpdate: (_) async => results[calls++])));
      await tester.tap(_key('thunderid-action-personal-agent-details-edit'));
      await tester.pumpAndSettle();
      await tester.enterText(_key('thunderid-field-personal-agent-details-name'), 'Spender');
      await tester.pump();

      await tester.ensureVisible(_key('thunderid-action-personal-agent-details-edit-save'));
      await tester.tap(_key('thunderid-action-personal-agent-details-edit-save'));
      await tester.pumpAndSettle();

      expect(find.text('Edit agent'), findsOneWidget);
      expect(find.text('Spender'), findsOneWidget);

      await tester.tap(_key('thunderid-action-personal-agent-details-edit-save'));
      await tester.pumpAndSettle();

      expect(find.text('Edit agent'), findsNothing);
      expect(calls, 2);
    });

    testWidgets('discards the draft when another agent is shown', (tester) async {
      Widget details(Agent agent) => _bare(BasePersonalAgentDetails(agent: agent, onUpdate: (_) async => true));
      await tester.pumpWidget(details(_agent()));
      await tester.tap(_key('thunderid-action-personal-agent-details-edit'));
      await tester.pumpAndSettle();
      await tester.enterText(_key('thunderid-field-personal-agent-details-name'), 'Spender');
      await tester.pump();

      await tester.pumpWidget(details(_agent(id: 'pa-2', name: 'Travel')));
      await tester.pumpWidget(details(_agent()));
      await tester.pumpAndSettle();

      expect(find.text('Edit agent'), findsNothing);
    });

    testWidgets('asks for confirmation before suspending, and unsuspends straight away', (tester) async {
      var suspended = 0;
      var unsuspended = 0;
      await tester.pumpWidget(
        _bare(BasePersonalAgentDetails(agent: _agent(), onSuspend: () => suspended++, onUnsuspend: () => unsuspended++)),
      );

      await _openMenuItem(tester, 'suspend');
      expect(suspended, 0);
      expect(find.text('Suspend Spending? It loses access until you unsuspend it.'), findsOneWidget);
      await tester.tap(_key('thunderid-action-personal-agent-details-suspend-confirm'));
      await tester.pumpAndSettle();
      expect(suspended, 1);

      await tester.pumpWidget(
        _bare(
          BasePersonalAgentDetails(
            agent: _agent(suspendedBy: ['owner']),
            onSuspend: () => suspended++,
            onUnsuspend: () => unsuspended++,
          ),
        ),
      );
      await _openMenuItem(tester, 'unsuspend');
      expect(unsuspended, 1);
    });

    testWidgets('cancelling a delete runs nothing', (tester) async {
      var deleted = 0;
      await tester.pumpWidget(_bare(BasePersonalAgentDetails(agent: _agent(), onDelete: () => deleted++)));

      await _openMenuItem(tester, 'delete');
      expect(find.text('Delete Spending? This cannot be undone.'), findsOneWidget);
      await tester.tap(_key('thunderid-action-personal-agent-details-delete-cancel'));
      await tester.pumpAndSettle();

      expect(deleted, 0);
      expect(_key('thunderid-action-personal-agent-details-menu'), findsOneWidget);
    });

    testWidgets('a pending confirmation closes when the agent changes', (tester) async {
      var deleted = 0;
      await tester.pumpWidget(_bare(BasePersonalAgentDetails(agent: _agent(), onDelete: () => deleted++)));
      await _openMenuItem(tester, 'delete');

      await tester.pumpWidget(
        _bare(BasePersonalAgentDetails(agent: _agent(id: 'pa-2', name: 'Mail'), onDelete: () => deleted++)),
      );

      expect(find.text('Delete Mail? This cannot be undone.'), findsNothing);
      expect(_key('thunderid-action-personal-agent-details-delete-confirm'), findsNothing);
      expect(deleted, 0);
    });

    testWidgets('never edits or deletes a read-only agent', (tester) async {
      await tester.pumpWidget(
        _bare(BasePersonalAgentDetails(agent: _agent(isReadOnly: true), onUpdate: (_) async => true, onDelete: () {})),
      );

      expect(_key('thunderid-action-personal-agent-details-edit'), findsNothing);
      expect(_key('thunderid-action-personal-agent-details-menu'), findsNothing);
    });

    testWidgets('hands a builder only the actions that apply to the agent', (tester) async {
      PersonalAgentDetailsState? state;
      await tester.pumpWidget(
        _bare(
          BasePersonalAgentDetails(
            agent: _agent(suspendedBy: ['owner']),
            onUpdate: (_) async => true,
            onDelete: () {},
            onSuspend: () {},
            onUnsuspend: () {},
            builder: (context, s) {
              state = s;
              return Text(s.agent!.name);
            },
          ),
        ),
      );

      expect(find.text('Spending'), findsOneWidget);
      expect(state?.oauth?.grantTypes, ['urn:openid:params:grant-type:ciba', 'refresh_token']);
      expect(state?.onUpdate, isNotNull);
      expect(state?.onDelete, isNotNull);
      expect(state?.onSuspend, isNull);
      expect(state?.onUnsuspend, isNotNull);
    });
  });

  group('connected', () {
    const channel = MethodChannel('dev.thunderid/sdk');
    final List<MethodCall> log = [];

    setUp(() {
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        log.add(call);
        return switch (call.method) {
          'initialize' => true,
          'isSignedIn' => false,
          'getMeAgents' => {
              'totalResults': 1,
              'agents': [_agentJson()],
            },
          'getMeAgent' => _agentJson(),
          'suspendMeAgent' => null,
          _ => null,
        };
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    Widget app(Widget child) => MaterialApp(
          home: ThunderIDProvider(
            config: const ThunderIDConfig(baseUrl: 'https://idp.example.com', clientId: 'test'),
            child: Scaffold(body: SingleChildScrollView(child: child)),
          ),
        );

    testWidgets('PersonalAgentList lists only personal agents', (tester) async {
      await tester.pumpWidget(app(const PersonalAgentList()));
      await tester.pumpAndSettle();

      expect(find.text('Spending'), findsOneWidget);
      final call = log.firstWhere((c) => c.method == 'getMeAgents');
      expect((call.arguments as Map<Object?, Object?>)['kind'], 'personal-assistant');
      expect(_key('thunderid-action-personal-agent-list-suspendAll'), findsNothing);
    });

    testWidgets('PersonalAgentDetails suspends after confirmation and reloads the agent', (tester) async {
      await tester.pumpWidget(app(const PersonalAgentDetails(agentId: 'pa-1', suspendable: true)));
      await tester.pumpAndSettle();
      expect(log.where((c) => c.method == 'getMeAgent'), hasLength(1));

      await _openMenuItem(tester, 'suspend');
      await tester.tap(_key('thunderid-action-personal-agent-details-suspend-confirm'));
      await tester.pumpAndSettle();

      expect((log.firstWhere((c) => c.method == 'suspendMeAgent').arguments as Map<Object?, Object?>)['id'], 'pa-1');
      expect(log.where((c) => c.method == 'getMeAgent'), hasLength(2));
    });

    testWidgets('PersonalAgentDetails shows a deleted agent as gone, without an onDeleted', (tester) async {
      await tester.pumpWidget(app(const PersonalAgentDetails(agentId: 'pa-1', deletable: true)));
      await tester.pumpAndSettle();
      expect(find.text('Spending'), findsWidgets);

      await _openMenuItem(tester, 'delete');
      await tester.tap(_key('thunderid-action-personal-agent-details-delete-confirm'));
      await tester.pumpAndSettle();

      expect((log.firstWhere((c) => c.method == 'deleteMeAgent').arguments as Map<Object?, Object?>)['id'], 'pa-1');
      expect(find.text('Spending'), findsNothing);
      expect(_key('thunderid-action-personal-agent-details-menu'), findsNothing);
    });
  });

  group('admin agent views', () {
    testWidgets('AgentList marks a personal agent', (tester) async {
      await tester.pumpWidget(
        _bare(BaseAgentList(agents: [_agent(), Agent.fromJson(const {'id': 'a-2', 'ouId': 'ou', 'type': 'bot', 'display': 'Bot'})])),
      );

      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('Bot'), findsOneWidget);
    });

    testWidgets('AgentDetails shows the owner, the kind of a personal agent, and who holds it suspended',
        (tester) async {
      final agent = Agent.fromJson({
        ..._agentJson(suspendedBy: ['owner', 'cascade', 'auditor']),
        'owner': {'id': 'usr-1'},
      });
      await tester.pumpWidget(_bare(BaseAgentDetails(agent: agent)));

      expect(find.text('usr-1'), findsOneWidget);
      expect(find.text('Personal'), findsOneWidget);
      expect(find.text("Owner, Owner's account suspension, auditor"), findsOneWidget);
    });

    testWidgets('AgentDetails names the organization for a suspension that names no party', (tester) async {
      final agent = Agent.fromJson(const {
        'id': 'a-1',
        'ouId': 'ou',
        'type': 'bot',
        'status': {'value': 'SUSPENDED'},
      });
      await tester.pumpWidget(_bare(BaseAgentDetails(agent: agent)));

      expect(find.text('Suspended by'), findsOneWidget);
      expect(find.text('Organization'), findsOneWidget);
    });

    testWidgets('AgentDetails shows no kind or suspending party for an ordinary agent', (tester) async {
      await tester.pumpWidget(
        _bare(BaseAgentDetails(agent: Agent.fromJson(const {'id': 'a-1', 'ouId': 'ou', 'type': 'bot'}))),
      );

      expect(find.text('No owner'), findsOneWidget);
      expect(find.text('Kind'), findsNothing);
      expect(find.text('Suspended by'), findsNothing);
    });
  });
}
