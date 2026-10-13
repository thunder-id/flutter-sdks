// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

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

  PagedSelectField<String> field({
    required FetchPagedOptions<String> fetch,
    TextEditingController? controller,
    PagedSelectOptionMapping<String>? mapping,
  }) =>
      PagedSelectField<String>(
        fieldRef: 'owner',
        controller: controller ?? TextEditingController(),
        label: 'Owner',
        fetchOptions: fetch,
        mapping: mapping,
      );

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byType(PagedSelectField<String>));
    await tester.pumpAndSettle();
  }

  group('PagedSelectField', () {
    testWidgets('opening loads the first page and lists the returned options', (tester) async {
      final requests = <PagedSelectRequest>[];
      await tester.pumpWidget(
        wrap(
          field(
            fetch: (request) async {
              requests.add(request);
              return const PagedSelectPage(
                options: [
                  PagedSelectOption('Jane Doe', 'user-1'),
                  PagedSelectOption('John Roe', 'user-2'),
                ],
                nextOffset: null,
                totalResults: 2,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await open(tester);

      expect(requests, hasLength(1));
      expect(requests.first.offset, 0);
      expect(requests.first.limit, 30);
      expect(find.text('Jane Doe'), findsOneWidget);
      expect(find.text('John Roe'), findsOneWidget);
    });

    testWidgets('selecting an option submits its value and shows its label on the trigger',
        (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        wrap(
          field(
            controller: controller,
            fetch: (request) async => const PagedSelectPage(
              options: [PagedSelectOption('Jane Doe', 'user-1')],
              nextOffset: null,
              totalResults: 1,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await open(tester);
      await tester.tap(find.text('Jane Doe'));
      await tester.pumpAndSettle();

      expect(controller.text, 'user-1');
      expect(find.text('Jane Doe'), findsOneWidget);
      expect(find.byType(CloseButton), findsNothing);
    });

    testWidgets('the label stays after reopening and closing without choosing again',
        (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        wrap(
          field(
            controller: controller,
            fetch: (request) async => const PagedSelectPage(
              options: [PagedSelectOption('Jane Doe', 'user-1')],
              nextOffset: null,
              totalResults: 1,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await open(tester);
      await tester.tap(find.text('Jane Doe'));
      await tester.pumpAndSettle();

      await open(tester);
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();

      expect(controller.text, 'user-1');
      expect(find.text('Jane Doe'), findsOneWidget);
    });

    testWidgets('an externally changed value does not keep the previous option label',
        (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        wrap(
          field(
            controller: controller,
            fetch: (request) async => const PagedSelectPage(
              options: [PagedSelectOption('Jane Doe', 'user-1')],
              nextOffset: null,
              totalResults: 1,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await open(tester);
      await tester.tap(find.text('Jane Doe'));
      await tester.pumpAndSettle();

      controller.text = 'user-9';
      await tester.pumpAndSettle();

      expect(find.text('Jane Doe'), findsNothing);
      expect(find.text('user-9'), findsOneWidget);

      controller.clear();
      await tester.pumpAndSettle();

      expect(find.text('Select an option'), findsOneWidget);
    });

    testWidgets('a disabled option cannot be selected', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        wrap(
          field(
            controller: controller,
            fetch: (request) async => const PagedSelectPage(
              options: [PagedSelectOption('Suspended User', 'user-1', disabled: true)],
              nextOffset: null,
              totalResults: 1,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await open(tester);
      await tester.tap(find.text('Suspended User'));
      await tester.pumpAndSettle();

      expect(controller.text, isEmpty);
      expect(find.byType(CloseButton), findsOneWidget);
    });

    testWidgets('a failed load shows the fallback error text with a working retry',
        (tester) async {
      var attempt = 0;
      await tester.pumpWidget(
        wrap(
          field(
            fetch: (request) async {
              attempt++;
              if (attempt == 1) throw Exception('boom');
              return const PagedSelectPage(
                options: [PagedSelectOption('Jane Doe', 'user-1')],
                nextOffset: null,
                totalResults: 1,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await open(tester);

      expect(find.text('Failed to load options.'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(attempt, 2);
      expect(find.text('Jane Doe'), findsOneWidget);
    });

    testWidgets('a short page with more to come offers Load more, and it stops at the last page',
        (tester) async {
      final offsets = <int>[];
      await tester.pumpWidget(
        wrap(
          field(
            fetch: (request) async {
              offsets.add(request.offset);
              return request.offset == 0
                  ? const PagedSelectPage(
                      options: [PagedSelectOption('Jane Doe', 'user-1')],
                      nextOffset: 30,
                      totalResults: 2,
                    )
                  : const PagedSelectPage(
                      options: [PagedSelectOption('John Roe', 'user-2')],
                      nextOffset: null,
                      totalResults: 2,
                    );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await open(tester);

      expect(find.text('Load more'), findsOneWidget);

      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      expect(offsets, [0, 30]);
      expect(find.text('John Roe'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
    });

    testWidgets('a page that maps to no options still leaves later pages reachable',
        (tester) async {
      final offsets = <int>[];
      await tester.pumpWidget(
        wrap(
          field(
            mapping: PagedSelectOptionMapping<String>(
              label: (item) => item,
              value: (item) => item == 'hidden' ? null : item,
            ),
            fetch: (request) async {
              offsets.add(request.offset);
              return request.offset == 0
                  ? const PagedSelectPage<String>(
                      items: ['hidden'],
                      nextOffset: 30,
                      totalResults: 31,
                    )
                  : const PagedSelectPage<String>(
                      items: ['user-31'],
                      nextOffset: null,
                      totalResults: 31,
                    );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await open(tester);

      expect(find.text('No options found.'), findsNothing);
      expect(find.text('Load more'), findsOneWidget);

      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      expect(offsets, [0, 30]);
      expect(find.text('user-31'), findsOneWidget);
    });

    testWidgets('an empty final list shows the empty message', (tester) async {
      await tester.pumpWidget(
        wrap(
          field(
            fetch: (request) async =>
                const PagedSelectPage(options: [], nextOffset: null, totalResults: 0),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await open(tester);

      expect(find.text('No options found.'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
    });
  });
}
