// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/components/auth/buttons/github_button.dart';
import 'package:thunderid_flutter/src/components/auth/buttons/google_button.dart';
import 'package:thunderid_flutter/src/components/auth/buttons/outlined_trigger_button.dart';

void main() {
  testWidgets('GoogleButton renders its brand glyph and label without throwing',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoogleButton(onPressed: () => tapped = true),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Continue with Google'), findsOneWidget);

    await tester.tap(find.byType(OutlinedButton));
    expect(tapped, true);
  });

  testWidgets('GitHubButton renders its brand glyph and label without throwing',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GitHubButton(onPressed: () {}),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Continue with GitHub'), findsOneWidget);
  });

  testWidgets(
      'OutlinedTriggerButton falls back to the schema label when loading',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OutlinedTriggerButton(
            label: 'Continue with Acme',
            isLoading: true,
            onPressed: () {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(button.onPressed, isNull);
  });
}
