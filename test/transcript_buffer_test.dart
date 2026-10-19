import 'package:flutter_test/flutter_test.dart';
import 'package:typed/voice/transcriber.dart';

void main() {
  test('an empty final keeps the last guess', () {
    final b = TranscriptBuffer()
      ..partial('buy eggs')
      ..partial('buy eggs and bread')
      ..finalResult('');
    expect(b.text, 'buy eggs and bread');
  });

  test('a session that ends with no final keeps its guess', () {
    final b = TranscriptBuffer()
      ..partial('call the bank')
      ..endSession()
      ..partial('water the plants');
    expect(b.text, 'call the bank water the plants');
  });

  test('a real final replaces the guess', () {
    final b = TranscriptBuffer()
      ..partial('by eggs')
      ..finalResult('Buy eggs.');
    expect(b.text, 'Buy eggs.');
  });

  test('sessions accumulate and empty partials erase nothing', () {
    final b = TranscriptBuffer()
      ..partial('first part')
      ..finalResult('First part.')
      ..partial('')
      ..partial('second part')
      ..endSession();
    expect(b.text, 'First part. second part');
    b.endSession();
    expect(b.text, 'First part. second part');
  });

  test('clear starts over', () {
    final b = TranscriptBuffer()
      ..partial('x')
      ..clear();
    expect(b.text, '');
  });
}
