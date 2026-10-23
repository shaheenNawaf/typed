import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typed/models/note.dart';
import 'package:typed/screens/home_screen.dart';
import 'package:typed/theme/palettes.dart';
import 'package:typed/utils/note_storage.dart';
import 'package:typed/voice/transcriber.dart';
import 'package:typed/voice/voice_shaper.dart';
import 'package:typed/widgets/voice_memo_sheet.dart';

/// Speaks whatever the test tells it to.
class FakeTranscriber implements Transcriber {
  TranscriberProblem? problem;
  void Function(String)? _onText;
  void Function(TranscriberProblem)? onProblem;
  void Function(double)? onLevel;
  String _text = '';
  bool listening = false;
  bool cancelled = false;

  /// Mimics Android's on-device recogniser handing back an empty final
  /// result on stop after streaming good partials.
  bool blankOnStop = false;

  FakeTranscriber({this.problem});

  void say(String text) {
    _text = [_text, text].where((s) => s.isNotEmpty).join(' ');
    _onText?.call(_text);
  }

  @override
  Future<TranscriberProblem?> prepare() async => problem;

  @override
  Future<void> start({
    required void Function(String text) onText,
    required void Function(TranscriberProblem problem) onProblem,
    void Function(double level)? onLevel,
  }) async {
    this.onLevel = onLevel;
    _text = '';
    _onText = onText;
    this.onProblem = onProblem;
    listening = true;
  }

  @override
  Future<String> stop() async {
    listening = false;
    if (blankOnStop) {
      _onText?.call('');
      return '';
    }
    return _text;
  }

  @override
  Future<void> cancel() async {
    listening = false;
    cancelled = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final ch in ['com.z4yed.typed/widget', 'flutter_timezone']) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(ch), (call) async => null);
  }

  late FakeTranscriber fake;
  setUp(() {
    final today = DateTime.now();
    HomeScreen.clock = () => DateTime(today.year, today.month, today.day, 12);
    fake = FakeTranscriber();
    VoiceMemo.isSupported = () => true;
    VoiceMemo.createTranscriber = () => fake;
  });
  tearDown(() {
    HomeScreen.clock = DateTime.now;
    VoiceMemo.reset();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> pumpHome(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
    List<Note> extra = const [],
  }) async {
    SharedPreferences.setMockInitialValues({
      'onboarded_v1': true,
      'onboarding_flow_complete_v1': true,
      'dock_swipe_hint_seen_v1': true,
      'shell_state_v1': '{"filter":"home","tab":"home"}',
      ...prefs,
    });
    await NoteStorage().save([
      Note(id: 'x', title: 'Existing', content: 'hi', tags: const []),
      ...extra,
    ]);
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
    await settle(tester);
  }

  Future<List<Note>> saved() async => (await NoteStorage().loadResult()).items;

  testWidgets('speaking tasks saves a to-do list', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byTooltip('Voice memo'));
    await settle(tester);
    expect(find.text('LISTENING'), findsOneWidget);
    expect(find.text('Transcribed on this device'), findsOneWidget);

    fake.say('I need to buy eggs and then call the bank.');
    await tester.pump();
    expect(find.textContaining('buy eggs'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await settle(tester);

    // Review: shaped as a list, tasks editable.
    expect(find.text('To-do list'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Buy eggs'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Call the bank'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(find.text('List saved'), findsOneWidget);
    final list = (await saved()).firstWhere((n) => n.type == 'todo');
    expect(list.content, '- [ ] Buy eggs\n- [ ] Call the bank\n');
    expect(list.tags, containsAll(['todo', 'voice']));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(VoiceMemoSheet.draftKey), isNull);
  });

  testWidgets('switching to Note saves what was said as a note',
      (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byTooltip('Voice memo'));
    await settle(tester);
    fake.say('The talk was about sync. I should email Sam.');
    await tester.tap(find.text('Done'));
    await settle(tester);

    // One incidental task: a note with a checklist line.
    await tester.tap(find.text('Note'));
    await settle(tester);
    await tester.tap(find.text('Save'));
    await settle(tester);

    final note = (await saved()).firstWhere((n) => n.title.contains('talk'));
    expect(note.type, 'text');
    expect(note.content, contains('The talk was about sync.'));
    expect(note.content, contains('- [ ] Email Sam'));
  });

  testWidgets('a sheet closed mid-memo keeps the words for next time',
      (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byTooltip('Voice memo'));
    await settle(tester);
    fake.say('Remember to renew the passport');
    await tester.pump();

    // Swipe the sheet away.
    Navigator.of(tester.element(find.byType(VoiceMemoSheet))).pop();
    await settle(tester);
    expect(fake.cancelled, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(VoiceMemoSheet.draftKey),
      'Remember to renew the passport',
    );

    // Reopening picks the draft back up in review.
    await tester.tap(find.byTooltip('Voice memo'));
    await settle(tester);
    expect(find.text('From your last memo'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Renew the passport'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await settle(tester);
    expect(prefs.getString(VoiceMemoSheet.draftKey), isNull);
  });

  testWidgets('no on-device speech explains itself instead of using the cloud',
      (tester) async {
    fake.problem = TranscriberProblem.unavailable;
    await pumpHome(tester);
    await tester.tap(find.byTooltip('Voice memo'));
    await settle(tester);
    expect(find.text('Voice memos need on-device speech'), findsOneWidget);
    expect(fake.listening, isFalse);

    // Fixed (e.g. language downloaded): Try again starts listening.
    fake.problem = null;
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(find.text('LISTENING'), findsOneWidget);
  });

  testWidgets('a failure mid-memo keeps what was heard for review',
      (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byTooltip('Voice memo'));
    await settle(tester);
    fake.say('Call the dentist');
    await tester.pump();
    fake.onProblem!(TranscriberProblem.unavailable);
    await settle(tester);
    expect(find.widgetWithText(TextField, 'Call the dentist'), findsOneWidget);
  });

  testWidgets('the Create sheet offers a voice memo', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byTooltip('New note'));
    await settle(tester);
    expect(find.text('Voice memo'), findsOneWidget);
  });

  testWidgets('no mic where voice is not supported', (tester) async {
    VoiceMemo.isSupported = () => false;
    await pumpHome(tester);
    expect(find.byTooltip('Voice memo'), findsNothing);
  });

  testWidgets('a recogniser that goes blank on stop keeps what was shown',
      (tester) async {
    fake.blankOnStop = true;
    await pumpHome(tester);
    await tester.tap(find.byTooltip('Voice memo'));
    await settle(tester);
    fake.say('I need to buy eggs and then call the bank.');
    await tester.pump();

    await tester.tap(find.text('Done'));
    await settle(tester);

    expect(find.widgetWithText(TextField, 'Buy eggs'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Call the bank'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await settle(tester);
    final list = (await saved()).firstWhere((n) => n.type == 'todo');
    expect(list.content, '- [ ] Buy eggs\n- [ ] Call the bank\n');
  });

  testWidgets('the on-device model refines the draft when it is installed',
      (tester) async {
    VoiceMemo.refine = (t) async => const VoiceDraft(
          noteTitle: 'n',
          listTitle: 'Bank and groceries',
          kind: VoiceKind.todo,
          tasks: [
            VoiceTask('Call the bank about the card'),
            VoiceTask('Buy rice'),
          ],
          other: [],
        );
    await pumpHome(tester);
    await tester.tap(find.byTooltip('Voice memo'));
    await settle(tester);
    fake.say('the bank still hasnt sorted my card and were out of rice');
    await tester.tap(find.text('Done'));
    await settle(tester);

    expect(find.text('Shaped on this device'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Bank and groceries'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Buy rice'), findsOneWidget);
  });

  testWidgets('a late model draft never overwrites the user\'s edits',
      (tester) async {
    final late = Completer<VoiceDraft?>();
    VoiceMemo.refine = (t) => late.future;
    await pumpHome(tester);
    await tester.tap(find.byTooltip('Voice memo'));
    await settle(tester);
    fake.say('I need to buy eggs');
    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(find.text('Refining…'), findsOneWidget);

    // The user edits the rules draft while the model is still working.
    await tester.enterText(find.widgetWithText(TextField, 'Buy eggs'),
        'Buy free-range eggs');
    late.complete(const VoiceDraft(
      noteTitle: 'n',
      listTitle: 'Model title',
      kind: VoiceKind.todo,
      tasks: [VoiceTask('Something else')],
      other: [],
    ));
    await settle(tester);

    expect(find.text('Something else'), findsNothing);
    expect(find.widgetWithText(TextField, 'Buy free-range eggs'),
        findsOneWidget);
  });

  testWidgets('the level meter hears silence and says so', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byTooltip('Voice memo'));
    await settle(tester);
    expect(find.textContaining('Start talking'), findsOneWidget);

    // Four silent seconds: explain why nothing is showing.
    for (var i = 0; i < 5; i++) {
      fake.onLevel?.call(0.02);
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.textContaining('Not hearing much yet'), findsOneWidget);

    // Sound arrives: the hint goes away.
    fake.onLevel?.call(0.6);
    await tester.pump();
    expect(find.textContaining('Not hearing much yet'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
  });

  testWidgets('a misheard word can be fixed in the transcript and re-shaped',
      (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byTooltip('Voice memo'));
    await settle(tester);
    fake.say('I need to buy x. Call the bank.');
    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(find.widgetWithText(TextField, 'Buy x'), findsOneWidget);

    await tester.tap(find.text('Transcript'));
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'I need to buy x. Call the bank.'),
      'I need to buy eggs. Call the bank.',
    );
    await tester.tap(find.text('Re-shape from transcript'));
    await settle(tester);

    expect(find.widgetWithText(TextField, 'Buy eggs'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Buy x'), findsNothing);
  });

  testWidgets('keep talking adds to an edited draft instead of replacing it',
      (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byTooltip('Voice memo'));
    await settle(tester);
    fake.say('I need to buy eggs. Call the bank.');
    await tester.tap(find.text('Done'));
    await settle(tester);

    await tester.enterText(
        find.widgetWithText(TextField, 'Buy eggs'), 'Buy free-range eggs');
    await tester.tap(find.text('Keep talking'));
    await settle(tester);
    fake.say('Also water the plants.');
    await tester.tap(find.text('Done'));
    await settle(tester);

    expect(find.widgetWithText(TextField, 'Buy free-range eggs'),
        findsOneWidget);
    expect(find.widgetWithText(TextField, 'Call the bank'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Water the plants'), findsOneWidget);
  });

  testWidgets('tasks can go into an existing list, with an exact Undo',
      (tester) async {
    await pumpHome(tester, extra: [
      Note(
        id: 'g',
        title: 'Groceries',
        content: '- [ ] Milk\n',
        tags: const ['todo'],
        type: 'todo',
      ),
    ]);
    await tester.tap(find.byTooltip('Voice memo'));
    await settle(tester);
    fake.say('I need to buy eggs and then buy bread.');
    // Home's Next up also has a Done button; the sheet's is on top.
    await tester.tap(find.text('Done').last);
    await settle(tester);

    await tester.tap(find.text('A new list'));
    await settle(tester);
    await tester.tap(find.text('Groceries').last);
    await settle(tester);
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(find.text('Added 2 tasks to Groceries'), findsOneWidget);
    var list = (await saved()).firstWhere((n) => n.id == 'g');
    expect(list.content, '- [ ] Milk\n- [ ] Buy eggs\n- [ ] Buy bread\n');
    expect((await saved()).where((n) => n.type == 'todo'), hasLength(1));

    await tester.tap(find.text('Undo'));
    await settle(tester);
    list = (await saved()).firstWhere((n) => n.id == 'g');
    expect(list.content.trim(), '- [ ] Milk');
  });

  testWidgets('spoken spending is logged to this month\'s money, with Undo',
      (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byTooltip('Voice memo'));
    await settle(tester);
    fake.say('Spent 250 on lunch. Grab home was 180.');
    await tester.tap(find.text('Done').last);
    await settle(tester);

    // Review: an expense draft with editable amounts.
    expect(find.text('Expense'), findsOneWidget);
    expect(find.widgetWithText(TextField, '250'), findsOneWidget);
    expect(find.widgetWithText(TextField, '180'), findsOneWidget);
    expect(find.text('Food'), findsWidgets);
    expect(find.text('Transport'), findsWidgets);

    await tester.tap(find.text('Log'));
    await settle(tester);

    expect(find.textContaining('2 entries logged'), findsOneWidget);
    final money = (await saved()).firstWhere((n) => n.amounts.isNotEmpty);
    expect(money.amounts.map((e) => e.amount), [25000, 18000]);
    expect(money.amounts.map((e) => e.category), ['Food', 'Transport']);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    final after = await saved();
    expect(after.expand((n) => n.amounts), isEmpty);
  });

  testWidgets('a spoken time shows a date chip with a reminder bell',
      (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byTooltip('Voice memo'));
    await settle(tester);
    fake.say('Call the dentist tomorrow at 3. Buy milk.');
    await tester.tap(find.text('Done').last);
    await settle(tester);

    expect(find.byTooltip('Reminder on'), findsOneWidget);
    expect(find.text('Add date'), findsOneWidget);
    await tester.tap(find.byTooltip('Reminder on'));
    await tester.pump();
    expect(find.byTooltip('Remind me'), findsOneWidget);

    // Clearing the date drops it from the saved line.
    await tester.tap(find.bySemanticsLabel('Clear date'));
    await tester.pump();
    expect(find.text('Add date'), findsNWidgets(2));
    await tester.tap(find.text('Save'));
    await settle(tester);
    final list = (await saved()).firstWhere((n) => n.type == 'todo');
    expect(list.content, '- [ ] Call the dentist\n- [ ] Buy milk\n');
  });

  testWidgets('the widget mic, shortcut and tile open straight into recording',
      (tester) async {
    var served = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.z4yed.typed/widget'),
            (call) async {
      if (call.method == 'getIntent' && !served) {
        served = true;
        return 'voice';
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.z4yed.typed/widget'), (call) async => null));
    await pumpHome(tester);
    await settle(tester);
    expect(find.text('LISTENING'), findsOneWidget);
  });
}
