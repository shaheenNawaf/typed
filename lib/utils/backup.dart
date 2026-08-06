import 'dart:convert';
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import '../models/note.dart';

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

class Backup {
  static Future<XFile> exportToFile(List<Note> notes) async {
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final raw = jsonEncode({
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'notes': notes.map((n) => n.toJson()).toList(),
    });
    return XFile.fromData(
      Uint8List.fromList(utf8.encode(raw)),
      name: 'notes_export_$ts.json',
      mimeType: 'application/json',
    );
  }

  static Future<List<Note>> importFromFile(String path) async {
    return importFromBytes(await XFile(path).readAsBytes());
  }

  static Future<List<Note>> importFromBytes(List<int> bytes) async {
    final raw = utf8.decode(bytes);
    final data = jsonDecode(raw);
    final list = data is Map<String, dynamic>
        ? (data['notes'] as List? ?? const [])
        : (data as List);
    return list.map((e) => Note.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<XFile> exportFinanceCsv(List<Note> notes) async {
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;

    final buffer = StringBuffer();
    buffer.writeln('Date,Type,Category,Amount,Currency,Note,Payment Method');

    for (final note in notes) {
      if (note.type == 'text') continue;
      for (final entry in note.amounts) {
        final noteField = entry.note ?? '';
        final pm = entry.paymentMethod ?? '';
        final cur = entry.currency ?? note.currency ?? '';
        // Effective type falls back to the note's type when the entry has none.
        final type = entry.type ?? note.type;
        buffer.writeln(
          '${csvEscape(entry.date.toIso8601String().split('T')[0])},'
          '${csvEscape(type)},'
          '${csvEscape(entry.category)},'
          '${csvEscape(entry.amount.toString())},'
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
