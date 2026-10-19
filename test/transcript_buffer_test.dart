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

  group('fast speech (phrases locked in mid-session)', () {
    test('each locked phrase is kept when the next starts from scratch', () {
      final b = TranscriptBuffer()
        ..partial('buy eggs')
        ..partial('buy eggs and bread')
        ..intermediate('buy eggs and bread')
        ..partial('call the')
        ..partial('call the bank')
        ..intermediate('call the bank')
        ..partial('water the plants')
        ..finalResult('');
      expect(b.text, 'buy eggs and bread call the bank water the plants');
    });

    test('a cumulative recogniser is not doubled', () {
      final b = TranscriptBuffer()
        ..partial('buy eggs')
        ..intermediate('buy eggs')
        ..partial('buy eggs call mom')
        ..intermediate('Buy eggs, call mom')
        ..partial('buy eggs call mom water the plants')
        ..finalResult('Buy eggs, call mom, water the plants.');
      expect(b.text, 'buy eggs call mom water the plants.');
    });

    test('a final that repeats the last locked phrase adds nothing', () {
      final b = TranscriptBuffer()
        ..intermediate('pay rent')
        ..finalResult('Pay rent.');
      expect(b.text, 'pay rent');
    });

    test('an empty locked phrase keeps the guess', () {
      final b = TranscriptBuffer()
        ..partial('book flights')
        ..intermediate('')
        ..partial('pack bags')
        ..endSession();
      expect(b.text, 'book flights pack bags');
    });

    test('locked phrases survive a session that just ends', () {
      final b = TranscriptBuffer()
        ..intermediate('first thing')
        ..partial('second thing')
        ..endSession()
        ..partial('third thing')
        ..finalResult('third thing');
      expect(b.text, 'first thing second thing third thing');
    });
  });
}
