import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typed/models/money_entry.dart';
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

  Finder bySemanticsLabel(String label) => find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == label,
      );

  Future<void> seed({required String tab}) async {
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'onboarded_v1': true,
      'onboarding_flow_complete_v1': true,
      'shell_state_v1': '{"filter":"$tab","tab":"$tab"}',
    });
    await NoteStorage().save([
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
            amount: 18000,
            category: 'transport',
            date: now,
            type: 'expense',
            currency: 'PHP',
          ),
        ],
        updatedAt: now.subtract(const Duration(hours: 12)),
      ),
      Note(
        id: 'txt1',
        title: 'Welcome to Typed',
        content: 'hello world',
        tags: [],
        isPinned: true,
        updatedAt: now.subtract(const Duration(minutes: 2)),
      ),
    ]);
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

  testWidgets('mobile notes: no FAB, no header New; dock Create opens picker',
      (tester) async {
    await seed(tab: 'notes');
    await pumpHome(tester, surface: const Size(390, 844));

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(bySemanticsLabel('New note'), findsNothing);
    expect(bySemanticsLabel('Create'), findsOneWidget);

    await tester.tap(bySemanticsLabel('Create'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Blank note'), findsOneWidget);
  });

  testWidgets('mobile finance: dock Create opens expense/income sheet',
      (tester) async {
    await seed(tab: 'finance');
    await pumpHome(tester, surface: const Size(390, 844));

    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(bySemanticsLabel('Create'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Add expense'), findsOneWidget);
    expect(find.text('Add income'), findsOneWidget);
  });

  testWidgets('desktop notes: header New button is kept', (tester) async {
    await seed(tab: 'notes');
    await pumpHome(tester, surface: const Size(1440, 900));

    expect(bySemanticsLabel('New note'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('mobile home: only the dock Create remains', (tester) async {
    await seed(tab: 'home');
    await pumpHome(tester, surface: const Size(390, 844));

    expect(bySemanticsLabel('Create'), findsOneWidget);
    expect(find.text('New page'), findsNothing);
  });

  testWidgets('desktop home: Create square is kept, no dock', (tester) async {
    await seed(tab: 'home');
    await pumpHome(tester, surface: const Size(1440, 900));

    expect(bySemanticsLabel('Create'), findsOneWidget);
  });

  testWidgets(
      'quick-add save shows the log-landing snackbar with the running month total',
      (tester) async {
    await seed(tab: 'finance');
    await pumpHome(tester, surface: const Size(390, 844));

    await tester.tap(bySemanticsLabel('Create'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Add expense'), findsOneWidget);

    await tester.tap(find.text('Add expense'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final amountField = find.byWidgetPredicate(
      (w) => w is TextField && (w.decoration?.hintText ?? '').endsWith('0.00'),
    );
    await tester.enterText(amountField, '100');
    await tester.enterText(
      find.widgetWithText(TextField, 'Or type your own'),
      'Food',
    );
    await tester.pump();

    await tester.tap(find.text('Add Entry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    while (tester.takeException() != null) {}

    expect(find.textContaining('logged'), findsWidgets);

    final snackBar = find.textContaining(RegExp(r'logged · .+: .+ out'));
    expect(snackBar, findsOneWidget);
    expect(tester.widget<Text>(snackBar).data, contains('100.00'));
  });
}