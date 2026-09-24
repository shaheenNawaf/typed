import 'package:flutter/material.dart';
import '../models/budget.dart';
import '../models/money_entry.dart';
import '../models/note.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../theme/app_motion.dart';
import '../utils/finance_utils.dart';
import '../utils/date_format.dart';
import 'budget_sheet.dart';
import 'count_up_amount.dart';
import 'spend_sparkline.dart';

class FinanceSummary {
  // All monetary fields are integer minor units of their currency.
  final int totalIncome;
  final int totalExpense;
  final List<MapEntry<String, int>> categories;
  final List<(MoneyEntry, Note)> recentEntries;
  final int entryCount;
  final String dominantCurrency;
  final Map<String, int> incomeByCurrency;
  final Map<String, int> expenseByCurrency;
  final bool hasMixedCurrencies;
  final int previousPeriodExpense;
  final int previousPeriodIncome;
  final double averageDailySpend;
  final bool averageAvailable;
  final Set<String> noteIds;
  final Map<String, List<MoneyEntry>> entriesByNote;

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
    this.averageAvailable = false,
    this.noteIds = const {},
    this.entriesByNote = const {},
  });

  int get net => totalIncome - totalExpense;
  bool get isEmpty => entryCount == 0;

  Map<String, int> get netByCurrency {
    final currencies = {...incomeByCurrency.keys, ...expenseByCurrency.keys};
    return {
      for (final currency in currencies)
        currency: (incomeByCurrency[currency] ?? 0) -
            (expenseByCurrency[currency] ?? 0),
    };
  }
}

class FinanceStickyHeader extends StatelessWidget {
  final FinanceSummary summary;
  final String period;
  final ValueChanged<String> onPeriodChanged;
  final String Function(String?) currencySymbol;
  final String currencyScope;
  final List<String> currencyOptions;
  final ValueChanged<String>? onCurrencyChanged;

  const FinanceStickyHeader({
    super.key,
    required this.summary,
    required this.period,
    required this.onPeriodChanged,
    required this.currencySymbol,
    required this.currencyScope,
    required this.currencyOptions,
    this.onCurrencyChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (summary.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: _ScopeSelector(
          period: period,
          onPeriodChanged: onPeriodChanged,
          currencyScope: currencyScope,
          currencyOptions: currencyOptions,
          onCurrencyChanged: onCurrencyChanged,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
           _ScopeSelector(
             period: period,
             onPeriodChanged: onPeriodChanged,
             currencyScope: currencyScope,
             currencyOptions: currencyOptions,
             onCurrencyChanged: onCurrencyChanged,
           ),
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
      period: period,
    );
  }
}

class FinanceDashboardBody extends StatefulWidget {
  final FinanceSummary summary;
  final String period;
  final String Function(String?) currencySymbol;
  final List<Budget> budgets;

  /// Dashboard currency scope ('all' or a code); budgets outside the scope are hidden.
  final String currencyScope;

  /// Spend per budget id against each budget's own calendar period —
  /// independent of the dashboard's period selector.
  final Map<String, int> budgetActuals;
  final void Function(Budget)? onAddBudget;
  final void Function(Budget)? onRemoveBudget;
  final void Function(String)? onSelectNote;
  final VoidCallback? onAddExpense;
  final VoidCallback? onAddIncome;
  final void Function(String noteId, String entryId)? onSelectEntry;

  /// Minor-unit expense buckets, oldest -> newest, length 14 (see SpendSparkline).
  final List<int> dailyTotals;

  const FinanceDashboardBody({
    super.key,
    required this.summary,
    required this.period,
    required this.currencySymbol,
    this.budgets = const [],
    this.currencyScope = 'all',
    this.budgetActuals = const {},
    this.onAddBudget,
    this.onRemoveBudget,
    this.onSelectNote,
    this.onAddExpense,
    this.onAddIncome,
    this.onSelectEntry,
    this.dailyTotals = const [],
  });

  @override
  State<FinanceDashboardBody> createState() => _FinanceDashboardBodyState();
}

class _FinanceDashboardBodyState extends State<FinanceDashboardBody> {
  bool _showAllTxns = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle(context, 'RECENT TRANSACTIONS'),
        const SizedBox(height: 8),
        _buildRecentTransactions(context),
        const SizedBox(height: 24),
        _buildSectionTitle(context, 'TOP SPENDING CATEGORIES'),
        const SizedBox(height: 8),
        _buildCompactCategories(context),
        if (widget.dailyTotals.length == 14) ...[
          const SizedBox(height: 24),
          SpendSparkline(
            dailyTotals: widget.dailyTotals,
            currency: widget.summary.dominantCurrency,
          ),
        ],
        const SizedBox(height: 24),
        _buildBudgetHeader(context),
        const SizedBox(height: 8),
        _buildBudgetSection(context),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildCompactCategories(BuildContext context) {
    if (widget.summary.categories.isEmpty) return const SizedBox.shrink();
    return Column(children: _categoryRows(context, widget.summary, limit: 4));
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: AppType.t12,
        fontWeight: FontWeight.w500,
        color: context.colors.muted,
        letterSpacing: 0.08,
      ),
    );
  }

  Widget _buildBudgetSection(BuildContext context) {
    if (widget.onAddBudget == null) return const SizedBox.shrink();

    if (widget.budgets.isEmpty) {
      return Text(
        'No budgets yet. Add one to track spending against a limit.',
        style: TextStyle(fontSize: AppType.t12, color: context.colors.muted),
      );
    }

    final visible = _visibleBudgets(widget.budgets, widget.currencyScope);
    if (visible.isEmpty) {
      return Text(
        'No ${widget.currencyScope} budgets yet.',
        style: TextStyle(fontSize: AppType.t12, color: context.colors.muted),
      );
    }
    final mixedBudgetCurrencies =
        widget.budgets.map((b) => b.currency).toSet().length > 1;

    return Column(
      children: visible.map((b) {
        final actual = widget.budgetActuals[b.id] ?? 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _BudgetCard(
            budget: b,
            actual: actual,
            currency: b.currency,
            period: b.period,
            currencyLabel: mixedBudgetCurrencies ? b.currency : null,
            onEdit: () => _openBudgetSheet(context, b),
            onRemove: widget.onRemoveBudget != null
                ? () => widget.onRemoveBudget!(b)
                : null,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBudgetHeader(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _buildSectionTitle(context, 'BUDGETS')),
        if (widget.onAddBudget != null)
          TextButton.icon(
            onPressed: () => _openBudgetSheet(context),
            icon: const Icon(Icons.add, size: 15),
            label: const Text('Add budget'),
            style: TextButton.styleFrom(
              foregroundColor: context.colors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              textStyle: const TextStyle(fontSize: AppType.t12),
            ),
          ),
      ],
    );
  }

  void _openBudgetSheet(BuildContext context, [Budget? budget]) {
    final cats = widget.summary.categories.map((e) => e.key).toList();
    BudgetSheet.show(
      context,
      budget: budget,
      existingCategories: cats,
      currencySymbol: widget.currencySymbol(widget.summary.dominantCurrency),
      currencyCode: budget?.currency ?? widget.summary.dominantCurrency,
      budgetPeriod: budget?.period ?? widget.period,
      onSave: widget.onAddBudget!,
    );
  }

  Widget _buildRecentTransactions(BuildContext context) {
    if (widget.summary.recentEntries.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'No transactions in this period.',
            style: TextStyle(fontSize: AppType.t13_5, color: context.colors.muted),
          ),
          if (widget.onAddExpense != null || widget.onAddIncome != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (widget.onAddExpense != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.onAddExpense,
                      icon: const Icon(Icons.arrow_downward, size: 15),
                      label: const Text('Expense'),
                    ),
                  ),
                if (widget.onAddExpense != null && widget.onAddIncome != null)
                  const SizedBox(width: 8),
                if (widget.onAddIncome != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.onAddIncome,
                      icon: const Icon(Icons.arrow_upward, size: 15),
                      label: const Text('Income'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      );
    }

    final entries = _showAllTxns
        ? widget.summary.recentEntries
        : widget.summary.recentEntries.take(5).toList();

    return Column(
      children: [
        ...entries.map((e) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _RecentTransactionRow(
              entry: e.$1,
              isIncome: (e.$1.type ?? e.$2.type) == 'income',
              currency:
                  e.$1.currency ?? e.$2.currency ?? widget.summary.dominantCurrency,
              onTap: widget.onSelectEntry != null
                  ? () => widget.onSelectEntry!(e.$2.id, e.$1.id)
                  : widget.onSelectNote == null
                  ? null
                  : () => widget.onSelectNote!(e.$2.id),
            ),
          );
        }),
        if (widget.summary.recentEntries.length > 5)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _showAllTxns = !_showAllTxns),
              style: TextButton.styleFrom(
                foregroundColor: context.colors.muted,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                textStyle: const TextStyle(
                  fontSize: AppType.t12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              child: Text(
                _showAllTxns
                    ? 'Show less'
                    : 'See all ${widget.summary.recentEntries.length} transactions',
              ),
            ),
          ),
      ],
    );
  }
}

// -- Finance Mode Toggle -----------------------------------------------------

/// Simple / Advanced switch shown at the top of the Finance pane. Simple is
/// the calm default (this month at a glance); Advanced is the full dashboard.
class FinanceModeToggle extends StatelessWidget {
  final String mode;
  final ValueChanged<String> onChanged;

  const FinanceModeToggle({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: c.listBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(context, 'simple', 'Simple'),
          _segment(context, 'advanced', 'Advanced'),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, String value, String label) {
    final c = context.colors;
    final selected = mode == value;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: AnimatedContainer(
        duration: AppMotion.duration(context, AppMotion.base),
        curve: AppMotion.emphasized,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? c.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppType.t12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? c.fg : c.muted,
          ),
        ),
      ),
    );
  }
}

// -- Simple Finance View -----------------------------------------------------

/// The Simple finance mode: one month-at-a-glance card, one-tap capture, and
/// a few recent transactions. Only surfaces a budget line when one is
/// actually worth attention, so the pane stays quiet.
class SimpleFinanceView extends StatelessWidget {
  final FinanceSummary summary;
  final List<Budget> budgets;
  final Map<String, int> budgetActuals;
  final VoidCallback? onAddExpense;
  final VoidCallback? onAddIncome;
  final void Function(String)? onSelectNote;
  final void Function(String noteId, String entryId)? onSelectEntry;
  final VoidCallback? onOpenAdvanced;

  const SimpleFinanceView({
    super.key,
    required this.summary,
    this.budgets = const [],
    this.budgetActuals = const {},
    this.onAddExpense,
    this.onAddIncome,
    this.onSelectNote,
    this.onSelectEntry,
    this.onOpenAdvanced,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mixed = summary.hasMixedCurrencies;
    final currency = summary.dominantCurrency;
    final net = summary.net;
    final spentShare = summary.totalIncome > 0
        ? (summary.totalExpense / summary.totalIncome * 100).round().clamp(0, 100)
        : 0;
    final keptPct = summary.totalIncome > 0
        ? (net / summary.totalIncome * 100).round()
        : null;

    // Budgets worth attention (>= 60% used), dominant currency only, worst first.
    final candidates = <(Budget, double)>[];
    for (final b in budgets) {
      if (b.isDemo || b.limit <= 0) continue;
      if (b.currency != summary.dominantCurrency) continue;
      final ratio = (budgetActuals[b.id] ?? 0) / b.limit;
      if (ratio >= 0.6) candidates.add((b, ratio));
    }
    candidates.sort((a, b) => b.$2.compareTo(a.$2));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(AppRadius.panel),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'THIS MONTH',
                    style: TextStyle(
                      fontSize: AppType.t10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.06,
                      color: c.muted,
                    ),
                  ),
                  const Spacer(),
                  if (mixed)
                    Text(
                      'Primary currency',
                      style: TextStyle(fontSize: AppType.t10, color: c.muted),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _amount(
                      context,
                      'SPENT',
                      summary.totalExpense,
                      currency,
                      c.destructive,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _amount(
                      context,
                      'INCOME',
                      summary.totalIncome,
                      currency,
                      c.income,
                    ),
                  ),
                ],
              ),
              if (summary.totalIncome > 0) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 6,
                    child: Row(
                      children: [
                        if (spentShare > 0)
                          Expanded(
                            flex: spentShare,
                            child: Container(color: c.destructive),
                          ),
                        if (spentShare < 100)
                          Expanded(
                            flex: 100 - spentShare,
                            child: Container(color: c.income),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Divider(height: 1, color: c.border),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    keptPct != null && net >= 0
                        ? 'You kept $keptPct%'
                        : 'Net',
                    style: TextStyle(fontSize: AppType.t12, color: c.muted),
                  ),
                  const Spacer(),
                  CountUpAmount(
                    minor: net,
                    currency: currency,
                    style: TextStyle(
                      fontSize: AppType.t12,
                      fontWeight: FontWeight.w600,
                      fontFamily: c.monoFontFamily,
                      color: net >= 0 ? c.income : c.destructive,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onAddExpense,
                icon: const Icon(Icons.arrow_downward, size: 15),
                label: const Text('Expense'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.destructive,
                  side: BorderSide(color: c.border),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onAddIncome,
                icon: const Icon(Icons.arrow_upward, size: 15),
                label: const Text('Income'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.income,
                  side: BorderSide(color: c.border),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
                ),
              ),
            ),
          ],
        ),
        if (candidates.isNotEmpty) ...[
          const SizedBox(height: 14),
          ...candidates.take(2).map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _budgetWarning(context, e.$1, e.$2),
            ),
          ),
          if (candidates.length > 2)
            InkWell(
              onTap: onOpenAdvanced,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                child: Row(
                  children: [
                    Text(
                      candidates.length - 2 == 1
                          ? '1 more budget needs attention'
                          : '${candidates.length - 2} more budgets need attention',
                      style: TextStyle(fontSize: AppType.t11, color: c.muted),
                    ),
                    Icon(Icons.chevron_right, size: 14, color: c.muted),
                  ],
                ),
              ),
            ),
        ],
        if (candidates.isEmpty &&
            budgets.any((b) =>
                !b.isDemo &&
                b.limit > 0 &&
                b.currency == summary.dominantCurrency)) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.check_circle_outline, size: 14, color: c.income),
              const SizedBox(width: 8),
              Text(
                'All budgets on track.',
                style: TextStyle(fontSize: AppType.t11, color: c.muted),
              ),
            ],
          ),
        ],
        if (summary.recentEntries.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'RECENT',
            style: TextStyle(
              fontSize: AppType.t12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.08,
              color: c.muted,
            ),
          ),
          const SizedBox(height: 8),
          ...summary.recentEntries.take(4).map((e) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _RecentTransactionRow(
                entry: e.$1,
                isIncome: (e.$1.type ?? e.$2.type) == 'income',
                currency: e.$1.currency ?? e.$2.currency ?? currency,
                onTap: onSelectEntry != null
                    ? () => onSelectEntry!(e.$2.id, e.$1.id)
                    : onSelectNote == null
                    ? null
                    : () => onSelectNote!(e.$2.id),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _amount(
    BuildContext context,
    String label,
    int minor,
    String currency,
    Color color,
  ) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: AppType.t10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.06,
            color: c.muted,
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: CountUpAmount(
            minor: minor,
            currency: currency,
            style: TextStyle(
              fontSize: AppType.t22,
              fontWeight: FontWeight.w700,
              fontFamily: c.monoFontFamily,
              color: color,
              height: 1.1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _budgetWarning(BuildContext context, Budget budget, double ratio) {
    final c = context.colors;
    final color = ratio >= 1
        ? c.destructive
        : ratio >= 0.8
        ? c.accent
        : c.income;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_categoryIcon(budget.category), size: 14, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${budget.category} budget',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppType.t12, color: c.fg),
                ),
              ),
              Text(
                '${(ratio * 100).round()}%',
                style: TextStyle(
                  fontSize: AppType.t12,
                  fontWeight: FontWeight.w600,
                  fontFamily: c.monoFontFamily,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: ratio.clamp(0.0, 1.0)),
              duration: AppMotion.duration(context, AppMotion.slow),
              curve: AppMotion.decelerate,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 5,
                backgroundColor:
                    ratio >= 1 ? c.destructive.withAlpha(40) : c.border,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -- Period Selector ---------------------------------------------------------

class _ScopeSelector extends StatelessWidget {
  final String period;
  final ValueChanged<String> onPeriodChanged;
  final String currencyScope;
  final List<String> currencyOptions;
  final ValueChanged<String>? onCurrencyChanged;

  const _ScopeSelector({
    required this.period,
    required this.onPeriodChanged,
    required this.currencyScope,
    required this.currencyOptions,
    this.onCurrencyChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(
          child: _PeriodSelector(
            period: period,
            onChanged: onPeriodChanged,
          ),
        ),
        if (currencyOptions.length > 1 && onCurrencyChanged != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: Border.all(color: c.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: currencyOptions.contains(currencyScope)
                    ? currencyScope
                    : 'all',
                isDense: true,
                icon: Icon(Icons.expand_more, size: 16, color: c.muted),
                style: TextStyle(fontSize: AppType.t12, color: c.fg),
                onChanged: (value) {
                  if (value != null) onCurrencyChanged!(value);
                },
                items: currencyOptions
                    .map(
                      (currency) => DropdownMenuItem(
                        value: currency,
                        child: Text(currency == 'all' ? 'All currencies' : currency),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
      ],
    );
  }
}

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
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? context.colors.accentDim : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: Text(
                _labels[p] ?? p,
                style: TextStyle(
                  fontSize: AppType.t12,
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
  final String period;

  const _ExpandableSummaryCards({
    required this.summary,
    required this.currencySymbol,
    required this.period,
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
    ('kept', 'Money Kept'),
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
                amount: summary.hasMixedCurrencies ? null : summary.totalIncome,
                amountsByCurrency: summary.hasMixedCurrencies
                    ? _dominantFirst(
                        summary.incomeByCurrency,
                        summary.dominantCurrency,
                      )
                    : null,
                color: context.colors.income,
                currency: summary.dominantCurrency,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _SummaryCard(
                label: 'EXPENSES',
                amount: summary.hasMixedCurrencies
                    ? null
                    : summary.totalExpense,
                amountsByCurrency: summary.hasMixedCurrencies
                    ? _dominantFirst(
                        summary.expenseByCurrency,
                        summary.dominantCurrency,
                      )
                    : null,
                color: context.colors.destructive,
                currency: summary.dominantCurrency,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildDeltaRow(context),
        _buildSelectorRow(context),
        if (_selectedStat != null) ...[
          const SizedBox(height: 8),
          _buildExtraCard(context),
        ],
      ],
    );
  }

  /// Comparison against the equivalent previous calendar period. Hidden
  /// unless there is previous-period data (the summary reports none for the
  /// "All" scope, so there is nothing to compare against there).
  Widget _buildDeltaRow(BuildContext context) {
    return _DeltaRow(summary: widget.summary, period: widget.period);
  }

  Widget _buildSelectorRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: PopupMenuButton<String>(
            onSelected: (value) => setState(() => _selectedStat = value),
            itemBuilder: (context) => _options
                .map((o) => PopupMenuItem(value: o.$1, child: Text(o.$2)))
                .toList(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Row(
                children: [
                  Text(
                    _dropdownLabel,
                    style: TextStyle(
                      fontSize: AppType.t12,
                      color: context.colors.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 18,
                    color: context.colors.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_selectedStat != null) ...[
          const SizedBox(width: 4),
          InkWell(
            onTap: () => setState(() => _selectedStat = null),
            borderRadius: BorderRadius.circular(AppRadius.chip),
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
          amount: summary.hasMixedCurrencies ? null : summary.net,
          amountsByCurrency: summary.hasMixedCurrencies
              ? _dominantFirst(summary.netByCurrency, summary.dominantCurrency)
              : null,
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
        final others = {
          ...summary.incomeByCurrency.keys,
          ...summary.expenseByCurrency.keys,
        }..remove(summary.dominantCurrency);
        final othersList = others.toList()..sort();
        return _SummaryCard(
          label: 'AVG DAILY SPEND',
          amount: summary.averageAvailable
              ? summary.averageDailySpend.round()
              : null,
          valueText: summary.averageAvailable ? null : 'Not available',
          footnote: summary.averageAvailable && othersList.isNotEmpty
              ? 'excl. ${othersList.join(' · ')}'
              : null,
          color: context.colors.accent,
          currency: summary.dominantCurrency,
        );
      case 'kept':
        return _moneyKeptCard(context, summary);
      default:
        return const SizedBox.shrink();
    }
  }
}

class _DeltaRow extends StatelessWidget {
  final FinanceSummary summary;
  final String period;

  const _DeltaRow({required this.summary, required this.period});

  @override
  Widget build(BuildContext context) {
    final prevExpense = summary.previousPeriodExpense;
    final prevIncome = summary.previousPeriodIncome;
    if (prevExpense <= 0 && prevIncome <= 0) return const SizedBox.shrink();
    final periodLabel = switch (period) {
      'week' => 'last week',
      'month' => 'last month',
      'year' => 'last year',
      _ => '',
    };
    if (periodLabel.isEmpty) return const SizedBox.shrink();
    final c = context.colors;

    Widget chip(String label, int current, int previous, Color upColor, Color downColor) {
      if (previous <= 0) return const Expanded(child: SizedBox.shrink());
      final change = (current - previous) / previous * 100;
      final up = change >= 0;
      final color = up ? upColor : downColor;
      final magnitude = change.abs() >= 99.5 ? '100+' : '${change.abs().round()}';
      return Expanded(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              up ? Icons.trending_up : Icons.trending_down,
              size: 13,
              color: color,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                up
                    ? '$label up $magnitude% from $periodLabel'
                    : '$label down $magnitude% from $periodLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppType.t11, color: c.muted),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          chip(
            'Spending',
            summary.totalExpense,
            prevExpense,
            c.destructive,
            c.income,
          ),
          const SizedBox(width: 12),
          chip(
            'Income',
            summary.totalIncome,
            prevIncome,
            c.income,
            c.destructive,
          ),
        ],
      ),
    );
  }
}

// -- Summary Card ------------------------------------------------------------

/// Insertion-ordered copy of [values] with [dominant] first (when present),
/// remaining codes alphabetical. Dart map literals preserve insertion order.
Map<String, int> _dominantFirst(Map<String, int> values, String dominant) {
  final sorted = <String, int>{};
  if (values.containsKey(dominant)) sorted[dominant] = values[dominant]!;
  final rest = values.keys.where((k) => k != dominant).toList()..sort();
  for (final k in rest) {
    sorted[k] = values[k]!;
  }
  return sorted;
}

/// "Money Kept" savings-rate card: net as a percentage of income, dominant
/// currency only (never sums across currencies). Footnote carries the exact
/// amounts via currencySpan. Income <= 0 renders the same 'Not available'
/// pattern as the avg-daily card.
Widget _moneyKeptCard(BuildContext context, FinanceSummary summary) {
  final c = context.colors;
  final income = summary.totalIncome;
  if (income <= 0) {
    return _SummaryCard(
      label: 'MONEY KEPT',
      valueText: 'Not available',
      color: c.muted,
    );
  }
  final pct = (summary.net / income * 100).round();
  final footStyle = TextStyle(fontSize: AppType.t10, color: c.muted);
  final others = {
    ...summary.incomeByCurrency.keys,
    ...summary.expenseByCurrency.keys,
  }..remove(summary.dominantCurrency);
  final othersList = others.toList()..sort();
  return _SummaryCard(
    label: 'MONEY KEPT',
    valueText: '$pct%',
    color: summary.net >= 0 ? c.income : c.destructive,
    footnoteSpan: TextSpan(
      style: footStyle,
      children: [
        currencySpan(summary.dominantCurrency, footStyle),
        TextSpan(text: formatMinor(summary.net, summary.dominantCurrency)),
        const TextSpan(text: ' of '),
        currencySpan(summary.dominantCurrency, footStyle),
        TextSpan(text: formatMinor(income, summary.dominantCurrency)),
        const TextSpan(text: ' income'),
        if (othersList.isNotEmpty)
          TextSpan(text: ' · excl. ${othersList.join(' · ')}'),
      ],
    ),
  );
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final int? amount;
  final String? count;
  final Color color;
  final String? currency;
  final IconData? icon;
  final String? valueText;
  final Map<String, int>? amountsByCurrency;
  final String? footnote;
  final InlineSpan? footnoteSpan;

  const _SummaryCard({
    required this.label,
    this.amount,
    this.count,
    required this.color,
    this.currency,
    this.icon,
    this.valueText,
    this.amountsByCurrency,
    this.footnote,
    this.footnoteSpan,
  });

  @override
  Widget build(BuildContext context) {
    final valueStyle = TextStyle(
      fontSize: AppType.t22,
      fontWeight: FontWeight.w700,
      color: color,
      fontFamily: context.colors.monoFontFamily,
      height: 1.1,
    );

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(AppRadius.card),
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
                    fontSize: AppType.t10,
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
                ? CountUpAmount(
                    minor: amount!,
                    currency: currency,
                    style: valueStyle,
                  )
                : (amountsByCurrency != null && amountsByCurrency!.isNotEmpty)
                      ? _buildStackedAmounts(context, amountsByCurrency!)
                      : Text(valueText ?? count ?? '', style: valueStyle),
          ),
          if (footnoteSpan != null) ...[
            const SizedBox(height: 2),
            Text.rich(
              footnoteSpan!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ] else if (footnote != null) ...[
            const SizedBox(height: 2),
            Text(
              footnote!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppType.t10, color: context.colors.muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStackedAmounts(BuildContext context, Map<String, int> values) {
    final lineStyle = TextStyle(
      fontSize: AppType.t15,
      fontWeight: FontWeight.w700,
      color: color,
      fontFamily: context.colors.monoFontFamily,
      height: 1.25,
    );
    final shown = values.entries.take(3).toList();
    final extra = values.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in shown)
          Text.rich(
            TextSpan(
              style: lineStyle,
              children: [
                currencySpan(e.key, lineStyle),
                TextSpan(text: formatMinor(e.value, e.key)),
              ],
            ),
            maxLines: 1,
          ),
        if (extra > 0)
          Text(
            '+$extra more',
            style: TextStyle(fontSize: AppType.t10, color: context.colors.muted),
          ),
      ],
    );
  }
}

// -- Category Card -----------------------------------------------------------

IconData _categoryIcon(String category) {
  switch (category.toLowerCase()) {
    case 'food':
    case 'food & drink':
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

List<Widget> _categoryRows(BuildContext context, FinanceSummary summary, {int? limit}) {
  final totalSpending = summary.categories.fold(
    0,
    (int sum, e) => sum + e.value,
  );
  return summary.categories.take(limit ?? summary.categories.length).map((e) {
    final fraction = totalSpending > 0 ? e.value / totalSpending : 0.0;
    final pct = (fraction * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: fraction),
                    duration: AppMotion.duration(context, AppMotion.slow),
                    curve: AppMotion.decelerate,
                    builder: (context, value, _) => FractionallySizedBox(
                      widthFactor: value.clamp(0.0, 1.0),
                      child: Container(color: context.colors.accent.withAlpha(22)),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      _categoryIcon(e.key),
                      size: 14,
                      color: context.colors.accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.key,
                        style: TextStyle(fontSize: AppType.t12, color: context.colors.fg),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '$pct%',
                      style: TextStyle(
                        fontSize: AppType.t11,
                        fontFamily: context.colors.monoFontFamily,
                        color: context.colors.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text.rich(
                      TextSpan(
                        style: TextStyle(
                          fontSize: AppType.t11,
                          fontFamily: context.colors.monoFontFamily,
                          fontWeight: FontWeight.w600,
                          color: context.colors.fg,
                        ),
                        children: [
                          currencySpan(
                            summary.dominantCurrency,
                            TextStyle(
                              fontSize: AppType.t11,
                              fontFamily: context.colors.monoFontFamily,
                              fontWeight: FontWeight.w600,
                              color: context.colors.fg,
                            ),
                          ),
                          TextSpan(
                            text: formatMinor(
                              e.value,
                              summary.dominantCurrency,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }).toList();
}

List<Budget> _visibleBudgets(List<Budget> budgets, String currencyScope) {
  if (currencyScope == 'all') return budgets;
  return budgets.where((b) => b.currency == currencyScope).toList();
}

// -- Budget Card -------------------------------------------------------------

class _BudgetCard extends StatelessWidget {
  final Budget budget;
  final int actual;
  final String currency;
  final String period;
  final String? currencyLabel;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  const _BudgetCard({
    required this.budget,
    required this.actual,
    required this.currency,
    required this.period,
    this.currencyLabel,
    this.onEdit,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = budget.limit > 0 ? actual / budget.limit : 0.0;
    final fraction = ratio.clamp(0.0, 1.0);
    final overBudget = actual > budget.limit;
    final pct = ratio >= 9.995 ? 999 : (ratio * 100).round();
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
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_categoryIcon(budget.category), size: 16, color: barColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  budget.category,
                  style: TextStyle(
                    fontSize: AppType.t13_5,
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
                  fontSize: AppType.t12,
                  fontWeight: FontWeight.w600,
                  color: barColor,
                  fontFamily: context.colors.monoFontFamily,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                (currencyLabel == null ? '' : '$currencyLabel · ') +
                    (period == 'month'
                        ? 'Monthly'
                        : '${period[0].toUpperCase()}${period.substring(1)}'),
                style: TextStyle(fontSize: AppType.t10, color: context.colors.muted),
              ),
              if (onEdit != null)
                _BudgetAction(
                  icon: Icons.edit_outlined,
                  tooltip: 'Edit budget',
                  onPressed: onEdit!,
                ),
              if (onRemove != null)
                _BudgetAction(
                  icon: Icons.delete_outline,
                  tooltip: 'Delete budget',
                  onPressed: onRemove!,
                  color: context.colors.destructive,
                ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: fraction),
              duration: AppMotion.duration(context, AppMotion.slow),
              curve: AppMotion.decelerate,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 6,
                backgroundColor: overBudget
                    ? context.colors.destructive.withAlpha(40)
                    : context.colors.border,
                valueColor: AlwaysStoppedAnimation(barColor),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: AppType.t11,
                    fontFamily: context.colors.monoFontFamily,
                    fontWeight: FontWeight.w500,
                    color: context.colors.muted,
                  ),
                  children: [
                    const TextSpan(text: 'Spent '),
                    currencySpan(
                      currency,
                      TextStyle(
                        fontSize: AppType.t11,
                        fontFamily: context.colors.monoFontFamily,
                        fontWeight: FontWeight.w500,
                        color: context.colors.muted,
                      ),
                    ),
                    TextSpan(
                      text: formatMinor(
                        actual,
                        currency,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (overBudget)
                Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: AppType.t11,
                      fontFamily: context.colors.monoFontFamily,
                      fontWeight: FontWeight.w600,
                      color: context.colors.destructive,
                    ),
                    children: [
                      currencySpan(
                        currency,
                        TextStyle(
                          fontSize: AppType.t11,
                          fontFamily: context.colors.monoFontFamily,
                          fontWeight: FontWeight.w600,
                          color: context.colors.destructive,
                        ),
                      ),
                      TextSpan(
                        text: formatMinor(
                          remaining.abs(),
                          currency,
                        ),
                      ),
                      const TextSpan(text: ' over budget'),
                    ],
                  ),
                )
              else
                Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: AppType.t11,
                      fontFamily: context.colors.monoFontFamily,
                      fontWeight: FontWeight.w500,
                      color: context.colors.income,
                    ),
                    children: [
                      currencySpan(
                        currency,
                        TextStyle(
                          fontSize: AppType.t11,
                          fontFamily: context.colors.monoFontFamily,
                          fontWeight: FontWeight.w500,
                          color: context.colors.income,
                        ),
                      ),
                      TextSpan(
                        text: formatMinor(
                          remaining,
                          currency,
                        ),
                      ),
                      const TextSpan(text: ' left to spend'),
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

class _BudgetAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  const _BudgetAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 15, color: color ?? context.colors.muted),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    );
  }
}

// -- Recent Transaction Row --------------------------------------------------

class _RecentTransactionRow extends StatelessWidget {
  final MoneyEntry entry;
  final bool isIncome;
  final String currency;
  final VoidCallback? onTap;

  const _RecentTransactionRow({
    required this.entry,
    required this.isIncome,
    required this.currency,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final date = relativeDayLabel(entry.date);
    final amountColor = isIncome ? context.colors.income : context.colors.fg;
    final description = entry.note != null && entry.note!.isNotEmpty
        ? entry.note!
        : null;

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Icon(
            _categoryIcon(entry.category),
            size: 18,
            color: context.colors.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description ?? entry.category,
                  style: TextStyle(
                    fontSize: AppType.t13_5,
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
                        fontSize: AppType.t11,
                        color: context.colors.muted,
                      ),
                    ),
                    Text(
                      ' · ',
                      style: TextStyle(
                        fontSize: AppType.t11,
                        color: context.colors.muted,
                      ),
                    ),
                    Text(
                      date,
                      style: TextStyle(
                        fontSize: AppType.t11,
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
                  fontSize: AppType.t13_5,
                  fontFamily: context.colors.monoFontFamily,
                  fontWeight: FontWeight.w600,
                  color: amountColor,
                ),
                children: [
                  currencySpan(
                    currency,
                    TextStyle(
                      fontSize: AppType.t13_5,
                      fontFamily: context.colors.monoFontFamily,
                      fontWeight: FontWeight.w600,
                      color: amountColor,
                    ),
                  ),
                  TextSpan(
                    text: formatMinor(
                      entry.amount,
                      currency,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return onTap == null
        ? content
        : InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: content,
          );
  }

}

/// Wide desktop finance workspace: full dashboard for the editor pane when the
/// Finance tab is active and no note is open. Two columns — transactions left,
/// categories + budgets right — with all summary stats visible (no popup).
class FinanceWorkspace extends StatelessWidget {
  final FinanceSummary summary;
  final String period;
  final ValueChanged<String> onPeriodChanged;
  final String Function(String?) currencySymbol;
  final String currencyScope;
  final List<String> currencyOptions;
  final ValueChanged<String>? onCurrencyChanged;
  final List<Budget> budgets;
  final Map<String, int> budgetActuals;
  final void Function(Budget)? onAddBudget;
  final void Function(Budget)? onRemoveBudget;
  final void Function(String)? onSelectNote;
  final void Function(String noteId, String entryId)? onSelectEntry;
  final VoidCallback? onAddExpense;
  final VoidCallback? onAddIncome;
  final List<int> dailyTotals;

  const FinanceWorkspace({
    super.key,
    required this.summary,
    required this.period,
    required this.onPeriodChanged,
    required this.currencySymbol,
    required this.currencyScope,
    required this.currencyOptions,
    this.onCurrencyChanged,
    this.budgets = const [],
    this.budgetActuals = const {},
    this.onAddBudget,
    this.onRemoveBudget,
    this.onSelectNote,
    this.onSelectEntry,
    this.onAddExpense,
    this.onAddIncome,
    this.dailyTotals = const [],
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      color: c.listBg,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            children: [
              _ScopeSelector(
                period: period,
                onPeriodChanged: onPeriodChanged,
                currencyScope: currencyScope,
                currencyOptions: currencyOptions,
                onCurrencyChanged: onCurrencyChanged,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _incomeCard(context)),
                  const SizedBox(width: 8),
                  Expanded(child: _expenseCard(context)),
                  const SizedBox(width: 8),
                  Expanded(child: _netCard(context)),
                ],
              ),
              _DeltaRow(summary: summary, period: period),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (onAddExpense != null)
                    OutlinedButton.icon(
                      onPressed: onAddExpense,
                      icon: const Icon(Icons.arrow_downward, size: 15),
                      label: const Text('Expense'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.destructive,
                        side: BorderSide(color: c.border),
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.s12,
                          horizontal: AppSpacing.s16,
                        ),
                      ),
                    ),
                  if (onAddExpense != null && onAddIncome != null)
                    const SizedBox(width: 8),
                  if (onAddIncome != null)
                    OutlinedButton.icon(
                      onPressed: onAddIncome,
                      icon: const Icon(Icons.arrow_upward, size: 15),
                      label: const Text('Income'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.income,
                        side: BorderSide(color: c.border),
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.s12,
                          horizontal: AppSpacing.s16,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      label: 'TRANSACTIONS',
                      count: '${summary.entryCount}',
                      color: c.accent,
                      icon: Icons.receipt_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _moneyKeptCard(context, summary)),
                  const SizedBox(width: 8),
                  Expanded(child: _avgCard(context)),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: dailyTotals.length == 14
                        ? SpendSparkline(
                            dailyTotals: dailyTotals,
                            currency: summary.dominantCurrency,
                          )
                        : _SummaryCard(
                            label: 'LAST 14 DAYS',
                            valueText: 'Not available',
                            color: c.muted,
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: _transactionsColumn(context)),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: _rightColumn(context)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _incomeCard(BuildContext context) => _SummaryCard(
        label: 'INCOME',
        amount: summary.hasMixedCurrencies ? null : summary.totalIncome,
        amountsByCurrency: summary.hasMixedCurrencies
            ? _dominantFirst(summary.incomeByCurrency, summary.dominantCurrency)
            : null,
        color: context.colors.income,
        currency: summary.dominantCurrency,
      );

  Widget _expenseCard(BuildContext context) => _SummaryCard(
        label: 'EXPENSES',
        amount: summary.hasMixedCurrencies ? null : summary.totalExpense,
        amountsByCurrency: summary.hasMixedCurrencies
            ? _dominantFirst(summary.expenseByCurrency, summary.dominantCurrency)
            : null,
        color: context.colors.destructive,
        currency: summary.dominantCurrency,
      );

  Widget _netCard(BuildContext context) => _SummaryCard(
        label: 'NET',
        amount: summary.hasMixedCurrencies ? null : summary.net,
        amountsByCurrency: summary.hasMixedCurrencies
            ? _dominantFirst(summary.netByCurrency, summary.dominantCurrency)
            : null,
        color: summary.net >= 0
            ? context.colors.income
            : context.colors.destructive,
        currency: summary.dominantCurrency,
      );

  Widget _avgCard(BuildContext context) {
    final others = {
      ...summary.incomeByCurrency.keys,
      ...summary.expenseByCurrency.keys,
    }..remove(summary.dominantCurrency);
    final othersList = others.toList()..sort();
    return _SummaryCard(
      label: 'AVG DAILY SPEND',
      amount: summary.averageAvailable ? summary.averageDailySpend.round() : null,
      valueText: summary.averageAvailable ? null : 'Not available',
      footnote: summary.averageAvailable && othersList.isNotEmpty
          ? 'excl. ${othersList.join(' · ')}'
          : null,
      color: context.colors.accent,
      currency: summary.dominantCurrency,
    );
  }

  Widget _transactionsColumn(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'ALL TRANSACTIONS',
          style: TextStyle(
            fontSize: AppType.t12,
            fontWeight: FontWeight.w500,
            color: context.colors.muted,
            letterSpacing: 0.08,
          ),
        ),
        const SizedBox(height: 8),
        if (summary.recentEntries.isEmpty)
          Text(
            'No transactions in this period.',
            style: TextStyle(
              fontSize: AppType.t13_5,
              color: context.colors.muted,
            ),
          )
        else
          ...summary.recentEntries.map((e) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _RecentTransactionRow(
                entry: e.$1,
                isIncome: (e.$1.type ?? e.$2.type) == 'income',
                currency:
                    e.$1.currency ?? e.$2.currency ?? summary.dominantCurrency,
                onTap: onSelectEntry != null
                    ? () => onSelectEntry!(e.$2.id, e.$1.id)
                    : onSelectNote == null
                    ? null
                    : () => onSelectNote!(e.$2.id),
              ),
            );
          }),
      ],
    );
  }

  Widget _rightColumn(BuildContext context) {
    final visible = _visibleBudgets(budgets, currencyScope);
    final mixedBudgetCurrencies = budgets.map((b) => b.currency).toSet().length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'TOP SPENDING CATEGORIES',
          style: TextStyle(
            fontSize: AppType.t12,
            fontWeight: FontWeight.w500,
            color: context.colors.muted,
            letterSpacing: 0.08,
          ),
        ),
        const SizedBox(height: 8),
        if (summary.categories.isEmpty)
          Text(
            'No spending in this period.',
            style: TextStyle(fontSize: AppType.t12, color: context.colors.muted),
          )
        else
          Column(children: _categoryRows(context, summary)),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                'BUDGETS',
                style: TextStyle(
                  fontSize: AppType.t12,
                  fontWeight: FontWeight.w500,
                  color: context.colors.muted,
                  letterSpacing: 0.08,
                ),
              ),
            ),
            if (onAddBudget != null)
              TextButton.icon(
                onPressed: () => _openBudgetSheet(context),
                icon: const Icon(Icons.add, size: 15),
                label: const Text('Add budget'),
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  textStyle: const TextStyle(fontSize: AppType.t12),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (onAddBudget == null)
          const SizedBox.shrink()
        else if (budgets.isEmpty)
          Text(
            'No budgets yet. Add one to track spending against a limit.',
            style: TextStyle(fontSize: AppType.t12, color: context.colors.muted),
          )
        else if (visible.isEmpty)
          Text(
            'No $currencyScope budgets yet.',
            style: TextStyle(fontSize: AppType.t12, color: context.colors.muted),
          )
        else
          ...visible.map((b) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _BudgetCard(
                budget: b,
                actual: budgetActuals[b.id] ?? 0,
                currency: b.currency,
                period: b.period,
                currencyLabel: mixedBudgetCurrencies ? b.currency : null,
                onEdit: () => _openBudgetSheet(context, b),
                onRemove: onRemoveBudget != null ? () => onRemoveBudget!(b) : null,
              ),
            );
          }),
      ],
    );
  }

  void _openBudgetSheet(BuildContext context, [Budget? budget]) {
    final cats = summary.categories.map((e) => e.key).toList();
    BudgetSheet.show(
      context,
      budget: budget,
      existingCategories: cats,
      currencySymbol: currencySymbol(summary.dominantCurrency),
      currencyCode: budget?.currency ?? summary.dominantCurrency,
      budgetPeriod: budget?.period ?? period,
      onSave: onAddBudget!,
    );
  }
}
