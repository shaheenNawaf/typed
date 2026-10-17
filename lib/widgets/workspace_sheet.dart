import 'package:flutter/material.dart';

import '../models/note.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import 'brand_mark.dart';

/// Phone navigation beyond the dock, as a bottom sheet instead of a side
/// drawer: it rises from where your thumb already is, and holds only what
/// the dock doesn't — the other spaces, pinned pages, tags, and Settings.
class WorkspaceSheet extends StatelessWidget {
  final String activeFilter;
  final String? activeTag;
  final Map<String, int> counts;
  final List<Note> pinnedNotes;
  final List<String> tags;
  final Map<String, int> tagCounts;
  final ValueChanged<String> onFilter;
  final ValueChanged<String> onTag;
  final ValueChanged<String> onNote;
  final VoidCallback onSettings;

  /// The draggable sheet's controller, so dragging and scrolling hand off.
  final ScrollController? scrollController;

  const WorkspaceSheet({
    super.key,
    required this.activeFilter,
    required this.activeTag,
    required this.counts,
    required this.pinnedNotes,
    required this.tags,
    required this.tagCounts,
    required this.onFilter,
    required this.onTag,
    required this.onNote,
    required this.onSettings,
    this.scrollController,
  });

  /// Opens the sheet; every action closes it first, then acts.
  static Future<void> show(
    BuildContext context, {
    required String activeFilter,
    required String? activeTag,
    required Map<String, int> counts,
    required List<Note> pinnedNotes,
    required List<String> tags,
    required Map<String, int> tagCounts,
    required ValueChanged<String> onFilter,
    required ValueChanged<String> onTag,
    required ValueChanged<String> onNote,
    required VoidCallback onSettings,
  }) {
    final c = context.colors;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: c.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheet) {
        void then(VoidCallback action) {
          Navigator.pop(sheet);
          action();
        }

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.62,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (context, scroll) => WorkspaceSheet(
            activeFilter: activeFilter,
            activeTag: activeTag,
            counts: counts,
            pinnedNotes: pinnedNotes,
            tags: tags,
            tagCounts: tagCounts,
            onFilter: (f) => then(() => onFilter(f)),
            onTag: (t) => then(() => onTag(t)),
            onNote: (id) => then(() => onNote(id)),
            onSettings: () => then(onSettings),
            scrollController: scroll,
          ),
        );
      },
    );
  }

  static const _spaces = [
    ('meeting', Icons.groups_outlined, 'Meetings'),
    ('journal', Icons.menu_book_outlined, 'Journal'),
    ('archive', Icons.archive_outlined, 'Archive'),
    ('trash', Icons.delete_outline, 'Trash'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sortedTags = [...tags]
      ..sort((a, b) {
        final byCount = (tagCounts[b] ?? 0).compareTo(tagCounts[a] ?? 0);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Row(
          children: [
            BrandMark(size: 20, fg: c.fg),
            const SizedBox(width: 10),
            Text(
              'Typed',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: c.fg,
                letterSpacing: -0.2,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Settings',
              onPressed: onSettings,
              icon: Icon(Icons.settings_outlined, color: c.muted),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _label(context, 'SPACES'),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.4,
          children: [
            for (final (id, icon, label) in _spaces)
              _spaceTile(context, id, icon, label),
          ],
        ),
        if (pinnedNotes.isNotEmpty) ...[
          const SizedBox(height: 24),
          _label(context, 'PINNED'),
          for (final note in pinnedNotes)
            _row(
              context,
              icon: Icons.push_pin_outlined,
              label: note.title.isEmpty ? 'Untitled' : note.title,
              onTap: () => onNote(note.id),
            ),
        ],
        if (sortedTags.isNotEmpty) ...[
          const SizedBox(height: 24),
          _label(context, 'TAGS'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final tag in sortedTags) _tagChip(context, tag)],
          ),
        ],
      ],
    );
  }

  Widget _label(BuildContext context, String text) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppType.t11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.9,
          color: c.muted,
        ),
      ),
    );
  }

  Widget _spaceTile(
    BuildContext context,
    String id,
    IconData icon,
    String label,
  ) {
    final c = context.colors;
    final active = activeFilter == id;
    final count = counts[id] ?? 0;
    return Semantics(
      button: true,
      selected: active,
      label: count > 0 ? '$label, $count' : label,
      excludeSemantics: true,
      child: Material(
        color: active ? c.fg.withValues(alpha: 0.06) : c.listBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: active ? c.fg.withValues(alpha: 0.25) : Colors.transparent,
          ),
        ),
        child: InkWell(
          onTap: () => onFilter(id),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(icon, size: 20, color: active ? c.fg : c.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.t15,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      color: c.fg,
                    ),
                  ),
                ),
                if (count > 0)
                  Text(
                    '$count',
                    style: TextStyle(fontSize: AppType.t12, color: c.muted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            const SizedBox(width: 2),
            Icon(icon, size: 18, color: c.muted),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppType.t15, color: c.fg),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tagChip(BuildContext context, String tag) {
    final c = context.colors;
    final active = activeTag == tag;
    final count = tagCounts[tag] ?? 0;
    return Material(
      color: active ? c.fg : c.listBg,
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: () => onTag(tag),
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '#$tag',
                  style: TextStyle(
                    fontSize: AppType.t13_5,
                    fontWeight: FontWeight.w500,
                    color: active ? c.surface : c.fg,
                  ),
                ),
                if (count > 0)
                  TextSpan(
                    text: '  $count',
                    style: TextStyle(
                      fontSize: AppType.t12,
                      color: active
                          ? c.surface.withValues(alpha: 0.7)
                          : c.muted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
