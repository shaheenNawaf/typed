import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typed/models/note.dart';
import 'package:typed/screens/home_screen.dart';
import 'package:typed/theme/palettes.dart';
import 'package:typed/utils/note_storage.dart';
import 'package:typed/widgets/editor.dart';
import 'package:typed/widgets/note_list.dart';
import 'package:typed/widgets/tasks_view.dart';
import 'package:typed/widgets/workspace_sheet.dart';

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

  final now = DateTime.now();

  List<Note> fixture() => [
        Note(
          id: 'inbox',
          title: 'Inbox',
          content: '- [ ] Call the bank\n- [x] Pay rent\n',
          tags: ['todo'],
          type: 'todo',
          updatedAt: now,
        ),
        Note(
          id: 'groceries',
          title: 'Groceries',
          content: '- [ ] Eggs\n- [ ] Bread\n',
          tags: ['todo'],
          type: 'todo',
          updatedAt: now.subtract(const Duration(hours: 1)),
        ),
        Note(
          id: 'packing',
          title: 'Packing',
          content: '- [x] Passport\n- [x] Charger\n',
          tags: ['todo'],
          type: 'todo',
          updatedAt: now.subtract(const Duration(hours: 2)),
        ),
        Note(
          id: 'prose',
          title: 'Thoughts',
          content: 'Not a list',
          tags: const [],
          updatedAt: now,
        ),
      ];

  Future<void> pumpTab(
    WidgetTester tester, {
    String tab = 'tasks',
    String? filter,
    Size size = const Size(390, 844),
  }) async {
    SharedPreferences.setMockInitialValues({
      'onboarded_v1': true,
      'onboarding_flow_complete_v1': true,
      'shell_state_v1': '{"filter":"${filter ?? tab}","tab":"$tab"}',
    });
    await NoteStorage().save(fixture());
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          extensions: <ThemeExtension<dynamic>>[kPalettes.first.light],
        ),
        home: const HomeScreen(),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  Future<Note> stored(WidgetTester tester, String id) async {
    await tester.pump(const Duration(seconds: 2));
    final saved = await tester.runAsync(() => NoteStorage().loadResult());
    return saved!.items.singleWhere((n) => n.id == id);
  }

  testWidgets('tasks tab groups open tasks by list', (tester) async {
    await pumpTab(tester);

    expect(find.byType(TasksView), findsOneWidget);
    expect(find.byType(NoteList), findsNothing);
    expect(find.text('3 open · 3 lists'), findsOneWidget);
    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Call the bank'), findsOneWidget);
    expect(find.text('Eggs'), findsOneWidget);
    // Done lines fold; an all-done list sinks to one quiet line.
    expect(find.text('Pay rent'), findsNothing);
    expect(find.text('ALL DONE'), findsOneWidget);
    expect(find.text('2 done'), findsOneWidget);
    expect(find.text('Passport'), findsNothing);
    // Prose notes are not lists.
    expect(find.text('Thoughts'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ticking a task in the Tasks view saves it', (tester) async {
    await pumpTab(tester);

    await tester.tap(find.bySemanticsLabel('Complete Eggs'));
    await tester.pump();
    expect(find.text('Eggs'), findsNothing);

    final groceries = await stored(tester, 'groceries');
    expect(groceries.content, '- [x] Eggs\n- [ ] Bread\n');
  });

  testWidgets('each list can take a new task in place', (tester) async {
    await pumpTab(tester);

    final groceriesAdd = find.descendant(
      of: find.ancestor(
        of: find.text('Groceries'),
        matching: find.byType(Container),
      ).first,
      matching: find.byType(TextField),
    );
    await tester.enterText(groceriesAdd, 'Milk');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('Milk'), findsOneWidget);
    final groceries = await stored(tester, 'groceries');
    expect(groceries.content, '- [ ] Eggs\n- [ ] Bread\n- [ ] Milk\n');
  });

  testWidgets('tapping a list title opens it', (tester) async {
    await pumpTab(tester);

    await tester.tap(find.text('Inbox'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(Editor), findsOneWidget);
  });

  testWidgets('desktop Tasks pane uses the grouped view', (tester) async {
    await pumpTab(tester, size: const Size(1440, 900));
    expect(find.byType(TasksView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('phone navigation: swipe up on the dock opens the sheet',
      (tester) async {
    await pumpTab(tester, tab: 'home');

    // No drawer and no corner hamburger: navigation lives at the bottom.
    expect(find.byType(Drawer), findsNothing);
    expect(find.byTooltip('Open navigation'), findsNothing);
    expect(find.byIcon(Icons.menu_rounded), findsNothing);

    await tester.drag(find.byTooltip('Notes'), const Offset(0, -120));
    await settle(tester);

    expect(find.byType(WorkspaceSheet), findsOneWidget);
    expect(find.text('SPACES'), findsOneWidget);
    for (final space in ['Meetings', 'Journal', 'Archive', 'Trash']) {
      expect(find.text(space), findsOneWidget, reason: space);
    }
    expect(find.textContaining('#todo', findRichText: true), findsOneWidget);

    await tester.tap(find.text('Archive'));
    await settle(tester);
    expect(find.byType(WorkspaceSheet), findsNothing);
    expect(find.text('No archived notes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sliding along the dock scrubs to a tab', (tester) async {
    await pumpTab(tester, tab: 'home');

    final from = tester.getCenter(find.byTooltip('Home'));
    final to = tester.getCenter(find.byTooltip('Tasks'));
    final gesture = await tester.startGesture(from);
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await settle(tester);

    expect(find.byType(TasksView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the swipe-up tip shows until the sheet has been opened',
      (tester) async {
    await pumpTab(tester, tab: 'home');
    expect(find.text('Swipe up for more'), findsOneWidget);

    // The tip is itself a way in.
    await tester.tap(find.text('Swipe up for more'));
    await settle(tester);
    expect(find.byType(WorkspaceSheet), findsOneWidget);
    Navigator.of(tester.element(find.byType(WorkspaceSheet))).pop();
    await settle(tester);
    expect(find.text('Swipe up for more'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('dock_swipe_hint_seen_v1'), isTrue);
  });

  testWidgets('screen readers can open navigation without the gesture',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpTab(tester, tab: 'home');

    final node = tester.getSemantics(find.byTooltip('Home'));
    SemanticsNode? withAction;
    SemanticsNode? cursor = node;
    while (cursor != null && withAction == null) {
      final data = cursor.getSemanticsData();
      if (data.customSemanticsActionIds?.isNotEmpty ?? false) {
        withAction = cursor;
      }
      cursor = cursor.parent;
    }
    expect(withAction, isNotNull, reason: 'dock exposes Open navigation');
    semantics.dispose();
  });

  testWidgets('desktop Tasks owns the canvas until a list is opened',
      (tester) async {
    await pumpTab(tester, size: const Size(1440, 900));

    // No 340px column beside an empty editor: the grouped view is the page.
    expect(find.byType(TasksView), findsOneWidget);
    expect(find.text('Select a note to start editing'), findsNothing);
    expect(find.text('Nothing open'), findsNothing);
    final wide = tester.getSize(find.byType(TasksView)).width;
    expect(wide, greaterThan(800));

    await tester.tap(find.text('Groceries'));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    // Opening a list brings the column back beside the editor.
    expect(find.byType(Editor), findsOneWidget);
    expect(tester.getSize(find.byType(TasksView)).width, lessThan(wide));
  });

  testWidgets('releasing a scrub on the lit tab still commits it',
      (tester) async {
    // Archive is reached from the sheet; the dock lights "Notes" for it.
    await pumpTab(tester, tab: 'notes', filter: 'archive');
    expect(find.text('No archived notes'), findsOneWidget);

    final from = tester.getCenter(find.byTooltip('Home'));
    final to = tester.getCenter(find.byTooltip('Notes'));
    final gesture = await tester.startGesture(from);
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await settle(tester);

    // Same as tapping Notes: back to all notes, not stuck in Archive.
    expect(find.text('No archived notes'), findsNothing);
    expect(find.text('Thoughts'), findsWidgets);
  });
}
