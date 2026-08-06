import 'package:flutter_test/flutter_test.dart';
import 'package:typed/utils/backup.dart';
import 'package:typed/utils/id.dart';

void main() {
  group('generateId', () {
    test('starts with the given prefix', () {
      expect(generateId('n').startsWith('n'), isTrue);
      expect(generateId('m').startsWith('m'), isTrue);
      expect(generateId('b').startsWith('b'), isTrue);
    });

    test('produces unique ids across rapid calls', () {
      final ids = <String>{};
      for (var i = 0; i < 1000; i++) {
        ids.add(generateId('n'));
      }
      expect(ids.length, 1000);
    });

    test('produces unique ids across different prefixes', () {
      final a = generateId('n');
      final b = generateId('m');
      expect(a, isNot(equals(b)));
    });
  });

  group('csvEscape', () {
    test('leaves plain fields unchanged', () {
      expect(csvEscape('hello'), 'hello');
      expect(csvEscape(''), '');
      expect(csvEscape('with space'), 'with space');
    });

    test('wraps fields containing commas', () {
      expect(csvEscape('a,b'), '"a,b"');
    });

    test('doubles embedded quotes', () {
      expect(csvEscape('say "hi"'), '"say ""hi"""');
    });

    test('wraps fields containing newlines', () {
      expect(csvEscape('line1\nline2'), '"line1\nline2"');
    });
  });
}
