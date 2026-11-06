import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typed/models/note.dart';
import 'package:typed/screens/home_screen.dart';
import 'package:typed/theme/palettes.dart';
import 'package:typed/utils/note_storage.dart';
import 'package:typed/voice/when_parser.dart';

/// A day as a task line writes it ("Sat, Nov 7"), [addDays] from today.
String dayLabel([int addDays = 0]) {
  final n = DateTime.now();
  return SpokenWhen(DateTime(n.year, n.month, n.day + addDays)).label;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Midday: time-of-day features (evening prompt, greeting) stay fixed.
  setUp(() {
    final today = DateTime.now();
    HomeScreen.clock =
        () => DateTime(today.year, today.month, today.day, 12);
  });
  tearDown(() => HomeScreen.clock = DateTime.now);
  for (final ch in ['com.z4yed.typed/widget', 'flutter_timezone']) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(ch), (call) async => null);
  }

  Future<void> pumpHome(WidgetTester tester, List<Note> notes) async {
    SharedPreferences.setMockInitialValues({
      'onboarded_v1': true,
      'onboarding_flow_complete_v1': true,
      'dock_swipe_hint_seen_v1': true,
      'shell_state_v1': '{"filter":"home","tab":"home"}',
    });
    await NoteStorage().save(notes);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        extensions: <ThemeExtension<dynamic>>[kPalettes.first.light],
      ),
      home: const HomeScreen(),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  Note list(String content) => Note(
        id: 'l',
        title: 'Errands',
        content: content,
        tags: const ['todo'],
        type: 'todo',
      );

  testWidgets('the subline speaks to the day', (tester) async {
    await pumpHome(tester, [
      list('- [ ] a — ${dayLabel()}\n- [ ] b — ${dayLabel()}\n'
          '- [ ] c — ${dayLabel(-1)}\n'),
    ]);
    expect(find.text('2 for today, 1 from yesterday.'), findsOneWidget);
  });

  testWidgets('a day with only undated tasks says nothing is due',
      (tester) async {
    await pumpHome(tester, [list('- [ ] a\n- [ ] b\n')]);
    expect(find.text('Nothing due today. A good day to write.'),
        findsOneWidget);
  });

  testWidgets('finishing tasks is acknowledged, not just emptied',
      (tester) async {
    await pumpHome(tester, [list('- [ ] only one — ${dayLabel()}\n')]);
    expect(find.text('1 for today.'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('All clear.'), findsOneWidget);
    expect(find.text('You finished 1 task today.'), findsOneWidget);
    expect(
      find.text('You finished 1 task today. Nothing else due.'),
      findsOneWidget,
    );
  });

  testWidgets('an older page resurfaces, and Not today puts it away',
      (tester) async {
    await pumpHome(tester, [
      Note(
        id: 'old',
        title: 'Ideas for the garden',
        content: 'Raised beds along the fence, tomatoes and basil first.',
        tags: const [],
        updatedAt: DateTime.now().subtract(const Duration(days: 40)),
      ),
    ]);
    expect(find.text('FROM YOUR NOTES'), findsOneWidget);
    expect(find.text('Ideas for the garden'), findsWidgets);
    expect(find.text('5 WEEKS AGO'), findsOneWidget);

    await tester.tap(find.text('Not today'));
    await tester.pump();
    expect(find.text('FROM YOUR NOTES'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('resurface_hidden_day_v1'), isNotNull);
  });

  testWidgets('fresh pages are not resurfaced', (tester) async {
    await pumpHome(tester, [
      Note(
        id: 'new',
        title: 'Today',
        content: 'Something written just now, long enough to preview.',
        tags: const [],
      ),
    ]);
    expect(find.text('FROM YOUR NOTES'), findsNothing);
  });

  testWidgets('tapping the greeting sets the name it greets you by',
      (tester) async {
    await pumpHome(tester, [list('- [ ] a\n')]);
    final greeting =
        find.textContaining(RegExp(r'^Good (morning|afternoon|evening)$'));
    expect(greeting, findsOneWidget);

    await tester.tap(greeting);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('What should we call you?'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Sam');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.textContaining(RegExp(r'^Good (morning|afternoon|evening), Sam$')),
      findsOneWidget,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('display_name_v1'), 'Sam');
  });

  testWidgets('evening with nothing open offers to set up tomorrow',
      (tester) async {
    final today = DateTime.now();
    HomeScreen.clock =
        () => DateTime(today.year, today.month, today.day, 20);
    await pumpHome(tester, [list('- [x] done already\n')]);

    expect(find.textContaining('TOMORROW ·'), findsOneWidget);
    expect(find.text('TODAY'), findsNothing);
    expect(find.text('LEFT FROM TODAY'), findsNothing);
    expect(find.text('Nothing set for tomorrow yet.'), findsOneWidget);
    final field =
        find.widgetWithText(TextField, 'Add something for tomorrow');
    await tester.enterText(field, 'Water the plants');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Dated for tomorrow in the Inbox, so it's listed under Tomorrow.
    expect(find.textContaining('Added to tomorrow'), findsOneWidget);
    expect(find.text('Water the plants'), findsOneWidget);
    expect(find.text('Here’s tomorrow.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    final saved = await tester.runAsync(() => NoteStorage().loadResult());
    final inbox = saved!.items.singleWhere((n) => n.title == 'Inbox');
    expect(inbox.content, '- [ ] Water the plants — ${dayLabel(1)}\n');
  });

  testWidgets('in the evening, what today left moves to tomorrow',
      (tester) async {
    final today = DateTime.now();
    HomeScreen.clock =
        () => DateTime(today.year, today.month, today.day, 20);
    await pumpHome(tester, [list('- [ ] still open — ${dayLabel()}\n')]);
    expect(find.text('LEFT FROM TODAY'), findsOneWidget);
    expect(find.text('still open'), findsOneWidget);
    expect(find.text('1 left over from today.'), findsOneWidget);

    await tester.tap(find.text('Move to tomorrow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('LEFT FROM TODAY'), findsNothing);
    expect(find.textContaining('Moved to tomorrow'), findsOneWidget);
    // Now it's tomorrow's.
    expect(find.text('still open'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    final saved = await tester.runAsync(() => NoteStorage().loadResult());
    expect(saved!.items.single.content, '- [ ] still open — ${dayLabel(1)}\n');
  });

  testWidgets('Leave it puts the leftovers away for the night',
      (tester) async {
    final today = DateTime.now();
    HomeScreen.clock =
        () => DateTime(today.year, today.month, today.day, 20);
    await pumpHome(tester, [list('- [ ] still open — ${dayLabel()}\n')]);
    await tester.tap(find.text('Leave it'));
    await tester.pump();
    expect(find.text('LEFT FROM TODAY'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('leftover_dismissed_day_v1'), isNotNull);
  });

  testWidgets('something timed later tonight keeps Today on top',
      (tester) async {
    final now = DateTime.now();
    HomeScreen.clock = () => DateTime(now.year, now.month, now.day, 20);
    final tonight =
        SpokenWhen(DateTime(now.year, now.month, now.day), hour: 21).label;
    await pumpHome(tester, [list('- [ ] Call Lola — $tonight\n')]);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('Call Lola'), findsOneWidget);
    expect(find.textContaining('TOMORROW ·'), findsOneWidget);
    expect(find.text('LEFT FROM TODAY'), findsNothing);
  });

  testWidgets('on Monday, last week is looked back on until hidden',
      (tester) async {
    final n = DateTime.now();
    final monday = DateTime(n.year, n.month, n.day - (n.weekday - 1), 10);
    HomeScreen.clock = () => monday;
    final lastWeek = monday.subtract(const Duration(days: 5));
    await pumpHome(tester, [
      Note(
        id: 'w',
        title: 'Written last week',
        content: 'words',
        tags: const [],
        createdAt: lastWeek,
        updatedAt: lastWeek,
      ),
      Note(
        id: 'v',
        title: 'Supplier call',
        content: 'They deliver by the 20th.',
        tags: const ['voice'],
        createdAt: lastWeek,
        updatedAt: lastWeek,
      ),
    ]);
    expect(find.textContaining('LAST WEEK ·'), findsOneWidget);
    expect(find.text('—'), findsOneWidget); // no task count kept yet
    expect(find.text('voice memo'), findsOneWidget);
    expect(find.text('Nothing spent last week.'), findsOneWidget);
    expect(find.textContaining('New week. '), findsOneWidget);

    await tester.tap(find.text('Hide'));
    await tester.pump();
    expect(find.textContaining('LAST WEEK ·'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('recap_hidden_v1'), isNotNull);
  });

  testWidgets('finished tasks are logged by day for the recap',
      (tester) async {
    await pumpHome(tester, [list('- [ ] one — ${dayLabel()}\n')]);
    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('done_log_v1'), contains(':1'));
  });
}
