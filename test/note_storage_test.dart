import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typed/utils/note_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NoteStorage corruption contract', () {
    test('loadResult reports failure for corrupt saved data instead of '
        'silently emptying the workspace', () async {
      SharedPreferences.setMockInitialValues({
        'notes_v1': '{ not json',
      });
      final result = await NoteStorage().loadResult();
      expect(result.hasError, isTrue);
      expect(result.error, isA<NoteStorageException>());
      expect(result.items, isEmpty);
    });

    test('loadResult succeeds on empty storage (first launch)', () async {
      SharedPreferences.setMockInitialValues({});
      final result = await NoteStorage().loadResult();
      expect(result.hasError, isFalse);
      expect(result.items, isEmpty);
    });

    test('corrupt budgets are surfaced, not swallowed', () async {
      SharedPreferences.setMockInitialValues({
        'budgets_v1': 'nope',
      });
      final result = await NoteStorage().loadBudgetsResult();
      expect(result.hasError, isTrue);
    });

    test('saves are serialized through the write queue', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = NoteStorage();
      await Future.wait([
        storage.save([]),
        storage.save([]),
        storage.save([]),
      ]);
      final prefs = await SharedPreferences.getInstance();
      expect(() => prefs.getString('notes_v1'), returnsNormally);
      expect(prefs.getString('notes_v1'), isNotNull);
    });
  });
}
