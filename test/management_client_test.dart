// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

/// Records every request and answers with [respond].
class FakeFetcher {
  final List<ManagementRequest> requests = [];
  ManagementResponse Function(ManagementRequest request) respond;

  FakeFetcher([ManagementResponse Function(ManagementRequest request)? respond])
      : respond = respond ?? ((_) => const ManagementResponse(statusCode: 200, body: '{}'));

  Future<ManagementResponse> call(ManagementRequest request) async {
    requests.add(request);
    return respond(request);
  }

  ManagementRequest get last => requests.last;
}

ManagementResponse json(Object body, {int status = 200}) =>
    ManagementResponse(statusCode: status, statusText: 'OK', body: jsonEncode(body));

void main() {
  const baseUrl = 'https://idp.example.com';
  late FakeFetcher fetcher;
  late ThunderIDManagementClient client;

  setUp(() {
    fetcher = FakeFetcher();
    client = ThunderIDManagementClient(baseUrl: baseUrl, fetcher: fetcher.call);
  });

  group('roles', () {
    test('getRoles sends GET with pagination and JSON headers, and parses the page', () async {
      fetcher.respond = (_) => json({
            'totalResults': 3,
            'startIndex': 1,
            'count': 1,
            'roles': [
              {'id': 'r1', 'name': 'Admin', 'ouId': 'ou1'},
            ],
          });

      final page = await client.getRoles(limit: 10, offset: 20);

      expect(fetcher.last.method, 'GET');
      expect(fetcher.last.url.toString(), '$baseUrl/roles?limit=10&offset=20');
      expect(fetcher.last.headers['Accept'], 'application/json');
      expect(fetcher.last.headers['Content-Type'], 'application/json');
      expect(fetcher.last.body, isNull);
      expect(page.totalResults, 3);
      expect(page.items.single.name, 'Admin');
    });

    test('createRole POSTs the payload', () async {
      fetcher.respond = (_) => json({'id': 'r1', 'name': 'Dev', 'ouId': 'ou1', 'permissions': []});

      final role = await client.createRole(
        const CreateRoleRequest(
          name: 'Dev',
          ouId: 'ou1',
          permissions: [
            RoleResourcePermissions(resourceServerId: 'rs1', permissions: ['system:user:view']),
          ],
        ),
      );

      expect(fetcher.last.method, 'POST');
      expect(fetcher.last.url.toString(), '$baseUrl/roles');
      expect(jsonDecode(fetcher.last.body!), {
        'name': 'Dev',
        'ouId': 'ou1',
        'permissions': [
          {
            'resourceServerId': 'rs1',
            'permissions': ['system:user:view'],
          },
        ],
      });
      expect(role.id, 'r1');
    });

    test('getRole, updateRole and deleteRole address the single resource', () async {
      fetcher.respond = (_) => json({'id': 'r1', 'name': 'Dev', 'ouId': 'ou1'});
      await client.getRole('r1');
      expect(fetcher.last.url.toString(), '$baseUrl/roles/r1');

      await client.updateRole('r1', const UpdateRoleRequest(name: 'Dev2', ouId: 'ou1'));
      expect(fetcher.last.method, 'PUT');
      expect(fetcher.last.url.toString(), '$baseUrl/roles/r1');
      expect(jsonDecode(fetcher.last.body!), {'name': 'Dev2', 'ouId': 'ou1', 'permissions': <Object?>[]});

      fetcher.respond = (_) => const ManagementResponse(statusCode: 204);
      await client.deleteRole('r1');
      expect(fetcher.last.method, 'DELETE');
      expect(fetcher.last.url.toString(), '$baseUrl/roles/r1');
    });

    test('assignment operations target the assignments sub-resources', () async {
      fetcher.respond = (_) => json({
            'totalResults': 2,
            'assignments': [
              {'id': 'u1', 'type': 'user', 'display': 'Ada'},
              {'id': 'x', 'type': 'unknown-kind'},
            ],
          });
      final page = await client.getRoleAssignments('r1', type: RoleAssigneeType.user, limit: 5);
      expect(
        fetcher.last.url.toString(),
        '$baseUrl/roles/r1/assignments?include=display&limit=5&type=user',
      );
      expect(page.items.single.display, 'Ada', reason: 'unknown assignee types are dropped');

      fetcher.respond = (_) => const ManagementResponse(statusCode: 204);
      const assignment = RoleAssignment(id: 'g1', type: RoleAssigneeType.group);
      await client.addRoleAssignments('r1', [assignment]);
      expect(fetcher.last.method, 'POST');
      expect(fetcher.last.url.toString(), '$baseUrl/roles/r1/assignments/add');
      expect(jsonDecode(fetcher.last.body!), {
        'assignments': [
          {'id': 'g1', 'type': 'group'},
        ],
      });

      await client.removeRoleAssignments('r1', [assignment]);
      expect(fetcher.last.url.toString(), '$baseUrl/roles/r1/assignments/remove');
    });
  });

  group('groups', () {
    test('CRUD and member operations', () async {
      fetcher.respond = (_) => json({'groups': <Object?>[], 'totalResults': 0});
      await client.getGroups(limit: 20, offset: 0);
      expect(fetcher.last.url.toString(), '$baseUrl/groups?include=display&limit=20&offset=0');

      fetcher.respond = (_) => json({'id': 'g1', 'name': 'Team', 'ouId': 'ou1'});
      await client.getGroup('g1');
      expect(fetcher.last.url.toString(), '$baseUrl/groups/g1?include=display');

      await client.createGroup(const CreateGroupRequest(name: 'Team', ouId: 'ou1', description: 'd'));
      expect(fetcher.last.method, 'POST');
      expect(jsonDecode(fetcher.last.body!), {'name': 'Team', 'ouId': 'ou1', 'description': 'd'});

      await client.updateGroup('g1', const UpdateGroupRequest(name: 'Team 2', ouId: 'ou1'));
      expect(fetcher.last.method, 'PUT');
      expect(fetcher.last.url.toString(), '$baseUrl/groups/g1');

      fetcher.respond = (_) => json({
            'members': [
              {'id': 'u1', 'type': 'user', 'display': 'Ada'},
              {'id': 'a1', 'type': 'agent'},
            ],
            'totalResults': 2,
          });
      final members = await client.getGroupMembers('g1', limit: 100);
      expect(fetcher.last.url.toString(), '$baseUrl/groups/g1/members?include=display&limit=100');
      expect(members.items.map((m) => m.type), [GroupMemberType.user, GroupMemberType.agent]);

      fetcher.respond = (_) => json({'id': 'g1', 'name': 'Team', 'ouId': 'ou1'});
      const member = GroupMember(id: 'u2', type: GroupMemberType.user, display: 'ignored');
      final updated = await client.addGroupMembers('g1', [member]);
      expect(fetcher.last.url.toString(), '$baseUrl/groups/g1/members/add');
      expect(jsonDecode(fetcher.last.body!), {
        'members': [
          {'id': 'u2', 'type': 'user'},
        ],
      });
      expect(updated?.id, 'g1');

      await client.removeGroupMembers('g1', [member]);
      expect(fetcher.last.url.toString(), '$baseUrl/groups/g1/members/remove');

      fetcher.respond = (_) => const ManagementResponse(statusCode: 204);
      await client.deleteGroup('g1');
      expect(fetcher.last.method, 'DELETE');
      expect(fetcher.last.url.toString(), '$baseUrl/groups/g1');
    });
  });

  group('users and agents', () {
    test('user operations, user groups and user types', () async {
      fetcher.respond = (_) => json({'users': <Object?>[], 'totalResults': 0});
      await client.getUsers(filter: 'username eq "ada"', limit: 1);
      expect(fetcher.last.url.queryParameters, {
        'filter': 'username eq "ada"',
        'include': 'display',
        'limit': '1',
      });

      fetcher.respond = (_) => json({'id': 'u1', 'ouId': 'ou1', 'type': 'customer'});
      await client.createUser(
        const CreateManagedUserRequest(ouId: 'ou1', type: 'customer', attributes: {'username': 'ada'}),
      );
      expect(fetcher.last.method, 'POST');
      expect(fetcher.last.url.toString(), '$baseUrl/users');
      expect(jsonDecode(fetcher.last.body!), {
        'ouId': 'ou1',
        'type': 'customer',
        'attributes': {'username': 'ada'},
      });

      await client.updateUser('u1', const UpdateManagedUserRequest(attributes: {'email': 'a@b.c'}));
      expect(fetcher.last.method, 'PUT');
      expect(fetcher.last.url.toString(), '$baseUrl/users/u1');

      fetcher.respond = (_) => json({
            'groups': [
              {'id': 'g1', 'name': 'Team', 'ouId': 'ou1'},
            ],
            'totalResults': 1,
          });
      final groups = await client.getUserGroups('u1', limit: 100);
      expect(fetcher.last.url.toString(), '$baseUrl/users/u1/groups?limit=100');
      expect(groups.items.single.name, 'Team');

      fetcher.respond = (_) => json({
            'types': [
              {'id': 't1', 'handle': 'customer', 'displayName': 'Customer'},
            ],
            'totalResults': 1,
          });
      final types = await client.getUserTypes(limit: 100);
      expect(fetcher.last.url.toString(), '$baseUrl/user-types?limit=100');
      expect(types.items.single.handle, 'customer');

      fetcher.respond = (_) => const ManagementResponse(statusCode: 204);
      await client.deleteUser('u1');
      expect(fetcher.last.method, 'DELETE');
    });

    test('agent groups, roles and types', () async {
      fetcher.respond = (_) => json({
            'groups': [
              {'id': 'g1', 'name': 'Bots', 'ouId': 'ou1'},
            ],
            'totalResults': 1,
          });
      await client.getAgentGroups('a1');
      expect(fetcher.last.url.toString(), '$baseUrl/agents/a1/groups');

      fetcher.respond = (_) => json({
            'roles': ['Reader', 7, 'Writer'],
            'totalResults': 2,
          });
      final roles = await client.getAgentRoles('a1', limit: 10);
      expect(fetcher.last.url.toString(), '$baseUrl/agents/a1/roles?limit=10');
      expect(roles.items, ['Reader', 'Writer']);

      fetcher.respond = (_) => json({
            'types': [
              {'id': 't1', 'handle': 'assistant', 'displayName': 'Assistant', 'ouId': 'ou1'},
            ],
            'totalResults': 1,
          });
      final types = await client.getAgentTypes();
      expect(fetcher.last.url.toString(), '$baseUrl/agent-types');
      expect(types.items.single.displayName, 'Assistant');

      fetcher.respond = (_) => json({'id': 'a1', 'name': 'Bot', 'ouId': 'ou1', 'type': 'assistant'});
      await client.createAgent(const CreateAgentRequest(name: 'Bot', ouId: 'ou1', type: 'assistant', owner: 'u1'));
      expect(fetcher.last.url.toString(), '$baseUrl/agents');
      expect(jsonDecode(fetcher.last.body!), {'name': 'Bot', 'ouId': 'ou1', 'type': 'assistant', 'owner': 'u1'});

      await client.getAgent('a1');
      expect(fetcher.last.url.toString(), '$baseUrl/agents/a1?include=display');
    });

    test('identifiers are path-encoded', () async {
      fetcher.respond = (_) => json({'id': 'a b/c', 'ouId': 'ou1', 'type': 't'});
      await client.getUser('a b/c');
      expect(fetcher.last.url.toString(), '$baseUrl/users/a%20b%2Fc?include=display');
    });
  });

  group('endpoint resolution', () {
    test('explicit url beats the endpoints override, which beats baseUrl', () async {
      final overridden = ThunderIDManagementClient(
        baseUrl: '$baseUrl/',
        endpoints: const {
          ManagementEndpointKeys.groups: 'https://rs.example.com/api/groups/',
          ManagementEndpointKeys.agentTypes: 'https://rs.example.com/api/agent-types',
        },
        fetcher: fetcher.call,
      );
      fetcher.respond = (_) => json({'groups': <Object?>[], 'types': <Object?>[]});

      await overridden.getGroupMembers('g1');
      expect(fetcher.last.url.toString(), 'https://rs.example.com/api/groups/g1/members?include=display');

      await overridden.getAgentTypes();
      expect(fetcher.last.url.toString(), 'https://rs.example.com/api/agent-types');

      await overridden.getRoles();
      expect(fetcher.last.url.toString(), '$baseUrl/roles', reason: 'no override: baseUrl + collection');

      await overridden.getGroups(url: 'https://other.example.com/g');
      expect(fetcher.last.url.toString(), 'https://other.example.com/g?include=display');
    });

    test('a per-call fetcher takes precedence over the client fetcher', () async {
      final perCall = FakeFetcher((_) => json({'roles': <Object?>[]}));
      await client.getRoles(fetcher: perCall.call);
      expect(perCall.requests, hasLength(1));
      expect(fetcher.requests, isEmpty);
    });

    test('rejects a non-HTTPS URL and an empty identifier before any request', () async {
      final insecure = ThunderIDManagementClient(baseUrl: 'http://idp.example.com', fetcher: fetcher.call);
      await expectLater(
        insecure.getRoles(),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.invalidConfiguration)),
      );
      await expectLater(
        client.getRole('  '),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.invalidInput)),
      );
      expect(fetcher.requests, isEmpty);

      final loopback = ThunderIDManagementClient(baseUrl: 'http://localhost:8090', fetcher: fetcher.call);
      fetcher.respond = (_) => json({'roles': <Object?>[]});
      await loopback.getRoles();
      expect(fetcher.last.url.toString(), 'http://localhost:8090/roles');
    });
  });

  group('errors', () {
    test('403 and 404 surface as distinct codes, without the server text in the message', () async {
      fetcher.respond = (_) => const ManagementResponse(
            statusCode: 403,
            statusText: 'Forbidden',
            body: '{"description":"user ada@example.com lacks system:role"}',
          );
      final forbidden = await client.getRoles().then<Object?>((_) => null, onError: (Object e) => e);
      expect(forbidden, isA<IAMApiException>());
      forbidden as IAMApiException;
      expect(forbidden.code, ThunderIDErrorCode.forbidden);
      expect(forbidden.statusCode, 403);
      expect(forbidden.statusText, 'Forbidden');
      expect(forbidden.operation, 'getRoles');
      expect(forbidden.message, isNot(contains('ada@example.com')));
      expect(forbidden.responseBody, contains('ada@example.com'));

      fetcher.respond = (_) => const ManagementResponse(statusCode: 404, statusText: 'Not Found');
      final notFound = await client.getRole('missing').then<Object?>((_) => null, onError: (Object e) => e);
      expect(notFound, isA<IAMApiException>());
      notFound as IAMApiException;
      expect(notFound.code, ThunderIDErrorCode.notFound);
      expect(notFound.statusCode, 404);
    });

    test('other statuses and transport failures', () async {
      fetcher.respond = (_) => const ManagementResponse(statusCode: 500);
      await expectLater(
        client.getRoles(),
        throwsA(isA<IAMApiException>().having((e) => e.code, 'code', ThunderIDErrorCode.serverError)),
      );

      fetcher.respond = (_) => throw const SocketException('down');
      await expectLater(
        client.getRoles(),
        throwsA(
          isA<IAMApiException>()
              .having((e) => e.code, 'code', ThunderIDErrorCode.networkError)
              .having((e) => e.statusCode, 'statusCode', 0),
        ),
      );
    });

    test('error codes round-trip through their string values', () {
      expect(ThunderIDErrorCode.forbidden.value, 'FORBIDDEN');
      expect(ThunderIDErrorCode.notFound.value, 'NOT_FOUND');
      expect(ThunderIDErrorCode.fromString('FORBIDDEN'), ThunderIDErrorCode.forbidden);
      expect(ThunderIDErrorCode.fromString('NOT_FOUND'), ThunderIDErrorCode.notFound);
    });
  });

  group('ThunderIDClient.management', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.thunderid/sdk'),
        (call) async => call.method == 'initialize' ? true : null,
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('dev.thunderid/sdk'), null);
    });

    test('requires initialization, then uses config endpoints and http.fetcher', () async {
      final sdk = ThunderIDClient();
      expect(
        () => sdk.management,
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.sdkNotInitialized)),
      );

      fetcher.respond = (_) => json({'users': <Object?>[]});
      await sdk.initialize(
        ThunderIDConfig(
          baseUrl: baseUrl,
          clientId: 'c',
          endpoints: const {ManagementEndpointKeys.users: 'https://rs.example.com/users'},
          http: ThunderIDHttpConfig(fetcher: fetcher.call),
        ),
      );
      await sdk.management.getUsers();
      expect(fetcher.last.url.toString(), 'https://rs.example.com/users?include=display');
    });
  });
}
