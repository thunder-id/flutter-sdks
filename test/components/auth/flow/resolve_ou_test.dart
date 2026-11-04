// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/components/auth/flow/flow_form.dart';
import 'package:thunderid_flutter/src/models/flow_models.dart';

// The Resolve OU step of a sign-in flow, rendered from the server's description like any step.

EmbeddedFlowResponse _step(Map<String, dynamic> data) =>
    EmbeddedFlowResponse(flowId: 'flow-1', flowStatus: FlowStatus.promptOnly, data: data);

void main() {
  late List<(String, Map<String, String>)> submitted;

  setUp(() => submitted = []);

  Future<void> pump(WidgetTester tester, EmbeddedFlowResponse step) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlowForm(
              applicationId: '',
              currentStep: step,
              isLoading: false,
              error: null,
              submit: (actionId, inputs) async => submitted.add((actionId, inputs)),
            ),
          ),
        ),
      );

  testWidgets('before sign-in, the user types the unit: nothing is listed', (tester) async {
    await pump(
      tester,
      _step({
        'inputs': [
          {'ref': 'ou_selection_input', 'identifier': 'ouId', 'type': 'OU_SELECT', 'required': true},
        ],
        'actions': [
          {'ref': 'action_ou', 'nextNode': 'auth'},
        ],
        'additionalData': {'rootOuId': 'ou-root'},
        'meta': {
          'components': [
            {'id': 'ou_selection_input', 'ref': 'ouId', 'type': 'OU_SELECT', 'label': 'Organization'},
            {'id': 'action_ou', 'ref': 'action_ou', 'type': 'ACTION', 'label': 'Continue'},
          ],
        },
      }),
    );

    expect(find.byType(DropdownButton<String>), findsNothing);
    final field = find.byKey(const Key('thunderid-field-ouId'));
    expect(field, findsOneWidget);
    await tester.enterText(field, 'engineering');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(submitted.single.$1, 'action_ou');
    expect(submitted.single.$2, {'ouId': 'engineering'});
  });

  testWidgets('after sign-in, the offered units are picked from a list', (tester) async {
    await pump(
      tester,
      _step({
        'inputs': [
          {
            'ref': 'ou_selection_input',
            'identifier': 'ouId',
            'type': 'SELECT',
            'required': true,
            'options': ['acme/east', 'acme/west'],
          },
        ],
        'actions': [
          {'ref': 'action_ou', 'nextNode': 'assert'},
        ],
      }),
    );

    expect(find.byType(DropdownButton<String>), findsOneWidget);
    await tester.tap(find.byKey(const Key('thunderid-field-ouId')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('acme/west').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('thunderid-action-action_ou')));
    await tester.pump();
    expect(submitted.single.$2, {'ouId': 'acme/west'});
  });

  testWidgets('a select component carries its own options as value and label', (tester) async {
    await pump(
      tester,
      _step({
        'inputs': [
          {'identifier': 'ouId', 'type': 'SELECT'},
        ],
        'actions': [
          {'ref': 'action_ou'},
        ],
        'meta': {
          'components': [
            {
              'category': 'FIELD',
              'ref': 'ouId',
              'type': 'SELECT',
              'label': 'Organization unit',
              'options': [
                {'value': 'ou-1', 'label': 'East'},
                {'value': 'ou-2', 'label': 'West'},
              ],
            },
            {'ref': 'action_ou', 'type': 'ACTION', 'label': 'Continue'},
          ],
        },
      }),
    );

    expect(find.text('Organization unit'), findsOneWidget);
    await tester.tap(find.byKey(const Key('thunderid-field-ouId')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('East').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(submitted.single.$2, {'ouId': 'ou-1'});
  });
}
