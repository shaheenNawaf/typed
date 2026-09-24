import 'package:flutter_test/flutter_test.dart';
import 'package:typed/models/budget.dart';
import 'package:typed/utils/onboarding.dart';
import 'package:typed/widgets/finance_dashboard.dart';
import 'package:typed/utils/backup.dart';
import 'package:typed/utils/id.dart';
import 'package:typed/utils/slash_commands.dart';

void main() {
  group('generateId', () {
    test('starts with the given prefix', () {
      expect(generateId('n').startsWith('n'), isTrue);
      expect(generateId('m').startsWith('m'), isTrue);
      expect(generateId('b').startsWith('b'), isTrue);
    });

    test('produces unique ids across rapid calls', () {
      final ids = <String>{};
      for (var i = 0; i < 1000; i++) {
        ids.add(generateId('n'));
      }
      expect(ids.length, 1000);
    });

    test('produces unique ids across different prefixes', () {
      final a = generateId('n');
      final b = generateId('m');
      expect(a, isNot(equals(b)));
    });
  });

  group('csvEscape', () {
    test('leaves plain fields unchanged', () {
      expect(csvEscape('hello'), 'hello');
      expect(csvEscape(''), '');
      expect(csvEscape('with space'), 'with space');
    });

    test('wraps fields containing commas', () {
      expect(csvEscape('a,b'), '"a,b"');
    });

    test('doubles embedded quotes', () {
      expect(csvEscape('say "hi"'), '"say ""hi"""');
    });

    test('wraps fields containing newlines', () {
      expect(csvEscape('line1\nline2'), '"line1\nline2"');
    });
  });

  group('slash commands', () {
    test('detects a slash token at the start of a line', () {
      final token = activeSlashToken('/h2', 3);
      expect(token?.start, 0);
      expect(token?.query, 'h2');
    });

    test('detects a slash token after whitespace', () {
      final token = activeSlashToken('Write /todo', 11);
      expect(token?.query, 'todo');
    });

    test('rejects slashes inside ordinary words and urls', () {
      expect(activeSlashToken('https://typed.dev', 8), isNull);
      expect(activeSlashToken('word/todo', 9), isNull);
    });

    test('filters commands by aliases', () {
      final matches = filterSlashCommands('checklist');
      expect(matches.map((command) => command.id), contains('todo'));
    });

    test('replaces only the active slash token', () {
      final text = 'Before /h2 after';
      final token = activeSlashToken(text, 10)!;
      expect(replaceSlashToken(text, token, '## '), 'Before ##  after');
    });
  });

  group('finance compatibility', () {
    test('old budgets receive safe currency and period defaults', () {
      final budget = Budget.fromJson({
        'id': 'b-old',
        'category': 'Food',
        'limit': 5000,
      });

      expect(budget.currency, 'PHP');
      expect(budget.period, 'month');
      expect(budget.toJson()['currency'], 'PHP');
      expect(budget.toJson()['period'], 'month');
    });

    test('finance summary exposes truthful per-currency net values', () {
      const summary = FinanceSummary(
        totalIncome: 100,
        totalExpense: 40,
        categories: [],
        recentEntries: [],
        entryCount: 2,
        dominantCurrency: 'PHP',
        incomeByCurrency: {'PHP': 100, 'USD': 20},
        expenseByCurrency: {'PHP': 40, 'USD': 5},
        hasMixedCurrencies: true,
        averageAvailable: true,
        noteIds: {'n1'},
      );

      expect(summary.netByCurrency['PHP'], 60);
      expect(summary.netByCurrency['USD'], 15);
      expect(summary.noteIds, contains('n1'));
    });
  });

  test('onboarding includes workspace how-to guides', () {
    final data = createOnboardingData();
    final titles = data.notes.map((note) => note.title).toSet();

    expect(titles, contains('Welcome to Typed'));
    expect(titles, contains('Using Notes'));
    expect(titles, contains('Managing Tasks'));
    expect(titles, contains('Tracking Finance'));
    expect(titles, contains('Navigating Typed'));
    expect(
      data.notes.firstWhere((note) => note.title == 'Tracking Finance').content,
      contains('dock'),
    );
  });
}
