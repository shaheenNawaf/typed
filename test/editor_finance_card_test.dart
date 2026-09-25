import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typed/models/money_entry.dart';
import 'package:typed/models/note.dart';
import 'package:typed/screens/home_screen.dart';
import 'package:typed/theme/palettes.dart';
import 'package:typed/utils/note_storage.dart';
import 'package:typed/widgets/editor_toolbar.dart';
import 'package:typed/widgets/markdown_controller.dart';

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

  Future<void> openNote(WidgetTester tester, String title) async {
    final row = find.text(title).last;
    await tester.ensureVisible(row);
    await tester.pump();
    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  List<Object> drainExceptions(WidgetTester tester) {
    final exceptions = <Object>[];
    Object? e;
    while ((e = tester.takeException()) != null) {
      exceptions.add(e!);
    }
    return exceptions;
  }

  void expectNoFlexOverflow(List<Object> exceptions) {
    expect(
      exceptions.where((e) => e.toString().contains('RenderFlex overflowed')),
      isEmpty,
    );
  }

  MoneyEntry mkEntry(int i, {int amount = 10000, String type = 'expense', String? note}) =>
      MoneyEntry(
        id: 'e$i',
        amount: amount,
        category: 'Item $i',
        note: note,
        date: DateTime(2026, 1, 1, 10, 30),
        type: type,
        currency: 'PHP',
      );

  Note finNote(List<MoneyEntry> amounts) => Note(
        id: 'fin2',
        title: 'Card',
        content: '',
        tags: ['finance'],
        type: 'expense',
        currency: 'PHP',
        amounts: amounts,
        updatedAt: DateTime(2026, 1, 1),
      );

  testWidgets('finance summary card never overflows', (tester) async {
    final now = DateTime.now();
    await seed(
      [
        Note(
          id: 'fin1',
          title: 'Travel budget',
          content: '',
          tags: ['finance'],
          type: 'expense',
          currency: 'PHP',
          amounts: [
            MoneyEntry(
              id: 'e1',
              amount: 12345678,
              category: 'Bills',
              date: now,
              type: 'expense',
              currency: 'PHP',
            ),
          ],
          updatedAt: now,
        ),
      ],
      tab: 'notes',
    );
    await pumpHome(tester, surface: const Size(390, 844));

    await openNote(tester, 'Travel budget');

    expect(find.text('EXPENSES'), findsOneWidget);
    expectNoFlexOverflow(drainExceptions(tester));
  });

  testWidgets('body renders WYSIWYG: no overlay, syntax hidden off the cursor line',
      (tester) async {
    final now = DateTime.now();
    await seed(
      [
        Note(
          id: 'txt1',
          title: 'Draft',
          content: '',
          tags: [],
          updatedAt: now,
        ),
      ],
      tab: 'notes',
    );
    await pumpHome(tester, surface: const Size(390, 844));
    await openNote(tester, 'Draft');

    expect(find.byKey(const Key('md-highlight-layer')), findsNothing);

    final contentField = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          (w.decoration?.hintText ?? '').startsWith('Start writing'),
    );
    await tester.enterText(contentField, '# Title\n\nSome **bold** text');
    await tester.pump();

    final ctrl =
        tester.widget<TextField>(contentField).controller!
            as MarkdownEditingController;
    // Storage stays pure markdown.
    expect(ctrl.text, '# Title\n\nSome **bold** text');

    final root = ctrl.buildTextSpan(style: null, withComposing: false);
    final leaves = <TextSpan>[];
    root.visitChildren((s) {
      if (s is TextSpan && (s.text ?? '').isNotEmpty) leaves.add(s);
      return true;
    });
    expect(leaves.map((s) => s.text).join(), '# Title\n\nSome **bold** text');

    // Cursor sits on line 2: line 0's '# ' marker is hidden (fontSize 0.1),
    // the cursor line's '**' markers stay visible (dimmed, full size).
    final hash = leaves.firstWhere((s) => s.text == '# ');
    expect(hash.style?.fontSize, 0.1);
    final stars = leaves.where((s) => s.text == '**').toList();
    expect(stars, isNotEmpty);
    for (final s in stars) {
      expect(s.style?.fontSize, isNot(0.1));
    }
    final bold = leaves.firstWhere((s) => s.text == 'bold');
    expect(bold.style?.fontWeight, FontWeight.w700);

    expectNoFlexOverflow(drainExceptions(tester));
  });

  testWidgets('negative net renders minus before the symbol', (tester) async {
    await seed(
      [finNote([mkEntry(1, amount: 100000), mkEntry(2, amount: 50000, type: 'income')])],
      tab: 'notes',
    );
    await pumpHome(tester, surface: const Size(390, 844));
    await openNote(tester, 'Card');

    expect(find.textContaining('\u2212₱500.00', findRichText: true), findsOneWidget);
    expect(find.textContaining('₱-500.00', findRichText: true), findsNothing);
    expectNoFlexOverflow(drainExceptions(tester));
  });

  testWidgets('short viewport: totals, entries and footer all reachable', (tester) async {
    await seed(
      [finNote(List.generate(20, (i) => mkEntry(i)))],
      tab: 'notes',
    );
    await pumpHome(tester, surface: const Size(390, 420));
    await openNote(tester, 'Card');

    expect(find.text('EXPENSES'), findsOneWidget);
    // 20 x 10000 minor = 200000 -> ₱2,000.00 total equals sum of entries
    // EXPENSES card + the NET card's '−₱2,000.00' both contain this substring.
    expect(find.textContaining('₱2,000.00', findRichText: true), findsNWidgets(2));
    expect(
      find.textContaining('\u2212₱2,000.00', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Entry'), findsOneWidget);

    // Anchor the drag to the card ListView's viewport center: 'EXPENSES'
    // unmounts after the first scroll in the lazy list, so a finder-based
    // drag throws on iteration 2.
    final cardList = find
        .ancestor(of: find.text('EXPENSES'), matching: find.byType(ListView))
        .first;
    final center = tester.getRect(cardList).center;
    for (var i = 0; i < 15 && find.text('Item 19').evaluate().isEmpty; i++) {
      await tester.dragFrom(center, const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.text('Item 19'), findsOneWidget);
    expectNoFlexOverflow(drainExceptions(tester));
  });

  testWidgets('empty finance note shows CTA and no duplicate add button', (tester) async {
    await seed([finNote([])], tab: 'notes');
    await pumpHome(tester, surface: const Size(390, 844));
    await openNote(tester, 'Card');

    expect(find.text('Add your first expense'), findsOneWidget);
    expect(find.text('Entry'), findsNothing);
    expect(find.text('EXPENSES'), findsNothing);
    expectNoFlexOverflow(drainExceptions(tester));
  });

  testWidgets('long text and huge amount never overflow at 320px', (tester) async {
    await seed(
      [
        finNote([
          mkEntry(1,
              amount: 123456789,
              note: 'A very long note that keeps going and going and going well past any reasonable length'),
        ]),
      ],
      tab: 'notes',
    );
    // rename category to a long title via a second entry is not needed; category is
    // 'Item 1' — instead assert the huge amount renders and nothing overflows.
    await pumpHome(tester, surface: const Size(320, 568));
    await openNote(tester, 'Card');

    expect(find.textContaining('₱1,234,567.89', findRichText: true), findsWidgets);
    expectNoFlexOverflow(drainExceptions(tester));
  });

  testWidgets('finance note shows no markdown editor or toolbar', (tester) async {
    await seed(
      [finNote([mkEntry(1, amount: 10000)])],
      tab: 'notes',
    );
    await pumpHome(tester, surface: const Size(390, 844));
    await openNote(tester, 'Card');

    expect(find.text('EXPENSES'), findsOneWidget);
    expect(find.byType(EditorToolbar), findsNothing);
    expect(find.textContaining('Start writing'), findsNothing);
    expect(find.text('Preview'), findsNothing);
    expectNoFlexOverflow(drainExceptions(tester));
  });

  testWidgets('text note still shows body toolbar and Preview chip', (tester) async {
    final now = DateTime.now();
    await seed(
      [
        Note(
          id: 'txt2',
          title: 'Text No Editor',
          content: '',
          tags: [],
          updatedAt: now,
        ),
      ],
      tab: 'notes',
    );
    await pumpHome(tester, surface: const Size(390, 844));
    await openNote(tester, 'Text No Editor');

    expect(find.byType(EditorToolbar), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expectNoFlexOverflow(drainExceptions(tester));
  });
}