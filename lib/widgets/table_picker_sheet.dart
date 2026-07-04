import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

enum TableAlign { left, center, right }

class TablePickerSheet extends StatefulWidget {
  final void Function(int rows, int cols, TableAlign align) onInsert;

  const TablePickerSheet({super.key, required this.onInsert});

  static Future<void> show(
    BuildContext context, {
    required void Function(int rows, int cols, TableAlign align) onInsert,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => TablePickerSheet(onInsert: onInsert),
    );
  }

  @override
  State<TablePickerSheet> createState() => _TablePickerSheetState();
}

class _TablePickerSheetState extends State<TablePickerSheet> {
  int _rows = 3;
  int _cols = 2;
  TableAlign _align = TableAlign.left;

  String _alignSep(TableAlign a) {
    switch (a) {
      case TableAlign.left:
        return ':---';
      case TableAlign.center:
        return ':---:';
      case TableAlign.right:
        return '---:';
    }
  }

  String _buildPreview() {
    final widths = List.generate(_cols, (i) => 5);
    final header =
        '| ${List.generate(_cols, (i) => 'Col ${i + 1}'.padBoth(widths[i])).join(' | ')} |';
    final sep =
        '| ${List.generate(_cols, (i) => _alignSep(_align).padRight(widths[i])).join(' | ')} |';
    final body = List.generate(_rows, (row) {
      return '| ${List.generate(_cols, (i) => ' '.padBoth(widths[i])).join(' | ')} |';
    }).join('\n');
    return '$header\n$sep\n$body';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: context.colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text('Insert table',
                style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600,
                  color: context.colors.fg, letterSpacing: 0.01,
                )),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _Stepper(
                  label: 'Rows',
                  value: _rows,
                  min: 1, max: 10,
                  onChanged: (v) => setState(() => _rows = v),
                )),
                const SizedBox(width: 12),
                Expanded(child: _Stepper(
                  label: 'Columns',
                  value: _cols,
                  min: 1, max: 8,
                  onChanged: (v) => setState(() => _cols = v),
                )),
              ],
            ),
            const SizedBox(height: 16),
            Text('Alignment',
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500,
                  color: context.colors.muted, letterSpacing: 0.04,
                )),
            const SizedBox(height: 6),
            _AlignToggle(
              value: _align,
              onChanged: (a) => setState(() => _align = a),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.colors.listBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.colors.border),
              ),
              child: Text(
                _buildPreview(),
                style:  TextStyle(
                  fontSize: 12, fontFamily: context.colors.monoFontFamily,
                  color: context.colors.fg, height: 1.5,
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
                      side:  BorderSide(color: context.colors.border),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text('Cancel',
                        style: TextStyle(color: context.colors.fg, fontSize: 14)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onInsert(_rows, _cols, _align);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.accent,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Insert',
                        style: TextStyle(color: Colors.white, fontSize: 14)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:  TextStyle(
              fontSize: 12, fontWeight: FontWeight.w500,
              color: context.colors.muted, letterSpacing: 0.04,
            )),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: context.colors.listBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.colors.border),
          ),
          child: Row(
            children: [
              _StepperBtn(
                icon: Icons.remove,
                onTap: value > min ? () => onChanged(value - 1) : null,
              ),
              Expanded(
                child: Center(
                  child: Text('$value',
                      style:  TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: context.colors.fg,
                      )),
                ),
              ),
              _StepperBtn(
                icon: Icons.add,
                onTap: value < max ? () => onChanged(value + 1) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepperBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepperBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        alignment: Alignment.center,
        child: Icon(icon,
            size: 16,
            color: onTap != null ? context.colors.fg : context.colors.muted.withAlpha(100)),
      ),
    );
  }
}

class _AlignToggle extends StatelessWidget {
  final TableAlign value;
  final ValueChanged<TableAlign> onChanged;

  const _AlignToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: context.colors.listBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        children: TableAlign.values.map((a) {
          final selected = a == value;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(a),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? context.colors.surface : null,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(_label(a),
                      style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500,
                        color: selected ? context.colors.fg : context.colors.muted,
                      )),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _label(TableAlign a) {
    switch (a) {
      case TableAlign.left:
        return 'Left';
      case TableAlign.center:
        return 'Center';
      case TableAlign.right:
        return 'Right';
    }
  }
}

extension _StringPad on String {
  String padBoth(int width) {
    if (length >= width) return this;
    final pad = width - length;
    final left = pad ~/ 2;
    final right = pad - left;
    return (' ' * left) + this + (' ' * right);
  }
}
