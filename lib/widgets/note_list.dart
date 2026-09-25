import 'package:flutter/material.dart';
import '../models/budget.dart';
import '../models/money_entry.dart';
import '../models/note.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../theme/app_motion.dart';
import '../utils/finance_utils.dart';
import '../utils/markdown_display.dart';
import 'finance_dashboard.dart';
import 'long_press_menu.dart';

class NoteList extends StatefulWidget {
  final List<Note> notes;
  final String? currentNoteId;
  final ValueChanged<String> onSelectNote;
  final bool sortDesc;
  final VoidCallback onSortToggle;
  final VoidCallback onNewNote;
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
  final String? financeCurrency;
  final List<String> financeCurrencyOptions;
  final ValueChanged<String>? onFinanceCurrencyChanged;
  final String Function(String?)? dashboardCurrencySymbol;
  final List<Budget>? budgets;

  /// Spend per budget id against each budget's own calendar period,
  /// computed by the caller from all notes (see HomeScreen._budgetActuals).
  final Map<String, int> budgetActuals;
  final void Function(Budget)? onAddBudget;
  final void Function(Budget)? onRemoveBudget;
  final VoidCallback? onQuickAddEntry;
  final VoidCallback? onQuickAddIncome;

  /// 'simple' | 'advanced' — Simple shows a quiet this-month view;
  /// Advanced shows the full dashboard (categories, budgets, deltas).
  final String? financeMode;
  final ValueChanged<String>? onFinanceModeChanged;
  final void Function(Note note, int lineIndex, bool checked)?
      onChecklistToggle;

  /// When false the finance pane renders notes only (desktop shows the
  /// dashboard in the wide FinanceWorkspace pane instead).
  final bool showFinanceDashboard;
  /// Tap a transaction row -> edit that entry (noteId, entryId).
  final void Function(String noteId, String entryId)? onSelectEntry;
  /// Minor-unit expense buckets, oldest -> newest, length 14 (sparkline).
  final List<int> financeDailyTotals;

  const NoteList({
    super.key,
    required this.notes,
    required this.currentNoteId,
    required this.onSelectNote,
    required this.sortDesc,
    required this.onSortToggle,
    required this.onNewNote,
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
    this.financeCurrency,
    this.financeCurrencyOptions = const ['all'],
    this.onFinanceCurrencyChanged,
    this.dashboardCurrencySymbol,
    this.budgets,
    this.budgetActuals = const {},
    this.onAddBudget,
    this.onRemoveBudget,
    this.onQuickAddEntry,
    this.onQuickAddIncome,
    this.financeMode,
    this.onFinanceModeChanged,
    this.onChecklistToggle,
    this.showFinanceDashboard = true,
    this.onSelectEntry,
    this.financeDailyTotals = const [],
  });

  @override
  State<NoteList> createState() => _NoteListState();
}

class _NoteListState extends State<NoteList> {
  /// True when the Finance pane should render the quiet this-month view.
  bool get _financeSimpleMode =>
      widget.activeFilter == 'finance' &&
      (widget.financeMode ?? 'simple') == 'simple';

  /// True when the Finance pane's Simple/Advanced toggle row owns the
  /// sort/settings controls (they stay fixed below the navbar there).
  bool get _showModeToggle =>
      widget.activeFilter == 'finance' &&
      widget.financeSummary != null &&
      widget.showFinanceDashboard &&
      widget.onFinanceModeChanged != null;

  /// True when the sort/settings controls ride on the list's first section
  /// header row ('Yesterday … Recent ↓ ⚙') instead of a separate fixed row
  /// below the navbar. Finance keeps its toggle row; archive/trash are flat
  /// lists with no section headers; empty lists keep the fixed row so the
  /// controls stay reachable.
  bool get _mergeControlsIntoList {
    final showDashboard =
        widget.activeFilter == 'finance' &&
        widget.financeSummary != null &&
        widget.showFinanceDashboard;
    if (showDashboard) return false;
    if (widget.activeFilter == 'archive' || widget.activeFilter == 'trash') {
      return false;
    }
    return _displayNotes.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final showDashboard =
        widget.activeFilter == 'finance' &&
        widget.financeSummary != null &&
        widget.showFinanceDashboard;
    final simpleMode = _financeSimpleMode;
    return Container(
      color: context.colors.listBg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Decide by the pane's own width, not the window: on desktop
          // the note list column is ~340px even when the window is wide.
          // The controls sit inside 16px horizontal padding, so decide on
          // the CONTENT width (pane - 32) — identical to the old
          // inside-Padding LayoutBuilder (390 pane -> 358 -> icon variant).
          final isMobilePane = constraints.maxWidth - 32 < 380;
          return Column(
            children: [
              _buildHeader(isMobilePane),
              // The period/currency scope selector belongs to the Advanced
              // dashboard; Simple is always a calm this-month view.
              if (showDashboard && !simpleMode)
                FinanceStickyHeader(
                  summary: widget.financeSummary!,
                  period: widget.financePeriod ?? 'all',
                  onPeriodChanged: widget.onFinancePeriodChanged ?? (_) {},
                  currencySymbol:
                      widget.dashboardCurrencySymbol ?? currencySymbol,
                  currencyScope: widget.financeCurrency ?? 'all',
                  currencyOptions: widget.financeCurrencyOptions,
                  onCurrencyChanged: widget.onFinanceCurrencyChanged,
                ),
              Expanded(child: _buildCardList(isMobilePane)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(bool isMobilePane) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_mergeControlsIntoList)
          Padding(
            // One snug control row below the workspace header: page mode
            // toggle on the left, sort/settings on the right.
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_showModeToggle) ...[
                  FinanceModeToggle(
                    mode: widget.financeMode ?? 'simple',
                    onChanged: widget.onFinanceModeChanged!,
                  ),
                  const Spacer(),
                ],
                ..._headerControls(isMobilePane),
              ],
            ),
          ),
        if (widget.activeTag != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: InkWell(
              onTap: widget.onClearActiveTag,
              borderRadius: BorderRadius.circular(AppRadius.panel),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: context.colors.tagBg,
                  borderRadius: BorderRadius.circular(AppRadius.panel),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '#${widget.activeTag}',
                      style: TextStyle(
                        fontSize: AppType.t12,
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

  /// Sort / new-note / settings controls, shared by the fixed header row and
  /// the merged first-section-header row.
  List<Widget> _headerControls(bool isMobilePane) {
    final isDesktopWindow = MediaQuery.of(context).size.width >= 1024;
    return [
      Semantics(
        label: 'Toggle sort order',
        child: InkWell(
          onTap: widget.onSortToggle,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: isMobilePane
                ? Icon(
                    widget.sortDesc
                        ? Icons.arrow_downward
                        : Icons.sort_by_alpha,
                    size: 16,
                    color: context.colors.muted,
                  )
                : Text(
                    widget.sortDesc ? 'Recent \u2193' : 'A\u2013Z \u2191',
                    style: TextStyle(
                      fontSize: AppType.t13_5,
                      color: context.colors.muted,
                    ),
                  ),
          ),
        ),
      ),
      const SizedBox(width: 4),
      if (widget.activeFilter != 'finance' && isDesktopWindow)
        Semantics(
          label: 'New note',
          child: InkWell(
            onTap: widget.onNewNote,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: isMobilePane
                  ? const Icon(Icons.add, size: 16)
                  : Row(
                      children: [
                        const Icon(Icons.add, size: 16),
                        const SizedBox(width: 2),
                        Text(
                          'New',
                          style: TextStyle(
                            fontSize: AppType.t13_5,
                            color: context.colors.muted,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      if (widget.onOpenSettings != null) ...[
        const SizedBox(width: 4),
        Semantics(
          label: 'Settings',
          child: InkWell(
            onTap: widget.onOpenSettings,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Icon(
                Icons.settings_outlined,
                size: 16,
                color: context.colors.muted,
              ),
            ),
          ),
        ),
      ],
    ];
  }

  Widget _buildCardItem(
    dynamic item, {
    bool isMobilePane = false,
    bool withControls = false,
  }) {
    if (item is String) {
      return _buildSectionHeader(
        item,
        trailing: withControls ? _headerControls(isMobilePane) : null,
      );
    }
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
      budgetActuals: widget.budgetActuals,
      onChecklistToggle: widget.onChecklistToggle,
      financeEntries: widget.financeSummary?.entriesByNote[note.id],
    );
  }

  List<Note> get _displayNotes {
    if (widget.activeFilter == 'finance' && widget.financeSummary != null) {
      final ids = widget.financeSummary!.noteIds;
      return widget.notes.where((note) => ids.contains(note.id)).toList();
    }
    return widget.notes;
  }

  Widget _buildCardList(bool isMobilePane) {
    final showDashboard =
        widget.activeFilter == 'finance' &&
        widget.financeSummary != null &&
        widget.showFinanceDashboard;
    final displayNotes = _displayNotes;

    final Widget child;

    if (showDashboard) {
      final Widget body;
      if (_financeSimpleMode) {
        body = SimpleFinanceView(
          summary: widget.financeSummary!,
          budgets: widget.budgets ?? const [],
          budgetActuals: widget.budgetActuals,
          onAddExpense: widget.onQuickAddEntry,
          onAddIncome: widget.onQuickAddIncome,
          onSelectNote: widget.onSelectNote,
          onSelectEntry: widget.onSelectEntry,
          onOpenAdvanced: widget.onFinanceModeChanged == null
              ? null
              : () => widget.onFinanceModeChanged!('advanced'),
        );
      } else {
        body = FinanceDashboardBody(
          summary: widget.financeSummary!,
          period: widget.financePeriod ?? 'all',
          currencySymbol: widget.dashboardCurrencySymbol ?? currencySymbol,
          budgets: widget.budgets ?? const [],
          budgetActuals: widget.budgetActuals,
          onAddBudget: widget.onAddBudget,
          onRemoveBudget: widget.onRemoveBudget,
          onSelectNote: widget.onSelectNote,
          onAddExpense: widget.onQuickAddEntry,
          onAddIncome: widget.onQuickAddIncome,
          currencyScope: widget.financeCurrency ?? 'all',
          onSelectEntry: widget.onSelectEntry,
          dailyTotals: widget.financeDailyTotals,
        );
      }

      if (displayNotes.isEmpty) {
        child = ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
          children: [body],
        );
      } else {
        final sectioned = _buildSectionedItems(displayNotes);
        child = ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
          itemCount: sectioned.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) return body;
            return _buildCardItem(sectioned[index - 1]);
          },
        );
      }
    } else if (displayNotes.isEmpty) {
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
            actions: [
              TextButton.icon(
                onPressed: widget.onNewNote,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Create Task'),
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.accent,
                ),
              ),
            ],
          );
          break;
        case 'meeting':
          child = _emptyState(
            icon: Icons.groups_outlined,
            title: 'No meetings recorded',
            subtitle: 'Capture attendees, decisions and action items.',
            actions: [
              TextButton.icon(
                onPressed: widget.onNewNote,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Meeting'),
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.accent,
                ),
              ),
            ],
          );
          break;
        case 'journal':
          child = _emptyState(
            icon: Icons.menu_book_outlined,
            title: 'No journal entries yet',
            subtitle: 'Record your thoughts, wins and lessons.',
            actions: [
              TextButton.icon(
                onPressed: widget.onNewNote,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Journal Entry'),
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.accent,
                ),
              ),
            ],
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
      final sectioned = _buildSectionedItems(displayNotes);
      child = ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
        itemCount: sectioned.length,
        itemBuilder: (context, index) {
          return _buildCardItem(
            sectioned[index],
            isMobilePane: isMobilePane,
            withControls: _mergeControlsIntoList &&
                index == 0 &&
                sectioned[0] is String,
          );
        },
      );
    }
    final switchKey = displayNotes.isEmpty
        ? (widget.searchQuery.isNotEmpty
            ? 'empty-search'
            : 'empty-${widget.activeFilter}')
        : 'list';
    return AnimatedSwitcher(
      duration: AppMotion.duration(context, AppMotion.base),
      switchInCurve: AppMotion.decelerate,
      switchOutCurve: AppMotion.accelerate,
      child: KeyedSubtree(key: ValueKey(switchKey), child: child),
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

  List<dynamic> _buildSectionedItems([List<Note>? source]) {
    final notes = source ?? widget.notes;
    if (widget.activeFilter == 'archive' || widget.activeFilter == 'trash') {
      return notes.toList();
    }
    final items = <dynamic>[];
    String? currentSection;
    for (final note in notes) {
      final section = _dateSection(note.updatedAt);
      if (section != currentSection) {
        items.add(section);
        currentSection = section;
      }
      items.add(note);
    }
    return items;
  }

  Widget _buildSectionHeader(String label, {List<Widget>? trailing}) {
    final hasTrailing = trailing != null && trailing.isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        0,
        hasTrailing ? 6 : 24,
        0,
        hasTrailing ? 6 : 8,
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: AppType.t11,
              fontWeight: FontWeight.w600,
              color: context.colors.muted,
              letterSpacing: 0.08,
              height: 1.2,
            ),
          ),
          if (hasTrailing) ...[const Spacer(), ...trailing],
        ],
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
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
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
                fontSize: AppType.t13_5,
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
  final Map<String, int> budgetActuals;
  final List<MoneyEntry>? financeEntries;
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
    this.budgetActuals = const {},
    this.financeEntries,
    this.onChecklistToggle,
  });

  @override
  State<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<_NoteCard> {
  double _dragOffset = 0;
  bool _isSnapping = false;
  bool _hovered = false;
  bool _pressed = false;

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
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: Padding(
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
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Center(
                  child: Icon(
                    Icons.delete_outline,
                    color: context.colors.onDestructive,
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
                  // Neutral reveal — income green implied a money meaning
                  // for what is an archive action.
                  color: context.colors.muted,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Center(
                  child: Icon(
                    Icons.archive_outlined,
                    color: AppColors.readableOn(context.colors.muted),
                    size: 26,
                  ),
                ),
              ),
            ),
          AnimatedContainer(
            duration: _isSnapping
                ? AppMotion.duration(context, AppMotion.base)
                : Duration.zero,
            curve: AppMotion.decelerate,
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
    ),
  ),
);
  }

  Widget _buildCard() {
    // ponytail: compact 2-line card for finance notes — title + amount on row 1,
    // time + entry count on row 2. No content preview, no tag chips. Other
    // filters keep the full card layout.
    final isFinance =
        widget.activeFilter == 'finance' && widget.note.type != 'text';
    final isDesktop = MediaQuery.of(context).size.width >= 1024;

    return Semantics(
      button: true,
      label: widget.note.title.isEmpty ? 'Untitled' : widget.note.title,
      child: InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(isDesktop ? AppRadius.chip : AppRadius.card),
      child: AnimatedContainer(
        duration: AppMotion.duration(context, AppMotion.base),
        curve: AppMotion.emphasized,
        padding: isFinance
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
            : EdgeInsets.symmetric(
                horizontal: isDesktop ? 12 : 14,
                vertical: isDesktop ? 11 : 14,
              ),
        decoration: BoxDecoration(
          color: isDesktop && !widget.selected
              ? Colors.transparent
              : context.colors.surface,
          // Desktop pairs a non-uniform border (accent rail + hairline) with
          // this decoration; a borderRadius on non-uniform border colors
          // throws in debug paints, and release already ignores the radius
          // for the border — so desktop drops it (release pixels unchanged).
          borderRadius: isDesktop ? null : BorderRadius.circular(AppRadius.card),
          border: isDesktop
              ? Border(
                  left: BorderSide(
                    color: widget.selected || _hovered
                        ? context.colors.accent
                        : Colors.transparent,
                    width: 2,
                  ),
                  bottom: BorderSide(
                    color: context.colors.border.withValues(alpha: 0.7),
                  ),
                )
              : Border.all(
                  color: widget.selected
                      ? context.colors.accent
                      : Colors.transparent,
                  width: widget.selected ? 1 : 0,
                ),
          boxShadow: null,
        ),
        transform: Matrix4.translationValues(
          0,
          _hovered && isDesktop && !_pressed ? -2 : 0,
          0,
        )..scaleByDouble(
          _pressed ? 0.985 : 1.0,
          _pressed ? 0.985 : 1.0,
          1.0,
          1.0,
        ),
        child: isFinance ? _buildFinanceCardBody() : _buildFullCardBody(),
      ),
      ),
    );
  }

  Widget _buildFinanceCardBody() {
    final amounts = widget.financeEntries ?? widget.note.amounts;
    final incomeEntries = amounts
        .where((e) => (e.type ?? widget.note.type) == 'income')
        .toList();
    final expenseEntries = amounts
        .where((e) => (e.type ?? widget.note.type) == 'expense')
        .toList();
    final hasIncome = incomeEntries.isNotEmpty;
    final hasExpense = expenseEntries.isNotEmpty;
    final amountColor = hasIncome && !hasExpense
        ? context.colors.income
        : hasIncome && hasExpense
            ? context.colors.accent
            : context.colors.fg;
    final dominant = _dominantCategory(widget.note, amounts);
    final budget = dominant != null
        ? widget.budgets.cast<Budget?>().firstWhere(
            (b) => b!.category == dominant,
            orElse: () => null,
          )
        : null;
    // Calendar-period spend for this budget's category across ALL notes —
    // comparing a single note's entries against the whole monthly limit
    // used to render a misleading progress bar.
    final budgetActual = budget != null
        ? widget.budgetActuals[budget.id] ?? 0
        : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
               Icon(
                hasIncome && hasExpense
                    ? Icons.swap_vert
                    : hasIncome
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                size: 12,
                color: amountColor,
             ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.note.title,
                style: TextStyle(
                  fontSize: AppType.t13_5,
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
                    fontSize: AppType.t12,
                    fontFamily: context.colors.monoFontFamily,
                    fontWeight: FontWeight.w600,
                   color: amountColor,
                  ),
                  children: _buildCardAmountSpans(
                    widget.note,
                    widget.financeEntries,
                  ),
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
                      value: budget.limit > 0
                          ? (budgetActual / budget.limit).clamp(0.0, 1.0)
                          : (budgetActual > 0 ? 1.0 : 0.0),
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
                Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: AppType.t10,
                      fontFamily: context.colors.monoFontFamily,
                      color: budgetActual > budget.limit
                          ? context.colors.destructive
                          : context.colors.muted,
                    ),
                    children: [
                      currencySpan(budget.currency, null),
                      TextSpan(
                        text: formatMinor(budgetActual, budget.currency),
                      ),
                      const TextSpan(text: ' / '),
                      currencySpan(budget.currency, null),
                      TextSpan(
                        text: formatMinor(budget.limit, budget.currency),
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

  String? _dominantCategory(Note note, [List<MoneyEntry>? amounts]) {
    final entries = amounts ?? note.amounts;
    if (entries.isEmpty) return null;
    final totals = <String, int>{};
    for (final e in entries) {
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
    final taskItems =
        (widget.activeFilter == 'tasks' && widget.onChecklistToggle != null)
        ? parseChecklist(widget.note.content)
        : const <ChecklistItem>[];
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
                  fontSize: AppType.t13_5,
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
        if (taskItems.isEmpty && _contentPreview(widget.note.content).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              _contentPreview(widget.note.content),
              style: TextStyle(
                fontSize: AppType.t12,
                color: context.colors.muted,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (taskItems.isNotEmpty) _buildTaskChecklist(taskItems),
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
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                      ),
                      child: Text(
                        '#$t',
                        style: TextStyle(
                          fontSize: AppType.t12,
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
              // Up for income, down for expense — matching the finance card
              // and quick actions (the full card previously had these
              // inverted).
              Icon(
                widget.note.type == 'income'
                    ? Icons.arrow_upward
                    : Icons.arrow_downward,
                size: 10,
                color: widget.note.type == 'income'
                    ? context.colors.income
                    : context.colors.fg,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: AppType.t12,
                      fontFamily: context.colors.monoFontFamily,
                      fontWeight: FontWeight.w500,
                      color: widget.note.type == 'income'
                          ? context.colors.income
                          : context.colors.fg,
                    ),
                    children: _buildCardAmountSpans(
                      widget.note,
                      widget.financeEntries,
                    ),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
               if ((widget.financeEntries ?? widget.note.amounts).length > 1) ...[
                const SizedBox(width: 4),
                Text(
                  '(${widget.note.amounts.length} entries)',
                  style: TextStyle(fontSize: AppType.t10, color: context.colors.muted),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: 6),
        Text(
          _relativeTime(widget.note.updatedAt),
          style: TextStyle(
            fontSize: AppType.t11,
            fontFamily: context.colors.monoFontFamily,
            color: context.colors.muted.withValues(alpha: 0.7),
            letterSpacing: 0.03,
          ),
        ),
      ],
    );
  }

  Widget _buildTaskChecklist(List<ChecklistItem> allItems) {
    final items = allItems.take(5).toList();
    if (items.isEmpty) return const SizedBox.shrink();

    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Column(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: Checkbox(
                        value: item.done,
                        onChanged: (_) => widget.onChecklistToggle!(
                          widget.note,
                          item.lineIndex,
                          !item.done,
                        ),
                        activeColor: c.accent,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      ),
                    ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: InkWell(
                      onTap: () => widget.onChecklistToggle!(
                        widget.note,
                        item.lineIndex,
                        !item.done,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: SizedBox(
                          height: 32,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              stripInlineMarkdown(item.text).isEmpty
                                  ? 'Untitled task'
                                  : stripInlineMarkdown(item.text),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppType.t12,
                                color: item.done ? c.muted : c.fg,
                                decoration: item.done
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _contentPreview(String content) => contentPreview(content);

  static String _relativeTime(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static List<InlineSpan> _buildCardAmountSpans(
    Note note,
    List<MoneyEntry>? filteredAmounts,
  ) {
    final amounts = filteredAmounts ?? note.amounts;
    final income = amounts
        .where((e) => (e.type ?? note.type) == 'income')
        .fold<int>(0, (sum, e) => sum + e.amount);
    final expense = amounts
        .where((e) => (e.type ?? note.type) == 'expense')
        .fold<int>(0, (sum, e) => sum + e.amount);
    final hasIncome = amounts.any((e) => (e.type ?? note.type) == 'income');
    final hasExpense = amounts.any((e) => (e.type ?? note.type) == 'expense');
    final label = hasIncome && hasExpense
        ? 'Net '
        : hasIncome
            ? 'Income '
            : 'Expenses ';
    final total = hasIncome && hasExpense
        ? income - expense
        : hasIncome
            ? income
            : expense;
    final currencies = amounts
        .map((e) => e.currency ?? note.currency ?? 'PHP')
        .toSet();
    if (currencies.length > 1) {
      return const [TextSpan(text: 'Mixed currencies')];
    }
    final currency = currencies.isEmpty
        ? (note.currency ?? 'PHP')
        : currencies.first;
    return [
      TextSpan(text: label),
      ...moneySpans(total, currency, null),
    ];
  }
}
