import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typed/models/budget.dart';
import 'package:typed/models/money_entry.dart';
import 'package:typed/models/note.dart';
import 'package:typed/theme/palettes.dart';
import 'package:typed/widgets/finance_dashboard.dart';
import 'package:typed/widgets/spend_sparkline.dart';
import 'package:typed/utils/finance_utils.dart';

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
      );

  Budget budget(String id, String category, int limit,
          {String currency = 'PHP', String period = 'month'}) =>
      Budget(id: id, category: category, limit: limit, currency: currency, period: period);

  testWidgets('budget section respects the currency scope', (tester) async {
    await tester.pumpWidget(wrap(FinanceDashboardBody(
      summary: summary(),
      period: 'month',
      currencySymbol: currencySymbol,
      currencyScope: 'USD',
      budgets: [
        budget('b1', 'Food & Drink', 70000),
        budget('b2', 'Subscriptions', 1500, currency: 'USD'),
      ],
      budgetActuals: const {'b1': 77050, 'b2': 999},
      onAddBudget: (_) {},
    )));
    await tester.pump();

    expect(find.text('Subscriptions'), findsOneWidget);
    expect(find.text('Food & Drink'), findsNothing);
    expect(find.textContaining('No USD budgets yet'), findsNothing);
  });

  testWidgets('budget section shows the empty-scope message when no budget matches',
      (tester) async {
    await tester.pumpWidget(wrap(FinanceDashboardBody(
      summary: summary(),
      period: 'month',
      currencySymbol: currencySymbol,
      currencyScope: 'USD',
      budgets: [budget('b1', 'Food & Drink', 70000)],
      onAddBudget: (_) {},
    )));
    await tester.pump();

    expect(find.text('No USD budgets yet.'), findsOneWidget);
  });

  testWidgets('overspent budget shows the unclamped percent', (tester) async {
    await tester.pumpWidget(wrap(FinanceDashboardBody(
      summary: summary(categories: const []),
      period: 'month',
      currencySymbol: currencySymbol,
      currencyScope: 'all',
      budgets: [budget('b1', 'Food & Drink', 70000)],
      budgetActuals: const {'b1': 77050},
      onAddBudget: (_) {},
    )));
    await tester.pump();

    expect(find.text('110%'), findsOneWidget);
    expect(find.text('100%'), findsNothing);
    expect(find.textContaining('over budget'), findsOneWidget);
  });

  testWidgets('mixed budgets get currency labels under the all scope', (tester) async {
    await tester.pumpWidget(wrap(FinanceDashboardBody(
      summary: summary(),
      period: 'month',
      currencySymbol: currencySymbol,
      currencyScope: 'all',
      budgets: [
        budget('b1', 'Food & Drink', 70000),
        budget('b2', 'Subscriptions', 1500, currency: 'USD'),
      ],
      onAddBudget: (_) {},
    )));
    await tester.pump();

    expect(find.textContaining('PHP · Monthly'), findsOneWidget);
    expect(find.textContaining('USD · Monthly'), findsOneWidget);
  });

  testWidgets('mixed-currency income card stacks symbol lines, not ISO joined text',
      (tester) async {
    final s = summary(
      mixed: true,
      entryCount: 1,
      incomeByCurrency: const {'PHP': 4050000, 'USD': 50000},
    );
    await tester.pumpWidget(wrap(FinanceStickyHeader(
      summary: s,
      period: 'month',
      onPeriodChanged: (_) {},
      currencySymbol: currencySymbol,
      currencyScope: 'all',
      currencyOptions: const ['all', 'PHP', 'USD'],
    )));
    await tester.pump();

    expect(find.textContaining('40,500.00'), findsWidgets);
    expect(find.textContaining('500.00'), findsWidgets);
    expect(find.textContaining('PHP 40,500.00 | USD'), findsNothing);
    expect(find.textContaining('| USD'), findsNothing);
  });

  testWidgets(
      'avg daily spend shows a dominant-currency number with an excl footnote when mixed',
      (tester) async {
    final s = summary(
      mixed: true,
      entryCount: 1,
      averageAvailable: true,
      averageDailySpend: 45701.25,
      expenseByCurrency: const {'PHP': 914025, 'USD': 999},
    );
    await tester.pumpWidget(wrap(FinanceStickyHeader(
      summary: s,
      period: 'month',
      onPeriodChanged: (_) {},
      currencySymbol: currencySymbol,
      currencyScope: 'all',
      currencyOptions: const ['all', 'PHP', 'USD'],
    )));
    await tester.pump();

    await tester.tap(find.text('Show more'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Avg Daily Spend'));
    await tester.pumpAndSettle();

    expect(find.textContaining('457.01'), findsOneWidget);
    expect(find.text('excl. USD'), findsOneWidget);
    expect(find.text('Mixed currencies'), findsNothing);
  });

  testWidgets('simple view caps warnings at two and links to advanced', (tester) async {
    await tester.pumpWidget(wrap(SimpleFinanceView(
      summary: summary(dominant: 'PHP'),
      budgets: [
        budget('b1', 'Food & Drink', 70000),
        budget('b2', 'Groceries', 300000),
        budget('b3', 'Transport', 150000),
      ],
      budgetActuals: const {'b1': 77050, 'b2': 234575, 'b3': 120000},
      onOpenAdvanced: () {},
    )));
    await tester.pump();

    expect(find.textContaining('Food & Drink budget'), findsOneWidget);
    expect(find.textContaining('Transport budget'), findsOneWidget);
    expect(find.textContaining('Groceries budget'), findsNothing);
    expect(find.text('1 more budget needs attention'), findsOneWidget);
  });

  testWidgets('see-all toggle expands the transaction list', (tester) async {
    final recent = <(MoneyEntry, Note)>[
      (entry('e1', 10000, 'Cat 1', 'PHP'), financeNote('n1')),
      (entry('e2', 20000, 'Cat 2', 'PHP'), financeNote('n2')),
      (entry('e3', 30000, 'Cat 3', 'PHP'), financeNote('n3')),
      (entry('e4', 40000, 'Cat 4', 'PHP'), financeNote('n4')),
      (entry('e5', 50000, 'Cat 5', 'PHP'), financeNote('n5')),
      (entry('e6', 60000, 'Cat 6', 'PHP'), financeNote('n6')),
      (entry('e7', 70000, 'Cat 7', 'PHP'), financeNote('n7')),
    ];
    await tester.pumpWidget(wrap(FinanceDashboardBody(
      summary: summary(recent: recent, entryCount: 7),
      period: 'month',
      currencySymbol: currencySymbol,
      onSelectEntry: (_, __) {},
    )));
    await tester.pump();

    expect(find.text('Cat 1'), findsNWidgets(2));
    expect(find.text('Cat 7'), findsNothing);
    expect(find.textContaining('See all 7 transactions'), findsOneWidget);

    await tester.ensureVisible(find.textContaining('See all 7 transactions'));
    await tester.tap(find.textContaining('See all 7 transactions'));
    await tester.pumpAndSettle();

    expect(find.text('Cat 7'), findsNWidgets(2));
    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('row tap reports noteId and entryId to onSelectEntry', (tester) async {
    (String, String)? collected;
    await tester.pumpWidget(wrap(FinanceDashboardBody(
      summary: summary(
        recent: [(entry('e9', 90000, 'Cat 9', 'PHP'), financeNote('n9'))],
        entryCount: 1,
      ),
      period: 'month',
      currencySymbol: currencySymbol,
      onSelectEntry: (noteId, entryId) => collected = (noteId, entryId),
    )));
    await tester.pump();

    await tester.tap(find.text('Cat 9').first);
    await tester.pumpAndSettle();

    expect(collected, ('n9', 'e9'));
  });

  testWidgets('sparkline shows the empty state when all days are zero', (tester) async {
    await tester.pumpWidget(wrap(SpendSparkline(
      dailyTotals: List<int>.filled(14, 0),
      currency: 'PHP',
    )));
    await tester.pump();

    expect(find.text('No spending in the last 14 days'), findsOneWidget);
    expect(find.text('LAST 14 DAYS'), findsOneWidget);
  });

  testWidgets('sparkline paints bars and the 14-day total when there is data',
      (tester) async {
    await tester.pumpWidget(wrap(SpendSparkline(
      dailyTotals: const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 18550],
      currency: 'PHP',
    )));
    await tester.pumpAndSettle();

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.textContaining('185.50'), findsOneWidget);
    expect(find.text('No spending in the last 14 days'), findsNothing);
  });
}