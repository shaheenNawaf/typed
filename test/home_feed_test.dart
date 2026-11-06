import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typed/models/money_entry.dart';
import 'package:typed/models/note.dart';
import 'package:typed/screens/home_screen.dart';
import 'package:typed/theme/palettes.dart';
import 'package:typed/utils/note_storage.dart';
import 'package:typed/widgets/mobile_nav.dart';
import 'package:typed/widgets/sidebar.dart';
import 'package:typed/widgets/editor.dart';
import 'package:typed/voice/when_parser.dart';

/// A day as a task line writes it ("Sat, Nov 7"), [addDays] from today.
String todayLabel([int addDays = 0]) {
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

  Future<List<Note>> fixtureNotes({bool withPin = true}) async {
    final now = DateTime.now();
    return [
      Note(
        id: 'fin1',
        title: 'Travel budget',
        content: '# Travel',
        tags: ['finance'],
        type: 'expense',
        currency: 'PHP',
        amounts: [
          MoneyEntry(
            id: 'e1',
            amount: 18000, // minor units -> 180.00 PHP
            category: 'transport',
            date: now,
            type: 'expense',
            currency: 'PHP',
          ),
        ],
        updatedAt: now.subtract(const Duration(hours: 12)),
      ),
      Note(
        id: 'todo1',
        title: 'Todo list',
        content: '- [ ] buy milk\n- [x] write spec\n',
        tags: ['todo'],
        type: 'todo',
        updatedAt: now.subtract(const Duration(hours: 12)),
      ),
      Note(
        id: 'txt1',
        title: 'Welcome to Typed',
        content: 'hello world',
        tags: [],
        isPinned: withPin,
        updatedAt: now.subtract(const Duration(minutes: 2)),
      ),
    ];
  }

  Future<void> seedHome({bool withPin = true}) async {
    SharedPreferences.setMockInitialValues({
      'onboarded_v1': true,
      'onboarding_flow_complete_v1': true,
      'shell_state_v1': '{"filter":"home","tab":"home"}',
    });
    await NoteStorage().save(await fixtureNotes(withPin: withPin));
  }

  Future<void> pumpHome(WidgetTester tester, {Size? surface}) async {
    if (surface != null) {
      // setSurfaceSize only resizes the layout root; MediaQuery keeps the
      // default 800x600, so width-gated production code (_selectNote's
      // desktop filter switch, the >=1200 context panel) would never fire.
      // tester.view drives both layout and MediaQuery, like a real window.
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = surface;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(MaterialApp(theme: testTheme(), home: const HomeScreen()));
    // NEVER pumpAndSettle here: the loading-skeleton shimmer controller
    // repeats forever, so pumpAndSettle would time out. Fixed pumps flush
    // the async load and finish the one-shot section stagger.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('mobile home: one thing per block, nothing extra',
      (tester) async {
    await seedHome();
    await pumpHome(tester, surface: const Size(390, 844));

    expect(find.textContaining('Good '), findsOneWidget);
    expect(find.text('What’s on your mind?'), findsOneWidget);
    // Nothing dated: a quiet Today that offers the undated task.
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('Nothing due today.'), findsOneWidget);
    expect(find.text('buy milk'), findsOneWidget);
    expect(find.text('Do today'), findsOneWidget);
    expect(find.text('write spec'), findsNothing);
    // Recent pages: notes and lists, never the money ledger.
    expect(find.text('RECENT'), findsOneWidget);
    expect(find.text('Welcome to Typed'), findsOneWidget);
    expect(find.text('1 of 2 done'), findsOneWidget);
    expect(find.text('Travel budget'), findsNothing);
    // The swipe tip stays off Home.
    expect(find.text('Swipe up for more'), findsNothing);
    // Money: spent since payday (no budget set).
    expect(find.text('UNTIL PAYDAY'), findsOneWidget);
    expect(find.textContaining('₱180 spent since'), findsOneWidget);
    expect(find.text('Set a budget'), findsOneWidget);
    // The old busy sections stay gone.
    for (final gone in [
      'PINNED',
      'JUMP BACK IN',
      'UP NEXT',
      'WRITING',
      'QUICK ACTIONS',
      'NEXT UP',
      'THIS MONTH',
    ]) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    expect(find.byType(MobileNav), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop home is the same single focused column',
      (tester) async {
    await seedHome();
    await pumpHome(tester, surface: const Size(1440, 900));

    expect(find.byType(Sidebar), findsOneWidget);
    expect(find.byType(MobileNav), findsNothing);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.textContaining('₱180 spent since'), findsOneWidget);
    // "New page" lives in the sidebar; Home adds no second create control.
    expect(
      find.descendant(
        of: find.byType(Sidebar),
        matching: find.text('New page'),
      ),
      findsOneWidget,
    );
    expect(find.text('New page'), findsOneWidget);
    // One column: today and recent share a left edge.
    final nextUpX = tester.getTopLeft(find.text('TODAY')).dx;
    final continueX =
        tester.getTopLeft(find.text('RECENT')).dx;
    expect((nextUpX - continueX).abs(), lessThan(1));
  });

  testWidgets('today: Done ticks it in place, Tomorrow moves its date',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'onboarded_v1': true,
      'onboarding_flow_complete_v1': true,
      'shell_state_v1': '{"filter":"home","tab":"home"}',
    });
    final today = todayLabel();
    await NoteStorage().save([
      Note(
        id: 'todo1',
        title: 'Errands',
        content: '- [ ] first thing — $today\n'
            '- [ ] second thing — $today\n'
            '- [ ] third thing — $today\n',
        tags: ['todo'],
        type: 'todo',
      ),
    ]);
    await pumpHome(tester, surface: const Size(390, 844));

    // The first is the focus; the others are listed under it, no dates.
    expect(find.text('first thing'), findsOneWidget);
    expect(find.text('second thing'), findsOneWidget);
    expect(find.textContaining(' — '), findsNothing);
    expect(find.text('3 for today.'), findsOneWidget);

    await tester.tap(find.text('Tomorrow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('first thing'), findsNothing);
    expect(find.textContaining('Moved to tomorrow'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('third thing'), findsOneWidget);
    // Snackbars queue (a pending Undo is never dropped): "Done" follows
    // once "Moved to tomorrow" has had its turn.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Done: second thing'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    final saved = await tester.runAsync(() => NoteStorage().loadResult());
    final todo = saved!.items.singleWhere((n) => n.id == 'todo1');
    expect(todo.content, contains('- [x] second thing — $today'));
    expect(todo.content, contains('- [ ] first thing — ${todayLabel(1)}'));
  });

  testWidgets('today: Undo puts a moved task back', (tester) async {
    SharedPreferences.setMockInitialValues({
      'onboarded_v1': true,
      'onboarding_flow_complete_v1': true,
      'shell_state_v1': '{"filter":"home","tab":"home"}',
    });
    await NoteStorage().save([
      Note(
        id: 'todo1',
        title: 'Errands',
        content: '- [ ] Pay Meralco — ${todayLabel(-1)}\n'
            '- [ ] Call — ${todayLabel()}\n',
        tags: ['todo'],
        type: 'todo',
      ),
    ]);
    await pumpHome(tester, surface: const Size(390, 844));
    // Overdue comes first, marked as such.
    expect(find.text('Pay Meralco'), findsOneWidget);
    expect(find.text('Due yesterday'), findsOneWidget);
    expect(find.text('1 for today, 1 from yesterday.'), findsOneWidget);

    await tester.tap(find.text('Tomorrow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Due yesterday'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    final saved = await tester.runAsync(() => NoteStorage().loadResult());
    final todo = saved!.items.singleWhere((n) => n.id == 'todo1');
    expect(todo.content, contains('- [ ] Pay Meralco — ${todayLabel(-1)}'));
  });

  testWidgets('today: a quiet day can take on an undated task',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'onboarded_v1': true,
      'onboarding_flow_complete_v1': true,
      'shell_state_v1': '{"filter":"home","tab":"home"}',
    });
    await NoteStorage().save([
      Note(
        id: 'todo1',
        title: 'Errands',
        content: '- [ ] Buy eggs\n',
        tags: ['todo'],
        type: 'todo',
      ),
    ]);
    await pumpHome(tester, surface: const Size(390, 844));
    expect(find.text('1 task in your lists has no date.'), findsOneWidget);

    await tester.tap(find.text('Do today'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    // Now it's today's task: the focus card, with Done.
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Buy eggs'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    final saved = await tester.runAsync(() => NoteStorage().loadResult());
    final todo = saved!.items.singleWhere((n) => n.id == 'todo1');
    expect(todo.content, '- [ ] Buy eggs — ${todayLabel()}\n');
  });

  testWidgets('today says so when nothing is waiting', (tester) async {
    SharedPreferences.setMockInitialValues({
      'onboarded_v1': true,
      'onboarding_flow_complete_v1': true,
      'shell_state_v1': '{"filter":"home","tab":"home"}',
    });
    await NoteStorage().save([
      Note(id: 'n', title: 'Plain', content: 'words', tags: const []),
    ]);
    await pumpHome(tester, surface: const Size(390, 844));
    expect(find.text('Nothing waiting on you.'), findsOneWidget);
    expect(find.text('Done'), findsNothing);
  });

  testWidgets('capture saves a note, or files a task into Inbox',
      (tester) async {
    await seedHome();
    await pumpHome(tester, surface: const Size(390, 844));

    final field = find.widgetWithText(TextField, 'What’s on your mind?');
    await tester.enterText(field, 'Call the landlord');
    // The task / save keys scale in once there is text.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Add as task'));
    await tester.pump(const Duration(milliseconds: 600));
    // Inbox is now the freshest list, so its task is offered first.
    expect(find.text('Call the landlord'), findsOneWidget);
    expect(find.textContaining('Added to Inbox'), findsOneWidget);

    await tester.enterText(field, 'Gift idea: a good fountain pen');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Save note'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pump(const Duration(seconds: 2));
    final saved = await tester.runAsync(() => NoteStorage().loadResult());
    final notes = saved!.items;
    final inbox = notes.singleWhere((n) => n.title == 'Inbox');
    expect(inbox.type, 'todo');
    expect(inbox.content, '- [ ] Call the landlord\n');
    expect(
      notes.where((n) => n.title == 'Gift idea: a good fountain pen'),
      hasLength(1),
    );
  });

  testWidgets('tapping a recent page opens the editor', (tester) async {
    await seedHome();
    await pumpHome(tester, surface: const Size(390, 844));
    await tester.pump();

    final card = find.text('Welcome to Typed');
    await tester.ensureVisible(card);
    await tester.pump();
    await tester.tap(card);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('RECENT'), findsNothing);
    expect(find.byType(MobileNav), findsNothing);
  });

  testWidgets('desktop recent tap opens the note in the three-pane editor',
      (tester) async {
    await seedHome();
    // 1100px: desktop shell (>=1024) but below the 1200px context-panel
    // threshold, keeping the assertion surface to list + editor.
    await pumpHome(tester, surface: const Size(1100, 900));

    final card = find.text('Welcome to Typed').last;
    await tester.ensureVisible(card);
    await tester.pump();
    await tester.tap(card);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    // One more frame: the AnimatedSwitcher prunes the outgoing home child
    // in a status-listener setState that lands on the next pump.
    await tester.pump();

    expect(find.text('RECENT'), findsNothing);
    expect(find.byType(Editor), findsOneWidget);
  });

  testWidgets('money stays in the dominant currency', (tester) async {
    SharedPreferences.setMockInitialValues({
      'onboarded_v1': true,
      'onboarding_flow_complete_v1': true,
      'shell_state_v1': '{"filter":"home","tab":"home"}',
    });
    final now = DateTime.now();
    await NoteStorage().save([
      Note(
        id: 'fin2',
        title: 'Daily spend',
        content: '# Mixed',
        tags: ['finance'],
        type: 'expense',
        currency: 'PHP',
        amounts: [
          MoneyEntry(
            id: 'm1',
            amount: 18000,
            category: 'Food',
            date: now,
            type: 'expense',
            currency: 'PHP',
          ),
          MoneyEntry(
            id: 'm2',
            amount: 999,
            category: 'Food',
            date: now,
            type: 'expense',
            currency: 'USD',
          ),
        ],
        updatedAt: now,
      ),
    ]);
    await pumpHome(tester, surface: const Size(390, 844));

    // ₱180 in the dominant currency; USD is never summed in (the old
    // code produced '₱189.99').
    expect(find.textContaining('₱180 spent since'), findsOneWidget);
    expect(find.textContaining('190'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with a budget, Home says what is left until payday',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'onboarded_v1': true,
      'onboarding_flow_complete_v1': true,
      'shell_state_v1': '{"filter":"home","tab":"home"}',
      'cutoff_budget_v1': '{"amount":1000000,"currency":"PHP"}',
    });
    await NoteStorage().save(await fixtureNotes());
    await pumpHome(tester, surface: const Size(390, 844));
    expect(find.text('UNTIL PAYDAY'), findsOneWidget);
    expect(find.textContaining('₱9,820 left until the'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^About ₱[\d,]+ a day for \d+ days?$')),
        findsOneWidget);
    expect(find.text('On pace'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no money and no budget: no payday card', (tester) async {
    SharedPreferences.setMockInitialValues({
      'onboarded_v1': true,
      'onboarding_flow_complete_v1': true,
      'shell_state_v1': '{"filter":"home","tab":"home"}',
    });
    await NoteStorage().save([
      Note(id: 'n', title: 'Plain', content: 'words', tags: const []),
    ]);
    await pumpHome(tester, surface: const Size(390, 844));
    expect(find.text('UNTIL PAYDAY'), findsNothing);
  });

  testWidgets('on payday, the last cutoff is summed up until Later',
      (tester) async {
    final n = DateTime.now();
    HomeScreen.clock = () => DateTime(n.year, n.month, 15, 12);
    SharedPreferences.setMockInitialValues({
      'onboarded_v1': true,
      'onboarding_flow_complete_v1': true,
      'shell_state_v1': '{"filter":"home","tab":"home"}',
      'cutoff_budget_v1': '{"amount":1000000,"currency":"PHP"}',
    });
    await NoteStorage().save([
      Note(
        id: 'fin',
        title: 'Spending',
        content: '',
        tags: const [],
        type: 'expense',
        currency: 'PHP',
        amounts: [
          MoneyEntry(
            id: 'a',
            amount: 882000,
            category: 'Food',
            date: DateTime(n.year, n.month, 5, 12),
            type: 'expense',
          ),
        ],
      ),
    ]);
    await pumpHome(tester, surface: const Size(390, 844));
    expect(find.text('PAYDAY'), findsOneWidget);
    expect(find.textContaining('₱1,180 kept'), findsOneWidget);
    expect(find.text('₱8,820 of ₱10,000 · most on Food'), findsOneWidget);
    // The summary stands in for the countdown on payday.
    expect(find.text('UNTIL PAYDAY'), findsNothing);

    await tester.tap(find.text('Later'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('PAYDAY'), findsNothing);
    expect(find.text('UNTIL PAYDAY'), findsOneWidget);
    expect(find.textContaining('₱10,000 left until the 30th'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('payday_card_seen_v1'), isNotNull);
  });

  testWidgets('home fits a 320px phone without overflow', (tester) async {
    SharedPreferences.setMockInitialValues({
      'onboarded_v1': true,
      'onboarding_flow_complete_v1': true,
      'shell_state_v1': '{"filter":"home","tab":"home"}',
    });
    await NoteStorage().save([
      Note(
        id: 'todo1',
        title: 'A list with a rather long name that will not fit',
        content: '- [ ] A long task that goes on well past one line of text'
            ' — ${todayLabel()}\n'
            '- [ ] another — ${todayLabel()}\n',
        tags: ['todo'],
        type: 'todo',
      ),
    ]);
    await pumpHome(tester, surface: const Size(320, 640));
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zero notes: mobile home shows empty CTA and opens the picker',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'onboarded_v1': true,
      'onboarding_flow_complete_v1': true,
      'shell_state_v1': '{"filter":"home","tab":"home"}',
    });
    await NoteStorage().save([]);
    await pumpHome(tester, surface: const Size(390, 844));

    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(find.text('Create your first note'), findsOneWidget);

    await tester.tap(find.text('Create your first note'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Blank note'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one note: empty CTA is hidden', (tester) async {
    SharedPreferences.setMockInitialValues({
      'onboarded_v1': true,
      'onboarding_flow_complete_v1': true,
      'shell_state_v1': '{"filter":"home","tab":"home"}',
    });
    final now = DateTime.now();
    await NoteStorage().save([
      Note(
        id: 'txt1',
        title: 'Welcome to Typed',
        content: 'hello world',
        tags: [],
        updatedAt: now,
      ),
    ]);
    await pumpHome(tester, surface: const Size(390, 844));

    expect(find.text('Nothing here yet'), findsNothing);
  });
}