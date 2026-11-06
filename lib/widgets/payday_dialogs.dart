import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../utils/cutoff.dart';
import '../utils/finance_utils.dart';

/// Settings → Payday: when pay arrives. Common Philippine schedules first;
/// "Once a month" picks a day.
Future<PaydaySettings?> showPaydayPicker(
  BuildContext context,
  PaydaySettings current,
) {
  return showDialog<PaydaySettings>(
    context: context,
    builder: (_) => _PaydayDialog(current: current),
  );
}

class _PaydayDialog extends StatefulWidget {
  final PaydaySettings current;
  const _PaydayDialog({required this.current});

  @override
  State<_PaydayDialog> createState() => _PaydayDialogState();
}

class _PaydayDialogState extends State<_PaydayDialog> {
  static const _presets = [
    PaydaySettings([15, 30]),
    PaydaySettings([15, 31]),
    PaydaySettings([10, 25]),
    PaydaySettings([31]),
  ];

  late PaydaySettings _picked = widget.current;
  late int _monthlyDay =
      widget.current.days.length == 1 && widget.current.days.first != 31
      ? widget.current.days.first
      : 15;

  bool get _isMonthly => _picked.days.length == 1 && _picked.days.first != 31;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget option(
      String label,
      bool selected,
      VoidCallback onTap, {
      Widget? trailing,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: selected ? c.accent : c.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: AppType.t15, color: c.fg),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      );
    }

    return AlertDialog(
      title: const Text('Payday'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Home shows what’s left until the next one.',
            style: TextStyle(fontSize: AppType.t13_5, color: c.muted),
          ),
          const SizedBox(height: 8),
          for (final p in _presets)
            option(
              p.label,
              !_isMonthly && _picked == p,
              () => setState(() => _picked = p),
            ),
          option(
            'Once a month on the',
            _isMonthly,
            () => setState(() => _picked = PaydaySettings([_monthlyDay])),
            trailing: DropdownButton<int>(
              value: _monthlyDay,
              underline: const SizedBox.shrink(),
              items: [
                for (var d = 1; d <= 30; d++)
                  DropdownMenuItem(value: d, child: Text(ordinal(d))),
              ],
              onChanged: (d) {
                if (d == null) return;
                setState(() {
                  _monthlyDay = d;
                  _picked = PaydaySettings([d]);
                });
              },
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _picked),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// The result of the budget dialog: a new budget, or none (removed).
typedef CutoffBudgetChoice = ({CutoffBudget? budget});

/// Settings → Budget per cutoff: one amount for each pay period. Null when
/// cancelled; `(budget: null)` when removed.
Future<CutoffBudgetChoice?> showCutoffBudgetDialog(
  BuildContext context, {
  required CutoffBudget? current,
  required String currency,
}) {
  return showDialog<CutoffBudgetChoice>(
    context: context,
    builder: (_) => _BudgetDialog(current: current, currency: currency),
  );
}

class _BudgetDialog extends StatefulWidget {
  final CutoffBudget? current;
  final String currency;
  const _BudgetDialog({required this.current, required this.currency});

  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  late final String _currency = widget.current?.currency ?? widget.currency;
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.current == null
        ? ''
        : formatMinor(widget.current!.amount, _currency).replaceAll(',', ''),
  );
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final minor = parseAmountToMinor(_ctrl.text.trim(), _currency);
    if (minor == null || minor <= 0) {
      setState(() => _error = 'Enter an amount, like 10000');
      return;
    }
    Navigator.pop<CutoffBudgetChoice>(context, (
      budget: CutoffBudget(minor, _currency),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AlertDialog(
      title: const Text('Budget per cutoff'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'How much to spend from one payday to the next. Home shows '
            'what’s left and whether you’re on pace.',
            style: TextStyle(fontSize: AppType.t13_5, color: c.muted),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: kAmountInputFormatters,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              prefixText: '${currencySymbol(_currency)} ',
              hintText: '10000',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        if (widget.current != null)
          TextButton(
            onPressed: () =>
                Navigator.pop<CutoffBudgetChoice>(context, (budget: null)),
            child: Text('Remove', style: TextStyle(color: c.destructive)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
