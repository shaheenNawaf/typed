import 'package:flutter_test/flutter_test.dart';
import 'package:typed/models/money_entry.dart';
import 'package:typed/models/note.dart';
import 'package:typed/utils/note_kind.dart';

void main() {
  Note note({
    String type = 'text',
    bool isArchived = false,
    bool isDeleted = false,
    List<MoneyEntry>? amounts,
  }) =>
      Note(
        id: 'n1',
        title: 'Note',
        content: '',
        tags: const [],
        type: type,
        isArchived: isArchived,
        isDeleted: isDeleted,
        amounts: amounts,
      );

  group('isFinanceType', () {
    test('accepts expense and income', () {
      expect(isFinanceType('expense'), isTrue);
      expect(isFinanceType('income'), isTrue);
    });

    test('rejects every other value, case-sensitively', () {
      expect(isFinanceType('text'), isFalse);
      expect(isFinanceType('todo'), isFalse);
      expect(isFinanceType(null), isFalse);
      expect(isFinanceType(''), isFalse);
      expect(isFinanceType('Finance'), isFalse);
      expect(isFinanceType('EXPENSE'), isFalse);
    });
  });

  group('isFinanceNote', () {
    test('matches only expense and income notes', () {
      expect(isFinanceNote(note(type: 'text')), isFalse);
      expect(isFinanceNote(note(type: 'todo')), isFalse);
      expect(isFinanceNote(note(type: 'expense')), isTrue);
      expect(isFinanceNote(note(type: 'income')), isTrue);
    });
  });

  group('isVisibleFinanceNote', () {
    test('excludes archived expense notes', () {
      expect(
        isVisibleFinanceNote(note(type: 'expense', isArchived: true)),
        isFalse,
      );
    });

    test('excludes trashed expense notes', () {
      expect(
        isVisibleFinanceNote(note(type: 'expense', isDeleted: true)),
        isFalse,
      );
    });

    test('excludes notes both archived and trashed', () {
      expect(
        isVisibleFinanceNote(
          note(type: 'income', isArchived: true, isDeleted: true),
        ),
        isFalse,
      );
    });

    test('includes plain expense and income notes', () {
      expect(isVisibleFinanceNote(note(type: 'expense')), isTrue);
      expect(isVisibleFinanceNote(note(type: 'income')), isTrue);
    });
  });

  test('a todo note carrying amounts is not a finance note', () {
    final n = note(
      type: 'todo',
      amounts: [
        MoneyEntry(
          id: 'm1',
          amount: 100,
          category: 'Food',
          date: DateTime(2026, 1, 1),
        ),
      ],
    );
    expect(isFinanceNote(n), isFalse);
    expect(n.amounts.isNotEmpty, isTrue);
  });

  test('archive and trash are excluded from totals but not from the type check', () {
    final n = note(type: 'expense', isArchived: true);
    expect(isFinanceNote(n), isTrue);
    expect(isVisibleFinanceNote(n), isFalse);
  });
}