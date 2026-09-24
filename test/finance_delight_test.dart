import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typed/models/budget.dart';
import 'package:typed/models/money_entry.dart';
import 'package:typed/models/note.dart';
import 'package:typed/theme/palettes.dart';
import 'package:typed/utils/date_format.dart';
import 'package:typed/utils/finance_utils.dart';
import 'package:typed/widgets/count_up_amount.dart';
import 'package:typed/widgets/finance_dashboard.dart';

Note financeNote(String id) => Note(
      id: id,
      title: 'Daily expenses',
      content: '',
      tags: const ['finance'],
      type: 'expense',
      currency: 'PHP',
    );

MoneyEntry entry(String id, int amount, String category, String currency,
        {String type = 'expense', String? note}) =>
    MoneyEntry(
      id: id,
      amount: amount,
      category: category,
      date: DateTime(2026, 9, 15, 12),
      note: note,
      currency: currency,
      type: type,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ThemeData testTheme() => ThemeData(
        useMaterial3: true,
        extensions: <ThemeExtension<dynamic>>[kPalettes.first.light],
      );

  Widget wrap(Widget child) => MaterialApp(
        theme: testTheme(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  Widget noMotionWrap(Widget child) => MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          theme: testTheme(),
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );

  FinanceSummary summary({
    String dominant = 'PHP',
    bool mixed = false,
    Map<String, int> incomeByCurrency = const {'PHP': 4050000},
    Map<String, int> expenseByCurrency = const {'PHP': 914025},
    List<MapEntry<String, int>> categories = const [
      MapEntry('Groceries', 432625)
    ],
    List<(MoneyEntry, Note)> recent = const [],
    int entryCount = 0,
    double averageDailySpend = 0,
    bool averageAvailable = false,
    int previousPeriodExpense = 0,
    int previousPeriodIncome = 0,
  }) =>
      FinanceSummary(
        totalIncome: incomeByCurrency[dominant] ?? 0,
        totalExpense: expenseByCurrency[dominant] ?? 0,
        categories: categories,
        recentEntries: recent,
        entryCount: entryCount,
        dominantCurrency: dominant,
        incomeByCurrency: incomeByCurrency,
        expenseByCurrency: expenseByCurrency,
        hasMixedCurrencies: mixed,
        averageDailySpend: averageDailySpend,
        averageAvailable: averageAvailable,
        previousPeriodExpense: previousPeriodExpense,
        previousPeriodIncome: previousPeriodIncome,
      );

  Budget budget(String id, String category, int limit,
          {String currency = 'PHP', String period = 'month'}) =>
      Budget(id: id, category: category, limit: limit, currency: currency, period: period);

  group('relativeDayLabel', () {
    final now = DateTime(2026, 9, 21, 12);

    test('same day different times read Today', () {
      expect(relativeDayLabel(DateTime(2026, 9, 21, 0, 1), now: now), 'Today');
      expect(relativeDayLabel(DateTime(2026, 9, 21, 23, 59), now: now), 'Today');
    });

    test('the day before reads Yesterday', () {
      expect(relativeDayLabel(DateTime(2026, 9, 20), now: now), 'Yesterday');
    });

    test('within the last week reads the weekday', () {
      expect(relativeDayLabel(DateTime(2026, 9, 19), now: now), 'Sat');
      expect(relativeDayLabel(DateTime(2026, 9, 15), now: now), 'Tue');
    });

    test('a week back reads absolute M/D', () {
      expect(relativeDayLabel(DateTime(2026, 9, 14), now: now), '9/14');
    });

    test('future within a week reads the weekday', () {
      expect(relativeDayLabel(DateTime(2026, 9, 22), now: now), 'Tue');
      expect(relativeDayLabel(DateTime(2026, 9, 27), now: now), 'Sun');
    });

    test('far future reads absolute M/D', () {
      expect(relativeDayLabel(DateTime(2026, 10, 5), now: now), '10/5');
    });
  });

  group('CountUpAmount', () {
    testWidgets('counts up from zero and settles on the formatted amount',
        (tester) async {
      await tester.pumpWidget(wrap(CountUpAmount(
        minor: 123450,
        currency: 'PHP',
        style: const TextStyle(),
      )));
      await tester.pump();

      expect(find.textContaining('0.00'), findsOneWidget);
      expect(find.textContaining('1,234.50'), findsNothing);

      await tester.pumpAndSettle();
      expect(find.textContaining('1,234.50'), findsOneWidget);
    });

    testWidgets('renders the final value immediately under reduce-motion',
        (tester) async {
      await tester.pumpWidget(noMotionWrap(CountUpAmount(
        minor: 123450,
        currency: 'PHP',
        style: const TextStyle(),
      )));
      await tester.pump();

      expect(find.textContaining('1,234.50'), findsOneWidget);
    });

    testWidgets('negative amounts keep the sign', (tester) async {
      await tester.pumpWidget(wrap(CountUpAmount(
        minor: -123450,
        currency: 'PHP',
        style: const TextStyle(),
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('-1,234.50'), findsOneWidget);
    });

    testWidgets('JPY renders zero decimals', (tester) async {
      await tester.pumpWidget(wrap(CountUpAmount(
        minor: 12345,
        currency: 'JPY',
        style: const TextStyle(),
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('12,345'), findsOneWidget);
    });
  });

  group('SimpleFinanceView voice + states', () {
    testWidgets('simple view swaps the Net label for the kept percentage',
        (tester) async {
      await tester.pumpWidget(wrap(SimpleFinanceView(
        summary: summary(dominant: 'PHP'),
        budgets: const [],
        budgetActuals: const {},
      )));
      await tester.pumpAndSettle();

      expect(find.text('You kept 77%'), findsOneWidget);
      expect(find.text('Net'), findsNothing);
    });

    testWidgets('negative net keeps the plain Net label', (tester) async {
      await tester.pumpWidget(wrap(SimpleFinanceView(
        summary: summary(
          incomeByCurrency: const {'PHP': 100000},
          expenseByCurrency: const {'PHP': 150000},
        ),
        budgets: const [],
        budgetActuals: const {},
      )));
      await tester.pumpAndSettle();

      expect(find.text('Net'), findsOneWidget);
      expect(find.textContaining('You kept'), findsNothing);
    });

    testWidgets('on-track line shows when every budget is under 60%',
        (tester) async {
      await tester.pumpWidget(wrap(SimpleFinanceView(
        summary: summary(dominant: 'PHP'),
        budgets: [budget('b1', 'Groceries', 300000)],
        budgetActuals: const {'b1': 100000},
      )));
      await tester.pumpAndSettle();

      expect(find.text('All budgets on track.'), findsOneWidget);
    });

    testWidgets('on-track line hidden when a budget needs attention',
        (tester) async {
      await tester.pumpWidget(wrap(SimpleFinanceView(
        summary: summary(dominant: 'PHP'),
        budgets: [budget('b1', 'Groceries', 300000)],
        budgetActuals: const {'b1': 250000},
      )));
      await tester.pumpAndSettle();

      expect(find.text('All budgets on track.'), findsNothing);
      expect(find.textContaining('Groceries budget'), findsOneWidget);
    });

    testWidgets('on-track line hidden when there are no budgets', (tester) async {
      await tester.pumpWidget(wrap(SimpleFinanceView(
        summary: summary(dominant: 'PHP'),
        budgets: const [],
        budgetActuals: const {},
      )));
      await tester.pumpAndSettle();

      expect(find.text('All budgets on track.'), findsNothing);
    });
  });

  group('Money Kept card', () {
    testWidgets('show-more menu offers Money Kept with pct and honest footnote',
        (tester) async {
      await tester.pumpWidget(wrap(FinanceStickyHeader(
        summary: summary(dominant: 'PHP', entryCount: 1),
        period: 'month',
        onPeriodChanged: (_) {},
        currencySymbol: currencySymbol,
        currencyScope: 'all',
        currencyOptions: const ['all', 'PHP'],
      )));
      await tester.pump();

      await tester.tap(find.text('Show more'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Money Kept'));
      await tester.pumpAndSettle();

      expect(find.text('MONEY KEPT'), findsOneWidget);
      expect(find.text('77%'), findsOneWidget);
      expect(find.textContaining('31,359.75 of'), findsOneWidget);
      expect(find.textContaining('40,500.00 income'), findsOneWidget);
    });

    testWidgets('Money Kept shows Not available without income', (tester) async {
      await tester.pumpWidget(wrap(FinanceStickyHeader(
        summary: summary(
          incomeByCurrency: const {'PHP': 0},
          expenseByCurrency: const {'PHP': 5000},
          entryCount: 1,
        ),
        period: 'month',
        onPeriodChanged: (_) {},
        currencySymbol: currencySymbol,
        currencyScope: 'all',
        currencyOptions: const ['all', 'PHP'],
      )));
      await tester.pump();

      await tester.tap(find.text('Show more'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Money Kept'));
      await tester.pumpAndSettle();

      expect(find.text('Not available'), findsOneWidget);
      expect(find.text('77%'), findsNothing);
    });

    testWidgets('mixed currencies add the excl footnote', (tester) async {
      await tester.pumpWidget(wrap(FinanceStickyHeader(
        summary: summary(
          mixed: true,
          entryCount: 1,
          incomeByCurrency: const {'PHP': 4050000, 'USD': 50000},
          expenseByCurrency: const {'PHP': 914025, 'USD': 999},
        ),
        period: 'month',
        onPeriodChanged: (_) {},
        currencySymbol: currencySymbol,
        currencyScope: 'all',
        currencyOptions: const ['all', 'PHP', 'USD'],
      )));
      await tester.pump();

      await tester.tap(find.text('Show more'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Money Kept'));
      await tester.pumpAndSettle();

      expect(find.textContaining('excl. USD'), findsOneWidget);
    });
  });

  group('delta chip + budget card copy', () {
    testWidgets('delta chip reads as a sentence (up)', (tester) async {
      await tester.pumpWidget(wrap(FinanceStickyHeader(
        summary: summary(
          entryCount: 1,
          previousPeriodExpense: 565050,
          previousPeriodIncome: 3000000,
        ),
        period: 'month',
        onPeriodChanged: (_) {},
        currencySymbol: currencySymbol,
        currencyScope: 'all',
        currencyOptions: const ['all', 'PHP'],
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('Spending up 62% from last month'), findsOneWidget);
      expect(find.textContaining('Income up 35% from last month'), findsOneWidget);
    });

    testWidgets('delta chip reads as a sentence (down)', (tester) async {
      await tester.pumpWidget(wrap(FinanceStickyHeader(
        summary: summary(
          entryCount: 1,
          previousPeriodExpense: 1914025,
        ),
        period: 'month',
        onPeriodChanged: (_) {},
        currencySymbol: currencySymbol,
        currencyScope: 'all',
        currencyOptions: const ['all', 'PHP'],
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('Spending down 52% from last month'), findsOneWidget);
    });

    testWidgets('budget card says left to spend', (tester) async {
      await tester.pumpWidget(wrap(FinanceDashboardBody(
        summary: summary(dominant: 'PHP'),
        period: 'month',
        currencySymbol: currencySymbol,
        budgets: [budget('b1', 'Groceries', 300000)],
        budgetActuals: const {'b1': 234575},
        currencyScope: 'all',
        onAddBudget: (_) {},
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('left to spend'), findsOneWidget);
      expect(find.textContaining('654.25'), findsOneWidget);
      expect(find.textContaining('Left '), findsNothing);
    });
  });
}