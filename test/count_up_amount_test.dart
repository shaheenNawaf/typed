import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typed/theme/palettes.dart';
import 'package:typed/widgets/count_up_amount.dart';

void main() {
  Widget wrap(int minor) => MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          extensions: <ThemeExtension<dynamic>>[kPalettes.first.light],
        ),
        home: Scaffold(
          body: Center(
            child: CountUpAmount(
              minor: minor,
              currency: 'PHP',
              style: const TextStyle(fontSize: 22),
            ),
          ),
        ),
      );

  testWidgets('negative amount renders minus before the symbol', (tester) async {
    await tester.pumpWidget(wrap(-50000));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('\u2212₱500.00', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('₱-500.00', findRichText: true), findsNothing);
  });

  testWidgets('zero renders with no sign', (tester) async {
    await tester.pumpWidget(wrap(0));
    await tester.pumpAndSettle();
    expect(find.textContaining('₱0.00', findRichText: true), findsOneWidget);
    expect(find.textContaining('\u2212', findRichText: true), findsNothing);
  });

  testWidgets('positive amount has no sign', (tester) async {
    await tester.pumpWidget(wrap(123456789));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('₱1,234,567.89', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('\u2212', findRichText: true), findsNothing);
  });
}