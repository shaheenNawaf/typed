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

  Finder descField() => find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration?.hintText ?? '') == 'Add a description',
      );

  testWidgets('finance note with no prose shows the add-description affordance',
      (tester) async {
    await seed([finNote([mkEntry(1)], content: '')], tab: 'notes');
    await pumpHome(tester, surface: const Size(390, 844));
    await openNote(tester, 'Card');

    expect(find.text('+ Add description'), findsOneWidget);
    expect(descField(), findsNothing);
    expectNoFlexOverflow(drainExceptions(tester));
  });

  testWidgets('tapping add-description reveals a plain-text field',
      (tester) async {
    await seed([finNote([mkEntry(1)], content: '')], tab: 'notes');
    await pumpHome(tester, surface: const Size(390, 844));
    await openNote(tester, 'Card');

    await tester.tap(find.text('+ Add description'));
    await tester.pump();

    expect(find.text('+ Add description'), findsNothing);
    expect(descField(), findsOneWidget);
    expectNoFlexOverflow(drainExceptions(tester));
  });

  testWidgets('typing in the description persists through onContentChange',
      (tester) async {
    await seed([finNote([mkEntry(1)], content: '')], tab: 'notes');
    await pumpHome(tester, surface: const Size(390, 844));
    await openNote(tester, 'Card');

    await tester.tap(find.text('+ Add description'));
    await tester.pump();
    await tester.enterText(descField(), 'Rent notes');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Close and reopen: the editor rebuilds from the updated note content, so
    // a prefilled field proves the typed text reached onContentChange.
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await openNote(tester, 'Card');

    expect(descField(), findsOneWidget);
    expect(tester.widget<TextField>(descField()).controller!.text, 'Rent notes');
    expectNoFlexOverflow(drainExceptions(tester));
  });

  testWidgets('plain prose renders as an editable description, not read-only',
      (tester) async {
    await seed(
      [finNote([mkEntry(1)], content: 'Just a plain sentence about rent.')],
      tab: 'notes',
    );
    await pumpHome(tester, surface: const Size(390, 844));
    await openNote(tester, 'Card');

    expect(descField(), findsOneWidget);
    expect(
      tester.widget<TextField>(descField()).controller!.text,
      'Just a plain sentence about rent.',
    );
    expect(
      find.text('This note has formatted text. Open source to edit.'),
      findsNothing,
    );
    expectNoFlexOverflow(drainExceptions(tester));
  });

  testWidgets('a heading in the prose makes the description read-only',
      (tester) async {
    await seed(
      [finNote([mkEntry(1)], content: '## September\nRent and groceries')],
      tab: 'notes',
    );
    await pumpHome(tester, surface: const Size(390, 844));
    await openNote(tester, 'Card');

    expect(
      find.text('This note has formatted text. Open source to edit.'),
      findsOneWidget,
    );
    expect(descField(), findsNothing);
    expect(find.textContaining('September'), findsOneWidget);
    expect(find.textContaining('##'), findsNothing);
    expectNoFlexOverflow(drainExceptions(tester));
  });

  testWidgets('a markdown list in the prose makes the description read-only',
      (tester) async {
    await seed(
      [finNote([mkEntry(1)], content: '- Rent\n- Groceries')],
      tab: 'notes',
    );
    await pumpHome(tester, surface: const Size(390, 844));
    await openNote(tester, 'Card');

    expect(
      find.text('This note has formatted text. Open source to edit.'),
      findsOneWidget,
    );
    expect(descField(), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').startsWith('- '),
      ),
      findsNothing,
    );
    expectNoFlexOverflow(drainExceptions(tester));
  });

  testWidgets('a markdown table in the prose makes the description read-only',
      (tester) async {
    await seed(
      [finNote([mkEntry(1)], content: 'Item | Amount\nRent | 500')],
      tab: 'notes',
    );
    await pumpHome(tester, surface: const Size(390, 844));
    await openNote(tester, 'Card');

    expect(
      find.text('This note has formatted text. Open source to edit.'),
      findsOneWidget,
    );
    expect(descField(), findsNothing);
    expectNoFlexOverflow(drainExceptions(tester));
  });

  testWidgets('a regular text note still shows the full markdown editor',
      (tester) async {
    await seed(
      [
        Note(
          id: 'txt-desc',
          title: 'Plain Note',
          content: '',
          tags: [],
          updatedAt: DateTime(2026, 1, 1),
        ),
      ],
      tab: 'notes',
    );
    await pumpHome(tester, surface: const Size(390, 844));
    await openNote(tester, 'Plain Note');

    expect(find.byType(EditorToolbar), findsOneWidget);
    expect(find.text('+ Add description'), findsNothing);
    expect(find.byType(TextField), findsWidgets);
    expectNoFlexOverflow(drainExceptions(tester));
  });
}