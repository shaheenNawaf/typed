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

  testWidgets('finance summary card never overflows', (tester) async {
    final now = DateTime.now();
    await seed(
      [
        Note(
          id: 'fin1',
          title: 'Travel budget',
          content: '',
          tags: ['finance'],
          type: 'expense',
          currency: 'PHP',
          amounts: [
            MoneyEntry(
              id: 'e1',
              amount: 12345678,
              category: 'Bills',
              date: now,
              type: 'expense',
              currency: 'PHP',
            ),
          ],
          updatedAt: now,
        ),
      ],
      tab: 'notes',
    );
    await pumpHome(tester, surface: const Size(390, 844));

    await openNote(tester, 'Travel budget');

    expect(find.text('EXPENSES'), findsOneWidget);
    expectNoFlexOverflow(drainExceptions(tester));
  });

  testWidgets('highlight overlay lives under the editor and preserves text',
      (tester) async {
    final now = DateTime.now();
    await seed(
      [
        Note(
          id: 'txt1',
          title: 'Draft',
          content: '',
          tags: [],
          updatedAt: now,
        ),
      ],
      tab: 'notes',
    );
    await pumpHome(tester, surface: const Size(390, 844));

    await openNote(tester, 'Draft');

    expect(find.byKey(const Key('md-highlight-layer')), findsOneWidget);

    final contentField = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          (w.decoration?.hintText ?? '').startsWith('Start writing'),
    );

    await tester.enterText(contentField, '# Title **bold**');
    await tester.pump();

    TextSpan overlay() {
      final rich = tester.widget<RichText>(
        find.byKey(const Key('md-highlight-layer')),
      );
      return rich.text as TextSpan;
    }

    String overlayText() =>
        overlay().children!.map((c) => (c as TextSpan).text ?? '').join();

    expect(overlayText(), contains('**bold**'));

    await tester.enterText(contentField, '# Title **bold** tail');
    await tester.pump();

    expect(overlayText(), contains('tail'));
    expectNoFlexOverflow(drainExceptions(tester));
  });
}