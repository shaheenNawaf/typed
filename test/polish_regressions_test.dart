import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typed/models/budget.dart';
import 'package:typed/models/money_entry.dart';
import 'package:typed/models/note.dart';
import 'package:typed/utils/date_grouping.dart';
import 'package:typed/utils/finance_utils.dart';
import 'package:typed/utils/markdown_display.dart';
import 'package:typed/utils/note_storage.dart';
import 'package:typed/utils/slash_commands.dart';
import 'package:typed/utils/streak.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('com.z4yed.typed/widget'),
    (call) async => null,
  );

  group('formatMinorAmount', () {
    test('puts a true minus before the symbol', () {
      expect(formatMinorAmount(-50000, 'PHP'), '−₱500.00');
      expect(formatMinorAmount(-1, 'USD'), '−\$0.01');
    });

    test('zero and positives carry no sign', () {
      expect(formatMinorAmount(0, 'PHP'), '₱0.00');
      expect(formatMinorAmount(123456, 'JPY'), '¥123,456');
    });
  });

  group('amount parsing', () {
    test('rejects absurdly long input instead of throwing or wrapping', () {
      expect(parseAmountToMinor('1' * 20, 'PHP'), isNull);
      expect(parseAmountToMinor('9' * 18, 'PHP'), isNull);
      expect(parseAmountToMinor('1' * 13, 'PHP'), 1111111111111 * 100);
    });

    test('the error names the currency rule', () {
      expect(amountFormatError('JPY', example: '250'), contains('no decimals'));
      expect(amountFormatError('PHP', example: '250'), contains('2 decimals'));
    });
  });

  group('budget periods', () {
    test('only week, month and year survive', () {
      expect(normalizeBudgetPeriod('week'), 'week');
      expect(normalizeBudgetPeriod('year'), 'year');
      expect(normalizeBudgetPeriod('all'), 'month');
      expect(normalizeBudgetPeriod('day'), 'month');
      expect(normalizeBudgetPeriod(null), 'month');
    });

    test('stored "all" budgets load as monthly', () {
      final budget = Budget.fromJson({
        'id': 'b1',
        'category': 'Food',
        'limit': 500000,
        'period': 'all',
      });
      expect(budget.period, 'month');
    });
  });

  group('slash commands', () {
    test('prose with a spaced slash does not open the menu', () {
      const text = 'tea and / or';
      expect(activeSlashToken(text, text.length), isNull);
      const fraction = '1 / 2';
      expect(activeSlashToken(fraction, fraction.length), isNull);
    });

    test('commands typed flush against the slash still match', () {
      expect(activeSlashToken('/head', 5)?.query, 'head');
      const multi = '/bullet list';
      expect(activeSlashToken(multi, multi.length)?.query, 'bullet list');
    });
  });

  test('checklists accept *, + and - bullets', () {
    final items = parseChecklist('* [ ] star\n+ [x] plus\n- [ ] dash\n');
    expect(items.map((i) => i.text), ['star', 'plus', 'dash']);
    expect(items.map((i) => i.done), [false, true, false]);
  });

  test('calendar day diff counts calendar days, not 24h blocks', () {
    expect(
      calendarDayDiff(DateTime(2026, 3, 8, 23, 30), DateTime(2026, 3, 9, 0, 30)),
      -1,
    );
    expect(dateSection(DateTime(2026, 3, 8, 23), now: DateTime(2026, 3, 9, 1)),
        'Yesterday');
  });

  group('writing streak', () {
    Note noteAt(String id, DateTime when) =>
        Note(id: id, title: id, content: 'x', tags: const [], updatedAt: when);

    test('reports the last seven days, today last', () {
      final now = DateTime(2026, 10, 16, 12);
      final streak = computeWritingStreak([
        noteAt('a', now),
        noteAt('b', DateTime(2026, 10, 14, 9)),
      ], now: now);
      expect(streak.days, 1);
      expect(streak.lastSevenDays,
          [false, false, false, false, true, false, true]);
    });

    test('counts across a month boundary', () {
      final now = DateTime(2026, 11, 1, 8);
      final streak = computeWritingStreak([
        noteAt('a', now),
        noteAt('b', DateTime(2026, 10, 31, 22)),
        noteAt('c', DateTime(2026, 10, 30, 7)),
      ], now: now);
      expect(streak.days, 3);
    });
  });

  test('localEpochDay is a plain calendar-day count', () {
    expect(localEpochDay(DateTime(1970, 1, 1, 23, 59)), 0);
    expect(localEpochDay(DateTime(1970, 1, 2)), 1);
    expect(
      localEpochDay(DateTime(2026, 3, 9)) - localEpochDay(DateTime(2026, 3, 8)),
      1,
    );
  });

  group('home-screen widget payloads', () {
    Future<SharedPreferences> saved(List<Note> notes,
        {List<Budget> budgets = const []}) async {
      SharedPreferences.setMockInitialValues({});
      final storage = NoteStorage();
      await storage.saveBudgets(budgets);
      await storage.save(notes);
      return SharedPreferences.getInstance();
    }

    test('a finance note without prose gets an entry summary preview',
        () async {
      final prefs = await saved([
        Note(
          id: 'f1',
          title: 'Finance — October 2026',
          content: '',
          tags: const ['finance'],
          type: 'expense',
          amounts: [
            MoneyEntry(
              id: 'e1',
              amount: 1000,
              category: 'Food',
              date: DateTime.now(),
            ),
          ],
        ),
        Note(
          id: 'f2',
          title: 'Empty ledger',
          content: '',
          tags: const ['finance'],
          type: 'expense',
        ),
      ]);
      final recent = jsonDecode(prefs.getString('widget_recent_v1')!) as List;
      final byId = {for (final r in recent) r['id']: r['preview']};
      expect(byId['f1'], '1 entry');
      expect(byId['f2'], 'No entries yet');
    });

    test('the streak payload carries its day and a 7-day history', () async {
      final prefs = await saved([
        Note(id: 'n1', title: 'Today', content: 'x', tags: const []),
      ]);
      final streak =
          jsonDecode(prefs.getString('widget_streak_v1')!) as Map;
      expect(streak['asOfDay'], localEpochDay(DateTime.now()));
      expect(streak['week'], hasLength(7));
      expect((streak['week'] as List).last, isTrue);
    });

    test('the finance payload is month-stamped and carries budget amounts',
        () async {
      final now = DateTime.now();
      final prefs = await saved(
        [
          Note(
            id: 'f1',
            title: 'Spending',
            content: '',
            tags: const ['finance'],
            type: 'expense',
            currency: 'PHP',
            amounts: [
              MoneyEntry(
                id: 'e1',
                amount: 320000,
                category: 'Food',
                date: now,
                currency: 'PHP',
              ),
            ],
          ),
        ],
        budgets: [
          Budget(id: 'b1', category: 'Food', limit: 500000, currency: 'PHP'),
        ],
      );
      final finance =
          jsonDecode(prefs.getString('widget_finance_v1')!) as Map;
      expect(finance['monthIndex'], now.year * 12 + now.month - 1);
      expect(finance['currencyCount'], 1);
      expect(finance['budgetSpentText'], '₱3,200.00');
      expect(finance['budgetLimitText'], '₱5,000.00');
      expect(finance['balanceText'], '−₱3,200.00');
    });

    test('sample data stays off the finance widget', () async {
      final prefs = await saved(
        [
          Note(
            id: 'seed_finance',
            title: 'Sample',
            content: '',
            tags: const ['finance'],
            type: 'expense',
            currency: 'PHP',
            amounts: [
              MoneyEntry(
                id: 'demo',
                amount: 99900,
                category: 'Food',
                date: DateTime.now(),
                isDemo: true,
              ),
            ],
          ),
        ],
        budgets: [
          Budget(id: 'b', category: 'Food', limit: 100000, isDemo: true),
        ],
      );
      final finance =
          jsonDecode(prefs.getString('widget_finance_v1')!) as Map;
      expect(finance['empty'], isTrue);
      expect(finance['hasBudget'], isFalse);
    });
  });
}
