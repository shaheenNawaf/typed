import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typed/models/budget.dart';
import 'package:typed/theme/palettes.dart';
import 'package:typed/widgets/budget_sheet.dart';

void main() {
  ThemeData testTheme() => ThemeData(
        useMaterial3: true,
        extensions: <ThemeExtension<dynamic>>[kPalettes.first.light],
      );

  Future<void> pumpSheet(WidgetTester tester, List<Budget> saved) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(600, 1400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme(),
        home: Scaffold(
          body: BudgetSheet(onSave: saved.add),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('empty save shows an inline error and stays open',
      (tester) async {
    final saved = <Budget>[];
    await pumpSheet(tester, saved);

    await tester.tap(find.text('Add'));
    await tester.pump();

    expect(find.text('Enter a spending limit.'), findsOneWidget);
    expect(saved, isEmpty);
    expect(find.text('Add'), findsOneWidget);
  });

  testWidgets('valid save pops and returns the budget', (tester) async {
    final saved = <Budget>[];
    await pumpSheet(tester, saved);

    await tester.enterText(find.byType(TextField).last, '500');
    await tester.pump();
    await tester.tap(find.text('Food'));
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(saved, hasLength(1));
    expect(saved.single.limit, 50000);
    expect(saved.single.category, 'Food');
    expect(find.text('Add'), findsNothing);
  });
}