import 'dart:async';
import 'package:flutter/material.dart';
import '../models/note.dart';
import '../theme/app_colors.dart';
import 'brand_mark.dart';

class Sidebar extends StatefulWidget {
  final String activeFilter;
  final ValueChanged<String> onFilterChanged;
  final String sidebarState;
  final VoidCallback onCollapse;
  final ValueChanged<String> onTagFilter;
  final VoidCallback? onRequestOpen;
  final VoidCallback? onSettings;
  final Map<String, int> counts;
  final List<String> allTags;
  final Map<String, int> tagCounts;
  final List<Note> pinnedNotes;
  final ValueChanged<String>? onNoteSelected;

  const Sidebar({
    super.key,
    required this.activeFilter,
    required this.onFilterChanged,
    required this.sidebarState,
    required this.onCollapse,
    required this.onTagFilter,
    this.onRequestOpen,
    this.onSettings,
    required this.counts,
    required this.allTags,
    required this.tagCounts,
    this.pinnedNotes = const [],
    this.onNoteSelected,
  });

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  bool _isHovered = false;
  bool _tagsExpanded = true;
  Timer? _hoverTimer;

  @override
  void dispose() {
    _hoverTimer?.cancel();
    super.dispose();
  }

  void _onHoverEnter() {
    try {
      if (widget.sidebarState == 'expanded') return;
      _hoverTimer?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _isHovered = true);
      });
    } catch (_) {}
  }

  void _onHoverLeave() {
    try {
      if (widget.sidebarState == 'expanded') return;
      _hoverTimer?.cancel();
      _hoverTimer = Timer(const Duration(milliseconds: 150), () {
        if (mounted) setState(() => _isHovered = false);
      });
    } catch (_) {}
  }

  bool get _effectivelyCollapsed {
    if (widget.sidebarState == 'expanded') return false;
    if (_isHovered) return false;
    return true;
  }

  double _computeWidth() {
    switch (widget.sidebarState) {
      case 'expanded':
        return 232.0;
      case 'icons':
      default:
        return _isHovered ? 232.0 : 48.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 1024;
    final width = _computeWidth();

    return MouseRegion(
      onEnter: (_) => _onHoverEnter(),
      onExit: (_) => _onHoverLeave(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: width,
        clipBehavior: Clip.hardEdge,
        color: context.colors.sidebarBg,
        child: _buildContent(_effectivelyCollapsed, isMobile),
      ),
    );
  }

  Widget _buildContent(bool collapsed, bool isMobile) {
    return Column(
      children: [
        _buildHeader(collapsed, isMobile),
        Expanded(child: _buildNav(collapsed, isMobile)),
        _buildBottom(collapsed, isMobile),
      ],
    );
  }

  Widget _buildHeader(bool collapsed, bool isMobile) {
    return Container(
      padding: isMobile
          ? const EdgeInsets.fromLTRB(16, 20, 16, 16)
          : EdgeInsets.fromLTRB(
              collapsed ? 10 : 18,
              16,
              collapsed ? 10 : 18,
              12,
            ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.colors.sidebarFg.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          BrandMark(size: isMobile ? 22 : 18, fg: context.colors.sidebarFg),
          if (!collapsed) ...[
            SizedBox(width: isMobile ? 10 : 8),
            Text(
              'Typed',
              style: TextStyle(
                fontSize: isMobile ? 18 : 16,
                fontWeight: FontWeight.w600,
                color: context.colors.sidebarFg,
                letterSpacing: -0.01,
              ),
            ),
          ],
          if (!collapsed) const Spacer(),
          if (!collapsed && widget.onSettings != null)
            Semantics(
              label: 'Settings',
              child: InkWell(
                onTap: widget.onSettings,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.settings_outlined,
                    size: 20,
                    color: context.colors.sidebarMuted,
                  ),
                ),
              ),
            ),
          Semantics(
            label: 'Toggle sidebar',
            child: InkWell(
              onTap: widget.onCollapse,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                child: Icon(
                  collapsed ? Icons.menu_open : Icons.chevron_left,
                  size: 20,
                  color: context.colors.sidebarMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNav(bool collapsed, bool isMobile) {
    return ListView(
      padding: EdgeInsets.symmetric(vertical: isMobile ? 12 : 8),
      children: [
        _buildWorkspaceSection(collapsed, isMobile),
        _buildLibrarySection(collapsed, isMobile),
        if (widget.pinnedNotes.isNotEmpty)
          _buildPinnedSection(collapsed, isMobile),
      ],
    );
  }

  Widget _buildWorkspaceSection(bool collapsed, bool isMobile) {
    final items = <(String, IconData, String)>[
      ('home', Icons.home_outlined, 'Home'),
      ('notes', Icons.article_outlined, 'Notes'),
      ('finance', Icons.account_balance_wallet_outlined, 'Finance'),
      ('tasks', Icons.check_circle_outline, 'Tasks'),
      ('meeting', Icons.groups_outlined, 'Meetings'),
      ('journal', Icons.menu_book_outlined, 'Journal'),
    ];
    return Column(
      children: [
        _buildSectionLabel('Workspace', isMobile, collapsed: collapsed),
        _buildItemGroup(items, collapsed, isMobile, topPadding: true),
      ],
    );
  }

  Widget _buildLibrarySection(bool collapsed, bool isMobile) {
    return Column(
      children: [
        _buildSectionDivider(isMobile),
        _buildSectionLabel('Library', isMobile, collapsed: collapsed),
        if (!collapsed && widget.allTags.isNotEmpty)
          _buildTagsItem(isMobile),
        _buildItemGroup([
          ('archive', Icons.archive_outlined, 'Archive'),
          ('trash', Icons.delete_outline, 'Trash'),
        ], collapsed, isMobile),
      ],
    );
  }

  Widget _buildTagsItem(bool isMobile) {
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _tagsExpanded = !_tagsExpanded),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 12,
              vertical: isMobile ? 10 : 6,
            ),
            child: Row(
              children: [
                Icon(Icons.label_outline,
                    size: isMobile ? 20 : 18,
                    color: context.colors.sidebarFg.withAlpha(140)),
                SizedBox(width: isMobile ? 10 : 8),
                Text('Tags',
                    style: TextStyle(
                      fontSize: isMobile ? 15 : 13.5,
                      color: context.colors.sidebarFg,
                    )),
                const Spacer(),
                Text('${widget.allTags.length}',
                    style: TextStyle(
                      fontSize: isMobile ? 12 : 11,
                      fontFamily: context.colors.monoFontFamily,
                      color: context.colors.sidebarMuted,
                    )),
                SizedBox(width: 4),
                AnimatedRotation(
                  turns: _tagsExpanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.play_arrow,
                      size: 14,
                      color: context.colors.sidebarFg.withValues(alpha: 0.45)),
                ),
              ],
            ),
          ),
        ),
        if (_tagsExpanded)
          Padding(
            padding: EdgeInsets.only(left: isMobile ? 4 : 4),
            child: Column(
              children: _buildTagTree(isMobile),
            ),
          ),
      ],
    );
  }

  Widget _buildPinnedSection(bool collapsed, bool isMobile) {
    final pinned = widget.pinnedNotes;
    return Column(
      children: [
        _buildSectionDivider(isMobile),
        _buildSectionLabel('Pinned', isMobile, collapsed: collapsed),
        if (!collapsed && pinned.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.only(
                left: isMobile ? 12 : 12,
                right: isMobile ? 12 : 12,
              ),
              children: pinned
                  .map((note) => _buildPinnedItem(note, isMobile))
                  .toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildPinnedItem(Note note, bool isMobile) {
    return InkWell(
      onTap: () {
        widget.onFilterChanged('pinned');
        widget.onNoteSelected?.call(note.id);
      },
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: isMobile ? 6 : 4,
          horizontal: isMobile ? 16 : 12,
        ),
        child: Row(
          children: [
            Icon(Icons.push_pin_outlined,
                size: isMobile ? 16 : 14,
                color: context.colors.sidebarMuted),
            SizedBox(width: isMobile ? 8 : 6),
            Expanded(
              child: Text(
                note.title.isEmpty ? 'Untitled' : note.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isMobile ? 14 : 12.5,
                  color: context.colors.sidebarFg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemGroup(
    List<(String, IconData, String)> items,
    bool collapsed,
    bool isMobile, {
    bool topPadding = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(
        top: topPadding ? (isMobile ? 8 : 4) : 0,
        left: isMobile ? 12 : (collapsed ? 6 : 12),
        right: isMobile ? 12 : (collapsed ? 6 : 12),
      ),
      child: Column(
        children: items
            .map((e) => _buildNavItem(
                  view: e.$1,
                  icon: e.$2,
                  label: e.$3,
                  count: widget.counts[e.$1]?.toString() ?? '0',
                  collapsed: collapsed,
                  isMobile: isMobile,
                ))
            .toList(),
      ),
    );
  }

  Widget _buildSectionLabel(String label, bool isMobile,
      {required bool collapsed}) {
    if (collapsed) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 12, isMobile ? 10 : 8, 12, isMobile ? 4 : 2),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.colors.sidebarMuted.withValues(alpha: 0.7),
              letterSpacing: 0.08,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionDivider(bool isMobile) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 10,
        vertical: isMobile ? 4 : 2,
      ),
      child: Container(
        height: 1,
        color: context.colors.sidebarFg.withValues(alpha: 0.06),
      ),
    );
  }

  Widget _buildNavItem({
    required String view,
    required IconData icon,
    required String label,
    required String count,
    required bool collapsed,
    required bool isMobile,
  }) {
    final active = widget.activeFilter == view;
    return Semantics(
      label: collapsed ? label : '$label, $count items',
      child: InkWell(
        onTap: () => widget.onFilterChanged(view),
        borderRadius: BorderRadius.circular(6),
        child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 16 : (collapsed ? 8 : 12),
          vertical: isMobile ? 10 : 6,
        ),
        decoration: BoxDecoration(
          color: active ? context.colors.sidebarActive : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: isMobile ? 20 : 18,
              color: active
                  ? context.colors.sidebarFg
                  : context.colors.sidebarFg.withAlpha(140),
            ),
            if (!collapsed) ...[
              SizedBox(width: isMobile ? 10 : 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isMobile ? 15 : 13.5,
                  letterSpacing: 0.01,
                  color: active ? context.colors.sidebarFg : context.colors.sidebarFg,
                ),
              ),
              const Spacer(),
              Text(
                count,
                style: TextStyle(
                  fontSize: isMobile ? 12 : 11,
                  letterSpacing: 0.04,
                  fontFamily: context.colors.monoFontFamily,
                  color: active
                      ? context.colors.sidebarFg.withValues(alpha: 0.55)
                      : context.colors.sidebarMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    ));
  }

  // ponytail: derive tag groups from the actual note tags. Tags with a
  // '/' become a group (prefix) + leaf (suffix). Tags without '/' are
  // standalone leaves. Group order and leaf order are alphabetical.
  List<Widget> _buildTagTree(bool isMobile) {
    final groups = <String, List<String>>{};
    final standalone = <String>[];
    for (final tag in widget.allTags) {
      final slash = tag.indexOf('/');
      if (slash > 0 && slash < tag.length - 1) {
        final g = tag.substring(0, slash);
        final leaf = tag.substring(slash + 1);
        groups.putIfAbsent(g, () => []).add(leaf);
      } else {
        standalone.add(tag);
      }
    }
    final result = <Widget>[];
    final groupKeys = groups.keys.toList()..sort();
    for (final g in groupKeys) {
      final leaves = groups[g]!..sort();
      result.add(
        _buildTagGroup(g, leaves.map((l) => ('$g/$l', l)).toList(), isMobile),
      );
    }
    standalone.sort();
    for (final s in standalone) {
      result.add(_buildTagLeaf(s, s, isMobile));
    }
    return result;
  }

  Widget _buildTagGroup(
    String label,
    List<(String, String)> children,
    bool isMobile,
  ) {
    return _TagGroup(
      label: label,
      children: children,
      onTagTap: widget.onTagFilter,
      isMobile: isMobile,
      tagCounts: widget.tagCounts,
    );
  }

  Widget _buildTagLeaf(String filter, String label, bool isMobile) {
    final count = widget.tagCounts[filter];
    return Padding(
      padding: EdgeInsets.only(left: isMobile ? 40 : 36),
      child: InkWell(
        onTap: () => widget.onTagFilter(filter),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: isMobile ? 8 : 4,
            horizontal: isMobile ? 16 : 12,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text('#$label',
                    style: TextStyle(
                      fontSize: isMobile ? 14 : 12.5,
                      color: context.colors.sidebarMuted,
                      letterSpacing: 0.01,
                    )),
              ),
              if (count != null && count > 0)
                Text('$count',
                    style: TextStyle(
                      fontSize: isMobile ? 11 : 10,
                      color: context.colors.sidebarMuted.withValues(alpha: 0.5),
                    )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottom(bool collapsed, bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 12,
        vertical: isMobile ? 12 : 8,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.colors.sidebarFg.withValues(alpha: 0.06))),
      ),
      child: InkWell(
        onTap: widget.onCollapse,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: double.infinity,
          height: 36,
          child: Center(
            child: Icon(
              collapsed ? Icons.chevron_right : Icons.chevron_left,
              size: isMobile ? 18 : 16,
              color: context.colors.sidebarMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _TagGroup extends StatefulWidget {
  final String label;
  final List<(String, String)> children;
  final ValueChanged<String> onTagTap;
  final bool isMobile;
  final Map<String, int> tagCounts;

  const _TagGroup({
    required this.label,
    required this.children,
    required this.onTagTap,
    required this.isMobile,
    required this.tagCounts,
  });

  @override
  State<_TagGroup> createState() => _TagGroupState();
}

class _TagGroupState extends State<_TagGroup> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final isMobile = widget.isMobile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 12,
            vertical: isMobile ? 8 : 5,
          ),
          child: Row(
            children: [
              InkWell(
                onTap: () => setState(() => _open = !_open),
                borderRadius: BorderRadius.circular(4),
                child: AnimatedRotation(
                  turns: _open ? 0.25 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.play_arrow,
                      size: isMobile ? 16 : 14,
                      color: context.colors.sidebarFg.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ),
              SizedBox(width: isMobile ? 8 : 6),
              InkWell(
                onTap: () => widget.onTagTap(widget.label),
                borderRadius: BorderRadius.circular(4),
                child: Row(
                  children: [
                    Container(
                      width: isMobile ? 10 : 8,
                      height: isMobile ? 10 : 8,
                      decoration: BoxDecoration(
                        color: context.colors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: isMobile ? 8 : 6),
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: isMobile ? 14.5 : 13,
                        color: context.colors.sidebarFg,
                    letterSpacing: 0.01,
                  ),
                ),
                if (widget.children.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(left: isMobile ? 8 : 6),
                    child: Text(
                      '${widget.children.map((e) => widget.tagCounts[e.$1] ?? 0).reduce((a, b) => a + b)}',
                      style: TextStyle(
                        fontSize: isMobile ? 11 : 10,
                        color: context.colors.sidebarMuted.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
          ),
        ),
        if (_open)
          Padding(
            padding: EdgeInsets.only(left: isMobile ? 36 : 32),
            child: Column(
              children: widget.children
                  .map(
                    (e) => InkWell(
                      onTap: () => widget.onTagTap(e.$1),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: isMobile ? 8 : 4,
                          horizontal: isMobile ? 16 : 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('#${e.$2}',
                                  style: TextStyle(
                                    fontSize: isMobile ? 14 : 12.5,
                                    color: context.colors.sidebarMuted,
                                    letterSpacing: 0.01,
                                  )),
                            ),
                            if (widget.tagCounts.containsKey(e.$1))
                              Text('${widget.tagCounts[e.$1]}',
                                  style: TextStyle(
                                    fontSize: isMobile ? 11 : 10,
                                    color: context.colors.sidebarMuted.withValues(alpha: 0.5),
                                  )),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }
}
