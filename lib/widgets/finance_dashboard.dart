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
import 'home_modules.dart';
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

  /// True when the user has at least one transaction in ANY period. Distinguishes
  /// "brand new" from "nothing in this period" so the dashboard shows one empty
  /// state instead of five.
  final bool hasAnyEntries;
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
    this.hasAnyEntries = true,
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
        currency:
            (incomeByCurrency[currency] ?? 0) -
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
        const HomeLabel('RECENT'),
        _buildRecentTransactions(context),
        if (widget.summary.categories.isNotEmpty) ...[
          const SizedBox(height: 22),
          const HomeLabel('TOP CATEGORIES'),
          _buildCompactCategories(context),
        ],
        if (widget.dailyTotals.length == 14) ...[
          const SizedBox(height: 24),
          SpendSparkline(
            dailyTotals: widget.dailyTotals,
            currency: widget.summary.dominantCurrency,
          ),
        ],
        const SizedBox(height: 22),
        _buildBudgetHeader(context),
        _buildBudgetSection(context),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildCompactCategories(BuildContext context) {
    if (widget.summary.categories.isEmpty) return const SizedBox.shrink();
    return Column(children: _categoryRows(context, widget.summary, limit: 4));
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
    return HomeLabel(
      'BUDGETS',
      trailing: widget.onAddBudget == null ? null : 'Add budget',
      trailingIcon: false,
      onTrailingTap: widget.onAddBudget == null
          ? null
          : () => _openBudgetSheet(context),
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

  Widget _txnRow((MoneyEntry, Note) e) {
    return _RecentTransactionRow(
      flat: true,
      entry: e.$1,
      isIncome: (e.$1.type ?? e.$2.type) == 'income',
      currency:
          e.$1.currency ?? e.$2.currency ?? widget.summary.dominantCurrency,
      onTap: widget.onSelectEntry != null
          ? () => widget.onSelectEntry!(e.$2.id, e.$1.id)
          : widget.onSelectNote == null
          ? null
          : () => widget.onSelectNote!(e.$2.id),
    );
  }

  Widget _buildRecentTransactions(BuildContext context) {
    if (widget.summary.recentEntries.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'No transactions in this period.',
            style: TextStyle(
              fontSize: AppType.t13_5,
              color: context.colors.muted,
            ),
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

    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: 58,
                    endIndent: 16,
                    color: c.border.withValues(alpha: 0.8),
                  ),
                _txnRow(entries[i]),
              ],
            ],
          ),
        ),
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
    return _QuietChoice(
      value: mode,
      onChanged: onChanged,
      options: const {'simple': 'Simple', 'advanced': 'Advanced'},
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

  /// Which period the summary reflects. The label is derived from it, so the card
  /// never claims a scope it is not showing.
  final String period;

  /// When non-null, renders the Day / Week / Month / All filter. Callers that do not
  /// offer a scope (desktop, tests, legacy mounts) get the previous single-scope card.
  final ValueChanged<String>? onPeriodChanged;

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
    this.period = 'month',
    this.onPeriodChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mixed = summary.hasMixedCurrencies;
    final currency = summary.dominantCurrency;
    final net = summary.net;
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
    final hasBudgets = budgets.any(
      (b) => !b.isDemo && b.limit > 0 && b.currency == summary.dominantCurrency,
    );

    final recent = summary.recentEntries.take(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onPeriodChanged != null) ...[
          _QuietChoice(
            value: period,
            onChanged: onPeriodChanged!,
            options: const {
              'day': 'Day',
              'week': 'Week',
              'month': 'Month',
              'all': 'All',
            },
          ),
          const SizedBox(height: 4),
        ],
        HomeLabel(
          periodName(period).toUpperCase(),
          trailing: mixed ? 'Primary currency' : null,
        ),
        HomeCard(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: _spentBlock(context, currency, net, keptPct),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _AddButton(
                label: 'Expense',
                icon: Icons.remove_rounded,
                primary: true,
                onPressed: onAddExpense,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _AddButton(
                label: 'Income',
                icon: Icons.add_rounded,
                onPressed: onAddIncome,
              ),
            ),
          ],
        ),
        if (candidates.isNotEmpty || hasBudgets) ...[
          const SizedBox(height: 22),
          const HomeLabel('BUDGETS'),
          HomeCard(
            padding: EdgeInsets.zero,
            child: candidates.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                    child: Row(
                      children: [
                        Icon(Icons.check_rounded, size: 16, color: c.muted),
                        const SizedBox(width: 10),
                        Text(
                          'All budgets on track.',
                          style: TextStyle(fontSize: 13, color: c.fg),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < candidates.length && i < 2; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            indent: 18,
                            endIndent: 18,
                            color: c.border.withValues(alpha: 0.8),
                          ),
                        _budgetRow(context, candidates[i].$1, candidates[i].$2),
                      ],
                      if (candidates.length > 2) ...[
                        Divider(
                          height: 1,
                          color: c.border.withValues(alpha: 0.8),
                        ),
                        InkWell(
                          onTap: onOpenAdvanced,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    candidates.length - 2 == 1
                                        ? '1 more budget needs attention'
                                        : '${candidates.length - 2} more budgets need attention',
                                    style: TextStyle(
                                      fontSize: AppType.t12,
                                      color: c.muted,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 14,
                                  color: c.muted,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 22),
          HomeLabel(
            'RECENT',
            trailing: onOpenAdvanced == null ? null : 'See all',
            onTrailingTap: onOpenAdvanced,
            trailingSemantics: 'Open the full finance view',
          ),
          HomeCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < recent.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 58,
                      endIndent: 16,
                      color: c.border.withValues(alpha: 0.8),
                    ),
                  _RecentTransactionRow(
                    flat: true,
                    entry: recent[i].$1,
                    isIncome:
                        (recent[i].$1.type ?? recent[i].$2.type) == 'income',
                    currency:
                        recent[i].$1.currency ??
                        recent[i].$2.currency ??
                        currency,
                    onTap: onSelectEntry != null
                        ? () => onSelectEntry!(recent[i].$2.id, recent[i].$1.id)
                        : onSelectNote == null
                        ? null
                        : () => onSelectNote!(recent[i].$2.id),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// One number in ink — what went out — with income and what's left as a
  /// quiet line under it. Colour stays a small cue, never the headline.
  Widget _spentBlock(
    BuildContext context,
    String currency,
    int net,
    int? keptPct,
  ) {
    final c = context.colors;
    final quiet = TextStyle(fontSize: 13, color: c.muted);
    final quietAmount = quiet.copyWith(
      color: c.fg,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final spentRatio = summary.totalIncome > 0
        ? (summary.totalExpense / summary.totalIncome).clamp(0.0, 1.0)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Spent', style: quiet),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: CountUpAmount(
            minor: summary.totalExpense,
            currency: currency,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              height: 1.15,
              color: c.fg,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        if (spentRatio != null) ...[
          const SizedBox(height: 14),
          // How much of what came in has gone out. Ink on a hairline track;
          // it only turns red once spending passes income.
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: spentRatio),
              duration: AppMotion.duration(context, AppMotion.slow),
              curve: AppMotion.decelerate,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 4,
                backgroundColor: c.border.withValues(alpha: 0.8),
                valueColor: AlwaysStoppedAnimation(
                  net < 0 ? c.destructive : c.fg.withValues(alpha: 0.75),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: quiet,
                  children: [
                    const TextSpan(text: 'Income  '),
                    ...moneySpans(summary.totalIncome, currency, quietAmount),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            if (keptPct != null && net >= 0)
              Text('You kept $keptPct%', style: quietAmount)
            else ...[
              Text('Net', style: quiet),
              const SizedBox(width: 6),
              Text.rich(
                TextSpan(
                  style: quietAmount.copyWith(
                    color: net < 0 ? c.destructive : c.fg,
                  ),
                  children: moneySpans(
                    net,
                    currency,
                    quietAmount.copyWith(color: net < 0 ? c.destructive : c.fg),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _budgetRow(BuildContext context, Budget budget, double ratio) {
    final c = context.colors;
    final over = ratio >= 1;
    final tone = over ? c.destructive : c.fg;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_categoryIcon(budget.category), size: 16, color: c.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${budget.category} budget',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppType.t13_5, color: c.fg),
                ),
              ),
              Text(
                over ? 'Over' : '${(ratio * 100).round()}%',
                style: TextStyle(
                  fontSize: AppType.t12,
                  fontWeight: FontWeight.w600,
                  color: over ? c.destructive : c.muted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: ratio.clamp(0.0, 1.0)),
              duration: AppMotion.duration(context, AppMotion.slow),
              curve: AppMotion.decelerate,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 4,
                backgroundColor: c.border.withValues(alpha: 0.8),
                valueColor: AlwaysStoppedAnimation(
                  over ? tone : c.fg.withValues(alpha: 0.75),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The two capture keys under the summary. Expense — the common case — is a
/// solid ink key; Income is its outlined twin. No red/green: the icon and
/// the word carry the meaning.
class _AddButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback? onPressed;

  const _AddButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: primary
          ? BorderSide.none
          : BorderSide(color: c.border.withValues(alpha: 0.8)),
    );
    final fg = primary ? c.bg : c.fg;
    return Material(
      color: primary ? c.fg : c.surface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          height: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A quiet single-choice row: plain words, the chosen one in ink on a soft
/// pill. Replaces the boxed segmented controls on the calm surfaces.
class _QuietChoice extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final Map<String, String> options;

  const _QuietChoice({
    required this.value,
    required this.onChanged,
    required this.options,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final e in options.entries)
          Semantics(
            button: true,
            selected: e.key == value,
            child: InkWell(
              onTap: () => onChanged(e.key),
              borderRadius: BorderRadius.circular(18),
              child: AnimatedContainer(
                duration: AppMotion.duration(context, AppMotion.base),
                curve: AppMotion.decelerate,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: e.key == value
                      ? c.fg.withValues(alpha: 0.07)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  e.value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: e.key == value
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: e.key == value ? c.fg : c.muted,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// -- Period Selector ---------------------------------------------------------

/// Period chips on the left, currency picker as plain text on the right.
/// Phone and desktop share it, so the scope reads the same everywhere.
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
          child: _QuietChoice(
            value: period,
            onChanged: onPeriodChanged,
            options: const {
              'all': 'All',
              'week': 'Week',
              'month': 'Month',
              'year': 'Year',
            },
          ),
        ),
        if (currencyOptions.length > 1 && onCurrencyChanged != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
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
                        child: Text(
                          currency == 'all' ? 'All currencies' : currency,
                        ),
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
                label: 'Income',
                amount: summary.hasMixedCurrencies ? null : summary.totalIncome,
                amountsByCurrency: summary.hasMixedCurrencies
                    ? _dominantFirst(
                        summary.incomeByCurrency,
                        summary.dominantCurrency,
                      )
                    : null,
                // Ink figures; the labels say which is which.
                color: context.colors.fg,
                currency: summary.dominantCurrency,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SummaryCard(
                label: 'Expenses',
                amount: summary.hasMixedCurrencies
                    ? null
                    : summary.totalExpense,
                amountsByCurrency: summary.hasMixedCurrencies
                    ? _dominantFirst(
                        summary.expenseByCurrency,
                        summary.dominantCurrency,
                      )
                    : null,
                color: context.colors.fg,
                currency: summary.dominantCurrency,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
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
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: context.colors.border.withValues(alpha: 0.8),
                ),
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
        final netColor = summary.net > 0
            ? context.colors.income
            : summary.net < 0
            ? context.colors.destructive
            : context.colors.muted;
        return _SummaryCard(
          label: 'Net',
          amount: summary.hasMixedCurrencies ? null : summary.net,
          amountsByCurrency: summary.hasMixedCurrencies
              ? _dominantFirst(summary.netByCurrency, summary.dominantCurrency)
              : null,
          color: netColor,
          currency: summary.dominantCurrency,
        );
      case 'txn_count':
        return _SummaryCard(
          label: 'Transactions',
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
          label: 'Avg daily spend',
          amount: summary.averageAvailable
              ? summary.averageDailySpend.round()
              : null,
          valueText: summary.averageAvailable ? null : '\u2014',
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

    Widget chip(
      String label,
      int current,
      int previous,
      Color upColor,
      Color downColor,
    ) {
      if (previous <= 0) return const Expanded(child: SizedBox.shrink());
      final change = (current - previous) / previous * 100;
      final up = change >= 0;
      final color = up ? upColor : downColor;
      final magnitude = change.abs() >= 99.5
          ? '100+'
          : '${change.abs().round()}';
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

/// The hero's spending-change chip: "Spending down 38% from last month" in a
/// dim-tinted pill. Extracted from [_DeltaRow]'s chip body; the row itself stays
/// for the mobile Show-more menu.
class _DeltaChip extends StatelessWidget {
  final String label;
  final int current;
  final int previous;

  /// "last week" / "last month" / "last year"; empty hides the chip.
  final String periodLabel;

  const _DeltaChip({
    required this.label,
    required this.current,
    required this.previous,
    required this.periodLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (previous <= 0 || periodLabel.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final change = (current - previous) / previous * 100;
    final up = change >= 0;
    // Spending up is money going out (expense red); spending down is income green.
    final color = up ? c.expense : c.income;
    final magnitude = change.abs() >= 99.5 ? '100+' : '${change.abs().round()}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(36),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
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
              style: TextStyle(
                fontSize: AppType.t12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
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

/// The single style for every small dashboard label — section headings and
/// summary-card labels alike. Sentence case, so no uppercase tracking.
TextStyle _labelStyle(BuildContext context) => TextStyle(
  fontSize: AppType.t11,
  fontWeight: FontWeight.w600,
  letterSpacing: 0,
  color: context.colors.muted,
);

/// Day header for the desktop ledger's day groups: "Today · Sep 28",
/// "Yesterday · Sep 27", "Wed · Sep 24". [relativeDayLabel] decides the
/// Today/Yesterday wording; every other day gets its weekday abbreviation.
String _dayGroupLabel(DateTime d) {
  final rel = relativeDayLabel(d);
  if (rel == 'Today' || rel == 'Yesterday') return '$rel · ${dayLabel(d)}';
  return '${kWeekdayNamesShort[d.weekday - 1]} · ${dayLabel(d)}';
}

/// "Saved" savings-rate card: net as a percentage of income, dominant
/// currency only (never sums across currencies). Footnote carries the exact
/// amounts via currencySpan. Income <= 0 renders the same the em-dash placeholder
/// pattern as the avg-daily card.
Widget _moneyKeptCard(BuildContext context, FinanceSummary summary) {
  final c = context.colors;
  final income = summary.totalIncome;
  if (income <= 0) {
    return _SummaryCard(label: 'Saved', valueText: '\u2014', color: c.muted);
  }
  final pct = (summary.net / income * 100).round();
  final footStyle = TextStyle(fontSize: AppType.t10, color: c.muted);
  final others = {
    ...summary.incomeByCurrency.keys,
    ...summary.expenseByCurrency.keys,
  }..remove(summary.dominantCurrency);
  final othersList = others.toList()..sort();
  return _SummaryCard(
    label: 'Saved',
    valueText: '$pct%',
    color: summary.net > 0
        ? c.income
        : summary.net < 0
        ? c.destructive
        : c.muted,
    footnoteSpan: TextSpan(
      style: footStyle,
      children: [
        ...moneySpans(summary.net, summary.dominantCurrency, footStyle),
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

  /// Card padding. Dense mobile tiles keep the compact default; desktop cards
  /// pass the BRANDING card contract (14px 16px).
  final EdgeInsetsGeometry padding;

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
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
      padding: padding,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.colors.border.withValues(alpha: 0.8)),
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
              Expanded(child: Text(label, style: _labelStyle(context))),
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
              style: TextStyle(
                fontSize: AppType.t10,
                color: context.colors.muted,
              ),
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
              children: [...moneySpans(e.value, e.key, lineStyle)],
            ),
            maxLines: 1,
          ),
        if (extra > 0)
          Text(
            '+$extra more',
            style: TextStyle(
              fontSize: AppType.t10,
              color: context.colors.muted,
            ),
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

List<Widget> _categoryRows(
  BuildContext context,
  FinanceSummary summary, {
  int? limit,
}) {
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
                      child: Container(
                        color: context.colors.fg.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      _categoryIcon(e.key),
                      size: 14,
                      color: context.colors.muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.key,
                        style: TextStyle(
                          fontSize: AppType.t12,
                          color: context.colors.fg,
                        ),
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
      // Token contract (app_colors.dart): 80-100 % of limit is warning amber,
      // never red or green — accent here was a contract miss.
      barColor = context.colors.warning;
    } else {
      // On track is the quiet state: ink, no green.
      barColor = context.colors.fg.withValues(alpha: 0.75);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.colors.border.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _categoryIcon(budget.category),
                size: 16,
                color: context.colors.muted,
              ),
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
                style: TextStyle(
                  fontSize: AppType.t10,
                  color: context.colors.muted,
                ),
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
                ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: overBudget
                // Prototype .b-bar.over: the bar fills red, then a track-colored
                // mask covers limit/actual of it — the exposed red segment IS
                // the overshoot (E2's clamp is gone; honesty via proportion).
                ? TweenAnimationBuilder<double>(
                    tween: Tween(
                      begin: 0,
                      end: actual <= 0
                          ? 0.0
                          : (budget.limit / actual).clamp(0.0, 1.0),
                    ),
                    duration: AppMotion.duration(context, AppMotion.slow),
                    curve: AppMotion.decelerate,
                    builder: (context, mask, _) => SizedBox(
                      height: 6,
                      child: LayoutBuilder(
                        builder: (context, constraints) => Stack(
                          children: [
                            Positioned.fill(
                              child: ColoredBox(
                                color: context.colors.destructive,
                              ),
                            ),
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              width: constraints.maxWidth * mask,
                              child: ColoredBox(color: context.colors.border),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : TweenAnimationBuilder<double>(
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
                    TextSpan(text: formatMinor(actual, currency)),
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
                      TextSpan(text: formatMinor(remaining.abs(), currency)),
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
                      color: pct >= 80
                          ? context.colors.warning
                          : context.colors.muted,
                    ),
                    children: [
                      currencySpan(
                        currency,
                        TextStyle(
                          fontSize: AppType.t11,
                          fontFamily: context.colors.monoFontFamily,
                          fontWeight: FontWeight.w500,
                          color: pct >= 80
                              ? context.colors.warning
                              : context.colors.muted,
                        ),
                      ),
                      TextSpan(text: formatMinor(remaining, currency)),
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

  const _BudgetAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 15, color: context.colors.muted),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    );
  }
}

// -- Recent Transaction Row --------------------------------------------------

class _RecentTransactionRow extends StatefulWidget {
  final MoneyEntry entry;
  final bool isIncome;
  final String currency;
  final VoidCallback? onTap;

  /// Parent note title shown after the category in the subtitle (desktop
  /// ledger, where the day header already carries the date). Null keeps the
  /// relative-date suffix (mobile).
  final String? noteTitle;

  /// Desktop only: trailing pencil chip that highlights on hover.
  final bool showEditAffordance;

  /// A divider row inside a shared card (Simple view) instead of a
  /// standalone tile.
  final bool flat;

  const _RecentTransactionRow({
    required this.entry,
    required this.isIncome,
    required this.currency,
    this.onTap,
    this.noteTitle,
    this.showEditAffordance = false,
    this.flat = false,
  });

  @override
  State<_RecentTransactionRow> createState() => _RecentTransactionRowState();
}

class _RecentTransactionRowState extends State<_RecentTransactionRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final date = relativeDayLabel(widget.entry.date);
    // Prototype: expense amounts are expense-red, income green (color is the
    // secondary cue; the −/+ sign is the primary one, 05-D1).
    // Outgoing money reads in ink; only income carries a colour, and the
    // −/+ sign is the primary cue either way.
    final amountColor = widget.isIncome ? c.income : c.fg;
    final description =
        widget.entry.note != null && widget.entry.note!.isNotEmpty
        ? widget.entry.note!
        : null;
    final amountStyle = TextStyle(
      fontSize: AppType.t13_5,
      fontFamily: c.monoFontFamily,
      fontWeight: FontWeight.w600,
      color: amountColor,
    );

    final content = MouseRegion(
      onEnter: widget.showEditAffordance
          ? (_) => setState(() => _hovering = true)
          : null,
      onExit: widget.showEditAffordance
          ? (_) => setState(() => _hovering = false)
          : null,
      child: Container(
        padding: widget.flat
            ? const EdgeInsets.fromLTRB(16, 12, 16, 12)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: widget.flat ? Colors.transparent : c.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          children: [
            Container(
              width: widget.flat ? 30 : 28,
              height: widget.flat ? 30 : 28,
              decoration: BoxDecoration(
                color: widget.flat ? c.fg.withValues(alpha: 0.05) : c.border,
                borderRadius: BorderRadius.circular(
                  widget.flat ? 15 : AppRadius.chip,
                ),
              ),
              child: Icon(
                _categoryIcon(widget.entry.category),
                size: 15,
                color: c.muted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    description ?? widget.entry.category,
                    style: TextStyle(
                      fontSize: AppType.t13_5,
                      fontWeight: FontWeight.w600,
                      color: c.fg,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      // Without a note the title already IS the category;
                      // repeating it read "Food / Food · Today".
                      if (description != null) ...[
                        Flexible(
                          child: Text(
                            widget.entry.category,
                            style: TextStyle(
                              fontSize: AppType.t11,
                              color: c.muted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          ' · ',
                          style: TextStyle(
                            fontSize: AppType.t11,
                            color: c.muted,
                          ),
                        ),
                      ],
                      Flexible(
                        child: Text(
                          widget.noteTitle ?? date,
                          style: widget.noteTitle != null
                              ? TextStyle(fontSize: AppType.t11, color: c.muted)
                              : TextStyle(
                                  fontSize: AppType.t11,
                                  fontFamily: c.monoFontFamily,
                                  color: c.muted,
                                ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text.rich(
                TextSpan(
                  style: amountStyle,
                  children: [
                    TextSpan(text: widget.isIncome ? '+' : '\u2212'),
                    currencySpan(widget.currency, amountStyle),
                    TextSpan(
                      text: formatMinor(widget.entry.amount, widget.currency),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.showEditAffordance) ...[
              const SizedBox(width: 8),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  border: Border.all(
                    color: _hovering ? c.border : const Color(0x00000000),
                  ),
                ),
                child: Icon(
                  Icons.edit_outlined,
                  size: 13,
                  color: _hovering ? c.fg : c.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    return widget.onTap == null
        ? content
        : InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: content,
          );
  }
}

class _ZeroTransactionsState extends StatelessWidget {
  final VoidCallback? onAddExpense;
  final VoidCallback? onAddIncome;

  const _ZeroTransactionsState({this.onAddExpense, this.onAddIncome});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: c.fg.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.account_balance_wallet_outlined,
              size: 26,
              color: c.muted,
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          Text(
            'No transactions yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppType.t15,
              fontWeight: FontWeight.w600,
              color: c.fg,
            ),
          ),
          const SizedBox(height: AppSpacing.s6),
          Text(
            'Track your spending, income and budgets in one place.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppType.t13_5,
              color: c.muted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.s20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              if (onAddExpense != null)
                ElevatedButton.icon(
                  onPressed: onAddExpense,
                  icon: const Icon(Icons.arrow_downward, size: 16),
                  label: const Text('Add expense'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.fg,
                    foregroundColor: c.bg,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s20,
                      vertical: AppSpacing.s12,
                    ),
                    textStyle: const TextStyle(
                      fontSize: AppType.t13_5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (onAddIncome != null)
                OutlinedButton.icon(
                  onPressed: onAddIncome,
                  icon: const Icon(Icons.arrow_upward, size: 16),
                  label: const Text('Add income'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.fg,
                    backgroundColor: c.surface,
                    side: BorderSide(color: c.border.withValues(alpha: 0.8)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s20,
                      vertical: AppSpacing.s12,
                    ),
                    textStyle: const TextStyle(
                      fontSize: AppType.t13_5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The desktop hero: Net for the period as the largest number on the canvas,
/// answered as a sentence ("You kept ₱X of ₱Y this month · Z%") with the
/// spending-delta chip below. Dominant currency only; non-dominant currencies
/// are declared in the footnote, never summed (05-B rule). Income <= 0 renders
/// the em-dash placeholder instead of the sentence.
class _NetHeroCard extends StatelessWidget {
  final FinanceSummary summary;
  final String period;

  const _NetHeroCard({required this.summary, required this.period});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Ink, like every headline figure; red only once more went out than in.
    final amountColor = summary.net < 0 ? c.destructive : c.fg;
    final heroStyle = TextStyle(
      fontSize: 34,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6,
      color: amountColor,
      height: 1.15,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.border.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Net · ${periodName(period)}', style: _labelStyle(context)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: summary.net.toDouble()),
              duration: AppMotion.duration(context, AppMotion.page),
              curve: AppMotion.decelerate,
              builder: (context, value, _) => Text.rich(
                TextSpan(
                  style: heroStyle,
                  children: [
                    // Prototype shows the sign explicitly on the hero ("+₱X");
                    // moneySpans keeps the U+2212 for negatives.
                    if (value.round() > 0) const TextSpan(text: '+'),
                    ...moneySpans(
                      value.round(),
                      summary.dominantCurrency,
                      heroStyle,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          _savingsSentence(context),
          if (summary.previousPeriodExpense > 0 ||
              summary.previousPeriodIncome > 0) ...[
            const SizedBox(height: 8),
            _DeltaChip(
              label: 'Spending',
              current: summary.totalExpense,
              previous: summary.previousPeriodExpense,
              periodLabel: switch (period) {
                'week' => 'last week',
                'month' => 'last month',
                'year' => 'last year',
                _ => '',
              },
            ),
          ],
        ],
      ),
    );
  }

  /// "You kept X of Y this period · Z%", amounts emphasized in mono fg,
  /// exclusion footnote when other currencies exist. Em-dash when there is
  /// no income.
  Widget _savingsSentence(BuildContext context) {
    final c = context.colors;
    final income = summary.totalIncome;
    final mutedStyle = TextStyle(fontSize: AppType.t12, color: c.muted);
    if (income <= 0) {
      return Text('\u2014', style: mutedStyle);
    }
    final pct = ((summary.net / income) * 100).round();
    final amountStyle = TextStyle(
      fontSize: AppType.t12,
      fontWeight: FontWeight.w600,
      color: c.fg,
      fontFamily: c.monoFontFamily,
    );
    final others = {
      ...summary.incomeByCurrency.keys,
      ...summary.expenseByCurrency.keys,
    }..remove(summary.dominantCurrency);
    final othersList = others.toList()..sort();
    final periodWord = switch (period) {
      'week' => 'this week',
      'month' => 'this month',
      'year' => 'this year',
      _ => 'overall',
    };
    return Text.rich(
      TextSpan(
        style: mutedStyle,
        children: [
          const TextSpan(text: 'You kept '),
          ...moneySpans(summary.net, summary.dominantCurrency, amountStyle),
          const TextSpan(text: ' of '),
          currencySpan(summary.dominantCurrency, amountStyle),
          TextSpan(
            text: formatMinor(income, summary.dominantCurrency),
            style: amountStyle,
          ),
          TextSpan(text: ' $periodWord · '),
          TextSpan(text: '$pct%', style: amountStyle),
          if (othersList.isNotEmpty)
            TextSpan(text: ' · excl. ${othersList.join(' · ')}'),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Desktop ledger column from the accepted prototype: "Transactions" header with
/// a View-all link, day-grouped signed rows collapsed to the first five, and the
/// centered expand/collapse footer link. Owns its expansion state so
/// FinanceWorkspace can stay stateless.
class _LedgerColumn extends StatefulWidget {
  final FinanceSummary summary;
  final String period;
  final VoidCallback? onViewAllTime;
  final void Function(String noteId, String entryId)? onSelectEntry;
  final void Function(String)? onSelectNote;

  const _LedgerColumn({
    required this.summary,
    required this.period,
    this.onViewAllTime,
    this.onSelectEntry,
    this.onSelectNote,
  });

  @override
  State<_LedgerColumn> createState() => _LedgerColumnState();
}

class _LedgerColumnState extends State<_LedgerColumn> {
  static const int _collapsedCount = 5;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final entries = widget.summary.recentEntries;
    final canExpand = entries.length > _collapsedCount;
    final shown = _expanded || !canExpand
        ? entries
        : entries.take(_collapsedCount).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeLabel(
          'TRANSACTIONS',
          trailing: canExpand
              ? (_expanded ? 'Show fewer' : 'View all ${entries.length}')
              : null,
          trailingIcon: false,
          onTrailingTap: canExpand
              ? () => setState(() => _expanded = !_expanded)
              : null,
        ),
        if (entries.isEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No transactions in ${periodName(widget.period)}.',
                style: TextStyle(
                  fontSize: AppType.t13_5,
                  color: context.colors.muted,
                ),
              ),
              if (widget.onViewAllTime != null && widget.period != 'all') ...[
                const SizedBox(height: 6),
                TextButton(
                  onPressed: widget.onViewAllTime,
                  style: TextButton.styleFrom(
                    foregroundColor: context.colors.fg,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    alignment: Alignment.centerLeft,
                    textStyle: const TextStyle(fontSize: AppType.t12),
                  ),
                  child: const Text('View all time'),
                ),
              ],
            ],
          )
        else
          ..._groupedRows(context, shown),
        if (canExpand)
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            style: TextButton.styleFrom(
              foregroundColor: context.colors.muted,
              padding: const EdgeInsets.symmetric(vertical: 8),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontSize: AppType.t12),
            ),
            child: Text(
              _expanded
                  ? 'Show fewer \u2191'
                  : 'View all ${entries.length} transactions \u2193',
            ),
          ),
      ],
    );
  }

  /// Rows grouped under day headers, newest day first. Grouping is by calendar
  /// day on a LinkedHashMap so the first-seen (newest, given the home_screen
  /// sort) order is preserved even for unsorted input.
  List<Widget> _groupedRows(
    BuildContext context,
    List<(MoneyEntry, Note)> entries,
  ) {
    final groups = <DateTime, List<(MoneyEntry, Note)>>{};
    for (final e in entries) {
      final d = e.$1.date;
      final day = DateTime(d.year, d.month, d.day);
      groups.putIfAbsent(day, () => []).add(e);
    }
    final headerStyle = TextStyle(
      fontSize: AppType.t11,
      fontWeight: FontWeight.w600,
      color: context.colors.muted,
      letterSpacing: 0.9,
    );
    return [
      for (var i = 0; i < groups.length; i++)
        ..._dayGroup(
          context,
          groups.keys.elementAt(i),
          groups.values.elementAt(i),
          isFirst: i == 0,
          headerStyle: headerStyle,
        ),
    ];
  }

  List<Widget> _dayGroup(
    BuildContext context,
    DateTime day,
    List<(MoneyEntry, Note)> entries, {
    required bool isFirst,
    required TextStyle headerStyle,
  }) {
    final c = context.colors;
    return [
      Padding(
        padding: EdgeInsets.only(top: isFirst ? 0 : 16, bottom: 8, left: 4),
        child: Text(_dayGroupLabel(day).toUpperCase(), style: headerStyle),
      ),
      // One card per day, rows divided: the same grouped surface the phone
      // and Home use, instead of a stack of separate tiles.
      HomeCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: 58,
                  endIndent: 16,
                  color: c.border.withValues(alpha: 0.8),
                ),
              _RecentTransactionRow(
                flat: true,
                entry: entries[i].$1,
                isIncome:
                    (entries[i].$1.type ?? entries[i].$2.type) == 'income',
                currency:
                    entries[i].$1.currency ??
                    entries[i].$2.currency ??
                    widget.summary.dominantCurrency,
                noteTitle: entries[i].$2.title.isNotEmpty
                    ? entries[i].$2.title
                    : null,
                showEditAffordance: true,
                onTap: widget.onSelectEntry != null
                    ? () => widget.onSelectEntry!(
                        entries[i].$2.id,
                        entries[i].$1.id,
                      )
                    : widget.onSelectNote == null
                    ? null
                    : () => widget.onSelectNote!(entries[i].$2.id),
              ),
            ],
          ],
        ),
      ),
    ];
  }
}

/// The bordered keyboard-hint chip inside the capture buttons (prototype .kbd):
/// E / I at 65 % opacity in the button's own foreground color.
class _KbdHint extends StatelessWidget {
  final String label;
  final Color color;

  const _KbdHint({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.65,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppType.t10,
            fontFamily: context.colors.monoFontFamily,
            color: color,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}

/// Wide desktop finance workspace: full-canvas dashboard for the editor pane
/// when the Finance tab is active and no note is open. Hero Net card with the
/// savings sentence and spending-delta chip, compact In/Out cards with the
/// mixed-currency footnote, a full-width 14-day trend card, then two columns —
/// day-grouped transactions left, categories + budgets + the ledger-note link
/// right.
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

  /// Switches the period filter to 'all'. Null hides the "View all time" link.
  final VoidCallback? onViewAllTime;
  final List<int> dailyTotals;

  /// Title of the note the right-rail ledger link opens; null hides the link.
  final String? ledgerNoteLabel;

  /// Opens the ledger note from the right-rail link; null hides the link.
  final VoidCallback? onOpenLedgerNote;

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
    this.onViewAllTime,
    this.dailyTotals = const [],
    this.ledgerNoteLabel,
    this.onOpenLedgerNote,
  });

  /// The one persistent add pattern, top-right beside the period filter.
  /// Expense is the most frequent action so it is the solid ink key (same as
  /// the phone); Income is its outlined twin. Neither uses money red or green.
  /// Tooltips advertise the E / I shortcuts wired in home_screen.
  Widget _addButtons(BuildContext context) {
    final c = context.colors;
    const label = TextStyle(
      fontSize: AppType.t13_5,
      fontWeight: FontWeight.w600,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onAddExpense != null)
          Tooltip(
            message: 'Expense (E)',
            child: ElevatedButton.icon(
              onPressed: onAddExpense,
              icon: const Icon(Icons.arrow_downward, size: 15),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Expense'),
                  const SizedBox(width: 6),
                  _KbdHint(label: 'E', color: c.bg),
                ],
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.fg,
                foregroundColor: c.bg,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
                minimumSize: const Size(0, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: label,
              ),
            ),
          ),
        if (onAddExpense != null && onAddIncome != null)
          const SizedBox(width: 8),
        if (onAddIncome != null)
          Tooltip(
            message: 'Income (I)',
            child: OutlinedButton.icon(
              onPressed: onAddIncome,
              icon: const Icon(Icons.arrow_upward, size: 15),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Income'),
                  const SizedBox(width: 6),
                  _KbdHint(label: 'I', color: c.fg),
                ],
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.fg,
                backgroundColor: c.surface,
                side: BorderSide(color: c.border.withValues(alpha: 0.8)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
                minimumSize: const Size(0, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: label,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (!summary.hasAnyEntries) {
      return Container(
        color: c.listBg,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              children: [
                _ZeroTransactionsState(
                  onAddExpense: onAddExpense,
                  onAddIncome: onAddIncome,
                ),
                if (budgets.isNotEmpty) ..._budgetsSection(context),
              ],
            ),
          ),
        ),
      );
    }
    return Container(
      color: c.listBg,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _ScopeSelector(
                      period: period,
                      onPeriodChanged: onPeriodChanged,
                      currencyScope: currencyScope,
                      currencyOptions: currencyOptions,
                      onCurrencyChanged: onCurrencyChanged,
                    ),
                  ),
                  if (onAddExpense != null || onAddIncome != null) ...[
                    const SizedBox(width: 16),
                    _addButtons(context),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              // The prototype's flex row stretches all three cards to one height;
              // a Flutter Row centers them, so the heights must be forced equal.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _NetHeroCard(summary: summary, period: period),
                    ),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: _inCard(context)),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: _outCard(context)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SpendSparkline(
                dailyTotals: dailyTotals,
                currency: summary.dominantCurrency,
                showDayLabels: true,
                averagePerDay: summary.averageAvailable
                    ? summary.averageDailySpend.round()
                    : null,
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _LedgerColumn(
                      summary: summary,
                      period: period,
                      onViewAllTime: onViewAllTime,
                      onSelectEntry: onSelectEntry,
                      onSelectNote: onSelectNote,
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(flex: 2, child: _rightColumn(context)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inCard(BuildContext context) {
    final others = {...summary.incomeByCurrency.keys}
      ..remove(summary.dominantCurrency);
    final othersList = others.toList()..sort();
    final incomeEntries = summary.recentEntries
        .where((e) => (e.$1.type ?? e.$2.type) == 'income')
        .toList();
    String? topCategory;
    if (incomeEntries.isNotEmpty) {
      final byCategory = <String, int>{};
      for (final e in incomeEntries) {
        byCategory[e.$1.category] =
            (byCategory[e.$1.category] ?? 0) + e.$1.amount;
      }
      topCategory = byCategory.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
    }
    final parts = <String>[
      if (incomeEntries.isNotEmpty)
        '${incomeEntries.length} source${incomeEntries.length == 1 ? '' : 's'}',
      if (topCategory != null) topCategory,
      if (othersList.isNotEmpty)
        'excl. ${othersList.map((code) => '${formatMinorAmount(summary.incomeByCurrency[code]!, code)} $code').join(' · ')}',
    ];
    return _SummaryCard(
      label: 'In',
      amount: summary.hasMixedCurrencies ? null : summary.totalIncome,
      amountsByCurrency: summary.hasMixedCurrencies
          ? _dominantFirst(summary.incomeByCurrency, summary.dominantCurrency)
          : null,
      color: context.colors.fg,
      currency: summary.dominantCurrency,
      footnote: parts.isEmpty ? null : parts.join(' · '),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
    );
  }

  Widget _outCard(BuildContext context) {
    final others = {...summary.expenseByCurrency.keys}
      ..remove(summary.dominantCurrency);
    final othersList = others.toList()..sort();
    final expenseCount = summary.recentEntries
        .where((e) => (e.$1.type ?? e.$2.type) != 'income')
        .length;
    final parts = <String>[
      if (expenseCount > 0)
        '$expenseCount ${expenseCount == 1 ? 'entry' : 'entries'}',
      if (othersList.isNotEmpty)
        'excl. ${othersList.map((code) => '${formatMinorAmount(summary.expenseByCurrency[code]!, code)} $code').join(' · ')}',
    ];
    return _SummaryCard(
      label: 'Out',
      amount: summary.hasMixedCurrencies ? null : summary.totalExpense,
      amountsByCurrency: summary.hasMixedCurrencies
          ? _dominantFirst(summary.expenseByCurrency, summary.dominantCurrency)
          : null,
      color: context.colors.fg,
      currency: summary.dominantCurrency,
      footnote: parts.isEmpty ? null : parts.join(' · '),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
    );
  }

  Widget _rightColumn(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._budgetsSection(context, leadingGap: false),
        const SizedBox(height: 22),
        const HomeLabel('TOP CATEGORIES'),
        if (summary.categories.isEmpty)
          Text(
            'No spending in this period.',
            style: TextStyle(
              fontSize: AppType.t12,
              color: context.colors.muted,
            ),
          )
        else
          Column(children: _categoryRows(context, summary)),
        if (ledgerNoteLabel != null && onOpenLedgerNote != null)
          _ledgerNoteLink(context),
      ],
    );
  }

  /// Slim link card to the monthly ledger note — the replacement affordance for
  /// the dropped note-list pane. Solid border on the border token (quieter than
  /// a filled card); whole card is the tap target.
  Widget _ledgerNoteLink(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: HomeCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        onTap: onOpenLedgerNote,
        semanticsLabel: 'Open $ledgerNoteLabel',
        child: Row(
          children: [
            Icon(Icons.article_outlined, size: 16, color: c.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: TextStyle(fontSize: AppType.t12, color: c.muted),
                  children: [
                    TextSpan(
                      text:
                          "${monthName(DateTime.now().month)}'s ledger lives in ",
                    ),
                    TextSpan(
                      text: ledgerNoteLabel,
                      style: TextStyle(
                        fontSize: AppType.t12,
                        fontWeight: FontWeight.w500,
                        color: c.fg,
                      ),
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_rounded, size: 14, color: c.muted),
          ],
        ),
      ),
    );
  }

  /// The Budgets header, its "Add budget" action and the budget cards.
  ///
  /// Extracted from [_rightColumn] so the zero-transactions empty state can
  /// render budgets on its own: a budget can exist before any transaction.
  List<Widget> _budgetsSection(BuildContext context, {bool leadingGap = true}) {
    final visible = _visibleBudgets(budgets, currencyScope);
    final mixedBudgetCurrencies =
        budgets.map((b) => b.currency).toSet().length > 1;
    return [
      if (leadingGap) const SizedBox(height: 22),
      HomeLabel(
        'BUDGETS',
        trailing: onAddBudget == null ? null : 'Add budget',
        trailingIcon: false,
        onTrailingTap: onAddBudget == null
            ? null
            : () => _openBudgetSheet(context),
      ),
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
              onRemove: onRemoveBudget != null
                  ? () => onRemoveBudget!(b)
                  : null,
            ),
          );
        }),
    ];
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
