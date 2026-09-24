import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/budget.dart';
import '../models/money_entry.dart';
import '../models/note.dart';
import 'date_format.dart';
import 'finance_utils.dart';
import 'markdown_display.dart';
import 'streak.dart';

/// Truncates without splitting a UTF-16 surrogate pair (emoji in note
/// previews would otherwise render as a broken tail char in the widget).
String truncateSafe(String value, int max) {
  if (value.length <= max) return value;
  var cut = max;
  final tail = value.codeUnitAt(cut - 1);
  if (tail >= 0xD800 && tail <= 0xDBFF) cut--;
  return '${value.substring(0, cut)}...';
}

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
      final previewLine = firstPreviewLine(n.content);
      return <String, dynamic>{
        'id': n.id,
        'title': n.title.isEmpty ? 'Untitled' : n.title,
        'preview': truncateSafe(previewLine, 80),
      };
    }).toList();
    await prefs.setString(_widgetRecentKey, jsonEncode(recent));

    final todo = <Map<String, dynamic>>[];
    for (final n in visible) {
      if (!isTaskNote(n)) continue;
      for (final item in parseChecklist(n.content)) {
        // Empty-text template lines (`- [ ] `) are editing scaffolding, not
        // widget rows — the legacy `.+` regex skipped them, keep that.
        if (item.text.isEmpty) continue;
        todo.add({
          'id': n.id,
          'done': item.done,
          'text': stripInlineMarkdown(item.text),
        });
      }
    }
    await prefs.setString(_widgetTodoKey, jsonEncode(todo));

    final budgets = _budgetsFromPrefs(prefs);
    await prefs.setString(
      'widget_streak_v1',
      jsonEncode(computeWritingStreak(notes).toJson()),
    );
    await prefs.setString(
      'widget_finance_v1',
      jsonEncode(_financePayload(notes, budgets)),
    );
  }

  List<Budget> _budgetsFromPrefs(SharedPreferences prefs) {
    final raw = prefs.getString(_budgetsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((item) => Budget.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Map<String, dynamic> _financePayload(List<Note> notes, List<Budget> budgets) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final nextMonth = DateTime(now.year, now.month + 1);
    final entries = <MoneyEntry>[];
    final typeByEntry = <String, String>{};
    for (final note in notes) {
      if (note.isArchived || note.isDeleted || note.type == 'text') continue;
      for (final entry in note.amounts) {
        if (!entry.date.isBefore(monthStart) &&
            entry.date.isBefore(nextMonth)) {
          entries.add(entry);
          typeByEntry[entry.id] = entry.type ?? note.type;
        }
      }
    }

    final currencyCounts = <String, int>{};
    for (final entry in entries) {
      final currency = entry.currency ?? 'PHP';
      currencyCounts[currency] = (currencyCounts[currency] ?? 0) + 1;
    }
    final currency = currencyCounts.entries.fold<String>(
      'PHP',
      (current, entry) =>
          entry.value > (currencyCounts[current] ?? 0) ? entry.key : current,
    );
    var income = 0;
    var expense = 0;
    final categorySpend = <String, int>{};
    for (final entry in entries) {
      if ((entry.currency ?? 'PHP') != currency) continue;
      final type = typeByEntry[entry.id] ?? entry.type;
      if (type == 'income') {
        income += entry.amount;
      } else if (type == 'expense') {
        expense += entry.amount;
        categorySpend[entry.category] =
            (categorySpend[entry.category] ?? 0) + entry.amount;
      }
    }

    Budget? selectedBudget;
    var selectedSpent = 0;
    var selectedRatio = 0.0;
    for (final budget in budgets) {
      if (budget.period != 'month' || budget.currency != currency) {
        continue;
      }
      final spent = categorySpend[budget.category] ?? 0;
      final ratio = budget.limit > 0 ? spent / budget.limit : 0.0;
      if (selectedBudget == null || ratio > selectedRatio) {
        selectedBudget = budget;
        selectedSpent = spent;
        selectedRatio = ratio;
      }
    }

    // Amounts are pre-formatted (minor units live exactly once in Dart code);
    // the widget just renders text.
    return {
      'month': '${monthShort(now.month)} ${now.year}',
      'currency': currency,
      'incomeText': formatMinorAmount(income, currency),
      'expenseText': formatMinorAmount(expense, currency),
      'balanceText': formatMinorAmount(income - expense, currency),
      'empty': income == 0 && expense == 0,
      'budgetCategory': selectedBudget?.category ?? '',
      'hasBudget': selectedBudget != null && selectedBudget.limit > 0,
      'budgetPercent': selectedBudget != null && selectedBudget.limit > 0
          ? (selectedSpent / selectedBudget.limit * 100).round().clamp(0, 100)
          : 0,
      'budgetOver': selectedBudget != null && selectedSpent > selectedBudget.limit,
    };
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
      final notesRaw = prefs.getString(_notesKey);
      if (notesRaw != null) {
        try {
          final notes = (jsonDecode(notesRaw) as List)
              .map((item) => Note.fromJson(item as Map<String, dynamic>))
              .toList();
          await prefs.setString(
            'widget_finance_v1',
            jsonEncode(_financePayload(notes, budgets)),
          );
          try {
            await _channel.invokeMethod('refreshWidgets');
          } catch (_) {}
        } catch (_) {}
      }
    });
  }
}
