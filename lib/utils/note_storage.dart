import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/budget.dart';
import '../models/note.dart';

class NoteStorage {
  static const _notesKey = 'notes_v1';
  static const _budgetsKey = 'budgets_v1';
  static const _widgetRecentKey = 'widget_recent_v1';
  static const _widgetTodoKey = 'widget_todo_v1';
  static const _channel = MethodChannel('com.z4yed.typed/widget');

  Future<List<Note>> load() async => _load(_notesKey, Note.fromJson);

  Future<bool> hasSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_notesKey);
  }

  Future<void> save(List<Note> notes) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(notes.map((n) => n.toJson()).toList());
    await prefs.setString(_notesKey, raw);
    await _writeWidgetPayload(prefs, notes);
    try {
      await _channel.invokeMethod('refreshWidgets');
    } catch (_) {}
  }

  Future<void> _writeWidgetPayload(SharedPreferences prefs, List<Note> notes) async {
    final recent = notes.take(5).map((n) {
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
    for (final n in notes) {
      if (n.type != 'todo' && !n.tags.contains('todo') && !_hasChecklist(n.content)) continue;
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

  Future<List<Budget>> loadBudgets() async => _load(_budgetsKey, Budget.fromJson);

  Future<List<T>> _load<T>(String key, T Function(Map<String, dynamic>) fromJson) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveBudgets(List<Budget> budgets) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(budgets.map((b) => b.toJson()).toList());
    await prefs.setString(_budgetsKey, raw);
  }
}
