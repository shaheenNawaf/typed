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

  FinanceSummary summary(
          {Map<String, List<MoneyEntry>> entriesByNote = const {}}) =>
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
    bool showFinanceDashboard = false,
    VoidCallback? onOpenSettings,
    double width = 800,
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

  testWidgets('the finance column header has a title', (tester) async {
    await pumpList(
      tester,
      const [],
      activeFilter: 'finance',
      financeSummary: summary(),
      showFinanceDashboard: true,
    );

    expect(find.text('Finance notes'), findsOneWidget);
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
}