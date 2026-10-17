import '../utils/finance_utils.dart';

/// The only periods a budget can have. The dashboard's own filter also has
/// "day" and "all", which leaked into budgets created under them: an "All"
/// budget was tracked as monthly but never alerted.
const kBudgetPeriods = ['week', 'month', 'year'];

String normalizeBudgetPeriod(String? period) =>
    kBudgetPeriods.contains(period) ? period! : 'month';

class Budget {
  String id;
  String category;

  /// Limit in integer minor units of [currency] (see finance_utils).
  int limit;
  String currency;
  String period;

  /// First-run sample data: excluded from dashboards and budget alerts.
  bool isDemo;

  Budget({
    required this.id,
    required this.category,
    required this.limit,
    this.currency = 'PHP',
    this.period = 'month',
    this.isDemo = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'limit': limit,
        'currency': currency,
        'period': period,
        if (isDemo) 'isDemo': true,
      };

  factory Budget.fromJson(Map<String, dynamic> json) => Budget(
        id: json['id'] as String,
        category: json['category'] as String,
        limit: decodeMinorAmount(
          json['limit'],
          (json['currency'] as String?) ?? 'PHP',
        ),
        currency: (json['currency'] as String?) ?? 'PHP',
        period: normalizeBudgetPeriod(json['period'] as String?),
        isDemo: (json['isDemo'] as bool?) ?? false,
      );
}
