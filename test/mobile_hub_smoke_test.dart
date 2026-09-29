import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typed/theme/palettes.dart';
import 'package:typed/widgets/mobile_nav.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ThemeData testTheme() => ThemeData(
        useMaterial3: true,
        extensions: <ThemeExtension<dynamic>>[kPalettes.first.light],
      );

  Widget shell({bool showEditor = false}) {
    return MaterialApp(
      theme: testTheme(),
      home: Scaffold(
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          child: KeyedSubtree(
            key: ValueKey<bool>(showEditor),
            child: SafeArea(
              child: Column(
                children: const [
                  Text('WORKSPACE HEADER'),
                  Expanded(child: Center(child: Text('LIST CONTENT'))),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: MobileNav(
          currentTab: 'notes',
          onTabChanged: (_) {},
          onCreate: () {},
        ),
      ),
    );
  }

  testWidgets(
    'icon-only dock renders five slots and keeps the body live',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(shell());
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(seconds: 1));

      // the dock itself: five icon slots, no visible labels
      expect(find.byType(MobileNav), findsOneWidget);
      expect(find.byIcon(Icons.home_outlined), findsOneWidget);
      expect(find.byIcon(Icons.article_outlined), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.text('Home'), findsNothing);
      expect(find.text('Notes'), findsNothing);
      expect(find.text('Create'), findsNothing);

      // the body above the dock must stay live — nothing swallowed
      expect(find.text('WORKSPACE HEADER'), findsOneWidget);
      expect(find.text('LIST CONTENT'), findsOneWidget);

      // geometry: the body content sits ABOVE the dock icons
      final listY = tester.getTopLeft(find.text('LIST CONTENT')).dy;
      final dockY = tester.getTopLeft(find.byIcon(Icons.home_outlined)).dy;
      expect(listY, lessThan(dockY));
      // regression: the dock must hug the bottom at several pane sizes —
      // a centered or drifted dock means the Scaffold collapsed.
      for (final size in [
        const Size(390, 844),
        const Size(511, 891),
        const Size(700, 900),
      ]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        final dockY = tester.getTopLeft(find.byIcon(Icons.home_outlined)).dy;
        // ignore: avoid_print
        print('DOCKY ${size.width}x${size.height}: dockTop='
            '${dockY.round()} expected>=${(size.height - 200).round()}');
        expect(dockY, greaterThan(size.height - 200),
            reason:
                'dock drifted to the middle at ${size.width}x${size.height}');
      }
    },
  );

  testWidgets('tapping a dock icon fires onTabChanged; + fires onCreate',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    String? lastTab;
    var created = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme(),
        home: Scaffold(
          body: const Center(child: Text('BODY')),
          bottomNavigationBar: MobileNav(
            currentTab: 'notes',
            onTabChanged: (t) => lastTab = t,
            onCreate: () => created = true,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pump();
    expect(lastTab, 'home');

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(created, isTrue);
    expect(tester.takeException(), isNull);
  });
}
