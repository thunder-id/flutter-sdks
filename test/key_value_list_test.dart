// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thunderid_flutter/src/models/flow_models.dart';
import 'package:thunderid_flutter/src/models/thunderid_config.dart';
import 'package:thunderid_flutter/src/widgets/flow_form.dart';
import 'package:thunderid_flutter/src/widgets/thunderid_provider.dart';

const _config = ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'test');
const _sdkChannel = MethodChannel('dev.thunderid/sdk');

final Map<String, dynamic> _flowMeta = <String, dynamic>{
  'i18n': <String, dynamic>{
    'translations': <String, dynamic>{
      'signin': <String, dynamic>{
        'forms.link_prompt.title': 'Link your account',
        'forms.link_prompt.actions.confirm.label': 'Link account',
        'forms.link_prompt.actions.reject.label': 'No, I want a separate account',
      },
    },
  },
};

/// The account-linking prompt as the bridge hands it to Dart: a KEY_VALUE_LIST bound to
/// `linkingPromptDetails`, whose pairs arrive JSON-encoded under that key in `additionalData`.
EmbeddedFlowResponse _linkingStep(String details) => EmbeddedFlowResponse(
      flowStatus: FlowStatus.promptOnly,
      type: 'VIEW',
      data: <String, dynamic>{
        'actions': [
          {'id': 'action_confirm', 'ref': 'action_confirm', 'nextNode': 'credentials_auth'},
          {'id': 'action_reject', 'ref': 'action_reject', 'nextNode': 'linking'},
        ],
        'additionalData': <String, dynamic>{'linkingPromptDetails': details},
        'meta': <String, dynamic>{
          'components': [
            {
              'category': 'DISPLAY',
              'id': 'text_title',
              'type': 'TEXT',
              'variant': 'HEADING_3',
              'label': '{{ t(signin:forms.link_prompt.title) }}',
            },
            {'category': 'DISPLAY', 'id': 'kv_001', 'type': 'KEY_VALUE_LIST', 'source': 'linkingPromptDetails'},
            {
              'category': 'BLOCK',
              'id': 'block_001',
              'type': 'BLOCK',
              'components': [
                {
                  'category': 'ACTION',
                  'id': 'action_confirm',
                  'type': 'ACTION',
                  'variant': 'PRIMARY',
                  'eventType': 'SUBMIT',
                  'label': '{{ t(signin:forms.link_prompt.actions.confirm.label) }}',
                },
                {
                  'category': 'ACTION',
                  'id': 'action_reject',
                  'type': 'ACTION',
                  'variant': 'SECONDARY',
                  'eventType': 'SUBMIT',
                  'label': '{{ t(signin:forms.link_prompt.actions.reject.label) }}',
                },
              ],
            },
          ],
        },
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KeyValuePair.list', () {
    test('parses a JSON-encoded list in order', () {
      expect(
        KeyValuePair.list('[{"label":"Email","value":"alice@example.com"},{"label":"Username","value":"alice"}]'),
        const [
          KeyValuePair(label: 'Email', value: 'alice@example.com'),
          KeyValuePair(label: 'Username', value: 'alice'),
        ],
      );
    });

    test('accepts an already decoded list', () {
      expect(
        KeyValuePair.list([
          {'label': 'Email', 'value': 'alice@example.com'},
        ]),
        const [KeyValuePair(label: 'Email', value: 'alice@example.com')],
      );
    });

    test('drops entries that are not objects or carry no value', () {
      expect(
        KeyValuePair.list(
          '[{"label":"Email","value":"alice@example.com"},{"label":"Empty","value":""},'
          '{"label":"Missing"},{"label":"Number","value":42},"row",null,["Email","a"]]',
        ),
        const [KeyValuePair(label: 'Email', value: 'alice@example.com')],
      );
    });

    test('defaults a missing label to empty', () {
      expect(
        KeyValuePair.list('[{"value":"alice@example.com"}]'),
        const [KeyValuePair(label: '', value: 'alice@example.com')],
      );
    });

    test('returns no pairs for anything that is not a list', () {
      expect(KeyValuePair.list(null), isEmpty);
      expect(KeyValuePair.list(''), isEmpty);
      expect(KeyValuePair.list('not json'), isEmpty);
      expect(KeyValuePair.list('{"label":"Email","value":"alice@example.com"}'), isEmpty);
    });
  });

  group('isOutlinedVariant', () {
    test('outlines secondary and outlined actions', () {
      expect(isOutlinedVariant('SECONDARY'), isTrue);
      expect(isOutlinedVariant('secondary'), isTrue);
      expect(isOutlinedVariant('OUTLINED'), isTrue);
    });

    test('keeps primary and missing variants filled', () {
      expect(isOutlinedVariant('PRIMARY'), isFalse);
      expect(isOutlinedVariant(''), isFalse);
    });
  });

  group('FlowForm account-linking prompt', () {
    late List<String> submitted;

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_sdkChannel, null);
    });

    Future<void> pumpStep(WidgetTester tester, EmbeddedFlowResponse step) async {
      submitted = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        _sdkChannel,
        (call) async => switch (call.method) {
          'initialize' => true,
          'isSignedIn' => false,
          'getFlowMeta' => _flowMeta,
          _ => null,
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThunderIDProvider(
              config: _config,
              child: FlowForm(
                applicationId: 'app-1',
                currentStep: step,
                isLoading: false,
                error: null,
                submit: (actionId, inputs) async => submitted.add(actionId),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders the matched pairs from additionalData', (tester) async {
      await pumpStep(
        tester,
        _linkingStep('[{"label":"Email","value":"alice@example.com"},{"label":"Username","value":"alice"}]'),
      );

      expect(find.byType(Table), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('alice@example.com'), findsOneWidget);
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
    });

    testWidgets('announces each row as one label and value pair', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpStep(tester, _linkingStep('[{"label":"Email","value":"alice@example.com"}]'));

      expect(find.bySemanticsLabel('Email: alice@example.com'), findsOneWidget);
      expect(find.bySemanticsLabel('alice@example.com'), findsNothing);
      semantics.dispose();
    });

    testWidgets('renders nothing for the list when the source holds no pairs', (tester) async {
      await pumpStep(tester, _linkingStep('[]'));

      expect(find.byType(Table), findsNothing);
      expect(find.text('Link your account'), findsOneWidget);
    });

    testWidgets('renders confirm filled and reject outlined, each submitting its own action', (tester) async {
      await pumpStep(tester, _linkingStep('[{"label":"Email","value":"alice@example.com"}]'));

      final confirm = find.byKey(const Key('thunderid-action-action_confirm'));
      final reject = find.byKey(const Key('thunderid-action-action_reject'));
      expect(tester.widget(confirm), isA<FilledButton>());
      expect(tester.widget(reject), isA<OutlinedButton>());
      expect(find.text('Link account'), findsOneWidget);
      expect(find.text('No, I want a separate account'), findsOneWidget);

      await tester.tap(reject);
      await tester.tap(confirm);
      expect(submitted, ['action_reject', 'action_confirm']);
    });
  });
}
