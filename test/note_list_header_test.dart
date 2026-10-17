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

  FinanceSummary summary({
    Map<String, List<MoneyEntry>> entriesByNote = const {},
    Set<String> noteIds = const {},
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
        entriesByNote: entriesByNote,
        noteIds: noteIds,
      );

  Future<void> pumpList(
    WidgetTester tester,
    List<Note> notes, {
    String activeFilter = 'notes',
    FinanceSummary? financeSummary,
    bool showFinanceDashboard = false,
    VoidCallback? onOpenSettings,
    double width = 800,
    bool sortDesc = true,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme(),
        home: Scaffold(
          body: NoteList(
            notes: notes,
            currentNoteId: null,
            onSelectNote: (_) {},
            sortDesc: sortDesc,
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
            showFinanceDashboard: showFinanceDashboard,
            onOpenSettings: onOpenSettings,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 1));
  }

  List<String> tooltipMessages(WidgetTester tester) => tester
      .widgetList<Tooltip>(find.byType(Tooltip))
      .map((t) => t.message)
      .whereType<String>()
      .toList();

  testWidgets('the finance pane skips the redundant column title',
      (tester) async {
    await pumpList(
      tester,
      const [],
      activeFilter: 'finance',
      financeSummary: summary(),
      showFinanceDashboard: true,
    );

    // The workspace header already says "Finance"; the dashboard's own
    // section labels carry the structure below it.
    expect(find.text('Finance notes'), findsNothing);
  });

  testWidgets('finance ledgers sit in one labelled section, not date buckets',
      (tester) async {
    final note = Note(
      id: 'f1',
      title: 'Finance — October',
      content: '',
      tags: const ['finance'],
      updatedAt: now,
    );
    await pumpList(
      tester,
      [note],
      activeFilter: 'finance',
      financeSummary: summary(noteIds: const {'f1'}),
      showFinanceDashboard: true,
    );

    expect(find.text('LEDGER'), findsOneWidget);
    expect(find.text('Today'), findsNothing);
  });

  testWidgets('the notes column header has no finance title', (tester) async {
    final note = Note(
      id: 'n1',
      title: 'Hello',
      content: 'body',
      tags: const [],
      updatedAt: now,
    );
    await pumpList(tester, [note], activeFilter: 'notes');

    expect(find.text('Finance notes'), findsNothing);
  });

  testWidgets('the sort and settings icons have tooltips on a narrow pane',
      (tester) async {
    await pumpList(
      tester,
      const [],
      activeFilter: 'finance',
      financeSummary: summary(),
      showFinanceDashboard: true,
      onOpenSettings: () {},
      width: 360,
    );

    final messages = tooltipMessages(tester);
    expect(messages.any((m) => m.startsWith('Sort')), isTrue);
    expect(messages.contains('Finance settings'), isTrue);
  });

  testWidgets('the sort control shows text instead of a tooltip on a wide pane',
      (tester) async {
    await pumpList(
      tester,
      const [],
      activeFilter: 'finance',
      financeSummary: summary(),
      showFinanceDashboard: true,
      onOpenSettings: () {},
      width: 500,
    );

    expect(find.text('Recent \u2193'), findsOneWidget);
    expect(tooltipMessages(tester).any((m) => m.startsWith('Sort')), isFalse);
  });

  group('section headers', () {
    final today = DateTime.now();
    final older = today.subtract(const Duration(days: 40));
    Note note(String id, DateTime at, {bool pinned = false}) => Note(
          id: id,
          title: id,
          content: 'body',
          tags: const [],
          updatedAt: at,
          isPinned: pinned,
        );

    testWidgets('A–Z order is not split into repeating date buckets',
        (tester) async {
      await pumpList(
        tester,
        [note('Apple', today), note('Banana', older), note('Cherry', today)],
        sortDesc: false,
      );
      expect(find.text('A–Z'), findsOneWidget);
      expect(find.text('Today'), findsNothing);
      expect(find.text('Older'), findsNothing);
      // The sort toggle rides on the first header and must survive A–Z.
      expect(find.textContaining('A–Z'), findsWidgets);
    });

    testWidgets('pinned notes get their own section', (tester) async {
      await pumpList(tester, [
        note('Old pin', older, pinned: true),
        note('Fresh', today),
      ]);
      expect(find.text('Pinned'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Older'), findsNothing);
    });
  });
}