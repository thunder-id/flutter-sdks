// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

const baseUrl = 'https://localhost:8090';

ManagementResponse _json(Object? body, {int status = 200}) =>
    ManagementResponse(statusCode: status, statusText: status == 200 ? 'OK' : 'Error', body: jsonEncode(body));

/// Answers by `METHOD path` and records every request. Anything unrouted is a 404.
class _FakeServer {
  final Map<String, ManagementResponse> routes = {};
  final List<ManagementRequest> requests = [];

  void on(String method, String path, Object? body, {int status = 200}) =>
      routes['$method $path'] = _json(body, status: status);

  Future<ManagementResponse> call(ManagementRequest request) async {
    requests.add(request);
    return routes['${request.method} ${request.url.path}'] ??
        const ManagementResponse(statusCode: 404, statusText: 'Not Found');
  }
}

const _email = FlowVariableDefinition(
  identifier: 'supportEmail',
  type: FlowVariableTypes.emailInput,
  defaultValue: 'a@b.co',
);
const _flag = FlowVariableDefinition(
  identifier: 'showSignUp',
  type: FlowVariableTypes.booleanInput,
  defaultValue: true,
);
const _ttl = FlowVariableDefinition(identifier: 'ttl', type: FlowVariableTypes.numberInput, defaultValue: 60);
const _mfa = FlowVariableDefinition(
  identifier: 'mfa',
  type: FlowVariableTypes.select,
  defaultValue: 'EMAIL_OTP',
  options: ['SMS_OTP', 'EMAIL_OTP', 30],
);

const _connections = [
  ConnectionInstance(id: '1', name: 'Google login', type: ConnectionType.google, categories: ['identity-provider']),
  ConnectionInstance(id: '2', name: 'GitHub login', type: ConnectionType.github, categories: ['identity-provider']),
  ConnectionInstance(id: '3', name: 'Twilio', type: ConnectionType.twilio, categories: ['sms-provider']),
];

ResolvedOverlay _pinned(String variable, String value) => ResolvedOverlay(
      isOwnedByOU: false,
      rules: {
        'variables.$variable': OverlayRule(editable: false, value: [value]),
      },
    );

void main() {
  group('operations', () {
    late _FakeServer server;
    late ThunderIDManagementClient client;

    setUp(() {
      server = _FakeServer();
      client = ThunderIDManagementClient(baseUrl: baseUrl, fetcher: server.call);
    });

    test('getFlows filters on the organization unit and reads the ownership of each flow', () async {
      server.on('GET', '/flows', {
        'totalResults': 2,
        'flows': [
          {'id': 'f1', 'handle': 'login', 'flowType': 'AUTHENTICATION', 'isOwnedByOU': true},
          {'id': 'f2', 'handle': 'shared', 'flowType': 'AUTHENTICATION', 'isOwnedByOU': false},
        ],
      });

      final page = await client.getFlows(ouId: 'ou-"1"', flowType: FlowTypes.authentication, limit: 100);

      expect(server.requests.single.url.queryParameters, {
        'filter': 'ouId eq "ou-1"',
        'flowType': 'AUTHENTICATION',
        'limit': '100',
      });
      expect(page.items.map((flow) => flow.isOwnedByOU), [true, false]);
    });

    test('getFlows without an organization unit sends no filter', () async {
      server.on('GET', '/flows', {'flows': <Object?>[]});

      final page = await client.getFlows();

      expect(server.requests.single.url.queryParameters, isEmpty);
      expect(page.items, isEmpty);
    });

    test('getConnections filters on the organization unit', () async {
      server.on('GET', '/connections', {'connections': <Object?>[]});

      await client.getConnections(ouId: 'ou-1', limit: 100);

      expect(server.requests.single.url.queryParameters, {'filter': 'ouId eq "ou-1"', 'limit': '100'});
    });

    test('getConnections of a type does not send the organization unit', () async {
      server.on('GET', '/connections/google', <Object?>[]);

      await client.getConnections(type: ConnectionType.google, ouId: 'ou-1');

      expect(server.requests.single.url.queryParameters, isEmpty);
    });

    test('getFlow for an organization unit reads the variables a shared flow comes back as', () async {
      server.on('GET', '/flows/f1', {
        'id': 'f1',
        'handle': 'login',
        'flowType': 'AUTHENTICATION',
        'ouId': 'ou-1',
        'isOwnedByOU': false,
        'variables': [
          {'identifier': 'supportEmail', 'type': 'EMAIL_INPUT', 'defaultValue': 'a@b.co'},
          {'junk': true},
        ],
      });

      final flow = await client.getFlow('f1', ouId: 'ou-1');

      expect(server.requests.single.url.queryParameters, {'ouId': 'ou-1'});
      expect(flow.isOwnedByOU, isFalse);
      expect(flow.ouId, 'ou-1');
      expect(flow.variables?.single.identifier, 'supportEmail');
      expect(flow.variables?.single.defaultValue, 'a@b.co');
    });

    test('getFlowVariables reads the values of the unit', () async {
      server.on('GET', '/flows/f1/variables', {
        'values': {'supportEmail': 'x@y.co', 'ttl': 120, 'showSignUp': false, 'junk': <Object?>[]},
      });

      final variables = await client.getFlowVariables('f1', 'ou-1');

      expect(server.requests.single.url.queryParameters, {'ouId': 'ou-1'});
      expect(variables.values, {'supportEmail': 'x@y.co', 'ttl': 120, 'showSignUp': false});
    });

    test('updateFlowVariables PUTs the unit and its values', () async {
      server.on('PUT', '/flows/f1/variables', {
        'values': {'ttl': 30},
      });

      final variables = await client.updateFlowVariables('f1', 'ou-1', {'ttl': 30});

      expect(jsonDecode(server.requests.single.body!), {
        'ouId': 'ou-1',
        'values': {'ttl': 30},
      });
      expect(variables.values, {'ttl': 30});
    });

    test('getFlowOverlayRules reads the owner flag flows use, and the rule of each variable', () async {
      server.on('GET', '/flows/f1/overlay-rules', {
        'isOwnedByOU': false,
        'rules': {
          'variables.mfa': {
            'editable': true,
            'allowedValues': ['SMS_OTP'],
          },
        },
      });

      final overlay = await client.getFlowOverlayRules('f1', 'ou-1');

      expect(server.requests.single.url.queryParameters, {'ouId': 'ou-1'});
      expect(overlay.isOwnedByOU, isFalse);
      expect(overlay.rules['variables.mfa']?.allowedValues, ['SMS_OTP']);
    });

    test('a missing flow surfaces as not found', () async {
      server.on('GET', '/flows/f1/overlay-rules', {'code': 'FLW-404'}, status: 404);

      await expectLater(
        client.getFlowOverlayRules('f1', 'ou-1'),
        throwsA(isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.notFound)),
      );
    });
  });

  group('getFlowVariableDefinitions', () {
    test('returns nothing without a flow', () {
      expect(getFlowVariableDefinitions(null), isEmpty);
    });

    test('reads the variables of a flow shared with the unit', () {
      const flow = FlowDefinition(id: 'f', name: 'n', handle: 'h', flowType: 'AUTHENTICATION', variables: [_email]);

      expect(getFlowVariableDefinitions(flow), [_email]);
    });

    test('reads the inputs of the VARIABLES node of an owned flow, skipping malformed ones', () {
      const flow = FlowDefinition(
        id: 'f',
        name: 'n',
        handle: 'h',
        flowType: 'AUTHENTICATION',
        nodes: [
          {'id': 'start', 'type': 'START'},
          {
            'id': 'vars',
            'type': 'VARIABLES',
            'inputs': [
              {
                'identifier': 'mfa',
                'type': 'SELECT',
                'options': ['SMS'],
              },
              {'junk': true},
            ],
          },
        ],
      );

      final definitions = getFlowVariableDefinitions(flow);

      expect(definitions.map((d) => d.identifier), ['mfa']);
      expect(definitions.single.options, ['SMS']);
    });

    test('returns nothing when the flow has no VARIABLES node', () {
      const flow = FlowDefinition(
        id: 'f',
        name: 'n',
        handle: 'h',
        flowType: 'AUTHENTICATION',
        nodes: [
          {'id': 'start', 'type': 'START'},
        ],
      );

      expect(getFlowVariableDefinitions(flow), isEmpty);
    });
  });

  group('getFlowVariableOptions', () {
    test('lists the declared values of a select as strings', () {
      const definition = FlowVariableDefinition(
        identifier: 'mfa',
        type: FlowVariableTypes.select,
        options: ['SMS_OTP', 2, true],
      );

      expect(getFlowVariableOptions(definition), const [
        FlowVariableOption(label: 'SMS_OTP', value: 'SMS_OTP'),
        FlowVariableOption(label: '2', value: '2'),
        FlowVariableOption(label: 'true', value: 'true'),
      ]);
    });

    test('lists the connections of the category, whichever way it is spelled', () {
      const definition = FlowVariableDefinition(
        identifier: 'idp',
        type: FlowVariableTypes.connectionSelect,
        category: 'IDENTITY_PROVIDER',
      );

      expect(getFlowVariableOptions(definition, connections: _connections), const [
        FlowVariableOption(label: 'Google login', value: '1'),
        FlowVariableOption(label: 'GitHub login', value: '2'),
      ]);
    });

    test('narrows the connections to the vendors, ignoring case', () {
      const definition = FlowVariableDefinition(
        identifier: 'idp',
        type: FlowVariableTypes.connectionSelect,
        category: 'IDENTITY_PROVIDER',
        connectionTypes: ['Google'],
      );

      expect(getFlowVariableOptions(definition, connections: _connections).map((o) => o.value), ['1']);
    });

    test('lists every connection when the variable names no category', () {
      const definition = FlowVariableDefinition(identifier: 'c', type: FlowVariableTypes.connectionSelect);

      expect(getFlowVariableOptions(definition, connections: _connections), hasLength(3));
    });

    test('keeps to the values a policy allows and drops the ones it takes away', () {
      const definition = FlowVariableDefinition(
        identifier: 'mfa',
        type: FlowVariableTypes.select,
        options: ['SMS_OTP', 'EMAIL_OTP', 'TOTP'],
      );

      expect(
        getFlowVariableOptions(definition, allowedValues: ['SMS_OTP', 'TOTP']).map((o) => o.value),
        ['SMS_OTP', 'TOTP'],
      );
      expect(
        getFlowVariableOptions(definition, excludedValues: ['TOTP']).map((o) => o.value),
        ['SMS_OTP', 'EMAIL_OTP'],
      );
      expect(
        getFlowVariableOptions(
          const FlowVariableDefinition(
            identifier: 'idp',
            type: FlowVariableTypes.connectionSelect,
            category: 'IDENTITY_PROVIDER',
          ),
          connections: _connections,
          allowedValues: ['2'],
        ).map((o) => o.value),
        ['2'],
      );
    });

    test('has no options for the other types', () {
      const definition = FlowVariableDefinition(identifier: 't', type: FlowVariableTypes.textInput);

      expect(getFlowVariableOptions(definition, connections: _connections), isEmpty);
    });
  });

  group('resolveFlowVariableRule', () {
    test('lets everything be edited without an overlay', () {
      final rule = resolveFlowVariableRule(_email);

      expect(rule.editable, isTrue);
      expect(rule.defaultValue, 'a@b.co');
    });

    test('lets the owner edit everything and ignores any rule', () {
      final rule = resolveFlowVariableRule(
        _email,
        const ResolvedOverlay(
          isOwnedByOU: true,
          rules: {
            'variables.supportEmail': OverlayRule(allowedValues: ['x'], editable: false, value: ['y']),
          },
        ),
      );

      expect(rule.editable, isTrue);
      expect(rule.defaultValue, 'a@b.co');
      expect(rule.allowedValues, isNull);
      expect(rule.excludedValues, isNull);
    });

    test('locks a variable no policy names, at the owner default', () {
      final rule = resolveFlowVariableRule(_email, const ResolvedOverlay(isOwnedByOU: false));

      expect(rule.editable, isFalse);
      expect(rule.defaultValue, 'a@b.co');
    });

    test('opens a variable a policy makes editable', () {
      final rule = resolveFlowVariableRule(
        _email,
        const ResolvedOverlay(
          isOwnedByOU: false,
          rules: {'variables.supportEmail': OverlayRule(editable: true)},
        ),
      );

      expect(rule.editable, isTrue);
    });

    test('pins a locked variable to the value the policy fixes, in the variable type', () {
      expect(resolveFlowVariableRule(_flag, _pinned('showSignUp', 'false')).defaultValue, false);
      expect(resolveFlowVariableRule(_ttl, _pinned('ttl', '120')).defaultValue, 120);
      expect(resolveFlowVariableRule(_mfa, _pinned('mfa', '30')).defaultValue, 30);
      expect(resolveFlowVariableRule(_mfa, _pinned('mfa', 'SMS_OTP')).defaultValue, 'SMS_OTP');
    });

    test('carries the values the unit may choose from and the ones taken away', () {
      final rule = resolveFlowVariableRule(
        _mfa,
        const ResolvedOverlay(
          isOwnedByOU: false,
          rules: {
            'variables.mfa': OverlayRule(
              allowedValues: ['SMS_OTP', 'EMAIL_OTP'],
              editable: true,
              excludedValues: ['EMAIL_OTP'],
            ),
          },
        ),
      );

      expect(rule.allowedValues, ['SMS_OTP', 'EMAIL_OTP']);
      expect(rule.excludedValues, ['EMAIL_OTP']);
    });
  });

  group('validateFlowVariableValue', () {
    FlowVariableValidationError? check(FlowVariableDefinition definition, Object? value) =>
        validateFlowVariableValue(definition, value);
    const required = FlowVariableValidationError(FlowVariableValidationErrorCode.required);
    const invalid = FlowVariableValidationError(FlowVariableValidationErrorCode.invalid);

    test('requires a value except for a boolean', () {
      const text = FlowVariableDefinition(identifier: 'v', type: FlowVariableTypes.textInput);
      const flag = FlowVariableDefinition(identifier: 'b', type: FlowVariableTypes.booleanInput);

      expect(check(text, ''), required);
      expect(check(text, null), required);
      expect(check(flag, null), isNull);
      expect(check(flag, 'yes'), invalid);
    });

    test('applies the text rules and carries the rule message', () {
      const definition = FlowVariableDefinition(
        identifier: 'v',
        type: FlowVariableTypes.textInput,
        validation: [
          FlowVariableValidationRule(type: 'minLength', value: 3, message: 'too short'),
          FlowVariableValidationRule(type: 'maxLength', value: 5),
          FlowVariableValidationRule(type: 'regex', value: r'^[a-z]+$', message: 'letters only'),
        ],
      );

      expect(
        check(definition, 'ab'),
        const FlowVariableValidationError(FlowVariableValidationErrorCode.minLength, 'too short'),
      );
      expect(check(definition, 'abcdef'), const FlowVariableValidationError(FlowVariableValidationErrorCode.maxLength));
      expect(
        check(definition, 'ab1de'),
        const FlowVariableValidationError(FlowVariableValidationErrorCode.pattern, 'letters only'),
      );
      expect(check(definition, 'abcd'), isNull);
    });

    test('lets a pattern Dart cannot compile through', () {
      const definition = FlowVariableDefinition(
        identifier: 'v',
        type: FlowVariableTypes.textInput,
        validation: [FlowVariableValidationRule(type: 'regex', value: '(?<')],
      );

      expect(check(definition, 'x'), isNull);
    });

    test('bounds a number', () {
      const definition = FlowVariableDefinition(identifier: 'n', type: FlowVariableTypes.numberInput, min: 1, max: 10);

      expect(check(definition, 'abc'), invalid);
      expect(check(definition, 0), const FlowVariableValidationError(FlowVariableValidationErrorCode.min));
      expect(check(definition, 11), const FlowVariableValidationError(FlowVariableValidationErrorCode.max));
      expect(check(definition, 5), isNull);
      expect(check(definition, '5'), isNull);
    });

    test('keeps a select to its options', () {
      const definition = FlowVariableDefinition(identifier: 's', type: FlowVariableTypes.select, options: ['A', 2]);

      expect(check(definition, 'B'), const FlowVariableValidationError(FlowVariableValidationErrorCode.notOption));
      expect(check(definition, 2), isNull);
    });

    test('accepts the text of a select option, as the server does', () {
      const flags = FlowVariableDefinition(identifier: 'f', type: FlowVariableTypes.select, options: [true, false]);
      const mixed = FlowVariableDefinition(identifier: 'm', type: FlowVariableTypes.select, options: ['A', 2]);

      expect(check(flags, 'true'), isNull);
      expect(check(flags, false), isNull);
      expect(check(flags, 'yes'), const FlowVariableValidationError(FlowVariableValidationErrorCode.notOption));
      expect(check(mixed, '2'), isNull);
    });

    test('checks the format of email, phone and date', () {
      const email = FlowVariableDefinition(identifier: 'e', type: FlowVariableTypes.emailInput);
      const phone = FlowVariableDefinition(identifier: 'p', type: FlowVariableTypes.phoneInput);
      const date = FlowVariableDefinition(identifier: 'd', type: FlowVariableTypes.dateInput);

      expect(check(email, 'nope'), invalid);
      expect(check(email, 'a@b.co'), isNull);
      expect(check(phone, 'abc'), invalid);
      expect(check(phone, '+94 77 123 4567'), isNull);
      expect(check(date, '31/10/2026'), invalid);
      expect(check(date, '2026-10-31'), isNull);
    });

    test('takes a connection id as a string', () {
      const definition = FlowVariableDefinition(identifier: 'c', type: FlowVariableTypes.connectionSelect);

      expect(check(definition, 12), invalid);
      expect(check(definition, 'abc'), isNull);
    });
  });

  group('FlowVariablesController', () {
    late _FakeServer server;
    late ManagementResources resources;

    setUp(() {
      server = _FakeServer();
      resources = ManagementResources(ThunderIDManagementClient(baseUrl: baseUrl, fetcher: server.call));
    });

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    void serveSharedFlow(List<Map<String, Object?>> variables) {
      server
        ..on('GET', '/flows/f1', {
          'id': 'f1',
          'handle': 'login',
          'flowType': 'AUTHENTICATION',
          'isOwnedByOU': false,
          'variables': variables,
        })
        ..on('GET', '/flows/f1/variables', {
          'values': {'supportEmail': 'x@y.co'},
        })
        ..on('GET', '/flows/f1/overlay-rules', {'isOwnedByOU': false, 'rules': <String, Object?>{}});
    }

    test('loads the definitions, the values and the rules, and skips connections it does not need', () async {
      serveSharedFlow([
        {'identifier': 'supportEmail', 'type': 'EMAIL_INPUT'},
      ]);

      final controller = FlowVariablesController(resources, flowId: 'f1', ouId: 'ou-1');
      addTearDown(controller.dispose);
      expect(controller.isLoaded, isFalse);
      await settle();
      await settle();

      expect(controller.isLoaded, isTrue);
      expect(controller.error, isNull);
      expect(controller.definitions.single.identifier, 'supportEmail');
      expect(controller.overrides, {'supportEmail': 'x@y.co'});
      expect(controller.overlay?.isOwnedByOU, isFalse);
      expect(server.requests.where((r) => r.url.path == '/connections'), isEmpty);
    });

    test('loads the connections of the unit when a variable takes one', () async {
      serveSharedFlow([
        {'identifier': 'idp', 'type': 'CONNECTION_SELECT', 'category': 'IDENTITY_PROVIDER'},
      ]);
      server.on('GET', '/connections', {
        'connections': [
          {
            'id': 'c1',
            'name': 'Google',
            'type': 'google',
            'categories': ['identity-provider'],
          },
        ],
      });

      final controller = FlowVariablesController(resources, flowId: 'f1', ouId: 'ou-1');
      addTearDown(controller.dispose);
      for (var i = 0; i < 4; i++) {
        await settle();
      }

      final request = server.requests.singleWhere((r) => r.url.path == '/connections');
      expect(request.url.queryParameters, {'filter': 'ouId eq "ou-1"', 'limit': '100'});
      expect(controller.connections.single.id, 'c1');
    });

    test('reports a load failure', () async {
      serveSharedFlow(const []);
      server.on('GET', '/flows/f1/overlay-rules', {'code': 'x'}, status: 403);

      final controller = FlowVariablesController(resources, flowId: 'f1', ouId: 'ou-1');
      addTearDown(controller.dispose);
      await settle();
      await settle();

      expect(controller.isLoaded, isFalse);
      expect(controller.error, isA<IAMException>().having((e) => e.code, 'code', ThunderIDErrorCode.forbidden));
    });

    test('saves the values, reports them and reloads the unit values', () async {
      serveSharedFlow(const []);
      server.on('PUT', '/flows/f1/variables', {
        'values': {'ttl': 30},
      });
      FlowVariableValues? saved;

      final controller = FlowVariablesController(
        resources,
        flowId: 'f1',
        ouId: 'ou-1',
        onSaved: (values) => saved = values,
      );
      addTearDown(controller.dispose);
      await settle();

      final result = await controller.save({'ttl': 30});
      await settle();

      expect(result?.values, {'ttl': 30});
      expect(saved, {'ttl': 30});
      expect(controller.saveError, isNull);
      expect(server.requests.where((r) => r.method == 'GET' && r.url.path == '/flows/f1/variables'), hasLength(2));
    });

    test('keeps a failed save in saveError instead of throwing', () async {
      serveSharedFlow(const []);
      server.on('PUT', '/flows/f1/variables', {'code': 'x'}, status: 400);

      final controller = FlowVariablesController(resources, flowId: 'f1', ouId: 'ou-1');
      addTearDown(controller.dispose);
      await settle();

      expect(await controller.save({'ttl': 'nope'}), isNull);
      expect(controller.saveError, isA<IAMException>());
      expect(controller.isSaving, isFalse);
    });
  });
}
