import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typed/theme/palettes.dart';
import 'package:typed/widgets/sidebar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ThemeData testTheme() => ThemeData(
        useMaterial3: true,
        extensions: <ThemeExtension<dynamic>>[kPalettes.first.light],
      );

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

  testWidgets('collapsed sidebar puts a tooltip on every section',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme(),
        home: Scaffold(
          body: Sidebar(
            activeFilter: 'home',
            onFilterChanged: (_) {},
            sidebarState: 'icons',
            onCollapse: () {},
            onTagFilter: (_) {},
            onSettings: () {},
            counts: const {},
            allTags: const [],
            tagCounts: const {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final messages = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((tooltip) => tooltip.message)
        .toSet();

    expect(
      messages.containsAll(const [
        'Home',
        'Notes',
        'Finance',
        'Tasks',
        'Meetings',
        'Journal',
        'Archive',
        'Trash',
      ]),
      isTrue,
      reason: 'collapsed sidebar tooltips: $messages',
    );

    expectNoFlexOverflow(drainExceptions(tester));
  });
}