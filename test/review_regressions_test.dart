import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typed/models/note.dart';
import 'package:typed/screens/home_screen.dart';
import 'package:typed/theme/palettes.dart';
import 'package:typed/utils/note_storage.dart';
import 'package:typed/widgets/mobile_nav.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Midday: time-of-day features (evening prompt, greeting) stay fixed.
  setUp(() {
    final today = DateTime.now();
    HomeScreen.clock =
        () => DateTime(today.year, today.month, today.day, 12);
  });
  tearDown(() => HomeScreen.clock = DateTime.now);
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

  ThemeData theme() => ThemeData(
        useMaterial3: true,
        extensions: <ThemeExtension<dynamic>>[kPalettes.first.light],
      );

  Future<void> pumpApp(
    WidgetTester tester,
    List<Note> notes, {
    String tab = 'home',
  }) async {
    SharedPreferences.setMockInitialValues({
      'onboarded_v1': true,
      'onboarding_flow_complete_v1': true,
      'dock_swipe_hint_seen_v1': true,
      'shell_state_v1': '{"filter":"$tab","tab":"$tab"}',
    });
    await NoteStorage().save(notes);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: theme(), home: const HomeScreen()));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  Future<List<Note>> stored(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 2));
    final saved = await tester.runAsync(() => NoteStorage().loadResult());
    return saved!.items;
  }

  Future<void> capture(WidgetTester tester, String text) async {
    final field = find.widgetWithText(TextField, 'What’s on your mind?');
    await tester.enterText(field, text);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Add as task'));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('undoing one captured task keeps the ones added after it',
      (tester) async {
    await pumpApp(tester, [
      Note(id: 'n', title: 'Plain', content: 'x', tags: const []),
    ]);
    await capture(tester, 'Task A');
    await capture(tester, 'Task B');

    // The first snackbar's Undo is still the one on screen (they queue).
    await tester.tap(find.text('Undo').first);
    await tester.pump(const Duration(milliseconds: 300));

    final inbox = (await stored(tester)).singleWhere((n) => n.title == 'Inbox');
    expect(inbox.content, contains('- [ ] Task B'));
    expect(inbox.content, isNot(contains('Task A')));
  });

  testWidgets('the editor add row keeps focus after adding', (tester) async {
    await pumpApp(
      tester,
      [
        Note(
          id: 'l',
          title: 'List',
          content: '- [ ] one\n',
          tags: const ['todo'],
          type: 'todo',
        ),
      ],
      tab: 'notes',
    );
    await tester.tap(find.text('List').last);
    await tester.pump(const Duration(seconds: 1));

    final field = find.widgetWithText(TextField, 'Add a task');
    await tester.tap(field);
    await tester.enterText(field, 'two');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();

    final editable = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Add a task'),
    );
    expect(editable.focusNode!.hasFocus, isTrue);
  });

  testWidgets('Tasks cards keep their place when one is edited',
      (tester) async {
    final now = DateTime.now();
    await pumpApp(
      tester,
      [
        Note(
          id: 'a',
          title: 'Alpha',
          content: '- [ ] a1\n',
          tags: const ['todo'],
          type: 'todo',
          updatedAt: now,
        ),
        Note(
          id: 'b',
          title: 'Beta',
          // Two tasks: ticking one leaves the list open (an all-done list
          // rightly moves to the "All done" section).
          content: '- [ ] b1\n- [ ] b2\n',
          tags: const ['todo'],
          type: 'todo',
          updatedAt: now.subtract(const Duration(hours: 1)),
        ),
      ],
      tab: 'tasks',
    );
    final betaY = tester.getTopLeft(find.text('Beta')).dy;
    await tester.tap(find.bySemanticsLabel('Complete b1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getTopLeft(find.text('Beta')).dy, betaY);
  });

  testWidgets('the dock expands from collapsed without overflow',
      (tester) async {
    var collapsed = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme(),
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: MobileNav(
              currentTab: 'home',
              onTabChanged: (_) {},
              onCreate: () {},
              collapsed: collapsed,
              onExpand: () => setState(() => collapsed = false),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Home, show navigation'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Tasks'), findsOneWidget);
  });

  testWidgets('a hardware keyboard can type e and i in a text field',
      (tester) async {
    await pumpApp(tester, [
      Note(id: 'n', title: 'Plain', content: 'x', tags: const []),
    ]);
    final field = find.widgetWithText(TextField, 'What’s on your mind?');
    await tester.tap(field);
    await tester.pump();
    // The root shortcut layer must not claim bare letters while typing.
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyE), isFalse);
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyI), isFalse);
  });

  testWidgets('E still adds an expense on the Finance tab', (tester) async {
    await pumpApp(
      tester,
      [Note(id: 'n', title: 'Plain', content: 'x', tags: const [])],
      tab: 'finance',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Add entry'), findsOneWidget);
  });
}
