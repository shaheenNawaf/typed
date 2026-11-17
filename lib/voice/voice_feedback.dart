import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'voice_shaper.dart';

/// A local log of saved voice memos: what was heard, what the app drafted
/// from it, and what was actually saved. It is how the voice model gets
/// better: the rows where the save differs from the draft are the mistakes
/// (misheard words, wrong tasks), written by real speech, not typed
/// examples. Stays on this device until the user shares the file; the
/// newest [max] memos are kept.
class VoiceFeedback {
  VoiceFeedback._();

  static const key = 'voice_feedback_v1';
  static const max = 100;

  /// One row. [heard] is the recogniser's text before any correction;
  /// [transcript] is what was shaped (the same unless the user fixed it).
  static Map<String, Object?> entry({
    required DateTime at,
    required String heard,
    required String transcript,
    required VoiceDraft? draft,
    required bool usedModel,
    required int? modelMs,
    required bool edited,
    required String? locale,
    required String savedKind,
    required String savedTitle,
    required String savedContent,
  }) => {
    'at': at.toIso8601String(),
    'heard': heard,
    if (transcript != heard) 'transcript': transcript,
    'source': usedModel ? 'model' : 'rules',
    'model_ms': ?modelMs,
    'locale': ?locale,
    'edited': edited,
    if (draft != null)
      'draft': {
        'kind': draft.kind.name,
        'title': draft.title,
        'tasks': draft.taskLines,
        'note': draft.other.join(' '),
        'spends': [
          for (final s in draft.spends) '${s.amount} ${s.category} ${s.note}',
        ],
      },
    'saved': {'kind': savedKind, 'title': savedTitle, 'content': savedContent},
  };

  static Future<void> record(Map<String, Object?> row) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rows = prefs.getStringList(key) ?? [];
      rows.add(jsonEncode(row));
      if (rows.length > max) rows.removeRange(0, rows.length - max);
      await prefs.setStringList(key, rows);
    } catch (_) {
      // A log must never get in the way of saving a memo.
    }
  }

  static Future<int> count() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(key) ?? const []).length;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  /// The log as one JSON-lines file, ready to share.
  static Future<XFile> exportFile() async {
    final prefs = await SharedPreferences.getInstance();
    final rows = prefs.getStringList(key) ?? const [];
    final day = DateTime.now().toIso8601String().split('T').first;
    return XFile.fromData(
      Uint8List.fromList(utf8.encode('${rows.join('\n')}\n')),
      name: 'typed_voice_log_$day.jsonl',
      mimeType: 'application/jsonl',
    );
  }
}

/// Which language the recogniser listens for. Null follows the phone.
class VoiceLanguage {
  VoiceLanguage._();

  static const key = 'voice_locale_v1';

  static Future<String?> get() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(key);
    return v == null || v.isEmpty ? null : v;
  }

  static Future<void> set(String? localeId) async {
    final prefs = await SharedPreferences.getInstance();
    if (localeId == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, localeId);
    }
  }
}
