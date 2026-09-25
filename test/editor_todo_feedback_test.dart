import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typed/models/note.dart';
import 'package:typed/screens/home_screen.dart';
import 'package:typed/theme/palettes.dart';
import 'package:typed/utils/note_storage.dart';

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

  Note todoNote({String content = ''}) => Note(
        id: 'todo1',
        title: 'Shopping list',
        content: content,
        tags: [],
        type: 'todo',
        updatedAt: DateTime.now(),
      );

  testWidgets('empty todo add shows a hint', (tester) async {
    await seed([todoNote()], tab: 'notes');
    await pumpHome(tester, surface: const Size(390, 844));

    await openNote(tester, 'Shopping list');

    await tester.tap(find.text('Add'));
    await tester.pump();

    expect(find.text('Type something to add.'), findsOneWidget);
    expectNoFlexOverflow(drainExceptions(tester));
  });

  testWidgets('todo delete offers undo and restores the item', (tester) async {
    await seed([todoNote(content: '- [ ] Buy milk\n')], tab: 'notes');
    await pumpHome(tester, surface: const Size(390, 844));

    await openNote(tester, 'Shopping list');

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Task deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Buy milk'), findsOneWidget);
    expectNoFlexOverflow(drainExceptions(tester));
  });

  testWidgets('entry save shows Entry added', (tester) async {
    await seed(
      [
        Note(
          id: 'fin1',
          title: 'Travel budget',
          content: '',
          tags: ['finance'],
          type: 'expense',
          currency: 'PHP',
          updatedAt: DateTime.now(),
        ),
      ],
      tab: 'notes',
    );
    await pumpHome(tester, surface: const Size(390, 844));

    await openNote(tester, 'Travel budget');

    await tester.ensureVisible(find.text('Add your first expense'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Add your first expense'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final amountField = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          (w.decoration?.hintText ?? '').endsWith('0.00'),
    );
    await tester.enterText(amountField, '100');
    await tester.pump();

    await tester.ensureVisible(find.text('Add Entry'));
    await tester.tap(find.text('Add Entry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Entry added'), findsOneWidget);
    expectNoFlexOverflow(drainExceptions(tester));
  });

  testWidgets('empty checklist shows a CTA that focuses the add field', (tester) async {
    await seed([todoNote()], tab: 'notes');
    await pumpHome(tester, surface: const Size(390, 844));

    await openNote(tester, 'Shopping list');

    expect(find.text('Add your first to-do'), findsOneWidget);
    expect(find.text('Add your first to-do item below.'), findsNothing);
    await tester.tap(find.text('Add your first to-do'));
    await tester.pump();
    final addField = tester.widget<TextField>(find.byWidgetPredicate(
      (w) => w is TextField && (w.decoration?.hintText ?? '') == 'Add an item...',
    ));
    expect(addField.focusNode!.hasFocus, isTrue);
    expectNoFlexOverflow(drainExceptions(tester));
  });
}