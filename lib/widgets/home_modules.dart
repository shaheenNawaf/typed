import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../home/today_plan.dart';
import '../models/note.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../theme/app_motion.dart';
import '../utils/cutoff.dart';
import '../utils/date_format.dart';
import '../utils/finance_utils.dart';
import 'task_row.dart';

/// Home's modules, built for focus. Each block holds one kind of thing — a
/// place to capture, today's tasks with one first, what's left until
/// payday — so there is always a single obvious next step.
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

  /// Opens a voice memo; null hides the mic (unsupported platform).
  final VoidCallback? onVoice;

  const HomeCaptureBar({
    super.key,
    required this.onSaveNote,
    required this.onAddTask,
    this.onVoice,
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
                  : widget.onVoice != null
                  // Empty bar: talk instead of type.
                  ? IconButton(
                      key: const ValueKey('voice'),
                      tooltip: 'Voice memo',
                      onPressed: widget.onVoice,
                      icon: Icon(
                        Icons.mic_none_rounded,
                        size: 22,
                        color: c.muted,
                      ),
                    )
                  : const SizedBox(key: ValueKey('none'), height: 44),
            ),
          ),
        ],
      ),
    );
  }
}

// ── today ──────────────────────────────────────────────────────────────────

/// Today: the one task to do first (overdue, then by time), with the rest
/// of the day under it grouped by time of day. On a quiet day it says so
/// and offers a couple of undated tasks to take on.
class HomeToday extends StatefulWidget {
  final TodayPlan plan;
  final DateTime now;

  /// Tasks finished today; turns the empty state into an acknowledgement.
  final int doneToday;

  /// `noteId|line` for tasks with a reminder (a bell on their row).
  final Set<String> reminders;

  final void Function(TodayItem item) onComplete;
  final void Function(TodayItem item) onTomorrow;
  final void Function(TodayItem item) onDoToday;
  final void Function(TodayItem item) onOpen;
  final VoidCallback onViewAll;

  const HomeToday({
    super.key,
    required this.plan,
    required this.now,
    this.doneToday = 0,
    this.reminders = const {},
    required this.onComplete,
    required this.onTomorrow,
    required this.onDoToday,
    required this.onOpen,
    required this.onViewAll,
  });

  @override
  State<HomeToday> createState() => _HomeTodayState();
}

class _HomeTodayState extends State<HomeToday> {
  String? _completing;

  Future<void> _complete(TodayItem item) async {
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
    setState(() => _completing = null);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final plan = widget.plan;
    final focus = plan.focus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeLabel(
          'TODAY',
          trailing: plan.isEmpty ? null : 'All tasks',
          onTrailingTap: plan.isEmpty ? null : widget.onViewAll,
          trailingSemantics: 'See all tasks',
        ),
        HomeCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                child: focus == null
                    ? KeyedSubtree(
                        key: const ValueKey('quiet'),
                        child: _quiet(context),
                      )
                    : KeyedSubtree(
                        key: ValueKey(focus.key),
                        child: _focusCard(context, focus),
                      ),
              ),
              if (focus != null && plan.rest.isNotEmpty) ...[
                Divider(height: 1, thickness: 1, color: c.border),
                HomeTaskRows(
                  items: plan.rest,
                  now: widget.now,
                  reminders: widget.reminders,
                  onOpen: widget.onOpen,
                  onMore: widget.onViewAll,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── focus card ──

  Widget _focusCard(BuildContext context, TodayItem item) {
    final c = context.colors;
    final done = _completing == item.key;
    final listName = item.note.title.isEmpty ? 'Untitled' : item.note.title;
    final chip = _chip(context, item);
    return Padding(
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
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ?chip,
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
                TextButton(
                  onPressed: done
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          widget.onTomorrow(item);
                        },
                  style: TextButton.styleFrom(
                    foregroundColor: c.muted,
                    minimumSize: const Size(0, 40),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('Tomorrow'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "Due yesterday" (overdue), "2:00 PM" (timed), "Today" (dated, no time).
  Widget? _chip(BuildContext context, TodayItem item) {
    final c = context.colors;
    final (String text, Color color) = switch (item.standing) {
      TaskStanding.overdue => (
        'Due ${dueLabel(item.when!.day, widget.now)}',
        c.warning,
      ),
      TaskStanding.today when item.hasTime => (item.timeLabel, c.accent),
      TaskStanding.today => ('Today', c.accent),
      _ => ('', c.muted),
    };
    if (text.isEmpty) return null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  // ── quiet day ──

  Widget _quiet(BuildContext context) {
    final c = context.colors;
    final plan = widget.plan;
    final done = widget.doneToday;
    final undated = plan.undated.length;
    final String title;
    final String? sub;
    if (done > 0) {
      title = 'All clear.';
      sub = done == 1
          ? 'You finished 1 task today.'
          : 'You finished $done tasks today.';
    } else if (undated > 0) {
      title = 'Nothing due today.';
      sub = undated == 1
          ? '1 task in your lists has no date.'
          : '$undated tasks in your lists have no date.';
    } else {
      title = 'Nothing waiting on you.';
      sub = null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(Icons.task_alt_rounded, size: 22, color: c.income),
              const SizedBox(width: 12),
              Expanded(
                child: sub == null
                    ? Text(
                        title,
                        style: TextStyle(fontSize: AppType.t15, color: c.muted),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: AppType.t15,
                              fontWeight: FontWeight.w600,
                              color: c.fg,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            sub,
                            style: TextStyle(
                              fontSize: AppType.t13_5,
                              color: c.muted,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
        for (final item in plan.undated.take(2)) ...[
          Divider(height: 1, thickness: 1, color: c.border),
          _suggestion(context, item),
        ],
      ],
    );
  }

  /// An undated task offered for today: tick it off, or take it on.
  Widget _suggestion(BuildContext context, TodayItem item) {
    final c = context.colors;
    final done = _completing == item.key;
    final listName = item.note.title.isEmpty ? 'Untitled' : item.note.title;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
      child: Row(
        children: [
          TaskCheck(
            done: done,
            semanticsLabel: 'Complete ${item.text}',
            onTap: () => _complete(item),
          ),
          Expanded(
            child: InkWell(
              onTap: () => widget.onOpen(item),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppType.t15,
                        color: done ? c.muted : c.fg,
                        decoration: done
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        decorationColor: c.muted,
                      ),
                    ),
                    Text(
                      listName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppType.t12, color: c.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: done
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    widget.onDoToday(item);
                  },
            style: OutlinedButton.styleFrom(
              foregroundColor: c.fg,
              side: BorderSide(color: c.border),
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(
                fontSize: AppType.t12,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('Do today'),
          ),
        ],
      ),
    );
  }
}

/// Tasks grouped by time of day (Any time, Morning, Afternoon, Evening):
/// text on the left, the time and a reminder bell on the right. Tapping a
/// row opens its list.
class HomeTaskRows extends StatelessWidget {
  final List<TodayItem> items;
  final DateTime now;
  final Set<String> reminders;
  final void Function(TodayItem item) onOpen;

  /// Opens everything when rows are cut off ("+3 more").
  final VoidCallback onMore;
  final int maxRows;

  const HomeTaskRows({
    super.key,
    required this.items,
    required this.now,
    this.reminders = const {},
    required this.onOpen,
    required this.onMore,
    this.maxRows = 6,
  });

  @override
  Widget build(BuildContext context) {
    final rest = items;
    final c = context.colors;
    final shown = rest.take(maxRows).toList();
    final hidden = rest.length - shown.length;
    final children = <Widget>[];
    TodayGroup? group;
    for (final item in shown) {
      if (item.group != group) {
        group = item.group;
        children.add(
          Padding(
            padding: EdgeInsets.fromLTRB(18, children.isEmpty ? 10 : 12, 18, 2),
            child: Text(
              kTodayGroupNames[group]!.toUpperCase(),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: c.muted,
              ),
            ),
          ),
        );
      }
      children.add(_row(context, item));
    }
    if (hidden > 0) {
      children.add(
        InkWell(
          onTap: onMore,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
            child: Text(
              '+$hidden more',
              style: TextStyle(fontSize: AppType.t13_5, color: c.muted),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _row(BuildContext context, TodayItem item) {
    final c = context.colors;
    final overdue = item.standing == TaskStanding.overdue;
    final due = overdue ? dueLabel(item.when!.day, now) : '';
    final time = overdue
        ? '${due[0].toUpperCase()}${due.substring(1)}'
        : item.timeLabel;
    final bell = reminders.contains('${item.note.id}|${item.raw}');
    return Semantics(
      button: true,
      label: [
        item.text,
        if (time.isNotEmpty) time,
        if (bell) 'reminder set',
      ].join(', '),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => onOpen(item),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppType.t15, color: c.fg),
                ),
              ),
              if (time.isNotEmpty) ...[
                const SizedBox(width: 10),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 13,
                    color: overdue ? c.warning : c.muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              if (bell) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.notifications_none_rounded,
                  size: 16,
                  color: c.accent,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "yesterday", "Tue" (within the week), "Nov 2" (earlier).
String dueLabel(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(day.year, day.month, day.day);
  final ago = today.difference(d).inDays;
  if (ago == 1) return 'yesterday';
  if (ago > 1 && ago < 7) return kWeekdayNamesShort[d.weekday - 1];
  return '${monthShort(d.month)} ${d.day}';
}

// ── recent ─────────────────────────────────────────────────────────────────

/// One row in [HomeRecent].
class RecentItem {
  final Note note;
  final IconData icon;
  final String? subtitle;
  final String when;

  const RecentItem({
    required this.note,
    required this.icon,
    required this.subtitle,
    required this.when,
  });
}

/// The last few pages you worked in — notes, lists and voice memos — so
/// Home always has something of yours to return to.
class HomeRecent extends StatelessWidget {
  final List<RecentItem> items;
  final void Function(Note note) onOpen;
  final VoidCallback onViewAll;

  const HomeRecent({
    super.key,
    required this.items,
    required this.onOpen,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeLabel(
          'RECENT',
          trailing: 'All notes',
          onTrailingTap: onViewAll,
          trailingSemantics: 'See all notes',
        ),
        HomeCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: c.border),
                _row(context, items[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, RecentItem item) {
    final c = context.colors;
    final title = item.note.title.isEmpty ? 'Untitled' : item.note.title;
    return Semantics(
      button: true,
      label: 'Open $title',
      child: InkWell(
        onTap: () => onOpen(item.note),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.listBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, size: 20, color: c.muted),
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
                    if (item.subtitle != null && item.subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.subtitle!,
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
                item.when,
                style: TextStyle(fontSize: AppType.t12, color: c.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── evening ────────────────────────────────────────────────────────────────

/// After six, what today didn't get to — moved to tomorrow in one tap, or
/// left where it is. Never more than a gentle offer.
class HomeLeftovers extends StatelessWidget {
  final List<TodayItem> items;
  final VoidCallback onMoveAll;
  final VoidCallback onLeave;
  final void Function(TodayItem item) onOpen;

  const HomeLeftovers({
    super.key,
    required this.items,
    required this.onMoveAll,
    required this.onLeave,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = items.take(4).toList();
    final more = items.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HomeLabel('LEFT FROM TODAY'),
        HomeCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 6),
              for (final item in shown)
                InkWell(
                  onTap: () => onOpen(item),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: AppType.t15, color: c.fg),
                        ),
                        Text(
                          item.note.title.isEmpty
                              ? 'Untitled'
                              : item.note.title,
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
              if (more > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
                  child: Text(
                    '+$more more',
                    style: TextStyle(fontSize: AppType.t13_5, color: c.muted),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    FilledButton(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        onMoveAll();
                      },
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
                      child: const Text('Move to tomorrow'),
                    ),
                    TextButton(
                      onPressed: onLeave,
                      style: TextButton.styleFrom(
                        foregroundColor: c.muted,
                        minimumSize: const Size(0, 40),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Leave it'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tomorrow at a glance, grouped like Today, with a line to add to it —
/// so the next day starts with something ready instead of a blank page.
class HomeTomorrow extends StatelessWidget {
  final DateTime day;
  final List<TodayItem> items;
  final DateTime now;
  final Set<String> reminders;
  final void Function(TodayItem item) onOpen;
  final VoidCallback onViewAll;
  final ValueChanged<String> onAdd;

  const HomeTomorrow({
    super.key,
    required this.day,
    required this.items,
    required this.now,
    this.reminders = const {},
    required this.onOpen,
    required this.onViewAll,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final label =
        '${kWeekdayNamesShort[day.weekday - 1]}, ${monthShort(day.month)} '
        '${day.day}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeLabel(
          'TOMORROW · ${label.toUpperCase()}',
          trailing: 'All tasks',
          onTrailingTap: onViewAll,
          trailingSemantics: 'See all tasks',
        ),
        HomeCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (items.isNotEmpty)
                HomeTaskRows(
                  items: items,
                  now: now,
                  reminders: reminders,
                  onOpen: onOpen,
                  onMore: onViewAll,
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 10, 2),
                child: TaskAddRow(
                  hint: 'Add something for tomorrow',
                  onSubmit: onAdd,
                ),
              ),
            ],
          ),
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

// ── money until payday ─────────────────────────────────────────────────────

/// "Will it last until payday?" — one figure: what's left until the next
/// payday, a daily amount, and whether spending is on pace. Without a
/// budget it says what has been spent since payday. The Finance tab is a
/// tap away for everything else.
class HomePaydayCard extends StatelessWidget {
  final CutoffMoney money;
  final DateTime now;
  final VoidCallback onOpen;
  final VoidCallback onSetBudget;

  const HomePaydayCard({
    super.key,
    required this.money,
    required this.now,
    required this.onOpen,
    required this.onSetBudget,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cur = money.currency;
    final big = TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6,
      color: c.fg,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final quiet = TextStyle(
      fontSize: AppType.t15,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: c.muted,
    );
    final small = TextStyle(fontSize: 13, color: c.muted);
    final payday = ordinal(money.cutoff.nextPayday.day);
    final budget = money.budget;
    final evening = now.hour >= 18 && money.todaySpent > 0;
    final days = money.daysLeft;

    final List<Widget> body;
    if (budget == null) {
      body = [
        Text.rich(
          TextSpan(
            children: [
              ...wholeMoneySpans(money.spent, cur, big),
              TextSpan(
                text:
                    ' spent since ${monthShort(money.cutoff.start.month)} '
                    '${money.cutoff.start.day}',
                style: quiet,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                evening
                    ? '${formatWholeAmount(money.todaySpent, cur)} logged today'
                    : 'About ${formatWholeAmount(money.perDaySpent, cur)} a day '
                          '· payday on the $payday',
                style: small,
              ),
            ),
            TextButton(
              onPressed: onSetBudget,
              style: TextButton.styleFrom(
                foregroundColor: c.fg,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: const TextStyle(
                  fontSize: AppType.t12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('Set a budget'),
            ),
          ],
        ),
      ];
    } else {
      final status = money.status;
      final over = status == PaceStatus.overBudget;
      final left = money.left!;
      body = [
        Text.rich(
          TextSpan(
            children: [
              ...wholeMoneySpans(over ? -left : left, cur, big),
              TextSpan(
                text: over ? ' over budget' : ' left until the $payday',
                style: quiet,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        PaceBar(
          spent: money.spent,
          budget: budget.amount,
          ideal: money.ideal,
          status: status,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                evening
                    ? '${formatWholeAmount(money.todaySpent, cur)} logged today'
                    : over
                    ? '$days ${days == 1 ? 'day' : 'days'} until payday'
                    : 'About ${formatWholeAmount(money.perDayLeft!, cur)} a day '
                          'for $days ${days == 1 ? 'day' : 'days'}',
                style: small,
              ),
            ),
            _paceBadge(context, money),
          ],
        ),
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeLabel(
          'UNTIL PAYDAY',
          trailing: 'Money',
          onTrailingTap: onOpen,
          trailingSemantics: 'Open Finance',
        ),
        HomeCard(
          onTap: onOpen,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: body,
          ),
        ),
      ],
    );
  }

  Widget _paceBadge(BuildContext context, CutoffMoney money) {
    final c = context.colors;
    final (String text, Color color, IconData? icon) = switch (money.status) {
      PaceStatus.onPace => ('On pace', c.income, Icons.check_rounded),
      PaceStatus.overPace => (
        '${formatWholeAmount(money.spent - money.ideal!, money.currency)} over pace',
        c.warning,
        null,
      ),
      PaceStatus.overBudget => ('Over budget', c.expense, null),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 3),
        ],
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Spent against a budget, with a tick where an even pace would be today.
class PaceBar extends StatelessWidget {
  final int spent;
  final int budget;
  final int? ideal;
  final PaceStatus status;

  const PaceBar({
    super.key,
    required this.spent,
    required this.budget,
    this.ideal,
    this.status = PaceStatus.onPace,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fill = budget <= 0 ? 1.0 : (spent / budget).clamp(0.0, 1.0);
    final tick = ideal == null || budget <= 0
        ? null
        : (ideal! / budget).clamp(0.0, 1.0);
    final color = switch (status) {
      PaceStatus.onPace => c.fg.withValues(alpha: 0.85),
      PaceStatus.overPace => c.warning,
      PaceStatus.overBudget => c.expense,
    };
    return SizedBox(
      height: 14,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: c.fg.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Container(
                width: w * fill,
                height: 6,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              if (tick != null)
                Positioned(
                  left: (w * tick - 1).clamp(0.0, w - 2),
                  child: Container(
                    width: 2,
                    height: 14,
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// On payday: how the last cutoff went, and a fresh start.
class HomePaydaySummary extends StatelessWidget {
  final CutoffMoney last;
  final VoidCallback onStart;
  final VoidCallback onLater;
  final VoidCallback onOpen;

  const HomePaydaySummary({
    super.key,
    required this.last,
    required this.onStart,
    required this.onLater,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cur = last.currency;
    final budget = last.budget;
    final left = last.left;
    final big = TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6,
      color: c.fg,
    );
    final quiet = TextStyle(
      fontSize: AppType.t15,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: c.muted,
    );
    final top = last.topCategory;
    final detail = [
      if (budget != null)
        '${formatWholeAmount(last.spent, cur)} of '
            '${formatWholeAmount(budget.amount, cur)}',
      if (top != null) budget == null ? 'Most on $top' : 'most on $top',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeLabel(
          'PAYDAY',
          trailing: 'Money',
          onTrailingTap: onOpen,
          trailingSemantics: 'Open Finance',
        ),
        HomeCard(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Last cutoff · ${last.cutoff.rangeLabel}',
                style: TextStyle(fontSize: 13, color: c.muted),
              ),
              const SizedBox(height: 2),
              Text.rich(
                TextSpan(
                  children: left == null
                      ? [
                          ...wholeMoneySpans(last.spent, cur, big),
                          TextSpan(text: ' spent', style: quiet),
                        ]
                      : left >= 0
                      ? [
                          ...wholeMoneySpans(
                            left,
                            cur,
                            big.copyWith(color: c.income),
                          ),
                          TextSpan(text: ' kept', style: quiet),
                        ]
                      : [
                          ...wholeMoneySpans(
                            -left,
                            cur,
                            big.copyWith(color: c.warning),
                          ),
                          TextSpan(text: ' over', style: quiet),
                        ],
                ),
              ),
              if (budget != null) ...[
                const SizedBox(height: 10),
                PaceBar(
                  spent: last.spent,
                  budget: budget.amount,
                  status: left! >= 0
                      ? PaceStatus.onPace
                      : PaceStatus.overBudget,
                ),
              ],
              if (detail.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(detail, style: TextStyle(fontSize: 13, color: c.muted)),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  FilledButton(
                    onPressed: onStart,
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
                    child: Text(
                      budget == null ? 'Set a budget' : 'Start new cutoff',
                    ),
                  ),
                  TextButton(
                    onPressed: onLater,
                    style: TextButton.styleFrom(
                      foregroundColor: c.muted,
                      minimumSize: const Size(0, 40),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text('Later'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
