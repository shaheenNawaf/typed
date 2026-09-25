import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typed/models/money_entry.dart';
import 'package:typed/theme/palettes.dart';
import 'package:typed/widgets/entry_sheet.dart';

void main() {
  ThemeData testTheme() => ThemeData(
        useMaterial3: true,
        extensions: <ThemeExtension<dynamic>>[kPalettes.first.light],
      );

  Finder amountField() => find.byWidgetPredicate(
        (w) => w is TextField && (w.decoration?.hintText ?? '').endsWith('0.00'),
      );

  Future<List<MoneyEntry>> pumpSheet(WidgetTester tester) async {
    final saved = <MoneyEntry>[];
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1000, 2200);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme(),
        home: Scaffold(
          body: EntrySheet(
            onSave: saved.add,
            currencySymbol: '₱',
            noteCurrency: 'PHP',
            noteType: 'expense',
          ),
        ),
      ),
    );
    await tester.pump();
    return saved;
  }

  testWidgets(
      'empty amount shows an inline error and keeps the sheet open',
      (tester) async {
    final saved = await pumpSheet(tester);

    await tester.tap(find.text('Add Entry'));
    await tester.pump();

    expect(find.text('Enter an amount to save this entry.'), findsOneWidget);
    expect(saved, isEmpty);
    expect(find.text('Add Entry'), findsOneWidget);
  });

  testWidgets('zero amount shows the greater-than-zero error', (tester) async {
    final saved = await pumpSheet(tester);

    await tester.enterText(amountField(), '0');
    await tester.pump();
    await tester.tap(find.text('Add Entry'));
    await tester.pump();

    expect(find.text('Amount must be greater than 0.'), findsOneWidget);
    expect(saved, isEmpty);
  });

  testWidgets('missing category saves as Uncategorized', (tester) async {
    final saved = await pumpSheet(tester);

    await tester.enterText(amountField(), '250');
    await tester.pump();
    await tester.tap(find.text('Add Entry'));
    await tester.pump();

    expect(saved, hasLength(1));
    expect(saved.single.category, 'Uncategorized');
    expect(saved.single.amount, 25000);
  });

  testWidgets('typing clears the amount error', (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.text('Add Entry'));
    await tester.pump();
    expect(find.text('Enter an amount to save this entry.'), findsOneWidget);

    await tester.enterText(amountField(), '5');
    await tester.pump();

    expect(find.text('Enter an amount to save this entry.'), findsNothing);
  });
}