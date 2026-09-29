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

  FinanceSummary summary({Map<String, List<MoneyEntry>> entriesByNote = const {}}) =>
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
        entriesByNote: entriesByNote,
      );

  Future<void> pumpList(
    WidgetTester tester,
    List<Note> notes, {
    String activeFilter = 'notes',
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
            activeFilter: activeFilter,
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

  testWidgets('finance note preview shows Net and the entry count',
      (tester) async {
    final note = Note(
      id: 'f1',
      title: 'Payday',
      content: '',
      tags: const [],
      type: 'expense',
      currency: 'PHP',
      amounts: [
        entry('i1', 120000, type: 'income'),
        entry('e1', 45000),
      ],
      updatedAt: now,
    );
    await pumpList(tester, [note]);

    expect(find.textContaining('Net'), findsOneWidget);
    expect(find.textContaining('· 2 entries'), findsOneWidget);
  });

  testWidgets('single-entry finance preview uses the singular label',
      (tester) async {
    final note = Note(
      id: 'f2',
      title: 'Coffee',
      content: '',
      tags: const [],
      type: 'expense',
      currency: 'PHP',
      amounts: [entry('e1', 45000)],
      updatedAt: now,
    );
    await pumpList(tester, [note]);

    expect(find.textContaining('· 1 entry'), findsOneWidget);
    expect(find.textContaining('1 entries'), findsNothing);
  });

  testWidgets('finance note with no filtered entries shows No entries yet',
      (tester) async {
    final note = Note(
      id: 'f3',
      title: 'Out of period',
      content: '',
      tags: const [],
      type: 'expense',
      currency: 'PHP',
      amounts: [entry('e1', 10000)],
      updatedAt: now,
    );
    await pumpList(
      tester,
      [note],
      financeSummary: summary(entriesByNote: const {'f3': []}),
    );

    expect(find.textContaining('No entries yet'), findsOneWidget);
  });

  testWidgets('finance note across currencies shows one net per currency',
      (tester) async {
    final note = Note(
      id: 'f4',
      title: 'Travel',
      content: '',
      tags: const [],
      type: 'expense',
      currency: 'PHP',
      amounts: [
        entry('e1', 10000, currency: 'PHP'),
        entry('e2', 5000, currency: 'USD'),
      ],
      updatedAt: now,
    );
    await pumpList(tester, [note]);

    expect(
      find.textContaining('Net \u2212₱100.00 · \u2212\$50.00 · 2 entries'),
      findsOneWidget,
    );
  });

  testWidgets('empty regular note previews as Empty note', (tester) async {
    final note = Note(
      id: 't5',
      title: 'Blank',
      content: '',
      tags: const [],
      updatedAt: now,
    );
    await pumpList(tester, [note]);

    expect(find.textContaining('Empty note'), findsOneWidget);
  });

  testWidgets('regular note with content does not preview as Empty note',
      (tester) async {
    final note = Note(
      id: 't6',
      title: 'Welcome',
      content: 'hello world',
      tags: const [],
      updatedAt: now,
    );
    await pumpList(tester, [note]);

    expect(find.textContaining('Empty note'), findsNothing);
    expect(find.textContaining('hello world'), findsOneWidget);
  });

  testWidgets('todo note carrying amounts does not render finance chrome',
      (tester) async {
    final note = Note(
      id: 'td7',
      title: 'Errands',
      content: 'shopping',
      tags: const [],
      type: 'todo',
      amounts: [
        entry('i1', 100, type: 'income'),
        entry('e1', 50),
      ],
      updatedAt: now,
    );
    await pumpList(tester, [note]);

    expect(find.textContaining('Net'), findsNothing);
  });
}