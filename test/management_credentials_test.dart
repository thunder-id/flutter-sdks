// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

// Credential configurations (OpenID4VCI), presentation definitions (OpenID4VP), dynamic client
// registration (RFC 7591 / 7592), and the gateway master.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

const baseUrl = 'https://localhost:8090';

/// Records every request and answers each with [status] and [body].
class Recorder {
  final int status;
  final Object? body;
  final List<ManagementRequest> requests = [];

  Recorder({this.status = 200, this.body = const <String, Object?>{}});

  Future<ManagementResponse> call(ManagementRequest request) async {
    requests.add(request);
    return ManagementResponse(
      statusCode: status,
      statusText: 'x',
      body: body is String ? body! as String : jsonEncode(body),
    );
  }

  List<String> get calls => [for (final r in requests) '${r.method} ${r.url}'];

  Object? get sentBody {
    final sent = requests.single.body;
    return sent == null ? null : jsonDecode(sent);
  }
}

typedef Case = (Future<Object?> Function(ThunderIDManagementClient), String, String, Object?);

ThunderIDManagementClient clientFor(Recorder recorder, {Map<String, String> endpoints = const {}}) =>
    ThunderIDManagementClient(baseUrl: baseUrl, endpoints: endpoints, fetcher: recorder.call);

void runCases(Map<String, Case> cases) {
  cases.forEach((name, entry) {
    final (run, method, path, body) = entry;
    test('$name sends $method $path', () async {
      final recorder = Recorder();

      await run(clientFor(recorder));

      expect(recorder.calls, ['$method $baseUrl$path']);
      expect(recorder.sentBody, body);
    });
  });
}

void main() {
  group('credential configurations', () {
    const payload = CredentialConfigurationRequest(
      handle: 'pid',
      ouId: 'ou-1',
      vct: 'urn:example:pid:1',
      format: CredentialFormats.sdJwt,
      claims: [CredentialClaimMapping(name: 'given_name', displayName: 'Given name')],
      display: CredentialDisplay(locale: 'en', logoUri: 'https://e/logo.png'),
      validitySeconds: 3600,
    );
    const payloadJson = {
      'handle': 'pid',
      'ouId': 'ou-1',
      'vct': 'urn:example:pid:1',
      'format': 'dc+sd-jwt',
      'claims': [
        {'name': 'given_name', 'displayName': 'Given name'},
      ],
      'display': {'locale': 'en', 'logoUri': 'https://e/logo.png'},
      'validitySeconds': 3600,
    };

    runCases({
      'getCredentialConfigurations': (
        (c) => c.getCredentialConfigurations(),
        'GET',
        '/openid4vci/credential-configurations',
        null,
      ),
      'getCredentialConfiguration': (
        (c) => c.getCredentialConfiguration('cc 1'),
        'GET',
        '/openid4vci/credential-configurations/cc%201',
        null,
      ),
      'createCredentialConfiguration': (
        (c) => c.createCredentialConfiguration(payload),
        'POST',
        '/openid4vci/credential-configurations',
        payloadJson,
      ),
      'updateCredentialConfiguration': (
        (c) => c.updateCredentialConfiguration('cc-1', payload),
        'PUT',
        '/openid4vci/credential-configurations/cc-1',
        payloadJson,
      ),
      'deleteCredentialConfiguration': (
        (c) => c.deleteCredentialConfiguration('cc-1'),
        'DELETE',
        '/openid4vci/credential-configurations/cc-1',
        null,
      ),
    });

    test('parses a listing and a single configuration', () async {
      final list = await clientFor(
        Recorder(
          body: [
            {'id': 'cc-1', 'handle': 'pid', 'ouId': 'ou-1', 'ouHandle': 'root', 'format': 'dc+sd-jwt', 'vct': 'v'},
          ],
        ),
      ).getCredentialConfigurations();
      expect(list.single.ouHandle, 'root');
      expect(list.single.claims, isEmpty);

      final single = await clientFor(
        Recorder(
          body: {
            ...payloadJson,
            'id': 'cc-1',
            'ouHandle': 'root',
          },
        ),
      ).getCredentialConfiguration('cc-1');
      expect(single.id, 'cc-1');
      expect(single.format, CredentialFormats.sdJwt);
      expect(single.claims.single.displayName, 'Given name');
      expect(single.display?.logoUri, 'https://e/logo.png');
      expect(single.validitySeconds, 3600);
    });

    test('follows its endpoint override', () async {
      final recorder = Recorder();
      await clientFor(
        recorder,
        endpoints: const {ManagementEndpointKeys.credentialConfigurations: 'https://vc.example.com/configs'},
      ).getCredentialConfiguration('cc-1');
      expect(recorder.calls, ['GET https://vc.example.com/configs/cc-1']);
    });
  });

  group('presentation definitions', () {
    const payload = PresentationDefinitionRequest(
      handle: 'age',
      ouId: 'ou-1',
      vct: 'urn:example:pid:1',
      mandatoryClaims: ['birthdate'],
      optionalClaims: ['given_name'],
      claimValues: {
        'nationality': ['LK'],
      },
      enforceTrustedIssuer: true,
      trustedAuthorities: ['https://issuer.example.com'],
    );
    const payloadJson = {
      'handle': 'age',
      'ouId': 'ou-1',
      'vct': 'urn:example:pid:1',
      'mandatoryClaims': ['birthdate'],
      'optionalClaims': ['given_name'],
      'claimValues': {
        'nationality': ['LK'],
      },
      'enforceTrustedIssuer': true,
      'trustedAuthorities': ['https://issuer.example.com'],
    };

    runCases({
      'getPresentationDefinitions': (
        (c) => c.getPresentationDefinitions(),
        'GET',
        '/openid4vp/presentation-definitions',
        null,
      ),
      'getPresentationDefinition': (
        (c) => c.getPresentationDefinition('pd-1'),
        'GET',
        '/openid4vp/presentation-definitions/pd-1',
        null,
      ),
      'createPresentationDefinition': (
        (c) => c.createPresentationDefinition(payload),
        'POST',
        '/openid4vp/presentation-definitions',
        payloadJson,
      ),
      'updatePresentationDefinition': (
        (c) => c.updatePresentationDefinition('pd-1', payload),
        'PUT',
        '/openid4vp/presentation-definitions/pd-1',
        payloadJson,
      ),
      'deletePresentationDefinition': (
        (c) => c.deletePresentationDefinition('pd-1'),
        'DELETE',
        '/openid4vp/presentation-definitions/pd-1',
        null,
      ),
    });

    test('parses a definition', () async {
      final definition = await clientFor(
        Recorder(body: {...payloadJson, 'id': 'pd-1', 'format': 'dc+sd-jwt', 'ouHandle': 'root'}),
      ).getPresentationDefinition('pd-1');
      expect(definition.id, 'pd-1');
      expect(definition.mandatoryClaims, ['birthdate']);
      expect(definition.claimValues, {
        'nationality': ['LK'],
      });
      expect(definition.enforceTrustedIssuer, isTrue);
      expect(definition.trustedAuthorities, ['https://issuer.example.com']);
      expect(definition.requestedClaims, isEmpty);
    });

    test('follows its endpoint override', () async {
      final recorder = Recorder(body: const <Object?>[]);
      await clientFor(
        recorder,
        endpoints: const {ManagementEndpointKeys.presentationDefinitions: 'https://vp.example.com/defs'},
      ).getPresentationDefinitions();
      expect(recorder.calls, ['GET https://vp.example.com/defs']);
    });
  });

  group('client registrations', () {
    const request = ClientRegistrationRequest(
      redirectUris: ['https://app.example.com/cb'],
      ouId: 'ou-1',
      clientName: 'My App',
      grantTypes: [OAuth2GrantTypes.authorizationCode],
      responseTypes: ['code'],
      tokenEndpointAuthMethod: 'client_secret_basic',
      scope: 'openid profile',
      requirePushedAuthorizationRequests: true,
      idTokenSignedResponseAlg: 'RS256',
      additionalFields: {'client_name#fr': 'Mon App'},
    );
    const requestJson = {
      'client_name#fr': 'Mon App',
      'redirect_uris': ['https://app.example.com/cb'],
      'ou_id': 'ou-1',
      'client_name': 'My App',
      'grant_types': ['authorization_code'],
      'response_types': ['code'],
      'token_endpoint_auth_method': 'client_secret_basic',
      'scope': 'openid profile',
      'require_pushed_authorization_requests': true,
      'id_token_signed_response_alg': 'RS256',
    };
    const update = UpdateClientRegistrationRequest(
      redirectUris: ['https://app.example.com/cb2'],
      clientName: 'Renamed',
      clientSecret: 'hunter2',
    );

    runCases({
      'registerClient': ((c) => c.registerClient(request), 'POST', '/oauth2/dcr/register', requestJson),
      'getClientRegistration': (
        (c) => c.getClientRegistration('s6Bh/dRk'),
        'GET',
        '/oauth2/dcr/register/s6Bh%2FdRk',
        null,
      ),
      'updateClientRegistration': (
        (c) => c.updateClientRegistration('s6BhdRk', update),
        'PUT',
        '/oauth2/dcr/register/s6BhdRk',
        {
          'redirect_uris': ['https://app.example.com/cb2'],
          'client_name': 'Renamed',
          'client_secret': 'hunter2',
          'client_id': 's6BhdRk',
        },
      ),
      'deleteClientRegistration': (
        (c) => c.deleteClientRegistration('s6BhdRk'),
        'DELETE',
        '/oauth2/dcr/register/s6BhdRk',
        null,
      ),
    });

    test('the path client id wins over one in the payload', () async {
      final recorder = Recorder();
      await clientFor(recorder).updateClientRegistration(
        'right',
        const UpdateClientRegistrationRequest(redirectUris: ['https://a/cb'], additionalFields: {'client_id': 'wrong'}),
      );
      expect((recorder.sentBody! as Map)['client_id'], 'right');
    });

    test('maps a registration from snake_case, keeping unmodeled metadata', () async {
      final registration = await clientFor(
        Recorder(
          status: 201,
          body: {
            'client_id': 's6BhdRk',
            'client_secret': 'ZJYCqe3GGRvdrudKyZS0XhGv',
            'client_secret_expires_at': 0,
            'app_id': 'app-1',
            'client_name': 'My App',
            'client_name#fr': 'Mon App',
            'redirect_uris': ['https://app.example.com/cb'],
            'post_logout_redirect_uris': ['https://app.example.com/out'],
            'grant_types': ['authorization_code', 'refresh_token'],
            'token_endpoint_auth_method': 'client_secret_basic',
            'jwks': {'keys': <Object?>[]},
            'require_pushed_authorization_requests': false,
          },
        ),
      ).registerClient(request);

      expect(registration.clientId, 's6BhdRk');
      expect(registration.clientSecret, 'ZJYCqe3GGRvdrudKyZS0XhGv');
      expect(registration.clientSecretExpiresAt, 0);
      expect(registration.appId, 'app-1');
      expect(registration.clientName, 'My App');
      expect(registration.redirectUris, ['https://app.example.com/cb']);
      expect(registration.postLogoutRedirectUris, ['https://app.example.com/out']);
      expect(registration.grantTypes, ['authorization_code', 'refresh_token']);
      expect(registration.tokenEndpointAuthMethod, 'client_secret_basic');
      expect(registration.jwks, {'keys': <Object?>[]});
      expect(registration.requirePushedAuthorizationRequests, isFalse);
      expect(registration.additionalFields, {'client_name#fr': 'Mon App'});
    });

    test('never prints the client secret', () {
      const registration = ClientRegistration(clientId: 'c-1', clientSecret: 'hunter2', clientName: 'App');
      expect(registration.toString(), isNot(contains('hunter2')));
      expect(registration.toString(), contains('c-1'));
      expect(update.toString(), isNot(contains('hunter2')));
    });

    test('a read without a secret leaves it null', () async {
      final registration = await clientFor(
        Recorder(body: {'client_id': 'c-1', 'client_secret_expires_at': 0}),
      ).getClientRegistration('c-1');
      expect(registration.clientSecret, isNull);
    });

    test('follows its endpoint override', () async {
      final recorder = Recorder();
      await clientFor(
        recorder,
        endpoints: const {ManagementEndpointKeys.clientRegistrations: 'https://dcr.example.com/register'},
      ).deleteClientRegistration('c-1');
      expect(recorder.calls, ['DELETE https://dcr.example.com/register/c-1']);
    });

    test('maps an OAuth error into the management error, keeping statuses distinct', () async {
      Future<IAMApiException> failure(int status) async {
        try {
          await clientFor(
            Recorder(
              status: status,
              body: {'error': 'invalid_client_metadata', 'error_description': 'redirect_uris is required'},
            ),
          ).getClientRegistration('c-1');
        } on IAMApiException catch (error) {
          return error;
        }
        fail('expected an IAMApiException');
      }

      final invalid = await failure(400);
      expect(invalid.code, ThunderIDErrorCode.invalidInput);
      expect(invalid.operation, 'getClientRegistration');
      expect(invalid.serverError?.code, 'invalid_client_metadata');
      expect(invalid.serverError?.message?.defaultValue, 'redirect_uris is required');
      expect(invalid.message, isNot(contains('redirect_uris is required')));

      expect((await failure(401)).code, ThunderIDErrorCode.sessionExpired);
      expect((await failure(403)).code, ThunderIDErrorCode.forbidden);
      expect((await failure(404)).code, ThunderIDErrorCode.notFound);
    });

    test('an OAuth error without a description has no message', () {
      final error = ServerError.tryParse('{"error":"invalid_token"}');
      expect(error?.code, 'invalid_token');
      expect(error?.message, isNull);
      expect(ServerError.tryParse('{"error":1}'), isNull);
    });
  });

  group('gateway master', () {
    runCases({
      'getGatewayMaster': ((c) => c.getGatewayMaster('g-1'), 'GET', '/gateways/g-1/master', null),
      'getGatewayMasterHistory': (
        (c) => c.getGatewayMasterHistory('g-1'),
        'GET',
        '/gateways/g-1/master/history',
        null,
      ),
      'getGatewayMasterResource': (
        (c) => c.getGatewayMasterResource('g 1', 'application', 'app/1'),
        'GET',
        '/gateways/g%201/master/resources/application/app%2F1',
        null,
      ),
    });

    test('follows the gateways override', () async {
      final recorder = Recorder();
      await clientFor(
        recorder,
        endpoints: const {ManagementEndpointKeys.gateways: 'https://gw.example.com/gateways'},
      ).getGatewayMaster('g-1');
      expect(recorder.calls, ['GET https://gw.example.com/gateways/g-1/master']);
    });

    test('parses a master, its history and a resource history', () async {
      final entry = {
        'key': 'application/app-1',
        'resourceType': 'application',
        'id': 'app-1',
        'name': 'Shop',
        'contentHash': 'sha',
        'sourceVersion': 'abc1234',
        'origin': 'console',
        'state': 'failed',
        'failure': {'code': 'GW-1', 'message': 'Refused', 'description': 'bad field'},
        'at': '2026-01-01T00:00:00Z',
        'by': {'id': 'u-1', 'name': 'Ada'},
      };

      final master = await clientFor(
        Recorder(
          body: {
            'gatewayId': 'g-1',
            'number': 3,
            'master': 'm-hash',
            'createdAt': '2026-01-01T00:00:00Z',
            'createdBy': {'id': 'u-1', 'name': 'Ada'},
            'resources': 'kind: Application',
            'summary': {'deployed': 2, 'failed': 1, 'removed': 0},
            'entries': [entry],
          },
        ),
      ).getGatewayMaster('g-1');
      expect(master.number, 3);
      expect(master.master, 'm-hash');
      expect(master.createdBy?.name, 'Ada');
      expect(master.summary?.failed, 1);
      expect(master.entries.single.state, 'failed');
      expect(master.entries.single.failure?.description, 'bad field');
      expect(master.entries.single.by?.id, 'u-1');

      final empty = await clientFor(Recorder(body: {'gatewayId': 'g-1', 'number': 0})).getGatewayMaster('g-1');
      expect(empty.number, 0);
      expect(empty.master, isNull);
      expect(empty.entries, isEmpty);

      final history = await clientFor(
        Recorder(
          body: [
            {
              'number': 2,
              'master': 'b',
              'summary': {'deployed': 1},
            },
            {'number': 1, 'master': 'a'},
          ],
        ),
      ).getGatewayMasterHistory('g-1');
      expect(history.map((m) => m.number), [2, 1]);
      expect(history.first.summary?.deployed, 1);

      final resource = await clientFor(
        Recorder(
          body: {
            'gatewayId': 'g-1',
            'key': 'application/app-1',
            'history': [
              {'master': 'b', 'number': 2, 'entry': entry},
            ],
          },
        ),
      ).getGatewayMasterResource('g-1', 'application', 'app-1');
      expect(resource.key, 'application/app-1');
      expect(resource.history.single.number, 2);
      expect(resource.history.single.entry?.sourceVersion, 'abc1234');
    });

    test('a missing resource surfaces as not found', () async {
      await expectLater(
        clientFor(
          Recorder(status: 404, body: {'code': 'GTW-1031'}),
        ).getGatewayMasterResource('g-1', 'application', 'gone'),
        throwsA(
          isA<IAMApiException>()
              .having((e) => e.code, 'code', ThunderIDErrorCode.notFound)
              .having((e) => e.serverError?.code, 'server code', 'GTW-1031'),
        ),
      );
    });
  });
}
