import 'dart:convert';

/// Something Typed captured for you (a shared receipt, later a payment
/// notification) that waits for one tap before it counts. Until then it
/// lives here, outside every note, so no total, chart or budget sees it.
/// (Copilot's To Review.)
class ReviewItem {
  final String id;

  /// Minor units of [currency].
  final int amount;
  final String currency;
  final String category;

  /// Who was paid, as the receipt says it.
  final String merchant;
  final DateTime date;

  /// Where it came from, shown under the merchant: "GCash receipt".
  final String source;

  /// The payment's reference number, so the same receipt is never queued
  /// twice.
  final String? ref;

  const ReviewItem({
    required this.id,
    required this.amount,
    required this.currency,
    required this.category,
    required this.merchant,
    required this.date,
    required this.source,
    this.ref,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'amount': amount,
        'currency': currency,
        'category': category,
        'merchant': merchant,
        'date': date.toIso8601String(),
        'source': source,
        'ref': ref,
      };

  static ReviewItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final amount = raw['amount'];
    final date = DateTime.tryParse('${raw['date']}');
    if (amount is! int || amount <= 0 || date == null) return null;
    return ReviewItem(
      id: '${raw['id'] ?? date.microsecondsSinceEpoch}',
      amount: amount,
      currency: '${raw['currency'] ?? 'PHP'}',
      category: '${raw['category'] ?? 'Other'}',
      merchant: '${raw['merchant'] ?? ''}',
      date: date,
      source: '${raw['source'] ?? 'Receipt'}',
      ref: raw['ref'] as String?,
    );
  }
}

const reviewQueueKey = 'review_queue_v1';

/// The stored queue, newest first. Bad rows are skipped, never thrown.
List<ReviewItem> decodeReviewQueue(String? raw) {
  if (raw == null || raw.isEmpty) return [];
  try {
    final list = jsonDecode(raw);
    if (list is! List) return [];
    final items = [for (final r in list) ?ReviewItem.fromJson(r)];
    items.sort((a, b) => b.date.compareTo(a.date));
    return items;
  } catch (_) {
    return [];
  }
}

String encodeReviewQueue(List<ReviewItem> items) =>
    jsonEncode([for (final i in items) i.toJson()]);

/// Adds [item] unless one with the same reference number is already queued
/// or was already logged ([loggedRefs]).
List<ReviewItem> enqueueReview(
  List<ReviewItem> queue,
  ReviewItem item, {
  Set<String> loggedRefs = const {},
}) {
  final ref = item.ref;
  if (ref != null &&
      (loggedRefs.contains(ref) || queue.any((q) => q.ref == ref))) {
    return queue;
  }
  return [item, ...queue];
}
