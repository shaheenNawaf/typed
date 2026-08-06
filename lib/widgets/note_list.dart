import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/budget.dart';
import '../models/note.dart';
import '../theme/app_colors.dart';
import '../utils/finance_utils.dart';
import 'finance_dashboard.dart';
import 'long_press_menu.dart';

class NoteList extends StatefulWidget {
  final List<Note> notes;
  final String? currentNoteId;
  final ValueChanged<String> onSelectNote;
  final bool sortDesc;
  final VoidCallback onSortToggle;
  final VoidCallback onNewNote;
  final String listTitle;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final String activeFilter;
  final String? activeTag;
  final VoidCallback? onClearActiveTag;
  final VoidCallback? onOpenSettings;
  final void Function(Note) onArchive;
  final void Function(Note) onDelete;
  final void Function(Note) onRestore;
  final Future<void> Function(Note) onDeletePermanent;
  final void Function(Note) onTogglePin;
  final VoidCallback? onEmptyTrash;
  final FinanceSummary? financeSummary;
  final String? financePeriod;
  final ValueChanged<String>? onFinancePeriodChanged;
  final String Function(String?)? dashboardCurrencySymbol;
  final String Function(double, String?)? dashboardFormatAmount;
  final List<Budget>? budgets;
  final void Function(Budget)? onAddBudget;
  final void Function(Budget)? onRemoveBudget;
  final VoidCallback? onQuickAddEntry;
  final void Function(Note note, int lineIndex, bool checked)?
      onChecklistToggle;

  const NoteList({
    super.key,
    required this.notes,
    required this.currentNoteId,
    required this.onSelectNote,
    required this.sortDesc,
    required this.onSortToggle,
    required this.onNewNote,
    required this.listTitle,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.activeFilter,
    this.activeTag,
    this.onClearActiveTag,
    this.onOpenSettings,
    required this.onArchive,
    required this.onDelete,
    required this.onRestore,
    required this.onDeletePermanent,
    required this.onTogglePin,
    this.onEmptyTrash,
    this.financeSummary,
    this.financePeriod,
    this.onFinancePeriodChanged,
    this.dashboardCurrencySymbol,
    this.dashboardFormatAmount,
    this.budgets,
    this.onAddBudget,
    this.onRemoveBudget,
    this.onQuickAddEntry,
    this.onChecklistToggle,
  });

  @override
  State<NoteList> createState() => _NoteListState();
}

class _NoteListState extends State<NoteList> {
  late TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: widget.searchQuery);
  }

  @override
  void didUpdateWidget(NoteList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != _searchCtrl.text) {
      _searchCtrl.text = widget.searchQuery;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 1024;
    final showDashboard =
        widget.activeFilter == 'finance' && widget.financeSummary != null;
    final showQuickFab =
        !isDesktop &&
        widget.activeFilter == 'finance' &&
        widget.onQuickAddEntry != null;
    return Stack(
      children: [
        Container(
          color: context.colors.listBg,
          child: Column(
            children: [
              _buildSearch(),
              _buildHeader(),
              if (showDashboard)
                FinanceStickyHeader(
                  summary: widget.financeSummary!,
                  period: widget.financePeriod ?? 'all',
                  onPeriodChanged: widget.onFinancePeriodChanged ?? (_) {},
                  currencySymbol:
                      widget.dashboardCurrencySymbol ?? currencySymbol,
                ),
              Expanded(child: _buildCardList()),
            ],
          ),
        ),
        if (showQuickFab)
          Positioned(
            right: 20,
            bottom: 20,
            child: FloatingActionButton(
              heroTag: 'quickAddFab',
              onPressed: widget.onQuickAddEntry,
              backgroundColor: context.colors.accent,
              foregroundColor: Colors.white,
              elevation: 4,
              shape: const CircleBorder(),
              child: const Icon(Icons.bolt, color: Colors.white, size: 24),
            ),
          ),
        if (!isDesktop &&
            widget.activeFilter != 'archive' &&
            widget.activeFilter != 'trash' &&
            widget.activeFilter != 'finance')
          Positioned(
            right: 20,
            bottom: 20,
            child: FloatingActionButton(
              heroTag: 'newNoteFab',
              onPressed: widget.onNewNote,
              backgroundColor: context.colors.accent,
              foregroundColor: Colors.white,
              elevation: 4,
              shape: const CircleBorder(),
              child: const Icon(Icons.add, size: 24),
            ),
          ),
      ],
    );
  }

  Widget _buildSearch() {
    final isMobile = MediaQuery.of(context).size.width < 1024;
    final hasQuery = _searchCtrl.text.isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 12 : 16,
        isMobile ? 10 : 14,
        isMobile ? 12 : 16,
        10,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: widget.onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search notes...',
                hintStyle: TextStyle(
                  fontSize: isMobile ? 15 : 13.5,
                  color: context.colors.muted,
                ),
                filled: true,
                fillColor: context.colors.surface,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: isMobile ? 12 : 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.colors.accent),
                ),
              ),
              style: TextStyle(
                fontSize: isMobile ? 15 : 13.5,
                color: context.colors.fg,
              ),
            ),
          ),
          if (hasQuery)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Semantics(
                label: 'Cancel search',
                child: InkWell(
                  onTap: () {
                    _searchCtrl.clear();
                    widget.onSearchChanged('');
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.accent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.listTitle,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: context.colors.muted,
                  letterSpacing: 0.06,
                ),
              ),
              Row(
                children: [
                  Semantics(
                    label: 'Toggle sort order',
                    child: InkWell(
                      onTap: widget.onSortToggle,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: isMobile
                            ? Icon(
                                widget.sortDesc
                                    ? Icons.arrow_downward
                                    : Icons.sort_by_alpha,
                                size: 16,
                                color: context.colors.muted,
                              )
                            : Text(
                                widget.sortDesc
                                    ? 'Recent \u2193'
                                    : 'A\u2013Z \u2191',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: context.colors.muted,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Semantics(
                    label: 'New note',
                    child: InkWell(
                      onTap: widget.onNewNote,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: isMobile
                            ? Icon(
                                Icons.add,
                                size: 16,
                                color: context.colors.muted,
                              )
                            : Row(
                                children: [
                                  Icon(
                                    Icons.add,
                                    size: 16,
                                    color: context.colors.muted,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    'New',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: context.colors.muted,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  if (widget.activeFilter == 'finance' &&
                      widget.onQuickAddEntry != null &&
                      !isMobile) ...[
                    const SizedBox(width: 4),
                    Semantics(
                      label: 'Quick add expense',
                      child: InkWell(
                        onTap: widget.onQuickAddEntry,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.bolt,
                                size: 16,
                                color: context.colors.accent,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                'Quick',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: context.colors.accent,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (widget.onOpenSettings != null) ...[
                    const SizedBox(width: 4),
                    Semantics(
                      label: 'Settings',
                      child: InkWell(
                        onTap: widget.onOpenSettings,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Icon(
                            Icons.settings_outlined,
                            size: 16,
                            color: context.colors.muted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (widget.activeTag != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: InkWell(
              onTap: widget.onClearActiveTag,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: context.colors.tagBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '#${widget.activeTag}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: context.colors.tagFg,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.close, size: 12, color: context.colors.tagFg),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCardItem(dynamic item) {
    if (item is String) return _buildSectionHeader(item);
    final note = item as Note;
    final isArchiveOrTrash =
        widget.activeFilter == 'archive' || widget.activeFilter == 'trash';
    return _NoteCard(
      note: note,
      selected: note.id == widget.currentNoteId,
      onTap: () => widget.onSelectNote(note.id),
      onPrimaryAction: () =>
          isArchiveOrTrash ? widget.onRestore(note) : widget.onArchive(note),
      onSecondaryAction: widget.activeFilter == 'trash'
          ? () => widget.onDeletePermanent(note)
          : widget.activeFilter == 'archive'
          ? () => widget.onDeletePermanent(note)
          : () => widget.onDelete(note),
      longPressActions: _buildLongPressActions(note),
      activeFilter: widget.activeFilter,
      budgets: widget.budgets ?? const [],
      onChecklistToggle: widget.onChecklistToggle,
    );
  }

  Widget _buildCardList() {
    final showDashboard =
        widget.activeFilter == 'finance' && widget.financeSummary != null;

    final Widget child;

    if (showDashboard) {
      final body = FinanceDashboardBody(
        summary: widget.financeSummary!,
        period: widget.financePeriod ?? 'all',
        currencySymbol: widget.dashboardCurrencySymbol ?? currencySymbol,
        budgets: widget.budgets ?? const [],
        onAddBudget: widget.onAddBudget,
        onRemoveBudget: widget.onRemoveBudget,
        onSelectNote: widget.onSelectNote,
      );

      if (widget.notes.isEmpty) {
        child = ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          children: [body],
        );
      } else {
        final sectioned = _buildSectionedItems();
        child = ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          itemCount: sectioned.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) return body;
            return _buildCardItem(sectioned[index - 1]);
          },
        );
      }
    } else if (widget.notes.isEmpty) {
      switch (widget.activeFilter) {
        case 'archive':
          child = _emptyState(
            icon: Icons.archive_outlined,
            title: 'No archived notes',
            subtitle: 'Notes you archive will appear here.',
          );
          break;
        case 'trash':
          child = _emptyState(
            icon: Icons.delete_outline,
            title: 'Trash is empty',
            subtitle: 'Deleted notes will appear here.',
          );
          break;
        case 'pinned':
          child = _emptyState(
            icon: Icons.push_pin_outlined,
            title: 'No pinned notes',
            subtitle: 'Long-press a note to pin it.',
          );
          break;
        case 'tasks':
          child = _emptyState(
            icon: Icons.check_circle_outline,
            title: 'No tasks yet',
            subtitle: 'Create your first task.',
          );
          break;
        case 'meeting':
          child = _emptyState(
            icon: Icons.groups_outlined,
            title: 'No meetings recorded',
            subtitle: 'Capture attendees, decisions and action items.',
          );
          break;
        case 'journal':
          child = _emptyState(
            icon: Icons.menu_book_outlined,
            title: 'No journal entries yet',
            subtitle: 'Record your thoughts, wins and lessons.',
          );
          break;
        case 'finance':
          child = _emptyState(
            icon: Icons.account_balance_wallet_outlined,
            title: 'No financial records yet',
            subtitle: 'Track expenses, income and budgets.',
            actions: [
              TextButton.icon(
                onPressed: widget.onQuickAddEntry,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add First Transaction'),
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.accent,
                ),
              ),
            ],
          );
          break;
        case 'today':
          child = _emptyState(
            icon: Icons.calendar_today_outlined,
            title: 'Nothing today',
            subtitle: 'Notes you edit today will appear here.',
          );
          break;
        case 'untagged':
          child = _emptyState(
            icon: Icons.tag,
            title: 'All notes are tagged',
            subtitle: 'Untagged notes will appear here.',
          );
          break;
        default:
          if (widget.searchQuery.isNotEmpty) {
            child = _emptyState(
              icon: Icons.search_off,
              title: 'No notes match your search.',
              subtitle: 'Try a different search or filter.',
            );
          } else {
            child = _emptyState(
              icon: Icons.note_add_outlined,
              title: 'No notes yet',
              subtitle: 'Create your first note to get started.',
              actions: [
                TextButton.icon(
                  onPressed: widget.onNewNote,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Create Note'),
                  style: TextButton.styleFrom(
                    foregroundColor: context.colors.accent,
                  ),
                ),
              ],
            );
          }
      }
    } else {
      final sectioned = _buildSectionedItems();
      child = ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        itemCount: sectioned.length,
        itemBuilder: (context, index) {
          return _buildCardItem(sectioned[index]);
        },
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: child,
    );
  }

  static String _dateSection(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(d.year, d.month, d.day);
    final diff = date.difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == -1) return 'Yesterday';
    if (diff > -7) return 'This Week';
    return 'Older';
  }

  List<dynamic> _buildSectionedItems() {
    if (widget.activeFilter == 'archive' || widget.activeFilter == 'trash') {
      return widget.notes.toList();
    }
    final items = <dynamic>[];
    String? currentSection;
    for (final note in widget.notes) {
      final section = _dateSection(note.updatedAt);
      if (section != currentSection) {
        items.add(section);
        currentSection = section;
      }
      items.add(note);
    }
    return items;
  }

  Widget _buildSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: context.colors.muted,
          letterSpacing: 0.08,
          height: 1.2,
        ),
      ),
    );
  }

  List<LongPressAction> _buildLongPressActions(Note note) {
    final isTrash = widget.activeFilter == 'trash';
    final isArchive = widget.activeFilter == 'archive';
    final isMain = !isTrash && !isArchive;

    return [
      if (isMain || isArchive)
        LongPressAction(
          icon: note.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
          label: note.isPinned ? 'Unpin' : 'Pin',
          onTap: () => widget.onTogglePin(note),
        ),
      if (isMain)
        LongPressAction(
          icon: Icons.archive_outlined,
          label: 'Archive',
          onTap: () => widget.onArchive(note),
        ),
      if (isArchive)
        LongPressAction(
          icon: Icons.unarchive_outlined,
          label: 'Restore',
          onTap: () => widget.onRestore(note),
        ),
      if (isTrash)
        LongPressAction(
          icon: Icons.restore_from_trash_outlined,
          label: 'Restore',
          onTap: () => widget.onRestore(note),
        ),
      if (isMain)
        LongPressAction(
          icon: Icons.delete_outline,
          label: 'Delete',
          onTap: () => widget.onDelete(note),
        ),
      if (isArchive || isTrash)
        LongPressAction(
          icon: Icons.delete_forever_outlined,
          label: 'Delete permanently',
          onTap: () => widget.onDeletePermanent(note),
          destructive: true,
        ),
    ];
  }

  Widget _emptyState({
    IconData? icon,
    required String title,
    required String subtitle,
    List<Widget>? actions,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 36, color: context.colors.muted.withAlpha(80)),
            const SizedBox(height: 16),
          ],
          Text(
            title,
            style: GoogleFonts.dmSans(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: context.colors.fg,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              subtitle,
              style: TextStyle(
                fontSize: 13,
                color: context.colors.muted,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          if (actions != null && actions.isNotEmpty) ...[
            const SizedBox(height: 20),
            ...actions,
          ],
        ],
      ),
    );
  }
}

class _NoteCard extends StatefulWidget {
  final Note note;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onPrimaryAction;
  final VoidCallback? onSecondaryAction;
  final List<LongPressAction> longPressActions;
  final String activeFilter;
  final List<Budget> budgets;
  final void Function(Note note, int lineIndex, bool checked)?
      onChecklistToggle;

  const _NoteCard({
    required this.note,
    required this.selected,
    required this.onTap,
    required this.onPrimaryAction,
    this.onSecondaryAction,
    required this.longPressActions,
    this.activeFilter = 'notes',
    this.budgets = const [],
    this.onChecklistToggle,
  });

  @override
  State<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<_NoteCard> {
  double _dragOffset = 0;
  bool _isSnapping = false;

  static const double _kActionZoneWidth = 80.0;
  static const double _kActionThreshold = 48.0;

  void _onDragStart(DragStartDetails details) {
    setState(() => _isSnapping = false);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final double newOffset = _dragOffset + details.primaryDelta!;
    setState(() {
      _dragOffset = newOffset.clamp(-_kActionZoneWidth, _kActionZoneWidth);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_dragOffset >= _kActionThreshold) {
      widget.onPrimaryAction();
    } else if (_dragOffset <= -_kActionThreshold) {
      widget.onSecondaryAction?.call();
    }
    _dragOffset = 0;
    setState(() => _isSnapping = true);
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _isSnapping = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 1024;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Stack(
        children: [
          if (_dragOffset < 0)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: _kActionZoneWidth,
              child: Container(
                decoration: BoxDecoration(
                  color: context.colors.destructive,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(
                    Icons.delete_outline,
                    color: Color(0xFFF0F0F0),
                    size: 26,
                  ),
                ),
              ),
            ),
          if (_dragOffset > 0)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: _kActionZoneWidth,
              child: Container(
                decoration: BoxDecoration(
                  color: context.colors.income,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(
                    Icons.archive_outlined,
                    color: Color(0xFFF0F0F0),
                    size: 26,
                  ),
                ),
              ),
            ),
          AnimatedContainer(
            duration: _isSnapping
                ? const Duration(milliseconds: 200)
                : Duration.zero,
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(_dragOffset, 0, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: isDesktop ? null : _onDragStart,
              onHorizontalDragUpdate: isDesktop ? null : _onDragUpdate,
              onHorizontalDragEnd: isDesktop ? null : _onDragEnd,
              onLongPressStart: (details) {
                if (widget.longPressActions.isEmpty) return;
                LongPressMenu.show(
                  context,
                  actions: widget.longPressActions,
                  tapPosition: details.globalPosition,
                );
              },
              child: _buildCard(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard() {
    // ponytail: compact 2-line card for finance notes — title + amount on row 1,
    // time + entry count on row 2. No content preview, no tag chips. Other
    // filters keep the full card layout.
    final isFinance =
        widget.activeFilter == 'finance' && widget.note.type != 'text';

    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: isFinance
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
            : const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: widget.selected ? context.colors.accent : Colors.transparent,
            width: widget.selected ? 1 : 0,
          ),
          boxShadow: widget.selected
              ? [
                  BoxShadow(
                    color: context.colors.accentDim,
                    blurRadius: 0,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: isFinance ? _buildFinanceCardBody() : _buildFullCardBody(),
      ),
    );
  }

  Widget _buildFinanceCardBody() {
    final dominant = _dominantCategory(widget.note);
    final budget = dominant != null
        ? widget.budgets.cast<Budget?>().firstWhere(
            (b) => b!.category == dominant,
            orElse: () => null,
          )
        : null;
    final budgetActual = budget != null && dominant != null
        ? widget.note.amounts
              .where(
                (e) =>
                    e.category == dominant &&
                    (e.type ?? widget.note.type) == 'expense',
              )
              .fold<double>(0, (s, e) => s + e.amount)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              widget.note.type == 'income'
                  ? Icons.arrow_downward
                  : Icons.arrow_upward,
              size: 12,
              color: widget.note.type == 'income'
                  ? context.colors.income
                  : context.colors.fg,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.note.title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: context.colors.fg,
                  letterSpacing: -0.01,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            if (widget.note.amounts.isNotEmpty)
              Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: 12.5,
                    fontFamily: context.colors.monoFontFamily,
                    fontWeight: FontWeight.w600,
                    color: widget.note.type == 'income'
                        ? context.colors.income
                        : context.colors.fg,
                  ),
                  children: _buildCardAmountSpans(widget.note),
                ),
              ),
          ],
        ),
        if (budget != null && widget.note.type != 'income')
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: (budgetActual / budget.limit).clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: context.colors.border,
                      valueColor: AlwaysStoppedAnimation(
                        budgetActual > budget.limit
                            ? context.colors.destructive
                            : context.colors.income,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${formatAmount(budgetActual, widget.note.currency)} / ${formatAmount(budget.limit, widget.note.currency)}',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontFamily: context.colors.monoFontFamily,
                    color: budgetActual > budget.limit
                        ? context.colors.destructive
                        : context.colors.muted,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String? _dominantCategory(Note note) {
    if (note.amounts.isEmpty) return null;
    final totals = <String, double>{};
    for (final e in note.amounts) {
      if ((e.type ?? note.type) != 'expense') continue;
      totals[e.category] = (totals[e.category] ?? 0) + e.amount;
    }
    if (totals.isEmpty) return null;
    return totals.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  bool _isUnread(Note note) {
    if (note.viewedAt == null) return true;
    return note.updatedAt.isAfter(note.viewedAt!);
  }

  Widget _buildFullCardBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (_isUnread(widget.note))
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: context.colors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            if (widget.note.isPinned) ...[
              Icon(Icons.push_pin, size: 12, color: context.colors.accent),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                widget.note.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.colors.fg,
                  letterSpacing: -0.01,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (_contentPreview(widget.note.content).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              _contentPreview(widget.note.content),
              style: TextStyle(
                fontSize: 12,
                color: context.colors.muted,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (widget.activeFilter == 'tasks' &&
            widget.onChecklistToggle != null)
          _buildTaskChecklist(),
        Row(
          children: [
            ...widget.note.tags
                .take(3)
                .map(
                  (t) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: context.colors.tagBg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '#$t',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: context.colors.tagFg,
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ),
        if (widget.note.type != 'text' && widget.note.amounts.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                widget.note.type == 'income'
                    ? Icons.arrow_downward
                    : Icons.arrow_upward,
                size: 10,
                color: widget.note.type == 'income'
                    ? context.colors.income
                    : context.colors.fg,
              ),
              const SizedBox(width: 4),
              Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: context.colors.monoFontFamily,
                    fontWeight: FontWeight.w500,
                    color: widget.note.type == 'income'
                        ? context.colors.income
                        : context.colors.fg,
                  ),
                  children: _buildCardAmountSpans(widget.note),
                ),
              ),
              if (widget.note.amounts.length > 1) ...[
                const SizedBox(width: 4),
                Text(
                  '(${widget.note.amounts.length} entries)',
                  style: TextStyle(fontSize: 10, color: context.colors.muted),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: 6),
        Text(
          _relativeTime(widget.note.updatedAt),
          style: TextStyle(
            fontSize: 10.5,
            fontFamily: context.colors.monoFontFamily,
            color: context.colors.muted.withValues(alpha: 0.7),
            letterSpacing: 0.03,
          ),
        ),
      ],
    );
  }

  Widget _buildTaskChecklist() {
    final items = <(int, bool, String)>[];
    for (final entry in widget.note.content.split('\n').asMap().entries) {
      final match = RegExp(r'^\s*-\s+\[([ xX])\]\s+(.*)$')
          .firstMatch(entry.value);
      if (match == null) continue;
      items.add((
        entry.key,
        match.group(1)!.toLowerCase() == 'x',
        match.group(2)?.trim() ?? '',
      ));
      if (items.length == 5) break;
    }
    if (items.isEmpty) return const SizedBox.shrink();

    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Column(
        children: [
          for (final item in items)
            Semantics(
              button: true,
              checked: item.$2,
              label: item.$3.isEmpty ? 'Checklist item' : item.$3,
              child: InkWell(
                onTap: () => widget.onChecklistToggle!(
                  widget.note,
                  item.$1,
                  !item.$2,
                ),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Icon(
                        item.$2
                            ? Icons.check_box_outlined
                            : Icons.check_box_outline_blank,
                        size: 17,
                        color: item.$2 ? c.accent : c.muted,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.$3.isEmpty ? 'Untitled task' : item.$3,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: item.$2 ? c.muted : c.fg,
                            decoration: item.$2
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _contentPreview(String content) {
    // ponytail: strip markdown syntax, take first ~120 chars
    var text = content
        .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
        .replaceAll(RegExp(r'\*\*|__'), '')
        .replaceAll(RegExp(r'\*|_'), '')
        .replaceAll(RegExp(r'`[^`]+`'), '')
        .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]+\)'), '')
        .replaceAll(RegExp(r'\[[^\]]*\]\([^)]+\)'), '')
        .replaceAll(RegExp(r'^\s*[-+]\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*>\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*\|.*$', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*---+\s*$', multiLine: true), '')
        .replaceAll(RegExp(r'[[\]]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.length > 120) text = '${text.substring(0, 120)}...';
    return text;
  }

  static String _relativeTime(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static List<InlineSpan> _buildCardAmountSpans(Note note) {
    final total = note.amounts.fold<double>(0, (sum, e) => sum + e.amount);
    return [
      currencySpan(note.currency, null),
      TextSpan(
        text: formatNumber(total, decimals: note.currency == 'JPY' ? 0 : 2),
      ),
    ];
  }
}
