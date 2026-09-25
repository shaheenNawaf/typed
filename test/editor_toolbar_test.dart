import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typed/theme/palettes.dart';
import 'package:typed/widgets/editor_toolbar.dart';

void main() {
  Widget wrap(double width, {bool rawMode = false, VoidCallback? onToggleRaw}) => MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        extensions: <ThemeExtension<dynamic>>[kPalettes.first.light],
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: EditorToolbar(
              onInsertMD: (_) {},
              onInsertLine: (_) {},
              onInsertTable: (_, __, ___) {},
              previewMode: false,
              onTogglePreview: () {},
              wordCount: 0,
              rawMode: rawMode,
              onToggleRaw: onToggleRaw,
            ),
          ),
        ),
      ),
    );

  testWidgets('collapsed mobile row has no word-count badge', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(390));
    await tester.pump();
    expect(find.text('0 w'), findsNothing);
    expect(find.text('H2'), findsOneWidget);
  });

  testWidgets('expanded mobile row shows the word-count badge', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(390));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('0 w'), findsOneWidget);
  });

  testWidgets('raw toggle label renders on one line', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(390, rawMode: true, onToggleRaw: () {}));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Styled'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}