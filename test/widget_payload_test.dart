import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typed/models/note.dart';
import 'package:typed/utils/note_storage.dart';
import 'package:typed/utils/image_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('widget recent payload', () {
    test('is a JSON array of objects (Kotlin reads optJSONObject)', () async {
      SharedPreferences.setMockInitialValues({});
      final note = Note(
        id: 'n1',
        title: 'Rust Ownership',
        content: '# Heading\nSome **body** text here',
        tags: [],
      );
      await NoteStorage().save([note]);

      final prefs = await SharedPreferences.getInstance();
      final decoded = jsonDecode(prefs.getString('widget_recent_v1')!) as List;
      expect(decoded, hasLength(1));
      expect(decoded.first, isA<Map>());
      expect(decoded.first['id'], 'n1');
      expect(decoded.first['title'], 'Rust Ownership');
      expect(decoded.first['preview'], 'Some body text here');
    });

    test('blank titles fall back to Untitled', () async {
      SharedPreferences.setMockInitialValues({});
      await NoteStorage().save([
        Note(id: 'n2', title: '', content: 'body', tags: []),
      ]);
      final prefs = await SharedPreferences.getInstance();
      final decoded = jsonDecode(prefs.getString('widget_recent_v1')!) as List;
      expect(decoded.first['title'], 'Untitled');
    });

    test('archived and trashed notes are excluded', () async {
      SharedPreferences.setMockInitialValues({});
      await NoteStorage().save([
        Note(id: 'a', title: 'Archived', content: 'x', tags: [], isArchived: true),
        Note(id: 'd', title: 'Trashed', content: 'x', tags: [], isDeleted: true),
      ]);
      final prefs = await SharedPreferences.getInstance();
      final decoded = jsonDecode(prefs.getString('widget_recent_v1')!) as List;
      expect(decoded, isEmpty);
    });
  });

  group('truncateSafe', () {
    test('leaves short strings alone', () {
      expect(truncateSafe('short', 80), 'short');
    });

    test('does not split surrogate pairs', () {
      final value = '${'x' * 79}😀tail';
      final cut = truncateSafe(value, 80);
      expect(cut.endsWith('...'), isTrue);
      expect(cut, isNot(contains('\uD83D')));
    });
  });

  group('widget todo payload', () {
    test('strips inline markdown, skips empty items, excludes seeds', () async {
      SharedPreferences.setMockInitialValues({});
      await NoteStorage().save([
        Note(
          id: 't1',
          title: 'Audit todo',
          content: '- [ ] Buy **milk** and eggs\n'
              '- [x] Pay the `electric` bill\n'
              '- [ ] Review [[Welcome to Typed]]\n'
              '- [ ] \n',
          tags: [],
          type: 'todo',
        ),
        Note(
          id: 'seed_welcome',
          title: 'Welcome to Typed',
          content: '- [ ] phantom demo task\n',
          tags: [],
        ),
        Note(
          id: 'seed_tasks_guide',
          title: 'Managing Tasks',
          content: '- [ ] guide demo task\n',
          tags: ['guide'],
          type: 'todo',
        ),
      ]);

      final prefs = await SharedPreferences.getInstance();
      final decoded = jsonDecode(prefs.getString('widget_todo_v1')!) as List;
      expect(decoded, hasLength(3));
      expect(decoded[0]['text'], 'Buy milk and eggs');
      expect(decoded[0]['done'], false);
      expect(decoded[1]['text'], 'Pay the electric bill');
      expect(decoded[1]['done'], true);
      expect(decoded[2]['text'], 'Review Welcome to Typed');
      expect(
        decoded.any((e) => (e['text'] as String).contains('phantom')),
        isFalse,
      );
      expect(
        decoded.any((e) => (e['text'] as String).contains('guide')),
        isFalse,
      );
    });
  });

  group('widget recent preview parity', () {
    test('keeps hyphens and code-span content', () async {
      SharedPreferences.setMockInitialValues({});
      await NoteStorage().save([
        Note(
          id: 'p1',
          title: 'P',
          content: 'A local-first note with `code` here',
          tags: [],
        ),
      ]);
      final prefs = await SharedPreferences.getInstance();
      final decoded = jsonDecode(prefs.getString('widget_recent_v1')!) as List;
      expect(decoded.first['preview'], 'A local-first note with code here');
    });

    test('bullet dashes no longer leak into the preview', () async {
      SharedPreferences.setMockInitialValues({});
      await NoteStorage().save([
        Note(id: 'p2', title: 'P2', content: '- buy milk', tags: []),
      ]);
      final prefs = await SharedPreferences.getInstance();
      final decoded = jsonDecode(prefs.getString('widget_recent_v1')!) as List;
      expect(decoded.first['preview'], 'buy milk');
    });
  });

  group('resolveImagePath', () {
    test('decodes Windows drive-letter schemes and %20', () {
      final uri = Uri.parse('c:/Users/John%20Smith/x.png');
      expect(
        resolveImagePath(uri, windows: true),
        r'c:\Users\John Smith\x.png',
      );
    });

    test('handles proper file URIs on Windows', () {
      final uri = Uri.parse('file:///C:/Users/John%20Smith/x.png');
      expect(
        resolveImagePath(uri, windows: true),
        r'C:\Users\John Smith\x.png',
      );
    });

    test('leaves POSIX paths alone when not on Windows', () {
      final uri = Uri.parse('/home/user/a%20b.png');
      expect(resolveImagePath(uri), '/home/user/a b.png');
    });
  });
}
