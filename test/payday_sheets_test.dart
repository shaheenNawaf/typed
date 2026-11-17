import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typed/theme/palettes.dart';
import 'package:typed/utils/cutoff.dart';
import 'package:typed/widgets/payday_sheets.dart';

void main() {
  Future<void> host(
    WidgetTester tester,
    Future<void> Function(BuildContext) open,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          extensions: <ThemeExtension<dynamic>>[kPalettes.first.light],
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('payday sheet: presets, once a month, next payday', (
    tester,
  ) async {
    PaydaySettings? result;
    await host(tester, (context) async {
      result = await showPaydaySheet(
        context,
        PaydaySettings.standard,
        now: DateTime(2026, 11, 7),
      );
    });
    expect(tester.takeException(), isNull);
    expect(find.text('Payday'), findsOneWidget);
    expect(find.textContaining('Sun, Nov 15'), findsOneWidget);

    await tester.tap(find.text('Once a month'));
    await tester.pumpAndSettle();
    expect(find.text('15th'), findsOneWidget);
    await tester.tap(find.byTooltip('Later'));
    await tester.pumpAndSettle();
    expect(find.text('16th'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result!.days, [16]);
  });

  testWidgets('budget sheet: per-day hint, save and remove', (tester) async {
    CutoffBudgetChoice? result;
    await host(tester, (context) async {
      result = await showCutoffBudgetSheet(
        context,
        current: null,
        currency: 'PHP',
        cutoffDays: 16,
        lastSpent: 882000,
      );
    });
    expect(tester.takeException(), isNull);
    expect(find.text('Budget per cutoff'), findsOneWidget);
    expect(find.textContaining('Last cutoff you spent ₱8,820'), findsOneWidget);
    expect(find.text('Remove'), findsNothing);

    await tester.enterText(find.byType(TextField), '16000');
    await tester.pump();
    expect(find.textContaining('₱1,000'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result!.budget!.amount, 1600000);
  });

  testWidgets('budget sheet: an existing budget can be removed', (
    tester,
  ) async {
    CutoffBudgetChoice? result;
    await host(tester, (context) async {
      result = await showCutoffBudgetSheet(
        context,
        current: const CutoffBudget(1000000, 'PHP'),
        currency: 'PHP',
        cutoffDays: 15,
      );
    });
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '10000',
    );
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.budget, isNull);
  });
}
