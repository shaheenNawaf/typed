import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typed/screens/onboarding_screen.dart';
import 'package:typed/theme/palettes.dart';

void main() {
  testWidgets('page 4 explains navigation and finishes onboarding',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var finishCount = 0;
    bool? capturedIncludeSamples;
    String? capturedFinanceMode;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          extensions: <ThemeExtension<dynamic>>[kPalettes.first.light],
        ),
        home: OnboardingScreen(
          onFinish: ({required bool includeSamples, required String financeMode}) {
            finishCount++;
            capturedIncludeSamples = includeSamples;
            capturedFinanceMode = financeMode;
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Typed'), findsOneWidget);
    expect(find.textContaining('A quiet workspace'), findsOneWidget);

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(find.text('Everything in reach'), findsOneWidget);
    expect(find.text('The dock'), findsOneWidget);
    expect(find.text('Preview & Edit'), findsOneWidget);
    expect(find.text('Raw mode'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);

    await tester.tap(find.text('Get started'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(finishCount, 1);
    expect(capturedIncludeSamples, isTrue);
    expect(capturedFinanceMode, 'simple');
  });
}