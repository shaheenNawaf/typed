import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typed/models/budget.dart';
import 'package:typed/models/money_entry.dart';
import 'package:typed/models/note.dart';
import 'package:typed/theme/palettes.dart';
import 'package:typed/widgets/finance_dashboard.dart';
import 'package:typed/widgets/spend_sparkline.dart';
import 'package:typed/utils/finance_utils.dart';
import 'package:typed/utils/date_format.dart';

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
          {String type = 'expense', String? note, DateTime? date}) =>
      MoneyEntry(
        id: id,
        amount: amount,
        category: category,
        date: date ?? DateTime(2026, 9, 15, 12),
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
    bool hasAnyEntries = true,
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
        hasAnyEntries: hasAnyEntries,
        averageDailySpend: averageDailySpend,
        averageAvailable: averageAvailable,
        previousPeriodExpense: previousPeriodExpense,
        previousPeriodIncome: previousPeriodIncome,
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
    expect(find.text('Last 14 days'), findsOneWidget);
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

  testWidgets('an empty period names the period and offers all time', (tester) async {
    await tester.pumpWidget(wrap(SizedBox(height: 600, child: FinanceWorkspace(
      summary: summary(entryCount: 0),
      period: 'month',
      onPeriodChanged: (_) {},
      currencySymbol: currencySymbol,
      currencyScope: 'all',
      currencyOptions: const ['all', 'PHP', 'USD'],
      onViewAllTime: () {},
    ))));
    await tester.pump();

    expect(find.textContaining('No transactions in '), findsOneWidget);
    expect(find.text('View all time'), findsOneWidget);
  });

  testWidgets('all time hides the view-all-time link', (tester) async {
    await tester.pumpWidget(wrap(SizedBox(height: 600, child: FinanceWorkspace(
      summary: summary(entryCount: 0),
      period: 'all',
      onPeriodChanged: (_) {},
      currencySymbol: currencySymbol,
      currencyScope: 'all',
      currencyOptions: const ['all', 'PHP', 'USD'],
      onViewAllTime: () {},
    ))));
    await tester.pump();

    expect(find.text('No transactions in All time.'), findsOneWidget);
    expect(find.text('View all time'), findsNothing);
  });

  testWidgets('zero transactions ever shows one empty state and no cards', (tester) async {
    var expenseTaps = 0;
    var incomeTaps = 0;
    await tester.pumpWidget(wrap(SizedBox(height: 600, child: FinanceWorkspace(
      summary: summary(hasAnyEntries: false, entryCount: 0),
      period: 'month',
      onPeriodChanged: (_) {},
      currencySymbol: currencySymbol,
      currencyScope: 'all',
      currencyOptions: const ['all', 'PHP', 'USD'],
      budgets: const [],
      onAddExpense: () => expenseTaps++,
      onAddIncome: () => incomeTaps++,
    ))));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('No transactions yet'), findsOneWidget);
    expect(find.text('Track your spending, income and budgets in one place.'), findsOneWidget);
    expect(find.text('Add expense'), findsOneWidget);
    expect(find.text('Add income'), findsOneWidget);

    expect(find.text('Income'), findsNothing);
    expect(find.text('Expenses'), findsNothing);
    expect(find.text('Net'), findsNothing);
    expect(find.text('Transactions'), findsNothing);
    expect(find.text('Last 14 days'), findsNothing);
    expect(find.text('Top categories'), findsNothing);
    expect(find.text('Budgets'), findsNothing);

    expect(find.text('All'), findsNothing);
    expect(find.text('Month'), findsNothing);

    await tester.tap(find.text('Add expense'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(expenseTaps, 1);
    expect(incomeTaps, 0);
  });

  testWidgets('zero transactions ever still lists existing budgets', (tester) async {
    await tester.pumpWidget(wrap(SizedBox(height: 600, child: FinanceWorkspace(
      summary: summary(hasAnyEntries: false, entryCount: 0),
      period: 'month',
      onPeriodChanged: (_) {},
      currencySymbol: currencySymbol,
      currencyScope: 'all',
      currencyOptions: const ['all', 'PHP', 'USD'],
      budgets: [budget('b1', 'Food & Drink', 70000)],
      onAddBudget: (_) {},
    ))));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('No transactions yet'), findsOneWidget);
    expect(find.text('Budgets'), findsOneWidget);
    expect(find.text('Add budget'), findsOneWidget);

    expect(find.text('Transactions'), findsNothing);
    expect(find.text('Top categories'), findsNothing);
  });

  testWidgets('zero transactions ever hides the budgets block when there are none',
      (tester) async {
    await tester.pumpWidget(wrap(SizedBox(height: 600, child: FinanceWorkspace(
      summary: summary(hasAnyEntries: false, entryCount: 0),
      period: 'month',
      onPeriodChanged: (_) {},
      currencySymbol: currencySymbol,
      currencyScope: 'all',
      currencyOptions: const ['all', 'PHP', 'USD'],
      budgets: const [],
      onAddBudget: (_) {},
    ))));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('No transactions yet'), findsOneWidget);
    expect(find.text('Budgets'), findsNothing);
    expect(find.text('No budgets yet. Add one to track spending against a limit.'), findsNothing);
  });

  testWidgets('the add buttons sit beside the period filter', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(SizedBox(height: 600, child: FinanceWorkspace(
      summary: summary(),
      period: 'month',
      onPeriodChanged: (_) {},
      currencySymbol: currencySymbol,
      currencyScope: 'all',
      currencyOptions: const ['all', 'PHP', 'USD'],
      onAddExpense: () {},
      onAddIncome: () {},
    ))));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Expense'), findsOneWidget);
    // 'Income' labels only the add button now; scoped for safety anyway.
    expect(
      find.descendant(
        of: find.bySubtype<OutlinedButton>(),
        matching: find.text('Income'),
      ),
      findsOneWidget,
    );
    // ElevatedButton.icon builds the private _ElevatedButtonWithIcon subclass,
    // which find.byType (exact-type) cannot match.
    expect(find.bySubtype<ElevatedButton>(), findsOneWidget);
    expect(find.bySubtype<OutlinedButton>(), findsWidgets);

    final messages =
        tester.widgetList<Tooltip>(find.byType(Tooltip)).map((t) => t.message);
    expect(messages, contains('Expense (E)'));
    expect(messages, contains('Income (I)'));
  });

  testWidgets('expense is the primary action', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(SizedBox(height: 600, child: FinanceWorkspace(
      summary: summary(),
      period: 'month',
      onPeriodChanged: (_) {},
      currencySymbol: currencySymbol,
      currencyScope: 'all',
      currencyOptions: const ['all', 'PHP', 'USD'],
      onAddExpense: () {},
      onAddIncome: () {},
    ))));
    await tester.pump(const Duration(milliseconds: 400));

    final expenseButton = find.bySubtype<ElevatedButton>();
    expect(
      find.descendant(of: expenseButton, matching: find.text('Expense')),
      findsOneWidget,
    );
  });

  testWidgets('the add buttons fit beside the filters at 1024', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(SizedBox(height: 600, child: FinanceWorkspace(
      summary: summary(),
      period: 'month',
      onPeriodChanged: (_) {},
      currencySymbol: currencySymbol,
      currencyScope: 'all',
      currencyOptions: const ['all', 'PHP', 'USD'],
      onAddExpense: () {},
      onAddIncome: () {},
    ))));
    await tester.pump(const Duration(milliseconds: 400));

    Object? exception;
    while ((exception = tester.takeException()) != null) {
      expect('$exception', isNot(contains('overflowed')));
    }
  });

  testWidgets('capture buttons show their keyboard hints', (tester) async {
    await tester.pumpWidget(wrap(SizedBox(height: 600, child: FinanceWorkspace(
      summary: summary(),
      budgets: const [],
      period: 'month',
      onPeriodChanged: (_) {},
      currencySymbol: currencySymbol,
      currencyScope: 'all',
      currencyOptions: const ['all', 'PHP', 'USD'],
      dailyTotals: const [],
      onAddExpense: () {},
      onAddIncome: () {},
    ))));
    await tester.pumpAndSettle();
    expect(find.text('E'), findsOneWidget);
    expect(find.text('I'), findsOneWidget);
  });

  testWidgets('workspace shows the hero net, savings sentence, In and Out',
      (tester) async {
    await tester.pumpWidget(wrap(SizedBox(height: 600, child: FinanceWorkspace(
      summary: summary(),
      period: 'month',
      onPeriodChanged: (_) {},
      currencySymbol: currencySymbol,
      currencyScope: 'all',
      currencyOptions: const ['all', 'PHP', 'USD'],
    ))));
    await tester.pumpAndSettle();

    expect(find.text('Net · ${periodName('month')}'), findsOneWidget);
    expect(find.text('In'), findsOneWidget);
    expect(find.text('Out'), findsOneWidget);
    expect(find.text('Income'), findsNothing);
    expect(find.text('Expenses'), findsNothing);
    expect(find.text('Saved'), findsNothing);
    expect(find.text('Avg daily spend'), findsNothing);
    expect(find.textContaining('You kept', findRichText: true), findsOneWidget);
    expect(find.textContaining('77%', findRichText: true), findsOneWidget);
    expect(find.textContaining('40,500.00', findRichText: true), findsWidgets);
  });

  testWidgets('In and Out cards carry count sub-lines', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9);
    final recent = <(MoneyEntry, Note)>[
      (
        entry('e1', 18000, 'Food & Drink', 'PHP', date: today),
        financeNote('n1'),
      ),
      (
        entry('e2', 50000, 'Freelance', 'PHP', type: 'income', date: today),
        financeNote('n2'),
      ),
    ];
    await tester.pumpWidget(wrap(SizedBox(height: 600, child: FinanceWorkspace(
      summary: summary(recent: recent, entryCount: 2),
      budgets: const [],
      period: 'month',
      onPeriodChanged: (_) {},
      currencySymbol: currencySymbol,
      currencyScope: 'all',
      currencyOptions: const ['all', 'PHP', 'USD'],
      dailyTotals: const [],
    ))));
    await tester.pumpAndSettle();
    expect(find.text('1 source · Freelance'), findsOneWidget);
    expect(find.text('1 entry'), findsOneWidget);
  });

  testWidgets('hero sentence declares excluded currencies when mixed',
      (tester) async {
    final s = summary(
      mixed: true,
      entryCount: 1,
      incomeByCurrency: const {'PHP': 4050000, 'USD': 50000},
    );
    await tester.pumpWidget(wrap(SizedBox(height: 600, child: FinanceWorkspace(
      summary: s,
      period: 'month',
      onPeriodChanged: (_) {},
      currencySymbol: currencySymbol,
      currencyScope: 'all',
      currencyOptions: const ['all', 'PHP', 'USD'],
    ))));
    await tester.pumpAndSettle();

    // Rich sub-line: amount + code (prototype "excl. $9.99 USD").
    expect(find.text('excl. \$500.00 USD'), findsOneWidget);
    expect(find.textContaining('· excl. USD', findRichText: true), findsOneWidget);
  });

  testWidgets('hero shows the em dash instead of the sentence without income',
      (tester) async {
    await tester.pumpWidget(wrap(SizedBox(height: 600, child: FinanceWorkspace(
      summary: summary(incomeByCurrency: const {'PHP': 0}),
      period: 'month',
      onPeriodChanged: (_) {},
      currencySymbol: currencySymbol,
      currencyScope: 'all',
      currencyOptions: const ['all', 'PHP', 'USD'],
    ))));
    await tester.pumpAndSettle();

    expect(find.textContaining('You kept', findRichText: true), findsNothing);
    expect(
      find.textContaining('\u2212\u20B19,140.25', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('hero renders the spending delta chip against the previous period',
      (tester) async {
    await tester.pumpWidget(wrap(SizedBox(height: 600, child: FinanceWorkspace(
      summary: summary(previousPeriodExpense: 1500000),
      period: 'month',
      onPeriodChanged: (_) {},
      currencySymbol: currencySymbol,
      currencyScope: 'all',
      currencyOptions: const ['all', 'PHP', 'USD'],
    ))));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Spending down 39% from last month'),
      findsOneWidget,
    );
  });

  testWidgets('no delta chip at the all-time scope', (tester) async {
    await tester.pumpWidget(wrap(SizedBox(height: 600, child: FinanceWorkspace(
      summary: summary(previousPeriodExpense: 565050),
      period: 'all',
      onPeriodChanged: (_) {},
      currencySymbol: currencySymbol,
      currencyScope: 'all',
      currencyOptions: const ['all', 'PHP', 'USD'],
    ))));
    await tester.pumpAndSettle();

    expect(find.textContaining('from last'), findsNothing);
  });

  testWidgets('hero amount carries an explicit + sign when net is positive',
      (tester) async {
    await tester.pumpWidget(wrap(SizedBox(height: 600, child: FinanceWorkspace(
      summary: summary(),
      budgets: const [],
      period: 'month',
      onPeriodChanged: (_) {},
      currencySymbol: currencySymbol,
      currencyScope: 'all',
      currencyOptions: const ['all', 'PHP', 'USD'],
      dailyTotals: const [],
    ))));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('\u002B\u20B131,359.75', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('ledger groups rows under day headers', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final threeDaysAgo = today.subtract(const Duration(days: 3));
    final recent = <(MoneyEntry, Note)>[
      (entry('e1', 18000, 'Food & Drink', 'PHP', date: today), financeNote('n1')),
      (entry('e2', 32000, 'Transport', 'PHP', date: yesterday), financeNote('n2')),
      (entry('e3', 48000, 'Groceries', 'PHP', date: threeDaysAgo), financeNote('n3')),
    ];
    await tester.pumpWidget(wrap(SizedBox(height: 900, child: FinanceWorkspace(
      summary: summary(recent: recent, entryCount: 3),
      period: 'month',
      onPeriodChanged: (_) {},
      currencySymbol: currencySymbol,
      currencyScope: 'all',
      currencyOptions: const ['all', 'PHP', 'USD'],
    ))));
    await tester.pump();

    expect(find.text('TODAY · ${dayLabel(today).toUpperCase()}'), findsOneWidget);
    expect(
      find.text('YESTERDAY · ${dayLabel(yesterday).toUpperCase()}'),
      findsOneWidget,
    );
    expect(
      find.text(
        '${kWeekdayNamesShort[threeDaysAgo.weekday - 1].toUpperCase()}'
        ' · ${dayLabel(threeDaysAgo).toUpperCase()}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('ledger collapses to five rows and expands via the links',
      (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9);
    final recent = <(MoneyEntry, Note)>[
      for (var i = 0; i < 7; i++)
        (
          entry('e$i', 1000 + i, 'Cat $i', 'PHP', date: today),
          financeNote('n$i'),
        ),
    ];
    await tester.binding.setSurfaceSize(const Size(1280, 1400));
    await tester.pumpWidget(
      wrap(
        SizedBox(
          height: 1300,
          child: FinanceWorkspace(
            summary: summary(recent: recent, entryCount: 7),
            budgets: const [],
            period: 'month',
            onPeriodChanged: (_) {},
            currencySymbol: currencySymbol,
            currencyScope: 'all',
            currencyOptions: const ['all', 'PHP', 'USD'],
            dailyTotals: const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Collapsed: first five rows only. Each visible row renders its category
    // TWICE (title when no note + subtitle), hence findsNWidgets(2).
    expect(find.text('Cat 4'), findsNWidgets(2));
    expect(find.text('Cat 5'), findsNothing);
    expect(find.text('View all 7'), findsOneWidget);
    expect(find.text('View all 7 transactions \u2193'), findsOneWidget);
    await tester.tap(find.text('View all 7 transactions \u2193'));
    await tester.pumpAndSettle();
    expect(find.text('Cat 6'), findsNWidgets(2));
    expect(find.text('Show fewer'), findsOneWidget);
    expect(find.text('Show fewer \u2191'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('the right rail leads with budgets, then categories',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    await tester.pumpWidget(
      wrap(
        SizedBox(
          height: 1100,
          child: FinanceWorkspace(
            summary: summary(),
            budgets: [budget('b1', 'Groceries', 500000)],
            period: 'month',
            onPeriodChanged: (_) {},
            currencySymbol: currencySymbol,
            currencyScope: 'all',
            currencyOptions: const ['all', 'PHP', 'USD'],
            dailyTotals: const [],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    final budgetsTop = tester.getTopLeft(find.text('Budgets')).dy;
    final catsTop = tester.getTopLeft(find.text('Top categories')).dy;
    expect(budgetsTop, lessThan(catsTop));
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('desktop rows show the note title and the edit affordance',
      (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9);
    final recent = <(MoneyEntry, Note)>[
      (
        entry('e1', 18000, 'Food & Drink', 'PHP',
            note: 'Morning coffee', date: today),
        financeNote('n1'),
      ),
    ];
    await tester.pumpWidget(wrap(SizedBox(height: 600, child: FinanceWorkspace(
      summary: summary(recent: recent, entryCount: 1),
      budgets: const [],
      period: 'month',
      onPeriodChanged: (_) {},
      currencySymbol: currencySymbol,
      currencyScope: 'all',
      currencyOptions: const ['all', 'PHP', 'USD'],
      dailyTotals: const [],
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Morning coffee'), findsOneWidget); // row title
    expect(find.text('Daily expenses'), findsOneWidget); // subtitle note title
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
  });

  testWidgets('transaction amounts are signed', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final recent = <(MoneyEntry, Note)>[
      (entry('e1', 18000, 'Food & Drink', 'PHP', date: today), financeNote('n1')),
      (entry('e2', 50000, 'Freelance', 'PHP', type: 'income', date: today),
          financeNote('n2')),
    ];
    await tester.pumpWidget(wrap(SizedBox(height: 900, child: FinanceWorkspace(
      summary: summary(recent: recent, entryCount: 2),
      period: 'month',
      onPeriodChanged: (_) {},
      currencySymbol: currencySymbol,
      currencyScope: 'all',
      currencyOptions: const ['all', 'PHP', 'USD'],
    ))));
    await tester.pump();

    expect(find.textContaining('\u2212', findRichText: true), findsOneWidget);
    expect(find.textContaining('+', findRichText: true), findsOneWidget);
  });

  testWidgets('a budget at 80-99 percent paints warning amber', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final colors = kPalettes.first.light;
    await tester.pumpWidget(wrap(SizedBox(height: 1100, child: FinanceWorkspace(
      summary: summary(),
      period: 'month',
      onPeriodChanged: (_) {},
      currencySymbol: currencySymbol,
      currencyScope: 'all',
      currencyOptions: const ['all', 'PHP', 'USD'],
      budgets: [budget('b1', 'Food & Drink', 100000)],
      budgetActuals: const {'b1': 81000},
      onAddBudget: (_) {},
    ))));
    await tester.pump(const Duration(milliseconds: 400));

    final pct = tester.widget<Text>(find.text('81%'));
    expect(pct.style?.color, colors.warning);
  });

  testWidgets('the ledger-note link renders and opens the note', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var opened = 0;
    await tester.pumpWidget(wrap(SizedBox(height: 1100, child: FinanceWorkspace(
      summary: summary(),
      period: 'month',
      onPeriodChanged: (_) {},
      currencySymbol: currencySymbol,
      currencyScope: 'all',
      currencyOptions: const ['all', 'PHP', 'USD'],
      ledgerNoteLabel: 'Finance — September 2026',
      onOpenLedgerNote: () => opened++,
    ))));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('ledger lives in'), findsOneWidget);
    expect(find.textContaining('Finance — September 2026'), findsOneWidget);
    await tester.tap(find.text('Open ›'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(opened, 1);
  });

  testWidgets('no ledger-note link without a finance note', (tester) async {
    await tester.pumpWidget(wrap(SizedBox(height: 1100, child: FinanceWorkspace(
      summary: summary(),
      period: 'month',
      onPeriodChanged: (_) {},
      currencySymbol: currencySymbol,
      currencyScope: 'all',
      currencyOptions: const ['all', 'PHP', 'USD'],
    ))));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('ledger lives in'), findsNothing);
  });

  testWidgets('trend card shows day labels and the per-day average when asked',
      (tester) async {
    await tester.pumpWidget(wrap(SizedBox(height: 300, child: SpendSparkline(
      dailyTotals: const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 18550],
      currency: 'PHP',
      showDayLabels: true,
      averagePerDay: 1325,
    ))));
    await tester.pumpAndSettle();

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('${DateTime.now().day}'), findsOneWidget);
    expect(find.textContaining(' / day'), findsOneWidget);
  });

  testWidgets('sparkline defaults keep the compact height and no labels',
      (tester) async {
    await tester.pumpWidget(wrap(SizedBox(height: 300, child: SpendSparkline(
      dailyTotals: const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 18550],
      currency: 'PHP',
    ))));
    await tester.pumpAndSettle();

    final bars = tester.getSize(
      find
          .descendant(
            of: find.byType(SpendSparkline),
            matching: find.byType(CustomPaint),
          )
          .first,
    );
    expect(bars.height, 56);
    expect(find.text('${DateTime.now().day}'), findsNothing);
  });

  testWidgets('desktop hero cards share one height and one inset', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(SizedBox(
      height: 1100,
      child: FinanceWorkspace(
        summary: summary(),
        period: 'all',
        onPeriodChanged: (_) {},
        currencySymbol: currencySymbol,
        currencyScope: 'all',
        currencyOptions: const ['all', 'PHP', 'USD'],
        onAddExpense: () {},
        onAddIncome: () {},
      ),
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final heroCard = find
        .ancestor(of: find.text('Net · All time'), matching: find.byType(Container))
        .first;
    final heroLabel = find.text('Net · All time');
    final inCard = find
        .ancestor(of: find.text('In'), matching: find.byType(Container))
        .first;
    final inLabel = find.text('In');
    final outCard = find
        .ancestor(of: find.text('Out'), matching: find.byType(Container))
        .first;

    final heroHeight = tester.getRect(heroCard).height;
    expect(tester.getRect(inCard).height, closeTo(heroHeight, 0.5));
    expect(tester.getRect(outCard).height, closeTo(heroHeight, 0.5));
    expect(tester.getRect(heroCard).top, closeTo(tester.getRect(inCard).top, 0.5));

    final heroInset =
        tester.getTopLeft(heroLabel).dx - tester.getTopLeft(heroCard).dx;
    final inInset = tester.getTopLeft(inLabel).dx - tester.getTopLeft(inCard).dx;
    expect(inInset, closeTo(heroInset, 0.5));
    expect(inInset, closeTo(17, 1.0));
  });

  testWidgets('the desktop scope row is one 44dp control height', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(SizedBox(
      height: 1100,
      child: FinanceWorkspace(
        summary: summary(),
        period: 'all',
        onPeriodChanged: (_) {},
        currencySymbol: currencySymbol,
        currencyScope: 'all',
        currencyOptions: const ['PHP'],
        onAddExpense: () {},
        onAddIncome: () {},
      ),
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Capture buttons build the private .icon subclasses, so exact-type
    // find.byType cannot match them (see the tooltips test above).
    final expenseButton = find.bySubtype<ElevatedButton>();
    final incomeButton = find.bySubtype<OutlinedButton>();
    // find.widgetWithText is ancestor-ordered closest-first, so .first is the
    // selected segment thumb (inside the chrome); the chrome is the next
    // Container up (.at(1)).
    final selectorChrome = find.widgetWithText(Container, 'All').at(1);

    expect(tester.getSize(expenseButton).height, closeTo(44, 0.5));
    expect(tester.getSize(incomeButton).height, closeTo(44, 0.5));
    expect(tester.getSize(selectorChrome).height, closeTo(44, 0.5));

    expect(
      tester.getRect(expenseButton).top,
      closeTo(tester.getRect(incomeButton).top, 0.5),
    );
    expect(
      tester.getRect(expenseButton).top,
      closeTo(tester.getRect(selectorChrome).top, 0.5),
    );
  });

  testWidgets('section gutters on the desktop canvas are 16px', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(SizedBox(
      height: 1100,
      child: FinanceWorkspace(
        summary: summary(),
        period: 'all',
        onPeriodChanged: (_) {},
        currencySymbol: currencySymbol,
        currencyScope: 'all',
        currencyOptions: const ['all', 'PHP', 'USD'],
        dailyTotals: const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 18550],
      ),
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final heroCard = find
        .ancestor(of: find.text('Net · All time'), matching: find.byType(Container))
        .first;
    final trendCard = find
        .descendant(of: find.byType(SpendSparkline), matching: find.byType(Container))
        .first;

    expect(
      tester.getRect(trendCard).top - tester.getRect(heroCard).bottom,
      closeTo(16, 0.5),
    );
  });

  testWidgets('dense rows share one inset', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9);
    final recent = <(MoneyEntry, Note)>[
      (entry('e1', 18000, 'Transport', 'PHP', date: today), financeNote('n1')),
    ];
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(SizedBox(
      height: 1100,
      child: FinanceWorkspace(
        summary: summary(recent: recent, entryCount: 1),
        period: 'all',
        onPeriodChanged: (_) {},
        currencySymbol: currencySymbol,
        currencyScope: 'all',
        currencyOptions: const ['all', 'PHP', 'USD'],
      ),
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Both dense rows are measured card edge -> first child, because each row
    // indents its own label past a leading mark (a 28px avatar in the ledger, a
    // 14px category icon in the rail). Neither row has a border, so the shared
    // inset is exactly the h12 dense-row padding.
    final rowCard = find
        .ancestor(of: find.text('Transport'), matching: find.byType(Container))
        .first;
    final rowLeading =
        find.descendant(of: rowCard, matching: find.byType(Container)).first;
    final railCard = find
        .ancestor(of: find.text('Groceries'), matching: find.byType(Container))
        .first;
    final railLeading =
        find.descendant(of: railCard, matching: find.byType(Icon)).first;

    final rowInset =
        tester.getTopLeft(rowLeading).dx - tester.getTopLeft(rowCard).dx;
    final railInset =
        tester.getTopLeft(railLeading).dx - tester.getTopLeft(railCard).dx;
    expect(rowInset, closeTo(railInset, 0.5));
    expect(rowInset, closeTo(12, 0.5));
  });
}