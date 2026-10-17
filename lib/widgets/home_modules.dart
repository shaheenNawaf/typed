import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/note.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../theme/app_motion.dart';
import '../utils/finance_utils.dart';
import 'task_row.dart';

/// Home's modules, built for focus. Each block holds ONE thing — one place
/// to capture, one task, one note to return to, one line of money — so
/// there is always a single obvious next step and nothing competes with it.
/// (Attention-friendly patterns: one primary action, one task at a time,
/// progressive disclosure, no urgency mechanics like streak-loss nags.)

// ── shared chrome ──────────────────────────────────────────────────────────

class HomeLabel extends StatelessWidget {
  final String text;
  final String? trailing;

  /// Makes the trailing text a quiet link (with an arrow).
  final VoidCallback? onTrailingTap;
  final String? trailingSemantics;
  final bool trailingIcon;

  const HomeLabel(
    this.text, {
    super.key,
    this.trailing,
    this.onTrailingTap,
    this.trailingSemantics,
    this.trailingIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = TextStyle(
      fontSize: AppType.t11,
      fontWeight: FontWeight.w600,
      color: c.muted,
      letterSpacing: 0.9,
    );
    final trailingStyle = style.copyWith(
      fontSize: AppType.t12,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    );
    Widget? end;
    if (onTrailingTap != null) {
      end = Semantics(
        button: true,
        label: trailingSemantics,
        child: InkWell(
          onTap: onTrailingTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (trailing != null) Text(trailing!, style: trailingStyle),
                if (trailing == null) Text('All', style: trailingStyle),
                if (trailingIcon) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, size: 14, color: c.muted),
                ],
              ],
            ),
          ),
        ),
      );
    } else if (trailing != null) {
      end = Text(trailing!, style: trailingStyle);
    }
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 28),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ?end,
          ],
        ),
      ),
    );
  }
}

/// The calm surface every Home (and Finance) block sits on: radius 18, a
/// hairline border, no shadow.
class HomeCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  const HomeCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final card = Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: c.border.withValues(alpha: 0.8)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
    if (semanticsLabel == null) return card;
    return Semantics(button: true, label: semanticsLabel, child: card);
  }
}

// ── capture ────────────────────────────────────────────────────────────────

/// The one primary action on Home: say what is on your mind. Enter (or the
/// arrow) keeps it as a note; the checkbox key files it as a task.
class HomeCaptureBar extends StatefulWidget {
  final ValueChanged<String> onSaveNote;
  final ValueChanged<String> onAddTask;

  const HomeCaptureBar({
    super.key,
    required this.onSaveNote,
    required this.onAddTask,
  });

  @override
  State<HomeCaptureBar> createState() => _HomeCaptureBarState();
}

class _HomeCaptureBarState extends State<HomeCaptureBar> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  bool get _hasText => _ctrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit({required bool asTask}) {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    if (asTask) {
      widget.onAddTask(text);
    } else {
      widget.onSaveNote(text);
    }
    _ctrl.clear();
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final focused = _focus.hasFocus;
    return AnimatedContainer(
      duration: AppMotion.duration(context, AppMotion.base),
      curve: AppMotion.emphasized,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: focused ? c.fg.withValues(alpha: 0.4) : c.border,
          width: focused ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: c.fg.withValues(alpha: focused ? 0.08 : 0.03),
            blurRadius: focused ? 20 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 6, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                // Shift+Enter breaks a line; Enter alone saves.
                const SingleActivator(LogicalKeyboardKey.enter): () =>
                    _submit(asTask: false),
              },
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(asTask: false),
                // A tap elsewhere ends the edit; otherwise the caret lingers after
                // the keyboard is dismissed.
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                style: TextStyle(fontSize: 17, height: 1.35, color: c.fg),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  hintText: 'What’s on your mind?',
                  hintStyle: TextStyle(fontSize: 17, color: c.muted),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: AnimatedSwitcher(
              duration: AppMotion.duration(context, AppMotion.fast),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: _hasText
                  ? Row(
                      key: const ValueKey('actions'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Add as task',
                          onPressed: () => _submit(asTask: true),
                          icon: Icon(
                            Icons.check_box_outlined,
                            size: 22,
                            color: c.muted,
                          ),
                        ),
                        const SizedBox(width: 2),
                        IconButton.filled(
                          tooltip: 'Save note',
                          onPressed: () => _submit(asTask: false),
                          style: IconButton.styleFrom(
                            backgroundColor: c.fg,
                            foregroundColor: c.surface,
                            fixedSize: const Size(40, 40),
                            shape: const CircleBorder(),
                          ),
                          icon: const Icon(
                            Icons.arrow_upward_rounded,
                            size: 20,
                          ),
                        ),
                      ],
                    )
                  : const SizedBox(key: ValueKey('none'), height: 44),
            ),
          ),
        ],
      ),
    );
  }
}

// ── next up ────────────────────────────────────────────────────────────────

/// One open checklist line.
class UpNextItem {
  final Note note;
  final int lineIndex;
  final String text;

  const UpNextItem({
    required this.note,
    required this.lineIndex,
    required this.text,
  });

  String get key => '${note.id}:$lineIndex';
}

/// One task at a time. The whole list never shows here — just the next
/// thing, a big target to finish it, and "Later" to set it aside for now
/// (session only; nothing is changed). Finishing slides the next one in.
class HomeNextUp extends StatefulWidget {
  final List<UpNextItem> items;
  final void Function(UpNextItem item) onComplete;
  final void Function(UpNextItem item) onOpen;
  final VoidCallback onViewAll;

  /// Tasks finished today; turns the empty state into an acknowledgement.
  final int doneToday;

  const HomeNextUp({
    super.key,
    required this.items,
    this.doneToday = 0,
    required this.onComplete,
    required this.onOpen,
    required this.onViewAll,
  });

  @override
  State<HomeNextUp> createState() => _HomeNextUpState();
}

class _HomeNextUpState extends State<HomeNextUp> {
  /// Set aside with "Later" this session; they come back after the rest.
  final _later = <String>[];
  String? _completing;

  List<UpNextItem> get _ordered {
    final now = widget.items.where((i) => !_later.contains(i.key)).toList();
    final later = [
      for (final key in _later) ...widget.items.where((i) => i.key == key),
    ];
    return [...now, ...later];
  }

  Future<void> _complete(UpNextItem item) async {
    if (_completing != null) return;
    HapticFeedback.selectionClick();
    setState(() => _completing = item.key);
    await Future<void>.delayed(
      AppMotion.duration(context, const Duration(milliseconds: 360)),
    );
    // Complete even if Home was left mid-animation: the check was shown, so
    // the tick must land. The callback belongs to the still-mounted shell.
    widget.onComplete(item);
    if (!mounted) return;
    setState(() {
      _completing = null;
      _later.remove(item.key);
    });
  }

  void _setAside(UpNextItem item) {
    HapticFeedback.selectionClick();
    setState(() {
      _later
        ..remove(item.key)
        ..add(item.key);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ordered = _ordered;
    final current = ordered.isEmpty ? null : ordered.first;
    final remaining = ordered.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeLabel(
          'NEXT UP',
          trailing: remaining > 1 ? '1 of $remaining' : null,
          onTrailingTap: remaining > 0 ? widget.onViewAll : null,
          trailingSemantics: 'See all tasks',
        ),
        AnimatedSwitcher(
          duration: AppMotion.duration(context, AppMotion.base),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, ?current],
          ),
          child: current == null
              ? _allClear(context)
              : KeyedSubtree(
                  key: ValueKey(current.key),
                  child: _taskCard(context, current, remaining),
                ),
        ),
      ],
    );
  }

  Widget _allClear(BuildContext context) {
    final c = context.colors;
    return HomeCard(
      key: const ValueKey('clear'),
      child: Row(
        children: [
          Icon(Icons.task_alt_rounded, size: 22, color: c.income),
          const SizedBox(width: 12),
          Expanded(
            child: widget.doneToday > 0
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'All clear.',
                        style: TextStyle(
                          fontSize: AppType.t15,
                          fontWeight: FontWeight.w600,
                          color: c.fg,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.doneToday == 1
                            ? 'You finished 1 task today.'
                            : 'You finished ${widget.doneToday} tasks today.',
                        style: TextStyle(
                          fontSize: AppType.t13_5,
                          color: c.muted,
                        ),
                      ),
                    ],
                  )
                : Text(
                    'Nothing waiting on you.',
                    style: TextStyle(fontSize: AppType.t15, color: c.muted),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _taskCard(BuildContext context, UpNextItem item, int remaining) {
    final c = context.colors;
    final done = _completing == item.key;
    final listName = item.note.title.isEmpty ? 'Untitled' : item.note.title;
    return HomeCard(
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TaskCheck(
                done: done,
                size: 24,
                semanticsLabel: 'Complete ${item.text}',
                onTap: () => _complete(item),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: InkWell(
                  onTap: () => widget.onOpen(item),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedDefaultTextStyle(
                          duration: AppMotion.duration(context, AppMotion.base),
                          style: TextStyle(
                            fontSize: 18,
                            height: 1.3,
                            fontWeight: FontWeight.w500,
                            color: done ? c.muted : c.fg,
                            decoration: done
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                            decorationColor: c.muted,
                          ),
                          child: Text(
                            item.text,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'in $listName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppType.t12,
                            color: c.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 52),
            // Wrap, not Row: large text or a narrow phone must never clip.
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                FilledButton(
                  onPressed: done ? null : () => _complete(item),
                  style: FilledButton.styleFrom(
                    backgroundColor: c.fg,
                    foregroundColor: c.surface,
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontSize: AppType.t13_5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Done'),
                ),
                if (remaining > 1)
                  TextButton(
                    onPressed: done ? null : () => _setAside(item),
                    style: TextButton.styleFrom(
                      foregroundColor: c.muted,
                      minimumSize: const Size(0, 40),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text('Later'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── continue ───────────────────────────────────────────────────────────────

/// The single note you were last working in — not a list to choose from.
class HomeContinueCard extends StatelessWidget {
  final Note note;
  final IconData icon;
  final String? subtitle;
  final String when;
  final VoidCallback onOpen;

  const HomeContinueCard({
    super.key,
    required this.note,
    required this.icon,
    required this.subtitle,
    required this.when,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = note.title.isEmpty ? 'Untitled' : note.title;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HomeLabel('PICK UP WHERE YOU LEFT OFF'),
        HomeCard(
          onTap: onOpen,
          semanticsLabel: 'Open $title',
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.listBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: c.muted),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppType.t15 + 1,
                        fontWeight: FontWeight.w600,
                        color: c.fg,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppType.t13_5,
                          color: c.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                when,
                style: TextStyle(fontSize: AppType.t12, color: c.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── evening ────────────────────────────────────────────────────────────────

/// After six, with nothing open: one gentle prompt to set up tomorrow, so
/// the next day starts with something ready instead of a blank page. What
/// you type lands in the Inbox; the prompt itself never nags or repeats.
class HomeWindDown extends StatelessWidget {
  final ValueChanged<String> onAdd;

  const HomeWindDown({super.key, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HomeLabel('FOR TOMORROW'),
        HomeCard(
          padding: const EdgeInsets.fromLTRB(4, 2, 10, 2),
          child: TaskAddRow(hint: 'Anything for tomorrow?', onSubmit: onAdd),
        ),
      ],
    );
  }
}

// ── resurface ──────────────────────────────────────────────────────────────

/// "From your notes": one older page, brought back for the day. A quiet
/// moment of rediscovery that makes Home worth opening; "Not today" puts it
/// away until tomorrow.
class HomeResurfaceCard extends StatelessWidget {
  final Note note;
  final String preview;
  final String age;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  const HomeResurfaceCard({
    super.key,
    required this.note,
    required this.preview,
    required this.age,
    required this.onOpen,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = note.title.isEmpty ? 'Untitled' : note.title;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeLabel(
          'FROM YOUR NOTES',
          trailing: 'Not today',
          onTrailingTap: onDismiss,
          trailingSemantics: 'Hide until tomorrow',
          trailingIcon: false,
        ),
        HomeCard(
          onTap: onOpen,
          semanticsLabel: 'Open $title, written $age',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                age.toUpperCase(),
                style: TextStyle(
                  fontSize: AppType.t11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: c.muted,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppType.t15 + 1,
                  fontWeight: FontWeight.w600,
                  color: c.fg,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                preview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppType.t15,
                  height: 1.45,
                  color: c.fg.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── money ──────────────────────────────────────────────────────────────────

/// Money as one quiet line; the dashboard is a tap away when you want it.
class HomeMoneyLine extends StatelessWidget {
  final String monthLabel;
  final bool hasData;
  final String currency;
  final int spent;
  final VoidCallback onOpen;

  const HomeMoneyLine({
    super.key,
    required this.monthLabel,
    required this.hasData,
    required this.currency,
    required this.spent,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final strong = TextStyle(
      fontSize: AppType.t15,
      fontWeight: FontWeight.w600,
      color: c.fg,
    );
    final quiet = TextStyle(fontSize: AppType.t15, color: c.muted);
    return Semantics(
      button: true,
      label: hasData
          ? '${formatMinorAmount(spent, currency)} spent in $monthLabel. '
                'Open Finance'
          : 'Nothing spent in $monthLabel yet. Open Finance',
      excludeSemantics: true,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 18,
                color: c.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: hasData
                        ? [
                            ...moneySpans(spent, currency, strong),
                            TextSpan(
                              text: ' spent in $monthLabel',
                              style: quiet,
                            ),
                          ]
                        : [
                            TextSpan(
                              text: 'Nothing spent in $monthLabel yet',
                              style: quiet,
                            ),
                          ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.arrow_forward_rounded, size: 18, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }
}
