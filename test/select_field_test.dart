// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

const _jane = SelectOption('Jane Doe', 'user-1');
const _john = SelectOption('John Roe', 'user-2');

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.thunderid/sdk'),
      (call) async {
        switch (call.method) {
          case 'initialize':
            return true;
          case 'isSignedIn':
            return false;
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dev.thunderid/sdk'), null);
  });

  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(
          body: ThunderIDProvider(
            config: const ThunderIDConfig(baseUrl: 'https://localhost:8090', clientId: 'test'),
            child: child,
          ),
        ),
      );

  /// A field whose props the test changes through [rebuild], the way an owner would.
  late void Function(VoidCallback) rebuild;
  var value = '';
  var options = <SelectOption>[_jane, _john];
  var required = false;
  var enabled = true;
  var loading = false;
  VoidCallback? onLoadMore;
  String? emptyText;
  String? errorText;
  SelectOption? selectedOption;
  final changes = <String>[];

  setUp(() {
    value = '';
    options = <SelectOption>[_jane, _john];
    required = false;
    enabled = true;
    loading = false;
    onLoadMore = null;
    emptyText = null;
    errorText = null;
    selectedOption = null;
    changes.clear();
  });

  Future<void> pumpField(WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return SelectField(
              name: 'owner',
              label: 'Owner',
              value: value,
              options: options,
              required: required,
              enabled: enabled,
              loading: loading,
              onLoadMore: onLoadMore,
              emptyText: emptyText,
              errorText: errorText,
              selectedOption: selectedOption,
              onChanged: (next) {
                changes.add(next);
                rebuild(() => value = next);
              },
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byType(SelectField));
    await tester.pumpAndSettle();
  }

  /// Changes the owner's props. The open page follows a frame later, so two frames are pumped.
  Future<void> change(WidgetTester tester, VoidCallback update) async {
    rebuild(update);
    await tester.pump();
    await tester.pump();
  }

  group('SelectField', () {
    testWidgets('shows the placeholder until something is chosen', (tester) async {
      await pumpField(tester);

      expect(find.text('Select an option'), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);
    });

    testWidgets('opening lists the options without choosing anything', (tester) async {
      await pumpField(tester);
      await open(tester);

      expect(find.text('Jane Doe'), findsOneWidget);
      expect(find.text('John Roe'), findsOneWidget);
      expect(changes, isEmpty);
    });

    testWidgets('choosing an option reports its value, closes the page and shows its label',
        (tester) async {
      await pumpField(tester);
      await open(tester);
      await tester.tap(find.text('Jane Doe'));
      await tester.pumpAndSettle();

      expect(changes, ['user-1']);
      expect(find.byType(CloseButton), findsNothing);
      expect(find.text('Jane Doe'), findsOneWidget);
    });

    testWidgets('the label stays after reopening and closing without choosing again',
        (tester) async {
      await pumpField(tester);
      await open(tester);
      await tester.tap(find.text('Jane Doe'));
      await tester.pumpAndSettle();

      await open(tester);
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();

      expect(changes, ['user-1']);
      expect(find.text('Jane Doe'), findsOneWidget);
    });

    testWidgets('a value set from outside is labelled by the loaded option, else by itself',
        (tester) async {
      value = 'user-2';
      await pumpField(tester);

      expect(find.text('John Roe'), findsOneWidget);

      await change(tester, () => value = 'user-9');

      expect(find.text('user-9'), findsOneWidget);
      expect(find.text('John Roe'), findsNothing);

      await change(tester, () => value = '');

      expect(find.text('Select an option'), findsOneWidget);
    });

    testWidgets('selectedOption labels a value that is not among the options', (tester) async {
      value = 'user-9';
      selectedOption = const SelectOption('Saved Person', 'user-9');
      await pumpField(tester);

      expect(find.text('Saved Person'), findsOneWidget);

      await open(tester);

      expect(find.text('Saved Person'), findsOneWidget);
      expect(find.text('Jane Doe'), findsOneWidget);
    });

    testWidgets('the option last picked keeps labelling its value after the options are replaced',
        (tester) async {
      await pumpField(tester);
      await open(tester);
      await tester.tap(find.text('Jane Doe'));
      await tester.pumpAndSettle();

      await change(tester, () => options = <SelectOption>[_john]);

      expect(find.text('Jane Doe'), findsOneWidget);
    });

    testWidgets('the placeholder row clears the choice', (tester) async {
      value = 'user-1';
      await pumpField(tester);
      await open(tester);

      expect(find.byKey(const Key('thunderid-option-clear')), findsOneWidget);

      await tester.tap(find.byKey(const Key('thunderid-option-clear')));
      await tester.pumpAndSettle();

      expect(changes, ['']);
      expect(find.text('Select an option'), findsOneWidget);
    });

    testWidgets('a required field cannot be cleared and is marked as required', (tester) async {
      value = 'user-1';
      required = true;
      await pumpField(tester);

      expect(find.text('Owner *'), findsOneWidget);

      await open(tester);
      await tester.tap(find.byKey(const Key('thunderid-option-clear')));
      await tester.pumpAndSettle();

      expect(changes, isEmpty);
      expect(find.byType(CloseButton), findsOneWidget);
    });

    testWidgets('a disabled field does not open', (tester) async {
      enabled = false;
      await pumpField(tester);
      await tester.tap(find.byType(SelectField));
      await tester.pumpAndSettle();

      expect(find.byType(CloseButton), findsNothing);
    });

    testWidgets('a disabled option cannot be chosen', (tester) async {
      options = <SelectOption>[const SelectOption('Suspended User', 'user-1', disabled: true)];
      await pumpField(tester);
      await open(tester);
      await tester.tap(find.text('Suspended User'));
      await tester.pumpAndSettle();

      expect(changes, isEmpty);
      expect(find.byType(CloseButton), findsOneWidget);
    });

    testWidgets('shows the error text under the field', (tester) async {
      errorText = 'Pick an owner';
      await pumpField(tester);

      expect(find.text('Pick an owner'), findsOneWidget);
    });

    testWidgets('without onLoadMore there is no Load more row', (tester) async {
      await pumpField(tester);
      await open(tester);

      expect(find.text('Load more'), findsNothing);
    });

    testWidgets('Load more asks for more options and never changes the selection',
        (tester) async {
      var asked = 0;
      value = 'user-1';
      onLoadMore = () => asked += 1;
      await pumpField(tester);
      await open(tester);

      expect(find.text('Load more'), findsOneWidget);

      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      expect(asked, 1);
      expect(changes, isEmpty);
      expect(find.byType(CloseButton), findsOneWidget);
    });

    testWidgets('while more options load, the row reads Loading more and cannot be chosen',
        (tester) async {
      var asked = 0;
      loading = true;
      onLoadMore = () => asked += 1;
      await tester.pumpWidget(const SizedBox());
      await pumpField(tester);
      await tester.tap(find.byType(SelectField));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Loading more…'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
      expect(asked, 0);
    });

    testWidgets('the first load shows Loading and no Load more row', (tester) async {
      options = <SelectOption>[];
      loading = true;
      onLoadMore = () {};
      await pumpField(tester);
      await tester.tap(find.byType(SelectField));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Loading…'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
    });

    testWidgets('an empty final list shows the empty text', (tester) async {
      options = <SelectOption>[];
      await pumpField(tester);
      await open(tester);

      expect(find.text('No results found.'), findsOneWidget);
    });

    testWidgets('an empty list can say it in its own words', (tester) async {
      options = <SelectOption>[];
      emptyText = 'No owners yet';
      await pumpField(tester);
      await open(tester);

      expect(find.text('No owners yet'), findsOneWidget);
    });

    testWidgets('an empty list that can load more offers Load more, not the empty text',
        (tester) async {
      options = <SelectOption>[];
      onLoadMore = () {};
      await pumpField(tester);
      await open(tester);

      expect(find.text('No results found.'), findsNothing);
      expect(find.text('Load more'), findsOneWidget);
    });

    testWidgets('options appended while the page is open show up in it', (tester) async {
      await pumpField(tester);
      await open(tester);

      expect(find.text('Carol Lee'), findsNothing);

      await change(
        tester,
        () => options = <SelectOption>[_jane, _john, const SelectOption('Carol Lee', 'user-3')],
      );

      expect(find.text('Carol Lee'), findsOneWidget);
    });

    testWidgets('the Load more row follows the loading state while the page is open',
        (tester) async {
      onLoadMore = () {};
      await pumpField(tester);
      await open(tester);

      expect(find.text('Load more'), findsOneWidget);

      await change(tester, () => loading = true);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Loading more…'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);

      await change(tester, () {
        loading = false;
        onLoadMore = null;
      });

      expect(find.text('Load more'), findsNothing);
      expect(find.text('Loading more…'), findsNothing);
    });
  });

  group('SelectField with an InfiniteOptionsController', () {
    testWidgets('lists three pages in place, offers Load more until the data ends, and picks a row',
        (tester) async {
      final offsets = <int>[];
      final controller = InfiniteOptionsController<int>(
        load: (context) async {
          final offset = context.cursor ?? 0;
          offsets.add(offset);
          final count = offset == 60 ? 15 : 30;
          return SelectOptionsBatch<int>.page(
            [
              for (var i = offset; i < offset + count; i++) SelectOption('User ${i + 1}', 'user-${i + 1}'),
            ],
            nextCursor: offset + count < 75 ? offset + count : null,
          );
        },
      )..loadMore();
      addTearDown(controller.dispose);
      var value = '';

      await tester.pumpWidget(
        wrap(
          StatefulBuilder(
            builder: (context, setState) => ListenableBuilder(
              listenable: controller,
              builder: (context, _) => SelectField(
                name: 'owner',
                label: 'Owner',
                value: value,
                options: controller.options,
                loading: controller.loading,
                onLoadMore: controller.hasMore ? controller.loadMore : null,
                onChanged: (next) => setState(() => value = next),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SelectField));
      await tester.pumpAndSettle();

      final loadMore = find.byKey(const Key('thunderid-load-more-owner'));
      Future<void> tapLoadMore() async {
        await tester.dragUntilVisible(loadMore, find.byType(ListView), const Offset(0, -300));
        await tester.tap(loadMore);
        await tester.pumpAndSettle();
      }

      expect(offsets, [0]);
      expect(find.byKey(const Key('thunderid-option-user-1')), findsOneWidget);

      await tapLoadMore();
      await tapLoadMore();

      expect(offsets, [0, 30, 60]);
      expect(controller.options, hasLength(75));
      expect(find.byKey(const Key('thunderid-load-more-owner')), findsNothing);

      await tester.dragUntilVisible(
        find.byKey(const Key('thunderid-option-user-75')),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.tap(find.byKey(const Key('thunderid-option-user-75')));
      await tester.pumpAndSettle();

      expect(value, 'user-75');
      expect(find.text('User 75'), findsOneWidget);
    });
  });

  group('SelectField accessibility', () {
    testWidgets('the trigger is one button naming the label, the choice and that it is required',
        (tester) async {
      final semantics = tester.ensureSemantics();
      required = true;
      value = 'user-1';
      await pumpField(tester);

      expect(find.bySemanticsLabel('Owner, required'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Owner, required')),
        isSemantics(label: 'Owner, required', value: 'Jane Doe', isButton: true),
      );
      semantics.dispose();
    });

    testWidgets('the chosen row is marked selected and the others are not', (tester) async {
      final semantics = tester.ensureSemantics();
      value = 'user-1';
      await pumpField(tester);
      await open(tester);

      expect(
        tester.getSemantics(find.byKey(const Key('thunderid-option-user-1'))),
        isSemantics(isSelected: true),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('thunderid-option-user-2'))),
        isNot(isSemantics(isSelected: true)),
      );
      semantics.dispose();
    });

    testWidgets('the empty row of a field with no choice is marked selected', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpField(tester);
      await open(tester);

      expect(
        tester.getSemantics(find.byKey(const Key('thunderid-option-clear'))),
        isSemantics(isSelected: true),
      );
      semantics.dispose();
    });

    testWidgets('a progress row is announced as a live region', (tester) async {
      final semantics = tester.ensureSemantics();
      options = <SelectOption>[];
      loading = true;
      onLoadMore = () {};
      await pumpField(tester);
      await tester.tap(find.byType(SelectField));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        tester.getSemantics(find.text('Loading…')),
        isSemantics(label: 'Loading…', isLiveRegion: true),
      );
      semantics.dispose();
    });
  });
}
