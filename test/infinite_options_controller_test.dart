// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thunderid_flutter/src/models/select.dart';
import 'package:thunderid_flutter/src/models/select_loading.dart';
import 'package:thunderid_flutter/src/widgets/infinite_options_controller.dart';

class _Boom implements Exception {
  final int id;

  const _Boom(this.id);
}

List<SelectOption> options(int from, int to) =>
    [for (var i = from; i <= to; i++) SelectOption('User ${i + 1}', 'user-${i + 1}')];

SelectOptionsBatch<int> page(int start, int count, int total) => SelectOptionsBatch<int>.page(
      options(start, start + count - 1),
      nextCursor: start + count < total ? start + count : null,
    );

/// Lets every pending microtask and zero-delay timer run.
Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

List<String> values(InfiniteOptionsController<int> controller) =>
    controller.options.map((o) => o.value).toList();

void main() {
  InfiniteOptionsController<int> make({
    required SelectOptionsLoader<int> load,
    List<SelectOption> initialOptions = const [],
    void Function(Object error)? onError,
  }) {
    final controller = InfiniteOptionsController<int>(
      initialOptions: initialOptions,
      load: load,
      onError: onError,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test('makes no request until loadMore', () async {
    var calls = 0;
    final controller = make(load: (_) async {
      calls += 1;
      return page(0, 0, 0);
    },);

    await settle();

    expect(calls, 0);
    expect(controller.options, isEmpty);
    expect(controller.loading, false);
    expect(controller.hasMore, true);
  });

  test('the initial options are shown before anything loads', () {
    final controller = make(initialOptions: options(0, 1), load: (_) async => null);

    expect(values(controller), ['user-1', 'user-2']);
  });

  test('the first load has no cursor and lists the batch', () async {
    final contexts = <SelectOptionsLoadContext<int>>[];
    final controller = make(load: (context) async {
      contexts.add(context);
      return page(0, 30, 75);
    },);

    controller.loadMore();
    await settle();

    expect(contexts, hasLength(1));
    expect(contexts.single.cursor, isNull);
    expect(controller.options, hasLength(30));
    expect(controller.hasMore, true);
    expect(controller.loading, false);
  });

  test('is loading while a batch is in flight and tells its listeners', () async {
    final gate = Completer<void>();
    final controller = make(load: (_) async {
      await gate.future;
      return page(0, 3, 3);
    },);
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    controller.loadMore();
    expect(controller.loading, true);
    expect(notifications, greaterThan(0));

    gate.complete();
    await settle();

    expect(controller.loading, false);
    expect(controller.options, hasLength(3));
  });

  test('two immediate calls make one request', () async {
    var calls = 0;
    final controller = make(load: (_) async {
      calls += 1;
      return page(0, 30, 75);
    },);

    controller.loadMore();
    controller.loadMore();
    await settle();

    expect(calls, 1);
  });

  test('the next load continues from the stored cursor', () async {
    final cursors = <int?>[];
    final controller = make(load: (context) async {
      cursors.add(context.cursor);
      return page(context.cursor ?? 0, 30, 75);
    },);

    controller.loadMore();
    await settle();
    controller.loadMore();
    await settle();

    expect(cursors, [null, 30]);
    expect(controller.options.last.value, 'user-60');
  });

  test('the load context carries the options loaded so far', () async {
    final seen = <int>[];
    final controller = make(load: (context) async {
      seen.add(context.options.length);
      return page(context.cursor ?? 0, 2, 6);
    },);

    controller.loadMore();
    await settle();
    controller.loadMore();
    await settle();

    expect(seen, [0, 2]);
  });

  test('does nothing once the data has ended', () async {
    var calls = 0;
    final controller = make(load: (_) async {
      calls += 1;
      return SelectOptionsBatch<int>.page(options(0, 2));
    },);

    controller.loadMore();
    await settle();
    controller.loadMore();
    await settle();

    expect(calls, 1);
    expect(controller.hasMore, false);
  });

  test('a failed load keeps the options, sets the error and calls onError', () async {
    final reported = <Object>[];
    var attempt = 0;
    final controller = make(
      onError: reported.add,
      load: (context) async {
        attempt += 1;
        if (attempt == 2) throw const _Boom(2);
        return page(context.cursor ?? 0, 30, 75);
      },
    );

    controller.loadMore();
    await settle();
    controller.loadMore();
    await settle();

    expect(controller.options, hasLength(30));
    expect((controller.error! as _Boom).id, 2);
    expect(reported, hasLength(1));
    expect(controller.hasMore, true);
    expect(controller.loading, false);
  });

  test('asking again after a failure repeats the same request and clears the error', () async {
    final cursors = <int?>[];
    var attempt = 0;
    final controller = make(load: (context) async {
      cursors.add(context.cursor);
      attempt += 1;
      if (attempt == 1) throw const _Boom(1);
      return page(0, 30, 75);
    },);

    controller.loadMore();
    await settle();
    controller.loadMore();
    await settle();

    expect(cursors, [null, null]);
    expect(controller.error, isNull);
    expect(controller.options, hasLength(30));
  });

  test('an onError callback that throws does not break the list', () async {
    final controller = make(
      onError: (_) => throw StateError('callback bug'),
      load: (_) async => throw const _Boom(1),
    );
    final messages = <String?>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => messages.add(message);
    addTearDown(() => debugPrint = original);

    controller.loadMore();
    await settle();

    expect(controller.loading, false);
    expect(controller.error, isA<_Boom>());
    expect(messages.single, contains('onError'));
  });

  test('removes an option repeated across a batch boundary', () async {
    final controller = make(load: (context) async {
      return context.cursor == null
          ? SelectOptionsBatch<int>.page(options(0, 2), nextCursor: 3)
          : SelectOptionsBatch<int>.page(options(2, 4));
    },);

    controller.loadMore();
    await settle();
    controller.loadMore();
    await settle();

    expect(values(controller), ['user-1', 'user-2', 'user-3', 'user-4', 'user-5']);
  });

  test('a result from before a reset is dropped and does not end the new load', () async {
    final staleGate = Completer<void>();
    final freshGate = Completer<void>();
    var call = 0;
    final controller = make(load: (_) async {
      call += 1;
      if (call == 1) {
        await staleGate.future;
        return page(0, 3, 10);
      }
      await freshGate.future;
      return SelectOptionsBatch<int>.page(options(100, 102));
    },);

    controller.loadMore();
    await settle();
    controller.reset();
    await settle();
    staleGate.complete();
    await settle();

    expect(controller.options, isEmpty);
    expect(controller.loading, true);

    freshGate.complete();
    await settle();

    expect(values(controller), ['user-101', 'user-102', 'user-103']);
    expect(controller.loading, false);
    expect(controller.hasMore, false);
  });

  test('a failure from before a reset is not reported', () async {
    final staleGate = Completer<void>();
    var reported = 0;
    var call = 0;
    final controller = make(
      onError: (_) => reported += 1,
      load: (_) async {
        call += 1;
        if (call == 1) {
          await staleGate.future;
          throw const _Boom(1);
        }
        return page(0, 3, 3);
      },
    );

    controller.loadMore();
    await settle();
    controller.reset();
    await settle();
    staleGate.complete();
    await settle();

    expect(reported, 0);
    expect(controller.error, isNull);
    expect(controller.options, hasLength(3));
    expect(controller.loading, false);
  });

  test('reset goes back to the initial options and the first cursor', () async {
    final cursors = <int?>[];
    final controller = make(
      initialOptions: options(0, 0),
      load: (context) async {
        cursors.add(context.cursor);
        return page(context.cursor ?? 0, 2, 4);
      },
    );

    controller.loadMore();
    await settle();
    controller.reset();
    await settle();

    expect(cursors, [null, null]);
  });

  test('reset loads again right away when loading had been requested', () async {
    var calls = 0;
    final controller = make(load: (_) async {
      calls += 1;
      return page(0, 3, 3);
    },);

    controller.loadMore();
    await settle();
    controller.reset();
    await settle();

    expect(calls, 2);
    expect(controller.options, hasLength(3));
  });

  test('reset does not load when nothing was requested', () async {
    var calls = 0;
    final controller = make(
      initialOptions: options(0, 0),
      load: (_) async {
        calls += 1;
        return null;
      },
    );

    controller.reset();
    await settle();

    expect(calls, 0);
    expect(controller.options, hasLength(1));
  });

  test('a batch that adds nothing new keeps loading up to the limit then waits', () async {
    var calls = 0;
    final controller = make(
      initialOptions: options(0, 0),
      load: (context) async {
        calls += 1;
        return SelectOptionsBatch<int>.page(options(0, 0), nextCursor: (context.cursor ?? 0) + 1);
      },
    );

    controller.loadMore();
    await settle();

    expect(calls, SelectConstants.maxEmptyContinuations + 1);
    expect(controller.hasMore, true);
    expect(controller.loading, false);

    controller.loadMore();
    await settle();

    expect(calls, 2 * (SelectConstants.maxEmptyContinuations + 1));
  });

  test('stops continuing as soon as a batch adds something', () async {
    var calls = 0;
    final controller = make(load: (context) async {
      calls += 1;
      final cursor = context.cursor ?? 0;
      return cursor < 2
          ? SelectOptionsBatch<int>.page(const [], nextCursor: cursor + 1)
          : SelectOptionsBatch<int>.page(options(0, 1), nextCursor: cursor + 1);
    },);

    controller.loadMore();
    await settle();

    expect(calls, 3);
    expect(controller.options, hasLength(2));
  });

  test('a cursor that does not move ends the list and says so', () async {
    final messages = <String?>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => messages.add(message);
    addTearDown(() => debugPrint = original);
    final controller = make(
      initialOptions: options(0, 0),
      load: (_) async => SelectOptionsBatch<int>.page(options(0, 0), nextCursor: 5),
    );

    controller.loadMore();
    await settle();

    expect(controller.hasMore, false);
    expect(messages, hasLength(1));
  });

  test('a plain list ends when it adds nothing new', () async {
    var calls = 0;
    final controller = make(load: (_) async {
      calls += 1;
      return SelectOptionsBatch<int>.list(options(0, 1));
    },);

    controller.loadMore();
    await settle();
    expect(controller.hasMore, true);
    controller.loadMore();
    await settle();

    expect(calls, 2);
    expect(controller.hasMore, false);
  });

  test('a missing batch counts as empty and ends the list', () async {
    final controller = make(load: (_) async => null);

    controller.loadMore();
    await settle();

    expect(controller.options, isEmpty);
    expect(controller.hasMore, false);
  });

  test('update gives the next request the new loader without restarting the list', () async {
    final used = <String>[];
    final controller = make(load: (context) async {
      used.add('old');
      return page(context.cursor ?? 0, 2, 6);
    },);

    controller.loadMore();
    await settle();
    controller.update(load: (context) async {
      used.add('new');
      return page(context.cursor ?? 0, 2, 6);
    },);
    controller.loadMore();
    await settle();

    expect(used, ['old', 'new']);
    expect(controller.options, hasLength(4));
  });

  test('two controllers do not share a cursor', () async {
    final first = make(load: (context) async => page(context.cursor ?? 0, 2, 6));
    final second = make(load: (context) async => page(context.cursor ?? 0, 2, 6));

    first.loadMore();
    await settle();
    first.loadMore();
    await settle();
    second.loadMore();
    await settle();

    expect(first.options, hasLength(4));
    expect(values(second), ['user-1', 'user-2']);
  });

  test('a result that arrives after dispose is ignored', () async {
    final gate = Completer<void>();
    var reported = 0;
    final controller = InfiniteOptionsController<int>(
      onError: (_) => reported += 1,
      load: (_) async {
        await gate.future;
        throw const _Boom(1);
      },
    );

    controller.loadMore();
    await settle();
    controller.dispose();
    gate.complete();
    await settle();

    expect(reported, 0);
  });
}
