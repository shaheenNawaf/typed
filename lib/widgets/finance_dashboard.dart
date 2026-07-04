import 'package:flutter/material.dart';
import '../models/budget.dart';
import '../models/money_entry.dart';
import '../models/note.dart';
import '../theme/app_colors.dart';
import '../utils/finance_utils.dart';
import 'budget_sheet.dart';

class FinanceSummary {
  final double totalIncome;
  final double totalExpense;
  final List<MapEntry<String, double>> categories;
  final List<(MoneyEntry, Note)> recentEntries;
  final int entryCount;
  final String dominantCurrency;
  final Map<String, double> incomeByCurrency;
  final Map<String, double> expenseByCurrency;
  final bool hasMixedCurrencies;
  final double previousPeriodExpense;
  final double previousPeriodIncome;
  final double averageDailySpend;

  const FinanceSummary({
    required this.totalIncome,
    required this.totalExpense,
    required this.categories,
    required this.recentEntries,
    required this.entryCount,
    required this.dominantCurrency,
    required this.incomeByCurrency,
    required this.expenseByCurrency,
    required this.hasMixedCurrencies,
    this.previousPeriodExpense = 0,
    this.previousPeriodIncome = 0,
    this.averageDailySpend = 0,
  });

  double get net => totalIncome - totalExpense;
  bool get isEmpty => entryCount == 0;
}

class FinanceStickyHeader extends StatelessWidget {
  final FinanceSummary summary;
  final String period;
  final ValueChanged<String> onPeriodChanged;
  final String Function(String?) currencySymbol;

  const FinanceStickyHeader({
    super.key,
    required this.summary,
    required this.period,
    required this.onPeriodChanged,
    required this.currencySymbol,
  });

  @override
  Widget build(BuildContext context) {
    if (summary.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PeriodSelector(period: period, onChanged: onPeriodChanged),
          const SizedBox(height: 16),
          _buildSummaryCards(context),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(BuildContext context) {
    return _ExpandableSummaryCards(
      summary: summary,
      currencySymbol: currencySymbol,
    );
  }
}

class FinanceDashboardBody extends StatelessWidget {
  final FinanceSummary summary;
  final String period;
  final String Function(String?) currencySymbol;
  final List<Budget> budgets;
  final void Function(Budget)? onAddBudget;
  final void Function(Budget)? onRemoveBudget;
  final void Function(String)? onSelectNote;

  const FinanceDashboardBody({
    super.key,
    required this.summary,
    required this.period,
    required this.currencySymbol,
    this.budgets = const [],
    this.onAddBudget,
    this.onRemoveBudget,
    this.onSelectNote,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle(context, 'RECENT TRANSACTIONS'),
        const SizedBox(height: 8),
        _buildRecentTransactions(context),
        const SizedBox(height: 24),
        _buildSectionTitle(context, 'CATEGORIES'),
        const SizedBox(height: 8),
        _buildCompactCategories(context),
        const SizedBox(height: 24),
        _buildSectionTitle(context, 'BUDGETS'),
        const SizedBox(height: 8),
        _buildBudgetSection(context),
        const SizedBox(height: 8),
      ],
    );
  }


  Widget _buildCompactCategories(BuildContext context) {
    if (summary.categories.isEmpty) return const SizedBox.shrink();

    final totalSpending =
        summary.categories.fold(0.0, (sum, e) => sum + e.value);
    return Column(
      children: summary.categories.take(4).map((e) {
        final fraction =
            totalSpending > 0 ? e.value / totalSpending : 0.0;
        final pct = (fraction * 100).round();
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(_categoryIcon(e.key),
                    size: 14, color: context.colors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(e.key,
                      style:
                          TextStyle(fontSize: 12, color: context.colors.fg),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                Text('$pct%',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: context.colors.monoFontFamily,
                      color: context.colors.muted,
                      fontWeight: FontWeight.w500,
                    )),
                const SizedBox(width: 8),
                Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: context.colors.monoFontFamily,
                      fontWeight: FontWeight.w600,
                      color: context.colors.fg,
                    ),
                    children: [
                      currencySpan(summary.dominantCurrency, TextStyle(
                        fontSize: 11,
                        fontFamily: context.colors.monoFontFamily,
                        fontWeight: FontWeight.w600,
                        color: context.colors.fg,
                      )),
                      TextSpan(
                        text: formatNumber(e.value,
                            decimals:
                                summary.dominantCurrency == 'JPY' ? 0 : 2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: context.colors.muted,
        letterSpacing: 0.08,
      ),
    );
  }

  Widget _buildBudgetSection(BuildContext context) {
    if (onAddBudget == null) return const SizedBox.shrink();

    if (budgets.isEmpty) {
      return Align(
        alignment: Alignment.centerRight,
        child: Tooltip(
          message: 'Add budget',
          waitDuration: const Duration(milliseconds: 400),
          child: InkWell(
            onTap: () {
              final cats = summary.categories.map((e) => e.key).toList();
              BudgetSheet.show(
                context,
                existingCategories: cats,
                currencySymbol: currencySymbol(summary.dominantCurrency),
                onSave: onAddBudget!,
              );
            },
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.add_circle_outline,
                  size: 18, color: context.colors.accent),
            ),
          ),
        ),
      );
    }

    return Column(
      children: budgets.map((b) {
        final actual = summary.categories
            .where((e) => e.key == b.category)
            .fold<double>(0, (sum, e) => sum + e.value);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _BudgetCard(
            budget: b,
            actual: actual,
            currency: summary.dominantCurrency,
            onRemove: onRemoveBudget != null
                ? () => onRemoveBudget!(b)
                : null,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRecentTransactions(BuildContext context) {
    if (summary.recentEntries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'No transactions yet',
          style: TextStyle(fontSize: 13, color: context.colors.muted),
        ),
      );
    }

    return Column(
      children: summary.recentEntries.map((e) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _RecentTransactionRow(
            entry: e.$1,
            isIncome: (e.$1.type ?? e.$2.type) == 'income',
            currency: e.$1.currency ??
                e.$2.currency ??
                summary.dominantCurrency,
          ),
        );
      }).toList(),
    );
  }
}

class FinanceDashboard extends StatelessWidget {
  final FinanceSummary summary;
  final String period;
  final ValueChanged<String> onPeriodChanged;
  final String Function(String?) currencySymbol;
  final String Function(double, String?)? formatAmount;
  final List<Budget> budgets;
  final void Function(Budget)? onAddBudget;
  final void Function(Budget)? onRemoveBudget;
  final void Function(String)? onSelectNote;

  const FinanceDashboard({
    super.key,
    required this.summary,
    required this.period,
    required this.onPeriodChanged,
    required this.currencySymbol,
    this.formatAmount,
    this.budgets = const [],
    this.onAddBudget,
    this.onRemoveBudget,
    this.onSelectNote,
  });

  @override
  Widget build(BuildContext context) {
    if (summary.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FinanceStickyHeader(
          summary: summary,
          period: period,
          onPeriodChanged: onPeriodChanged,
          currencySymbol: currencySymbol,
        ),
        FinanceDashboardBody(
          summary: summary,
          period: period,
          currencySymbol: currencySymbol,
          budgets: budgets,
          onAddBudget: onAddBudget,
          onRemoveBudget: onRemoveBudget,
          onSelectNote: onSelectNote,
        ),
      ],
    );
  }
}

// -- Period Selector ---------------------------------------------------------

class _PeriodSelector extends StatelessWidget {
  final String period;
  final ValueChanged<String> onChanged;
  const _PeriodSelector({required this.period, required this.onChanged});

  static const _periods = ['all', 'week', 'month', 'year'];
  static const _labels = {
    'all': 'All',
    'week': 'Week',
    'month': 'Month',
    'year': 'Year',
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _periods.map((p) {
        final selected = period == p;
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: InkWell(
            onTap: () => onChanged(p),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: selected
                    ? context.colors.accentDim
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _labels[p] ?? p,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected
                      ? context.colors.accent
                      : context.colors.muted,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// -- Expandable Summary Cards ------------------------------------------------

class _ExpandableSummaryCards extends StatefulWidget {
  final FinanceSummary summary;
  final String Function(String?) currencySymbol;

  const _ExpandableSummaryCards({
    required this.summary,
    required this.currencySymbol,
  });

  @override
  State<_ExpandableSummaryCards> createState() =>
      _ExpandableSummaryCardsState();
}

class _ExpandableSummaryCardsState extends State<_ExpandableSummaryCards> {
  String? _selectedStat;

  static const _options = [
    ('net', 'Net'),
    ('txn_count', 'Transactions'),
    ('avg_spend', 'Avg Daily Spend'),
  ];

  String get _dropdownLabel {
    if (_selectedStat == null) return 'Show more';
    return _options.firstWhere((o) => o.$1 == _selectedStat).$2;
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                label: 'INCOME',
                amount: summary.totalIncome,
                color: context.colors.income,
                currency: summary.dominantCurrency,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _SummaryCard(
                label: 'EXPENSES',
                amount: summary.totalExpense,
                color: context.colors.destructive,
                currency: summary.dominantCurrency,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildSelectorRow(context),
        if (_selectedStat != null) ...[
          const SizedBox(height: 8),
          _buildExtraCard(context),
        ],
      ],
    );
  }

  Widget _buildSelectorRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: PopupMenuButton<String>(
            onSelected: (value) => setState(() => _selectedStat = value),
            itemBuilder: (context) => _options.map((o) =>
              PopupMenuItem(value: o.$1, child: Text(o.$2)),
            ).toList(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Text(
                    _dropdownLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.arrow_drop_down,
                      size: 18, color: context.colors.muted),
                ],
              ),
            ),
          ),
        ),
        if (_selectedStat != null) ...[
          const SizedBox(width: 4),
          InkWell(
            onTap: () => setState(() => _selectedStat = null),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.close, size: 14, color: context.colors.muted),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildExtraCard(BuildContext context) {
    final summary = widget.summary;
    switch (_selectedStat) {
      case 'net':
        final netColor = summary.net >= 0
            ? context.colors.income
            : context.colors.destructive;
        return _SummaryCard(
          label: 'NET',
          amount: summary.net,
          color: netColor,
          currency: summary.dominantCurrency,
        );
      case 'txn_count':
        return _SummaryCard(
          label: 'TRANSACTIONS',
          count: '${summary.entryCount}',
          color: context.colors.accent,
          icon: Icons.receipt_outlined,
        );
      case 'avg_spend':
        return _SummaryCard(
          label: 'AVG DAILY SPEND',
          amount: summary.averageDailySpend,
          color: context.colors.accent,
          currency: summary.dominantCurrency,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// -- Summary Card ------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  final String label;
  final double? amount;
  final String? count;
  final Color color;
  final String? currency;
  final IconData? icon;

  const _SummaryCard({
    required this.label,
    this.amount,
    this.count,
    required this.color,
    this.currency,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final valueStyle = TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: color,
      fontFamily: context.colors.monoFontFamily,
      height: 1.1,
    );

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.06,
                    color: context.colors.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: amount != null
                ? Text.rich(
                    TextSpan(
                      style: valueStyle,
                      children: [
                        currencySpan(currency, valueStyle),
                        TextSpan(
                          text: formatNumber(amount!,
                              decimals: currency == 'JPY' ? 0 : 2),
                        ),
                      ],
                    ),
                  )
                : Text(
                    count ?? '',
                    style: valueStyle,
                  ),
          ),
        ],
      ),
    );
  }
}

// -- Spending Trends ---------------------------------------------------------

// -- Category Card -----------------------------------------------------------

IconData _categoryIcon(String category) {
  switch (category.toLowerCase()) {
    case 'food':
    case 'dining':
    case 'restaurant':
      return Icons.restaurant_outlined;
    case 'transport':
    case 'transportation':
    case 'gas':
    case 'fuel':
      return Icons.directions_car_outlined;
    case 'shopping':
    case 'clothing':
      return Icons.shopping_bag_outlined;
    case 'bills':
    case 'utilities':
    case 'electric':
    case 'water':
      return Icons.receipt_outlined;
    case 'entertainment':
    case 'movies':
    case 'games':
      return Icons.movie_outlined;
    case 'health':
    case 'medical':
    case 'fitness':
      return Icons.health_and_safety_outlined;
    case 'education':
    case 'school':
    case 'tuition':
      return Icons.school_outlined;
    case 'salary':
    case 'work':
    case 'income':
      return Icons.work_outlined;
    case 'freelance':
    case 'freelancing':
      return Icons.laptop_outlined;
    case 'investment':
    case 'stocks':
    case 'dividend':
      return Icons.trending_up_outlined;
    case 'groceries':
    case 'supermarket':
      return Icons.local_grocery_store_outlined;
    case 'rent':
    case 'housing':
    case 'mortgage':
      return Icons.home_outlined;
    case 'travel':
    case 'hotel':
    case 'vacation':
      return Icons.flight_outlined;
    case 'coffee':
    case 'cafe':
    case 'drinks':
      return Icons.coffee_outlined;
    case 'insurance':
      return Icons.shield_outlined;
    case 'subscription':
    case 'streaming':
      return Icons.subscriptions_outlined;
    case 'gift':
    case 'donation':
    case 'charity':
      return Icons.card_giftcard_outlined;
    default:
      return Icons.circle_outlined;
  }
}



// -- Budget Card -------------------------------------------------------------

class _BudgetCard extends StatelessWidget {
  final Budget budget;
  final double actual;
  final String currency;
  final VoidCallback? onRemove;

  const _BudgetCard({
    required this.budget,
    required this.actual,
    required this.currency,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = budget.limit > 0 ? (actual / budget.limit).clamp(0.0, 1.0) : 0.0;
    final overBudget = actual > budget.limit;
    final pct = (fraction * 100).round();
    final remaining = budget.limit - actual;

    Color barColor;
    if (overBudget) {
      barColor = context.colors.destructive;
    } else if (pct >= 80) {
      barColor = context.colors.accent;
    } else {
      barColor = context.colors.income;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_categoryIcon(budget.category),
                  size: 16, color: barColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  budget.category,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: context.colors.fg,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '$pct%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: barColor,
                  fontFamily: context.colors.monoFontFamily,
                ),
              ),
              if (onRemove != null) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: onRemove,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.close,
                        size: 14, color: context.colors.muted),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: context.colors.border,
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: context.colors.monoFontFamily,
                    fontWeight: FontWeight.w500,
                    color: context.colors.muted,
                  ),
                  children: [
                    TextSpan(text: 'Spent '),
                    currencySpan(currency, TextStyle(
                      fontSize: 11,
                      fontFamily: context.colors.monoFontFamily,
                      fontWeight: FontWeight.w500,
                      color: context.colors.muted,
                    )),
                    TextSpan(
                      text: formatNumber(actual,
                          decimals: currency == 'JPY' ? 0 : 2),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (overBudget)
                Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: context.colors.monoFontFamily,
                      fontWeight: FontWeight.w600,
                      color: context.colors.destructive,
                    ),
                    children: [
                      const TextSpan(text: 'Overspent '),
                      currencySpan(currency, TextStyle(
                        fontSize: 11,
                        fontFamily: context.colors.monoFontFamily,
                        fontWeight: FontWeight.w600,
                        color: context.colors.destructive,
                      )),
                      TextSpan(
                        text: formatNumber(remaining.abs(),
                            decimals: currency == 'JPY' ? 0 : 2),
                      ),
                    ],
                  ),
                )
              else
                Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: context.colors.monoFontFamily,
                      fontWeight: FontWeight.w500,
                      color: context.colors.income,
                    ),
                    children: [
                      const TextSpan(text: 'Left '),
                      currencySpan(currency, TextStyle(
                        fontSize: 11,
                        fontFamily: context.colors.monoFontFamily,
                        fontWeight: FontWeight.w500,
                        color: context.colors.income,
                      )),
                      TextSpan(
                        text: formatNumber(remaining,
                            decimals: currency == 'JPY' ? 0 : 2),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// -- Recent Transaction Row --------------------------------------------------

class _RecentTransactionRow extends StatelessWidget {
  final MoneyEntry entry;
  final bool isIncome;
  final String currency;

  const _RecentTransactionRow({
    required this.entry,
    required this.isIncome,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final date = '${entry.date.month}/${entry.date.day}';
    final amountColor =
        isIncome ? context.colors.income : context.colors.fg;
    final description = entry.note != null && entry.note!.isNotEmpty
        ? entry.note!
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(_categoryIcon(entry.category),
              size: 18, color: context.colors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description ?? entry.category,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: context.colors.fg,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      entry.category,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.colors.muted,
                      ),
                    ),
                    Text(' · ',
                        style: TextStyle(
                            fontSize: 11, color: context.colors.muted)),
                    Text(
                      date,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: context.colors.monoFontFamily,
                        color: context.colors.muted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: context.colors.monoFontFamily,
                  fontWeight: FontWeight.w600,
                  color: amountColor,
                ),
                children: [
                  currencySpan(currency, TextStyle(
                    fontSize: 13,
                    fontFamily: context.colors.monoFontFamily,
                    fontWeight: FontWeight.w600,
                    color: amountColor,
                  )),
                  TextSpan(
                    text: formatNumber(entry.amount,
                        decimals: currency == 'JPY' ? 0 : 2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
