import 'package:flutter_test/flutter_test.dart';
import 'package:typed/home/review_queue.dart';

void main() {
  ReviewItem item(String id, int day, {String? ref}) => ReviewItem(
        id: id,
        amount: 18600,
        currency: 'PHP',
        category: 'Food',
        merchant: '7-Eleven',
        date: DateTime(2026, 11, day, 9),
        source: 'GCash receipt',
        ref: ref,
      );

  test('round-trips through storage, newest first', () {
    final raw = encodeReviewQueue([item('a', 18), item('b', 20)]);
    final back = decodeReviewQueue(raw);
    expect(back.map((i) => i.id), ['b', 'a']);
    expect(back.first.amount, 18600);
    expect(back.first.source, 'GCash receipt');
  });

  test('bad or missing data never throws', () {
    expect(decodeReviewQueue(null), isEmpty);
    expect(decodeReviewQueue('not json'), isEmpty);
    expect(
      decodeReviewQueue('[{"amount": -5, "date": "2026-11-20"}, 3]'),
      isEmpty,
    );
  });

  test('the same receipt is never queued twice', () {
    var q = enqueueReview(const [], item('a', 20, ref: '6028871884223'));
    q = enqueueReview(q, item('b', 20, ref: '6028871884223'));
    expect(q.length, 1);
    q = enqueueReview(q, item('c', 20, ref: '999'), loggedRefs: {'999'});
    expect(q.length, 1, reason: 'already logged');
    q = enqueueReview(q, item('d', 20));
    expect(q.length, 2, reason: 'no reference number: nothing to match on');
  });
}
