// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

const baseUrl = 'https://localhost:8090';

ManagementResponse json(Object? body) => ManagementResponse(statusCode: 200, statusText: 'OK', body: jsonEncode(body));

/// Answers like the server: the flow configuration, the flow listing, flow execution, and
/// [resource] for every other request. Every request is recorded.
class FakeServer {
  final Map<String, Object?> config;
  final Object? execution;
  final List<Map<String, Object?>> flows;
  final Object? resource;
  final List<ManagementRequest> requests = [];

  FakeServer({this.config = const {}, this.execution, this.flows = const [], this.resource = const {}});

  Future<ManagementResponse> call(ManagementRequest request) async {
    requests.add(request);
    final url = request.url.toString();
    if (url == '$baseUrl/server-config/flow') return json({'merged': config});
    if (url.startsWith('$baseUrl/flows?flowType=ADMINISTRATION')) return json({'flows': flows});
    if (url == '$baseUrl/flow/execute') {
      return json(
        execution ??
            {
              'data': {'additionalData': <String, String>{}},
              'flowStatus': 'COMPLETE',
            },
      );
    }
    return json(resource);
  }

  List<String> get calls => [for (final r in requests) '${r.method} ${r.url}'];

  List<Object?> get executions => [
        for (final r in requests)
          if (r.url.toString() == '$baseUrl/flow/execute') jsonDecode(r.body!),
      ];
}

Map<String, Object?> flow(String handle, String id) => {'flowType': 'ADMINISTRATION', 'handle': handle, 'id': id};

Map<String, Object?> configured(String key, String handle) => {
      key: {'defaultHandle': handle},
    };

typedef Case = (Future<Object?> Function(ThunderIDManagementClient), String, String, Object?);

void main() {
  ThunderIDManagementClient clientFor(FakeServer server, {Map<String, String> endpoints = const {}}) =>
      ThunderIDManagementClient(baseUrl: baseUrl, endpoints: endpoints, fetcher: server.call);

  void runCases(Map<String, Case> cases) {
    cases.forEach((name, entry) {
      final (run, method, path, body) = entry;
      test('$name sends $method $path', () async {
        final server = FakeServer();

        await run(clientFor(server));

        expect(server.calls, ['$method $baseUrl$path']);
        final sent = server.requests.single.body;
        expect(sent == null ? null : jsonDecode(sent), body);
      });
    });
  }

  const ouPayload = OrganizationUnitRequest(handle: 'eng', name: 'Engineering', parent: 'ou-root');
  const ouByPath = UpdateOrganizationUnitByPathRequest(handle: 'eng', name: 'Eng', description: 'R&D');

  group('agent types', () {
    runCases({
      'createAgentType': (
        (c) => c.createAgentType(
              const CreateAgentTypeRequest(
                handle: 'default',
                displayName: 'Default',
                ouId: 'ou-1',
                schema: {},
                systemAttributes: EntityTypeSystemAttributes(display: 'name'),
              ),
            ),
        'POST',
        '/agent-types',
        {
          'displayName': 'Default',
          'handle': 'default',
          'ouId': 'ou-1',
          'schema': <String, Object?>{},
          'systemAttributes': {'display': 'name'},
        },
      ),
      'deleteAgentType': ((c) => c.deleteAgentType('at-1'), 'DELETE', '/agent-types/at-1', null),
    });
  });

  group('organization units', () {
    runCases({
      'getOrganizationUnits': (
        (c) => c.getOrganizationUnits(filter: 'handle eq "eng"', limit: 5, offset: 10),
        'GET',
        '/organization-units?filter=handle+eq+%22eng%22&limit=5&offset=10',
        null,
      ),
      'getOrganizationUnit': ((c) => c.getOrganizationUnit('ou-1'), 'GET', '/organization-units/ou-1', null),
      'getOrganizationUnitByPath': (
        (c) => c.getOrganizationUnitByPath('eng/platform'),
        'GET',
        '/organization-units/tree/eng/platform',
        null,
      ),
      'createOrganizationUnit': (
        (c) => c.createOrganizationUnit(ouPayload),
        'POST',
        '/organization-units',
        {'handle': 'eng', 'name': 'Engineering', 'parent': 'ou-root'},
      ),
      'createOrganizationUnit (root)': (
        (c) => c.createOrganizationUnit(const OrganizationUnitRequest(handle: 'root', name: 'Root')),
        'POST',
        '/organization-units',
        {'handle': 'root', 'name': 'Root', 'parent': null},
      ),
      'updateOrganizationUnit': (
        (c) => c.updateOrganizationUnit('ou-1', ouPayload),
        'PUT',
        '/organization-units/ou-1',
        {'handle': 'eng', 'name': 'Engineering', 'parent': 'ou-root'},
      ),
      'updateOrganizationUnitByPath': (
        (c) => c.updateOrganizationUnitByPath('eng', ouByPath),
        'PUT',
        '/organization-units/tree/eng',
        {'handle': 'eng', 'name': 'Eng', 'description': 'R&D'},
      ),
      'deleteOrganizationUnit': ((c) => c.deleteOrganizationUnit('ou-1'), 'DELETE', '/organization-units/ou-1', null),
      'deleteOrganizationUnitByPath': (
        (c) => c.deleteOrganizationUnitByPath('eng/platform'),
        'DELETE',
        '/organization-units/tree/eng/platform',
        null,
      ),
      'getOrganizationUnitChildren by id': (
        (c) => c.getOrganizationUnitChildren(ouId: 'ou-1', limit: 2),
        'GET',
        '/organization-units/ou-1/ous?limit=2',
        null,
      ),
      'getOrganizationUnitChildren by path': (
        (c) => c.getOrganizationUnitChildren(path: 'eng'),
        'GET',
        '/organization-units/tree/eng/ous',
        null,
      ),
      'getOrganizationUnitUsers by id': (
        (c) => c.getOrganizationUnitUsers(ouId: 'ou-1', limit: 1, offset: 0),
        'GET',
        '/organization-units/ou-1/users?include=display&limit=1&offset=0',
        null,
      ),
      'getOrganizationUnitUsers by path': (
        (c) => c.getOrganizationUnitUsers(path: 'eng/platform'),
        'GET',
        '/organization-units/tree/eng/platform/users?include=display',
        null,
      ),
      'getOrganizationUnitGroups by id': (
        (c) => c.getOrganizationUnitGroups(ouId: 'ou-1'),
        'GET',
        '/organization-units/ou-1/groups',
        null,
      ),
      'getOrganizationUnitGroups by path': (
        (c) => c.getOrganizationUnitGroups(path: 'eng', offset: 3),
        'GET',
        '/organization-units/tree/eng/groups?offset=3',
        null,
      ),
      'getOrganizationUnitRoles by id': (
        (c) => c.getOrganizationUnitRoles(ouId: 'ou-1'),
        'GET',
        '/organization-units/ou-1/roles',
        null,
      ),
      'getOrganizationUnitRoles by path': (
        (c) => c.getOrganizationUnitRoles(path: 'eng'),
        'GET',
        '/organization-units/tree/eng/roles',
        null,
      ),
    });

    test('encodes each handle of a path on its own and keeps the slashes', () async {
      final server = FakeServer();

      await clientFor(server).getOrganizationUnitByPath('/r&d team/a?b#c/50%/');

      expect(server.calls, ['GET $baseUrl/organization-units/tree/r&d%20team/a%3Fb%23c/50%25']);
      expect(server.requests.single.url.pathSegments, ['organization-units', 'tree', 'r&d team', 'a?b#c', '50%']);
    });

    test('refuses an empty path or an empty handle before sending anything', () async {
      final server = FakeServer();
      final client = clientFor(server);

      for (final path in ['', '/', 'a//b', ' ']) {
        await expectLater(
          client.getOrganizationUnitByPath(path),
          throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.invalidInput)),
        );
      }
      expect(server.requests, isEmpty);
    });

    test('needs exactly one of ouId and path for the member listings', () async {
      final server = FakeServer();
      final client = clientFor(server);

      await expectLater(client.getOrganizationUnitChildren(), throwsA(isA<IAMException>()));
      await expectLater(client.getOrganizationUnitUsers(ouId: 'ou-1', path: 'eng'), throwsA(isA<IAMException>()));
      expect(server.requests, isEmpty);
    });

    test('the endpoint override applies to id and path addressing', () async {
      final server = FakeServer();
      final client = clientFor(
        server,
        endpoints: const {ManagementEndpointKeys.organizationUnits: 'https://ou.example.com/v2/ous'},
      );

      await client.getOrganizationUnit('ou-1');
      await client.getOrganizationUnitRoles(path: 'eng/platform');
      await client.getOrganizationUnits(url: 'https://other.example.com/units');

      expect(server.calls, [
        'GET https://ou.example.com/v2/ous/ou-1',
        'GET https://ou.example.com/v2/ous/tree/eng/platform/roles',
        'GET https://other.example.com/units',
      ]);
    });

    test('parses a unit, a page of units, and member pages', () async {
      final client = ThunderIDManagementClient(
        baseUrl: baseUrl,
        fetcher: (request) async => switch (request.url.path) {
          '/organization-units/ou-1' => json({
              'id': 'ou-1',
              'handle': 'eng',
              'name': 'Engineering',
              'parent': 'ou-root',
              'isRegistrationFlowEnabled': true,
              'createdAt': '2026-01-01T00:00:00Z',
            }),
          '/organization-units' => json({
              'totalResults': 3,
              'organizationUnits': [
                {'id': 'ou-1', 'handle': 'eng', 'name': 'Engineering', 'isReadOnly': true},
              ],
            }),
          _ => json({
              'totalResults': 1,
              'users': [
                {'id': 'u-1', 'type': 'customer', 'display': 'Ada', 'isOwned': false},
              ],
            }),
        },
      );

      final unit = await client.getOrganizationUnit('ou-1');
      expect(unit.handle, 'eng');
      expect(unit.parent, 'ou-root');
      expect(unit.isRegistrationFlowEnabled, isTrue);

      final page = await client.getOrganizationUnits();
      expect(page.totalResults, 3);
      expect(page.items.single.isReadOnly, isTrue);

      final users = await client.getOrganizationUnitUsers(ouId: 'ou-1');
      expect(users.items.single.display, 'Ada');
      expect(users.items.single.isOwned, isFalse);
    });
  });

  group('users and applications', () {
    runCases({
      'getUsersByPath': (
        (c) => c.getUsersByPath('eng/platform', limit: 10),
        'GET',
        '/users/tree/eng/platform?include=display&limit=10',
        null,
      ),
      'createUserByPath': (
        (c) => c.createUserByPath(
              'eng',
              const CreateUserByPathRequest(type: 'customer', attributes: {'username': 'ada'}),
            ),
        'POST',
        '/users/tree/eng',
        {
          'type': 'customer',
          'attributes': {'username': 'ada'},
        },
      ),
      'getUserSharingPolicies': (
        (c) => c.getUserSharingPolicies('u-1', limit: 5),
        'GET',
        '/users/u-1/sharing-policies?limit=5',
        null,
      ),
      'createUserSharingPolicy': (
        (c) => c.createUserSharingPolicy(
              'u-1',
              const CreateSharingPolicyRequest(childUnits: {'mode': 'all'}),
            ),
        'POST',
        '/users/u-1/sharing-policies',
        {
          'childUnits': {'mode': 'all'},
        },
      ),
      'getUserSharingPolicy': (
        (c) => c.getUserSharingPolicy('u-1', 'p-1'),
        'GET',
        '/users/u-1/sharing-policies/p-1',
        null,
      ),
      'updateUserSharingPolicy': (
        (c) => c.updateUserSharingPolicy('u-1', 'p-1', const UpdateSharingPolicyRequest(version: 2)),
        'PUT',
        '/users/u-1/sharing-policies/p-1',
        {'version': 2},
      ),
      'deleteUserSharingPolicy': (
        (c) => c.deleteUserSharingPolicy('u-1', 'p-1'),
        'DELETE',
        '/users/u-1/sharing-policies/p-1',
        null,
      ),
      'getUserOverlayRules': (
        (c) => c.getUserOverlayRules('u-1', ouId: 'ou-2'),
        'GET',
        '/users/u-1/overlay-rules?ouId=ou-2',
        null,
      ),
      'getApplicationSharingPolicies': (
        (c) => c.getApplicationSharingPolicies('app-1'),
        'GET',
        '/applications/app-1/sharing-policies',
        null,
      ),
      'createApplicationSharingPolicy': (
        (c) => c.createApplicationSharingPolicy(
              'app-1',
              const CreateSharingPolicyRequest(initiatingOuId: 'ou-1', version: 1),
            ),
        'POST',
        '/applications/app-1/sharing-policies',
        {'initiatingOuId': 'ou-1', 'version': 1},
      ),
      'getApplicationSharingPolicy': (
        (c) => c.getApplicationSharingPolicy('app-1', 'p-1'),
        'GET',
        '/applications/app-1/sharing-policies/p-1',
        null,
      ),
      'updateApplicationSharingPolicy': (
        (c) => c.updateApplicationSharingPolicy(
              'app-1',
              'p-1',
              const UpdateSharingPolicyRequest(version: 3, allUnits: {'excludedOuIds': <String>[]}),
            ),
        'PUT',
        '/applications/app-1/sharing-policies/p-1',
        {
          'version': 3,
          'allUnits': {'excludedOuIds': <Object?>[]},
        },
      ),
      'deleteApplicationSharingPolicy': (
        (c) => c.deleteApplicationSharingPolicy('app-1', 'p-1'),
        'DELETE',
        '/applications/app-1/sharing-policies/p-1',
        null,
      ),
      'getApplicationOverlayRules': (
        (c) => c.getApplicationOverlayRules('app-1'),
        'GET',
        '/applications/app-1/overlay-rules',
        null,
      ),
    });

    test('sharing and path operations follow the users and applications overrides', () async {
      final server = FakeServer();
      final client = clientFor(
        server,
        endpoints: const {
          ManagementEndpointKeys.users: 'https://users.example.com/users',
          ManagementEndpointKeys.applications: 'https://apps.example.com/apps',
        },
      );

      await client.getUsersByPath('eng');
      await client.getApplicationOverlayRules('app-1');

      expect(server.calls, [
        'GET https://users.example.com/users/tree/eng?include=display',
        'GET https://apps.example.com/apps/app-1/overlay-rules',
      ]);
    });

    test('parses a sharing policy and an overlay', () async {
      final policy = SharingPolicy.fromJson({
        'id': 'p-1',
        'stage': 'share',
        'version': 4,
        'childUnits': {'mode': 'selected', 'units': <Object?>[]},
      });
      expect(policy.version, 4);
      expect(policy.childUnits?['mode'], 'selected');

      final overlay = ResolvedOverlay.fromJson({
        'ouId': 'ou-2',
        'visible': true,
        'policyIds': ['p-1'],
        'rules': {
          'email': {
            'editable': false,
            'value': ['a@example.com'],
          },
        },
      });
      expect(overlay.visible, isTrue);
      expect(overlay.rules['email']?.editable, isFalse);
      expect(overlay.rules['email']?.value, ['a@example.com']);
    });
  });

  group('resource servers', () {
    runCases({
      'getResourceServers': (
        (c) => c.getResourceServers(limit: 10, offset: 0),
        'GET',
        '/resource-servers?limit=10&offset=0',
        null,
      ),
      'getResourceServer': ((c) => c.getResourceServer('rs-1'), 'GET', '/resource-servers/rs-1', null),
      'createResourceServer': (
        (c) => c.createResourceServer(
              const CreateResourceServerRequest(name: 'API', identifier: 'https://api', ouId: 'ou-1', type: 'API'),
            ),
        'POST',
        '/resource-servers',
        {'name': 'API', 'identifier': 'https://api', 'ouId': 'ou-1', 'type': 'API'},
      ),
      'updateResourceServer': (
        (c) => c.updateResourceServer(
              'rs-1',
              const UpdateResourceServerRequest(
                name: 'API',
                ouId: 'ou-1',
                authorizationEngine: AuthorizationEngineConfig(type: 'authzen_pdp', pdpConnectionId: 'c-1'),
              ),
            ),
        'PUT',
        '/resource-servers/rs-1',
        {
          'name': 'API',
          'ouId': 'ou-1',
          'authorizationEngine': {
            'type': 'authzen_pdp',
            'properties': {'pdpConnectionId': 'c-1'},
          },
        },
      ),
      'deleteResourceServer': ((c) => c.deleteResourceServer('rs-1'), 'DELETE', '/resource-servers/rs-1', null),
      'getResources': (
        (c) => c.getResources('rs-1', parentId: 'r-0', limit: 2),
        'GET',
        '/resource-servers/rs-1/resources?parentId=r-0&limit=2',
        null,
      ),
      'getResource': ((c) => c.getResource('rs-1', 'r-1'), 'GET', '/resource-servers/rs-1/resources/r-1', null),
      'createResource': (
        (c) => c.createResource('rs-1', const CreateResourceRequest(name: 'Orders', handle: 'orders')),
        'POST',
        '/resource-servers/rs-1/resources',
        {'name': 'Orders', 'handle': 'orders'},
      ),
      'updateResource': (
        (c) => c.updateResource('rs-1', 'r-1', const UpdateResourceRequest(description: 'All orders')),
        'PUT',
        '/resource-servers/rs-1/resources/r-1',
        {'description': 'All orders'},
      ),
      'deleteResource': (
        (c) => c.deleteResource('rs-1', 'r-1'),
        'DELETE',
        '/resource-servers/rs-1/resources/r-1',
        null,
      ),
      'getActions on the server': (
        (c) => c.getActions('rs-1', kind: 'tool'),
        'GET',
        '/resource-servers/rs-1/actions?kind=tool',
        null,
      ),
      'getActions on a resource': (
        (c) => c.getActions('rs-1', resourceId: 'r-1'),
        'GET',
        '/resource-servers/rs-1/resources/r-1/actions',
        null,
      ),
      'getAction': (
        (c) => c.getAction('rs-1', 'a-1', resourceId: 'r-1'),
        'GET',
        '/resource-servers/rs-1/resources/r-1/actions/a-1',
        null,
      ),
      'createAction': (
        (c) => c.createAction('rs-1', const CreateActionRequest(name: 'Read', handle: 'read', kind: 'tool')),
        'POST',
        '/resource-servers/rs-1/actions',
        {'name': 'Read', 'handle': 'read', 'kind': 'tool'},
      ),
      'updateAction': (
        (c) => c.updateAction('rs-1', 'a-1', const UpdateActionRequest(name: 'Read all'), resourceId: 'r-1'),
        'PUT',
        '/resource-servers/rs-1/resources/r-1/actions/a-1',
        {'name': 'Read all'},
      ),
      'deleteAction on the server': (
        (c) => c.deleteAction('rs-1', 'a-1'),
        'DELETE',
        '/resource-servers/rs-1/actions/a-1',
        null,
      ),
      'deleteAction on a resource': (
        (c) => c.deleteAction('rs-1', 'a-1', resourceId: 'r-1'),
        'DELETE',
        '/resource-servers/rs-1/resources/r-1/actions/a-1',
        null,
      ),
    });

    FakeServer actionDeletion() => FakeServer(
          config: configured('actionDeletionFlow', 'delete-action'),
          flows: [flow('delete-action', 'flow-9')],
        );

    test('deleteAction deletes directly by default, without reading the flow configuration', () async {
      final server = actionDeletion();

      await clientFor(server).deleteAction('rs-1', 'a-1');

      expect(server.calls, ['DELETE $baseUrl/resource-servers/rs-1/actions/a-1']);
    });

    test('deleteAction runs the action deletion flow in flow mode, with the resource when given', () async {
      final server = actionDeletion();
      final client = clientFor(server);

      await client.deleteAction('rs-1', 'a-1', administrationMode: AdministrationMode.flow);
      await client.deleteAction('rs-1', 'a-2', resourceId: 'r-1', administrationMode: AdministrationMode.flow);

      expect(server.calls.where((call) => call.startsWith('DELETE')), isEmpty);
      expect(server.executions, [
        {
          'flowId': 'flow-9',
          'inputs': {'targetActionId': 'a-1', 'targetResourceServerId': 'rs-1'},
        },
        {
          'flowId': 'flow-9',
          'inputs': {'targetActionId': 'a-2', 'targetResourceServerId': 'rs-1', 'targetResourceId': 'r-1'},
        },
      ]);
    });

    test('deleteAction deletes directly in flow mode when no flow is configured', () async {
      final server = FakeServer();

      await clientFor(server).deleteAction('rs-1', 'a-1', resourceId: 'r-1', administrationMode: AdministrationMode.flow);

      expect(server.executions, isEmpty);
      expect(server.calls, [
        'GET $baseUrl/server-config/flow',
        'DELETE $baseUrl/resource-servers/rs-1/resources/r-1/actions/a-1',
      ]);
    });

    test('parses a resource server with its authorization engine', () {
      final server = ResourceServer.fromJson({
        'id': 'rs-1',
        'name': 'API',
        'identifier': 'https://api',
        'type': 'MCP',
        'ouId': 'ou-1',
        'delimiter': ':',
        'authorizationEngine': {
          'type': 'authzen_pdp',
          'properties': {'pdpConnectionId': 'c-1'},
        },
      });
      expect(server.type, ResourceServerTypes.mcp);
      expect(server.authorizationEngine?.pdpConnectionId, 'c-1');
    });
  });

  group('account lifecycle', () {
    final operations = <String, (Future<AccountLifecycleResult> Function(ThunderIDManagementClient, String?), String)>{
      'suspendUser': ((c, note) => c.suspendUser('id-1', operatorNote: note), 'userSuspendFlow'),
      'unsuspendUser': ((c, note) => c.unsuspendUser('id-1', operatorNote: note), 'userUnsuspendFlow'),
      'unlockUser': ((c, note) => c.unlockUser('id-1', operatorNote: note), 'userUnlockFlow'),
      'suspendAgent': ((c, note) => c.suspendAgent('id-1', operatorNote: note), 'agentSuspendFlow'),
      'unsuspendAgent': ((c, note) => c.unsuspendAgent('id-1', operatorNote: note), 'agentUnsuspendFlow'),
      'unlockAgent': ((c, note) => c.unlockAgent('id-1', operatorNote: note), 'agentUnlockFlow'),
      'suspendApplication': ((c, note) => c.suspendApplication('id-1', operatorNote: note), 'applicationSuspendFlow'),
      'unsuspendApplication': (
        (c, note) => c.unsuspendApplication('id-1', operatorNote: note),
        'applicationUnsuspendFlow',
      ),
    };

    operations.forEach((name, entry) {
      final (run, configKey) = entry;

      test('$name runs $configKey with the subject and the operator note', () async {
        final server = FakeServer(
          config: configured(configKey, 'lifecycle'),
          flows: [flow('lifecycle', 'flow-7')],
          execution: {
            'flowStatus': 'COMPLETE',
            'data': {
              'additionalData': {'emailSent': 'true'},
            },
          },
        );

        final result = await run(clientFor(server), 'Policy breach');

        expect(result.emailSent, isTrue);
        expect(server.executions, [
          {
            'flowId': 'flow-7',
            'inputs': {'subject': 'id-1', 'operatorNote': 'Policy breach'},
          },
        ]);
        expect(server.calls.where((call) => !call.contains('/server-config/') && !call.contains('/flow')), isEmpty);
      });

      test('$name fails with NotConfiguredError when no flow is configured, and changes nothing', () async {
        final server = FakeServer();

        final error = await run(clientFor(server), null).then<Object?>((_) => null, onError: (Object e) => e);

        expect(error, isA<AdministrationFlowError>());
        expect((error! as AdministrationFlowError).flowCode, '$name-NotConfiguredError-001');
        expect(server.calls, ['GET $baseUrl/server-config/flow']);
      });
    });

    test('reads emailSent as false, or as absent when the flow has no email step', () async {
      Future<AccountLifecycleResult> withData(Map<String, String> data) => clientFor(
            FakeServer(
              config: configured('userUnlockFlow', 'unlock'),
              flows: [flow('unlock', 'flow-1')],
              execution: {
                'flowStatus': 'COMPLETE',
                'data': {'additionalData': data},
              },
            ),
          ).unlockUser('u-1');

      expect((await withData({'emailSent': 'false'})).emailSent, isFalse);
      expect((await withData({})).emailSent, isNull);
    });

    test('leaves out an empty operator note', () async {
      final server = FakeServer(config: configured('agentSuspendFlow', 's'), flows: [flow('s', 'flow-2')]);

      await clientFor(server).suspendAgent('ag-1', operatorNote: '');

      expect(server.executions, [
        {
          'flowId': 'flow-2',
          'inputs': {'subject': 'ag-1'},
        },
      ]);
    });

    final kinds = <(AccountLifecycleSubjectKind, AccountLifecycleAction, String)>[
      (AccountLifecycleSubjectKind.user, AccountLifecycleAction.suspend, 'userSuspendFlow'),
      (AccountLifecycleSubjectKind.user, AccountLifecycleAction.unsuspend, 'userUnsuspendFlow'),
      (AccountLifecycleSubjectKind.user, AccountLifecycleAction.unlock, 'userUnlockFlow'),
      (AccountLifecycleSubjectKind.agent, AccountLifecycleAction.suspend, 'agentSuspendFlow'),
      (AccountLifecycleSubjectKind.agent, AccountLifecycleAction.unsuspend, 'agentUnsuspendFlow'),
      (AccountLifecycleSubjectKind.agent, AccountLifecycleAction.unlock, 'agentUnlockFlow'),
      (AccountLifecycleSubjectKind.application, AccountLifecycleAction.suspend, 'applicationSuspendFlow'),
      (AccountLifecycleSubjectKind.application, AccountLifecycleAction.unsuspend, 'applicationUnsuspendFlow'),
    ];

    for (final (kind, action, configKey) in kinds) {
      test('runAccountLifecycleAction runs the ${kind.name} ${action.name} flow configured under $configKey', () async {
        final server = FakeServer(config: configured(configKey, 'lifecycle'), flows: [flow('lifecycle', 'flow-9')]);

        await clientFor(server).runAccountLifecycleAction(kind, action, 's-1');

        expect(kind.flowConfigKeys[action], configKey);
        expect(server.executions, [
          {
            'flowId': 'flow-9',
            'inputs': {'subject': 's-1'},
          },
        ]);
      });
    }

    test('runAccountLifecycleAction passes the operator note and reports whether the email was sent', () async {
      final server = FakeServer(
        config: configured('userSuspendFlow', 'suspend'),
        flows: [flow('suspend', 'flow-3')],
        execution: {
          'flowStatus': 'COMPLETE',
          'data': {
            'additionalData': {'emailSent': 'false'},
          },
        },
      );

      final result = await clientFor(server).runAccountLifecycleAction(
        AccountLifecycleSubjectKind.user,
        AccountLifecycleAction.suspend,
        'u-1',
        operatorNote: 'Ticket 4521',
      );

      expect(result.emailSent, isFalse);
      expect(server.executions, [
        {
          'flowId': 'flow-3',
          'inputs': {'subject': 'u-1', 'operatorNote': 'Ticket 4521'},
        },
      ]);
    });

    test('runAccountLifecycleAction fails with the operation error when no flow is configured', () async {
      final error = await clientFor(FakeServer())
          .runAccountLifecycleAction(AccountLifecycleSubjectKind.agent, AccountLifecycleAction.unlock, 'a-1')
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect((error! as AdministrationFlowError).flowCode, 'unlockAgent-NotConfiguredError-001');
    });

    test('runAccountLifecycleAction refuses to unlock an application without calling the server', () async {
      final server = FakeServer();

      final error = await clientFor(server)
          .runAccountLifecycleAction(AccountLifecycleSubjectKind.application, AccountLifecycleAction.unlock, 'app-1')
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect((error! as IAMException).code, ThunderIDErrorCode.invalidInput);
      expect(server.requests, isEmpty);
      expect(AccountLifecycleSubjectKind.application.flowConfigKeys, isNot(contains(AccountLifecycleAction.unlock)));
    });
  });

  group('getAccountLifecycleActions', () {
    const allUserFlows = {
      'userSuspendFlow': 'f-suspend',
      'userUnlockFlow': 'f-unlock',
      'userUnsuspendFlow': 'f-unsuspend',
    };
    const user = AccountLifecycleSubjectKind.user;
    const suspend = AccountLifecycleAction.suspend;
    const unlock = AccountLifecycleAction.unlock;
    const unsuspend = AccountLifecycleAction.unsuspend;

    test('offers the actions each status allows, most expected first', () {
      expect(getAccountLifecycleActions(user, AccessStatusValue.active, allUserFlows), [suspend]);
      expect(getAccountLifecycleActions(user, AccessStatusValue.locked, allUserFlows), [unlock, suspend]);
      expect(getAccountLifecycleActions(user, AccessStatusValue.suspended, allUserFlows), [unsuspend]);
    });

    test('reads an identity with no status as active', () {
      expect(getAccountLifecycleActions(user, null, allUserFlows), [suspend]);
    });

    test('offers only the actions whose flow is configured', () {
      expect(getAccountLifecycleActions(user, AccessStatusValue.locked, {'userSuspendFlow': 'f-suspend'}), [suspend]);
      expect(getAccountLifecycleActions(user, AccessStatusValue.active, {}), isEmpty);
    });

    test('reads the flows of the identity kind it is given', () {
      const agent = AccountLifecycleSubjectKind.agent;
      expect(getAccountLifecycleActions(agent, AccessStatusValue.active, allUserFlows), isEmpty);
      expect(
        getAccountLifecycleActions(agent, AccessStatusValue.locked, {'agentSuspendFlow': 'a', 'agentUnlockFlow': 'b'}),
        [unlock, suspend],
      );
    });

    test('never offers an unlock for an application', () {
      expect(
        getAccountLifecycleActions(
          AccountLifecycleSubjectKind.application,
          AccessStatusValue.locked,
          {'applicationSuspendFlow': 'a', 'applicationUnsuspendFlow': 'b'},
        ),
        [suspend],
      );
    });

    test('offers nothing for a status it does not know', () {
      expect(getAccountLifecycleActions(user, 'ARCHIVED', allUserFlows), isEmpty);
    });
  });

  group('access status', () {
    test('users and agents read their access status and its details', () {
      final user = ManagedUser.fromJson({
        'id': 'u-1',
        'ouId': 'ou-1',
        'type': 'customer',
        'status': {
          'value': 'LOCKED',
          'details': {
            'reason': 'FAILED_ATTEMPTS',
            'lockedMethods': [
              {'method': 'password', 'expiresAt': '2026-10-28T10:00:00Z'},
              {'method': 'account'},
            ],
          },
        },
      });
      final agent = Agent.fromJson({
        'id': 'a-1',
        'name': 'Bot',
        'ouId': 'ou-1',
        'type': 'bot',
        'status': {
          'value': 'SUSPENDED',
          'details': {'reason': 'ADMINISTRATIVE_SUSPENSION', 'operatorNote': 'Ticket 4521', 'since': '2026-10-27'},
        },
      });

      expect(user.status?.value, AccessStatusValue.locked);
      expect(user.status?.details?.reason, AccessHoldReason.failedAttempts);
      expect(user.status?.details?.lockedMethods?.map((m) => m.method), ['password', 'account']);
      expect(user.status?.details?.lockedMethods?.first.expiresAt, '2026-10-28T10:00:00Z');
      expect(agent.status?.value, AccessStatusValue.suspended);
      expect(agent.status?.details?.operatorNote, 'Ticket 4521');
      expect(agent.status?.details?.since, '2026-10-27');
    });

    test('a record without a status, or with a malformed one, has none', () {
      expect(ManagedUser.fromJson({'id': 'u-1', 'ouId': 'ou-1', 'type': 'customer'}).status, isNull);
      expect(
        ManagedUser.fromJson({'id': 'u-1', 'ouId': 'ou-1', 'type': 'customer', 'status': 'ACTIVE'}).status,
        isNull,
      );
      expect(Application.fromJson({'id': 'app-1', 'name': 'Shop', 'status': <String, Object?>{}}).status, isNull);
    });

    test('an application reads its status and does not keep it to send back', () {
      final application = Application.fromJson({
        'id': 'app-1',
        'name': 'Shop',
        'status': {'value': 'SUSPENDED'},
      });

      expect(application.status?.value, AccessStatusValue.suspended);
      expect(application.additionalFields.containsKey('status'), isFalse);
      expect(application.toJson().containsKey('status'), isFalse);
    });
  });

  group('connections', () {
    runCases({
      'getConnections': (
        (c) => c.getConnections(category: 'identity-provider', limit: 5),
        'GET',
        '/connections?category=identity-provider&limit=5',
        null,
      ),
      'getConnections of a type': (
        (c) => c.getConnections(type: ConnectionType.smsGateway, limit: 5),
        'GET',
        '/connections/sms-gateway',
        null,
      ),
      'getConnection': (
        (c) => c.getConnection(ConnectionType.oidc, 'c-1'),
        'GET',
        '/connections/oidc/c-1',
        null,
      ),
      'createConnection': (
        (c) => c.createConnection(
              ConnectionType.google,
              const ConnectionRequest(
                name: 'Google',
                settings: {'clientId': 'id', 'clientSecret': 's3cret', 'redirectUri': 'https://app/cb'},
              ),
            ),
        'POST',
        '/connections/google',
        {'clientId': 'id', 'clientSecret': 's3cret', 'redirectUri': 'https://app/cb', 'name': 'Google'},
      ),
      'updateConnection': (
        (c) => c.updateConnection(
              ConnectionType.emailSmtp,
              'c-1',
              const ConnectionRequest(name: 'Mail', description: 'Outbound', settings: {'host': 'smtp', 'port': 587}),
            ),
        'PUT',
        '/connections/email-smtp/c-1',
        {'host': 'smtp', 'port': 587, 'name': 'Mail', 'description': 'Outbound'},
      ),
      'deleteConnection': (
        (c) => c.deleteConnection(ConnectionType.authzenPdp, 'c-1'),
        'DELETE',
        '/connections/authzen-pdp/c-1',
        null,
      ),
      'getConnectionUsages': (
        (c) => c.getConnectionUsages(ConnectionType.twilio, 'c-1'),
        'GET',
        '/connections/twilio/c-1/usages',
        null,
      ),
      'getConnectionsMeta': (
        (c) => c.getConnectionsMeta(vendor: 'twilio'),
        'GET',
        '/connections/meta?vendor=twilio',
        null,
      ),
    });

    test('lists a type from its unpaged array, with that type on each connection', () async {
      final client = ThunderIDManagementClient(
        baseUrl: baseUrl,
        fetcher: (_) async => json([
          {'id': 'c-1', 'name': 'Risk engine'},
          {'id': 'c-2', 'name': 'Audit'},
        ]),
      );

      final page = await client.getConnections(type: ConnectionType.http);

      expect(page.totalResults, 2);
      expect(page.items.map((c) => c.type), [ConnectionType.http, ConnectionType.http]);
    });

    test('keeps type-specific settings, and never prints them', () async {
      final client = ThunderIDManagementClient(
        baseUrl: baseUrl,
        fetcher: (_) async => json({'id': 'c-1', 'name': 'Vonage', 'apiKey': 'k', 'apiSecret': 'x', 'senderId': 'ID'}),
      );

      final connection = await client.getConnection(ConnectionType.vonage, 'c-1');

      expect(connection.type, ConnectionType.vonage);
      expect(connection.settings, {'apiKey': 'k', 'apiSecret': 'x', 'senderId': 'ID'});
      expect(
        const ConnectionRequest(name: 'n', settings: {'apiSecret': 'x'}).toString(),
        isNot(contains('x')),
      );
    });

    test('refuses usages for an HTTP connection without sending anything', () async {
      final server = FakeServer();

      await expectLater(
        clientFor(server).getConnectionUsages(ConnectionType.http, 'c-1'),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.invalidInput)),
      );
      expect(server.requests, isEmpty);
    });
  });

  group('flows', () {
    runCases({
      'getFlows': (
        (c) => c.getFlows(flowType: FlowTypes.registration, limit: 10, offset: 20),
        'GET',
        '/flows?flowType=REGISTRATION&limit=10&offset=20',
        null,
      ),
      'getFlow': ((c) => c.getFlow('f-1'), 'GET', '/flows/f-1', null),
      'createFlow': (
        (c) => c.createFlow(
              const FlowDefinitionRequest(
                name: 'Login',
                handle: 'login',
                flowType: FlowTypes.authentication,
                nodes: [
                  {'id': 'start', 'type': 'START'},
                ],
              ),
            ),
        'POST',
        '/flows',
        {
          'name': 'Login',
          'handle': 'login',
          'flowType': 'AUTHENTICATION',
          'nodes': [
            {'id': 'start', 'type': 'START'},
          ],
        },
      ),
      'updateFlow': (
        (c) => c.updateFlow(
              'f-1',
              const FlowDefinitionRequest(name: 'Login', handle: 'login', flowType: 'AUTHENTICATION', nodes: []),
            ),
        'PUT',
        '/flows/f-1',
        {'name': 'Login', 'handle': 'login', 'flowType': 'AUTHENTICATION', 'nodes': <Object?>[]},
      ),
      'deleteFlow': ((c) => c.deleteFlow('f-1'), 'DELETE', '/flows/f-1', null),
      'getFlowVersions': ((c) => c.getFlowVersions('f-1'), 'GET', '/flows/f-1/versions', null),
      'getFlowVersion': ((c) => c.getFlowVersion('f-1', 3), 'GET', '/flows/f-1/versions/3', null),
      'restoreFlowVersion': ((c) => c.restoreFlowVersion('f-1', 2), 'POST', '/flows/f-1/restore', {'version': 2}),
      'getFlowUsages': ((c) => c.getFlowUsages('f-1'), 'GET', '/flows/f-1/usages', null),
    });

    test('the flows override applies to getFlows but not to the administration flow lookup', () async {
      final server = FakeServer();
      final client = clientFor(server, endpoints: const {ManagementEndpointKeys.flows: 'https://flows.example.com/flows'});

      await client.getFlows(limit: 1);
      await client.findAdministrationFlows(['x']);

      expect(server.calls, [
        'GET https://flows.example.com/flows?limit=1',
        'GET $baseUrl/flows?flowType=ADMINISTRATION&limit=100&offset=0',
      ]);
    });

    test('parses versions and usages', () async {
      final versions = FlowVersions.fromJson({
        'totalVersions': 2,
        'versions': [
          {'version': 2, 'createdAt': '2026-01-02T00:00:00Z', 'isActive': true},
          {'version': 1, 'createdAt': '2026-01-01T00:00:00Z', 'isActive': false},
        ],
      });
      expect(versions.versions.first.isActive, isTrue);

      final usages = ResourceUsages.fromJson({
        'totalResults': 1,
        'count': 1,
        'summary': {'application': 1},
        'usages': [
          {'resourceType': 'application', 'id': 'app-1', 'displayName': 'Shop', 'behaviorOnDelete': 'fallback'},
        ],
      });
      expect(usages.summary, {'application': 1});
      expect(usages.usages.single.behaviorOnDelete, 'fallback');
    });
  });

  group('notification templates', () {
    const content = NotificationTemplateContent(subject: 'Hi', body: 'Hello {{name}}');
    runCases({
      'getNotificationTemplates': (
        (c) => c.getNotificationTemplates(NotificationChannel.email, limit: 5),
        'GET',
        '/notification-templates/email/templates?limit=5',
        null,
      ),
      'getNotificationTemplate': (
        (c) => c.getNotificationTemplate(NotificationChannel.sms, 't-1'),
        'GET',
        '/notification-templates/sms/templates/t-1',
        null,
      ),
      'createNotificationTemplate': (
        (c) => c.createNotificationTemplate(
              NotificationChannel.email,
              const CreateNotificationTemplateRequest(
                handle: 'welcome',
                ouId: 'ou-1',
                displayName: 'Welcome',
                content: content,
                colorScheme: 'dark',
              ),
            ),
        'POST',
        '/notification-templates/email/templates',
        {
          'handle': 'welcome',
          'ouId': 'ou-1',
          'displayName': 'Welcome',
          'design': {'colorScheme': 'dark'},
          'content': {'subject': 'Hi', 'body': 'Hello {{name}}'},
        },
      ),
      'updateNotificationTemplate': (
        (c) => c.updateNotificationTemplate(
              NotificationChannel.sms,
              't-1',
              const UpdateNotificationTemplateRequest(
                displayName: 'OTP',
                content: NotificationTemplateContent(body: 'Code {{otp}}'),
              ),
            ),
        'PUT',
        '/notification-templates/sms/templates/t-1',
        {
          'displayName': 'OTP',
          'content': {'body': 'Code {{otp}}'},
        },
      ),
      'deleteNotificationTemplate': (
        (c) => c.deleteNotificationTemplate(NotificationChannel.email, 't-1'),
        'DELETE',
        '/notification-templates/email/templates/t-1',
        null,
      ),
    });
  });

  group('design', () {
    const theme = DesignThemeRequest(handle: 'dark', displayName: 'Dark', theme: {'colorSchemes': <String, Object?>{}});
    const layout = DesignLayoutRequest(handle: 'centered', displayName: 'Centered', layout: {'variant': 'centered'});
    runCases({
      'getThemes': ((c) => c.getThemes(limit: 3), 'GET', '/design/themes?limit=3', null),
      'getTheme': ((c) => c.getTheme('t-1'), 'GET', '/design/themes/t-1', null),
      'createTheme': (
        (c) => c.createTheme(theme),
        'POST',
        '/design/themes',
        {'handle': 'dark', 'displayName': 'Dark', 'theme': {'colorSchemes': <String, Object?>{}}},
      ),
      'updateTheme': (
        (c) => c.updateTheme('t-1', theme),
        'PUT',
        '/design/themes/t-1',
        {'handle': 'dark', 'displayName': 'Dark', 'theme': {'colorSchemes': <String, Object?>{}}},
      ),
      'deleteTheme': ((c) => c.deleteTheme('t-1'), 'DELETE', '/design/themes/t-1', null),
      'getThemeUsages': ((c) => c.getThemeUsages('t-1'), 'GET', '/design/themes/t-1/usages', null),
      'getLayouts': ((c) => c.getLayouts(offset: 4), 'GET', '/design/layouts?offset=4', null),
      'getLayout': ((c) => c.getLayout('l-1'), 'GET', '/design/layouts/l-1', null),
      'createLayout': (
        (c) => c.createLayout(layout),
        'POST',
        '/design/layouts',
        {'handle': 'centered', 'displayName': 'Centered', 'layout': {'variant': 'centered'}},
      ),
      'updateLayout': (
        (c) => c.updateLayout('l-1', layout),
        'PUT',
        '/design/layouts/l-1',
        {'handle': 'centered', 'displayName': 'Centered', 'layout': {'variant': 'centered'}},
      ),
      'deleteLayout': ((c) => c.deleteLayout('l-1'), 'DELETE', '/design/layouts/l-1', null),
      'getLayoutUsages': ((c) => c.getLayoutUsages('l-1', limit: 1), 'GET', '/design/layouts/l-1/usages?limit=1', null),
      'resolveDesign': (
        (c) => c.resolveDesign(DesignEntityType.application, 'app-1'),
        'GET',
        '/design/resolve?type=APP&id=app-1',
        null,
      ),
    });
  });

  group('translations', () {
    runCases({
      'getLanguages': ((c) => c.getLanguages(), 'GET', '/i18n/languages', null),
      'resolveTranslations': (
        (c) => c.resolveTranslations('en-US', namespace: 'signin'),
        'GET',
        '/i18n/languages/en-US/translations/resolve?namespace=signin',
        null,
      ),
      'resolveTranslation': (
        (c) => c.resolveTranslation('en-US', 'signin', 'title'),
        'GET',
        '/i18n/languages/en-US/translations/ns/signin/keys/title/resolve',
        null,
      ),
      'setTranslations': (
        (c) => c.setTranslations(
              'fr',
              const SetTranslationsRequest(
                translations: {
                  'signin': {'title': 'Connexion'},
                },
              ),
            ),
        'POST',
        '/i18n/languages/fr/translations',
        {
          'translations': {
            'signin': {'title': 'Connexion'},
          },
        },
      ),
      'deleteTranslations': ((c) => c.deleteTranslations('fr'), 'DELETE', '/i18n/languages/fr/translations', null),
      'setTranslation': (
        (c) => c.setTranslation('fr', 'signin', 'title', const SetTranslationRequest(value: 'Connexion')),
        'POST',
        '/i18n/languages/fr/translations/ns/signin/keys/title',
        {'value': 'Connexion'},
      ),
      'deleteTranslation': (
        (c) => c.deleteTranslation('fr', 'signin', 'title'),
        'DELETE',
        '/i18n/languages/fr/translations/ns/signin/keys/title',
        null,
      ),
    });

    test('parses languages and a translation bundle', () async {
      final client = ThunderIDManagementClient(
        baseUrl: baseUrl,
        fetcher: (request) async => request.url.path.endsWith('/languages')
            ? json({
                'languages': ['en-US', 'fr'],
              })
            : json({
                'language': 'fr',
                'totalResults': 1,
                'translations': {
                  'signin': {'title': 'Connexion'},
                },
              }),
      );

      expect(await client.getLanguages(), ['en-US', 'fr']);
      final bundle = await client.resolveTranslations('fr');
      expect(bundle.translations['signin']?['title'], 'Connexion');
    });
  });

  group('server configuration', () {
    runCases({
      'getServerConfigs': ((c) => c.getServerConfigs(), 'GET', '/server-config', null),
      'getServerConfig': ((c) => c.getServerConfig('accountAccess'), 'GET', '/server-config/accountAccess', null),
      'updateServerConfig': (
        (c) => c.updateServerConfig('notification', const {'defaultEmailSenderId': 'c-1'}),
        'PUT',
        '/server-config/notification',
        {'defaultEmailSenderId': 'c-1'},
      ),
    });

    test('parses the configuration names and layers', () async {
      final client = ThunderIDManagementClient(
        baseUrl: baseUrl,
        fetcher: (request) async => request.url.path == '/server-config'
            ? json(['flow', 'notification'])
            : json({
                'readOnly': {'a': 1},
                'writable': {'b': 2},
                'merged': {'a': 1, 'b': 2},
              }),
      );

      expect(await client.getServerConfigs(), ['flow', 'notification']);
      final layers = await client.getServerConfig('flow');
      expect(layers.merged, {'a': 1, 'b': 2});
      expect(layers.readOnly, {'a': 1});
    });
  });

  group('gateways', () {
    runCases({
      'getGateways': ((c) => c.getGateways(), 'GET', '/gateways', null),
      'getGateway': ((c) => c.getGateway('g-1'), 'GET', '/gateways/g-1', null),
      'createGateway': (
        (c) => c.createGateway(const RegisterGatewayRequest(name: 'Edge', baseUrl: 'https://edge', isDefault: true)),
        'POST',
        '/gateways',
        {'name': 'Edge', 'baseUrl': 'https://edge', 'isDefault': true},
      ),
      'updateGateway': (
        (c) => c.updateGateway('g-1', const UpdateGatewayRequest(name: 'Edge 2')),
        'PUT',
        '/gateways/g-1',
        {'name': 'Edge 2'},
      ),
      'deleteGateway': ((c) => c.deleteGateway('g-1'), 'DELETE', '/gateways/g-1', null),
      'applyGatewayConfiguration': (
        (c) => c.applyGatewayConfiguration(
              'g-1',
              payload: const ApplyGatewayConfigurationRequest(version: 'abc1234', dryRun: true),
            ),
        'POST',
        '/gateways/g-1/apply',
        {'version': 'abc1234', 'dryRun': true},
      ),
      'applyGatewayConfiguration without a payload': (
        (c) => c.applyGatewayConfiguration('g-1'),
        'POST',
        '/gateways/g-1/apply',
        <String, Object?>{},
      ),
      'revertGatewayConfiguration': (
        (c) => c.revertGatewayConfiguration(
              'g-1',
              payload: const RevertGatewayConfigurationRequest(confirmRemovals: true),
            ),
        'POST',
        '/gateways/g-1/revert',
        {'confirmRemovals': true},
      ),
      'getGatewayConfigurationDiff': (
        (c) => c.getGatewayConfigurationDiff('g-1', version: 'latest'),
        'GET',
        '/gateways/g-1/diff?version=latest',
        null,
      ),
      'getGatewayAppliedConfiguration': (
        (c) => c.getGatewayAppliedConfiguration('g-1'),
        'GET',
        '/gateways/g-1/applied-configuration',
        null,
      ),
      'getGatewayAppliedVersion': (
        (c) => c.getGatewayAppliedVersion('g-1'),
        'GET',
        '/gateways/g-1/applied-version',
        null,
      ),
      'getGatewayVariables': (
        (c) => c.getGatewayVariables('g-1', names: ['A', 'B'], limit: 2),
        'GET',
        '/gateways/g-1/variables?names=A&names=B&limit=2',
        null,
      ),
      'getGatewayVariable': (
        (c) => c.getGatewayVariable('g-1', 'A'),
        'GET',
        '/gateways/g-1/variables/A',
        null,
      ),
      'createGatewayVariable': (
        (c) => c.createGatewayVariable('g-1', const CreateVariableRequest(name: 'A', value: '1')),
        'POST',
        '/gateways/g-1/variables',
        {'name': 'A', 'value': '1'},
      ),
      'updateGatewayVariable': (
        (c) => c.updateGatewayVariable('g-1', 'A', const UpdateVariableRequest(value: '2')),
        'PUT',
        '/gateways/g-1/variables/A',
        {'value': '2'},
      ),
      'deleteGatewayVariable': (
        (c) => c.deleteGatewayVariable('g-1', 'A'),
        'DELETE',
        '/gateways/g-1/variables/A',
        null,
      ),
      'getGatewaySecrets': ((c) => c.getGatewaySecrets('g-1'), 'GET', '/gateways/g-1/secrets', null),
      'getGatewaySecret': ((c) => c.getGatewaySecret('g-1', 'S'), 'GET', '/gateways/g-1/secrets/S', null),
      'createGatewaySecret': (
        (c) => c.createGatewaySecret('g-1', const CreateSecretRequest(name: 'S', value: 'v')),
        'POST',
        '/gateways/g-1/secrets',
        {'name': 'S', 'value': 'v'},
      ),
      'updateGatewaySecret': (
        (c) => c.updateGatewaySecret('g-1', 'S', const UpdateSecretRequest(value: 'w', description: 'Key')),
        'PUT',
        '/gateways/g-1/secrets/S',
        {'value': 'w', 'description': 'Key'},
      ),
      'deleteGatewaySecret': ((c) => c.deleteGatewaySecret('g-1', 'S'), 'DELETE', '/gateways/g-1/secrets/S', null),
    });

    test('parses a registration with its key, and an apply result', () async {
      final registration = GatewayRegistration.fromJson({'id': 'g-1', 'name': 'Edge', 'baseUrl': 'https://e', 'key': 'k'});
      expect(registration.gateway.id, 'g-1');
      expect(registration.key, 'k');
      expect(const RegisterGatewayRequest(name: 'n', baseUrl: 'b', key: 'k').toString(), isNot(contains('k)')));

      final result = GatewayApplyResult.fromJson({
        'gatewayId': 'g-1',
        'queued': true,
        'diff': {
          'summary': {'added': 1, 'updated': 0},
          'changes': [
            {
              'key': 'application/a',
              'change': 'added',
              'lines': [
                {'kind': '+', 'text': 'name: Shop'},
              ],
            },
          ],
        },
        'missing': {
          'variables': ['A'],
          'secrets': <String>[],
        },
      });
      expect(result.queued, isTrue);
      expect(result.diff?.summary, {'added': 1, 'updated': 0});
      expect(result.diff?.changes.single.lines.single['kind'], '+');
      expect(result.missing?.variables, ['A']);
    });
  });

  group('variables and secrets', () {
    runCases({
      'getVariables': (
        (c) => c.getVariables(names: ['A'], filter: 'name sw "A"', limit: 1),
        'GET',
        '/variables?names=A&filter=name+sw+%22A%22&limit=1',
        null,
      ),
      'getVariable': ((c) => c.getVariable('A'), 'GET', '/variables/A', null),
      'createVariable': (
        (c) => c.createVariable(const CreateVariableRequest(name: 'A', value: '1', description: 'First')),
        'POST',
        '/variables',
        {'name': 'A', 'value': '1', 'description': 'First'},
      ),
      'updateVariable': (
        (c) => c.updateVariable('A', const UpdateVariableRequest(value: '2')),
        'PUT',
        '/variables/A',
        {'value': '2'},
      ),
      'deleteVariable': ((c) => c.deleteVariable('A'), 'DELETE', '/variables/A', null),
      'getSecrets': ((c) => c.getSecrets(offset: 2), 'GET', '/secrets?offset=2', null),
      'getSecret': ((c) => c.getSecret('S'), 'GET', '/secrets/S', null),
      'createSecret': (
        (c) => c.createSecret(const CreateSecretRequest(name: 'S', value: 'v')),
        'POST',
        '/secrets',
        {'name': 'S', 'value': 'v'},
      ),
      'updateSecret': (
        (c) => c.updateSecret('S', const UpdateSecretRequest(value: 'w')),
        'PUT',
        '/secrets/S',
        {'value': 'w'},
      ),
      'deleteSecret': ((c) => c.deleteSecret('S'), 'DELETE', '/secrets/S', null),
    });

    test('variables and secrets have their own overrides', () async {
      final server = FakeServer();
      final client = clientFor(
        server,
        endpoints: const {
          ManagementEndpointKeys.variables: 'https://vault.example.com/vars',
          ManagementEndpointKeys.secrets: 'https://vault.example.com/secrets',
        },
      );

      await client.getVariable('A');
      await client.deleteSecret('S');

      expect(server.calls, ['GET https://vault.example.com/vars/A', 'DELETE https://vault.example.com/secrets/S']);
    });

    test('a secret reads back without a value, and a secret request never prints its value', () {
      final secret = Secret.fromJson({'name': 'S', 'exists': true, 'description': 'API key'});
      expect(secret.exists, isTrue);
      expect(const CreateSecretRequest(name: 'S', value: 'hunter2').toString(), isNot(contains('hunter2')));
      expect(const UpdateSecretRequest(value: 'hunter2').toString(), isNot(contains('hunter2')));
    });
  });

  group('configuration versions, export and import', () {
    runCases({
      'getConfigurationVersions': ((c) => c.getConfigurationVersions(), 'GET', '/configuration-versions', null),
      'getConfigurationVersion': (
        (c) => c.getConfigurationVersion('abc1234'),
        'GET',
        '/configuration-versions/abc1234',
        null,
      ),
      'createConfigurationVersion': (
        (c) => c.createConfigurationVersion(const CreateConfigurationVersionRequest(name: 'v1', current: true)),
        'POST',
        '/configuration-versions',
        {'name': 'v1', 'current': true},
      ),
      'exportConfiguration': (
        (c) => c.exportConfiguration(
              const ExportConfigurationRequest(
                applications: ['*'],
                themes: ['t-1'],
                options: ExportOptions(includeDependencies: true),
              ),
            ),
        'POST',
        '/export',
        {
          'applications': ['*'],
          'themes': ['t-1'],
          'options': {'includeDependencies': true},
        },
      ),
      'importConfiguration': (
        (c) => c.importConfiguration(
              const ImportConfigurationRequest(
                content: 'kind: Application',
                variables: {'A': '1'},
                dryRun: true,
                deletions: [ImportResourceDeletion(resourceType: 'application', id: 'app-1')],
                options: ImportOptions(upsert: true),
              ),
            ),
        'POST',
        '/import',
        {
          'content': 'kind: Application',
          'variables': {'A': '1'},
          'dryRun': true,
          'deletions': [
            {'resourceType': 'application', 'id': 'app-1'},
          ],
          'options': {'upsert': true},
        },
      ),
      'deleteImportedConfiguration': (
        (c) => c.deleteImportedConfiguration(
              const DeleteImportedConfigurationRequest(resourceType: 'application', resourceKey: 'shop'),
            ),
        'POST',
        '/import/delete',
        {'resourceType': 'application', 'resourceKey': 'shop'},
      ),
    });

    test('import and export follow their own overrides', () async {
      final server = FakeServer();
      final client = clientFor(
        server,
        endpoints: const {
          ManagementEndpointKeys.import: 'https://cfg.example.com/in',
          ManagementEndpointKeys.export: 'https://cfg.example.com/out',
          ManagementEndpointKeys.configurationVersions: 'https://cfg.example.com/versions',
        },
      );

      await client.exportConfiguration(const ExportConfigurationRequest());
      await client.deleteImportedConfiguration(
        const DeleteImportedConfigurationRequest(resourceType: 'flow', resourceKey: 'login'),
      );
      await client.getConfigurationVersion('1');

      expect(server.calls, [
        'POST https://cfg.example.com/out',
        'POST https://cfg.example.com/in/delete',
        'GET https://cfg.example.com/versions/1',
      ]);
    });

    test('parses versions, an export and an import result', () async {
      final client = ThunderIDManagementClient(
        baseUrl: baseUrl,
        fetcher: (request) async => switch (request.url.path) {
          '/configuration-versions' => json([
              {
                'number': 2,
                'version': 'abc',
                'current': true,
                'createdBy': {'id': 'u-1', 'name': 'Ada'},
                'references': [
                  {'name': 'A', 'kind': 'variable'},
                ],
              },
            ]),
          '/export' => json({'resources': 'kind: Application', 'environment_variables': 'A=1'}),
          _ => json({
              'summary': {'totalDocuments': 2, 'imported': 1, 'failed': 1, 'importedAt': '2026-01-01T00:00:00Z'},
              'results': [
                {'resourceType': 'application', 'status': 'failed', 'code': 'APP-1001'},
              ],
            }),
        },
      );

      final versions = await client.getConfigurationVersions();
      expect(versions.single.number, 2);
      expect(versions.single.createdBy?.name, 'Ada');
      expect(versions.single.references.single.kind, 'variable');

      final exported = await client.exportConfiguration(const ExportConfigurationRequest(applications: ['*']));
      expect(exported.environmentVariables, 'A=1');

      final imported = await client.importConfiguration(const ImportConfigurationRequest(content: 'x'));
      expect(imported.summary.failed, 1);
      expect(imported.results.single.code, 'APP-1001');
    });
  });

  group('endpoint keys', () {
    test('every collection has a key and an EndpointsConfig field', () {
      expect(ManagementEndpointKeys.values, hasLength(21));
      const config = EndpointsConfig(
        organizationUnits: 'https://e/ou',
        resourceServers: 'https://e/rs',
        connections: 'https://e/c',
        flows: 'https://e/f',
        notificationTemplates: 'https://e/nt',
        design: 'https://e/d',
        i18n: 'https://e/i',
        serverConfig: 'https://e/sc',
        gateways: 'https://e/g',
        variables: 'https://e/v',
        secrets: 'https://e/s',
        configurationVersions: 'https://e/cv',
        import: 'https://e/in',
        export: 'https://e/out',
      );
      expect(config.collections.keys.toSet(), ManagementEndpointKeys.values.skip(7).toSet());
    });

    test('a management error keeps 403 and 404 distinct for the new operations', () async {
      ThunderIDManagementClient answering(int status) => ThunderIDManagementClient(
            baseUrl: baseUrl,
            fetcher: (_) async => ManagementResponse(statusCode: status, statusText: 'x', body: ''),
          );

      await expectLater(
        answering(403).getGateways(),
        throwsA(isA<IAMApiException>().having((e) => e.code, 'code', ThunderIDErrorCode.forbidden)),
      );
      await expectLater(
        answering(404).getTheme('t-1'),
        throwsA(
          isA<IAMApiException>()
              .having((e) => e.code, 'code', ThunderIDErrorCode.notFound)
              .having((e) => e.operation, 'operation', 'getTheme'),
        ),
      );
    });
  });
}
