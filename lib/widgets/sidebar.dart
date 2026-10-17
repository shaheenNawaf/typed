import 'dart:async';

import 'package:flutter/material.dart';
import '../models/note.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../theme/app_motion.dart';
import 'brand_mark.dart';

/// Workspace sidebar: the desktop rail (expanded 232px / collapsed 48px icon
/// rail with hover peek) and the mobile drawer.
///
/// One collapse control only — a panel icon in the desktop header (the brand
/// mark toggles too). The drawer has none: it closes by scrim, swipe or Back.
/// Counts are shown only where they carry information (never 0, never Home).
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

  /// Opens the command palette; renders the Search row when set.
  final VoidCallback? onSearch;

  /// Opens the create flow; renders the New page row when set.
  final VoidCallback? onCreate;

  /// The active tag filter, highlighted in the Tags section.
  final String? activeTag;

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
    this.onSearch,
    this.onCreate,
    this.activeTag,
  });

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  /// Tags beyond this many hide behind "Show all".
  static const _tagPreviewCount = 6;

  bool _tagsExpanded = true;
  bool _showAllTags = false;
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

  // ── metrics ────────────────────────────────────────────────────────────
  // One horizontal grid for every row so icons, labels and tags line up.
  double _outer(bool collapsed, bool isMobile) =>
      collapsed ? 6 : (isMobile ? 12 : 10);
  double _inner(bool collapsed, bool isMobile) =>
      collapsed ? 9 : (isMobile ? 12 : 10);
  double _iconSize(bool isMobile) => isMobile ? 20 : 18;
  double _gap(bool isMobile) => isMobile ? 14 : 10;
  double _rowHeight(bool isMobile) => isMobile ? 44 : 34;

  Widget _buildContent(bool collapsed, bool isMobile) {
    return Column(
      children: [
        _buildHeader(collapsed, isMobile),
        if (widget.onSearch != null || widget.onCreate != null)
          _buildActions(collapsed, isMobile),
        Expanded(child: _buildNav(collapsed, isMobile)),
        _buildFooter(collapsed, isMobile),
      ],
    );
  }

  Widget _buildHeader(bool collapsed, bool isMobile) {
    final c = context.colors;
    final mark = BrandMark(size: isMobile ? 22 : 18, fg: c.sidebarFg);
    final brand = isMobile
        ? mark
        : _tooltip(
            widget.sidebarState == 'expanded'
                ? 'Collapse sidebar'
                : (collapsed ? 'Expand sidebar' : 'Keep sidebar open'),
            InkWell(
              onTap: widget.onCollapse,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              child: SizedBox(
                width: 36,
                height: 36,
                child: Center(child: mark),
              ),
            ),
          );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        collapsed ? 6 : (isMobile ? 20 : 12),
        isMobile ? 20 : 12,
        collapsed ? 6 : (isMobile ? 16 : 8),
        isMobile ? 12 : 6,
      ),
      child: Row(
        children: [
          brand,
          if (!collapsed) ...[
            SizedBox(width: isMobile ? 12 : 6),
            Expanded(
              child: Text(
                'Typed',
                maxLines: 1,
                style: TextStyle(
                  fontSize: isMobile ? 18 : 15,
                  fontWeight: FontWeight.w600,
                  color: c.sidebarFg,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            if (!isMobile)
              _iconButton(
                // While peeking (rail hovered open), the same control keeps
                // the sidebar open — say so instead of "Collapse".
                tooltip: widget.sidebarState == 'expanded'
                    ? 'Collapse sidebar'
                    : 'Keep sidebar open',
                // A panel glyph, not another chevron.
                icon: Transform.flip(
                  flipX: true,
                  child: Icon(
                    Icons.view_sidebar_outlined,
                    size: 17,
                    color: c.sidebarMuted,
                  ),
                ),
                onTap: widget.onCollapse,
              ),
          ],
        ],
      ),
    );
  }

  /// Search + New page: the two things you reach for from anywhere.
  Widget _buildActions(bool collapsed, bool isMobile) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _outer(collapsed, isMobile),
        isMobile ? 4 : 2,
        _outer(collapsed, isMobile),
        isMobile ? 8 : 6,
      ),
      child: Column(
        children: [
          if (widget.onSearch != null)
            _row(
              collapsed: collapsed,
              isMobile: isMobile,
              icon: Icons.search,
              label: 'Search',
              onTap: widget.onSearch!,
              trailing: isMobile
                  ? null
                  : Text(
                      'Ctrl K',
                      style: TextStyle(
                        fontSize: AppType.t10,
                        fontFamily: c.monoFontFamily,
                        color: c.sidebarMuted,
                      ),
                    ),
            ),
          if (widget.onCreate != null)
            _row(
              collapsed: collapsed,
              isMobile: isMobile,
              icon: Icons.add,
              label: 'New page',
              onTap: widget.onCreate!,
            ),
        ],
      ),
    );
  }

  Widget _buildNav(bool collapsed, bool isMobile) {
    final tags = widget.allTags;
    return ListView(
      padding: EdgeInsets.only(bottom: isMobile ? 12 : 8),
      children: [
        _section('Workspace', collapsed, isMobile, [
          _navItem(
            'home',
            Icons.home_outlined,
            'Home',
            collapsed,
            isMobile,
            showCount: false,
          ),
          _navItem(
            'notes',
            Icons.article_outlined,
            'Notes',
            collapsed,
            isMobile,
          ),
          _navItem(
            'finance',
            Icons.account_balance_wallet_outlined,
            'Finance',
            collapsed,
            isMobile,
          ),
          _navItem(
            'tasks',
            Icons.check_circle_outline,
            'Tasks',
            collapsed,
            isMobile,
          ),
          _navItem(
            'meeting',
            Icons.groups_outlined,
            'Meetings',
            collapsed,
            isMobile,
          ),
          _navItem(
            'journal',
            Icons.menu_book_outlined,
            'Journal',
            collapsed,
            isMobile,
          ),
        ]),
        if (!collapsed && widget.pinnedNotes.isNotEmpty)
          _section('Pinned', collapsed, isMobile, [
            for (final n in widget.pinnedNotes) _pinnedItem(n, isMobile),
          ]),
        if (!collapsed && tags.isNotEmpty)
          _section(
            'Tags',
            collapsed,
            isMobile,
            _tagsExpanded ? _tagItems(isMobile) : const [],
            onLabelTap: () => setState(() => _tagsExpanded = !_tagsExpanded),
            labelTrailing: _tagsExpanded ? null : '${tags.length}',
          ),
        _section('Library', collapsed, isMobile, [
          _navItem(
            'archive',
            Icons.archive_outlined,
            'Archive',
            collapsed,
            isMobile,
          ),
          _navItem('trash', Icons.delete_outline, 'Trash', collapsed, isMobile),
        ]),
      ],
    );
  }

  Widget _section(
    String label,
    bool collapsed,
    bool isMobile,
    List<Widget> children, {
    VoidCallback? onLabelTap,
    String? labelTrailing,
  }) {
    final c = context.colors;
    final title = Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: AppType.t10,
        fontWeight: FontWeight.w600,
        color: c.sidebarMuted,
        letterSpacing: 0.9,
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _outer(collapsed, isMobile)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (collapsed)
            // A hairline between groups keeps the icon rail scannable.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              child: Container(
                height: 1,
                color: c.sidebarFg.withValues(alpha: 0.07),
              ),
            )
          else
            Padding(
              padding: EdgeInsets.fromLTRB(
                0,
                isMobile ? 18 : 14,
                0,
                isMobile ? 6 : 4,
              ),
              child: onLabelTap == null
                  ? Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: _inner(collapsed, isMobile),
                      ),
                      child: title,
                    )
                  : Semantics(
                      button: true,
                      label: '$label, ${_tagsExpanded ? 'collapse' : 'expand'}',
                      excludeSemantics: true,
                      child: InkWell(
                        onTap: onLabelTap,
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: _inner(collapsed, isMobile),
                            vertical: 2,
                          ),
                          child: Row(
                            children: [
                              title,
                              const Spacer(),
                              if (labelTrailing != null)
                                Text(
                                  labelTrailing,
                                  style: TextStyle(
                                    fontSize: AppType.t10,
                                    fontFamily: c.monoFontFamily,
                                    color: c.sidebarMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ...children,
        ],
      ),
    );
  }

  Widget _navItem(
    String view,
    IconData icon,
    String label,
    bool collapsed,
    bool isMobile, {
    bool showCount = true,
  }) {
    final count = widget.counts[view] ?? 0;
    return _row(
      collapsed: collapsed,
      isMobile: isMobile,
      icon: icon,
      label: label,
      active: widget.activeFilter == view,
      onTap: () => widget.onFilterChanged(view),
      semanticsLabel: showCount && count > 0 ? '$label, $count items' : label,
      trailing: showCount && count > 0 ? _count(count, isMobile) : null,
    );
  }

  Widget _pinnedItem(Note note, bool isMobile) {
    return _row(
      collapsed: false,
      isMobile: isMobile,
      icon: Icons.push_pin_outlined,
      iconSize: isMobile ? 17 : 15,
      label: note.title.isEmpty ? 'Untitled' : note.title,
      dense: true,
      onTap: () {
        widget.onFilterChanged('pinned');
        widget.onNoteSelected?.call(note.id);
      },
    );
  }

  List<Widget> _tagItems(bool isMobile) {
    // Most-used first: the tags you reach for are on top, and the long tail
    // folds behind "Show all".
    final tags = [...widget.allTags]
      ..sort((a, b) {
        final byCount = (widget.tagCounts[b] ?? 0).compareTo(
          widget.tagCounts[a] ?? 0,
        );
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    final visible = _showAllTags ? tags : tags.take(_tagPreviewCount).toList();
    final hidden = tags.length - visible.length;
    final c = context.colors;
    return [
      for (final tag in visible)
        _row(
          collapsed: false,
          isMobile: isMobile,
          leading: SizedBox(
            width: _iconSize(isMobile),
            child: Text(
              '#',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isMobile ? AppType.t15 : AppType.t13_5,
                fontWeight: FontWeight.w500,
                color: c.sidebarMuted,
              ),
            ),
          ),
          label: tag,
          dense: true,
          active: widget.activeTag == tag,
          onTap: () => widget.onTagFilter(tag),
          trailing: (widget.tagCounts[tag] ?? 0) > 0
              ? _count(widget.tagCounts[tag]!, isMobile)
              : null,
        ),
      if (hidden > 0 || _showAllTags && tags.length > _tagPreviewCount)
        _row(
          collapsed: false,
          isMobile: isMobile,
          leading: SizedBox(width: _iconSize(isMobile)),
          label: _showAllTags ? 'Show fewer' : 'Show all $hidden more',
          muted: true,
          dense: true,
          onTap: () => setState(() => _showAllTags = !_showAllTags),
        ),
    ];
  }

  Widget _buildFooter(bool collapsed, bool isMobile) {
    final c = context.colors;
    if (widget.onSettings == null) return const SizedBox(height: 8);
    return Container(
      padding: EdgeInsets.fromLTRB(
        _outer(collapsed, isMobile),
        isMobile ? 8 : 6,
        _outer(collapsed, isMobile),
        isMobile ? 12 : 8,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: c.sidebarFg.withValues(alpha: 0.07)),
        ),
      ),
      child: _row(
        collapsed: collapsed,
        isMobile: isMobile,
        icon: Icons.settings_outlined,
        label: 'Settings',
        onTap: widget.onSettings!,
      ),
    );
  }

  // ── primitives ─────────────────────────────────────────────────────────

  /// The one row shape every sidebar entry uses: same height, same padding,
  /// same icon column, so everything aligns on a single grid.
  Widget _row({
    required bool collapsed,
    required bool isMobile,
    IconData? icon,
    Widget? leading,
    double? iconSize,
    required String label,
    required VoidCallback onTap,
    bool active = false,
    bool muted = false,
    bool dense = false,
    Widget? trailing,
    String? semanticsLabel,
  }) {
    final c = context.colors;
    final fg = active
        ? c.sidebarFg
        : muted
        ? c.sidebarMuted
        : c.sidebarFg.withValues(alpha: 0.82);
    final lead =
        leading ??
        Icon(
          icon,
          size: iconSize ?? _iconSize(isMobile),
          color: active ? c.sidebarFg : c.sidebarFg.withValues(alpha: 0.55),
        );
    final height = dense && !isMobile ? 30.0 : _rowHeight(isMobile);
    final tile = Semantics(
      button: true,
      selected: active,
      label: semanticsLabel ?? label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.chip + 2),
          hoverColor: c.sidebarHover,
          child: AnimatedContainer(
            duration: AppMotion.duration(context, AppMotion.fast),
            height: height,
            padding: EdgeInsets.symmetric(
              horizontal: _inner(collapsed, isMobile),
            ),
            decoration: BoxDecoration(
              color: active ? c.sidebarActive : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.chip + 2),
            ),
            child: Row(
              children: [
                // Fixed icon column: smaller glyphs (pins) still start their
                // label on the shared grid.
                SizedBox(
                  width: _iconSize(isMobile),
                  child: Center(child: lead),
                ),
                if (!collapsed) ...[
                  SizedBox(width: _gap(isMobile)),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isMobile
                            ? (dense ? AppType.t13_5 + 0.5 : AppType.t15)
                            : (dense ? AppType.t12 + 0.5 : AppType.t13_5),
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                        color: fg,
                      ),
                    ),
                  ),
                  if (trailing != null) ...[const SizedBox(width: 8), trailing],
                ],
              ],
            ),
          ),
        ),
      ),
    );
    final padded = Padding(
      padding: EdgeInsets.only(bottom: isMobile ? 2 : 1),
      child: tile,
    );
    return collapsed ? Tooltip(message: label, child: padded) : padded;
  }

  Widget _count(int count, bool isMobile) {
    final c = context.colors;
    return Text(
      '$count',
      style: TextStyle(
        fontSize: isMobile ? AppType.t12 : AppType.t11,
        fontFamily: c.monoFontFamily,
        color: c.sidebarMuted,
      ),
    );
  }

  Widget _iconButton({
    required String tooltip,
    required Widget icon,
    required VoidCallback onTap,
  }) {
    return _tooltip(
      tooltip,
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: SizedBox(width: 32, height: 32, child: Center(child: icon)),
      ),
    );
  }

  Widget _tooltip(String message, Widget child) => Tooltip(
    message: message,
    child: Semantics(label: message, button: true, child: child),
  );
}
