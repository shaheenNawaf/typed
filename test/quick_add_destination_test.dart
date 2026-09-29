import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typed/models/note.dart';
import 'package:typed/models/money_entry.dart';
import 'package:typed/screens/home_screen.dart';
import 'package:typed/theme/palettes.dart';
import 'package:typed/utils/date_format.dart';
import 'package:typed/utils/note_storage.dart';
import 'package:typed/widgets/finance_dashboard.dart';
import 'package:typed/widgets/note_list.dart';
import 'package:typed/widgets/editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('com.z4yed.typed/widget'),
    (call) async => null,
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('flutter_timezone'),
    (call) async => null,
  );

  ThemeData testTheme() => ThemeData(
        useMaterial3: true,
        extensions: <ThemeExtension<dynamic>>[kPalettes.first.light],
      );

  Future<void> seed(List<Note> notes, {required String tab}) async {
    SharedPreferences.setMockInitialValues({
      'onboarded_v1': true,
      'onboarding_flow_complete_v1': true,
      'shell_state_v1': '{"filter":"$tab","tab":"$tab"}',
    });
    await NoteStorage().save(notes);
  }

  /// One real transaction so `hasAnyEntries` is true and FinanceWorkspace renders
  /// its normal layout. With zero notes the dashboard shows the single
  /// zero-transactions empty state, which has its own 'Add expense' button and no
  /// 'Expense' button for `openQuickAdd` to tap. The title deliberately does not
  /// match the monthly-note pattern, so quick add still creates a fresh one.
  Note seededFinanceNote() => Note(
        id: 'n_seed',
        title: 'Sample spending',
        content: '',
        tags: const ['finance'],
        type: 'expense',
        currency: 'PHP',
        amounts: [
          MoneyEntry(
            id: 'e_seed',
            amount: 15000,
            category: 'Food',
            date: DateTime.now(),
            type: 'expense',
            currency: 'PHP',
          ),
        ],
      );

  Future<void> pumpHome(WidgetTester tester, {required Size surface}) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surface;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: testTheme(), home: const HomeScreen()),
    );
    // NEVER pumpAndSettle: the loading-skeleton shimmer repeats forever.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> openQuickAdd(WidgetTester tester) async {
    final expenseBtn = find.text('Expense');
    await tester.ensureVisible(expenseBtn);
    await tester.pump();
    await tester.tap(expenseBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// A second finance note in USD so `_financeCurrencyOptions` offers more than
  /// `all` and the currency scope dropdown renders. Added for the currency-scope
  /// tests; the shared `seededFinanceNote` fixture is left untouched.
  Note seededUsdNote() => Note(
        id: 'n_seed_usd',
        title: 'US card spending',
        content: '',
        tags: const ['finance'],
        type: 'expense',
        currency: 'USD',
        amounts: [
          MoneyEntry(
            id: 'e_seed_usd',
            amount: 4200,
            category: 'Travel',
            date: DateTime.now(),
            type: 'expense',
            currency: 'USD',
          ),
        ],
      );

  /// Seeds the two-currency fixture with the workspace in Advanced mode, where
  /// the currency scope actually applies (`_effectiveFinanceCurrency` is 'all'
  /// in Simple mode). The shared `seed` helper is left untouched.
  Future<void> seedAdvanced(List<Note> notes) async {
    SharedPreferences.setMockInitialValues({
      'onboarded_v1': true,
      'onboarding_flow_complete_v1': true,
      'shell_state_v1':
          '{"filter":"finance","tab":"finance","financeMode":"advanced"}',
    });
    await NoteStorage().save(notes);
  }

  Future<void> selectCurrencyScope(WidgetTester tester, String code) async {
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text(code).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('quick add from the dashboard targets the monthly finance note',
      (tester) async {
    await seed([seededFinanceNote()], tab: 'finance');
    await pumpHome(tester, surface: const Size(1400, 900));

    await openQuickAdd(tester);

    expect(find.text('Add Entry'), findsOneWidget);

    final now = DateTime.now();
    final expected =
        'Saving to: Finance — ${monthName(now.month)} ${now.year}';
    expect(find.text(expected, findRichText: true), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
  });

  testWidgets('quick add does not open the note editor', (tester) async {
    await seed([seededFinanceNote()], tab: 'finance');
    await pumpHome(tester, surface: const Size(1400, 900));

    await openQuickAdd(tester);

    expect(find.text('+ Add description'), findsNothing);
    expect(find.text('View source'), findsNothing);

    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('+ Add description'), findsNothing);
  });

  testWidgets('finance tab on desktop hides the note-list pane', (tester) async {
    await seed([seededFinanceNote()], tab: 'finance');
    await pumpHome(tester, surface: const Size(1400, 900));

    expect(find.byType(FinanceWorkspace), findsOneWidget);
    expect(find.byType(NoteList), findsNothing);
  });

  testWidgets('the workspace ledger link opens the note and restores the pane',
      (tester) async {
    await seed([seededFinanceNote()], tab: 'finance');
    await pumpHome(tester, surface: const Size(1400, 1400));

    await tester.ensureVisible(find.text('Open ›'));
    await tester.tap(find.text('Open ›'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(Editor), findsOneWidget);
    expect(find.byType(NoteList), findsOneWidget);
    expect(find.byType(FinanceWorkspace), findsNothing);
  });

  testWidgets('quick add inherits the dashboard currency scope', (tester) async {
    await seedAdvanced([seededFinanceNote(), seededUsdNote()]);
    await pumpHome(tester, surface: const Size(1400, 900));

    // Two currencies in play: the scope dropdown renders, closed on 'all'.
    expect(find.text('All currencies'), findsOneWidget);

    await selectCurrencyScope(tester, 'USD');

    await openQuickAdd(tester);

    expect(find.textContaining('Amount · USD'), findsOneWidget);
    expect(find.textContaining('Amount · PHP'), findsNothing);

    await closeSheet(tester);
  });

  testWidgets('quick add falls back to the note currency when the scope is all',
      (tester) async {
    await seedAdvanced([seededFinanceNote(), seededUsdNote()]);
    await pumpHome(tester, surface: const Size(1400, 900));

    // Leave the scope on All currencies; the dropdown is never touched.
    expect(find.text('All currencies'), findsOneWidget);

    await openQuickAdd(tester);

    expect(find.textContaining('Amount · PHP'), findsOneWidget);
    expect(find.textContaining('Amount · USD'), findsNothing);

    await closeSheet(tester);
  });
}