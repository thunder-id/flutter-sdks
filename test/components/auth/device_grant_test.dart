// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

const _channel = MethodChannel('dev.thunderid/sdk');
const _config = ThunderIDConfig(baseUrl: 'https://auth.example.com', clientId: 'app', applicationId: 'app-1');

/// Answers the flow endpoint from a queue and the device callback with [callback], recording every
/// request body.
class _FlowServer {
  final List<HttpResponseData> flowAnswers = [];
  HttpResponseData callback = _json(200, {'redirect_uri': 'https://auth.example.com/device/done'});
  final List<({Uri url, Map<String, dynamic> body})> sent = [];

  Future<HttpResponseData> transport(String method, Uri url, Map<String, String> headers, String? body) async {
    sent.add((url: url, body: body == null ? const {} : jsonDecode(body) as Map<String, dynamic>));
    if (url.path == '/oauth2/auth/callback') return callback;
    if (flowAnswers.isEmpty) return _json(500, {'code': 'SSE-5000'});
    return flowAnswers.removeAt(0);
  }

  List<Map<String, dynamic>> get flowBodies => [
    for (final request in sent)
      if (request.url.path == '/flow/execute') request.body,
  ];
}

HttpResponseData _json(int status, Object body) => HttpResponseData(statusCode: status, body: jsonEncode(body));

const _codeStep = {
  'executionId': 'exec-1',
  'flowStatus': 'INCOMPLETE',
  'data': {
    'inputs': [
      {'identifier': 'user_code', 'type': 'TEXT_INPUT', 'required': true},
    ],
  },
};

const _approved = {
  'executionId': 'exec-1',
  'flowStatus': 'COMPLETE',
  'assertion': 'jwt-assertion',
  'data': {
    'additionalData': {'authId': 'auth-1', 'callbackType': 'device'},
  },
};

Widget _app(_FlowServer server, Widget child) => MaterialApp(
  home: ThunderIDProvider(
    config: _config,
    client: ThunderIDClient(httpTransport: server.transport),
    child: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

Finder _key(String key) => find.byKey(Key(key));

void main() {
  late _FlowServer server;

  setUp(() {
    server = _FlowServer();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      (call) async => call.method == 'initialize' ? true : (call.method == 'isSignedIn' ? false : null),
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
  });

  testWidgets('asks for the code, submits it, and shows the device was approved', (tester) async {
    server.flowAnswers
      ..add(_json(200, _codeStep))
      ..add(_json(200, _approved));
    final outcomes = <DeviceGrantResult>[];
    await tester.pumpWidget(_app(server, DeviceGrant(onComplete: outcomes.add)));
    await tester.pumpAndSettle();

    expect(find.text('Authorize a device'), findsOneWidget);
    expect(find.text('Device code'), findsOneWidget);
    expect(server.flowBodies.single, {
      'applicationId': 'app-1',
      'flowType': 'DEVICE_GRANT',
      'inputs': <String, dynamic>{},
      'verbose': true,
    });

    await tester.enterText(_key('thunderid-field-user_code'), 'WDJB-MJHT');
    await tester.tap(_key('thunderid-action-submit'));
    await tester.pumpAndSettle();

    expect(server.flowBodies.last, {
      'executionId': 'exec-1',
      'inputs': {'user_code': 'WDJB-MJHT'},
    });
    expect(server.sent.last.url.path, '/oauth2/auth/callback');
    expect(outcomes, [DeviceGrantResult.approved]);
    expect(_key('thunderid-device-grant-result-approved'), findsOneWidget);
    expect(find.text('Device authorized'), findsOneWidget);
  });

  testWidgets('starts with a given code and asks again, translated, when the server refuses it', (tester) async {
    server.flowAnswers.add(
      _json(200, {
        ..._codeStep,
        'failureReason': 'Invalid user code',
        'error': {
          'code': 'FET-1131',
          'message': {'key': 'x', 'defaultValue': 'server text'},
        },
      }),
    );
    await tester.pumpWidget(_app(server, const DeviceGrant(userCode: 'NOPE-NOPE')));
    await tester.pumpAndSettle();

    expect((server.flowBodies.single['inputs'] as Map)['user_code'], 'NOPE-NOPE');
    expect(find.text('This code is invalid or no longer available. Try again.'), findsOneWidget);
    expect(find.textContaining('server text'), findsNothing);
    expect(tester.widget<TextField>(_key('thunderid-field-user_code')).controller?.text, 'NOPE-NOPE');
  });

  testWidgets('shows the device was denied when the flow refuses it', (tester) async {
    server
      ..callback = _json(400, {'error': 'access_denied'})
      ..flowAnswers.add(
        _json(200, {
          'executionId': 'exec-1',
          'flowStatus': 'ERROR',
          'errorAssertion': 'jwt-error',
          'failureReason': 'Denied',
          'data': {
            'additionalData': {'authId': 'auth-1', 'callbackType': 'device'},
          },
        }),
      );
    final outcomes = <DeviceGrantResult>[];
    await tester.pumpWidget(_app(server, DeviceGrant(userCode: 'WDJB-MJHT', onComplete: outcomes.add)));
    await tester.pumpAndSettle();

    expect(outcomes, [DeviceGrantResult.denied]);
    expect(find.text('Device not authorized'), findsOneWidget);
  });

  testWidgets('reports a flow that cannot start with a translated message', (tester) async {
    server.flowAnswers.add(_json(500, {'code': 'SSE-5000', 'message': 'server text'}));
    final errors = <String>[];
    await tester.pumpWidget(_app(server, DeviceGrant(onError: errors.add)));
    await tester.pumpAndSettle();

    expect(errors, ['Could not start device verification. Please try again.']);
    expect(_key('thunderid-device-grant-result-failed'), findsOneWidget);
    expect(find.textContaining('server text'), findsNothing);
  });

  testWidgets('ends as expired when the step times out first', (tester) async {
    final deadline = DateTime.now().add(const Duration(seconds: 1)).millisecondsSinceEpoch;
    server.flowAnswers.add(
      _json(200, {
        ..._codeStep,
        'data': {
          ...(_codeStep['data']! as Map<String, Object>),
          'additionalData': {'stepTimeout': deadline},
        },
      }),
    );
    final outcomes = <DeviceGrantResult>[];
    await tester.pumpWidget(_app(server, DeviceGrant(onComplete: outcomes.add)));
    await tester.pumpAndSettle();
    expect(outcomes, isEmpty);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(outcomes, [DeviceGrantResult.expired]);
    expect(find.text('Code expired'), findsOneWidget);
  });

  testWidgets('renders a server-described step with tagged fields and actions', (tester) async {
    server.flowAnswers
      ..add(
        _json(200, {
          'executionId': 'exec-1',
          'flowStatus': 'INCOMPLETE',
          'data': {
            'inputs': [
              {'identifier': 'user_code', 'type': 'TEXT_INPUT'},
            ],
            'actions': [
              {'ref': 'approve', 'nextNode': 'end'},
            ],
            'meta': {
              'components': [
                {'type': 'TEXT_INPUT', 'id': 'c1', 'ref': 'user_code', 'label': 'Code'},
                {'type': 'ACTION', 'id': 'approve', 'ref': 'approve', 'label': 'Approve', 'eventType': 'SUBMIT'},
              ],
            },
          },
        }),
      )
      ..add(_json(200, _approved));
    await tester.pumpWidget(_app(server, const DeviceGrant(userCode: 'WDJB-MJHT')));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(_key('thunderid-field-user_code')).controller?.text, 'WDJB-MJHT');
    await tester.tap(_key('thunderid-action-approve'));
    await tester.pumpAndSettle();

    expect(server.flowBodies.last['action'], 'approve');
    expect(server.flowBodies.last['inputs'], {'user_code': 'WDJB-MJHT'});
    expect(find.text('Device authorized'), findsOneWidget);
  });

  testWidgets('hands the step, values and submit to a custom builder', (tester) async {
    server.flowAnswers
      ..add(_json(200, _codeStep))
      ..add(_json(200, _approved));
    await tester.pumpWidget(
      _app(
        server,
        DeviceGrant(
          builder: (context, state) {
            if (state.result != null) return Text('custom ${state.result!.name}');
            if (state.inputs.isEmpty) return const Text('custom loading');
            return Column(
              children: [
                TextField(key: const Key('custom-code'), onChanged: (v) => state.onValueChanged('user_code', v)),
                TextButton(onPressed: () => state.submit(), child: const Text('custom submit')),
              ],
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_key('thunderid-device-grant'), findsNothing);

    await tester.enterText(_key('custom-code'), 'ABCD-EFGH');
    await tester.tap(find.text('custom submit'));
    await tester.pumpAndSettle();
    expect(server.flowBodies.last['inputs'], {'user_code': 'ABCD-EFGH'});
    expect(find.text('custom approved'), findsOneWidget);
  });

  testWidgets('BaseDeviceGrant works without a provider and submits the only action', (tester) async {
    final submitted = <(String?, Map<String, String>)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BaseDeviceGrant(
            step: EmbeddedFlowResponse.fromMap({
              'flowId': 'exec-1',
              'flowStatus': 'INCOMPLETE',
              'data': {
                'inputs': [
                  {'name': 'user_code', 'type': 'TEXT_INPUT'},
                ],
                'actions': [
                  {'ref': 'continue', 'label': 'Continue'},
                ],
              },
            }),
            initialValues: const {'user_code': 'WDJB-MJHT'},
            onSubmit: (action, inputs) => submitted.add((action, inputs)),
          ),
        ),
      ),
    );
    await tester.tap(_key('thunderid-action-continue'));
    expect(submitted.single.$1, 'continue');
    expect(submitted.single.$2, {'user_code': 'WDJB-MJHT'});
  });
}
