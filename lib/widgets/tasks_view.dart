import 'package:flutter/material.dart';

import '../models/note.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../utils/markdown_display.dart';
import 'task_row.dart';

/// The Tasks tab: every open task in one place, grouped by list. Each list
/// is one card — a chunk you can take in at a glance — with its open tasks
/// tickable in place, a quiet line to add another, and done ones folded
/// away. Lists that are all done sink to the bottom as a single line.
class TasksView extends StatefulWidget {
  final List<Note> lists;
  final void Function(Note note, int lineIndex, bool done) onToggle;
  final void Function(Note note) onOpenList;
  final void Function(Note note, String text) onAddTask;
  final VoidCallback onNewList;

  /// Desktop, nothing open: the view owns the main canvas, so it sits on the
  /// page background with Home's roomier top margin.
  final bool fullCanvas;

  const TasksView({
    super.key,
    required this.lists,
    required this.onToggle,
    required this.onOpenList,
    required this.onAddTask,
    required this.onNewList,
    this.fullCanvas = false,
  });

  @override
  State<TasksView> createState() => _TasksViewState();
}

class _TasksViewState extends State<TasksView> {
  /// Open tasks shown per list before "Show N more".
  static const _preview = 6;

  final _expanded = <String>{};
  final _showDone = <String>{};

  /// List order frozen for the life of the view: adding to or ticking in a
  /// list bumps its edit time, and re-sorting then yanked the card out from
  /// under the finger. New lists join at the top; vanished ones drop out.
  final _order = <String>[];

  List<Note> _stable(List<Note> lists) {
    final ids = lists.map((n) => n.id).toSet();
    _order.removeWhere((id) => !ids.contains(id));
    final fresh = [
      for (final n in lists)
        if (!_order.contains(n.id)) n.id,
    ];
    _order.insertAll(0, fresh);
    final byId = {for (final n in lists) n.id: n};
    return [for (final id in _order) byId[id]!];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final groups = [
      for (final note in _stable(widget.lists))
        (
          note,
          parseChecklist(note.content).where((i) => i.text.isNotEmpty).toList(),
        ),
    ];
    final active = groups
        .where((g) => g.$2.isEmpty || g.$2.any((i) => !i.done))
        .toList();
    final finished = groups
        .where((g) => g.$2.isNotEmpty && g.$2.every((i) => i.done))
        .toList();
    final openCount = groups.fold<int>(
      0,
      (sum, g) => sum + g.$2.where((i) => !i.done).length,
    );

    return ColoredBox(
      color: widget.fullCanvas ? c.bg : c.listBg,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              widget.fullCanvas ? 56 : 16,
              16,
              24 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              _summary(context, openCount, groups.length),
              const SizedBox(height: 12),
              if (groups.isEmpty) _empty(context),
              for (final (note, items) in active) ...[
                KeyedSubtree(
                  key: ValueKey('list-${note.id}'),
                  child: _listCard(context, note, items),
                ),
                const SizedBox(height: 16),
              ],
              if (finished.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    'ALL DONE',
                    style: TextStyle(
                      fontSize: AppType.t11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.9,
                      color: c.muted,
                    ),
                  ),
                ),
                for (final (note, items) in finished)
                  _finishedRow(context, note, items.length),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _summary(BuildContext context, int open, int lists) {
    final c = context.colors;
    final text = lists == 0
        ? 'No lists yet'
        : open == 0
        ? 'Nothing open'
        : '$open open · ${lists == 1 ? '1 list' : '$lists lists'}';
    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: AppType.t13_5, color: c.muted),
            ),
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: widget.onNewList,
          icon: Icon(Icons.add_rounded, size: 18, color: c.fg),
          label: Text(
            'New list',
            style: TextStyle(
              fontSize: AppType.t13_5,
              fontWeight: FontWeight.w500,
              color: c.fg,
            ),
          ),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 40),
            shape: const StadiumBorder(),
          ),
        ),
      ],
    );
  }

  Widget _empty(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          Icon(Icons.task_alt_rounded, size: 32, color: c.muted),
          const SizedBox(height: 12),
          Text(
            'Lists you make show up here, every open task in one place.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppType.t15,
              height: 1.45,
              color: c.muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, Widget child) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.border.withValues(alpha: 0.8)),
      ),
      child: child,
    );
  }

  Widget _listCard(BuildContext context, Note note, List<ChecklistItem> items) {
    final c = context.colors;
    final title = note.title.isEmpty ? 'Untitled' : note.title;
    final open = items.where((i) => !i.done).toList();
    final done = items.where((i) => i.done).toList();
    final expanded = _expanded.contains(note.id);
    final shown = expanded ? open : open.take(_preview).toList();
    final hidden = open.length - shown.length;
    final showDone = _showDone.contains(note.id);

    return _card(
      context,
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              label: 'Open $title',
              excludeSemantics: true,
              child: InkWell(
                onTap: () => widget.onOpenList(note),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppType.t15 + 1,
                            fontWeight: FontWeight.w600,
                            color: c.fg,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        open.isEmpty ? 'Empty' : '${open.length} open',
                        style: TextStyle(fontSize: AppType.t12, color: c.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            for (final item in shown)
              TaskRow(
                key: ValueKey('${note.id}:${item.lineIndex}'),
                done: false,
                text: stripInlineMarkdown(item.text),
                onToggle: () => widget.onToggle(note, item.lineIndex, true),
                onTap: () => widget.onOpenList(note),
              ),
            if (hidden > 0)
              _quietButton(
                context,
                'Show $hidden more',
                () => setState(() => _expanded.add(note.id)),
              ),
            TaskAddRow(
              key: ValueKey('add-${note.id}'),
              hint: 'Add a task',
              dense: true,
              onSubmit: (text) => widget.onAddTask(note, text),
            ),
            if (done.isNotEmpty) ...[
              TaskCompletedToggle(
                count: done.length,
                expanded: showDone,
                onToggle: () => setState(() {
                  if (!_showDone.remove(note.id)) _showDone.add(note.id);
                }),
              ),
              if (showDone)
                for (final item in done)
                  TaskRow(
                    key: ValueKey('${note.id}:${item.lineIndex}'),
                    done: true,
                    dense: true,
                    text: stripInlineMarkdown(item.text),
                    onToggle: () =>
                        widget.onToggle(note, item.lineIndex, false),
                    onTap: () => widget.onOpenList(note),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _finishedRow(BuildContext context, Note note, int count) {
    final c = context.colors;
    final title = note.title.isEmpty ? 'Untitled' : note.title;
    return InkWell(
      onTap: () => widget.onOpenList(note),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, size: 18, color: c.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppType.t15, color: c.muted),
              ),
            ),
            Text(
              '$count done',
              style: TextStyle(fontSize: AppType.t12, color: c.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quietButton(BuildContext context, String label, VoidCallback onTap) {
    final c = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 40),
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: c.muted,
            minimumSize: const Size(0, 36),
          ),
          child: Text(label),
        ),
      ),
    );
  }
}
