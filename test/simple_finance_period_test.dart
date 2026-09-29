import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typed/models/money_entry.dart';
import 'package:typed/models/note.dart';
import 'package:typed/screens/home_screen.dart';
import 'package:typed/theme/palettes.dart';
import 'package:typed/utils/date_format.dart';
import 'package:typed/utils/note_storage.dart';
import 'package:typed/widgets/finance_dashboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.z4yed.typed/widget'),
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter_local_notifications'),
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      (call) async => 'UTC',
    );
  });

  ThemeData testTheme() => ThemeData(
        useMaterial3: true,
        extensions: <ThemeExtension<dynamic>>[kPalettes.first.light],
      );

  Widget wrap(Widget child) => MaterialApp(
        theme: testTheme(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
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

  group('periodName', () {
    test('day reads Today', () {
      expect(periodName('day'), 'Today');
    });

    test('week reads This week', () {
      expect(periodName('week'), 'This week');
    });

    test('all reads All time', () {
      expect(periodName('all'), 'All time');
    });

    test('month reads the anchored month name and year', () {
      expect(periodName('month', now: DateTime(2026, 9, 15)), 'September 2026');
    });
  });

  group('SimpleFinanceView period filter', () {
    testWidgets('simple view offers day week month and all', (tester) async {
      await tester.pumpWidget(wrap(SimpleFinanceView(
        summary: summary(dominant: 'PHP'),
        budgets: const [],
        budgetActuals: const {},
        period: 'month',
        onPeriodChanged: (_) {},
      )));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Day'), findsOneWidget);
      expect(find.text('Week'), findsOneWidget);
      expect(find.text('Month'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text(periodName('month').toUpperCase()), findsOneWidget);
    });

    testWidgets('the label follows the selected period', (tester) async {
      await tester.pumpWidget(wrap(SimpleFinanceView(
        summary: summary(dominant: 'PHP'),
        budgets: const [],
        budgetActuals: const {},
        period: 'all',
      )));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text(periodName('all').toUpperCase()), findsOneWidget);
      expect(find.text('THIS MONTH'), findsNothing);
    });

    testWidgets('tapping a scope reports it', (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(wrap(SimpleFinanceView(
        summary: summary(dominant: 'PHP'),
        budgets: const [],
        budgetActuals: const {},
        period: 'month',
        onPeriodChanged: (p) => picked.add(p),
      )));
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('Day'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(picked, ['day']);

      await tester.tap(find.text('All'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(picked, ['day', 'all']);
    });

    testWidgets('without a callback there is no filter', (tester) async {
      await tester.pumpWidget(wrap(SimpleFinanceView(
        summary: summary(dominant: 'PHP'),
        budgets: const [],
        budgetActuals: const {},
      )));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Day'), findsNothing);
      expect(find.text('Week'), findsNothing);
      expect(find.text(periodName('month').toUpperCase()), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('SimpleFinanceView in the mobile shell', () {
    Note bugNote() {
      final now = DateTime.now();
      return Note(
        id: 'n_bug',
        title: 'Reported spending',
        content: '',
        tags: const ['finance'],
        type: 'expense',
        currency: 'PHP',
        amounts: [
          MoneyEntry(
            id: 'e_today',
            amount: 10000,
            category: 'Food',
            date: now,
            type: 'expense',
            currency: 'PHP',
          ),
          MoneyEntry(
            id: 'e_prev',
            amount: 50000,
            category: 'Food',
            date: DateTime(now.year, now.month - 1, 15),
            type: 'expense',
            currency: 'PHP',
          ),
        ],
      );
    }

    Future<void> seedBug(List<Note> notes) async {
      SharedPreferences.setMockInitialValues({
        'onboarded_v1': true,
        'onboarding_flow_complete_v1': true,
        'shell_state_v1':
            '{"filter":"finance","tab":"finance","financeMode":"simple"}',
      });
      await NoteStorage().save(notes);
    }

    Future<void> pumpShell(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: testTheme(), home: const HomeScreen()),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        if (find.text('Month').evaluate().isNotEmpty) break;
      }
    }

    testWidgets('simple view can widen past this month', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await seedBug([bugNote()]);
      await pumpShell(tester);

      // Default Month scope: only today's entry counts.
      expect(find.textContaining('₱100.00', findRichText: true), findsWidgets);
      expect(find.textContaining('₱600.00', findRichText: true), findsNothing);
      expect(find.textContaining('₱500.00', findRichText: true), findsNothing);

      // Widen to All: the older month's entry joins the total.
      await tester.tap(find.text('All'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('₱600.00', findRichText: true), findsWidgets);

      // Narrow to Day: back to today only.
      await tester.tap(find.text('Day'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('₱100.00', findRichText: true), findsWidgets);
      expect(find.textContaining('₱600.00', findRichText: true), findsNothing);

      expect(tester.takeException(), isNull);
    });
  });
}