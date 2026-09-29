import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typed/screens/home_screen.dart';
import 'package:typed/theme/palettes.dart';
import 'package:typed/widgets/mobile_nav.dart';

/// Boots the REAL HomeScreen shell at phone sizes and asserts the mobile
/// geometry: the dock hugs the bottom and the hub body renders above it.
///
/// Platform channels must be mocked here: flutter_local_notifications'
/// initialize never completes against unmocked channels, which stalled the
/// shell on its loading screen and made earlier diagnostics report a
/// mobile layout that was never actually reached.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.z4yed.typed/widget'),
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter_local_notifications'),
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      (call) async => 'UTC',
    );
  });

  Future<void> pumpShell(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'onboarding_flow_complete_v1': true,
      'onboarded_v1': true,
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          extensions: <ThemeExtension<dynamic>>[kPalettes.first.light],
        ),
        home: const HomeScreen(),
      ),
    );
    // Loading resolves over several microtask hops; pump until the dock
    // exists so a stall here fails as "shell never left loading".
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.byType(MobileNav).evaluate().isNotEmpty &&
          find.text('Typed').evaluate().isEmpty) {
        break;
      }
    }
  }

  for (final size in [
    const Size(390, 844),
    const Size(511, 891),
    const Size(700, 900),
  ]) {
    testWidgets('shell at ${size.width}x${size.height}: dock bottom, body live',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpShell(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(MobileNav), findsOneWidget);

      // The hub body must actually render (regression: a faded-in body can
      // stay invisible in renderers whose animation clock is frozen).
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? '').startsWith('Good '),
        ),
        findsOneWidget,
      );

      final dockTop = tester.getTopLeft(find.byIcon(Icons.home_outlined)).dy;
      expect(
        dockTop,
        greaterThan(size.height - 200),
        reason:
            'dock drifted away from the bottom at ${size.width}x${size.height}',
      );

      final greeting = find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').startsWith('Good '),
      ).first;
      expect(
        tester.getTopLeft(greeting).dy,
        lessThan(dockTop),
        reason: 'hub body must sit above the dock',
      );
    });
  }
}
