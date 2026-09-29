// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thunderid_flutter/src/models/flow_models.dart';
import 'package:thunderid_flutter/src/models/thunderid_config.dart';
import 'package:thunderid_flutter/src/widgets/adapters/github_button.dart';
import 'package:thunderid_flutter/src/widgets/adapters/google_button.dart';
import 'package:thunderid_flutter/src/widgets/flow_form.dart';
import 'package:thunderid_flutter/src/widgets/thunderid_provider.dart';

const _config =
    ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'test');
const _sdkChannel = MethodChannel('dev.thunderid/sdk');

final Map<String, dynamic> _flowMeta = <String, dynamic>{
  'i18n': <String, dynamic>{
    'translations': <String, dynamic>{
      'signin': <String, dynamic>{
        'forms.credentials.fields.username.label': 'Username',
        'forms.credentials.fields.username.placeholder': 'Enter your username',
        'forms.credentials.fields.password.label': 'Password',
        'forms.credentials.fields.password.placeholder': 'Enter your password',
        'forms.credentials.links.forgot_password.prefix': '',
        'forms.credentials.links.forgot_password.label': 'Forgot password?',
        'forms.credentials.links.sign_up.prefix': "Don't have an account?",
        'forms.credentials.links.sign_up.label': 'Sign up',
      },
    },
  },
  'application': <String, dynamic>{
    'forgot_password_url': 'https://example.com/forgot-password',
    'sign_up_url': 'https://example.com/sign-up',
  },
};

final Map<String, dynamic> _stepData = <String, dynamic>{
  'inputs': [
    {
      'ref': 'input_001',
      'identifier': 'username',
      'type': 'TEXT_INPUT',
      'required': true,
    },
    {
      'ref': 'input_002',
      'identifier': 'password',
      'type': 'PASSWORD_INPUT',
      'required': true,
    },
  ],
  'actions': [
    {'ref': 'action_001', 'nextNode': 'credentials_auth'},
    {'ref': 'action_xoc0', 'nextNode': 'ID_0e5o'},
    {'ref': 'action_zeye', 'nextNode': 'ID_dbxc'},
  ],
  'meta': <String, dynamic>{
    'components': [
      {
        'align': 'center',
        'category': 'DISPLAY',
        'id': 'text_001',
        'label': 'Login',
        'resourceType': 'ELEMENT',
        'type': 'TEXT',
        'variant': 'HEADING_1',
      },
      {
        'category': 'BLOCK',
        'components': [
          {
            'category': 'FIELD',
            'hint': '',
            'id': 'input_001',
            'inputType': 'text',
            'label': '{{ t(signin:forms.credentials.fields.username.label) }}',
            'placeholder':
                '{{ t(signin:forms.credentials.fields.username.placeholder) }}',
            'ref': 'username',
            'required': true,
            'resourceType': 'ELEMENT',
            'type': 'TEXT_INPUT',
          },
          {
            'category': 'FIELD',
            'hint': '',
            'id': 'input_002',
            'inputType': 'text',
            'label': '{{ t(signin:forms.credentials.fields.password.label) }}',
            'placeholder':
                '{{ t(signin:forms.credentials.fields.password.placeholder) }}',
            'ref': 'password',
            'required': true,
            'resourceType': 'ELEMENT',
            'type': 'PASSWORD_INPUT',
          },
          {
            'category': 'DISPLAY',
            'id': 'rich_text_forgot_password',
            'label':
                '<p class="rich-text-paragraph"><span class="rich-text-pre-wrap">{{ t(signin:forms.credentials.links.forgot_password.prefix) }} </span><a href="{{meta(application.forgot_password_url)}}" target="_blank" rel="noopener noreferrer" class="rich-text-link"><span class="rich-text-pre-wrap">{{ t(signin:forms.credentials.links.forgot_password.label) }}</span></a></p>',
            'resourceType': 'ELEMENT',
            'type': 'RICH_TEXT',
          },
          {
            'category': 'ACTION',
            'eventType': 'SUBMIT',
            'id': 'action_001',
            'label': '{{ t(signin:forms.credentials.actions.submit.label) }}',
            'resourceType': 'ELEMENT',
            'type': 'ACTION',
            'variant': 'PRIMARY',
          },
          {
            'category': 'DISPLAY',
            'id': 'rich_text_signup',
            'label':
                '<p class="rich-text-paragraph"><span class="rich-text-pre-wrap">{{ t(signin:forms.credentials.links.sign_up.prefix) }} </span><a href="{{meta(application.sign_up_url)}}" target="_blank" rel="noopener noreferrer" class="rich-text-link"><span class="rich-text-pre-wrap">{{ t(signin:forms.credentials.links.sign_up.label) }}</span></a></p>',
            'resourceType': 'ELEMENT',
            'type': 'RICH_TEXT',
          },
        ],
        'id': 'block_001',
        'resourceType': 'ELEMENT',
        'type': 'BLOCK',
      },
      {
        'category': 'DISPLAY',
        'id': 'display_tfae',
        'label': 'Or',
        'resourceType': 'ELEMENT',
        'type': 'DIVIDER',
        'variant': 'HORIZONTAL',
      },
      {
        'category': 'ACTION',
        'components': [
          {
            'category': 'ACTION',
            'eventType': 'TRIGGER',
            'id': 'action_xoc0',
            'image': 'assets/images/icons/google.svg',
            'label': 'Continue with Google',
            'resourceType': 'ELEMENT',
            'type': 'ACTION',
            'variant': 'OUTLINED',
          },
        ],
        'eventType': 'TRIGGER',
        'id': 'block_per3',
        'resourceType': 'ELEMENT',
        'type': 'BLOCK',
      },
      {
        'category': 'ACTION',
        'components': [
          {
            'category': 'ACTION',
            'eventType': 'TRIGGER',
            'id': 'action_zeye',
            'image': 'assets/images/icons/github.svg',
            'label': 'Continue with GitHub',
            'resourceType': 'ELEMENT',
            'type': 'ACTION',
            'variant': 'OUTLINED',
          },
        ],
        'eventType': 'TRIGGER',
        'id': 'block_dzuu',
        'resourceType': 'ELEMENT',
        'type': 'BLOCK',
      },
    ],
  },
};

final _step = EmbeddedFlowResponse(
  flowStatus: FlowStatus.promptOnly,
  data: _stepData,
  challengeToken:
      'efb3706d1a8db1a291da65cd49e213af6e63fe6379006dfbd96d545d3a920119',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sdkChannel, null);
  });

  Widget buildForm() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sdkChannel, (call) async {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'isSignedIn':
          return false;
        case 'getFlowMeta':
          return _flowMeta;
        default:
          return null;
      }
    });

    return MaterialApp(
      home: Scaffold(
        body: ThunderIDProvider(
          config: _config,
          child: FlowForm(
            applicationId: 'app-1',
            currentStep: _step,
            isLoading: false,
            error: null,
            submit: (actionId, inputs) async {},
          ),
        ),
      ),
    );
  }

  group('FlowForm meta.components rendering', () {
    testWidgets('renders a Divider for DIVIDER components', (tester) async {
      await tester.pumpWidget(buildForm());
      await tester.pumpAndSettle();

      expect(find.byType(Divider), findsWidgets);
    });

    testWidgets('renders tappable rich-text links for RICH_TEXT components',
        (tester) async {
      await tester.pumpWidget(buildForm());
      await tester.pumpAndSettle();

      final richTextFinder = find.byWidgetPredicate((widget) {
        if (widget is! Text) return false;
        final span = widget.textSpan;
        if (span == null) return false;
        var hasLink = false;
        span.visitChildren((child) {
          if (child is TextSpan && child.recognizer is TapGestureRecognizer) {
            hasLink = true;
          }
          return true;
        });
        return hasLink;
      });
      expect(richTextFinder, findsWidgets);
    });

    testWidgets('resolves the field placeholder instead of the capitalized ref',
        (tester) async {
      await tester.pumpWidget(buildForm());
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField).first);
      final hintText = field.decoration?.hintText;
      expect(hintText, isNotNull);
      expect(hintText, isNot(contains('{{')));
      expect(hintText, 'Enter your username');
    });

    testWidgets(
        'renders branded buttons for ACTION components nested inside a '
        'category:ACTION wrapper block', (tester) async {
      await tester.pumpWidget(buildForm());
      await tester.pumpAndSettle();

      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Continue with GitHub'), findsOneWidget);
      expect(find.byType(GoogleButton), findsOneWidget);
      expect(find.byType(GitHubButton), findsOneWidget);
    });

    testWidgets(
        'tapping a data-action-ref sign-up link submits the matching action '
        'instead of trying to navigate the href="#" placeholder',
        (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_sdkChannel, (call) async {
        switch (call.method) {
          case 'initialize':
            return true;
          case 'isSignedIn':
            return false;
          case 'getFlowMeta':
            return _flowMeta;
          default:
            return null;
        }
      });

      final submittedActionIds = <String>[];
      final sentinelStep = EmbeddedFlowResponse(
        flowStatus: FlowStatus.promptOnly,
        data: <String, dynamic>{
          'inputs': _stepData['inputs'],
          'actions': [
            {'ref': 'action_001', 'nextNode': 'credentials_auth'},
            {'ref': 'action_signup', 'nextNode': 'call_registration'},
          ],
          'meta': <String, dynamic>{
            'components': [
              {
                'category': 'DISPLAY',
                'id': 'rich_text_signup',
                'label':
                    '<p data-component-ref="self-sign-up-link"><span class="rich-text-pre-wrap">Don\'t have an account? </span><a href="#" data-action-ref="action_signup" class="rich-text-link"><span class="rich-text-pre-wrap">Sign up</span></a></p>',
                'resourceType': 'ELEMENT',
                'type': 'RICH_TEXT',
              },
            ],
          },
        },
        challengeToken: 'token',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThunderIDProvider(
              config: _config,
              child: FlowForm(
                applicationId: 'app-1',
                currentStep: sentinelStep,
                isLoading: false,
                error: null,
                submit: (actionId, inputs) async {
                  submittedActionIds.add(actionId);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final richText = tester.widget<Text>(
        find.byWidgetPredicate((widget) {
          if (widget is! Text) return false;
          final span = widget.textSpan;
          if (span == null) return false;
          var hasLink = false;
          span.visitChildren((child) {
            if (child is TextSpan &&
                child.recognizer is TapGestureRecognizer) {
              hasLink = true;
            }
            return true;
          });
          return hasLink;
        }),
      );
      TapGestureRecognizer? linkRecognizer;
      richText.textSpan!.visitChildren((child) {
        if (child is TextSpan && child.recognizer is TapGestureRecognizer) {
          linkRecognizer = child.recognizer as TapGestureRecognizer;
        }
        return true;
      });
      expect(linkRecognizer, isNotNull);
      linkRecognizer!.onTap!();
      await tester.pumpAndSettle();

      expect(submittedActionIds, ['action_signup']);
    });

    testWidgets(
        'shows only the error banner and hides the stale prior-step form '
        'when an error is present', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_sdkChannel, (call) async {
        switch (call.method) {
          case 'initialize':
            return true;
          case 'isSignedIn':
            return false;
          case 'getFlowMeta':
            return _flowMeta;
          default:
            return null;
        }
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThunderIDProvider(
              config: _config,
              child: FlowForm(
                applicationId: 'app-1',
                currentStep: _step,
                isLoading: false,
                error: '[INVALID_INPUT] Bad request',
                submit: (actionId, inputs) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('[INVALID_INPUT] Bad request'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(GoogleButton), findsNothing);
      expect(find.byType(GitHubButton), findsNothing);
    });

    testWidgets(
        'skips a USER_SELECT input instead of rendering free text, and does not submit it',
        (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_sdkChannel, (call) async {
        switch (call.method) {
          case 'initialize':
            return true;
          case 'isSignedIn':
            return false;
          case 'getFlowMeta':
            return _flowMeta;
          default:
            return null;
        }
      });

      final step = EmbeddedFlowResponse(
        flowStatus: FlowStatus.promptOnly,
        data: <String, dynamic>{
          'inputs': [
            {'ref': 'input_username', 'identifier': 'username', 'type': 'TEXT_INPUT'},
            {'ref': 'input_owner', 'identifier': 'owner', 'type': 'USER_SELECT'},
          ],
          'actions': [
            {'ref': 'action_001', 'nextNode': 'submit'},
          ],
        },
        challengeToken: 'token',
      );

      Map<String, String>? submitted;
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
                submit: (actionId, inputs) async {
                  submitted = inputs;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byKey(const Key('thunderid-field-owner')), findsNothing);

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(submitted, isNotNull);
      expect(submitted!.keys, ['username']);
    });

    testWidgets('skips a USER_SELECT component whether or not the server tags it as a FIELD',
        (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_sdkChannel, (call) async {
        switch (call.method) {
          case 'initialize':
            return true;
          case 'isSignedIn':
            return false;
          case 'getFlowMeta':
            return _flowMeta;
          default:
            return null;
        }
      });

      final step = EmbeddedFlowResponse(
        flowStatus: FlowStatus.promptOnly,
        data: <String, dynamic>{
          'meta': {
            'components': [
              {'type': 'USER_SELECT', 'ref': 'owner_plain', 'label': 'Owner'},
              {'type': 'USER_SELECT', 'category': 'FIELD', 'ref': 'owner_field', 'label': 'Owner'},
            ],
          },
          'actions': [
            {'ref': 'action_001', 'nextNode': 'submit'},
          ],
        },
        challengeToken: 'token',
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
                submit: (actionId, inputs) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
    });
  });
}
