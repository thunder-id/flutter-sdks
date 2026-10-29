// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

/// A fake management server: answers by `METHOD path` and records every request.
class _FakeServer {
  final Map<String, ManagementResponse> routes = {};
  final List<ManagementRequest> requests = [];

  void on(String method, String path, Object? body, {int status = 200}) {
    routes['$method $path'] = ManagementResponse(
      statusCode: status,
      statusText: status == 403 ? 'Forbidden' : 'OK',
      body: body == null ? '' : jsonEncode(body),
    );
  }

  Future<ManagementResponse> fetch(ManagementRequest request) async {
    requests.add(request);
    return routes['${request.method} ${request.url.path}'] ??
        const ManagementResponse(statusCode: 404, statusText: 'Not Found');
  }

  Iterable<ManagementRequest> where(String method, String path) =>
      requests.where((r) => r.method == method && r.url.path == path);
}

Widget _app(_FakeServer server, Widget child, {ThunderIDPreferences? preferences}) => MaterialApp(
      home: ThunderIDProvider(
        config: ThunderIDConfig(
          baseUrl: 'https://idp.example.com',
          clientId: 'test',
          preferences: preferences,
          http: ThunderIDHttpConfig(fetcher: server.fetch),
        ),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  late _FakeServer server;

  setUp(() {
    server = _FakeServer();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.thunderid/sdk'),
      (call) async => call.method == 'initialize' ? true : (call.method == 'isSignedIn' ? false : null),
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dev.thunderid/sdk'), null);
  });

  group('UserList', () {
    testWidgets('renders users with stable identifiers and reports selection', (tester) async {
      server.on('GET', '/users', {
        'totalResults': 2,
        'users': [
          {
            'id': 'u1',
            'ouId': 'ou1',
            'ouHandle': 'default',
            'type': 'customer',
            'attributes': {'given_name': 'Ada', 'family_name': 'Lovelace'},
          },
          {'id': 'u2', 'ouId': 'ou1', 'type': 'customer', 'display': 'Grace'},
        ],
      });
      ManagedUser? selected;
      await tester.pumpWidget(_app(server, UserList(onSelect: (user) => selected = user)));
      await tester.pumpAndSettle();

      expect(find.text('Users'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('Grace'), findsOneWidget);
      expect(find.byKey(const Key('thunderid-admin-user-list')), findsOneWidget);
      expect(server.requests.single.url.queryParameters, {'include': 'display', 'limit': '20', 'offset': '0'});

      await tester.tap(find.byKey(const Key('thunderid-admin-user-list-row-u2')));
      expect(selected?.id, 'u2');
    });

    testWidgets('shows the translated forbidden message, never the server text', (tester) async {
      server.on('GET', '/users', {'description': 'Insufficient scope: system:user'}, status: 403);
      await tester.pumpWidget(_app(server, const UserList()));
      await tester.pumpAndSettle();

      expect(find.text('You do not have permission to do this.'), findsOneWidget);
      expect(find.textContaining('Insufficient scope'), findsNothing);
    });

    testWidgets('uses translations from preferences.i18n.bundles', (tester) async {
      server.on('GET', '/users', {'totalResults': 0, 'users': <Object?>[]});
      await tester.pumpWidget(
        _app(
          server,
          const UserList(),
          preferences: const ThunderIDPreferences(
            i18n: I18nPreferences(
              bundles: {
                'en-US': {'admin.users.list.title': 'People', 'admin.users.list.empty': 'Nobody here.'},
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('People'), findsOneWidget);
      expect(find.text('Nobody here.'), findsOneWidget);
    });
  });

  group('UserDetails', () {
    void serveUser() {
      server.on('GET', '/users/u1', {
        'id': 'u1',
        'ouId': 'ou1',
        'type': 'customer',
        'attributes': {'username': 'ada', 'password': 'never-shown'},
      });
      server.on('GET', '/users/u1/groups', {
        'totalResults': 1,
        'groups': [
          {'id': 'g1', 'name': 'Engineering', 'ouId': 'ou1'},
        ],
      });
    }

    testWidgets('is read-only by default and hides secret attributes', (tester) async {
      serveUser();
      await tester.pumpWidget(_app(server, const UserDetails(userId: 'u1')));
      await tester.pumpAndSettle();

      expect(find.text('ada'), findsWidgets);
      expect(find.text('Engineering'), findsOneWidget);
      expect(find.text('never-shown'), findsNothing);
      expect(find.byKey(const Key('thunderid-action-user-details-delete')), findsNothing);
      expect(find.byKey(const Key('thunderid-action-user-details-edit')), findsNothing);
    });

    testWidgets('deletes only after confirmation when deletable', (tester) async {
      serveUser();
      server.on('DELETE', '/users/u1', null, status: 204);
      var deleted = false;
      await tester.pumpWidget(
        _app(server, UserDetails(userId: 'u1', deletable: true, onDeleted: () => deleted = true)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('thunderid-action-user-details-delete')));
      await tester.pumpAndSettle();
      expect(server.where('DELETE', '/users/u1'), isEmpty, reason: 'the first tap only asks');
      expect(find.text('Delete ada?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('thunderid-action-user-details-delete-confirm')));
      await tester.pumpAndSettle();
      expect(server.where('DELETE', '/users/u1'), hasLength(1));
      expect(deleted, isTrue);
    });
  });

  group('GroupMembers', () {
    void serveMembers() {
      server.on('GET', '/groups/g1/members', {
        'totalResults': 1,
        'members': [
          {'id': 'u1', 'type': 'user', 'display': 'Ada'},
        ],
      });
      server.on('GET', '/users', {
        'totalResults': 2,
        'users': [
          {'id': 'u1', 'ouId': 'ou1', 'type': 'customer', 'display': 'Ada'},
          {'id': 'u2', 'ouId': 'ou1', 'type': 'customer', 'display': 'Grace'},
        ],
      });
      server.on('GET', '/agents', {'totalResults': 0, 'agents': <Object?>[]});
      server.on('POST', '/groups/g1/members/add', {'id': 'g1', 'name': 'Team', 'ouId': 'ou1'});
      server.on('POST', '/groups/g1/members/remove', {'id': 'g1', 'name': 'Team', 'ouId': 'ou1'});
    }

    testWidgets('offers no add or remove unless editable', (tester) async {
      serveMembers();
      await tester.pumpWidget(_app(server, const GroupMembers(groupId: 'g1')));
      await tester.pumpAndSettle();

      expect(find.text('Ada'), findsOneWidget);
      expect(find.byKey(const Key('thunderid-action-group-members-add')), findsNothing);
      expect(find.byKey(const Key('thunderid-action-group-members-remove-u1')), findsNothing);
      expect(server.where('GET', '/users'), isEmpty, reason: 'candidates load only when editable');
    });

    testWidgets('adds and removes members when editable', (tester) async {
      serveMembers();
      await tester.pumpWidget(_app(server, const GroupMembers(groupId: 'g1', editable: true)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('thunderid-field-group-members-identity')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grace').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('thunderid-action-group-members-add')));
      await tester.pumpAndSettle();

      final add = server.where('POST', '/groups/g1/members/add').single;
      expect(jsonDecode(add.body!), {
        'members': [
          {'id': 'u2', 'type': 'user'},
        ],
      });
      expect(server.where('GET', '/groups/g1/members').length, 2, reason: 'the add reloads the members');

      await tester.tap(find.byKey(const Key('thunderid-action-group-members-remove-u1')));
      await tester.pumpAndSettle();
      expect(jsonDecode(server.where('POST', '/groups/g1/members/remove').single.body!), {
        'members': [
          {'id': 'u1', 'type': 'user'},
        ],
      });
    });

    testWidgets('lists candidates from its organization unit and drops them when it changes', (tester) async {
      serveMembers();
      server.on('GET', '/agents', {
        'totalResults': 1,
        'agents': [
          {'id': 'a1', 'ouId': 'ou1', 'type': 'default', 'attributes': {'name': 'Bot'}},
        ],
      });
      late GroupMembersState state;
      Widget view(String ouId) => _app(
            server,
            GroupMembers(
              groupId: 'g1',
              editable: true,
              ouId: ouId,
              builder: (context, members) {
                state = members;
                return const SizedBox.shrink();
              },
            ),
          );

      await tester.pumpWidget(view('ou1'));
      await tester.pumpAndSettle();

      for (final path in ['/users', '/agents']) {
        expect(server.where('GET', path).last.url.queryParameters['filter'], 'ouId eq "ou1"');
      }
      expect(state.candidates![GroupMemberType.user], hasLength(2));
      expect(state.candidates![GroupMemberType.agent], hasLength(1));

      for (final path in ['/users', '/agents']) {
        server.on('GET', path, {'message': 'failed'}, status: 500);
      }
      await tester.pumpWidget(view('ou2'));
      await tester.pumpAndSettle();

      for (final path in ['/users', '/agents']) {
        expect(server.where('GET', path).last.url.queryParameters['filter'], 'ouId eq "ou2"');
      }
      expect(state.candidates![GroupMemberType.user], isEmpty);
      expect(state.candidates![GroupMemberType.agent], isEmpty);
    });

    testWidgets('lists no candidates for an organization unit that makes no filter', (tester) async {
      serveMembers();
      late GroupMembersState state;
      await tester.pumpWidget(
        _app(
          server,
          GroupMembers(
            groupId: 'g1',
            editable: true,
            ouId: '  ',
            builder: (context, members) {
              state = members;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final path in ['/users', '/agents']) {
        expect(server.where('GET', path), isEmpty);
      }
      expect(state.candidates![GroupMemberType.user], isEmpty);
      expect(state.candidates![GroupMemberType.agent], isEmpty);
    });
  });

  group('Base components', () {
    testWidgets('BaseRoleCreate works without a provider and submits trimmed input', (tester) async {
      RoleCreateSubmission? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BaseRoleCreate(onSubmit: (value) => submitted = value)),
        ),
      );

      final submit = find.byKey(const Key('thunderid-action-role-create-submit'));
      expect(tester.widget<TextButton>(submit).onPressed, isNull, reason: 'name is required');

      await tester.enterText(find.byKey(const Key('thunderid-field-role-create-name')), '  Auditor ');
      await tester.pump();
      await tester.tap(submit);
      expect(submitted?.name, 'Auditor');
      expect(submitted?.description, isNull);
    });

    testWidgets('BaseRolePermissions groups permissions by resource server', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BaseRolePermissions(
              resourceServerNames: {'rs1': 'ThunderID API'},
              permissions: [
                RoleResourcePermissions(resourceServerId: 'rs1', permissions: ['system:user:view']),
                RoleResourcePermissions(resourceServerId: 'rs2'),
              ],
            ),
          ),
        ),
      );
      expect(find.text('ThunderID API'), findsOneWidget);
      expect(find.text('system:user:view'), findsOneWidget);
      expect(find.text('rs2'), findsNothing, reason: 'servers with no permissions are omitted');
    });

    testWidgets('BaseAgentDetails hides delete for read-only agents', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BaseAgentDetails(
              agent: const Agent(id: 'a1', name: 'Bot', ouId: 'ou1', type: 'assistant', isReadOnly: true),
              roles: const ['Reader'],
              onDelete: () {},
            ),
          ),
        ),
      );
      expect(find.text('Bot'), findsOneWidget);
      expect(find.text('Reader'), findsOneWidget);
      expect(find.text('No owner'), findsOneWidget);
      expect(find.byKey(const Key('thunderid-action-agent-details-delete')), findsNothing);
    });
  });
  group('builder (custom UI)', () {
    testWidgets('a list hands its rows and paging to the builder instead of the table', (tester) async {
      int? requested;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BaseUserList(
              users: const [
                ManagedUser(id: 'u1', ouId: 'ou1', type: 'customer', display: 'Ada'),
                ManagedUser(id: 'u2', ouId: 'ou1', type: 'customer', display: 'Grace'),
              ],
              totalResults: 45,
              offset: 20,
              onPageChange: (offset) => requested = offset,
              builder: (context, state) => Column(
                children: [
                  Text('${state.rows.length} of ${state.totalResults} from ${state.offset}'),
                  TextButton(onPressed: () => state.onPageChange?.call(40), child: const Text('Next')),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('2 of 45 from 20'), findsOneWidget);
      expect(find.byKey(const Key('thunderid-admin-user-list')), findsNothing);
      await tester.tap(find.text('Next'));
      expect(requested, 40);
    });

    testWidgets('a connected list hands the fetched rows to the builder', (tester) async {
      server.on('GET', '/groups', {
        'totalResults': 1,
        'groups': [
          {'id': 'g1', 'name': 'Admins', 'ouId': 'ou1'},
        ],
      });
      await tester.pumpWidget(
        _app(
          server,
          GroupList(
            builder: (context, state) => Column(children: [for (final group in state.rows) Text('row ${group.name}')]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('row Admins'), findsOneWidget);
    });

    testWidgets('a custom form sets values and submits them', (tester) async {
      GroupCreateSubmission? submitted;
      late NamedResourceFormState form;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BaseGroupCreate(
              onSubmit: (value) => submitted = value,
              builder: (context, state) {
                form = state;
                return Text(state.isValid ? 'valid' : 'invalid');
              },
            ),
          ),
        ),
      );

      expect(find.text('invalid'), findsOneWidget);
      form.submit();
      expect(submitted, isNull);
      form.onNameChanged('  Engineering ');
      await tester.pump();
      expect(find.text('valid'), findsOneWidget);
      form.submit();
      expect(submitted?.name, 'Engineering');
      expect(submitted?.description, isNull);
    });

    testWidgets('custom user details get no delete for read-only users and no hidden attributes', (tester) async {
      late UserDetailsState details;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BaseUserDetails(
              user: const ManagedUser(
                id: 'u1',
                ouId: 'ou1',
                type: 'customer',
                display: 'Ada',
                isReadOnly: true,
                attributes: {'username': 'ada', 'password': 'secret'},
              ),
              onDelete: () {},
              builder: (context, state) {
                details = state;
                return Text(state.displayName);
              },
            ),
          ),
        ),
      );

      expect(find.text('Ada'), findsOneWidget);
      expect(details.attributes.keys, ['username']);
      expect(details.onDelete, isNull);
    });

    testWidgets('custom permissions UI gets only granted servers with their names', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BaseRolePermissions(
              permissions: const [
                RoleResourcePermissions(resourceServerId: 'rs-1', permissions: ['read']),
                RoleResourcePermissions(resourceServerId: 'rs-2', permissions: []),
              ],
              resourceServerNames: const {'rs-1': 'Orders API'},
              builder: (context, state) => Column(
                children: [
                  for (final entry in state.permissions)
                    Text('${state.resourceServerName(entry.resourceServerId)}: ${entry.permissions.join(' ')}'),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Orders API: read'), findsOneWidget);
      expect(find.textContaining('rs-2'), findsNothing);
    });
  });

  group('search and filters', () {
    test('ManagementFilter.equality trims the value and rejects invalid input', () {
      expect(ManagementFilter.equality('username', '  ada '), 'username eq "ada"');
      expect(ManagementFilter.equality('name', 'Say "hi"'), 'name eq "Say hi"');
      expect(ManagementFilter.equality('username', '   '), isNull);
      expect(ManagementFilter.equality('user name', 'ada'), isNull);
    });

    testWidgets('UserList searches on the server by the chosen attribute', (tester) async {
      server.on('GET', '/users', {'totalResults': 0, 'users': []});
      await tester.pumpWidget(_app(server, const UserList()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('thunderid-field-user-list-search')), ' ada ');
      await tester.tap(find.byKey(const Key('thunderid-action-user-list-search')));
      await tester.pumpAndSettle();

      expect(server.where('GET', '/users').last.url.queryParameters['filter'], 'username eq "ada"');
      expect(find.text('No matches for "ada". Search matches the whole value.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('thunderid-action-user-list-search-clear')));
      await tester.pumpAndSettle();
      expect(server.where('GET', '/users').last.url.queryParameters.containsKey('filter'), isFalse);
    });

    testWidgets('AgentList searches by name', (tester) async {
      server.on('GET', '/agents', {'totalResults': 0, 'agents': []});
      await tester.pumpWidget(_app(server, const AgentList()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('thunderid-field-agent-list-search')), 'Concierge');
      await tester.tap(find.byKey(const Key('thunderid-action-agent-list-search')));
      await tester.pumpAndSettle();

      expect(server.where('GET', '/agents').last.url.queryParameters['filter'], 'name eq "Concierge"');
    });

    testWidgets('RoleAssignments lists candidates from its organization unit and drops them when it changes',
        (tester) async {
      server
        ..on('GET', '/roles/r1/assignments', {'totalResults': 0, 'assignments': []})
        ..on('GET', '/users', {
          'totalResults': 1,
          'users': [
            {'id': 'u1', 'display': 'Ada'},
          ],
        })
        ..on('GET', '/groups', {
          'totalResults': 1,
          'groups': [
            {'id': 'g1', 'name': 'Sales', 'ouId': 'ou1'},
          ],
        })
        ..on('GET', '/agents', {
          'totalResults': 1,
          'agents': [
            {'id': 'a1', 'ouId': 'ou1', 'type': 'default', 'attributes': {'name': 'Bot'}},
          ],
        });
      late RoleAssignmentsState state;
      Widget view(String ouId) => _app(
            server,
            RoleAssignments(
              roleId: 'r1',
              editable: true,
              ouId: ouId,
              builder: (context, assignments) {
                state = assignments;
                return const SizedBox.shrink();
              },
            ),
          );

      await tester.pumpWidget(view('ou1'));
      await tester.pumpAndSettle();

      for (final path in ['/users', '/groups', '/agents']) {
        expect(server.where('GET', path).last.url.queryParameters['filter'], 'ouId eq "ou1"');
      }
      expect(state.candidates![RoleAssigneeType.user], hasLength(1));
      expect(state.candidates![RoleAssigneeType.group], hasLength(1));
      expect(state.candidates![RoleAssigneeType.agent], hasLength(1));

      for (final path in ['/users', '/groups', '/agents']) {
        server.on('GET', path, {'message': 'failed'}, status: 500);
      }
      await tester.pumpWidget(view('ou2'));
      await tester.pumpAndSettle();

      for (final path in ['/users', '/groups', '/agents']) {
        expect(server.where('GET', path).last.url.queryParameters['filter'], 'ouId eq "ou2"');
      }
      expect(state.candidates![RoleAssigneeType.user], isEmpty);
      expect(state.candidates![RoleAssigneeType.group], isEmpty);
      expect(state.candidates![RoleAssigneeType.agent], isEmpty);
    });

    testWidgets('RoleAssignments lists no candidates for an organization unit that makes no filter', (tester) async {
      server.on('GET', '/roles/r1/assignments', {'totalResults': 0, 'assignments': []});
      late RoleAssignmentsState state;
      await tester.pumpWidget(
        _app(
          server,
          RoleAssignments(
            roleId: 'r1',
            editable: true,
            ouId: '  ',
            builder: (context, assignments) {
              state = assignments;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final path in ['/users', '/groups', '/agents']) {
        expect(server.where('GET', path), isEmpty);
      }
      expect(state.candidates![RoleAssigneeType.user], isEmpty);
      expect(state.candidates![RoleAssigneeType.group], isEmpty);
      expect(state.candidates![RoleAssigneeType.agent], isEmpty);
    });

    testWidgets('RoleAssignments hands the type filter to a builder and requests by type', (tester) async {
      server.on('GET', '/roles/r1/assignments', {'totalResults': 0, 'assignments': []});
      late RoleAssignmentsState state;
      await tester.pumpWidget(
        _app(
          server,
          RoleAssignments(
            roleId: 'r1',
            builder: (context, assignments) {
              state = assignments;
              return Text('type ${assignments.typeFilter?.value ?? 'all'}');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('type all'), findsOneWidget);

      state.onTypeFilterChange!(RoleAssigneeType.group);
      await tester.pumpAndSettle();

      expect(find.text('type group'), findsOneWidget);
      expect(server.where('GET', '/roles/r1/assignments').last.url.queryParameters['type'], 'group');
    });
  });
}
