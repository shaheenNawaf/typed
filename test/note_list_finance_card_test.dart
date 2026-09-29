import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typed/models/money_entry.dart';
import 'package:typed/models/note.dart';
import 'package:typed/theme/palettes.dart';
import 'package:typed/widgets/finance_dashboard.dart';
import 'package:typed/widgets/note_list.dart';

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

  final now = DateTime(2026, 9, 15, 12);

  MoneyEntry entry(
    String id,
    int amount, {
    String type = 'expense',
    String currency = 'PHP',
    DateTime? date,
  }) =>
      MoneyEntry(
        id: id,
        amount: amount,
        category: 'general',
        date: date ?? now,
        currency: currency,
        type: type,
      );

  FinanceSummary summary({
    Set<String> noteIds = const {},
    Map<String, List<MoneyEntry>> entriesByNote = const {},
  }) =>
      FinanceSummary(
        totalIncome: 0,
        totalExpense: 0,
        categories: const [],
        recentEntries: const [],
        entryCount: 0,
        dominantCurrency: 'PHP',
        incomeByCurrency: const {},
        expenseByCurrency: const {},
        hasMixedCurrencies: false,
        noteIds: noteIds,
        entriesByNote: entriesByNote,
      );

  Future<void> pumpList(
    WidgetTester tester,
    List<Note> notes, {
    FinanceSummary? financeSummary,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme(),
        home: Scaffold(
          body: NoteList(
            notes: notes,
            currentNoteId: null,
            onSelectNote: (_) {},
            sortDesc: true,
            onSortToggle: () {},
            onNewNote: () {},
            searchQuery: '',
            onSearchChanged: (_) {},
            activeFilter: 'finance',
            onArchive: (_) {},
            onDelete: (_) {},
            onRestore: (_) {},
            onDeletePermanent: (_) async {},
            onTogglePin: (_) {},
            financeSummary: financeSummary,
            showFinanceDashboard: false,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 1));
  }

  Note financeNote(
    String id,
    List<MoneyEntry> amounts, {
    String title = 'Note',
    String type = 'expense',
  }) =>
      Note(
        id: id,
        title: title,
        content: '',
        tags: const [],
        type: type,
        currency: 'PHP',
        amounts: amounts,
        updatedAt: now,
      );

  testWidgets('expense-only finance note shows a down arrow', (tester) async {
    final note = financeNote('c1', [entry('e1', 8000)]);
    await pumpList(tester, [note]);

    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsNothing);
    expect(find.byIcon(Icons.swap_vert), findsNothing);
    expect(find.byIcon(Icons.remove), findsNothing);
  });

  testWidgets('income-only finance note shows an up arrow', (tester) async {
    final note = financeNote(
      'c2',
      [entry('i1', 8000, type: 'income')],
      type: 'income',
    );
    await pumpList(tester, [note]);

    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
  });

  testWidgets('net-negative mixed entry note shows a down arrow',
      (tester) async {
    final note = financeNote('c3', [
      entry('i1', 5000, type: 'income'),
      entry('e1', 8000),
    ]);
    await pumpList(tester, [note]);

    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    expect(find.byIcon(Icons.swap_vert), findsNothing);
  });

  testWidgets('net-positive mixed entry note shows an up arrow',
      (tester) async {
    final note = financeNote('c4', [
      entry('i1', 8000, type: 'income'),
      entry('e1', 5000),
    ]);
    await pumpList(tester, [note]);

    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    expect(find.byIcon(Icons.swap_vert), findsNothing);
  });

  testWidgets('note whose entries net to zero shows a remove icon',
      (tester) async {
    final note = financeNote('c5', [
      entry('i1', 3000, type: 'income'),
      entry('e1', 3000),
    ]);
    await pumpList(tester, [note]);

    expect(find.byIcon(Icons.remove), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsNothing);
    expect(find.byIcon(Icons.arrow_downward), findsNothing);
  });

  testWidgets('two-currency finance note shows remove and per-currency nets',
      (tester) async {
    final note = financeNote('c6', [
      entry('e1', 10000, currency: 'PHP'),
      entry('i1', 5000, type: 'income', currency: 'USD'),
    ]);
    await pumpList(tester, [note]);

    expect(find.byIcon(Icons.remove), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsNothing);
    expect(find.byIcon(Icons.arrow_downward), findsNothing);
    expect(
      find.textContaining('Net \u2212₱100.00 · \$50.00 · 2 entries'),
      findsOneWidget,
    );
  });

  testWidgets('finance note spanning two days shows a date range',
      (tester) async {
    final note = financeNote('c7', [
      entry('e1', 10000, date: DateTime(2026, 9, 1)),
      entry('e2', 2000, date: DateTime(2026, 9, 26)),
    ]);
    await pumpList(tester, [note]);

    expect(find.textContaining('Sep 1'), findsOneWidget);
    expect(find.textContaining('Sep 26'), findsOneWidget);
  });

  testWidgets('finance note with no filtered entries has no date range',
      (tester) async {
    final note = financeNote('c8', [entry('e1', 10000)]);
    await pumpList(
      tester,
      [note],
      financeSummary: summary(
        noteIds: const {'c8'},
        entriesByNote: const {'c8': []},
      ),
    );

    expect(find.textContaining('No entries yet'), findsOneWidget);
    expect(find.text('Sep 15, 2026'), findsNothing);
  });
}