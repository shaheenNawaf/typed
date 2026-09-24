import 'dart:convert';
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import '../models/budget.dart';
import '../models/note.dart';
import 'finance_utils.dart';

/// Escapes a single CSV field per RFC 4180: fields containing a comma,
/// double-quote, or newline are wrapped in double quotes, and embedded quotes
/// are doubled.
String csvEscape(String value) {
  if (value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

class BackupBundle {
  final List<Note> notes;

  /// Empty for v1 backup files, which only knew about notes.
  final List<Budget> budgets;

  const BackupBundle(this.notes, [this.budgets = const []]);
}

class Backup {
  static Future<XFile> exportToFile(
    List<Note> notes, [
    List<Budget> budgets = const [],
  ]) async {
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final raw = jsonEncode({
      'version': 2,
      'exported_at': DateTime.now().toIso8601String(),
      // Trashed notes are deliberately not exported so a restore cannot
      // resurrect content the user already threw away.
      'notes': notes.where((n) => !n.isDeleted).map((n) => n.toJson()).toList(),
      'budgets': budgets.map((b) => b.toJson()).toList(),
    });
    return XFile.fromData(
      Uint8List.fromList(utf8.encode(raw)),
      name: 'notes_export_$ts.json',
      mimeType: 'application/json',
    );
  }

  static Future<BackupBundle> importFromFile(String path) async {
    return importFromBytes(await XFile(path).readAsBytes());
  }

  static Future<BackupBundle> importFromBytes(List<int> bytes) async {
    var raw = utf8.decode(bytes);
    if (raw.startsWith('\uFEFF')) raw = raw.substring(1);
    final data = jsonDecode(raw);
    final list = data is Map<String, dynamic>
        ? (data['notes'] as List? ?? const [])
        : (data as List);
    final notes =
        list.map((e) => Note.fromJson(e as Map<String, dynamic>)).toList();
    final budgets = data is Map<String, dynamic>
        ? (data['budgets'] as List? ?? const [])
            .map((e) => Budget.fromJson(e as Map<String, dynamic>))
            .toList()
        : const <Budget>[];
    return BackupBundle(notes, budgets);
  }

  static Future<XFile> exportFinanceCsv(List<Note> notes) async {
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;

    final buffer = StringBuffer();
    // UTF-8 BOM: without it Excel mojibakes the peso sign.
    buffer.write('\uFEFF');
    // RFC 4180 line endings.
    void line(String value) => buffer.write('$value\r\n');

    line('Date,Type,Category,Amount,Currency,Note,Payment Method');

    for (final note in notes) {
      if (note.type == 'text' || note.isDeleted) continue;
      for (final entry in note.amounts) {
        final noteField = entry.note ?? '';
        final pm = entry.paymentMethod ?? '';
        final cur = entry.currency ?? note.currency ?? '';
        final currencyCode = cur.isEmpty ? null : cur;
        final amount = minorToMajor(entry.amount, currencyCode)
            .toStringAsFixed(currencyDecimals(currencyCode));
        // Effective type falls back to the note's type when the entry has none.
        final type = entry.type ?? note.type;
        line(
          '${csvEscape(entry.date.toIso8601String().split('T')[0])},'
          '${csvEscape(type)},'
          '${csvEscape(entry.category)},'
          '${csvEscape(amount)},'
          '${csvEscape(cur)},'
          '${csvEscape(noteField)},'
          '${csvEscape(pm)}',
        );
      }
    }

    return XFile.fromData(
      Uint8List.fromList(utf8.encode(buffer.toString())),
      name: 'finance_export_$ts.csv',
      mimeType: 'text/csv',
    );
  }
}
