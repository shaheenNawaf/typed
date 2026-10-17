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
    // One task, not a list.
    expect(find.text('NEXT UP'), findsOneWidget);
    expect(find.text('buy milk'), findsOneWidget);
    expect(find.text('in Todo list'), findsOneWidget);
    expect(find.text('write spec'), findsNothing);
    // One page to return to: the last written, not a task list or ledger.
    expect(find.text('PICK UP WHERE YOU LEFT OFF'), findsOneWidget);
    expect(find.text('Welcome to Typed'), findsOneWidget);
    expect(find.text('Travel budget'), findsNothing);
    // Money as one line.
    expect(find.textContaining('180.00 spent in', findRichText: true),
        findsOneWidget);
    // The old busy sections stay gone.
    for (final gone in [
      'PINNED',
      'JUMP BACK IN',
      'UP NEXT',
      'WRITING',
      'QUICK ACTIONS',
      'TODAY',
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
    expect(find.text('NEXT UP'), findsOneWidget);
    expect(find.textContaining('180.00 spent in', findRichText: true),
        findsOneWidget);
    // "New page" lives in the sidebar; Home adds no second create control.
    expect(
      find.descendant(
        of: find.byType(Sidebar),
        matching: find.text('New page'),
      ),
      findsOneWidget,
    );
    expect(find.text('New page'), findsOneWidget);
    // One column: next up and continue share a left edge.
    final nextUpX = tester.getTopLeft(find.text('NEXT UP')).dx;
    final continueX =
        tester.getTopLeft(find.text('PICK UP WHERE YOU LEFT OFF')).dx;
    expect((nextUpX - continueX).abs(), lessThan(1));
  });

  testWidgets('next up: Done ticks it in place, Later sets it aside',
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
        content: '- [ ] first thing\n- [ ] second thing\n- [ ] third thing\n',
        tags: ['todo'],
        type: 'todo',
      ),
    ]);
    await pumpHome(tester, surface: const Size(390, 844));

    expect(find.text('first thing'), findsOneWidget);
    expect(find.text('second thing'), findsNothing);
    expect(find.text('1 of 3'), findsOneWidget);

    await tester.tap(find.text('Later'));
    // First frame starts the swap; the timed pump runs it to the end.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('second thing'), findsOneWidget);
    expect(find.text('first thing'), findsNothing);

    await tester.tap(find.text('Done'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('third thing'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.textContaining('Done: second thing'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    final saved = await tester.runAsync(() => NoteStorage().loadResult());
    final todo = saved!.items.singleWhere((n) => n.id == 'todo1');
    expect(todo.content, contains('- [x] second thing'));
    expect(todo.content, contains('- [ ] first thing'));
  });

  testWidgets('next up says so when nothing is waiting', (tester) async {
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
    // Inbox is now the freshest list, so its task is the one shown.
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

  testWidgets('tapping the continue card opens the editor', (tester) async {
    await seedHome();
    await pumpHome(tester, surface: const Size(390, 844));
    await tester.pump();

    final card = find.text('Welcome to Typed');
    await tester.ensureVisible(card);
    await tester.pump();
    await tester.tap(card);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('PICK UP WHERE YOU LEFT OFF'), findsNothing);
    expect(find.byType(MobileNav), findsNothing);
  });

  testWidgets('desktop continue tap opens the note in the three-pane editor',
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

    expect(find.text('PICK UP WHERE YOU LEFT OFF'), findsNothing);
    expect(find.byType(Editor), findsOneWidget);
  });

  testWidgets('money line stays in the dominant currency', (tester) async {
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

    // ₱180.00 in the dominant currency; USD is never summed in (the old
    // code produced '₱189.99').
    expect(find.textContaining('180.00 spent in', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('189.99', findRichText: true), findsNothing);
    expect(tester.takeException(), isNull);
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
        content: '- [ ] A long task that goes on well past one line of text\n'
            '- [ ] another\n',
        tags: ['todo'],
        type: 'todo',
      ),
    ]);
    await pumpHome(tester, surface: const Size(320, 640));
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
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