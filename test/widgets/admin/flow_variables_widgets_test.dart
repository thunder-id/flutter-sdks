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

Widget _app(_FakeServer server, Widget child) => MaterialApp(
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

Key _field(String identifier) => Key('thunderid-field-flow-variables-$identifier');

const _email = FlowVariableDefinition(
  identifier: 'supportEmail',
  type: FlowVariableTypes.emailInput,
  label: 'Support email',
  defaultValue: 'help@example.com',
);
const _flag = FlowVariableDefinition(
  identifier: 'showSignUp',
  type: FlowVariableTypes.booleanInput,
  label: 'Show sign-up',
  defaultValue: true,
);
const _mfa = FlowVariableDefinition(
  identifier: 'mfa',
  type: FlowVariableTypes.select,
  label: 'Second factor',
  defaultValue: 'EMAIL_OTP',
  options: ['SMS_OTP', 'EMAIL_OTP'],
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

  group('BaseFlowVariables', () {
    testWidgets('renders a card per variable with stable identifiers, and locks what the unit may not set',
        (tester) async {
      await tester.pumpWidget(
        _bare(
          BaseFlowVariables(
            variables: const [_email, _flag],
            overlay: const ResolvedOverlay(
              isOwnedByOU: false,
              rules: {'variables.supportEmail': OverlayRule(editable: true)},
            ),
            ownerName: 'Acme',
            ouName: 'Retail',
            showScopeNotice: true,
            onSubmit: (_, __) {},
          ),
        ),
      );

      expect(find.byKey(const Key('thunderid-admin-flow-variables')), findsOneWidget);
      expect(find.byKey(const Key('thunderid-admin-flow-variables-field-supportEmail')), findsOneWidget);
      expect(find.byKey(_field('supportEmail')), findsOneWidget);
      expect(find.text('Support email'), findsOneWidget);
      expect(find.text('Set by Acme · On'), findsOneWidget);
      expect(find.text('Applies to Retail'), findsOneWidget);
      expect(find.byKey(const Key('thunderid-action-flow-variables-submit')), findsOneWidget);
      expect(find.byKey(const Key('thunderid-action-flow-variables-reset')), findsOneWidget);
      expect(find.byKey(const Key('thunderid-action-flow-variables-cancel')), findsNothing);
    });

    testWidgets('says so when the flow has no variables, and has no save button', (tester) async {
      await tester.pumpWidget(_bare(BaseFlowVariables(variables: const [], onSubmit: (_, __) {})));

      expect(find.text('This flow has no variables to configure.'), findsOneWidget);
      expect(find.byKey(const Key('thunderid-action-flow-variables-submit')), findsNothing);
    });

    testWidgets('shows the translated error only once a value is changed, and submits only the overrides',
        (tester) async {
      FlowVariableValues? submittedValues;
      FlowVariableValues? submittedOverrides;
      await tester.pumpWidget(
        _bare(
          BaseFlowVariables(
            variables: const [_email, _flag],
            onSubmit: (values, overrides) {
              submittedValues = values;
              submittedOverrides = overrides;
            },
          ),
        ),
      );
      expect(find.text('Enter a valid value.'), findsNothing);

      await tester.enterText(find.byKey(_field('supportEmail')), 'nope');
      await tester.pump();
      expect(find.text('Enter a valid value.'), findsOneWidget);
      expect(find.byKey(const Key('thunderid-admin-flow-variables-field-supportEmail-customized')), findsOneWidget);

      await tester.tap(find.byKey(const Key('thunderid-action-flow-variables-submit')));
      await tester.pump();
      expect(submittedValues, isNull);

      await tester.enterText(find.byKey(_field('supportEmail')), 'team@example.com');
      await tester.pump();
      await tester.tap(find.byKey(const Key('thunderid-action-flow-variables-submit')));
      await tester.pump();

      expect(submittedValues, {'supportEmail': 'team@example.com', 'showSignUp': true});
      expect(submittedOverrides, {'supportEmail': 'team@example.com'});
    });

    testWidgets('starts from the unit values and resets to the defaults', (tester) async {
      final changes = <FlowVariableValues>[];
      await tester.pumpWidget(
        _bare(
          BaseFlowVariables(
            variables: const [_email, _flag],
            initialValues: const {'supportEmail': 'team@example.com', 'showSignUp': false},
            onChange: changes.add,
            onSubmit: (_, __) {},
          ),
        ),
      );
      expect(find.text('team@example.com'), findsOneWidget);
      expect(find.text('Default: help@example.com'), findsOneWidget);

      await tester.tap(find.byKey(const Key('thunderid-action-flow-variables-reset')));
      await tester.pump();

      expect(changes.last, {'supportEmail': 'help@example.com', 'showSignUp': true});
      expect(tester.widget<TextField>(find.byKey(_field('supportEmail'))).controller?.text, 'help@example.com');
      expect(find.text('Default: help@example.com'), findsNothing);
    });

    testWidgets('sets a boolean and a select', (tester) async {
      final changes = <FlowVariableValues>[];
      await tester.pumpWidget(_bare(BaseFlowVariables(variables: const [_flag, _mfa], onChange: changes.add)));

      await tester.tap(find.byKey(_field('showSignUp')));
      await tester.pump();
      expect(changes.last['showSignUp'], false);

      await tester.tap(find.byKey(_field('mfa')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SMS_OTP').last);
      await tester.pumpAndSettle();
      expect(changes.last['mfa'], 'SMS_OTP');
    });

    testWidgets('lists the connections a policy allows, with the hint and the create action', (tester) async {
      var createRequested = false;
      await tester.pumpWidget(
        _bare(
          BaseFlowVariables(
            variables: const [
              FlowVariableDefinition(
                identifier: 'idp',
                type: FlowVariableTypes.connectionSelect,
                category: 'IDENTITY_PROVIDER',
              ),
            ],
            connections: const [
              ConnectionInstance(id: 'c1', name: 'Google', categories: ['identity-provider']),
              ConnectionInstance(id: 'c2', name: 'GitHub', categories: ['identity-provider']),
            ],
            overlay: const ResolvedOverlay(
              isOwnedByOU: false,
              rules: {
                'variables.idp': OverlayRule(editable: true, allowedValues: ['c2']),
              },
            ),
            ouName: 'Retail',
            onCreateConnection: () => createRequested = true,
          ),
        ),
      );

      expect(find.text('Only connections that belong to Retail are listed.'), findsOneWidget);
      await tester.tap(find.byKey(_field('idp')));
      await tester.pumpAndSettle();
      expect(find.text('GitHub'), findsWidgets);
      expect(find.text('Google'), findsNothing);
      await tester.tap(find.text('GitHub').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('thunderid-action-flow-variables-create-connection-idp')));
      expect(createRequested, isTrue);
    });

    testWidgets('hands its state to a builder, which can change and submit the values', (tester) async {
      FlowVariableValues? submitted;
      await tester.pumpWidget(
        _bare(
          BaseFlowVariables(
            variables: const [_email],
            onSubmit: (_, overrides) => submitted = overrides,
            builder: (context, form) => Column(
              children: [
                for (final variable in form.variables)
                  Text('${variable.identifier}=${form.values[variable.identifier]}'),
                if (form.errors.isNotEmpty) Text(form.errors.values.first),
                TextButton(onPressed: () => form.onChanged('supportEmail', 'bad'), child: const Text('bad')),
                TextButton(onPressed: () => form.onChanged('supportEmail', 'ok@example.com'), child: const Text('ok')),
                TextButton(onPressed: form.submit, child: const Text('save')),
              ],
            ),
          ),
        ),
      );
      expect(find.text('supportEmail=help@example.com'), findsOneWidget);

      await tester.tap(find.text('bad'));
      await tester.pump();
      expect(find.text('Enter a valid value.'), findsOneWidget);

      await tester.tap(find.text('ok'));
      await tester.pump();
      await tester.tap(find.text('save'));
      await tester.pump();
      expect(submitted, {'supportEmail': 'ok@example.com'});
    });
  });

  group('FlowVariablesForm', () {
    void serveFlow() {
      server
        ..on('GET', '/flows/f1', {
          'id': 'f1',
          'handle': 'login',
          'flowType': 'AUTHENTICATION',
          'isOwnedByOU': false,
          'variables': [
            {
              'identifier': 'supportEmail',
              'type': 'EMAIL_INPUT',
              'label': 'Support email',
              'defaultValue': 'help@example.com',
            },
          ],
        })
        ..on('GET', '/flows/f1/variables', {
          'values': {'supportEmail': 'team@example.com'},
        })
        ..on('GET', '/flows/f1/overlay-rules', {
          'isOwnedByOU': false,
          'rules': {
            'variables.supportEmail': {'editable': true},
          },
        });
    }

    testWidgets('loads the unit values and saves the overrides', (tester) async {
      serveFlow();
      server.on('PUT', '/flows/f1/variables', {
        'values': {'supportEmail': 'desk@example.com'},
      });
      FlowVariableValues? saved;
      await tester.pumpWidget(_app(server, FlowVariablesForm(flowId: 'f1', ouId: 'ou-1', onSaved: (v) => saved = v)));
      await tester.pumpAndSettle();

      expect(find.text('Flow variables'), findsOneWidget);
      expect(find.text('team@example.com'), findsOneWidget);
      expect(server.where('GET', '/flows/f1').single.url.queryParameters, {'ouId': 'ou-1'});

      await tester.enterText(find.byKey(_field('supportEmail')), 'desk@example.com');
      await tester.pump();
      await tester.tap(find.byKey(const Key('thunderid-action-flow-variables-submit')));
      await tester.pumpAndSettle();

      expect(jsonDecode(server.where('PUT', '/flows/f1/variables').single.body!), {
        'ouId': 'ou-1',
        'values': {'supportEmail': 'desk@example.com'},
      });
      expect(saved, {'supportEmail': 'desk@example.com'});
    });

    testWidgets('shows the translated message when the variables cannot be loaded', (tester) async {
      serveFlow();
      server.on('GET', '/flows/f1/overlay-rules', {'description': 'Insufficient scope'}, status: 403);
      await tester.pumpWidget(_app(server, const FlowVariablesForm(flowId: 'f1', ouId: 'ou-1')));
      await tester.pumpAndSettle();

      expect(find.text('You do not have permission to do this.'), findsOneWidget);
      expect(find.textContaining('Insufficient scope'), findsNothing);
    });

    testWidgets('shows the translated message when the save fails', (tester) async {
      serveFlow();
      server.on('PUT', '/flows/f1/variables', {'description': 'value rejected'}, status: 400);
      await tester.pumpWidget(_app(server, const FlowVariablesForm(flowId: 'f1', ouId: 'ou-1')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(_field('supportEmail')), 'desk@example.com');
      await tester.pump();
      await tester.tap(find.byKey(const Key('thunderid-action-flow-variables-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Could not save the variables. Please try again.'), findsOneWidget);
      expect(find.textContaining('value rejected'), findsNothing);
    });
  });

  group('SharedFlowList', () {
    void serveFlows() => server.on('GET', '/flows', {
          'totalResults': 3,
          'flows': [
            {'id': 'f-own', 'name': 'Own login', 'handle': 'own', 'flowType': 'AUTHENTICATION', 'isOwnedByOU': true},
            {'id': 'f-a', 'name': 'Shared login', 'handle': 'a', 'flowType': 'AUTHENTICATION', 'isOwnedByOU': false},
            {'id': 'f-b', 'name': 'Shared sign-up', 'handle': 'b', 'flowType': 'REGISTRATION', 'isOwnedByOU': false},
          ],
        });

    testWidgets('lists the flows shared with the unit by default and reports the chosen one', (tester) async {
      serveFlows();
      ManagedFlow? selected;
      await tester.pumpWidget(_app(server, SharedFlowList(ouId: 'ou-1', onSelect: (flow) => selected = flow)));
      await tester.pumpAndSettle();

      expect(find.text('Shared flows'), findsOneWidget);
      expect(find.text('Shared login'), findsOneWidget);
      expect(find.text('Shared sign-up'), findsOneWidget);
      expect(find.text('Own login'), findsNothing);
      expect(server.requests.single.url.queryParameters, {'filter': 'ouId eq "ou-1"', 'limit': '100', 'offset': '0'});

      await tester.tap(find.byKey(const Key('thunderid-admin-shared-flow-list-row-f-b')));
      expect(selected?.id, 'f-b');
    });

    testWidgets('lists the flows the unit owns', (tester) async {
      serveFlows();
      await tester.pumpWidget(_app(server, const SharedFlowList(ouId: 'ou-1', ownership: SharedFlowOwnership.owned)));
      await tester.pumpAndSettle();

      expect(find.text('Own login'), findsOneWidget);
      expect(find.text('Shared login'), findsNothing);
    });

    testWidgets('pages every flow on the server', (tester) async {
      serveFlows();
      await tester.pumpWidget(
        _app(server, const SharedFlowList(ouId: 'ou-1', ownership: SharedFlowOwnership.all, limit: 2)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Own login'), findsOneWidget);
      expect(find.text('Shared login'), findsOneWidget);
      expect(server.requests.single.url.queryParameters, {'filter': 'ouId eq "ou-1"', 'limit': '2', 'offset': '0'});
    });

    testWidgets('shows the translated forbidden message, never the server text', (tester) async {
      server.on('GET', '/flows', {'description': 'Insufficient scope: system:flow'}, status: 403);
      await tester.pumpWidget(_app(server, const SharedFlowList(ouId: 'ou-1')));
      await tester.pumpAndSettle();

      expect(find.text('You do not have permission to do this.'), findsOneWidget);
      expect(find.textContaining('Insufficient scope'), findsNothing);
    });

    testWidgets('the Base variant hands its rows to a builder', (tester) async {
      await tester.pumpWidget(
        _bare(
          BaseSharedFlowList(
            flows: const [ManagedFlow(id: 'f1', handle: 'login', flowType: 'AUTHENTICATION', name: 'Login')],
            builder: (context, list) => Text('${list.rows.single.name} of ${list.totalResults}'),
          ),
        ),
      );

      expect(find.text('Login of 1'), findsOneWidget);
    });

    testWidgets('the Base variant says so when there are no flows', (tester) async {
      await tester.pumpWidget(_bare(const BaseSharedFlowList(flows: [])));

      expect(find.text('No flows have been shared with this organization unit.'), findsOneWidget);
    });
  });
}
