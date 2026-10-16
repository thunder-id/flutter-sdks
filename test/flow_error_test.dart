// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/flow_template_resolver.dart';
import 'package:thunderid_flutter/src/models/flow_models.dart';
import 'package:thunderid_flutter/src/models/thunderid_config.dart';
import 'package:thunderid_flutter/src/widgets/sign_up.dart';
import 'package:thunderid_flutter/src/widgets/thunderid_provider.dart';

const _sdkChannel = MethodChannel('dev.thunderid/sdk');

const Map<String, dynamic> _meta = {
  'i18n': {
    'translations': {
      'errors': {'user.exists': 'El usuario {{param(name)}} ya existe'},
      'system': {'generic': 'Algo salió mal'},
      'partial': {'missing': 'Falta {{param(other)}}'},
    },
  },
};

const _resolver = FlowTemplateResolver(_meta);

final Map<String, dynamic> _errorResponse = <String, dynamic>{
  'flowStatus': 'ERROR',
  'failureReason': 'User alice already exists',
  'error': {
    'code': 'FET-1007',
    'message': {
      'key': 'errors.user.exists',
      'defaultValue': 'User alice already exists',
      'params': {'name': 'alice'},
    },
  },
};

void main() {
  group('FlowTemplateResolver.translate', () {
    test('substitutes params into the key\'s translation', () {
      final text = EmbeddedFlowResponse.fromMap(_errorResponse).errorMessage;
      expect(_resolver.translate(text), 'El usuario alice ya existe');
    });

    test('falls back to the system namespace', () {
      expect(_resolver.translate(const FlowErrorText(key: 'generic')), 'Algo salió mal');
    });

    test('substitutes in one pass, so a param value is not expanded again', () {
      const text = FlowErrorText(key: 'errors.user.exists', params: {'name': '{{param(name)}}'});
      expect(_resolver.translate(text), isNull);
    });

    test('returns null when there is no key, no translation, or an unfilled param', () {
      expect(_resolver.translate(null), isNull);
      expect(_resolver.translate(const FlowErrorText(defaultValue: 'x')), isNull);
      expect(_resolver.translate(const FlowErrorText(key: 'errors.unknown')), isNull);
      expect(_resolver.translate(const FlowErrorText(key: 'partial.missing')), isNull);
    });
  });

  testWidgets('SignUp shows the translated flow error over the English failureReason', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _sdkChannel,
      (call) async => switch (call.method) {
        'initialize' => true,
        'isSignedIn' => false,
        'signUp' => _errorResponse,
        'getFlowMeta' => _meta,
        _ => null,
      },
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ThunderIDProvider(
            config: ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'test'),
            child: SignUp(applicationId: 'app-1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('El usuario alice ya existe'), findsOneWidget);
    expect(find.text('User alice already exists'), findsNothing);
  });
}
