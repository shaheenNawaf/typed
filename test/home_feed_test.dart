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

  testWidgets('mobile home shows quiet index layers and no old sections',
      (tester) async {
    await seedHome();
    await pumpHome(tester, surface: const Size(390, 844));

    expect(find.textContaining('Good '), findsOneWidget);
    expect(find.textContaining('180 spent'), findsOneWidget);
    expect(find.textContaining('1 open task'), findsOneWidget);
    expect(find.text('PINNED'), findsOneWidget);
    expect(find.text('JUMP BACK IN'), findsOneWidget);
    expect(find.text('New page'), findsNothing);
    expect(find.text('QUICK ACTIONS'), findsNothing);
    expect(find.text('CONTINUE'), findsNothing);
    expect(find.text('RECENT'), findsNothing);
    expect(find.text('TODAY'), findsNothing);
    expect(find.text('THIS MONTH'), findsNothing);
    expect(find.text('New note'), findsNothing);
    expect(find.text('Travel budget'), findsOneWidget);
    expect(find.text('Todo list'), findsOneWidget);
    expect(find.text('Welcome to Typed'), findsWidgets);
    expect(find.byType(MobileNav), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinned section is absent when nothing is pinned', (tester) async {
    await seedHome(withPin: false);
    await pumpHome(tester, surface: const Size(390, 844));

    expect(find.text('PINNED'), findsNothing);
    expect(find.text('JUMP BACK IN'), findsOneWidget);
    expect(find.textContaining('Good '), findsOneWidget);
  });

  testWidgets('desktop home renders the same quiet feed inside the desktop shell',
      (tester) async {
    await seedHome();
    await pumpHome(tester, surface: const Size(1440, 900));

    expect(find.byType(Sidebar), findsOneWidget);
    expect(find.byType(MobileNav), findsNothing);
    expect(find.text('JUMP BACK IN'), findsOneWidget);
    // Desktop renders two legitimate "PINNED" texts: the Sidebar's section
    // label and the home feed's section title.
    expect(find.text('PINNED'), findsWidgets);
    expect(find.textContaining('180 spent'), findsOneWidget);
    expect(find.text('New page'), findsNothing);
    expect(find.text('QUICK ACTIONS'), findsNothing);
  });

  testWidgets('tapping a jump-back-in row opens the editor', (tester) async {
    await seedHome();
    await pumpHome(tester, surface: const Size(390, 844));
    await tester.pump();

    // Tap the TEXT note's row (tree order: the PINNED chip comes first, the
    // JUMP BACK IN row last). Finance notes are avoided: the finance editor's
    // fixed-height summary card overflows under synthetic Ahem test fonts.
    final row = find.text('Welcome to Typed').last;
    await tester.ensureVisible(row);
    await tester.pump();
    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('JUMP BACK IN'), findsNothing);
    expect(find.byType(MobileNav), findsNothing);
  });

  testWidgets('desktop home row tap opens the note in the three-pane editor',
      (tester) async {
    await seedHome();
    // 1100px: desktop shell (>=1024) but below the 1200px context-panel
    // threshold, keeping the assertion surface to list + editor.
    await pumpHome(tester, surface: const Size(1100, 900));

    final row = find.text('Welcome to Typed').last;
    await tester.ensureVisible(row);
    await tester.pump();
    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    // One more frame: the AnimatedSwitcher prunes the outgoing home child
    // in a status-listener setState that lands on the next pump.
    await tester.pump();

    expect(find.text('JUMP BACK IN'), findsNothing);
    expect(find.byType(Editor), findsOneWidget);
  });

  testWidgets('todo row subtitle shows the next open item', (tester) async {
    await seedHome();
    await pumpHome(tester, surface: const Size(390, 844));

    // fixture todo1 content: '- [ ] buy milk\n- [x] write spec\n'
    expect(find.textContaining('buy milk · 1 of 2 done'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mixed-currency finance row stays in the dominant currency',
      (tester) async {
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

    // ₱180.00 dominant-currency sum, 1 dominant entry, USD excluded — the
    // old code summed 18000 + 999 minors across currencies into '₱189.99'.
    expect(
      find.textContaining('180.00 · 1 entry · excl. USD'),
      findsOneWidget,
    );
    expect(find.textContaining('189.99'), findsNothing);
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