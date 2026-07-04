import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../utils/templates.dart';

class TemplatePickerSheet extends StatelessWidget {
  final void Function(NoteTemplate) onPick;

  const TemplatePickerSheet({super.key, required this.onPick});

  static Future<void> show(
    BuildContext context, {
    required void Function(NoteTemplate) onPick,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => TemplatePickerSheet(onPick: onPick),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: context.colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  Text('New note',
                      style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: context.colors.fg, letterSpacing: 0.01,
                      )),
                ],
              ),
            ),
            const SizedBox(height: 4),
            ...getNoteTemplates().map((t) => _TemplateRow(
              template: t,
              onTap: () {
                Navigator.pop(context);
                onPick(t);
              },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _TemplateRow extends StatelessWidget {
  final NoteTemplate template;
  final VoidCallback onTap;

  const _TemplateRow({required this.template, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isBlank = template.name == 'Blank note';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isBlank
                    ? context.colors.listBg
                    : context.colors.accentDim,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                template.icon,
                size: 18,
                color: isBlank ? context.colors.muted : context.colors.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(template.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:  TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500,
                        color: context.colors.fg,
                      )),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      template.preview,
                      style:  TextStyle(
                        fontSize: 12, color: context.colors.muted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
