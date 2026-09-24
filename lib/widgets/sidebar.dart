import 'dart:async';

import 'package:flutter/material.dart';
import '../models/note.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../theme/app_motion.dart';
import 'brand_mark.dart';

class Sidebar extends StatefulWidget {
  final String activeFilter;
  final ValueChanged<String> onFilterChanged;
  final String sidebarState;
  final VoidCallback onCollapse;
  final ValueChanged<String> onTagFilter;
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
  bool _tagsExpanded = true;
  bool _isHovered = false;
  bool _pointerInRail = false;
  // Latched by an explicit collapse toggle done with the pointer parked
  // inside the rail; hover stays ignored until the pointer has genuinely
  // left the rail zone, so the sidebar cannot spring back open underneath it.
  bool _suppressHover = false;
  Timer? _hoverTimer;

  @override
  void dispose() {
    _hoverTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sidebarState == widget.sidebarState) return;
    _hoverTimer?.cancel();
    _isHovered = false;
    _suppressHover = widget.sidebarState == 'icons' && _pointerInRail;
  }

  void _onEnter(PointerEvent event) {
    _pointerInRail = event.position.dx <= 48;
    if (widget.sidebarState == 'expanded' || _suppressHover) return;
    _hoverTimer?.cancel();
    if (!_isHovered) setState(() => _isHovered = true);
  }

  void _onExit(PointerEvent event) {
    // A shrink-induced exit still has the pointer over the rail zone; only
    // a real leave clears the parked-cursor latch.
    _pointerInRail = event.position.dx <= 48;
    if (_pointerInRail) return;
    _suppressHover = false;
    _hoverTimer?.cancel();
    if (widget.sidebarState == 'expanded' || !_isHovered) return;
    _hoverTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _isHovered = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 1024;
    final collapsed = widget.sidebarState != 'expanded' && !_isHovered;

    return MouseRegion(
      onEnter: _onEnter,
      onExit: _onExit,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The mobile drawer supplies a tight width wider than the desktop
          // rail; fill it instead of pinning content at the desktop 232px.
          final expandedWidth = isMobile
              ? (constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : MediaQuery.of(context).size.width)
              : 232.0;
          final width = collapsed ? 48.0 : expandedWidth;
          return AnimatedContainer(
            duration: AppMotion.duration(context, AppMotion.base),
            curve: AppMotion.emphasized,
            width: width,
            clipBehavior: Clip.hardEdge,
            color: context.colors.sidebarBg,
            child: collapsed
                ? _buildContent(true, isMobile)
                : OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: 0,
                    maxWidth: expandedWidth,
                    child: SizedBox(
                      width: expandedWidth,
                      child: _buildContent(false, isMobile),
                    ),
                  ),
          );
        },
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
    final logo = isMobile
        ? BrandMark(size: 22, fg: context.colors.sidebarFg)
        : Semantics(
            label: collapsed ? 'Expand sidebar' : 'Collapse sidebar',
            button: true,
            child: InkWell(
              onTap: widget.onCollapse,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              child: SizedBox(
                width: 36,
                height: 36,
                child: Center(
                  child: BrandMark(size: 18, fg: context.colors.sidebarFg),
                ),
              ),
            ),
          );
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
          logo,
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
                borderRadius: BorderRadius.circular(AppRadius.chip),
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
          if (isMobile)
            Semantics(
              label: 'Toggle sidebar',
              child: InkWell(
                onTap: widget.onCollapse,
                borderRadius: BorderRadius.circular(AppRadius.chip),
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
      padding: EdgeInsets.symmetric(vertical: isMobile ? 12 : 12),
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
          borderRadius: BorderRadius.circular(AppRadius.chip),
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
                      fontSize: isMobile ? AppType.t15 : AppType.t13_5,
                      color: context.colors.sidebarFg,
                    )),
                const Spacer(),
                Text('${widget.allTags.length}',
                    style: TextStyle(
                      fontSize: isMobile ? AppType.t12 : AppType.t11,
                      fontFamily: context.colors.monoFontFamily,
                      color: context.colors.sidebarMuted,
                    )),
                SizedBox(width: 4),
                AnimatedRotation(
                  turns: _tagsExpanded ? 0.25 : 0,
                  duration: AppMotion.duration(context, AppMotion.base),
                  curve: AppMotion.emphasized,
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
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: isMobile ? 9 : 7,
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
                  fontSize: isMobile ? AppType.t13_5 : AppType.t12,
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
        top: topPadding ? (isMobile ? 8 : 8) : 0,
        left: isMobile ? 12 : (collapsed ? 6 : 12),
        right: isMobile ? 12 : (collapsed ? 6 : 12),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) SizedBox(height: isMobile ? 3 : 4),
            _buildNavItem(
              view: items[i].$1,
              icon: items[i].$2,
              label: items[i].$3,
              count: widget.counts[items[i].$1]?.toString() ?? '0',
              collapsed: collapsed,
              isMobile: isMobile,
            ),
          ],
        ],
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
              fontSize: AppType.t11,
              fontWeight: FontWeight.w600,
              color: context.colors.sidebarMuted,
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
        vertical: isMobile ? 4 : 8,
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
        borderRadius: BorderRadius.circular(AppRadius.chip),
        hoverColor: context.colors.sidebarHover,
        child: Stack(
          children: [
            Container(
            constraints: BoxConstraints(
              minHeight: isMobile ? 44 : (collapsed ? 44 : 40),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : (collapsed ? 8 : 12),
              vertical: isMobile ? 10 : 8,
            ),
            decoration: BoxDecoration(
              color: active ? context.colors.sidebarActive : null,
              borderRadius: BorderRadius.circular(AppRadius.chip),
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
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isMobile ? AppType.t15 : AppType.t13_5,
                        letterSpacing: 0.01,
                        color: active
                            ? context.colors.sidebarFg
                            : context.colors.sidebarFg.withAlpha(200),
                      ),
                    ),
                  ),
                  Text(
                    count,
                    style: TextStyle(
                      fontSize: isMobile ? AppType.t12 : AppType.t11,
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
            if (active)
              Positioned(
                left: 3,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    width: 3,
                    height: 14,
                    decoration: BoxDecoration(
                      color: context.colors.accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
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
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: isMobile ? 9 : 7,
            horizontal: isMobile ? 16 : 12,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text('#$label',
                    style: TextStyle(
                      fontSize: isMobile ? AppType.t13_5 : AppType.t12,
                      color: context.colors.sidebarMuted,
                      letterSpacing: 0.01,
                    )),
              ),
              if (count != null && count > 0)
                Text('$count',
                    style: TextStyle(
                      fontSize: isMobile ? AppType.t11 : AppType.t10,
                      color: context.colors.sidebarMuted,
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
        borderRadius: BorderRadius.circular(AppRadius.chip),
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
            vertical: isMobile ? 10 : 8,
          ),
          child: Row(
            children: [
              InkWell(
                onTap: () => setState(() => _open = !_open),
                borderRadius: BorderRadius.circular(AppRadius.chip),
                child: AnimatedRotation(
                  turns: _open ? 0.25 : 0,
                  duration: AppMotion.duration(context, AppMotion.base),
                  curve: AppMotion.emphasized,
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
                borderRadius: BorderRadius.circular(AppRadius.chip),
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
                        fontSize: isMobile ? AppType.t15 : AppType.t13_5,
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
                        fontSize: isMobile ? AppType.t11 : AppType.t10,
                        color: context.colors.sidebarMuted,
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
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: isMobile ? 9 : 7,
                          horizontal: isMobile ? 16 : 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('#${e.$2}',
                                  style: TextStyle(
                                    fontSize: isMobile ? AppType.t13_5 : AppType.t12,
                                    color: context.colors.sidebarMuted,
                                    letterSpacing: 0.01,
                                  )),
                            ),
                            if (widget.tagCounts.containsKey(e.$1))
                              Text('${widget.tagCounts[e.$1]}',
                                  style: TextStyle(
                                    fontSize: isMobile ? AppType.t11 : AppType.t10,
                                    color: context.colors.sidebarMuted,
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
