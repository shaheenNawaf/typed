import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/note.dart';

class Backup {
  static Future<String> exportToFile(List<Note> notes) async {
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final file = File('${dir.path}/notes_export_$ts.json');
    final raw = jsonEncode({
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'notes': notes.map((n) => n.toJson()).toList(),
    });
    await file.writeAsString(raw);
    return file.path;
  }

  static Future<List<Note>> importFromFile(String path) async {
    final raw = await File(path).readAsString();
    final data = jsonDecode(raw);
    final list = data is Map<String, dynamic>
        ? (data['notes'] as List? ?? const [])
        : (data as List);
    return list
        .map((e) => Note.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<String> exportFinanceCsv(List<Note> notes) async {
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final file = File('${dir.path}/finance_export_$ts.csv');

    final buffer = StringBuffer();
    buffer.writeln('Date,Type,Category,Amount,Currency,Note,Payment Method');

    for (final note in notes) {
      if (note.type == 'text') continue;
      for (final entry in note.amounts) {
        final noteField = entry.note?.replaceAll(',', ';') ?? '';
        final pm = entry.paymentMethod ?? '';
        final cur = entry.currency ?? note.currency ?? '';
        buffer.writeln(
          '${entry.date.toIso8601String().split('T')[0]},${note.type},'
          '${entry.category},${entry.amount},$cur,$noteField,$pm',
        );
      }
    }

    await file.writeAsString(buffer.toString());
    return file.path;
  }
}
