import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../utils/cutoff.dart';
import '../utils/date_format.dart';
import '../utils/finance_utils.dart';
import 'quiet_choice.dart';

/// Settings → Payday and → Budget per cutoff, in the calm sheet style of
/// the voice sheets: a handle, a bold title, one line of why, quiet
/// choices, and a single ink Save.

Future<T?> _showSheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.colors.surface,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: child,
    ),
  );
}

/// Handle, title and the one line of why: the top of every calm sheet.
class _SheetHeader extends StatelessWidget {
  final String title;
  final String body;

  const _SheetHeader({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: c.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: c.fg,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          style: TextStyle(fontSize: 14, height: 1.45, color: c.muted),
        ),
      ],
    );
  }
}

/// The solid ink key for a sheet's one primary action.
class _InkButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _InkButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: c.fg,
        foregroundColor: c.bg,
        minimumSize: const Size(88, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

/// A soft note under the controls: what the choice means in practice.
class _Hint extends StatelessWidget {
  final IconData icon;
  final InlineSpan text;

  const _Hint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.listBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: c.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              text,
              style: TextStyle(
                fontSize: AppType.t13_5,
                height: 1.35,
                color: c.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── payday ─────────────────────────────────────────────────────────────────

/// When pay arrives. Null when cancelled.
Future<PaydaySettings?> showPaydaySheet(
  BuildContext context,
  PaydaySettings current, {
  DateTime? now,
}) {
  return _showSheet<PaydaySettings>(
    context,
    _PaydaySheet(current: current, now: now ?? DateTime.now()),
  );
}

class _PaydaySheet extends StatefulWidget {
  final PaydaySettings current;
  final DateTime now;

  const _PaydaySheet({required this.current, required this.now});

  @override
  State<_PaydaySheet> createState() => _PaydaySheetState();
}

class _PaydaySheetState extends State<_PaydaySheet> {
  static const _presets = {
    '15-30': PaydaySettings([15, 30]),
    '15-31': PaydaySettings([15, 31]),
    '10-25': PaydaySettings([10, 25]),
  };

  late PaydaySettings _picked = widget.current;
  late int _monthlyDay = widget.current.days.length == 1
      ? widget.current.days.first
      : 15;

  /// The choice the current setting falls under.
  String get _key {
    for (final e in _presets.entries) {
      if (e.value == _picked) return e.key;
    }
    return _picked.days.length == 1 ? 'monthly' : 'custom';
  }

  void _choose(String key) {
    setState(() {
      _picked = switch (key) {
        'monthly' => PaydaySettings([_monthlyDay]),
        'custom' => widget.current,
        _ => _presets[key]!,
      };
    });
  }

  void _stepDay(int by) {
    setState(() {
      _monthlyDay = (_monthlyDay + by).clamp(1, 31);
      _picked = PaydaySettings([_monthlyDay]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final key = _key;
    final next = cutoffFor(_picked, widget.now).nextPayday;
    final today = DateTime(widget.now.year, widget.now.month, widget.now.day);
    final inDays = next.difference(today).inDays;
    final nextLabel =
        '${kWeekdayNamesShort[next.weekday - 1]}, '
        '${monthShort(next.month)} ${next.day}';
    final custom =
        widget.current.days.length == 2 &&
            !_presets.values.contains(widget.current)
        ? widget.current
        : null;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHeader(
              title: 'Payday',
              body:
                  'When your pay comes in. Home counts down to it, and a '
                  'budget runs from one payday to the next.',
            ),
            const SizedBox(height: 16),
            QuietChoice(
              value: key,
              onChanged: _choose,
              options: {
                '15-30': '15th & 30th',
                '15-31': '15th & last day',
                '10-25': '10th & 25th',
                if (custom != null)
                  'custom': custom.label.replaceAll(' and ', ' & '),
                'monthly': 'Once a month',
              },
            ),
            if (key == 'monthly') ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const SizedBox(width: 14),
                  Text(
                    'On the',
                    style: TextStyle(fontSize: 14, color: c.muted),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Earlier',
                    onPressed: _monthlyDay > 1 ? () => _stepDay(-1) : null,
                    icon: const Icon(Icons.remove_rounded, size: 20),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text(
                      _monthlyDay == 31 ? 'last day' : ordinal(_monthlyDay),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.fg,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Later',
                    onPressed: _monthlyDay < 31 ? () => _stepDay(1) : null,
                    icon: const Icon(Icons.add_rounded, size: 20),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            _Hint(
              icon: Icons.event_outlined,
              text: TextSpan(
                children: [
                  const TextSpan(text: 'Next payday '),
                  TextSpan(
                    text: nextLabel,
                    style: TextStyle(color: c.fg, fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: inDays == 1 ? ' · tomorrow' : ' · in $inDays days',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(foregroundColor: c.muted),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                _InkButton(
                  label: 'Save',
                  onPressed: () => Navigator.pop(context, _picked),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── budget per cutoff ──────────────────────────────────────────────────────

/// The result of the budget sheet: a new budget, or none (removed).
typedef CutoffBudgetChoice = ({CutoffBudget? budget});

/// One amount for each pay period. Null when cancelled; `(budget: null)`
/// when removed. [cutoffDays] sizes the "a day" hint; [lastSpent] is what
/// the last cutoff came to, as a reference point.
Future<CutoffBudgetChoice?> showCutoffBudgetSheet(
  BuildContext context, {
  required CutoffBudget? current,
  required String currency,
  required int cutoffDays,
  int lastSpent = 0,
}) {
  return _showSheet<CutoffBudgetChoice>(
    context,
    _BudgetSheet(
      current: current,
      currency: currency,
      cutoffDays: cutoffDays,
      lastSpent: lastSpent,
    ),
  );
}

class _BudgetSheet extends StatefulWidget {
  final CutoffBudget? current;
  final String currency;
  final int cutoffDays;
  final int lastSpent;

  const _BudgetSheet({
    required this.current,
    required this.currency,
    required this.cutoffDays,
    required this.lastSpent,
  });

  @override
  State<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends State<_BudgetSheet> {
  late final String _currency = widget.current?.currency ?? widget.currency;
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.current == null
        ? ''
        : minorToMajor(widget.current!.amount, _currency).round().toString(),
  );
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int? get _amount {
    final minor = parseAmountToMinor(_ctrl.text.trim(), _currency);
    return minor == null || minor <= 0 ? null : minor;
  }

  void _save() {
    final minor = _amount;
    if (minor == null) {
      setState(() => _error = 'Enter an amount, like 10000.');
      return;
    }
    Navigator.pop<CutoffBudgetChoice>(context, (
      budget: CutoffBudget(minor, _currency),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final amount = _amount;
    final symbolStyle = TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w700,
      color: c.muted,
      fontFamily: 'Roboto',
      fontFamilyFallback: const ['Noto Sans', 'sans-serif'],
    );
    final days = widget.cutoffDays;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHeader(
              title: 'Budget per cutoff',
              body:
                  'How much to spend from one payday to the next. Home '
                  'shows what’s left and whether you’re on pace.',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
              decoration: BoxDecoration(
                color: c.listBg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _error != null ? c.destructive : c.border,
                ),
              ),
              child: Row(
                children: [
                  Text(currencySymbol(_currency), style: symbolStyle),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      autofocus: widget.current == null,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: kAmountInputFormatters,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _save(),
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: c.fg,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                        hintText: '10000',
                        hintStyle: TextStyle(color: c.muted),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  _error!,
                  style: TextStyle(fontSize: AppType.t12, color: c.destructive),
                ),
              ),
            const SizedBox(height: 12),
            _Hint(
              icon: Icons.calendar_view_week_outlined,
              text: amount != null
                  ? TextSpan(
                      children: [
                        const TextSpan(text: 'About '),
                        TextSpan(
                          text: formatWholeAmount(
                            (amount / days).floor(),
                            _currency,
                          ),
                          style: TextStyle(
                            color: c.fg,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(text: ' a day over this $days-day cutoff.'),
                      ],
                    )
                  : widget.lastSpent > 0
                  ? TextSpan(
                      children: [
                        const TextSpan(text: 'Last cutoff you spent '),
                        TextSpan(
                          text: formatWholeAmount(widget.lastSpent, _currency),
                          style: TextStyle(
                            color: c.fg,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const TextSpan(text: '.'),
                      ],
                    )
                  : const TextSpan(
                      text: 'This cutoff runs until your next payday.',
                    ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                if (widget.current != null)
                  TextButton(
                    onPressed: () => Navigator.pop<CutoffBudgetChoice>(
                      context,
                      (budget: null),
                    ),
                    style: TextButton.styleFrom(foregroundColor: c.destructive),
                    child: const Text('Remove'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(foregroundColor: c.muted),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                _InkButton(label: 'Save', onPressed: _save),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
