import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typed/models/note.dart';
import 'package:typed/theme/palettes.dart';
import 'package:typed/voice/transcriber.dart';
import 'package:typed/widgets/editor.dart';

class _Fake implements Transcriber {
  void Function(String)? _onText;
  String _text = '';

  void say(String text) {
    _text = text;
    _onText?.call(text);
  }

  @override
  Future<TranscriberProblem?> prepare() async => null;

  @override
  Future<void> start({
    required void Function(String text) onText,
    required void Function(TranscriberProblem problem) onProblem,
    void Function(double level)? onLevel,
  }) async {
    _text = '';
    _onText = onText;
  }

  @override
  Future<String> stop() async => _text;

  @override
  Future<void> cancel() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final ch in ['com.z4yed.typed/widget', 'flutter_timezone']) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(ch), (call) async => null);
  }

  late _Fake fake;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fake = _Fake();
    VoiceMemo.isSupported = () => true;
    VoiceMemo.createTranscriber = () => fake;
  });
  tearDown(VoiceMemo.reset);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<Note> pumpEditor(WidgetTester tester, Note note) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          extensions: <ThemeExtension<dynamic>>[kPalettes.first.light],
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Editor(
              note: note,
              onTitleChange: (_) {},
              onContentChange: (v) => setState(() => note.content = v),
              onImageAdded: (_) {},
              previewMode: false,
              onTogglePreview: () {},
              allNotes: [note],
              onOpenNote: (_) {},
              onTypeChange: (_) {},
              onCurrencyChange: (_) {},
              onAmountsChange: (_) {},
              onTagsChange: (_) {},
              onTogglePin: (_) {},
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    return note;
  }

  testWidgets('dictating into a list appends tasks', (tester) async {
    final note = await pumpEditor(
      tester,
      Note(
        id: 'g',
        title: 'Groceries',
        content: '- [ ] Milk',
        tags: const ['todo'],
        type: 'todo',
      ),
    );
    await tester.tap(find.byTooltip('Dictate'));
    await settle(tester);
    fake.say('I need to buy eggs and then buy bread.');
    await tester.tap(find.text('Done').last);
    await settle(tester);

    expect(find.text('Adding to Groceries'), findsOneWidget);
    await tester.tap(find.text('Add'));
    await settle(tester);
    expect(note.content, '- [ ] Milk\n- [ ] Buy eggs\n- [ ] Buy bread\n');
  });

  testWidgets('dictating into a note appends a paragraph', (tester) async {
    final note = await pumpEditor(
      tester,
      Note(id: 'n', title: 'Talk', content: 'First thought.', tags: const []),
    );
    await tester.tap(find.byTooltip('Dictate'));
    await settle(tester);
    fake.say('Sync is the hard part, not storage.');
    await tester.tap(find.text('Done').last);
    await settle(tester);
    await tester.tap(find.text('Add'));
    await settle(tester);
    expect(
      note.content,
      'First thought.\n\nSync is the hard part, not storage.\n',
    );
  });
}
