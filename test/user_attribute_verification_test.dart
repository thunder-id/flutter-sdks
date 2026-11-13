// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/widgets/admin/internal/user_attribute_verification_parts.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

const _baseUrl = 'https://localhost:8090';

const Map<String, Object?> _configured = {
  'adminAttributeVerificationFlow': {'defaultHandle': 'configured-verify'},
};

/// Answers every request with [body] and [statusCode], and records it.
class _Server {
  final Object? body;
  final int statusCode;
  final List<ManagementRequest> requests = [];

  /// The `merged` layer of `GET /server-config/flow`.
  final Map<String, Object?> flowConfig;

  /// Status of `GET /server-config/flow`.
  final int configStatus;

  _Server({this.body, this.statusCode = 200, this.flowConfig = _configured, this.configStatus = 200});

  List<ManagementRequest> get executions => [
        for (final r in requests)
          if (r.url.path == '/flow/execute') r,
      ];

  Future<ManagementResponse> call(ManagementRequest request) async {
    requests.add(request);
    if (request.url.path == '/server-config/flow') {
      return ManagementResponse(
        statusCode: configStatus,
        statusText: 'S',
        body: jsonEncode(configStatus == 200 ? {'merged': flowConfig} : {'code': 'FES-1017'}),
      );
    }
    return ManagementResponse(statusCode: statusCode, statusText: 'S', body: jsonEncode(body));
  }
}

Map<String, Object?> _linkSent(Map<String, Object?> additionalData) => {
      'executionId': 'exec-1',
      'flowStatus': 'INCOMPLETE',
      'type': 'VIEW',
      'data': {'additionalData': additionalData},
    };

Future<Object?> _failure(Future<Object?> future) => future.then<Object?>((_) => null, onError: (Object e) => e);

void main() {
  ThunderIDManagementClient clientFor(_Server server, {String baseUrl = _baseUrl}) =>
      ThunderIDManagementClient(baseUrl: baseUrl, fetcher: server.call);

  group('sendUserAttributeVerification', () {
    test('starts the administrator-initiated flow for the user and reads the sent link', () async {
      final server = _Server(
        body: _linkSent({'channel': 'email', 'emailSent': 'true', 'maskedDestination': 'j***@example.com'}),
      );

      final result = await clientFor(server).sendUserAttributeVerification('u-1', 'email');

      expect(
        server.requests.map((r) => '${r.method} ${r.url.path}'),
        ['GET /server-config/flow', 'POST /flow/execute'],
      );
      final request = server.executions.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), '$_baseUrl/flow/execute');
      expect(jsonDecode(request.body!), {
        'flowType': 'ADMIN_INITIATED',
        'handle': 'configured-verify',
        'inputs': {'subject': 'u-1', 'attribute': 'email'},
        'verbose': true,
      });
      expect(result.channel, 'email');
      expect(result.emailSent, isTrue);
      expect(result.maskedDestination, 'j***@example.com');
    });

    test('runs the flow the app names, without reading the configuration', () async {
      final server = _Server(body: _linkSent({'channel': 'email'}));

      await clientFor(server).sendUserAttributeVerification('u-1', 'email', handle: 'custom-verify');

      expect(server.requests, hasLength(1));
      expect((jsonDecode(server.executions.single.body!) as Map)['handle'], 'custom-verify');
    });

    test('reads the configuration when the handle is blank', () async {
      final server = _Server(body: _linkSent({'channel': 'email'}));

      await clientFor(server).sendUserAttributeVerification('u-1', 'email', handle: ' ');

      expect((jsonDecode(server.executions.single.body!) as Map)['handle'], 'configured-verify');
    });

    for (final (name, config) in <(String, Map<String, Object?>)>[
      ('no entry', {}),
      ('an entry without a handle', {'adminAttributeVerificationFlow': <String, Object?>{}}),
      (
        'an empty handle',
        {
          'adminAttributeVerificationFlow': {'defaultHandle': ''},
        },
      ),
    ]) {
      test('sends nothing and says it is not configured when the configuration has $name', () async {
        final server = _Server(body: _linkSent({'channel': 'email'}), flowConfig: config);

        final error = await _failure(clientFor(server).sendUserAttributeVerification('u-1', 'email'));

        expect(
          error,
          isA<AdministrationFlowError>()
              .having((e) => e.flowCode, 'flowCode', 'sendUserAttributeVerification-NotConfiguredError-001'),
        );
        expect(server.executions, isEmpty);
      });
    }

    test('keeps a failed configuration read as an error rather than reading it as not configured', () async {
      final server = _Server(body: _linkSent({'channel': 'email'}), configStatus: 403);

      final error = await _failure(clientFor(server).sendUserAttributeVerification('u-1', 'email'));

      expect(error, isA<IAMApiException>().having((e) => e.statusCode, 'statusCode', 403));
      expect(server.executions, isEmpty);
    });

    test('reads emailSent "false" as false, and a missing emailSent or destination as null', () async {
      final notSent = await clientFor(_Server(body: _linkSent({'channel': 'email', 'emailSent': 'false'})))
          .sendUserAttributeVerification('u-1', 'email');
      final unreported = await clientFor(_Server(body: _linkSent({'channel': 'email', 'maskedDestination': ''})))
          .sendUserAttributeVerification('u-1', 'email');

      expect(notSent.emailSent, isFalse);
      expect(unreported.emailSent, isNull);
      expect(unreported.maskedDestination, isNull);
    });

    test("raises a refused step with the step's own code", () async {
      final server = _Server(
        body: {
          'flowStatus': 'ERROR',
          'error': {
            'code': 'FET-1114',
            'message': {'defaultValue': 'The user is suspended'},
          },
        },
      );

      final error = await _failure(clientFor(server).sendUserAttributeVerification('u-1', 'email'));

      expect(error, isA<AdministrationFlowError>());
      error as AdministrationFlowError;
      expect(error.flowCode, 'FET-1114');
      expect(error.flowError.code, 'FET-1114');
      expect(error.code, ThunderIDErrorCode.administrationFlowFailed);
    });

    test('a failed flow without a step code gets the generic flow code', () async {
      final error = await _failure(
        clientFor(_Server(body: {'flowStatus': 'ERROR'})).sendUserAttributeVerification('u-1', 'email'),
      );

      expect(
        error,
        isA<AdministrationFlowError>()
            .having((e) => e.flowCode, 'flowCode', 'sendUserAttributeVerification-FlowError-001'),
      );
    });

    for (final (name, body) in [
      ('a paused flow without a channel', _linkSent({})),
      ('a completed flow', {'flowStatus': 'COMPLETE', 'data': <String, Object?>{}}),
    ]) {
      test('$name is an unexpected state', () async {
        final error = await _failure(clientFor(_Server(body: body)).sendUserAttributeVerification('u-1', 'email'));

        expect(
          error,
          isA<AdministrationFlowError>()
              .having((e) => e.flowCode, 'flowCode', 'sendUserAttributeVerification-UnexpectedStateError-001'),
        );
      });
    }

    for (final (userId, attribute) in [('', 'email'), (' ', 'email'), ('u-1', ''), ('u-1', '  ')]) {
      test('refuses a blank user "$userId" or attribute "$attribute" before any request', () async {
        final server = _Server(body: _linkSent({'channel': 'email'}));

        final error = await _failure(clientFor(server).sendUserAttributeVerification(userId, attribute));

        expect(error, isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.invalidInput));
        expect(error, isNot(isA<AdministrationFlowError>()));
        expect(server.requests, isEmpty);
      });
    }

    test('keeps an HTTP refusal as an API error', () async {
      final error = await _failure(
        clientFor(_Server(statusCode: 403, body: {'code': 'FES-1017'})).sendUserAttributeVerification('u-1', 'email'),
      );

      expect(
        error,
        isA<IAMApiException>()
            .having((e) => e.code, 'code', ThunderIDErrorCode.forbidden)
            .having((e) => e.statusCode, 'statusCode', 403),
      );
    });

    test('needs the server URL', () async {
      final server = _Server(body: _linkSent({'channel': 'email'}));

      final error = await _failure(clientFor(server, baseUrl: '').sendUserAttributeVerification('u-1', 'email'));

      expect(error, isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.invalidConfiguration));
      expect(server.requests, isEmpty);
    });
  });

  test('FlowType.adminInitiated is ADMIN_INITIATED', () {
    expect(FlowType.adminInitiated.value, 'ADMIN_INITIATED');
  });

  group('ManagedUser.verifiedAttributes', () {
    Map<String, Object?> json([Object? verified]) => {
          'id': 'u-1',
          'ouId': 'ou-1',
          'type': 'customer',
          if (verified != null) 'verifiedAttributes': verified,
        };

    test('reads the verified attributes, empty when none is verified, and null when not reported', () {
      final verified = ManagedUser.fromJson(
        json({
          'email': {'verifiedAt': '2026-11-03T10:00:00Z'},
        }),
      );

      expect(verified.verifiedAttributes, {'email': const VerifiedAttribute(verifiedAt: '2026-11-03T10:00:00Z')});
      expect(ManagedUser.fromJson(json(<String, Object?>{})).verifiedAttributes, isEmpty);
      expect(ManagedUser.fromJson(json()).verifiedAttributes, isNull);
    });
  });

  group('administrator verification eligibility', () {
    const schema = <String, dynamic>{
      'email': {'type': 'email'},
      'workEmail': {'type': 'EMAIL'},
      'mobile_number': {'type': 'mobile'},
      'username': {'type': 'string'},
      'secretEmail': {'type': 'email', 'credential': true},
      'blank': {'type': 'email'},
      'count': {'type': 'email'},
    };

    ManagedUser user({
      Map<String, VerifiedAttribute>? verified = const {},
      bool isReadOnly = false,
      Map<String, dynamic>? attributes,
    }) =>
        ManagedUser(
          id: 'u-1',
          ouId: 'ou-1',
          type: 'customer',
          isReadOnly: isReadOnly,
          attributes: attributes ??
              const {
                'workEmail': 'w@example.com',
                'email': 'ada@example.com',
                'mobile_number': '+94771234567',
                'username': 'ada',
                'secretEmail': 's@example.com',
                'blank': '  ',
                'count': 42,
              },
          verifiedAttributes: verified,
        );

    test('lists visible email and mobile attributes with a value, sorted', () {
      expect(adminVerifiableAttributes(user(), schema, const {}), ['email', 'mobile_number', 'workEmail']);
      expect(adminVerifiableAttributes(user(), schema, const {'email'}), ['mobile_number', 'workEmail']);
    });

    test('lists an attribute with a record even when the schema does not type it', () {
      final verified = user(verified: {'username': const VerifiedAttribute(verifiedAt: 'x')});
      expect(
        adminVerifiableAttributes(verified, schema, const {}),
        ['email', 'mobile_number', 'username', 'workEmail'],
      );
      expect(adminVerifiableAttributes(verified, null, const {}), ['username']);
    });

    test('lists nothing when the server does not report verification, or without a user', () {
      expect(adminVerifiableAttributes(user(verified: null), schema, const {}), isEmpty);
      expect(adminVerifiableAttributes(null, schema, const {}), isEmpty);
    });

    test('sends only for unverified email-typed attributes of a writable user with a handler', () {
      final verified = user(verified: {'email': const VerifiedAttribute(verifiedAt: 'x')});
      List<String> verifiable(ManagedUser u) => adminVerifiableAttributes(u, schema, const {});

      expect(adminSendableAttributes(user(), schema, verifiable(user()), canSend: true), {'email', 'workEmail'});
      expect(adminSendableAttributes(verified, schema, verifiable(verified), canSend: true), {'workEmail'});
      expect(adminSendableAttributes(user(), schema, verifiable(user()), canSend: false), isEmpty);
      final readOnly = user(isReadOnly: true);
      expect(adminSendableAttributes(readOnly, schema, verifiable(readOnly), canSend: true), isEmpty);
      expect(adminSendableAttributes(user(), null, verifiable(user()), canSend: true), isEmpty);
    });

    test('names the flow handle only while the action is on and the server sets one', () {
      const configured = {AdministrationFlowConfigKey.adminAttributeVerification: 'admin-verification'};
      expect(adminVerificationFlowHandle(enabled: true, configuredFlows: configured), 'admin-verification');
      expect(adminVerificationFlowHandle(enabled: false, configuredFlows: configured), isNull);
      expect(adminVerificationFlowHandle(enabled: true, configuredFlows: const {}), isNull);
      expect(adminVerificationFlowHandle(enabled: true), isNull);
      expect(
        adminVerificationFlowHandle(
          enabled: true,
          configuredFlows: const {AdministrationFlowConfigKey.adminAttributeVerification: ''},
        ),
        isNull,
      );
      expect(
        adminVerificationFlowHandle(
          enabled: true,
          configuredFlows: const {AdministrationFlowConfigKey.userSuspend: 's'},
        ),
        isNull,
      );
    });

    test('reads the user type only while verification is on and reported', () {
      expect(verificationUserTypeHandle(user(), attributeVerification: true), 'customer');
      expect(verificationUserTypeHandle(user(), attributeVerification: false), isNull);
      expect(verificationUserTypeHandle(user(verified: null), attributeVerification: true), isNull);
      expect(verificationUserTypeHandle(null, attributeVerification: true), isNull);
    });

    test('names the configuration key of the administrator flow and the shared wire keys', () {
      expect(AdministrationFlowConfigKey.adminAttributeVerification, 'adminAttributeVerificationFlow');
      expect(AdministrationFlowConfigKey.values, contains('adminAttributeVerificationFlow'));
      expect(AdministrationFlowInput.subject, 'subject');
      expect(AdministrationFlowData.emailSent, 'emailSent');
    });
  });

  group('ManagementResources.userTypeByHandleQuery', () {
    Future<ManagementResponse> Function(ManagementRequest) typesServer(List<ManagementRequest> requests) =>
        (request) async {
          requests.add(request);
          final path = request.url.path;
          final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
          Object? body;
          if (path == '/user-types') {
            body = offset == 0
                ? {
                    'totalResults': 2,
                    'count': 1,
                    'types': [
                      {'id': 't-1', 'name': 'employee', 'handle': 'employee', 'ouId': 'ou-1'},
                    ],
                  }
                : {
                    'totalResults': 2,
                    'count': 1,
                    'startIndex': 1,
                    'types': [
                      {'id': 't-2', 'name': 'customer', 'handle': 'customer', 'ouId': 'ou-1'},
                    ],
                  };
          } else if (path == '/user-types/t-2') {
            body = {
              'id': 't-2',
              'name': 'customer',
              'handle': 'customer',
              'ouId': 'ou-1',
              'schema': {
                'email': {'type': 'email'},
              },
            };
          }
          return ManagementResponse(
            statusCode: body == null ? 404 : 200,
            statusText: 'S',
            body: jsonEncode(body ?? {}),
          );
        };

    Future<T?> settle<T>(ResourceQuery<T> query) async {
      while (query.isLoading) {
        await Future<void>.delayed(Duration.zero);
      }
      return query.data;
    }

    test('pages through the user types to the handle, then reads that type', () async {
      final requests = <ManagementRequest>[];
      final resources = ManagementResources(
        ThunderIDManagementClient(baseUrl: _baseUrl, fetcher: typesServer(requests)),
      );
      final query = resources.userTypeByHandleQuery('customer');
      final type = await settle(query);
      query.dispose();

      expect(type?.handle, 'customer');
      expect(type?.schema['email'], {'type': 'email'});
      expect(requests.map((r) => r.url.path), ['/user-types', '/user-types', '/user-types/t-2']);
    });

    test('is null for an unknown handle, and reads nothing without one', () async {
      final requests = <ManagementRequest>[];
      final resources = ManagementResources(
        ThunderIDManagementClient(baseUrl: _baseUrl, fetcher: typesServer(requests)),
      );
      final unknown = resources.userTypeByHandleQuery('partner');
      expect(await settle(unknown), isNull);
      expect(unknown.error, isNull);
      unknown.dispose();

      requests.clear();
      final none = resources.userTypeByHandleQuery(null);
      expect(none.isLoading, isFalse);
      expect(requests, isEmpty);
      none.dispose();
    });
  });
}
