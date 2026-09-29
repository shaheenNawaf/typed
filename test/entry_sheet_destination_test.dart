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

  Future<List<MoneyEntry>> pumpSheet(
    WidgetTester tester, {
    String? destinationLabel,
    Future<String?> Function()? onChangeDestination,
  }) async {
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
            destinationLabel: destinationLabel,
            onChangeDestination: onChangeDestination,
          ),
        ),
      ),
    );
    await tester.pump();
    return saved;
  }

  testWidgets('a destination label renders the saving-to row', (tester) async {
    await pumpSheet(tester, destinationLabel: 'Finance — September 2026');

    expect(find.textContaining('Saving to:'), findsOneWidget);
    expect(
      find.text('Saving to: Finance — September 2026', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('no destination label renders no saving-to row', (tester) async {
    await pumpSheet(tester);

    expect(find.textContaining('Saving to:'), findsNothing);
  });

  testWidgets('change affordance appears only with a callback',
      (tester) async {
    await pumpSheet(tester, destinationLabel: 'Finance — September 2026');

    expect(find.text('Change'), findsNothing);

    await pumpSheet(
      tester,
      destinationLabel: 'Finance — September 2026',
      onChangeDestination: () async => null,
    );

    expect(find.text('Change'), findsOneWidget);
  });

  testWidgets('tapping change invokes the callback', (tester) async {
    var taps = 0;
    await pumpSheet(
      tester,
      destinationLabel: 'Finance — September 2026',
      onChangeDestination: () async {
        taps++;
        return null;
      },
    );

    await tester.tap(find.text('Change'));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets(
      'picking a destination updates the label without closing the sheet',
      (tester) async {
    await pumpSheet(
      tester,
      destinationLabel: 'Finance — September 2026',
      onChangeDestination: () async => 'Finance — October 2026',
    );

    await tester.tap(find.text('Change'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text('Saving to: Finance — October 2026', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.text('Saving to: Finance — September 2026', findRichText: true),
      findsNothing,
    );
    expect(amountField(), findsOneWidget);
  });

  testWidgets(
      'cancelling the destination picker keeps the original label',
      (tester) async {
    await pumpSheet(
      tester,
      destinationLabel: 'Finance — September 2026',
      onChangeDestination: () async => null,
    );

    await tester.tap(find.text('Change'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text('Saving to: Finance — September 2026', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('a very long destination label does not overflow', (tester) async {
    final longLabel = 'Finance — ${'A' * 90}';
    await pumpSheet(tester, destinationLabel: longLabel);

    expect(tester.takeException(), isNull);
  });
}