// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

enum LogKind { ok, info, error }

class LogEntry {
  final DateTime time;
  final String name;
  final String detail;
  final LogKind kind;

  const LogEntry(this.time, this.name, this.detail, this.kind);

  String get clock {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}

/// In-memory log of every SDK call the playground makes and every session change it observes.
///
/// thunderid_flutter does not publish an event stream, so the playground records events
/// itself: each SDK call goes through [trace], and the shell logs provider state transitions.
class EventLog extends ChangeNotifier {
  EventLog._();

  static final EventLog instance = EventLog._();

  static const _limit = 300;
  final List<LogEntry> _entries = [];

  /// Newest first.
  List<LogEntry> get entries => List.unmodifiable(_entries);

  void add(String name, String detail, {LogKind kind = LogKind.info}) {
    _entries.insert(0, LogEntry(DateTime.now(), name, detail, kind));
    if (_entries.length > _limit) _entries.removeLast();
    _notify();
  }

  bool _notifyScheduled = false;

  /// Entries can be added while the tree is building (provider transitions are observed from
  /// didChangeDependencies), so listeners are notified after the current frame in that case.
  void _notify() {
    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      notifyListeners();
      return;
    }
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  void clear() {
    _entries.clear();
    _notify();
  }

  /// Runs an SDK call and records its outcome under [name].
  Future<T> trace<T>(
    String name,
    Future<T> Function() call, {
    String Function(T result)? detail,
  }) async {
    try {
      final result = await call();
      add(name, detail?.call(result) ?? 'ok', kind: LogKind.ok);
      return result;
    } catch (e) {
      add(name, describeError(e), kind: LogKind.error);
      rethrow;
    }
  }
}

/// A short, readable reason for an SDK failure.
String describeError(Object error) {
  if (error is IAMApiException) {
    return '${error.code.value} · HTTP ${error.statusCode} from ${error.operation}: ${error.message}';
  }
  if (error is IAMException) return '${error.code.value}: ${error.message}';
  final text = error.toString();
  return text.length > 240 ? '${text.substring(0, 240)}…' : text;
}
