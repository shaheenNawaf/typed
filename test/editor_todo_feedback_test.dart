import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typed/models/note.dart';
import 'package:typed/screens/home_screen.dart';
import 'package:typed/theme/palettes.dart';
import 'package:typed/utils/note_storage.dart';
import 'package:typed/widgets/task_row.dart';

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

  TextField addField(WidgetTester tester, String hint) =>
      tester.widget<TextField>(find.byWidgetPredicate(
        (w) => w is TextField && (w.decoration?.hintText ?? '') == hint,
      ));

  testWidgets('Enter adds a task and keeps the add field focused',
      (tester) async {
    await seed([todoNote(content: '- [ ] Buy milk\n')], tab: 'notes');
    await pumpHome(tester, surface: const Size(390, 844));
    await openNote(tester, 'Shopping list');

    final field = find.byWidgetPredicate(
      (w) => w is TextField && (w.decoration?.hintText ?? '') == 'Add a task',
    );
    await tester.tap(field);
    await tester.enterText(field, 'Eggs');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('Eggs'), findsOneWidget);
    expect(addField(tester, 'Add a task').focusNode!.hasFocus, isTrue);
    // Empty Enter is a no-op, not an error.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('Type something to add.'), findsNothing);
    expectNoFlexOverflow(drainExceptions(tester));
  });

  testWidgets('adding keeps lines separate when content lacks a newline',
      (tester) async {
    await seed([todoNote(content: '- [ ] Buy milk')], tab: 'notes');
    await pumpHome(tester, surface: const Size(390, 844));
    await openNote(tester, 'Shopping list');

    final field = find.byWidgetPredicate(
      (w) => w is TextField && (w.decoration?.hintText ?? '') == 'Add a task',
    );
    await tester.enterText(field, 'Eggs');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(seconds: 2));

    final saved = await tester.runAsync(() => NoteStorage().loadResult());
    final note = saved!.items.singleWhere((n) => n.id == 'todo1');
    expect(note.content, '- [ ] Buy milk\n- [ ] Eggs\n');
  });

  testWidgets('swipe deletes a task, with undo', (tester) async {
    await seed([todoNote(content: '- [ ] Buy milk\n')], tab: 'notes');
    await pumpHome(tester, surface: const Size(390, 844));
    await openNote(tester, 'Shopping list');

    // No delete button on every row any more.
    expect(find.byIcon(Icons.close), findsNothing);
    await tester.drag(find.text('Buy milk'), const Offset(-600, 0));
    // Swipe-away, then the row collapses, then the snackbar slides in.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Task deleted'), findsOneWidget);
    expect(find.text('Buy milk'), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Buy milk'), findsOneWidget);
    expectNoFlexOverflow(drainExceptions(tester));
  });

  testWidgets('done tasks fold under Completed', (tester) async {
    await seed(
      [todoNote(content: '- [ ] Open one\n- [x] Done one\n- [x] Done two\n')],
      tab: 'notes',
    );
    await pumpHome(tester, surface: const Size(390, 844));
    await openNote(tester, 'Shopping list');

    expect(find.text('Open one'), findsOneWidget);
    expect(find.text('Done one'), findsNothing);
    expect(find.text('Completed · 2'), findsOneWidget);

    await tester.tap(find.text('Show'));
    await tester.pump();
    expect(find.text('Done one'), findsOneWidget);
    expect(find.text('Done two'), findsOneWidget);
    expect(find.text('Hide'), findsOneWidget);
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

  testWidgets('an empty list opens straight into adding the first task',
      (tester) async {
    await seed([todoNote()], tab: 'notes');
    await pumpHome(tester, surface: const Size(390, 844));

    await openNote(tester, 'Shopping list');

    // No accent CTA button: the add line itself is the invitation.
    expect(find.text('Add your first to-do'), findsNothing);
    expect(
      addField(tester, 'Add your first task').focusNode!.hasFocus,
      isTrue,
    );
    expectNoFlexOverflow(drainExceptions(tester));
  });

  testWidgets('raw Markdown lives in the ••• menu, not on the page',
      (tester) async {
    await seed([todoNote(content: '- [ ] Buy milk\n')], tab: 'notes');
    await pumpHome(tester, surface: const Size(390, 844));
    await openNote(tester, 'Shopping list');

    expect(find.text('Edit raw'), findsNothing);
    await tester.tap(find.byIcon(Icons.more_horiz).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Edit as Markdown'), findsOneWidget);
  });

  testWidgets('a task note with prose opens in the full editor, nothing hidden',
      (tester) async {
    await seed(
      [todoNote(content: 'Plan the trip first.\n\n- [ ] Book flights\n')],
      tab: 'notes',
    );
    await pumpHome(tester, surface: const Size(390, 844));
    await openNote(tester, 'Shopping list');

    // The checklist panel would only render the "- [ ]" line and drop the
    // paragraph; the regular editor keeps every line.
    expect(find.byKey(const ValueKey('checklist-add')), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is EditableText &&
            w.controller.text.contains('Plan the trip first.'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('clearing an existing task deletes it with an Undo',
      (tester) async {
    await seed(
      [todoNote(content: '- [ ] Apples\n- [ ] Bread\n- [ ] Cheese\n')],
      tab: 'notes',
    );
    await pumpHome(tester, surface: const Size(390, 844));
    await openNote(tester, 'Shopping list');

    await tester.tap(find.text('Bread'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Bread'), '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Bread'), findsNothing);
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Bread'), findsOneWidget);
  });

  testWidgets('ticking inside an open list counts toward done today',
      (tester) async {
    await seed([todoNote(content: '- [ ] Apples\n')], tab: 'notes');
    await pumpHome(tester, surface: const Size(390, 844));
    await openNote(tester, 'Shopping list');

    await tester.tap(find.byType(TaskCheck).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('done_today_v1'), endsWith(':1'));
  });
}
