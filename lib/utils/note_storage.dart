import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/budget.dart';
import '../models/note.dart';

/// Thrown when stored data exists but cannot be decoded.
///
/// This is a distinct signal from "no data saved yet", so callers can decide
/// whether to show an error or fall back to onboarding data instead of
/// silently overwriting the user's notes with an empty list.
class NoteStorageException implements Exception {
  final String key;
  final Object cause;

  const NoteStorageException(this.key, this.cause);

  @override
  String toString() => 'NoteStorageException(key: $key, cause: $cause)';
}

/// Result of a load that distinguishes a successful read from a corrupt one.
class NoteStorageResult<T> {
  final List<T> items;
  final Object? error;

  const NoteStorageResult._(this.items, this.error);

  bool get hasError => error != null;

  static NoteStorageResult<T> success<T>(List<T> items) =>
      NoteStorageResult<T>._(items, null);

  static NoteStorageResult<T> failure<T>(Object error) =>
      NoteStorageResult<T>._(const [], error);
}

/// Serializes writes so that overlapping saves cannot leave stale data on disk.
class _WriteQueue {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }
}

class NoteStorage {
  static const _notesKey = 'notes_v1';
  static const _budgetsKey = 'budgets_v1';
  static const _widgetRecentKey = 'widget_recent_v1';
  static const _widgetTodoKey = 'widget_todo_v1';
  static const _channel = MethodChannel('com.z4yed.typed/widget');

  final _writeQueue = _WriteQueue();

  /// Loads notes, returning an empty list when nothing has been saved yet.
  ///
  /// Backward-compatible: never throws. Use [loadResult] to detect corrupt
  /// data with a clear error signal.
  Future<List<Note>> load() async {
    final result = await _load(_notesKey, Note.fromJson);
    return result.items;
  }

  /// Loads notes with an explicit success/error signal.
  ///
  /// Returns [NoteStorageResult.failure] when saved data is corrupt, instead
  /// of silently returning an empty list.
  Future<NoteStorageResult<Note>> loadResult() =>
      _load(_notesKey, Note.fromJson);

  Future<bool> hasSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_notesKey);
  }

  Future<void> save(List<Note> notes) {
    return _writeQueue.run(() async {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(notes.map((n) => n.toJson()).toList());
      await prefs.setString(_notesKey, raw);
      await _writeWidgetPayload(prefs, notes);
      try {
        await _channel.invokeMethod('refreshWidgets');
      } catch (_) {}
    });
  }

  Future<void> _writeWidgetPayload(
    SharedPreferences prefs,
    List<Note> notes,
  ) async {
    final visible = notes.where((n) => !n.isArchived && !n.isDeleted).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final recent = visible.take(5).map((n) {
      final previewLine = n.content
          .split('\n')
          .firstWhere(
            (l) => l.trim().isNotEmpty && !l.startsWith('#'),
            orElse: () => n.content.split('\n').first,
          )
          .replaceAll(RegExp(r'[#*`>\[\]]'), '')
          .trim();
      return jsonEncode({
        'id': n.id,
        'title': n.title,
        'preview': previewLine.length > 80
            ? '${previewLine.substring(0, 80)}...'
            : previewLine,
      });
    }).toList();
    await prefs.setString(_widgetRecentKey, jsonEncode(recent));

    final todo = <Map<String, dynamic>>[];
    for (final n in visible) {
      if (n.type != 'todo' &&
          !n.tags.contains('todo') &&
          !_hasChecklist(n.content)) {
        continue;
      }
      for (final line in n.content.split('\n')) {
        final m = RegExp(r'^\s*-\s+\[([ xX])\]\s+(.+)$').firstMatch(line);
        if (m != null) {
          todo.add({
            'id': n.id,
            'done': m.group(1) != ' ',
            'text': m.group(2)?.trim() ?? '',
          });
        }
      }
    }
    await prefs.setString(_widgetTodoKey, jsonEncode(todo));
  }

  bool _hasChecklist(String content) =>
      RegExp(r'^\s*-\s+\[[ xX]\]', multiLine: true).hasMatch(content);

  Future<List<Budget>> loadBudgets() async {
    final result = await _load(_budgetsKey, Budget.fromJson);
    return result.items;
  }

  /// Loads budgets with an explicit success/error signal.
  Future<NoteStorageResult<Budget>> loadBudgetsResult() =>
      _load(_budgetsKey, Budget.fromJson);

  Future<NoteStorageResult<T>> _load<T>(
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return NoteStorageResult.success<T>([]);
    }
    try {
      final list = jsonDecode(raw) as List;
      final items = list
          .map((e) => fromJson(e as Map<String, dynamic>))
          .toList();
      return NoteStorageResult.success<T>(items);
    } catch (e) {
      return NoteStorageResult.failure<T>(NoteStorageException(key, e));
    }
  }

  Future<void> saveBudgets(List<Budget> budgets) {
    return _writeQueue.run(() async {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(budgets.map((b) => b.toJson()).toList());
      await prefs.setString(_budgetsKey, raw);
    });
  }
}
