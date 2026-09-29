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

  MoneyEntry editEntry() => MoneyEntry(
        id: 'm_edit_1',
        amount: 12345,
        category: 'Food',
        date: DateTime(2026, 9, 15),
        type: 'expense',
        currency: 'PHP',
        note: 'Lunch',
      );

  Future<void> pumpSheet(
    WidgetTester tester, {
    MoneyEntry? entry,
    VoidCallback? onDelete,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1000, 2200);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme(),
        home: Scaffold(
          body: EntrySheet(
            entry: entry,
            onSave: (_) {},
            currencySymbol: '₱',
            noteCurrency: 'PHP',
            noteType: 'expense',
            onDelete: onDelete,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the date field is visible without opening details',
      (tester) async {
    await pumpSheet(tester);

    expect(find.text('Date'), findsOneWidget);
    expect(find.text('Show details'), findsOneWidget);
    expect(find.text('Currency'), findsNothing);
  });

  testWidgets('tapping show details still reveals the rest', (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.text('Show details'));
    await tester.pump();

    expect(find.text('Currency'), findsOneWidget);
    expect(find.text('Hide details'), findsOneWidget);
    expect(find.text('Date'), findsOneWidget);
  });

  testWidgets('add mode keeps Cancel, Add and Next, and Add Entry',
      (tester) async {
    await pumpSheet(tester);

    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Add & Next'), findsOneWidget);
    expect(find.text('Add Entry'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('edit mode replaces the dead slot with Delete and Update',
      (tester) async {
    var deleted = 0;
    await pumpSheet(
      tester,
      entry: editEntry(),
      onDelete: () => deleted++,
    );

    expect(find.text('Add & Next'), findsNothing);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline), findsNothing);
  });

  testWidgets('tapping Delete fires the callback and closes the sheet',
      (tester) async {
    var deleted = 0;
    await pumpSheet(
      tester,
      entry: editEntry(),
      onDelete: () => deleted++,
    );

    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(deleted, 1);
    expect(find.text('Update'), findsNothing);
  });
}