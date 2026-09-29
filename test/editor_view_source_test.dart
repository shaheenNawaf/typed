import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typed/models/money_entry.dart';
import 'package:typed/models/note.dart';
import 'package:typed/screens/home_screen.dart';
import 'package:typed/theme/palettes.dart';
import 'package:typed/utils/note_storage.dart';
import 'package:typed/widgets/editor.dart';

ThemeData testTheme() => ThemeData(
      useMaterial3: true,
      extensions: <ThemeExtension<dynamic>>[kPalettes.first.light],
    );

class _EditorHost extends StatefulWidget {
  final Note note;
  final ValueChanged<String>? onContentChange;
  const _EditorHost({required this.note, this.onContentChange});

  @override
  State<_EditorHost> createState() => _EditorHostState();
}

class _EditorHostState extends State<_EditorHost> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: testTheme(),
      home: Scaffold(
        body: Editor(
          note: widget.note,
          onTitleChange: (_) {},
          onContentChange: (v) {
            widget.onContentChange?.call(v);
            setState(() => widget.note.content = v);
          },
          onImageAdded: (_) {},
          previewMode: false,
          onTogglePreview: () {},
          allNotes: [widget.note],
          onOpenNote: (_) {},
          onTypeChange: (_) {},
          onCurrencyChange: (_) {},
          onAmountsChange: (_) {},
          onTagsChange: (_) {},
          onTogglePin: (_) {},
        ),
      ),
    );
  }
}

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

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_horiz).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> enterSourceMode(WidgetTester tester) async {
    await openMenu(tester);
    await tester.tap(find.text('View source'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Finder sourceField() => find.byWidgetPredicate(
        (w) => w is TextField && (w.decoration?.hintText ?? '#') == '',
      );

  MoneyEntry mkEntry(int i,
          {int amount = 10000, String type = 'expense', String? note}) =>
      MoneyEntry(
        id: 'e$i',
        amount: amount,
        category: 'Item $i',
        note: note,
        date: DateTime(2026, 1, 1, 10, 30),
        type: type,
        currency: 'PHP',
      );

  Note finNote(List<MoneyEntry> amounts, {String content = ''}) => Note(
        id: 'fin2',
        title: 'Card',
        content: content,
        tags: ['finance'],
        type: 'expense',
        currency: 'PHP',
        amounts: amounts,
        updatedAt: DateTime(2026, 1, 1),
      );

  testWidgets('finance note menu offers View source', (tester) async {
    await seed(
      [
        finNote([mkEntry(1)], content: '## September\nRent and groceries'),
      ],
      tab: 'notes',
    );
    await pumpHome(tester, surface: const Size(390, 844));
    await openNote(tester, 'Card');

    await openMenu(tester);

    expect(find.text('View source'), findsOneWidget);
  });

  testWidgets('View source shows the raw markdown verbatim', (tester) async {
    await seed(
      [
        finNote([mkEntry(1)], content: '## September\nRent and groceries'),
      ],
      tab: 'notes',
    );
    await pumpHome(tester, surface: const Size(390, 844));
    await openNote(tester, 'Card');

    await enterSourceMode(tester);

    expect(sourceField(), findsOneWidget);
    expect(
      tester.widget<TextField>(sourceField()).controller!.text,
      '## September\nRent and groceries',
    );
  });

  testWidgets('source mode hides the summary cards and entries', (tester) async {
    await seed(
      [
        finNote([mkEntry(1)], content: '## September\nRent and groceries'),
      ],
      tab: 'notes',
    );
    await pumpHome(tester, surface: const Size(390, 844));
    await openNote(tester, 'Card');

    await enterSourceMode(tester);

    expect(
      find.text('Raw markdown. Transactions are edited structurally.'),
      findsOneWidget,
    );
    expect(find.text('Entry'), findsNothing);
    expect(find.text('EXPENSES'), findsNothing);
  });

  testWidgets('the menu flips to View structured and returns to the cards',
      (tester) async {
    await seed(
      [
        finNote([mkEntry(1)], content: '## September\nRent and groceries'),
      ],
      tab: 'notes',
    );
    await pumpHome(tester, surface: const Size(390, 844));
    await openNote(tester, 'Card');

    await enterSourceMode(tester);
    await openMenu(tester);

    final menuItem = find.descendant(
      of: find.byType(PopupMenuItem<String>),
      matching: find.text('View structured'),
    );
    expect(menuItem, findsOneWidget);

    await tester.tap(menuItem);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('EXPENSES'), findsOneWidget);
    expect(
      find.text('Raw markdown. Transactions are edited structurally.'),
      findsNothing,
    );
  });

  testWidgets('editing the source persists and round-trips', (tester) async {
    String? recorded;
    final note = finNote(
      [mkEntry(1)],
      content: '## September\nRent and groceries',
    );
    await tester.pumpWidget(
      _EditorHost(note: note, onContentChange: (v) => recorded = v),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await enterSourceMode(tester);

    await tester.enterText(
      sourceField(),
      '## October\nRent and groceries',
    );
    await tester.pump();

    expect(recorded, '## October\nRent and groceries');

    await tester.tap(find.text('View structured'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('This note has formatted text. Open source to edit.'),
      findsOneWidget,
    );
    expect(find.textContaining('##'), findsNothing);
  });

  testWidgets('a regular text note menu has no View source item',
      (tester) async {
    await seed(
      [
        Note(
          id: 'txt-vs',
          title: 'Plain',
          content: '',
          tags: [],
          updatedAt: DateTime(2026, 1, 1),
        ),
      ],
      tab: 'notes',
    );
    await pumpHome(tester, surface: const Size(390, 844));
    await openNote(tester, 'Plain');

    await openMenu(tester);

    expect(find.text('View source'), findsNothing);
  });
}