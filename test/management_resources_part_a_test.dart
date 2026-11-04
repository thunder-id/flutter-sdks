// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

const baseUrl = 'https://localhost:8090';

/// Answers every request with [body] and records it.
class _Server {
  final Object? body;
  final int status;
  final List<ManagementRequest> requests = [];

  _Server({this.body = const <String, Object?>{}, this.status = 200});

  Future<ManagementResponse> call(ManagementRequest request) async {
    requests.add(request);
    return ManagementResponse(statusCode: status, statusText: 'x', body: body == null ? '' : jsonEncode(body));
  }

  List<String> get calls => [for (final r in requests) '${r.method} ${r.url}'];
}

typedef _Case = (Future<Object?> Function(ThunderIDManagementClient), String, String, Object?);

void main() {
  void runCases(Map<String, _Case> cases) {
    cases.forEach((name, entry) {
      final (run, method, path, body) = entry;
      test('$name sends $method $path', () async {
        final server = _Server();
        await run(ThunderIDManagementClient(baseUrl: baseUrl, fetcher: server.call));
        expect(server.calls, ['$method $baseUrl$path']);
        final sent = server.requests.single.body;
        expect(sent == null ? null : jsonDecode(sent), body);
      });
    });
  }

  group('role and flow sharing', () {
    runCases({
      'getRoleSharingPolicies': (
        (c) => c.getRoleSharingPolicies('r-1', limit: 5, offset: 10),
        'GET',
        '/roles/r-1/sharing-policies?limit=5&offset=10',
        null,
      ),
      'createRoleSharingPolicy': (
        (c) => c.createRoleSharingPolicy('r-1', const CreateSharingPolicyRequest(childUnits: {'mode': 'all'})),
        'POST',
        '/roles/r-1/sharing-policies',
        {
          'childUnits': {'mode': 'all'},
        },
      ),
      'getRoleSharingPolicy': ((c) => c.getRoleSharingPolicy('r-1', 'p-1'), 'GET', '/roles/r-1/sharing-policies/p-1', null),
      'updateRoleSharingPolicy': (
        (c) => c.updateRoleSharingPolicy('r-1', 'p-1', const UpdateSharingPolicyRequest(version: 2)),
        'PUT',
        '/roles/r-1/sharing-policies/p-1',
        {'version': 2},
      ),
      'deleteRoleSharingPolicy': (
        (c) => c.deleteRoleSharingPolicy('r-1', 'p-1'),
        'DELETE',
        '/roles/r-1/sharing-policies/p-1',
        null,
      ),
      'getRoleOverlayRules': (
        (c) => c.getRoleOverlayRules('r-1', ouId: 'ou-2'),
        'GET',
        '/roles/r-1/overlay-rules?ouId=ou-2',
        null,
      ),
      'getFlowSharingPolicies': ((c) => c.getFlowSharingPolicies('f-1'), 'GET', '/flows/f-1/sharing-policies', null),
      'createFlowSharingPolicy': (
        (c) => c.createFlowSharingPolicy('f-1', const CreateSharingPolicyRequest(initiatingOuId: 'ou-1')),
        'POST',
        '/flows/f-1/sharing-policies',
        {'initiatingOuId': 'ou-1'},
      ),
      'getFlowSharingPolicy': ((c) => c.getFlowSharingPolicy('f-1', 'p-1'), 'GET', '/flows/f-1/sharing-policies/p-1', null),
      'updateFlowSharingPolicy': (
        (c) => c.updateFlowSharingPolicy(
              'f-1',
              'p-1',
              const UpdateSharingPolicyRequest(version: 3, childUnits: {'mode': 'all'}),
            ),
        'PUT',
        '/flows/f-1/sharing-policies/p-1',
        {
          'version': 3,
          'childUnits': {'mode': 'all'},
        },
      ),
      'deleteFlowSharingPolicy': (
        (c) => c.deleteFlowSharingPolicy('f-1', 'p-1'),
        'DELETE',
        '/flows/f-1/sharing-policies/p-1',
        null,
      ),
      'getFlowOverlayRules': (
        (c) => c.getFlowOverlayRules('f-1', ouId: 'ou-2'),
        'GET',
        '/flows/f-1/overlay-rules?ouId=ou-2',
        null,
      ),
    });

    test('the roles and flows endpoint overrides apply', () async {
      final server = _Server();
      final client = ThunderIDManagementClient(
        baseUrl: baseUrl,
        endpoints: const {'roles': 'https://roles.example.com/r', 'flows': 'https://flows.example.com/f'},
        fetcher: server.call,
      );
      await client.getRoleSharingPolicies('r 1');
      await client.getFlowOverlayRules('f/1', ouId: 'ou-1');
      expect(server.calls, [
        'GET https://roles.example.com/r/r%201/sharing-policies',
        'GET https://flows.example.com/f/f%2F1/overlay-rules?ouId=ou-1',
      ]);
    });

    test('an overlay reads the role and flow ownership fields', () {
      expect(ResolvedOverlay.fromJson({'isOwnedByOU': true}).isOwned, isTrue);
      expect(ResolvedOverlay.fromJson({'owned': false}).isOwned, isFalse);
      final flow = ResolvedOverlay.fromJson({
        'ouId': 'ou-2',
        'owned': false,
        'visible': true,
        'policyIds': ['p-1'],
        'rules': {
          'variables.mfaMode': {
            'editable': false,
            'value': ['SMS_OTP'],
          },
        },
      });
      expect(flow.rules['variables.mfaMode']?.value, ['SMS_OTP']);
    });
  });

  group('flow variables', () {
    runCases({
      'getFlowVariables': (
        (c) => c.getFlowVariables('f-1', ouId: 'ou-2'),
        'GET',
        '/flows/f-1/variables?ouId=ou-2',
        null,
      ),
      'updateFlowVariables': (
        (c) => c.updateFlowVariables('f-1', {'supportEmail': 'help@acme.example', 'otp': 120, 'social': true}, ouId: 'ou-2'),
        'PUT',
        '/flows/f-1/variables',
        {
          'ouId': 'ou-2',
          'values': {'supportEmail': 'help@acme.example', 'otp': 120, 'social': true},
        },
      ),
    });

    test('parses the values and keeps only strings, numbers and booleans', () async {
      final server = _Server(
        body: {
          'values': {'a': 'x', 'b': 2, 'c': false, 'd': null, 'e': <Object?>[]},
        },
      );
      final result = await ThunderIDManagementClient(baseUrl: baseUrl, fetcher: server.call).getFlowVariables(
        'f-1',
        ouId: 'ou-1',
      );
      expect(result.values, {'a': 'x', 'b': 2, 'c': false});
    });

    test('refuses a blank organization unit or a value of another type before sending', () async {
      final server = _Server();
      final client = ThunderIDManagementClient(baseUrl: baseUrl, fetcher: server.call);
      await expectLater(
        client.getFlowVariables('f-1', ouId: ' '),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.invalidInput)),
      );
      await expectLater(
        client.updateFlowVariables('f-1', {'a': <String>[]}, ouId: 'ou-1'),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.invalidInput)),
      );
      expect(server.requests, isEmpty);
    });
  });

  group('groups by path', () {
    runCases({
      'getGroupsByPath': (
        (c) => c.getGroupsByPath('/eng/front end/', limit: 2, offset: 4),
        'GET',
        '/groups/tree/eng/front%20end?include=display&limit=2&offset=4',
        null,
      ),
      'createGroupByPath': (
        (c) => c.createGroupByPath(
              'eng/platform',
              const CreateGroupByPathRequest(
                name: 'Sports',
                description: 'Sports group',
                members: [GroupMember(id: 'u-1', type: GroupMemberType.user)],
              ),
            ),
        'POST',
        '/groups/tree/eng/platform',
        {
          'name': 'Sports',
          'description': 'Sports group',
          'members': [
            {'id': 'u-1', 'type': 'user'},
          ],
        },
      ),
    });

    test('encodes each handle on its own and refuses an empty one', () async {
      final server = _Server(body: {'totalResults': 1, 'groups': [{'id': 'g-1', 'name': 'Team', 'ouId': 'ou-1'}]});
      final client = ThunderIDManagementClient(baseUrl: baseUrl, fetcher: server.call);
      final page = await client.getGroupsByPath('a?b/c#d');
      expect(page.items.single.name, 'Team');
      expect(server.calls.single, 'GET $baseUrl/groups/tree/a%3Fb/c%23d?include=display');
      await expectLater(
        client.createGroupByPath('a//b', const CreateGroupByPathRequest(name: 'x')),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.invalidInput)),
      );
    });
  });

  group('projects', () {
    runCases({
      'getProjects': ((c) => c.getProjects(limit: 10, offset: 20), 'GET', '/projects?limit=10&offset=20', null),
      'getProject': ((c) => c.getProject('p-1'), 'GET', '/projects/p-1', null),
      'createProject': (
        (c) => c.createProject(const CreateProjectRequest(handle: 'retail', displayName: 'Retail', description: 'Shops')),
        'POST',
        '/projects',
        {'handle': 'retail', 'displayName': 'Retail', 'description': 'Shops'},
      ),
      'updateProject': (
        (c) => c.updateProject('p-1', const UpdateProjectRequest(displayName: 'Retail EU')),
        'PUT',
        '/projects/p-1',
        {'displayName': 'Retail EU'},
      ),
      'deleteProject': ((c) => c.deleteProject('p-1'), 'DELETE', '/projects/p-1', null),
    });

    test('parses a page of projects and honours the projects override', () async {
      final server = _Server(
        body: {
          'totalResults': 1,
          'startIndex': 1,
          'count': 1,
          'projects': [
            {'id': 'p-1', 'handle': 'retail', 'displayName': 'Retail', 'createdAt': '2026-10-23T10:15:00Z'},
          ],
        },
      );
      final client = ThunderIDManagementClient(
        baseUrl: baseUrl,
        endpoints: const {ManagementEndpointKeys.projects: 'https://p.example.com/projects'},
        fetcher: server.call,
      );
      final page = await client.getProjects();
      expect(page.items.single.handle, 'retail');
      expect(page.items.single.createdAt, '2026-10-23T10:15:00Z');
      expect(server.calls.single, 'GET https://p.example.com/projects');
    });
  });

  group('authorization detail types', () {
    const payload = AuthorizationDetailTypeRequest(
      type: 'payment_initiation',
      name: 'Payment initiation',
      schema: {'type': 'object'},
      consentTemplate: 'Pay {{amount}}',
      processor: AuthorizationDetailProcessor(
        endpoint: 'https://api.bank.example/rar',
        authentication: ProcessorAuthentication(type: 'bearer', properties: {'token': 't'}),
      ),
      reuse: false,
    );
    const body = {
      'type': 'payment_initiation',
      'name': 'Payment initiation',
      'schema': {'type': 'object'},
      'consentTemplate': 'Pay {{amount}}',
      'processor': {
        'endpoint': 'https://api.bank.example/rar',
        'authentication': {
          'type': 'bearer',
          'properties': {'token': 't'},
        },
      },
      'reuse': false,
    };
    runCases({
      'getAuthorizationDetailTypes': (
        (c) => c.getAuthorizationDetailTypes(limit: 5),
        'GET',
        '/authorization-detail-types?limit=5',
        null,
      ),
      'getAuthorizationDetailType': (
        (c) => c.getAuthorizationDetailType('t-1'),
        'GET',
        '/authorization-detail-types/t-1',
        null,
      ),
      'createAuthorizationDetailType': (
        (c) => c.createAuthorizationDetailType(payload),
        'POST',
        '/authorization-detail-types',
        body,
      ),
      'updateAuthorizationDetailType': (
        (c) => c.updateAuthorizationDetailType('t-1', payload),
        'PUT',
        '/authorization-detail-types/t-1',
        body,
      ),
      'deleteAuthorizationDetailType': (
        (c) => c.deleteAuthorizationDetailType('t-1'),
        'DELETE',
        '/authorization-detail-types/t-1',
        null,
      ),
    });

    test('parses a page of types', () async {
      final server = _Server(
        body: {
          'totalResults': 1,
          'types': [
            {
              'id': 't-1',
              'type': 'payment_initiation',
              'name': 'Payment initiation',
              'version': 2,
              'schema': {'type': 'object'},
              'reuse': true,
              'isReadOnly': true,
              'processor': {
                'endpoint': 'https://api.bank.example/rar',
                'authentication': {
                  'type': 'bearer',
                  'properties': {'token': '******'},
                },
              },
            },
          ],
        },
      );
      final page = await ThunderIDManagementClient(baseUrl: baseUrl, fetcher: server.call).getAuthorizationDetailTypes();
      final type = page.items.single;
      expect(type.version, 2);
      expect(type.reuse, isTrue);
      expect(type.isReadOnly, isTrue);
      expect(type.processor?.authentication?.properties['token'], '******');
    });

    test('a 403 and a 404 keep distinct codes', () async {
      for (final (status, code) in [(403, ThunderIDErrorCode.forbidden), (404, ThunderIDErrorCode.notFound)]) {
        final client = ThunderIDManagementClient(baseUrl: baseUrl, fetcher: _Server(status: status, body: null).call);
        await expectLater(
          client.getAuthorizationDetailType('t-1'),
          throwsA(isA<IAMApiException>().having((e) => e.code, 'code', code)),
        );
      }
    });
  });

  group('supported authorization details types', () {
    const metadata = {
      'type': 'https://bank.example/payment',
      'name': 'Payment',
      'version': 3,
      'schema': {'type': 'object'},
      'modifications': [
        {'field': 'amount', 'modification': 'decrease'},
      ],
    };

    test('lists the public types without an access token', () async {
      final server = _Server(
        body: {
          'types': [metadata],
        },
      );
      final types = await getSupportedAuthorizationDetailsTypes(baseUrl: '$baseUrl/', fetcher: server.call);
      expect(server.calls, ['GET $baseUrl/oauth2/authorization-details-types']);
      expect(server.requests.single.headers.keys, isNot(contains('Authorization')));
      expect(types.single.version, 3);
      expect(types.single.modifications.single.modification, 'decrease');
    });

    test('reads one type, encoding a URI type value as one segment', () async {
      final server = _Server(body: metadata);
      final type = await getSupportedAuthorizationDetailsType(
        'https://bank.example/payment',
        baseUrl: baseUrl,
        fetcher: server.call,
      );
      expect(server.calls, ['GET $baseUrl/oauth2/authorization-details-types/https:%2F%2Fbank.example%2Fpayment']);
      expect(type.name, 'Payment');
    });

    test('an unknown type raises notFound, and a non-HTTPS URL is refused', () async {
      await expectLater(
        getSupportedAuthorizationDetailsType('x', baseUrl: baseUrl, fetcher: _Server(status: 404, body: null).call),
        throwsA(isA<IAMApiException>().having((e) => e.code, 'code', ThunderIDErrorCode.notFound)),
      );
      await expectLater(
        getSupportedAuthorizationDetailsTypes(baseUrl: 'http://idp.example.com', fetcher: _Server().call),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.invalidConfiguration)),
      );
    });
  });
}
