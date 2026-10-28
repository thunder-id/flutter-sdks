// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

/// A fake server that answers like ThunderID: the `flow` server configuration ([configured],
/// handle by key), the administration flow listing (one flow per configured handle, with the id
/// `id-<handle>`), flow execution, and [resources] by `METHOD path`. Every request is recorded.
class _FlowServer {
  final Map<String, String> configured;
  final Map<String, Object?> resources;
  final List<ManagementRequest> requests = [];

  _FlowServer({this.configured = const {}, this.resources = const {}});

  ManagementResponse _json(Object? body) =>
      ManagementResponse(statusCode: 200, statusText: 'OK', body: body == null ? '' : jsonEncode(body));

  Future<ManagementResponse> fetch(ManagementRequest request) async {
    requests.add(request);
    final path = request.url.path;
    if (path == '/server-config/flow') {
      return _json({
        'merged': {
          for (final entry in configured.entries) entry.key: {'defaultHandle': entry.value},
        },
      });
    }
    if (path == '/flows') {
      return _json({
        'flows': [
          for (final handle in configured.values) {'flowType': 'ADMINISTRATION', 'handle': handle, 'id': 'id-$handle'},
        ],
      });
    }
    if (path == '/flow/execute') {
      return _json({
        'flowStatus': 'COMPLETE',
        'data': {'additionalData': <String, String>{}},
      });
    }
    final key = '${request.method} $path';
    if (resources.containsKey(key)) return _json(resources[key]);
    if (request.method == 'GET' && (path.endsWith('/groups') || path.endsWith('/roles'))) {
      return _json({'totalResults': 0, 'groups': <Object?>[], 'roles': <Object?>[]});
    }
    return const ManagementResponse(statusCode: 404, statusText: 'Not Found');
  }

  bool get readFlowConfiguration => requests.any((r) => r.url.path.startsWith('/server-config/'));

  List<Object?> get executions => [
        for (final r in requests)
          if (r.url.path == '/flow/execute') jsonDecode(r.body!),
      ];
}

Widget _app(_FlowServer server, Widget child) => MaterialApp(
      home: ThunderIDProvider(
        config: ThunderIDConfig(
          baseUrl: 'https://idp.example.com',
          clientId: 'test',
          http: ThunderIDHttpConfig(fetcher: server.fetch),
        ),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

Widget _bare(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

Finder _key(String key) => find.byKey(Key(key));

const _lockedUser = ManagedUser(
  id: 'u-1',
  ouId: 'ou-1',
  type: 'customer',
  display: 'Aiko Tanaka',
  status: AccessStatus(value: AccessStatusValue.locked),
);

const Map<String, Object?> _lockedUserJson = {
  'id': 'u-1',
  'ouId': 'ou-1',
  'type': 'customer',
  'display': 'Aiko Tanaka',
  'status': {'value': 'LOCKED'},
};

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.thunderid/sdk'),
      (call) async => call.method == 'initialize' ? true : (call.method == 'isSignedIn' ? false : null),
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dev.thunderid/sdk'), null);
  });

  group('BaseUserDetails', () {
    testWidgets('shows the translated access status', (tester) async {
      await tester.pumpWidget(_bare(const BaseUserDetails(user: _lockedUser)));

      expect(find.text('Locked'), findsOneWidget);
    });

    testWidgets('shows a status this SDK does not know as sent', (tester) async {
      await tester.pumpWidget(
        _bare(
          const BaseUserDetails(
            user: ManagedUser(id: 'u-1', ouId: 'ou-1', type: 'customer', status: AccessStatus(value: 'ARCHIVED')),
          ),
        ),
      );

      expect(find.text('ARCHIVED'), findsOneWidget);
    });

    testWidgets('offers no lifecycle actions without a handler', (tester) async {
      await tester.pumpWidget(
        _bare(
          const BaseUserDetails(
            user: _lockedUser,
            lifecycleActions: [AccountLifecycleAction.unlock, AccountLifecycleAction.suspend],
          ),
        ),
      );

      expect(_key('thunderid-action-user-details-unlock'), findsNothing);
      expect(_key('thunderid-action-user-details-suspend'), findsNothing);
    });

    testWidgets('unlocks straight away, and asks for confirmation and an optional note before suspending',
        (tester) async {
      final calls = <(AccountLifecycleAction, String?)>[];
      await tester.pumpWidget(
        _bare(
          BaseUserDetails(
            user: _lockedUser,
            lifecycleActions: const [AccountLifecycleAction.unlock, AccountLifecycleAction.suspend],
            onLifecycleAction: (action, note) => calls.add((action, note)),
          ),
        ),
      );

      await tester.tap(_key('thunderid-action-user-details-unlock'));
      await tester.pump();
      expect(calls, [(AccountLifecycleAction.unlock, null)]);

      await tester.tap(_key('thunderid-action-user-details-suspend'));
      await tester.pump();
      expect(calls, hasLength(1), reason: 'the first tap only asks');
      expect(
        find.text('Suspend Aiko Tanaka? It can no longer sign in, and its sessions and tokens are revoked.'),
        findsOneWidget,
      );
      expect(find.text('Note (optional)'), findsOneWidget);

      await tester.enterText(_key('thunderid-field-user-details-operatorNote'), ' Ticket 4521 ');
      await tester.tap(_key('thunderid-action-user-details-suspend-confirm'));
      await tester.pump();

      expect(calls.last, (AccountLifecycleAction.suspend, 'Ticket 4521'));
      expect(_key('thunderid-field-user-details-operatorNote'), findsNothing);
    });

    testWidgets('limits the operator note to 100 characters', (tester) async {
      await tester.pumpWidget(
        _bare(
          BaseUserDetails(
            user: _lockedUser,
            lifecycleActions: const [AccountLifecycleAction.suspend],
            onLifecycleAction: (_, __) {},
          ),
        ),
      );

      await tester.tap(_key('thunderid-action-user-details-suspend'));
      await tester.pump();

      final field = tester.widget<TextField>(_key('thunderid-field-user-details-operatorNote'));
      expect(field.maxLength, 100);
    });

    testWidgets('cancelling a suspension runs nothing', (tester) async {
      final calls = <AccountLifecycleAction>[];
      await tester.pumpWidget(
        _bare(
          BaseUserDetails(
            user: _lockedUser,
            lifecycleActions: const [AccountLifecycleAction.suspend],
            onLifecycleAction: (action, _) => calls.add(action),
          ),
        ),
      );

      await tester.tap(_key('thunderid-action-user-details-suspend'));
      await tester.pump();
      await tester.tap(_key('thunderid-action-user-details-suspend-cancel'));
      await tester.pump();

      expect(calls, isEmpty);
      expect(_key('thunderid-action-user-details-suspend'), findsOneWidget);
    });

    testWidgets('hands a builder the lifecycle actions, for read-only users too', (tester) async {
      UserDetailsState? state;
      void onLifecycleAction(AccountLifecycleAction action, String? note) {}
      await tester.pumpWidget(
        _bare(
          BaseUserDetails(
            user: const ManagedUser(
              id: 'u-1',
              ouId: 'ou-1',
              type: 'customer',
              isReadOnly: true,
              status: AccessStatus(value: AccessStatusValue.locked),
            ),
            lifecycleActions: const [AccountLifecycleAction.unlock],
            onLifecycleAction: onLifecycleAction,
            isRunningLifecycleAction: true,
            onDelete: () {},
            builder: (context, s) {
              state = s;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(state!.lifecycleActions, [AccountLifecycleAction.unlock]);
      expect(state!.onLifecycleAction, onLifecycleAction);
      expect(state!.isRunningLifecycleAction, isTrue);
      expect(state!.onDelete, isNull, reason: 'delete stays off for a read-only user');
    });

    testWidgets('hands a builder no lifecycle actions without a handler', (tester) async {
      UserDetailsState? state;
      await tester.pumpWidget(
        _bare(
          BaseUserDetails(
            user: _lockedUser,
            lifecycleActions: const [AccountLifecycleAction.unlock],
            builder: (context, s) {
              state = s;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(state!.lifecycleActions, isEmpty);
      expect(state!.onLifecycleAction, isNull);
    });
  });

  group('UserDetails', () {
    testWidgets('reads no flow configuration unless lifecycle actions are on', (tester) async {
      final server = _FlowServer(resources: {'GET /users/u-1': _lockedUserJson});
      await tester.pumpWidget(_app(server, const UserDetails(userId: 'u-1')));
      await tester.pumpAndSettle();

      expect(find.text('Aiko Tanaka'), findsWidgets);
      expect(find.text('Locked'), findsOneWidget);
      expect(server.readFlowConfiguration, isFalse);
      expect(_key('thunderid-action-user-details-unlock'), findsNothing);
    });

    testWidgets('offers only the actions whose flow is configured, and runs one through its flow', (tester) async {
      final server = _FlowServer(
        configured: {'userUnlockFlow': 'unlock-user'},
        resources: {'GET /users/u-1': _lockedUserJson},
      );
      await tester.pumpWidget(_app(server, const UserDetails(userId: 'u-1', lifecycleActions: true)));
      await tester.pumpAndSettle();

      expect(_key('thunderid-action-user-details-suspend'), findsNothing);
      await tester.tap(_key('thunderid-action-user-details-unlock'));
      await tester.pumpAndSettle();

      expect(server.executions, [
        {
          'flowId': 'id-unlock-user',
          'inputs': {'subject': 'u-1'},
        },
      ]);
      expect(
        server.requests.where((r) => r.method == 'GET' && r.url.path == '/users/u-1'),
        hasLength(2),
        reason: 'the action reloads the user',
      );
    });

    testWidgets('shows a translated message when an action fails, never the server text', (tester) async {
      final server = _FlowServer(
        configured: {'userUnlockFlow': 'missing'},
        resources: {'GET /users/u-1': _lockedUserJson},
      );
      await tester.pumpWidget(_app(server, const UserDetails(userId: 'u-1', lifecycleActions: true)));
      await tester.pumpAndSettle();
      // The listing names the flow, so the action is offered; drop it before running so the run
      // finds the configured flow gone.
      server.configured.remove('userUnlockFlow');

      await tester.tap(_key('thunderid-action-user-details-unlock'));
      await tester.pumpAndSettle();

      expect(find.text('The action could not be completed.'), findsOneWidget);
      expect(server.executions, isEmpty);
    });

    testWidgets('deletes through the user deletion flow in flow mode', (tester) async {
      final server = _FlowServer(
        configured: {'userDeletionFlow': 'delete-user'},
        resources: {'GET /users/u-1': _lockedUserJson},
      );
      var deleted = false;
      await tester.pumpWidget(
        _app(
          server,
          UserDetails(
            userId: 'u-1',
            deletable: true,
            administrationMode: AdministrationMode.flow,
            onDeleted: () => deleted = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_key('thunderid-action-user-details-delete'));
      await tester.pumpAndSettle();
      await tester.tap(_key('thunderid-action-user-details-delete-confirm'));
      await tester.pumpAndSettle();

      expect(deleted, isTrue);
      expect(server.executions, [
        {
          'flowId': 'id-delete-user',
          'inputs': {'subject': 'u-1'},
        },
      ]);
      expect(server.requests.where((r) => r.method == 'DELETE'), isEmpty);
    });

    testWidgets('deletes through the API by default, without reading the flow configuration', (tester) async {
      final server = _FlowServer(
        configured: {'userDeletionFlow': 'delete-user'},
        resources: {'GET /users/u-1': _lockedUserJson, 'DELETE /users/u-1': null},
      );
      await tester.pumpWidget(_app(server, const UserDetails(userId: 'u-1', deletable: true)));
      await tester.pumpAndSettle();

      await tester.tap(_key('thunderid-action-user-details-delete'));
      await tester.pumpAndSettle();
      await tester.tap(_key('thunderid-action-user-details-delete-confirm'));
      await tester.pumpAndSettle();

      expect(server.requests.where((r) => r.method == 'DELETE'), hasLength(1));
      expect(server.readFlowConfiguration, isFalse);
    });
  });

  testWidgets('GroupMembers removes a member through the membership removal flow in flow mode', (tester) async {
    final server = _FlowServer(
      configured: {'groupMembershipRemovalFlow': 'remove-member'},
      resources: {
        'GET /groups/g-1/members': {
          'totalResults': 1,
          'members': [
            {'id': 'u-1', 'type': 'user', 'display': 'Aiko Tanaka'},
          ],
        },
        'GET /users': {'totalResults': 0, 'users': <Object?>[]},
        'GET /agents': {'totalResults': 0, 'agents': <Object?>[]},
      },
    );
    await tester.pumpWidget(
      _app(server, const GroupMembers(groupId: 'g-1', editable: true, administrationMode: AdministrationMode.flow)),
    );
    await tester.pumpAndSettle();

    await tester.tap(_key('thunderid-action-group-members-remove-u-1'));
    await tester.pumpAndSettle();

    expect(server.executions, hasLength(1));
    expect(server.requests.where((r) => r.url.path.endsWith('/members/remove')), isEmpty);
  });

  testWidgets('RoleAssignments removes an assignment through the assignment removal flow in flow mode', (tester) async {
    final server = _FlowServer(
      configured: {'roleAssignmentRemovalFlow': 'remove-assignment'},
      resources: {
        'GET /roles/r-1/assignments': {
          'totalResults': 1,
          'assignments': [
            {'id': 'u-1', 'type': 'user', 'display': 'Aiko Tanaka'},
          ],
        },
        'GET /users': {'totalResults': 0, 'users': <Object?>[]},
        'GET /agents': {'totalResults': 0, 'agents': <Object?>[]},
      },
    );
    await tester.pumpWidget(
      _app(server, const RoleAssignments(roleId: 'r-1', editable: true, administrationMode: AdministrationMode.flow)),
    );
    await tester.pumpAndSettle();

    await tester.tap(_key('thunderid-action-role-assignments-remove-u-1'));
    await tester.pumpAndSettle();

    expect(server.executions, hasLength(1));
    expect(server.requests.where((r) => r.url.path.endsWith('/assignments/remove')), isEmpty);
  });

  testWidgets('AgentDetails unsuspends an agent through its flow', (tester) async {
    final server = _FlowServer(
      configured: {'agentSuspendFlow': 'suspend-agent', 'agentUnsuspendFlow': 'unsuspend-agent'},
      resources: {
        'GET /agents/a-1': {
          'id': 'a-1',
          'name': 'Billing bot',
          'ouId': 'ou-1',
          'type': 'bot',
          'status': {'value': 'SUSPENDED'},
        },
      },
    );
    await tester.pumpWidget(_app(server, const AgentDetails(agentId: 'a-1', lifecycleActions: true)));
    await tester.pumpAndSettle();

    expect(find.text('Suspended'), findsOneWidget);
    expect(_key('thunderid-action-agent-details-suspend'), findsNothing);
    await tester.tap(_key('thunderid-action-agent-details-unsuspend'));
    await tester.pumpAndSettle();
    expect(find.text('Unsuspend Billing bot? Its access is restored, unless it is also locked.'), findsOneWidget);
    expect(_key('thunderid-field-agent-details-operatorNote'), findsNothing, reason: 'only a suspension takes a note');

    await tester.tap(_key('thunderid-action-agent-details-unsuspend-confirm'));
    await tester.pumpAndSettle();

    expect(server.executions, [
      {
        'flowId': 'id-unsuspend-agent',
        'inputs': {'subject': 'a-1'},
      },
    ]);
  });

  testWidgets('ApplicationDetails suspends an application without asking for an operator note', (tester) async {
    final server = _FlowServer(
      configured: {'applicationSuspendFlow': 'suspend-app'},
      resources: {
        'GET /applications/app-1': {
          'id': 'app-1',
          'name': 'Portal',
          'status': {'value': 'ACTIVE'},
        },
      },
    );
    await tester.pumpWidget(_app(server, const ApplicationDetails(applicationId: 'app-1', lifecycleActions: true)));
    await tester.pumpAndSettle();

    expect(find.text('Active'), findsOneWidget);
    await tester.tap(_key('thunderid-action-application-details-suspend'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Suspend Portal?'), findsOneWidget);
    expect(_key('thunderid-field-application-details-operatorNote'), findsNothing);

    await tester.tap(_key('thunderid-action-application-details-suspend-confirm'));
    await tester.pumpAndSettle();

    expect(server.executions, [
      {
        'flowId': 'id-suspend-app',
        'inputs': {'subject': 'app-1'},
      },
    ]);
  });

  testWidgets('ApplicationDetails hands a builder the lifecycle actions it offers', (tester) async {
    final server = _FlowServer(
      configured: {'applicationSuspendFlow': 'suspend-app', 'applicationUnsuspendFlow': 'unsuspend-app'},
      resources: {
        'GET /applications/app-1': {
          'id': 'app-1',
          'name': 'Portal',
          'status': {'value': 'SUSPENDED'},
        },
      },
    );
    ApplicationDetailsState? state;
    await tester.pumpWidget(
      _app(
        server,
        ApplicationDetails(
          applicationId: 'app-1',
          lifecycleActions: true,
          builder: (context, s) {
            state = s;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(state!.application?.status?.value, AccessStatusValue.suspended);
    expect(state!.lifecycleActions, [AccountLifecycleAction.unsuspend]);

    state!.onLifecycleAction!(AccountLifecycleAction.unsuspend, null);
    await tester.pumpAndSettle();

    expect(server.executions, [
      {
        'flowId': 'id-unsuspend-app',
        'inputs': {'subject': 'app-1'},
      },
    ]);
  });
}
