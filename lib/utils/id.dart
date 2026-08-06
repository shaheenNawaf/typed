import 'dart:math';

final Random _random = Random();
int _lastIncrement = 0;

/// Generates a collision-resistant unique id with the given [prefix].
///
/// Combines a microsecond timestamp, a random component, and a monotonic
/// counter so ids stay unique even when created rapidly or across clock
/// adjustments. The returned string is safe to use in file paths and JSON.
String generateId(String prefix) {
  final micros = DateTime.now().microsecondsSinceEpoch;
  _lastIncrement = (_lastIncrement + 1) & 0xFFFF;
  return '$prefix${micros.toRadixString(36)}_'
      '${_random.nextInt(0xFFFFFF).toRadixString(36).padLeft(4, '0')}'
      '${_lastIncrement.toRadixString(36).padLeft(3, '0')}';
}
