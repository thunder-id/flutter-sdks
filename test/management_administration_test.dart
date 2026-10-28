// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

const baseUrl = 'https://localhost:8090';

ManagementResponse json(Object? body) => ManagementResponse(statusCode: 200, statusText: 'OK', body: jsonEncode(body));

/// A fetcher that answers like the server: the flow configuration, the flow listing, flow
/// execution, and [resource] for every other request. Every request is recorded.
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
    if (url.startsWith('$baseUrl/flows?')) return json({'flows': flows});
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

  ManagementRequest? firstWithMethod(String method) {
    for (final r in requests) {
      if (r.method == method) return r;
    }
    return null;
  }

  Object? bodyOf(String method) {
    final body = firstWithMethod(method)?.body;
    return body == null ? null : jsonDecode(body);
  }
}

Map<String, Object?> flow(String handle, String id) => {'flowType': 'ADMINISTRATION', 'handle': handle, 'id': id};

Map<String, Object?> configured(String key, String handle) => {
      key: {'defaultHandle': handle},
    };

void main() {
  ThunderIDManagementClient clientFor(FakeServer server, {String base = baseUrl}) =>
      ThunderIDManagementClient(baseUrl: base, fetcher: server.call);

  group('server error envelope', () {
    test("keeps the server's error envelope, with its code and params", () async {
      final client = ThunderIDManagementClient(
        baseUrl: baseUrl,
        fetcher: (request) async => ManagementResponse(
          statusCode: 409,
          statusText: 'Conflict',
          body: jsonEncode({
            'code': 'USR-1027',
            'message': {'key': 'error.user.delete', 'defaultValue': 'User cannot be deleted'},
            'description': {
              'defaultValue': 'Agents depend on it',
              'params': {'dependencies': 'agents'},
            },
          }),
        ),
      );
      final error = await client.deleteUser('u-1').then<Object?>((_) => null, onError: (Object e) => e);

      expect(error, isA<IAMApiException>());
      error as IAMApiException;
      expect(error.code, ThunderIDErrorCode.invalidInput, reason: 'existing status mapping is unchanged');
      expect(error.message, isNot(contains('Agents depend on it')));
      final serverError = error.serverError!;
      expect(serverError.code, 'USR-1027');
      expect(serverError.message?.key, 'error.user.delete');
      expect(serverError.message?.defaultValue, 'User cannot be deleted');
      expect(serverError.description?.defaultValue, 'Agents depend on it');
      expect(serverError.description?.params, {'dependencies': 'agents'});
    });

    test('reads a plain-string description as its default value', () {
      final serverError = ServerError.tryParse('{"code":"SSE-5000","description":"Something broke"}')!;
      expect(serverError.code, 'SSE-5000');
      expect(serverError.description?.defaultValue, 'Something broke');
      expect(serverError.description?.key, isNull);
      expect(serverError.message, isNull);
    });

    test('has no server error when the body is not an error envelope', () {
      IAMApiException withBody(String? body) =>
          IAMApiException(ThunderIDErrorCode.serverError, 'x', statusCode: 500, operation: 'getUser', responseBody: body);

      expect(withBody('Bad gateway').serverError, isNull);
      expect(withBody('{"foo":1}').serverError, isNull);
      expect(withBody('{"code":42}').serverError, isNull);
      expect(withBody('[1,2]').serverError, isNull);
      expect(withBody('').serverError, isNull);
      expect(withBody(null).serverError, isNull);
    });
  });

  group('management API additions', () {
    final cases = <String, (Future<Object?> Function(ThunderIDManagementClient), String, String, Object?)>{
      'getUserUsages': ((c) => c.getUserUsages('u-1'), 'GET', '/users/u-1/usages', null),
      'updateUserCredentials': (
        (c) => c.updateUserCredentials('u-1', const UpdateUserCredentialsRequest(credentials: {'password': 'p'})),
        'POST',
        '/users/u-1/update-credentials',
        {
          'credentials': {'password': 'p'},
        },
      ),
      'getUserTypes': ((c) => c.getUserTypes(limit: 10), 'GET', '/user-types?include=display&limit=10', null),
      'getUserType': ((c) => c.getUserType('t-1'), 'GET', '/user-types/t-1?include=display', null),
      'createUserType': (
        (c) => c.createUserType(
              const CreateUserTypeRequest(handle: 'staff', displayName: 'Staff', ouId: 'ou-1', schema: {}),
            ),
        'POST',
        '/user-types',
        {'displayName': 'Staff', 'handle': 'staff', 'ouId': 'ou-1', 'schema': <String, Object?>{}},
      ),
      'updateUserType': (
        (c) => c.updateUserType('t-1', const UpdateUserTypeRequest(displayName: 'Staff', ouId: 'ou-1', schema: {})),
        'PUT',
        '/user-types/t-1',
        {'displayName': 'Staff', 'ouId': 'ou-1', 'schema': <String, Object?>{}},
      ),
      'deleteUserType': ((c) => c.deleteUserType('t-1'), 'DELETE', '/user-types/t-1', null),
      'getAgentTypes': ((c) => c.getAgentTypes(), 'GET', '/agent-types?include=display', null),
      'getAgentType': ((c) => c.getAgentType('a-1'), 'GET', '/agent-types/a-1?include=display', null),
      'updateAgentType': (
        (c) => c.updateAgentType(
              'a-1',
              const UpdateAgentTypeRequest(
                displayName: 'Bot',
                ouId: 'ou-1',
                schema: {},
                systemAttributes: EntityTypeSystemAttributes(display: 'name', primaryEmail: 'ignored'),
              ),
            ),
        'PUT',
        '/agent-types/a-1',
        {
          'displayName': 'Bot',
          'ouId': 'ou-1',
          'schema': <String, Object?>{},
          'systemAttributes': {'display': 'name'},
        },
      ),
      'getRoles': ((c) => c.getRoles(limit: 5), 'GET', '/roles?include=display&limit=5', null),
      'getRole': ((c) => c.getRole('r-1'), 'GET', '/roles/r-1?include=display', null),
      'previewCimdDocument': (
        (c) => c.previewCimdDocument('https://client.example/cimd.json'),
        'POST',
        '/cimd/preview',
        {'clientId': 'https://client.example/cimd.json'},
      ),
      'getApplications': (
        (c) => c.getApplications(limit: 10, offset: 20),
        'GET',
        '/applications?limit=10&offset=20',
        null,
      ),
      'getApplication': ((c) => c.getApplication('app-1'), 'GET', '/applications/app-1', null),
      'createApplication': (
        (c) => c.createApplication(
              const CreateApplicationRequest(
                name: 'Shop',
                ouId: 'ou-1',
                type: 'browser',
                inboundAuthConfig: [
                  InboundAuthConfig(
                    config: OAuth2Config(
                      grantTypes: [OAuth2GrantTypes.authorizationCode],
                      responseTypes: [OAuth2ResponseTypes.code],
                      redirectUris: ['https://shop.example/callback'],
                      pkceRequired: true,
                    ),
                  ),
                ],
              ),
            ),
        'POST',
        '/applications',
        {
          'name': 'Shop',
          'type': 'browser',
          'ouId': 'ou-1',
          'inboundAuthConfig': [
            {
              'type': 'oauth2',
              'config': {
                'redirectUris': ['https://shop.example/callback'],
                'grantTypes': ['authorization_code'],
                'responseTypes': ['code'],
                'pkceRequired': true,
              },
            },
          ],
        },
      ),
      'updateApplication': (
        (c) => c.updateApplication('app-1', const UpdateApplicationRequest(name: 'Shop 2', description: 'New')),
        'PUT',
        '/applications/app-1',
        {'name': 'Shop 2', 'description': 'New'},
      ),
      'deleteApplication': ((c) => c.deleteApplication('app-1'), 'DELETE', '/applications/app-1', null),
    };

    cases.forEach((name, entry) {
      final (run, method, path, body) = entry;
      test('$name calls the right endpoint', () async {
        final server = FakeServer();

        await run(clientFor(server));

        expect(server.calls, ['$method $baseUrl$path']);
        final sent = server.requests.single.body;
        expect(sent == null ? null : jsonDecode(sent), body);
      });
    });

    test('parses user usages, type details and a CIMD preview', () async {
      final usages = await clientFor(
        FakeServer(
          resource: {
            'count': 1,
            'totalResults': null,
            'summary': {'agent': 1},
            'usages': [
              {'id': 'a-1', 'displayName': 'Bot', 'resourceType': 'agent', 'behaviorOnDelete': 'restrict'},
            ],
          },
        ),
      ).getUserUsages('u-1');
      expect(usages.count, 1);
      expect(usages.totalResults, isNull, reason: 'the server could not tell');
      expect(usages.summary, {'agent': 1});
      expect(usages.usages.single.behaviorOnDelete, UserUsageBehavior.restrict);

      final userType = await clientFor(
        FakeServer(
          resource: {
            'id': 't-1',
            'handle': 'staff',
            'displayName': 'Staff',
            'ouId': 'ou-1',
            'ouHandle': 'root',
            'schema': {
              'email': {'type': 'email', 'required': true},
            },
            'systemAttributes': {'display': 'email', 'primaryEmail': 'email'},
          },
        ),
      ).getUserType('t-1');
      expect(userType.ouHandle, 'root');
      expect(userType.schema.keys, ['email']);
      expect(userType.systemAttributes?.primaryEmail, 'email');

      final preview = await clientFor(
        FakeServer(
          resource: {
            'name': 'Client',
            'contacts': ['ops@client.example'],
            'inboundAuthConfig': [
              {'type': 'oauth2', 'config': <String, Object?>{}},
            ],
          },
        ),
      ).previewCimdDocument('https://client.example/cimd.json');
      expect(preview.name, 'Client');
      expect(preview.contacts, ['ops@client.example']);
      expect(preview.inboundAuthConfig.single.type, 'oauth2');
    });

    test('parses an application page and a full application', () async {
      final page = await clientFor(
        FakeServer(
          resource: {
            'totalResults': 5,
            'count': 1,
            'applications': [
              {'id': 'app-1', 'name': 'Shop', 'clientId': 'client', 'type': 'browser', 'isReadOnly': true},
            ],
          },
        ),
      ).getApplications(limit: 1);
      expect(page.totalResults, 5);
      expect(page.items.single.clientId, 'client');
      expect(page.items.single.isReadOnly, isTrue);

      final application = await clientFor(
        FakeServer(
          resource: {
            'id': 'app-1',
            'name': 'Shop',
            'createdAt': '2026-10-01',
            'ouId': 'ou-1',
            'assertion': {
              'validityPeriod': 3600,
              'userAttributes': ['email'],
            },
            'attestation': {
              'devMode': true,
              'apple': {'teamId': 'T', 'bundleId': 'B'},
            },
            'inboundAuthConfig': [
              {
                'type': 'oauth2',
                'config': {
                  'clientId': 'client',
                  'grantTypes': ['authorization_code', 'refresh_token'],
                  'responseTypes': ['code'],
                  'scopeClaims': {
                    'email': ['email', 'email_verified'],
                  },
                  'certificate': {'type': 'JWKS_URI', 'value': 'https://shop.example/jwks'},
                  'token': {
                    'accessToken': {
                      'userConfig': {
                        'validityPeriod': 600,
                        'attributes': ['groups'],
                      },
                    },
                    'idToken': {'validityPeriod': 300, 'responseType': 'JWT'},
                    'refreshToken': {'validityPeriod': 86400},
                    'idJag': {'enabled': true},
                  },
                  'userInfo': {'responseType': 'JSON'},
                },
              },
            ],
          },
        ),
      ).getApplication('app-1');
      expect(application.id, 'app-1');
      expect(application.createdAt, '2026-10-01');
      expect(application.assertion?.validityPeriod, 3600);
      expect(application.attestation?.apple?.bundleId, 'B');
      final oauth = application.oauth2Config!;
      expect(oauth.clientId, 'client');
      expect(oauth.grantTypes, ['authorization_code', 'refresh_token']);
      expect(oauth.scopeClaims, {
        'email': ['email', 'email_verified'],
      });
      expect(oauth.certificate?.value, 'https://shop.example/jwks');
      expect(oauth.token?.accessToken?.userConfig?.validityPeriod, 600);
      expect(oauth.token?.idToken?.responseType, 'JWT');
      expect(oauth.token?.refreshToken?.validityPeriod, 86400);
      expect(oauth.token?.idJag?.enabled, isTrue);
      expect(oauth.userInfo?.responseType, 'JSON');
    });

    test('an application read from the server goes back in an update without its server-set fields', () async {
      final read = {
        'id': 'app-1',
        'name': 'Shop',
        'createdAt': '2026-10-01',
        'updatedAt': '2026-10-02',
        'status': {'value': 'ACTIVE'},
        'futureField': {'kept': true},
        'inboundAuthConfig': [
          {
            'type': 'oauth2',
            'config': {
              'clientId': 'client',
              'grantTypes': ['client_credentials'],
              'responseTypes': <String>[],
              'futureOAuthField': 'kept',
            },
          },
        ],
      };
      final server = FakeServer(resource: read);
      final client = clientFor(server);

      final application = await client.getApplication('app-1');
      await client.updateApplication('app-1', application);

      expect(server.bodyOf('PUT'), {
        'name': 'Shop',
        'futureField': {'kept': true},
        'inboundAuthConfig': [
          {
            'type': 'oauth2',
            'config': {
              'clientId': 'client',
              'grantTypes': ['client_credentials'],
              'responseTypes': <String>[],
              'futureOAuthField': 'kept',
            },
          },
        ],
      });
    });

    test('an applications endpoint override applies to the application operations, not the CIMD preview', () async {
      final server = FakeServer(resource: {'id': 'app-1', 'name': 'Shop'});
      final client = ThunderIDManagementClient(
        baseUrl: baseUrl,
        endpoints: const {ManagementEndpointKeys.applications: 'https://apps.example.com/v1/applications'},
        fetcher: server.call,
      );

      await client.getApplications(limit: 1);
      await client.getApplication('app-1');
      await client.deleteApplication('app-1');
      await client.previewCimdDocument('https://client.example/cimd.json');

      expect(server.calls, [
        'GET https://apps.example.com/v1/applications?limit=1',
        'GET https://apps.example.com/v1/applications/app-1',
        'DELETE https://apps.example.com/v1/applications/app-1',
        'POST $baseUrl/cimd/preview',
      ]);
    });
  });

  group('administration flows', () {
    FakeServer userDeletion({Object? execution}) => FakeServer(
          config: configured('userDeletionFlow', 'delete-user'),
          flows: [flow('delete-user', 'flow-1')],
          execution: execution,
        );

    test('calls the API directly by default, without reading the flow configuration', () async {
      final server = userDeletion();

      await clientFor(server).deleteUser('u-1');

      expect(server.calls, ['DELETE $baseUrl/users/u-1']);
    });

    test('runs the configured flow in flow mode instead of calling the API', () async {
      final server = userDeletion();

      await clientFor(server).deleteUser('u-1', administrationMode: AdministrationMode.flow);

      expect(server.calls, [
        'GET $baseUrl/server-config/flow',
        'GET $baseUrl/flows?flowType=ADMINISTRATION&limit=100&offset=0',
        'POST $baseUrl/flow/execute',
      ]);
      expect(server.executions, [
        {
          'flowId': 'flow-1',
          'inputs': {'subject': 'u-1'},
        },
      ]);
    });

    test('calls the API directly in flow mode when no flow is configured', () async {
      final server = FakeServer();

      await clientFor(server).deleteGroup('g-1', administrationMode: AdministrationMode.flow);

      expect(server.executions, isEmpty);
      expect(server.calls.last, 'DELETE $baseUrl/groups/g-1');
    });

    test('flow calls go to baseUrl, while the direct call keeps the collection override', () async {
      final server = FakeServer();
      final client = ThunderIDManagementClient(
        baseUrl: baseUrl,
        endpoints: const {ManagementEndpointKeys.groups: 'https://groups.example.com/groups'},
        fetcher: server.call,
      );

      await client.deleteGroup('g-1', administrationMode: AdministrationMode.flow);

      expect(server.calls, [
        'GET $baseUrl/server-config/flow',
        'DELETE https://groups.example.com/groups/g-1',
      ]);
    });

    test('refuses when the configured flow no longer exists, rather than skipping the revocation', () async {
      final server = FakeServer(config: configured('roleDeletionFlow', 'gone'));

      await expectLater(
        clientFor(server).deleteRole('r-1', administrationMode: AdministrationMode.flow),
        throwsA(
          isA<AdministrationFlowError>()
              .having((e) => e.flowCode, 'flowCode', 'resolveAdministrationFlowId-NotFoundError-001')
              .having((e) => e.code, 'code', ThunderIDErrorCode.administrationFlowFailed),
        ),
      );
      expect(server.firstWithMethod('DELETE'), isNull);
    });

    test("reports a refused step with the step's own code", () async {
      final server = FakeServer(
        config: configured('applicationDeletionFlow', 'delete-app'),
        execution: {
          'error': {
            'code': 'FLW-4001',
            'message': {'defaultValue': 'Not allowed'},
          },
          'flowStatus': 'ERROR',
        },
        flows: [flow('delete-app', 'flow-2')],
      );

      final error = await clientFor(server)
          .deleteApplication('app-1', administrationMode: AdministrationMode.flow)
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect(error, isA<AdministrationFlowError>());
      error as AdministrationFlowError;
      expect(error.flowCode, 'FLW-4001');
      expect(error.flowError.code, 'FLW-4001');
      expect(error.message, contains('Not allowed'));
      expect(server.executions.single, {
        'flowId': 'flow-2',
        'inputs': {'targetApplicationId': 'app-1'},
      });
      expect(server.firstWithMethod('DELETE'), isNull);
    });

    test('refuses a flow that asks for more input', () async {
      final server = userDeletion(execution: {'flowStatus': 'INCOMPLETE'});

      await expectLater(
        clientFor(server).deleteUser('u-1', administrationMode: AdministrationMode.flow),
        throwsA(
          isA<AdministrationFlowError>()
              .having((e) => e.flowCode, 'flowCode', 'executeAdministrationFlow-IncompleteError-001'),
        ),
      );
    });

    test('a failed flow without a step code gets the generic flow code', () async {
      final server = userDeletion(execution: {'flowStatus': 'ERROR'});

      await expectLater(
        clientFor(server).deleteUser('u-1', administrationMode: AdministrationMode.flow),
        throwsA(isA<AdministrationFlowError>().having((e) => e.flowCode, 'flowCode', 'executeAdministrationFlow-FlowError-001')),
      );
    });

    test('needs the server URL to run a flow', () async {
      final server = userDeletion();
      final client = ThunderIDManagementClient(
        baseUrl: '',
        endpoints: const {ManagementEndpointKeys.users: '$baseUrl/users'},
        fetcher: server.call,
      );

      await expectLater(
        client.deleteUser('u-1', administrationMode: AdministrationMode.flow),
        throwsA(
          isA<IAMException>()
              .having((e) => e.code, 'code', ThunderIDErrorCode.invalidConfiguration)
              .having((e) => e.message, 'message', startsWith('resolveAdministrationFlowHandles:')),
        ),
      );
      expect(server.requests, isEmpty);

      // The direct call still works from the collection URL alone.
      await client.deleteUser('u-1');
      expect(server.calls, ['DELETE $baseUrl/users/u-1']);
    });

    test('runs the removal flow once for each member, and for each assignee', () async {
      final server = FakeServer(
        config: {
          ...configured('groupMembershipRemovalFlow', 'remove-member'),
          ...configured('roleAssignmentRemovalFlow', 'remove-assignment'),
        },
        flows: [flow('remove-member', 'flow-m'), flow('remove-assignment', 'flow-a')],
        resource: {'id': 'g-1', 'name': 'Team', 'ouId': 'ou-1'},
      );
      final client = clientFor(server);

      final group = await client.removeGroupMembers(
        'g-1',
        const [
          GroupMember(id: 'u-1', type: GroupMemberType.user),
          GroupMember(id: 'u-2', type: GroupMemberType.user),
        ],
        administrationMode: AdministrationMode.flow,
      );
      await client.removeRoleAssignments(
        'r-1',
        const [RoleAssignment(id: 'g-1', type: RoleAssigneeType.group)],
        administrationMode: AdministrationMode.flow,
      );

      expect(group?.name, 'Team', reason: 'the group is read after the flows');
      expect(server.calls, contains('GET $baseUrl/groups/g-1?include=display'));
      expect(server.calls.where((call) => call.contains('/members/remove') || call.contains('/assignments/remove')), isEmpty);
      expect(server.executions, [
        {
          'flowId': 'flow-m',
          'inputs': {'targetGroupId': 'g-1', 'targetMemberId': 'u-1'},
        },
        {
          'flowId': 'flow-m',
          'inputs': {'targetGroupId': 'g-1', 'targetMemberId': 'u-2'},
        },
        {
          'flowId': 'flow-a',
          'inputs': {'targetAssigneeId': 'g-1', 'targetRoleId': 'r-1'},
        },
      ]);
    });

    test('walks the flow listing page by page until the handle is found', () async {
      final requests = <ManagementRequest>[];
      final client = ThunderIDManagementClient(
        baseUrl: baseUrl,
        fetcher: (request) async {
          requests.add(request);
          final firstPage = request.url.queryParameters['offset'] == '0';
          return json({
            'flows': firstPage
                ? [for (var i = 0; i < 100; i++) flow('flow-$i', 'id-$i')]
                : [flow('late', 'id-late')],
          });
        },
      );

      final found = await client.findAdministrationFlows(['late']);

      expect(found['late']?.id, 'id-late');
      expect(requests.map((r) => r.url.queryParameters['offset']), ['0', '100']);
      expect(requests.first.url.queryParameters, {'flowType': 'ADMINISTRATION', 'limit': '100', 'offset': '0'});
    });

    test('ignores flows of another type, and resolves several operations at once', () async {
      final server = FakeServer(
        config: {
          ...configured('userDeletionFlow', 'delete-user'),
          ...configured('roleDeletionFlow', 'not-admin'),
          'groupDeletionFlow': <String, Object?>{},
        },
        flows: [
          flow('delete-user', 'flow-1'),
          {'flowType': 'AUTHENTICATION', 'handle': 'not-admin', 'id': 'flow-x'},
        ],
      );

      final resolved = await clientFor(server).resolveAdministrationFlows(AdministrationFlowConfigKey.values);

      expect(resolved, {'userDeletionFlow': 'flow-1'});
      expect(server.calls.where((call) => call.startsWith('GET $baseUrl/flows')), hasLength(1));
    });
  });

  group('updateRole in flow mode', () {
    const role = Role(
      id: 'r-1',
      name: 'Viewer',
      ouId: 'ou-1',
      permissions: [
        RoleResourcePermissions(resourceServerId: 'rs-1', permissions: ['read', 'write']),
      ],
    );
    final roleJson = {
      'id': 'r-1',
      'name': 'Viewer',
      'ouId': 'ou-1',
      'permissions': [
        {
          'resourceServerId': 'rs-1',
          'permissions': ['read', 'write'],
        },
      ],
    };
    FakeServer server() => FakeServer(
          config: configured('rolePermissionRemovalFlow', 'remove-permission'),
          flows: [flow('remove-permission', 'flow-p')],
          resource: roleJson,
        );

    test('saves directly when no permission is removed', () async {
      final fake = server();

      await clientFor(fake).updateRole(
        'r-1',
        const UpdateRoleRequest(
          name: 'Viewer',
          ouId: 'ou-1',
          permissions: [
            RoleResourcePermissions(resourceServerId: 'rs-1', permissions: ['read', 'write', 'admin']),
          ],
        ),
        administrationMode: AdministrationMode.flow,
        current: role,
      );

      expect(fake.executions, isEmpty);
      expect(fake.calls, ['PUT $baseUrl/roles/r-1']);
    });

    test('runs the flow for a removed permission, after saving the other fields with the old permissions', () async {
      final fake = server();
      const permissions = [
        RoleResourcePermissions(resourceServerId: 'rs-1', permissions: ['read']),
      ];

      final updated = await clientFor(fake).updateRole(
        'r-1',
        const UpdateRoleRequest(name: 'Reader', ouId: 'ou-1', permissions: permissions),
        administrationMode: AdministrationMode.flow,
      );

      expect(fake.calls.first, 'GET $baseUrl/roles/r-1?include=display');
      expect(fake.bodyOf('PUT'), {'name': 'Reader', 'ouId': 'ou-1', 'permissions': roleJson['permissions']});
      final execution = fake.executions.single! as Map<String, dynamic>;
      expect(execution['flowId'], 'flow-p');
      final inputs = execution['inputs'] as Map<String, dynamic>;
      expect(inputs['targetRoleId'], 'r-1');
      expect(jsonDecode(inputs['targetPermissions'] as String), [
        {
          'resourceServerId': 'rs-1',
          'permissions': ['read'],
        },
      ]);
      expect(updated.permissions.single.permissions, ['read']);
    });

    test('skips the write when only permissions change', () async {
      final fake = server();

      await clientFor(fake).updateRole(
        'r-1',
        const UpdateRoleRequest(name: 'Viewer', ouId: 'ou-1'),
        administrationMode: AdministrationMode.flow,
        current: role,
      );

      expect(fake.firstWithMethod('PUT'), isNull);
      expect(fake.executions, hasLength(1));
    });

    test('saves directly when no permission removal flow is configured', () async {
      final fake = FakeServer(resource: roleJson);

      await clientFor(fake).updateRole(
        'r-1',
        const UpdateRoleRequest(name: 'Viewer', ouId: 'ou-1'),
        administrationMode: AdministrationMode.flow,
        current: role,
      );

      expect(fake.executions, isEmpty);
      expect(fake.bodyOf('PUT'), {'name': 'Viewer', 'ouId': 'ou-1', 'permissions': <Object?>[]});
    });
  });

  group('secret regeneration', () {
    final application = {
      'createdAt': 'yesterday',
      'id': 'app-1',
      'inboundAuthConfig': [
        {
          'config': {'clientId': 'client', 'clientSecret': 'old'},
          'type': 'oauth2',
        },
      ],
      'name': 'Shop',
      'futureField': 'kept',
    };
    final secretPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

    test('returns the secret a regeneration flow produced', () async {
      final server = FakeServer(
        config: configured('secretRegenerationFlow', 'rotate'),
        execution: {
          'data': {
            'additionalData': {'clientSecret': 'from-flow'},
          },
          'flowStatus': 'COMPLETE',
        },
        flows: [flow('rotate', 'flow-s')],
      );

      final result = await clientFor(server).regenerateClientSecret('app-1', administrationMode: AdministrationMode.flow);

      expect(result.clientSecret, 'from-flow');
      expect(result.application, isNull);
      expect(server.firstWithMethod('PUT'), isNull);
    });

    test('refuses a regeneration flow that returns no secret', () async {
      final server = FakeServer(
        config: configured('secretRegenerationFlow', 'rotate'),
        flows: [flow('rotate', 'flow-s')],
      );

      await expectLater(
        clientFor(server).regenerateClientSecret('app-1', administrationMode: AdministrationMode.flow),
        throwsA(isA<AdministrationFlowError>().having((e) => e.flowCode, 'flowCode', 'regenerateClientSecret-FlowError-001')),
      );
    });

    test('otherwise saves a newly generated client secret on the application', () async {
      final server = FakeServer(resource: application);

      final result = await clientFor(server).regenerateClientSecret('app-1');

      expect(result.clientSecret, matches(secretPattern));
      expect(server.calls, ['GET $baseUrl/applications/app-1', 'PUT $baseUrl/applications/app-1']);
      expect(server.bodyOf('PUT'), {
        'inboundAuthConfig': [
          {
            'config': {'clientId': 'client', 'clientSecret': result.clientSecret},
            'type': 'oauth2',
          },
        ],
        'name': 'Shop',
        'futureField': 'kept',
      });
      expect(result.application?.name, 'Shop');
      expect(result.application?.oauth2Config?.clientId, 'client');
    });

    test('refuses to regenerate a client secret for an application without an OAuth client', () async {
      final server = FakeServer(resource: {'id': 'app-1', 'inboundAuthConfig': <Object?>[], 'name': 'Shop'});

      await expectLater(
        clientFor(server).regenerateClientSecret('app-1'),
        throwsA(
          isA<IAMException>()
              .having((e) => e.code, 'code', ThunderIDErrorCode.invalidInput)
              .having((e) => e.message, 'message', startsWith('regenerateClientSecret:')),
        ),
      );
      expect(server.firstWithMethod('PUT'), isNull);
    });

    test('saves a newly generated flow secret on the application', () async {
      final server = FakeServer(resource: application);

      final result = await clientFor(server).regenerateFlowSecret('app-1');

      final put = server.bodyOf('PUT')! as Map<String, dynamic>;
      expect(result.flowSecret, matches(secretPattern));
      expect(put['flowSecret'], result.flowSecret);
      expect(put['name'], 'Shop');
      expect(put.containsKey('id'), isFalse);
      expect(put.containsKey('createdAt'), isFalse);
    });

    test('generates a different secret each time', () async {
      final server = FakeServer(resource: application);
      final client = clientFor(server);

      final first = await client.regenerateFlowSecret('app-1');
      final second = await client.regenerateFlowSecret('app-1');

      expect(first.flowSecret, isNot(second.flowSecret));
    });

    test("saves a newly generated secret on the agent's OAuth client", () async {
      final server = FakeServer(
        resource: {
          'clientId': 'client',
          'id': 'a-1',
          'inboundAuthConfig': [
            {
              'config': {
                'grantTypes': ['client_credentials'],
              },
              'type': 'oauth2',
            },
          ],
          'name': 'Bot',
          'ouHandle': 'default',
          'ouId': 'ou-1',
          'type': 'bot',
        },
      );

      final result = await clientFor(server).regenerateAgentSecret('a-1');

      expect(result.clientSecret, matches(secretPattern));
      expect(server.calls, ['GET $baseUrl/agents/a-1?include=display', 'PUT $baseUrl/agents/a-1']);
      // The display-only organization unit handle and the server-set fields stay out of the update.
      expect(server.bodyOf('PUT'), {
        'delegated': false,
        'inboundAuthConfig': [
          {
            'config': {
              'clientSecret': result.clientSecret,
              'grantTypes': ['client_credentials'],
            },
            'type': 'oauth2',
          },
        ],
        'name': 'Bot',
        'ouId': 'ou-1',
        'type': 'bot',
      });
      expect(result.agent.name, 'Bot');
    });

    // The server does not store the delegated flag, so the update restates it from the grant types.
    for (final grantType in [
      'authorization_code',
      'urn:openid:params:grant-type:ciba',
      'urn:ietf:params:oauth:grant-type:token-exchange',
    ]) {
      test('keeps an agent with $grantType held to the delegated grant rules', () async {
        final server = FakeServer(
          resource: {
            'id': 'a-1',
            'inboundAuthConfig': [
              {
                'config': {
                  'grantTypes': [grantType, 'refresh_token'],
                },
                'type': 'oauth2',
              },
            ],
            'name': 'Assistant',
            'ouId': 'ou-1',
            'type': 'bot',
          },
        );

        await clientFor(server).regenerateAgentSecret('a-1');

        expect((server.bodyOf('PUT')! as Map<String, dynamic>)['delegated'], isTrue);
      });
    }

    test('refuses to regenerate the secret of an agent with no OAuth client', () async {
      final server = FakeServer(resource: {'id': 'a-1', 'name': 'Bot', 'ouId': 'ou-1', 'type': 'bot'});

      await expectLater(
        clientFor(server).regenerateAgentSecret('a-1'),
        throwsA(
          isA<IAMException>()
              .having((e) => e.code, 'code', ThunderIDErrorCode.invalidInput)
              .having((e) => e.message, 'message', startsWith('regenerateAgentSecret:')),
        ),
      );
      expect(server.firstWithMethod('PUT'), isNull);
    });

    test('UpdateAgentRequest sends delegated only when set', () {
      expect(const UpdateAgentRequest(name: 'Bot').toJson(), {'name': 'Bot'});
      expect(const UpdateAgentRequest(delegated: true).toJson(), {'delegated': true});
    });
  });
}
