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
    await pumpHome(tester, [list('- [ ] a\n- [ ] b\n')]);
    expect(find.text('2 things waiting. One at a time.'), findsOneWidget);
  });

  testWidgets('finishing tasks is acknowledged, not just emptied',
      (tester) async {
    await pumpHome(tester, [list('- [ ] only one\n')]);
    expect(find.text('One thing waiting for you.'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('All clear.'), findsOneWidget);
    expect(find.text('You finished 1 task today.'), findsOneWidget);
    expect(
      find.text('You finished 1 task today. Nothing else waiting.'),
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

    expect(find.text('FOR TOMORROW'), findsOneWidget);
    expect(find.text('NEXT UP'), findsNothing);
    final field = find.widgetWithText(TextField, 'Anything for tomorrow?');
    await tester.enterText(field, 'Water the plants');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // It went to the Inbox, so tomorrow's Next up has it ready.
    expect(find.textContaining('Added to Inbox'), findsOneWidget);
    expect(find.text('Water the plants'), findsOneWidget);
  });

  testWidgets('the evening prompt stays away while tasks are open',
      (tester) async {
    final today = DateTime.now();
    HomeScreen.clock =
        () => DateTime(today.year, today.month, today.day, 20);
    await pumpHome(tester, [list('- [ ] still open\n')]);
    expect(find.text('FOR TOMORROW'), findsNothing);
    expect(find.text('still open'), findsOneWidget);
  });
}
