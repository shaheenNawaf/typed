import 'package:flutter/material.dart';
import '../models/note.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';

class ContextPanel extends StatelessWidget {
  final Note note;
  final VoidCallback onClose;
  final VoidCallback? onTogglePin;
  final VoidCallback? onArchive;
  final VoidCallback? onDelete;
  final ValueChanged<String>? onTypeChange;
  final ValueChanged<String>? onTagFilter;
  final List<Note> allNotes;
  final ValueChanged<String>? onOpenNote;

  const ContextPanel({
    super.key,
    required this.note,
    required this.onClose,
    this.onTogglePin,
    this.onArchive,
    this.onDelete,
    this.onTypeChange,
    this.onTagFilter,
    this.allNotes = const [],
    this.onOpenNote,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wordCount = note.content.trim().isEmpty
        ? 0
        : note.content.trim().split(RegExp(r'\s+')).length;
    final typeLabel = switch (note.type) {
      'todo' => 'Task list',
      'expense' => 'Expense',
      'income' => 'Income',
      _ => 'Note',
    };
    final linkedNotes = _linkedNotes(note, allNotes);
    final backlinks = _backlinks(note, allNotes);

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(left: BorderSide(color: c.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 10, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'PAGE DETAILS',
                    style: TextStyle(
                      color: c.muted,
                      fontSize: AppType.t10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.12,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  tooltip: 'Close details',
                  icon: Icon(Icons.close, size: 18, color: c.muted),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.border),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              children: [
                Text(
                  note.title.trim().isEmpty ? 'Untitled' : note.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 18),
                _TypeProperty(
                  value: typeLabel,
                  currentType: note.type,
                  onChanged: onTypeChange,
                ),
                _PropertyRow(
                  label: 'Created',
                  value: _formatDate(note.createdAt),
                ),
                _PropertyRow(
                  label: 'Updated',
                  value: _formatDate(note.updatedAt),
                ),
                _PropertyRow(label: 'Words', value: '$wordCount'),
                if (note.amounts.isNotEmpty)
                  _PropertyRow(
                    label: 'Entries',
                    value: '${note.amounts.length}',
                  ),
                if (note.tags.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Text(
                    'TAGS',
                    style: TextStyle(
                      color: c.muted,
                      fontSize: AppType.t10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: note.tags
                        .map(
                          (tag) => InkWell(
                            onTap: onTagFilter == null
                                ? null
                                : () => onTagFilter!(tag),
                            borderRadius: BorderRadius.circular(5),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: c.tagBg,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                '#$tag',
                                style: TextStyle(
                                  color: c.tagFg,
                                  fontSize: AppType.t11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
                if (linkedNotes.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _SectionLabel(label: 'LINKED PAGES'),
                  const SizedBox(height: 8),
                  ...linkedNotes.map(
                    (linked) => _PageLink(
                      note: linked,
                      onTap: onOpenNote == null
                          ? null
                          : () => onOpenNote!(linked.id),
                    ),
                  ),
                ],
                if (backlinks.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _SectionLabel(label: 'BACKLINKS'),
                  const SizedBox(height: 8),
                  ...backlinks.map(
                    (backlink) => _PageLink(
                      note: backlink,
                      onTap: onOpenNote == null
                          ? null
                          : () => onOpenNote!(backlink.id),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: c.border),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                if (onTogglePin != null)
                  _PanelAction(
                    icon: note.isPinned
                        ? Icons.push_pin
                        : Icons.push_pin_outlined,
                    tooltip: note.isPinned ? 'Unpin page' : 'Pin page',
                    onPressed: onTogglePin!,
                  ),
                if (onArchive != null)
                  _PanelAction(
                    icon: Icons.archive_outlined,
                    tooltip: 'Archive page',
                    onPressed: onArchive!,
                  ),
                if (onDelete != null)
                  _PanelAction(
                    icon: Icons.delete_outline,
                    tooltip: 'Move to trash',
                    onPressed: onDelete!,
                    color: c.destructive,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.month}/${local.day}/${local.year}';
  }

  List<Note> _linkedNotes(Note source, List<Note> notes) {
    final linkedIds = _linkTargets(source.content);
    return notes
        .where((candidate) =>
            candidate.id != source.id &&
            (linkedIds.contains(candidate.id) ||
                linkedIds.contains(candidate.title)))
        .toList();
  }

  List<Note> _backlinks(Note target, List<Note> notes) {
    return notes
        .where((candidate) =>
            candidate.id != target.id &&
            (_linkTargets(candidate.content).contains(target.id) ||
                _linkTargets(candidate.content).contains(target.title)))
        .toList();
  }

  Set<String> _linkTargets(String content) {
    final targets = <String>{};
    final pattern = RegExp(r'\[\[([^\]\n|]+)(?:\|[^\]\n]+)?\]\]');
    for (final match in pattern.allMatches(content)) {
      targets.add(match.group(1)!.trim());
    }
    return targets;
  }
}

class _TypeProperty extends StatelessWidget {
  final String value;
  final String currentType;
  final ValueChanged<String>? onChanged;

  const _TypeProperty({
    required this.value,
    required this.currentType,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (onChanged == null) {
      return _PropertyRow(label: 'Type', value: value);
    }
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text('Type', style: TextStyle(fontSize: AppType.t12, color: c.muted)),
          ),
          Expanded(
            child: PopupMenuButton<String>(
              initialValue: currentType,
              onSelected: onChanged,
              tooltip: 'Change page type',
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'text', child: Text('Note')),
                PopupMenuItem(value: 'todo', child: Text('Task list')),
                PopupMenuItem(value: 'expense', child: Text('Expense')),
                PopupMenuItem(value: 'income', child: Text('Income')),
              ],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: AppType.t12,
                      color: c.fg,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Icon(Icons.expand_more, size: 16, color: c.muted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Text(
      label,
      style: TextStyle(
        color: c.muted,
        fontSize: AppType.t10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.12,
      ),
    );
  }
}

class _PageLink extends StatelessWidget {
  final Note note;
  final VoidCallback? onTap;

  const _PageLink({required this.note, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: c.listBg,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              Icon(Icons.article_outlined, size: 15, color: c.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  note.title.trim().isEmpty ? 'Untitled' : note.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: AppType.t12, color: c.fg),
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right, size: 15, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _PropertyRow extends StatelessWidget {
  final String label;
  final String value;

  const _PropertyRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: TextStyle(fontSize: AppType.t12, color: c.muted)),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: AppType.t12,
                color: c.fg,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  const _PanelAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 18, color: color ?? context.colors.muted),
      visualDensity: VisualDensity.compact,
    );
  }
}
