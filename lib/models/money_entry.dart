import '../utils/finance_utils.dart';

class MoneyEntry {
  String id;

  /// Amount in integer minor units of [currency] (see finance_utils).
  int amount;
  String category;
  DateTime date;
  String? note;
  String? paymentMethod;
  String? currency;
  String? type;
  bool isRecurring;
  String? recurInterval;
  DateTime? recurEnd;
  DateTime? lastGenerated;

  /// First-run sample data: excluded from dashboards, totals, alerts, and
  /// the finance widget so the demo cannot pollute real numbers.
  bool isDemo;

  MoneyEntry({
    required this.id,
    required this.amount,
    required this.category,
    required this.date,
    this.note,
    this.paymentMethod,
    this.currency,
    this.type,
    this.isRecurring = false,
    this.recurInterval,
    this.recurEnd,
    this.lastGenerated,
    this.isDemo = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'category': category,
        'date': date.toIso8601String(),
        'note': note,
        'paymentMethod': paymentMethod,
        'currency': currency,
        'type': type,
        'isRecurring': isRecurring,
        'recurInterval': recurInterval,
        'recurEnd': recurEnd?.toIso8601String(),
        'lastGenerated': lastGenerated?.toIso8601String(),
        if (isDemo) 'isDemo': true,
      };

  factory MoneyEntry.fromJson(Map<String, dynamic> json) => MoneyEntry(
        id: json['id'] as String,
        // Legacy documents stored major units as JSON doubles; ints are
        // already minor units. decodeMinorAmount migrates on load.
        amount: decodeMinorAmount(
          json['amount'],
          json['currency'] as String?,
        ),
        category: json['category'] as String,
        date: DateTime.parse(json['date'] as String),
        note: json['note'] as String?,
        paymentMethod: json['paymentMethod'] as String?,
        currency: json['currency'] as String?,
        type: json['type'] as String?,
        isRecurring: (json['isRecurring'] as bool?) ?? false,
        recurInterval: json['recurInterval'] as String?,
        recurEnd: json['recurEnd'] != null
            ? DateTime.parse(json['recurEnd'] as String)
            : null,
        lastGenerated: json['lastGenerated'] != null
            ? DateTime.parse(json['lastGenerated'] as String)
            : null,
        isDemo: (json['isDemo'] as bool?) ?? false,
      );
}
