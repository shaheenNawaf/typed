import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';

/// The one task vocabulary used everywhere a checklist line appears — Home's
/// Next up, an open list, the Tasks view: a round check that fills with ink,
/// a calm 15–16px label, done lines muted and struck. Motion is a short
/// fade only; nothing scales or bounces.

const Duration _fade = Duration(milliseconds: 160);

/// Round checkbox. Ink (the text colour) when done — no accent, no green —
/// so the page keeps its single accent for the primary action.
class TaskCheck extends StatelessWidget {
  final bool done;
  final VoidCallback onTap;
  final double size;
  final String? semanticsLabel;

  const TaskCheck({
    super.key,
    required this.done,
    required this.onTap,
    this.size = 22,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      checked: done,
      label: semanticsLabel,
      excludeSemantics: true,
      child: InkResponse(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        radius: 22,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: AnimatedContainer(
              duration: reduce ? Duration.zero : _fade,
              curve: Curves.easeOut,
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? c.fg : Colors.transparent,
                border: Border.all(
                  color: done ? c.fg : c.muted.withValues(alpha: 0.75),
                  width: 1.6,
                ),
              ),
              child: AnimatedOpacity(
                duration: reduce ? Duration.zero : _fade,
                opacity: done ? 1 : 0,
                child: Icon(
                  Icons.check_rounded,
                  size: size * 0.66,
                  color: c.surface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One checklist line: check · label · optional quiet meta on the right.
/// [label] replaces the text (the editor swaps in an inline field).
class TaskRow extends StatelessWidget {
  final bool done;
  final VoidCallback onToggle;
  final String text;
  final Widget? label;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? meta;
  final bool dense;

  const TaskRow({
    super.key,
    required this.done,
    required this.onToggle,
    required this.text,
    this.label,
    this.onTap,
    this.onLongPress,
    this.meta,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final body =
        label ??
        AnimatedDefaultTextStyle(
          duration: reduce ? Duration.zero : _fade,
          style: taskTextStyle(context, done: done, dense: dense),
          child: Text(text.isEmpty ? 'Untitled task' : text),
        );
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: dense ? 44 : 48),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TaskCheck(
            done: done,
            onTap: onToggle,
            semanticsLabel: done ? 'Mark $text not done' : 'Complete $text',
          ),
          const SizedBox(width: 4),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              onLongPress: onLongPress,
              onSecondaryTap: onLongPress,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: body,
              ),
            ),
          ),
          if (meta != null) ...[
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                meta!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppType.t12, color: c.muted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

TextStyle taskTextStyle(
  BuildContext context, {
  required bool done,
  bool dense = false,
}) {
  final c = context.colors;
  return TextStyle(
    fontSize: dense ? 14.5 : 15.5,
    height: 1.35,
    fontWeight: FontWeight.w400,
    color: done ? c.muted : c.fg,
    decoration: done ? TextDecoration.lineThrough : TextDecoration.none,
    decorationColor: c.muted,
  );
}

/// The "add a task" line, in the same shape as a task row: a quiet plus in
/// the check column, a borderless field, Enter adds and keeps you typing.
class TaskAddRow extends StatefulWidget {
  final ValueChanged<String> onSubmit;
  final String hint;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool dense;

  const TaskAddRow({
    super.key,
    required this.onSubmit,
    this.hint = 'Add a task',
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.dense = false,
  });

  @override
  State<TaskAddRow> createState() => _TaskAddRowState();
}

class _TaskAddRowState extends State<TaskAddRow> {
  late final TextEditingController _ctrl =
      widget.controller ?? TextEditingController();
  late final FocusNode _focus = widget.focusNode ?? FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctrl.removeListener(_changed);
    if (widget.controller == null) _ctrl.dispose();
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    widget.onSubmit(text);
    _ctrl.clear();
    // Stay in the field: adding several tasks is one motion, not several.
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasText = _ctrl.text.trim().isNotEmpty;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: widget.dense ? 44 : 48),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: Icon(Icons.add_rounded, size: 22, color: c.muted),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              autofocus: widget.autofocus,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              // A tap elsewhere ends the edit; otherwise the caret lingers after
              // the keyboard is dismissed.
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              style: taskTextStyle(context, done: false, dense: widget.dense),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintText: widget.hint,
                hintStyle: taskTextStyle(
                  context,
                  done: false,
                  dense: widget.dense,
                ).copyWith(color: c.muted),
              ),
            ),
          ),
          AnimatedOpacity(
            duration: reduce ? Duration.zero : _fade,
            opacity: hasText ? 1 : 0,
            child: IgnorePointer(
              ignoring: !hasText,
              child: IconButton(
                tooltip: 'Add task',
                onPressed: _submit,
                icon: Icon(
                  Icons.keyboard_return_rounded,
                  size: 20,
                  color: c.muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Completed · 3   Show" — done lines fold away so open work is all you
/// see by default. Text, not a chevron, says what tapping does.
class TaskCompletedToggle extends StatelessWidget {
  final int count;
  final bool expanded;
  final VoidCallback onToggle;

  const TaskCompletedToggle({
    super.key,
    required this.count,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: '$count completed, ${expanded ? 'hide' : 'show'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Text(
                'Completed · $count',
                style: TextStyle(
                  fontSize: AppType.t13_5,
                  fontWeight: FontWeight.w500,
                  color: c.muted,
                ),
              ),
              const Spacer(),
              Text(
                expanded ? 'Hide' : 'Show',
                style: TextStyle(fontSize: AppType.t13_5, color: c.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
