import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/budget.dart';
import '../theme/app_colors.dart';
import '../utils/finance_utils.dart';
import '../utils/id.dart';
import 'entry_sheet.dart';

class BudgetSheet extends StatefulWidget {
  final Budget? budget;
  final void Function(Budget) onSave;
  final List<String> existingCategories;
  final String currencySymbol;

  const BudgetSheet({
    super.key,
    this.budget,
    required this.onSave,
    this.existingCategories = const [],
    this.currencySymbol = '',
  });

  static Future<void> show(
    BuildContext context, {
    Budget? budget,
    required void Function(Budget) onSave,
    List<String> existingCategories = const [],
    String currencySymbol = '',
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: kIsWeb ? false : true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => kIsWeb
          ? BudgetSheet(
              budget: budget,
              onSave: onSave,
              existingCategories: existingCategories,
              currencySymbol: currencySymbol,
            )
          : Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: BudgetSheet(
          budget: budget,
          onSave: onSave,
          existingCategories: existingCategories,
          currencySymbol: currencySymbol,
        ),
      ),
    );
  }

  @override
  State<BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends State<BudgetSheet> {
  late TextEditingController _categoryCtrl;
  late TextEditingController _limitCtrl;

  @override
  void initState() {
    super.initState();
    final b = widget.budget;
    _categoryCtrl = TextEditingController(text: b?.category ?? '');
    _limitCtrl = TextEditingController(
        text: b != null ? b.limit.toStringAsFixed(2) : '');
  }

  @override
  void dispose() {
    _categoryCtrl.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final limit = double.tryParse(_limitCtrl.text.trim());
    if (limit == null || limit <= 0) {
      _showError('Enter a valid limit');
      return;
    }
    final category = _categoryCtrl.text.trim();
    if (category.isEmpty) {
      _showError('Enter a category');
      return;
    }
    final budget = Budget(
      id: widget.budget?.id ?? generateId('b'),
      category: category,
      limit: limit,
    );
    widget.onSave(budget);
    Navigator.pop(context);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.budget != null;
    final cats = <String>{
      ...kDefaultCategories,
      ...widget.existingCategories,
      if (_categoryCtrl.text.trim().isNotEmpty) _categoryCtrl.text.trim(),
    }.toList();
    cats.sort((a, b) {
      final aDef = kDefaultCategories.contains(a) ? 0 : 1;
      final bDef = kDefaultCategories.contains(b) ? 0 : 1;
      if (aDef != bDef) return aDef.compareTo(bDef);
      return a.compareTo(b);
    });
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: context.colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(isEdit ? 'Edit budget' : 'Add budget',
                style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600,
                  color: context.colors.fg, letterSpacing: 0.01,
                )),
            const SizedBox(height: 16),
            _Field(
              label: 'Category',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6, runSpacing: 6,
                    children: cats.map((cat) {
                      final selected = _categoryCtrl.text.trim() == cat;
                      return InkWell(
                        onTap: () => setState(() => _categoryCtrl.text = cat),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: selected
                                ? context.colors.accentDim
                                : context.colors.listBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected
                                  ? context.colors.accent
                                  : context.colors.border,
                            ),
                          ),
                          child: Text(cat,
                              style: TextStyle(
                                fontSize: 12,
                                color: selected
                                    ? context.colors.accent
                                    : context.colors.fg,
                              )),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _categoryCtrl,
                    decoration: _inputDeco('Or type your own'),
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(fontSize: 14, color: context.colors.fg),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Field(
              label: 'Limit',
              child: TextField(
                controller: _limitCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: kAmountInputFormatters,
                autofocus: !isEdit,
                decoration: _inputDeco(
                  widget.currencySymbol.isNotEmpty
                      ? '${widget.currencySymbol}0.00'
                      : '0.00',
                ),
                style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w500,
                  color: context.colors.fg,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: context.colors.border),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text('Cancel',
                        style: TextStyle(
                            color: context.colors.fg, fontSize: 14)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.accent,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(isEdit ? 'Update' : 'Add',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: context.colors.muted, fontSize: 14),
      filled: true,
      fillColor: context.colors.listBg,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: context.colors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: context.colors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: context.colors.accent),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final Widget child;
  const _Field({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w500,
              color: context.colors.muted, letterSpacing: 0.04,
            )),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
