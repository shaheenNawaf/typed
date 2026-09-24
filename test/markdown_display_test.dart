import 'package:flutter_test/flutter_test.dart';
import 'package:typed/models/note.dart';
import 'package:typed/utils/markdown_display.dart';

void main() {
  Note note({
    String id = 'n1',
    String title = 'T',
    String content = '',
    List<String> tags = const [],
    String type = 'text',
    bool isArchived = false,
    bool isDeleted = false,
  }) =>
      Note(
        id: id,
        title: title,
        content: content,
        tags: tags,
        type: type,
        isArchived: isArchived,
        isDeleted: isDeleted,
      );

  group('stripInlineMarkdown', () {
    test('keeps the content of bold, italic, code, strike', () {
      expect(stripInlineMarkdown('Buy **milk** and eggs'), 'Buy milk and eggs');
      expect(
        stripInlineMarkdown('Pay the `electric` bill'),
        'Pay the electric bill',
      );
      expect(stripInlineMarkdown('*italic* and __bold__'), 'italic and bold');
      expect(stripInlineMarkdown('~~done~~ soon'), 'done soon');
    });

    test('resolves wikilinks and links, drops images whole', () {
      expect(
        stripInlineMarkdown('Review [[Welcome to Typed]]'),
        'Review Welcome to Typed',
      );
      expect(
        stripInlineMarkdown('See [[n123_abc|Daily expenses]]'),
        'See Daily expenses',
      );
      expect(stripInlineMarkdown('[Typed](https://example.com)'), 'Typed');
      expect(
        stripInlineMarkdown('pic ![image](data:image/png;base64,QUJD)'),
        'pic',
      );
    });

    test('keeps hyphens, snake_case, and lone underscores', () {
      expect(
        stripInlineMarkdown('local-first workspace'),
        'local-first workspace',
      );
      expect(
        stripInlineMarkdown('fix auth_token and _build'),
        'fix auth_token and _build',
      );
    });

    test('removes unpaired markers and is idempotent', () {
      expect(stripInlineMarkdown('odd * star'), isNot(contains('*')));
      const raw = 'Buy **milk** and eggs';
      final once = stripInlineMarkdown(raw);
      expect(stripInlineMarkdown(once), once);
    });
  });

  group('parseChecklist', () {
    test('parses markers, line indexes, and uppercase X', () {
      final items = parseChecklist(
        'intro\n- [ ] Buy **milk**\n- [X] Pay bill\n- not a task\n',
      );
      expect(items, hasLength(2));
      expect(items[0].lineIndex, 1);
      expect(items[0].done, isFalse);
      expect(items[0].text, 'Buy **milk**'); // RAW — display sites strip
      expect(items[1].lineIndex, 2);
      expect(items[1].done, isTrue);
    });

    test('empty-text template line parses with empty text', () {
      final items = parseChecklist('- [ ] \n');
      expect(items, hasLength(1));
      expect(items[0].text, '');
    });

    test('prose containing a literal [ ] does not parse', () {
      expect(
        parseChecklist('- Add items using `- [ ] task description`.'),
        isEmpty,
      );
      expect(hasChecklist('fill the [ ] box'), isFalse);
      expect(hasChecklist('- [ ] real'), isTrue);
    });
  });

  group('countChecklist / firstOpenItem', () {
    test('counts open/done/total with uppercase X', () {
      expect(
        countChecklist('- [ ] a\n- [X] b\n- [x] c\n'),
        (open: 1, done: 2, total: 3),
      );
    });

    test('firstOpenItem strips, skips done and empty items', () {
      expect(
        firstOpenItem('- [x] done one\n- [ ] Buy **milk**\n- [ ] second'),
        'Buy milk',
      );
      expect(firstOpenItem('- [x] all done'), isNull);
      expect(firstOpenItem('- [ ] \n- [ ] real'), 'real');
    });
  });

  group('task membership', () {
    test('seeds: guide tag, _welcome and _guide id suffixes', () {
      expect(isSeedNote(note(id: 'nabc_x0y1z2w_welcome')), isTrue);
      expect(isSeedNote(note(id: 'nabc_x0y1z2w_tasks_guide')), isTrue);
      expect(isSeedNote(note(id: 'n1', tags: ['guide'])), isTrue);
      expect(isSeedNote(note(id: 'n1')), isFalse);
    });

    test('isTaskNote: type, tag, title, checklist — not prose, not seeds', () {
      expect(isTaskNote(note(type: 'todo')), isTrue);
      expect(isTaskNote(note(tags: ['todo'])), isTrue);
      expect(isTaskNote(note(title: 'My Todo list')), isTrue);
      expect(isTaskNote(note(content: '- [ ] real task')), isTrue);
      expect(isTaskNote(note(content: 'fill the [ ] box')), isFalse);
      expect(isTaskNote(note(content: '- [ ] demo', id: 'nx_welcome')), isFalse);
      expect(isTaskNote(note(content: '- [ ] x', isArchived: true)), isFalse);
    });

    test('openTaskCount skips seeds, deleted, and counts [X] as done', () {
      final notes = [
        note(id: 'a', content: '- [ ] one\n- [X] two'),
        note(id: 'b_welcome', content: '- [ ] phantom\n- [ ] phantom2'),
        note(id: 'c', content: '- [ ] three', isDeleted: true),
      ];
      expect(openTaskCount(notes), 1);
    });
  });

  group('contentPreview', () {
    test('checkbox lines leave no stray x and keep code-span content', () {
      expect(
        contentPreview('- [ ] Buy **milk** and eggs\n- [x] Pay the `electric` bill'),
        'Buy milk and eggs Pay the electric bill',
      );
    });

    test('keeps hyphens (local-first, not localfirst)', () {
      expect(
        contentPreview('Your private, local-first workspace.'),
        'Your private, local-first workspace.',
      );
    });

    test('strips block syntax: headings, bullets, quotes, rules, tables', () {
      expect(
        contentPreview('# Title\n- item\n> quote\n---\n| a | b |'),
        'Title item quote',
      );
    });

    test('wikilinks resolve to titles; images vanish whole', () {
      expect(
        contentPreview('See [[n1|Daily expenses]] and [[Welcome]]'),
        'See Daily expenses and Welcome',
      );
      expect(
        contentPreview('pic ![image](data:image/png;base64,QUJD) after'),
        'pic after',
      );
    });

    test('caps at maxChars with ellipsis, surrogate-safe', () {
      final capped = contentPreview('word ' * 40, maxChars: 90);
      expect(capped.length, lessThanOrEqualTo(93));
      expect(capped.endsWith('...'), isTrue);
      final cut = contentPreview('${'x' * 89}\u{1F600}tail', maxChars: 90);
      expect(cut, isNot(contains('\uD83D')));
      expect(cut, '${'x' * 89}...');
    });

    test('short content passes through', () {
      expect(contentPreview('short', maxChars: 90), 'short');
    });
  });

  group('firstPreviewLine', () {
    test('skips headings and strips inline markdown (widget lock parity)', () {
      expect(
        firstPreviewLine('# Heading\nSome **body** text here'),
        'Some body text here',
      );
    });

    test('bullet dashes and checkbox markers no longer leak', () {
      expect(firstPreviewLine('- buy milk'), 'buy milk');
      expect(firstPreviewLine('- [x] Pay the `bill`'), 'Pay the bill');
    });

    test('falls back to the first line, heading marker stripped', () {
      expect(firstPreviewLine('# Only heading'), 'Only heading');
    });

    test('empty content yields empty string', () {
      expect(firstPreviewLine(''), '');
    });
  });
}