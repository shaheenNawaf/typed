import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/money_entry.dart';
import '../models/note.dart';
import '../models/budget.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../theme/app_motion.dart';
import '../utils/backup.dart';
import '../utils/date_format.dart';
import '../utils/finance_utils.dart';
import '../utils/id.dart';
import '../utils/markdown_display.dart';
import '../utils/note_storage.dart';
import '../utils/notifications.dart';
import '../utils/onboarding.dart';
import '../utils/recurrence.dart';
import '../utils/templates.dart';
import '../widgets/brand_mark.dart';
import '../widgets/settings_sheet.dart';
import '../widgets/sidebar.dart';
import '../widgets/note_list.dart';
import '../widgets/editor.dart';
import '../widgets/mobile_nav.dart';
import '../widgets/template_picker_sheet.dart';
import '../widgets/finance_dashboard.dart';
import '../widgets/entry_sheet.dart';
import '../widgets/context_panel.dart';
import '../widgets/workspace_header.dart';
import '../widgets/command_palette.dart';
import 'onboarding_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _storage = NoteStorage();

  List<Note> notes = [];
  String? _currentNoteId;
  bool _sortDesc = true;
  String _activeFilter = 'notes';
  String _sidebarState = 'expanded';
  String _searchQuery = '';
  String _currentTab = 'home';
  String? _activeTag;
  bool _showEditor = false;
  bool _contextPanelOpen = false;
  bool _commandPaletteOpen = false;
  bool _previewMode = false;
  bool _isLoading = true;
  Object? _loadError;
  Timer? _persistTimer;
  List<String> _customCategories = [];
  List<String> _recentCategories = [];
  Future<void> _categoryWrite = Future.value();
  String _financePeriod = 'all';
  String _financeCurrency = 'all';
  // 'simple' | 'advanced' — Simple is the calm this-month default; Advanced
  // is the full dashboard. The choice is made during onboarding and lives
  // in the persisted shell state.
  String _financeMode = 'simple';
  bool _onboardingOpen = false;
  static const _onboardingCompleteKey = 'onboarding_flow_complete_v1';
  List<Budget> _budgets = [];
  Timer? _shellTimer;
  Timer? _savedResetTimer;
  Timer? _searchDebounce;
  late final AnimationController _shimmer;
  // Home plays its section entrance once per app start; afterwards plain
  // children render so revisiting Home never replays it.
  bool _homeAnimated = false;
  String _saveState = 'idle'; // idle | saving | saved
  static const _shellPrefsKey = 'shell_state_v1';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _loadAndHandleIntent();
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    // Persist the workspace layout (open note, filter, tab, sidebar, sort,
    // finance scope) on any state change, debounced — instead of teaching
    // every navigation mutator about it.
    _shellTimer?.cancel();
    _shellTimer = Timer(const Duration(milliseconds: 750), _saveShellState);
  }

  Future<void> _saveShellState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _shellPrefsKey,
        jsonEncode({
          'noteId': _currentNoteId,
          'filter': _activeFilter,
          'tab': _currentTab,
          'sidebar': _sidebarState,
          'sortDesc': _sortDesc,
          'financePeriod': _financePeriod,
          'financeCurrency': _financeCurrency,
          'financeMode': _financeMode,
          'showEditor': _showEditor,
          'previewMode': _previewMode,
        }),
      );
    } catch (_) {}
  }

  void _applyShellState(SharedPreferences prefs) {
    final raw = prefs.getString(_shellPrefsKey);
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final noteId = data['noteId'] as String?;
      if (noteId != null &&
          notes.any((n) => n.id == noteId && !n.isDeleted && !n.isArchived)) {
        _currentNoteId = noteId;
        _showEditor = data['showEditor'] == true;
        _previewMode = data['previewMode'] == true;
      }
      final filter = data['filter'] as String?;
      if (filter != null) _activeFilter = filter;
      final tab = data['tab'] as String?;
      if (tab != null) _currentTab = tab;
      final sidebar = data['sidebar'] as String?;
      if (sidebar != null) _sidebarState = sidebar;
      _sortDesc = data['sortDesc'] as bool? ?? _sortDesc;
      final period = data['financePeriod'] as String?;
      if (period != null) _financePeriod = period;
      final currency = data['financeCurrency'] as String?;
      if (currency != null) _financeCurrency = currency;
      final financeMode = data['financeMode'] as String?;
      if (financeMode == 'simple' || financeMode == 'advanced') {
        _financeMode = financeMode!;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shimmer.dispose();
    _persistTimer?.cancel();
    _shellTimer?.cancel();
    _savedResetTimer?.cancel();
    _searchDebounce?.cancel();
    _saveShellState();
    unawaited(_storage.save(notes).catchError((_) {}));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Widget taps and notification taps that arrive while the app is
    // already running used to be dropped (getIntent was only polled during
    // cold start). Re-check on every resume. Paused/inactive is also the
    // last safe moment to flush edits before Android can kill the process.
    if (state == AppLifecycleState.resumed) {
      _consumePendingAction();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_persistTimer?.isActive ?? false) {
        _persistTimer?.cancel();
        unawaited(_storage.save(notes).catchError((_) {}));
      }
      _shellTimer?.cancel();
      _saveShellState();
    }
  }

  Future<void> _loadAndHandleIntent() async {
    try {
      final hasData = await _storage.hasSavedData();
      if (hasData) {
        final result = await _storage.loadResult();
        if (result.hasError) throw result.error!;
        if (mounted) setState(() => notes = result.items);

        final budgetResult = await _storage.loadBudgetsResult();
        if (budgetResult.hasError) throw budgetResult.error!;
        if (mounted) setState(() => _budgets = budgetResult.items);
      } else {
        final data = createOnboardingData();
        if (mounted) {
          setState(() {
            notes = data.notes;
            _budgets = data.budgets;
            _activeFilter = 'home';
            _currentTab = 'home';
            _currentNoteId = null;
            _showEditor = false;
            _previewMode = false;
            _contextPanelOpen = false;
          });
        }
        await Future.wait([
          _storage.save(data.notes),
          _storage.saveBudgets(data.budgets),
        ]);
      }

      _purgeExpiredTrash();

      final prefs = await SharedPreferences.getInstance();
      var onboardingChanged = _appendWelcomeUpdate();
      // Guides are seeded once and then never resurrected; deleting a guide
      // used to bring it back on the next launch.
      if (!(prefs.getBool('onboarded_v1') ?? false) &&
          _ensureWorkspaceGuides()) {
        onboardingChanged = true;
      }
      await prefs.setBool('onboarded_v1', true);
      if (onboardingChanged) _persistNow();

      _generateRecurringEntries();
      final cats = prefs.getStringList('custom_categories') ?? [];
      final recent = prefs.getStringList('recent_categories') ?? [];
      if (mounted) {
        setState(() {
          _customCategories = cats;
          _recentCategories = recent;
          _applyShellState(prefs);
        });
      }

      await _syncNotifications(checkBudgets: true);

      if (!mounted) return;
      setState(() => _isLoading = false);
      // First launch (and once per major update if the flow has never been
      // completed): show the introduction before the workspace.
      if (!(prefs.getBool(_onboardingCompleteKey) ?? false)) {
        setState(() => _onboardingOpen = true);
      }
      await _drainStashedActions();
      await _consumePendingAction();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _isLoading = false;
      });
    }
  }

  bool _consumingIntent = false;

  /// Widget actions that arrived while the initial load was still running.
  /// The Kotlin side pops intents off a queue, so they are stashed here
  /// instead of being dropped and drained once loading finishes.
  final List<String> _stashedActions = [];

  /// Single consumer for widget and notification actions, called on cold
  /// start and on every resume so warm taps are no longer dropped (and a
  /// consumed action cannot fire a second time on the next launch).
  Future<void> _consumePendingAction() async {
    if (_consumingIntent) return;
    _consumingIntent = true;
    try {
      const channel = MethodChannel('com.z4yed.typed/widget');
      String? action = await _pullWidgetIntent(channel);
      action ??= await NotificationService.consumePendingAction();
      // The native side queues actions; drain until the queue is empty.
      while (action != null) {
        if (!mounted) return;
        if (_isLoading) {
          _stashedActions.add(action);
        } else {
          _handleIntentAction(action);
        }
        action = await _pullWidgetIntent(channel);
      }
    } finally {
      _consumingIntent = false;
    }
  }

  Future<String?> _pullWidgetIntent(MethodChannel channel) async {
    try {
      return await channel.invokeMethod<String>('getIntent');
    } on PlatformException {
      // Widget intents are optional on non-Android platforms.
      return null;
    } on MissingPluginException {
      // Widget intents are optional on non-Android platforms.
      return null;
    }
  }

  /// Runs the stashed actions once the initial load has completed.
  Future<void> _drainStashedActions() async {
    while (_stashedActions.isNotEmpty && mounted) {
      _handleIntentAction(_stashedActions.removeAt(0));
    }
  }

  void _handleIntentAction(String intentAction) {
    if (_onboardingOpen) {
      // Widget taps during the introduction are processed right after it
      // closes instead of firing underneath it.
      _stashedActions.add(intentAction);
      return;
    }
    if (intentAction == 'new') {
      _openTemplatePicker();
    } else if (intentAction == 'expense') {
      _quickAddEntry();
    } else if (intentAction == 'income') {
      _quickAddIncome();
    } else if (intentAction == 'finance') {
      _setFilter('finance');
    } else if (intentAction.startsWith('open:')) {
      final id = intentAction.substring(5);
      if (notes.any((n) => n.id == id)) _selectNote(id);
    } else if (intentAction.startsWith('toggle:')) {
      // "toggle:<id>:<encodedText>[:<doneAtTap>]" — the done-at-tap flag is
      // set by the widget; a replayed stale dispatch whose target line is
      // already in the post-toggle state is ignored.
      final parts = intentAction.substring(7).split(':');
      if (parts.isNotEmpty && parts[0].isNotEmpty && parts.length > 1) {
        final expectedDone = parts.length > 2 ? parts[2] == '1' : null;
        _toggleChecklistByContent(
          parts[0],
          Uri.decodeComponent(parts[1]),
          expectedDone: expectedDone,
        );
      }
    }
  }

  /// Toggles the first checklist line whose text matches [text]; used by
  /// the Android to-do widget's checkbox, which carries the note id and the
  /// item text rather than a fragile positional index. [expectedDone] is the
  /// item's state at tap time — when the line has already been toggled since
  /// (a stale or replayed dispatch), the request is skipped.
  void _toggleChecklistByContent(String noteId, String text, {bool? expectedDone}) {
    final note = _noteById(noteId);
    if (note == null) return;
    final lines = note.content.split('\n');
    final marker = RegExp(r'^(\s*-\s+\[)([ xX])(\]\s+.*)$');
    for (var i = 0; i < lines.length; i++) {
      final m = marker.firstMatch(lines[i]);
      if (m == null || stripInlineMarkdown(m.group(3)!.substring(1)) != stripInlineMarkdown(text)) {
        continue;
      }
      final checked = m.group(2) != ' ';
      if (expectedDone != null && checked != expectedDone) {
        return;
      }
      lines[i] = '${m.group(1)}${checked ? ' ' : 'x'}${m.group(3)}';
      note.content = lines.join('\n');
      note.updatedAt = DateTime.now();
      _persistNow();
      if (mounted) setState(() {});
      return;
    }
  }

  void _onCategoryUsed(String category) {
    _recentCategories = [
      category,
      ..._recentCategories.where((c) => c != category).take(19),
    ];
    if (!_customCategories.contains(category) &&
        !kDefaultCategories.contains(category)) {
      _customCategories = [..._customCategories, category];
    }
    _categoryWrite = _categoryWrite
        .then((_) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList('recent_categories', _recentCategories);
          await prefs.setStringList('custom_categories', _customCategories);
        })
        .catchError((_) {});
  }

  /// Trashed notes are permanently removed after 30 days — a retention
  /// policy, so trash does not grow forever while still forgiving an
  /// accidental delete for a full month. Runs once per launch.
  void _purgeExpiredTrash() {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final expired = notes
        .where((n) => n.isDeleted && n.updatedAt.isBefore(cutoff))
        .toList();
    if (expired.isEmpty) return;
    notes.removeWhere((n) => n.isDeleted && n.updatedAt.isBefore(cutoff));
    if (_currentNoteId != null && expired.any((n) => n.id == _currentNoteId)) {
      _currentNoteId = null;
      _showEditor = false;
    }
    _persistNow();
  }

  void _generateRecurringEntries() {
    final today = DateTime.now();
    var changed = false;

    for (final note in notes) {
      if (note.type == 'text') continue;
      for (final entry in note.amounts.toList()) {
        if (!entry.isRecurring || entry.recurInterval == null) continue;
        if (entry.lastGenerated == null) {
          entry.lastGenerated = entry.date;
          changed = true;
        }
        for (final date in plannedOccurrences(
          anchor: entry.date,
          interval: entry.recurInterval!,
          lastGenerated: entry.lastGenerated!,
          today: today,
          end: entry.recurEnd,
        )) {
          note.amounts.add(
            MoneyEntry(
              id: generateId('m'),
              amount: entry.amount,
              category: entry.category,
              date: date,
              note: entry.note,
              paymentMethod: entry.paymentMethod,
              currency: entry.currency,
              type: entry.type,
            ),
          );
          entry.lastGenerated = date;
          changed = true;
        }
      }
    }
    if (changed) _persistNow();
  }

  void _addBudget(Budget budget) {
    setState(() {
      final index = _budgets.indexWhere((b) => b.id == budget.id);
      if (index == -1) {
        _budgets = [..._budgets, budget];
      } else {
        final updated = [..._budgets];
        updated[index] = budget;
        _budgets = updated;
      }
    });
    _storage.saveBudgets(_budgets);
    _syncNotifications(checkBudgets: true);
  }

  void _removeBudget(Budget budget) {
    showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete budget?'),
        content: Text('Remove the ${budget.category} budget?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed != true || !mounted) return;
      setState(
        () => _budgets = _budgets.where((b) => b.id != budget.id).toList(),
      );
      _storage.saveBudgets(_budgets);
      _syncNotifications(checkBudgets: true);
    });
  }

  // ponytail: quick-add finds or auto-creates a "Quick expenses — {today}"
  // note and opens EntrySheet against it. One-tap flow from the Finance
  // note list header.
  Note _findOrCreateQuickNote(String type) {
    final today = DateTime.now();
    final dateStr = _quickDateLabel(today);
    final label = type == 'income'
        ? 'Quick income — $dateStr'
        : 'Quick expenses — $dateStr';
    final todayDate = DateTime(today.year, today.month, today.day);
    // Look for an existing quick note for this type and date
    for (final n in notes) {
      if (n.isArchived || n.isDeleted) continue;
      if (n.type != type) continue;
      if (n.title != label) continue;
      final nDate = DateTime(
        n.updatedAt.year,
        n.updatedAt.month,
        n.updatedAt.day,
      );
      if (nDate == todayDate) return n;
    }
    // Otherwise create one
    final id = generateId('n');
    final note = Note(
      id: id,
      title: label,
      content: '',
      tags: ['finance'],
      type: type,
      currency: 'PHP',
    );
    notes.insert(0, note);
    return note;
  }

  String _quickDateLabel(DateTime d) => dayLabel(d);

  void _quickAddEntry() => _quickAddTransaction('expense');

  void _quickAddIncome() => _quickAddTransaction('income');

  /// Dock Create on the Finance tab: the 1-tap expense/income chooser
  /// (moved from the removed note-list quick-add FAB).
  void _showFinanceQuickSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.arrow_downward, color: context.colors.destructive),
              title: const Text('Add expense'),
              subtitle: const Text('Record money leaving your accounts'),
              onTap: () {
                Navigator.pop(sheetContext);
                _quickAddEntry();
              },
            ),
            ListTile(
              leading: Icon(Icons.arrow_upward, color: context.colors.income),
              title: const Text('Add income'),
              subtitle: const Text('Record money coming in'),
              onTap: () {
                Navigator.pop(sheetContext);
                _quickAddIncome();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Single mobile create affordance: context-aware by tab.
  void _onDockCreate() {
    if (_currentTab == 'finance') {
      _showFinanceQuickSheet();
    } else {
      _openTemplatePicker();
    }
  }

  void _quickAddTransaction(String type) {
    final note = _findOrCreateQuickNote(type);
    setState(() {
      _currentNoteId = note.id;
      _activeFilter = 'finance';
      _currentTab = 'finance';
      _showEditor = true;
      _previewMode = false;
    });
    _persistNow();
    // Defer the EntrySheet open until after the editor is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      EntrySheet.show(
        context,
        onSave: (entry) {
          note.amounts.add(entry);
          note.updatedAt = DateTime.now();
          _persistNow();
          setState(() {});
          HapticFeedback.lightImpact();
          _showLogLandingSnackBar(entry, note);
        },
        currencySymbol: currencySymbol(note.currency),
        noteCurrency: note.currency,
        noteType: note.type,
        customCategories: _customCategories,
        recentCategories: _recentCategories,
        onCategoryUsed: _onCategoryUsed,
      );
    });
  }

  /// Progress-centric confirmation after a quick-add: the entry amount in its
  /// own currency, then the running total for the entry's month in the
  /// dominant currency ("₱185.50 logged · September: ₱9,325.75 out").
  /// Never sums across currencies — the total is dominant-currency only.
  void _showLogLandingSnackBar(MoneyEntry entry, Note note) {
    final entryCurrency = entry.currency ?? note.currency;
    final amount = formatMinorAmount(entry.amount, entryCurrency);
    final (hasData, spent, earned, dominant, _) =
        _monthFinanceTotals(entry.date);
    if (!hasData) {
      _showSnackBar('$amount logged');
      return;
    }
    final isIncome = (entry.type ?? note.type) == 'income';
    final total = formatMinorAmount(isIncome ? earned : spent, dominant);
    final month = monthName(entry.date.month);
    _showSnackBar(
      '$amount logged · $month: $total ${isIncome ? 'in' : 'out'}',
    );
  }

  /// Edit a single entry in place from a dashboard transaction row: opens the
  /// EntrySheet against the entry and replaces it inside its parent note.
  /// No navigation — the user stays on the dashboard. Mirrors the editor's
  /// pencil-edit flow (editor.dart _buildTransactionItem).
  void _editEntryFromDashboard(String noteId, String entryId) {
    final note = _noteById(noteId);
    if (note == null) return;
    final index = note.amounts.indexWhere((e) => e.id == entryId);
    if (index < 0) return;
    final entry = note.amounts[index];
    EntrySheet.show(
      context,
      entry: entry,
      onSave: (updated) {
        note.amounts[index] = updated;
        note.updatedAt = DateTime.now();
        _persistNow();
        setState(() {});
      },
      currencySymbol: currencySymbol(entry.currency ?? note.currency),
      noteCurrency: note.currency,
      noteType: note.type,
      customCategories: _customCategories,
      recentCategories: _recentCategories,
      onCategoryUsed: _onCategoryUsed,
    );
  }

  bool _saveErrorReported = false;

  void _persist() {
    _persistTimer?.cancel();
    _saveState = 'saving';
    _persistTimer = Timer(const Duration(milliseconds: 400), _persistNow);
  }

  void _persistNow() {
    _persistTimer?.cancel();
    _saveState = 'saving';
    _storage
        .save(notes)
        .then((_) {
          _saveErrorReported = false;
          if (!mounted) return;
          setState(() => _saveState = 'saved');
          _savedResetTimer?.cancel();
          _savedResetTimer = Timer(const Duration(seconds: 2), () {
            if (mounted) setState(() => _saveState = 'idle');
          });
          _syncNotifications();
        })
        .catchError((Object error) {
          // Without this the write failure is an unhandled async exception and
          // the user keeps typing into a session that is no longer persisting.
          if (!mounted || _saveErrorReported) return;
          _saveErrorReported = true;
          setState(() => _saveState = 'idle');
          _showSnackBar('Could not save to storage: $error', error: true);
        });
  }

  void _onSearchInput(String value) {
    // Debounced so every keystroke does not rebuild the shell and re-run
    // all derived getters over the full note list.
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _searchQuery = value);
    });
  }

  Future<void> _syncNotifications({bool checkBudgets = false}) async {
    try {
      await NotificationService.instance.sync(
        notes: notes,
        budgets: _budgets,
        checkBudgets: checkBudgets,
      );
    } catch (_) {}
  }

  List<String> get _allTags {
    final tags = <String>{};
    for (final n in notes.where((n) => !n.isArchived && !n.isDeleted)) {
      for (final tag in n.tags) {
        final normalized = _normalizeTag(tag);
        if (normalized.isNotEmpty) tags.add(normalized);
      }
    }
    final list = tags.toList()..sort();
    return list;
  }

  Map<String, int> get _tagCounts {
    final counts = <String, int>{};
    for (final n in notes.where((n) => !n.isArchived && !n.isDeleted)) {
      for (final tag in n.tags) {
        final normalized = _normalizeTag(tag);
        if (normalized.isNotEmpty) {
          counts[normalized] = (counts[normalized] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  bool _appendWelcomeUpdate() {
    final welcome = notes.cast<Note?>().firstWhere(
      (note) => note?.id.endsWith('_welcome') == true,
      orElse: () => null,
    );
    if (welcome == null || welcome.content.contains(kWelcomeUpdateMarker)) {
      return false;
    }
    welcome.content = '${welcome.content.trim()}\n\n$kWelcomeUpdateContent';
    welcome.updatedAt = DateTime.now();
    return true;
  }

  bool _ensureWorkspaceGuides() {
    final existingTitles = notes.map((note) => note.title).toSet();
    final missing = createWorkspaceGuideNotes().where(
      (guide) => !existingTitles.contains(guide.title),
    );
    final additions = missing.toList();
    if (additions.isEmpty) return false;
    notes.addAll(additions);
    return true;
  }

  String _normalizeTag(String tag) =>
      tag.trim().replaceFirst(RegExp(r'^#+'), '').trim();

  List<Note> get _pinnedNotes =>
      notes.where((n) => n.isPinned && !n.isArchived && !n.isDeleted).toList();

  Map<String, int> get _counts => {
    'home': notes.where((n) => !n.isArchived && !n.isDeleted).length,
    'notes': notes.where((n) => !n.isArchived && !n.isDeleted).length,
    'tasks': notes.where(_isTaskNote).length,
    'meeting': notes.where(_isMeetingNote).length,
    'journal': notes.where(_isJournalNote).length,
    'finance': notes
        .where((n) => n.type != 'text' && !n.isArchived && !n.isDeleted)
        .length,
    'archive': notes.where((n) => n.isArchived && !n.isDeleted).length,
    'trash': notes.where((n) => n.isDeleted).length,
  };

  // Classification prefers the structured type and template tags; the title
  // substring is a legacy fallback so old notes keep landing in the same
  // workspaces they always did. Seeds/guides are demo material — excluded.
  bool _isTaskNote(Note n) => isTaskNote(n);

  bool _isMeetingNote(Note n) =>
      !n.isArchived &&
      !n.isDeleted &&
      (n.tags.contains('meeting') || n.title.toLowerCase().contains('meeting'));

  bool _isJournalNote(Note n) =>
      !n.isArchived &&
      !n.isDeleted &&
      (n.tags.contains('journal') || n.title.toLowerCase().contains('journal'));

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  // Simple finance mode always renders a this-month, all-currencies view;
  // the stored period/currency scope only applies to the Advanced dashboard.
  String get _effectiveFinancePeriod =>
      _financeMode == 'simple' ? 'month' : _financePeriod;
  String get _effectiveFinanceCurrency =>
      _financeMode == 'simple' ? 'all' : _financeCurrency;

  bool _isInPeriod(DateTime d) {
    final now = DateTime.now();
    switch (_effectiveFinancePeriod) {
      case 'week':
        final monday = now.subtract(Duration(days: now.weekday - 1));
        final startOfWeek = DateTime(monday.year, monday.month, monday.day);
        return !d.isBefore(startOfWeek) &&
            d.isBefore(startOfWeek.add(const Duration(days: 7)));
      case 'month':
        final startOfMonth = DateTime(now.year, now.month, 1);
        return !d.isBefore(startOfMonth) &&
            d.isBefore(DateTime(now.year, now.month + 1, 1));
      case 'year':
        final startOfYear = DateTime(now.year, 1, 1);
        return !d.isBefore(startOfYear) &&
            d.isBefore(DateTime(now.year + 1, 1, 1));
      default:
        return true;
    }
  }

  bool _isInPreviousPeriod(DateTime d) {
    final now = DateTime.now();
    switch (_effectiveFinancePeriod) {
      case 'week':
        final monday = now.subtract(Duration(days: now.weekday - 1));
        final curStart = DateTime(monday.year, monday.month, monday.day);
        final prevStart = curStart.subtract(const Duration(days: 7));
        return !d.isBefore(prevStart) && d.isBefore(curStart);
      case 'month':
        final curStart = DateTime(now.year, now.month, 1);
        final prevStart = DateTime(now.year, now.month - 1, 1);
        return !d.isBefore(prevStart) && d.isBefore(curStart);
      case 'year':
        final curStart = DateTime(now.year, 1, 1);
        final prevStart = DateTime(now.year - 1, 1, 1);
        return !d.isBefore(prevStart) && d.isBefore(curStart);
      default:
        return false;
    }
  }

  double get _daysInCurrentPeriod {
    final now = DateTime.now();
    switch (_effectiveFinancePeriod) {
      case 'week':
        final monday = now.subtract(Duration(days: now.weekday - 1));
        return now
                .difference(DateTime(monday.year, monday.month, monday.day))
                .inDays +
            1;
      case 'month':
        return now.day.toDouble();
      case 'year':
        return now.difference(DateTime(now.year, 1, 1)).inDays + 1;
      default:
        return 0;
    }
  }

  FinanceSummary get _financeSummary {
    final financeNotes = notes.where(
      (n) => n.type != 'text' && !n.isArchived && !n.isDeleted,
    );

    // Previous-period totals per currency; they can only be resolved against
    // the dominant currency after the loop, so raw ints would silently mix
    // currencies in the comparison.
    final prevIncomeByCurrency = <String, int>{};
    final prevExpenseByCurrency = <String, int>{};
    final categoryByCurrency = <String, Map<String, int>>{};
    final allEntries = <(MoneyEntry, Note)>[];
    final currencyCounts = <String, int>{};
    final incomeByCurrency = <String, int>{};
    final expenseByCurrency = <String, int>{};
    final currenciesUsed = <String>{};
    final noteIdsInPeriod = <String>{};
    final entriesByNote = <String, List<MoneyEntry>>{};

    for (final n in financeNotes) {
      for (final e in n.amounts) {
        final inPeriod = _isInPeriod(e.date);
        final inPrev = _isInPreviousPeriod(e.date);
        if (!inPeriod && !inPrev) continue;

        final cur = e.currency ?? n.currency ?? 'PHP';
        if (_effectiveFinanceCurrency != 'all' &&
            cur != _effectiveFinanceCurrency) {
          continue;
        }
        final effectiveType = e.type ?? n.type;
        if (effectiveType != 'income' && effectiveType != 'expense') continue;

        if (inPeriod) {
          allEntries.add((e, n));
          entriesByNote.putIfAbsent(n.id, () => []).add(e);
          currenciesUsed.add(cur);
          if (effectiveType == 'income') {
            incomeByCurrency[cur] = (incomeByCurrency[cur] ?? 0) + e.amount;
          } else {
            expenseByCurrency[cur] = (expenseByCurrency[cur] ?? 0) + e.amount;
            final byCategory = categoryByCurrency.putIfAbsent(cur, () => {});
            byCategory[e.category] = (byCategory[e.category] ?? 0) + e.amount;
          }
          currencyCounts[cur] = (currencyCounts[cur] ?? 0) + 1;
          noteIdsInPeriod.add(n.id);
        }

        if (inPrev) {
          if (effectiveType == 'income') {
            prevIncomeByCurrency[cur] =
                (prevIncomeByCurrency[cur] ?? 0) + e.amount;
          } else {
            prevExpenseByCurrency[cur] =
                (prevExpenseByCurrency[cur] ?? 0) + e.amount;
          }
        }
      }
    }

    allEntries.sort((a, b) => b.$1.date.compareTo(a.$1.date));
    final dominant = _effectiveFinanceCurrency != 'all'
        ? _effectiveFinanceCurrency
        : currencyCounts.entries.fold<String>(
            'PHP',
            (acc, e) => e.value > (currencyCounts[acc] ?? 0) ? e.key : acc,
          );
    final totalIncome = incomeByCurrency[dominant] ?? 0;
    final totalExpense = expenseByCurrency[dominant] ?? 0;
    final sortedCategories =
        (categoryByCurrency[dominant] ?? {}).entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    // Average daily spend, in minor units per day.
    final avgDaily = _daysInCurrentPeriod > 0
        ? totalExpense / _daysInCurrentPeriod
        : 0.0;

    return FinanceSummary(
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      categories: sortedCategories,
      recentEntries: allEntries,
      entryCount: allEntries.length,
      dominantCurrency: dominant,
      incomeByCurrency: incomeByCurrency,
      expenseByCurrency: expenseByCurrency,
      hasMixedCurrencies: currenciesUsed.length > 1,
      previousPeriodExpense: prevExpenseByCurrency[dominant] ?? 0,
      previousPeriodIncome: prevIncomeByCurrency[dominant] ?? 0,
      averageDailySpend: avgDaily,
      averageAvailable: _financePeriod != 'all',
      noteIds: noteIdsInPeriod,
      entriesByNote: entriesByNote,
    );
  }

  /// Minor-unit expense totals per day for the last 14 days (oldest -> newest,
  /// index 13 = today), in the dashboard's dominant currency. Feeds the
  /// SpendSparkline trend card.
  List<int> get _last14DaySpend {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(const Duration(days: 13));
    final dominant = _financeSummary.dominantCurrency;
    final totals = List<int>.filled(14, 0);
    for (final n in notes) {
      if (n.type == 'text' || n.isArchived || n.isDeleted) continue;
      for (final e in n.amounts) {
        if ((e.type ?? n.type) != 'expense') continue;
        if ((e.currency ?? n.currency ?? 'PHP') != dominant) continue;
        final day = DateTime(e.date.year, e.date.month, e.date.day);
        if (day.isBefore(start) || day.isAfter(today)) continue;
        totals[day.difference(start).inDays] += e.amount;
      }
    }
    return totals;
  }

  /// Spend per budget against the budget's own calendar period (this week /
  /// this month / this year), scoped to the budget's category and currency.
  /// The dashboard's period selector must not leak into budget math — a
  /// weekly budget under the "All" filter previously compared lifetime spend
  /// against a weekly limit.
  Map<String, int> get _budgetActuals {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: now.weekday - 1));
    final monthStart = DateTime(now.year, now.month);
    final yearStart = DateTime(now.year);

    final actuals = <String, int>{};
    for (final budget in _budgets) {
      final start = switch (budget.period) {
        'week' => weekStart,
        'year' => yearStart,
        _ => monthStart,
      };
      var spent = 0;
      for (final n in notes) {
        if (n.isArchived || n.isDeleted || n.type == 'text') continue;
        for (final e in n.amounts) {
          if ((e.type ?? n.type) != 'expense') continue;
          if (e.date.isBefore(start)) continue;
          if ((e.currency ?? n.currency ?? 'PHP') != budget.currency) continue;
          if (e.category != budget.category) continue;
          spent += e.amount;
        }
      }
      actuals[budget.id] = spent;
    }
    return actuals;
  }

  List<String> get _financeCurrencyOptions {
    final currencies = <String>{'all'};
    for (final note in notes) {
      if (note.type == 'text' || note.isArchived || note.isDeleted) continue;
      currencies.add(note.currency ?? 'PHP');
      currencies.addAll(
        note.amounts.map((entry) => entry.currency ?? note.currency ?? 'PHP'),
      );
    }
    final sorted = currencies.toList()..sort();
    sorted.remove('all');
    return ['all', ...sorted];
  }

  String _dashboardCurrencySymbol(String? code) => currencySymbol(code);

  List<Note> get _filteredNotes {
    var filtered = notes.toList();

    switch (_activeFilter) {
      case 'pinned':
        filtered = filtered
            .where((n) => n.isPinned && !n.isArchived && !n.isDeleted)
            .toList();
      case 'untagged':
        filtered = filtered
            .where((n) => n.tags.isEmpty && !n.isArchived && !n.isDeleted)
            .toList();
      case 'tasks':
        filtered = filtered.where(_isTaskNote).toList();
      case 'today':
        filtered = filtered
            .where(
              (n) => !n.isArchived && !n.isDeleted && _isToday(n.updatedAt),
            )
            .toList();
      case 'finance':
        filtered = filtered
            .where((n) => n.type != 'text' && !n.isArchived && !n.isDeleted)
            .toList();
      case 'meeting':
        filtered = filtered.where(_isMeetingNote).toList();
      case 'journal':
        filtered = filtered.where(_isJournalNote).toList();
      case 'archive':
        filtered = filtered.where((n) => n.isArchived && !n.isDeleted).toList();
      case 'trash':
        filtered = filtered.where((n) => n.isDeleted).toList();
      default:
        filtered = filtered
            .where((n) => !n.isArchived && !n.isDeleted)
            .toList();
    }

    if (_activeTag != null) {
      final activeTag = _normalizeTag(_activeTag!);
      filtered = filtered
          .where((n) => n.tags.any((tag) => _normalizeTag(tag) == activeTag))
          .toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered
          .where(
            (n) =>
                n.title.toLowerCase().contains(q) ||
                n.content.toLowerCase().contains(q) ||
                n.tags.any((t) => t.toLowerCase().contains(q)),
          )
          .toList();
    }

    filtered.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      if (_sortDesc) {
        return b.updatedAt.compareTo(a.updatedAt);
      }
      return a.title.compareTo(b.title);
    });

    return filtered;
  }

  Note? _noteById(String? id) {
    if (id == null) return null;
    for (final n in notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  Note? get _currentNote => _noteById(_currentNoteId);

  void _archive(Note note) {
    note.isArchived = true;
    note.updatedAt = DateTime.now();
    if (_currentNoteId == note.id) {
      _currentNoteId = null;
      _showEditor = false;
    }
    _persistNow();
    setState(() {});
    _showSnackBar('Archived', onUndo: () => _restore(note));
  }

  void _togglePin(Note note) {
    note.isPinned = !note.isPinned;
    note.updatedAt = DateTime.now();
    _persistNow();
    setState(() {});
    _showSnackBar(note.isPinned ? 'Pinned' : 'Unpinned');
  }

  void _trash(Note note) {
    note.isDeleted = true;
    note.updatedAt = DateTime.now();
    if (_currentNoteId == note.id) {
      _currentNoteId = null;
      _showEditor = false;
    }
    _persistNow();
    setState(() {});
    _showSnackBar('Moved to trash', onUndo: () => _restore(note));
  }

  void _restore(Note note) {
    note.isArchived = false;
    note.isDeleted = false;
    note.updatedAt = DateTime.now();
    _persistNow();
    setState(() {});
  }

  Future<void> _deletePermanently(Note note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: Text('"${note.title}" will be gone forever.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: context.colors.destructive,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final index = notes.indexWhere((n) => n.id == note.id);
    if (index == -1) return;
    final wasArchived = note.isArchived;
    final wasDeleted = note.isDeleted;
    notes.removeAt(index);
    if (_currentNoteId == note.id) {
      _currentNoteId = null;
      _showEditor = false;
    }
    _persistNow();
    setState(() {});
    _showSnackBar(
      'Deleted permanently',
      onUndo: () {
        setState(() {
          notes.insert(index, note);
          note.isArchived = wasArchived;
          note.isDeleted = wasDeleted;
        });
        _persistNow();
      },
    );
  }

  Future<void> _emptyTrash() async {
    final trashed = notes.where((n) => n.isDeleted).toList();
    if (trashed.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Empty trash?'),
        content: Text(
          '${trashed.length} note${trashed.length == 1 ? '' : 's'} will be deleted permanently.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: context.colors.destructive,
            ),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    notes.removeWhere((n) => n.isDeleted);
    if (_currentNoteId != null && !notes.any((n) => n.id == _currentNoteId)) {
      _currentNoteId = null;
      _showEditor = false;
    }
    _persistNow();
    setState(() {});
    _showSnackBar('Trash emptied');
  }

  void _showSnackBar(
    String message, {
    VoidCallback? onUndo,
    bool error = false,
  }) {
    if (!mounted) return;
    // No clearSnackBars(): clearing destroyed a pending Undo silently.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? context.colors.destructive : null,
        duration: const Duration(seconds: 5),
        action: onUndo != null
            ? SnackBarAction(label: 'Undo', onPressed: onUndo)
            : null,
      ),
    );
  }

  Future<void> _exportNotes() async {
    try {
      final file = await Backup.exportToFile(notes, _budgets);
      await Share.shareXFiles([file], text: 'Typed notes backup');
    } catch (e) {
      _showSnackBar('Export failed: $e');
    }
  }

  Future<void> _exportFinance() async {
    try {
      final file = await Backup.exportFinanceCsv(notes);
      await Share.shareXFiles([file], text: 'Typed finance export');
    } catch (e) {
      _showSnackBar('Export failed: $e');
    }
  }

  Future<void> _importNotes() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.first.bytes;
      final path = result.files.first.path;
      if (bytes == null && path == null) return;

      final imported = bytes != null
          ? await Backup.importFromBytes(bytes)
          : await Backup.importFromFile(path!);
      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Replace all notes?'),
          content: Text(
            'This will replace all ${notes.length} current note${notes.length == 1 ? '' : 's'} '
            'with ${imported.notes.length} imported note${imported.notes.length == 1 ? '' : 's'}. '
            '${imported.budgets.isNotEmpty ? 'The ${imported.budgets.length} budget${imported.budgets.length == 1 ? '' : 's'} in this backup will also replace your current budgets. ' : ''}'
            'This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(
                foregroundColor: context.colors.destructive,
              ),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      setState(() {
        notes
          ..clear()
          ..addAll(imported.notes);
        // v1 backups carry no budgets; leave the current ones alone then.
        if (imported.budgets.isNotEmpty) {
          _budgets = imported.budgets;
        }
        _currentNoteId = null;
        _showEditor = false;
      });
      _persistNow();
      _storage.saveBudgets(_budgets);
      _showSnackBar('Imported ${imported.notes.length} notes');
    } catch (e) {
      _showSnackBar('Import failed: $e');
    }
  }

  void _showOnboarding() {
    final existing = notes.where((n) => n.id.endsWith('_welcome'));
    if (existing.isNotEmpty) {
      _selectNote(existing.first.id);
      _showSnackBar('Opened your welcome note');
      return;
    }
    final data = createOnboardingData();
    final welcome = data.notes.first;
    setState(() {
      // Only the welcome note: re-running this must not resurrect deleted
      // guides or sample finance data.
      notes = [welcome, ...notes];
      _currentNoteId = welcome.id;
      _showEditor = true;
      _previewMode = true;
    });
    _storage.save(notes);
    _showSnackBar('Welcome note created');
  }

  void _openSettings() {
    SettingsSheet.show(
      context,
      onExport: _exportNotes,
      onImport: _importNotes,
      onExportFinance: _exportFinance,
      onShowOnboarding: _showOnboarding,
      onReplayIntro: _showOnboardingFlow,
      onNotificationsChanged: () => _syncNotifications(checkBudgets: true),
      onRemoveSamples: _hasSampleData ? _removeSampleData : null,
    );
  }

  bool get _hasSampleData =>
      _budgets.any((b) => b.isDemo) ||
      notes.any(
        (n) => n.id.endsWith('_finance') || n.amounts.any((e) => e.isDemo),
      );

  void _removeSampleData({bool notify = true}) {
    setState(() {
      notes = notes.where((n) => !n.id.endsWith('_finance')).toList();
      for (final n in notes) {
        n.amounts.removeWhere((e) => e.isDemo);
      }
      _budgets = _budgets.where((b) => !b.isDemo).toList();
    });
    _persistNow();
    _storage.saveBudgets(_budgets);
    if (notify) _showSnackBar('Sample finance data removed');
  }

  void _showOnboardingFlow() {
    setState(() => _onboardingOpen = true);
  }

  void _completeOnboarding({
    required bool includeSamples,
    required String financeMode,
  }) {
    setState(() {
      _onboardingOpen = false;
      _financeMode = financeMode;
    });
    unawaited(_saveShellState());
    if (!includeSamples) _removeSampleData(notify: false);
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setBool(_onboardingCompleteKey, true),
      ),
    );
    unawaited(_drainStashedActions());
  }

  void _selectNote(String id) {
    final note = _noteById(id);
    if (note == null) return;
    note.viewedAt = DateTime.now();
    _persist();
    setState(() {
      _currentNoteId = id;
      _showEditor = true;
      _previewMode = note.content.isNotEmpty;
      final width = MediaQuery.of(context).size.width;
      if (width >= 1024 && _activeFilter == 'home') {
        // The desktop shell renders the editor only in the three-pane
        // workspace, so leave the home feed to reveal the selected note
        // (same pattern as _createNote). Mobile swaps its body on
        // _showEditor and needs no filter change.
        _activeFilter = 'notes';
        _currentTab = 'notes';
      }
      if (width >= 1200) {
        _contextPanelOpen = true;
      }
    });
  }

  void _openNoteById(String id) {
    _selectNote(id);
  }

  void _createNote() {
    final id = generateId('n');
    final note = Note(
      id: id,
      title: 'Untitled',
      content: '',
      tags: [],
      viewedAt: DateTime.now(),
    );
    setState(() {
      notes.insert(0, note);
      _currentNoteId = id;
      _activeFilter = 'notes';
      _currentTab = 'notes';
      _showEditor = true;
      _previewMode = false;
    });
    _persistNow();
  }

  void _openTemplatePicker() {
    TemplatePickerSheet.show(
      context,
      onPick: _createNoteFromTemplate,
      onQuickExpense: _quickAddEntry,
      onQuickIncome: _quickAddIncome,
    );
  }

  void _createNoteFromTemplate(NoteTemplate template) {
    final id = generateId('n');
    final note = Note(
      id: id,
      title: template.title,
      content: template.content,
      tags: List<String>.from(template.tags),
      type: template.type ?? 'text',
      currency: template.currency,
      viewedAt: DateTime.now(),
    );
    setState(() {
      notes.insert(0, note);
      _currentNoteId = id;
      _activeFilter = 'notes';
      _currentTab = 'notes';
      _showEditor = true;
      _previewMode = template.type != null && template.type != 'text'
          ? false
          : template.content.isNotEmpty;
    });
    _persistNow();
  }

  void _updateTitle(String title) {
    final note = _noteById(_currentNoteId);
    if (note == null) return;
    note.title = title;
    note.updatedAt = DateTime.now();
    // Rebuild so the breadcrumb, list row, and mobile header track the
    // title as it is typed.
    if (mounted) setState(() {});
    _persist();
  }

  void _updateContent(String content) {
    final note = _noteById(_currentNoteId);
    if (note == null) return;
    note.content = content;
    note.updatedAt = DateTime.now();
    if (mounted) setState(() {});
    _persist();
  }

  void _toggleChecklistItem(Note note, int lineIndex, bool checked) {
    final lines = note.content.split('\n');
    if (lineIndex < 0 || lineIndex >= lines.length) return;
    final marker = RegExp(r'\[[ xX]\]');
    if (!marker.hasMatch(lines[lineIndex])) return;
    lines[lineIndex] = lines[lineIndex].replaceFirst(
      marker,
      checked ? '[x]' : '[ ]',
    );
    note.content = lines.join('\n');
    note.updatedAt = DateTime.now();
    _persistNow();
    setState(() {});
  }

  void _onImageAdded(String path) {
    final note = _noteById(_currentNoteId);
    if (note == null) return;
    if (!note.imagePaths.contains(path)) {
      note.imagePaths.add(path);
      _persistNow();
    }
  }

  void _updateType(String type) {
    final note = _noteById(_currentNoteId);
    if (note == null) return;
    note.type = type;
    note.updatedAt = DateTime.now();
    if (type != 'text' && (note.currency == null || note.currency!.isEmpty)) {
      note.currency = 'PHP';
    }
    _persistNow();
    setState(() {});
  }

  void _updateCurrency(String currency) {
    final note = _noteById(_currentNoteId);
    if (note == null) return;
    note.currency = currency;
    note.updatedAt = DateTime.now();
    _persistNow();
    setState(() {});
  }

  void _updateAmounts(List<MoneyEntry> amounts) {
    final note = _noteById(_currentNoteId);
    if (note == null) return;
    note.amounts
      ..clear()
      ..addAll(amounts);
    note.updatedAt = DateTime.now();
    _persistNow();
    setState(() {});
  }

  void _updateTags(List<String> tags) {
    final note = _noteById(_currentNoteId);
    if (note == null) return;
    final normalized = <String>[];
    for (final tag in tags) {
      final value = _normalizeTag(tag);
      if (value.isNotEmpty && !normalized.contains(value)) {
        normalized.add(value);
      }
    }
    note.tags
      ..clear()
      ..addAll(normalized);
    note.updatedAt = DateTime.now();
    _persistNow();
    setState(() {});
  }

  void _onTagFilter(String tag) {
    final normalizedTag = _normalizeTag(tag);
    setState(() {
      _activeFilter = 'notes';
      _activeTag = normalizedTag;
      _searchQuery = '';
      _currentNoteId = null;
      _currentTab = 'notes';
      _showEditor = false;
    });
  }

  void _clearActiveTag() {
    setState(() => _activeTag = null);
  }

  void _setFilter(String filter) {
    setState(() {
      _activeFilter = filter;
      _currentNoteId = null;
      _searchQuery = '';
      _activeTag = null;
      _showEditor = false;
      if (filter == 'home') {
        _currentTab = 'home';
      } else if (filter == 'finance') {
        _currentTab = 'finance';
      } else if (filter == 'tasks') {
        _currentTab = 'tasks';
      } else {
        _currentTab = 'notes';
      }
    });
  }

  void _onTabChanged(String tab) {
    setState(() {
      _currentTab = tab;
      _showEditor = false;
      _searchQuery = '';
      _activeTag = null;
      if (tab == 'notes') {
        _activeFilter = 'notes';
      } else if (tab == 'finance') {
        _activeFilter = 'finance';
      } else if (tab == 'tasks') {
        _activeFilter = 'tasks';
      } else if (tab == 'home') {
        _activeFilter = 'home';
      }
    });
  }

  void _toggleSort() {
    setState(() => _sortDesc = !_sortDesc);
  }

  void _toggleSidebar() {
    setState(() {
      _sidebarState = _sidebarState == 'expanded' ? 'icons' : 'expanded';
    });
  }

  void _closeEditor() {
    setState(() => _showEditor = false);
  }

  void _togglePreview() {
    setState(() => _previewMode = !_previewMode);
  }

  void _toggleContextPanel() {
    setState(() => _contextPanelOpen = !_contextPanelOpen);
  }

  void _openCommandPalette() {
    setState(() => _commandPaletteOpen = true);
  }

  void _closeCommandPalette() {
    if (_commandPaletteOpen) setState(() => _commandPaletteOpen = false);
  }

  String get _workspaceSectionLabel {
    switch (_activeFilter) {
      case 'finance':
        return 'Finance';
      case 'tasks':
        return 'Tasks';
      case 'meeting':
        return 'Meetings';
      case 'journal':
        return 'Journal';
      case 'archive':
        return 'Library / Archive';
      case 'trash':
        return 'Library / Trash';
      case 'home':
        return 'Home';
      case 'today':
        return 'Today';
      case 'pinned':
        return 'Pinned';
      default:
        return 'Notes';
    }
  }

  List<CommandPaletteAction> _commandPaletteActions() {
    CommandPaletteAction navigate(
      String id,
      String label,
      IconData icon,
      String filter,
    ) {
      return CommandPaletteAction(
        id: id,
        label: label,
        description: 'Open $label',
        icon: icon,
        onInvoke: () => _setFilter(filter),
      );
    }

    return [
      CommandPaletteAction(
        id: 'new-note',
        label: 'New blank note',
        description: 'Start writing from an empty page',
        icon: Icons.add_box_outlined,
        shortcut: 'Ctrl N',
        onInvoke: _createNote,
      ),
      CommandPaletteAction(
        id: 'new-template',
        label: 'New from template',
        description: 'Choose a structured starting point',
        icon: Icons.auto_awesome_outlined,
        onInvoke: _openTemplatePicker,
      ),
      navigate('home', 'Home', Icons.home_outlined, 'home'),
      navigate('notes', 'Notes', Icons.notes_outlined, 'notes'),
      navigate('tasks', 'Tasks', Icons.check_circle_outline, 'tasks'),
      navigate(
        'finance',
        'Finance',
        Icons.account_balance_wallet_outlined,
        'finance',
      ),
      navigate('meetings', 'Meetings', Icons.groups_outlined, 'meeting'),
      navigate('journal', 'Journal', Icons.menu_book_outlined, 'journal'),
      navigate('archive', 'Archive', Icons.archive_outlined, 'archive'),
      navigate('trash', 'Trash', Icons.delete_outline, 'trash'),
      CommandPaletteAction(
        id: 'toggle-sidebar',
        label: 'Toggle sidebar',
        description: 'Expand or collapse workspace navigation',
        icon: Icons.view_sidebar_outlined,
        onInvoke: _toggleSidebar,
      ),
      CommandPaletteAction(
        id: 'settings',
        label: 'Open settings',
        description: 'Manage appearance, backup, and preferences',
        icon: Icons.settings_outlined,
        onInvoke: _openSettings,
      ),
      if (_currentNote != null)
        CommandPaletteAction(
          id: 'toggle-preview',
          label: _previewMode ? 'Edit page' : 'Preview page',
          description: 'Switch between writing and reading modes',
          icon: _previewMode ? Icons.edit_outlined : Icons.visibility_outlined,
          onInvoke: _togglePreview,
        ),
      ..._noteSearchActions(),
    ];
  }

  /// Recent pages as palette results so the top-right Search actually finds
  /// notes — matched on title and content via the palette's haystack.
  List<CommandPaletteAction> _noteSearchActions() {
    final candidates =
        notes.where((n) => !n.isArchived && !n.isDeleted).toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return candidates.take(40).map((note) {
      final icon = note.type == 'todo'
          ? Icons.check_circle_outline
          : note.type != 'text'
          ? Icons.account_balance_wallet_outlined
          : Icons.article_outlined;
      final preview = note.content.trim().isEmpty
          ? 'Empty page'
          : _homeContentPreview(note.content);
      return CommandPaletteAction(
        id: 'note-${note.id}',
        label: note.title.isEmpty ? 'Untitled' : note.title,
        description: preview,
        icon: icon,
        onInvoke: () => _selectNote(note.id),
        // Full-content haystack so Ctrl+K finds pages by body text, not
        // just by title/preview.
        searchText: '${note.title} ${note.content}',
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      final disabled = MediaQuery.disableAnimationsOf(context);
      return Scaffold(
        backgroundColor: context.colors.bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrandMark(
                size: 56,
                fg: context.colors.fg,
                accent: context.colors.accent,
              ),
              const SizedBox(height: 20),
              Text(
                'Typed',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: AppType.t28,
                  color: context.colors.fg,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: 360,
                child: Column(
                  children: [
                    _skeletonRow(disabled),
                    const SizedBox(height: 16),
                    _skeletonRow(disabled),
                    const SizedBox(height: 16),
                    _skeletonRow(disabled),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        backgroundColor: context.colors.bg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 40,
                  color: context.colors.destructive,
                ),
                const SizedBox(height: 12),
                Text(
                  'Could not load your notes',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Your saved data was not changed. Try again or restore from a backup.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.colors.muted),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _isLoading = true;
                          _loadError = null;
                        });
                        _loadAndHandleIntent();
                      },
                      child: const Text('Retry'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _importNotes,
                      child: const Text('Restore from backup'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_onboardingOpen) {
      return OnboardingScreen(onFinish: _completeOnboarding);
    }
    return CallbackShortcuts(
      bindings: {
        // Ctrl/Cmd+N now matches the palette's "New blank note — Ctrl N"
        // promise; the template picker is one keystroke deeper (Ctrl+K).
        SingleActivator(LogicalKeyboardKey.keyN, control: true): _createNote,
        SingleActivator(LogicalKeyboardKey.keyN, meta: true): _createNote,
        SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _openCommandPalette,
        SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _openCommandPalette,
        SingleActivator(LogicalKeyboardKey.escape): _closeEditor,
      },
      child: Stack(
        children: [
          // Positioned.fill: the mobile/desktop Scaffold must receive TIGHT
          // full-screen constraints — under the Stack's loose constraints a
          // Scaffold with a bottomNavigationBar collapses to the nav's own
          // height and ends up centered in the viewport.
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 1024) return _buildMobile();
                return _buildDesktop();
              },
            ),
          ),
          if (_commandPaletteOpen)
            Positioned.fill(
              child: CommandPalette(
                actions: _commandPaletteActions(),
                onDismiss: _closeCommandPalette,
              ),
            ),
        ],
      ),
    );
  }

  /// Shimmer placeholder row for the loading screen — maps to the shape of
  /// a home list row so the first real paint feels like a swap, not a jump.
  Widget _skeletonRow(bool disabled) {
    final base = context.colors.surface;
    final highlight = context.colors.listBg;
    BoxDecoration shade(double offset) => BoxDecoration(
          color: Color.lerp(
            base,
            highlight,
            disabled ? 0.5 : ((_shimmer.value + offset) % 1.0),
          ),
          borderRadius: BorderRadius.circular(AppRadius.chip),
        );
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Color.lerp(base, highlight, disabled ? 0.5 : _shimmer.value),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 11, width: 180, decoration: shade(0.15)),
              const SizedBox(height: 6),
              Container(height: 9, width: 260, decoration: shade(0.3)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWorkspaceHeader({bool isMobile = false}) {
    final currentTitle = _showEditor ? _currentNote?.title : null;
    return WorkspaceHeader(
      sectionLabel: _workspaceSectionLabel,
      tagLabel: _activeTag,
      noteTitle: currentTitle,
      isMobile: isMobile,
      headerSearch: isMobile && _currentTab == 'home' && !_showEditor,
      onSearchTap: _openCommandPalette,
      onHome: () => _setFilter('home'),
      onSection: () => _setFilter(_activeFilter),
      onMenu: isMobile ? () => _scaffoldKey.currentState?.openDrawer() : null,
      onOpenCommandPalette: _openCommandPalette,
    );
  }

  Widget _buildDesktop() {
    final screenWidth = MediaQuery.of(context).size.width;
    final sidebarOccupied = _sidebarState == 'expanded' ? 232.0 : 48.0;
    final canShowContext = screenWidth >= 1200 && _currentNote != null;
    final showContext = canShowContext && _contextPanelOpen;
    final contextWidth = showContext ? 280.0 : 0.0;
    final remaining = screenWidth - sidebarOccupied - contextWidth;
    final noteListW = (remaining * 0.28).clamp(280.0, 340.0);

    return Scaffold(
      backgroundColor: context.colors.bg,
      body: SafeArea(
        child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Sidebar(
                  activeFilter: _activeFilter,
                  onFilterChanged: _setFilter,
                  sidebarState: _sidebarState,
                  onCollapse: _toggleSidebar,
                  onTagFilter: _onTagFilter,
                  onSettings: _openSettings,
                  counts: _counts,
                  allTags: _allTags,
                  tagCounts: _tagCounts,
                  pinnedNotes: _pinnedNotes,
                  onNoteSelected: _selectNote,
                ),
                Expanded(
                  child: Column(
                    children: [
                      _buildWorkspaceHeader(),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: AppMotion.duration(context, AppMotion.slow),
                          switchInCurve: AppMotion.decelerate,
                          switchOutCurve: AppMotion.accelerate,
                          transitionBuilder: (child, animation) => FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.02),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          ),
                          child: KeyedSubtree(
                            key: ValueKey('workspace-$_activeFilter'),
                            child: _activeFilter == 'home'
                                // The switcher's Stack lays children out with
                                // loose constraints; without a tight box the
                                // short quiet feed shrink-wraps and floats
                                // centered instead of filling the pane.
                                ? SizedBox.expand(child: _buildHomeScreen())
                                : Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    width: noteListW,
                                    child: NoteList(
                                      notes: _filteredNotes,
                                      currentNoteId: _currentNoteId,
                                      onSelectNote: _selectNote,
                                      sortDesc: _sortDesc,
                                      onSortToggle: _toggleSort,
                                      searchQuery: _searchQuery,
                                      onSearchChanged: _onSearchInput,
                                      activeFilter: _activeFilter,
                                      onArchive: _archive,
                                      onDelete: _trash,
                                      onRestore: _restore,
                                      onDeletePermanent: _deletePermanently,
                                      onTogglePin: _togglePin,
                                      onNewNote: _openTemplatePicker,
                                      activeTag: _activeTag,
                                      onClearActiveTag: _clearActiveTag,
                                      onOpenSettings: _openSettings,
                                      onEmptyTrash: _emptyTrash,
                                      financeSummary: _activeFilter == 'finance'
                                          ? _financeSummary
                                          : null,
                                      financePeriod: _financePeriod,
                                      onFinancePeriodChanged: (p) =>
                                          setState(() => _financePeriod = p),
                                      financeCurrency: _financeCurrency,
                                      financeCurrencyOptions:
                                          _financeCurrencyOptions,
                                      onFinanceCurrencyChanged: (currency) =>
                                          setState(
                                            () => _financeCurrency = currency,
                                          ),
                                      dashboardCurrencySymbol:
                                          _dashboardCurrencySymbol,
                                      budgets: _budgets,
                                      budgetActuals: _budgetActuals,
                                      financeMode: _financeMode,
                                      onFinanceModeChanged: (mode) =>
                                          setState(() => _financeMode = mode),
                                      onAddBudget: _addBudget,
                                      onRemoveBudget: _removeBudget,
                                      onQuickAddEntry: _quickAddEntry,
                                      onQuickAddIncome: _quickAddIncome,
                                      showFinanceDashboard: false,
                                      onSelectEntry: _editEntryFromDashboard,
                                      financeDailyTotals: _last14DaySpend,
                                      onChecklistToggle: _toggleChecklistItem,
                                    ),
                                  ),
                                  Expanded(
                                    child: _showEditor && _currentNote != null
                                        ? Editor(
                                            key: ValueKey(
                                              _currentNote?.id ?? '__empty__',
                                            ),
                                            note: _currentNote,
                                            onTitleChange: _updateTitle,
                                            onContentChange: _updateContent,
                                            onImageAdded: _onImageAdded,
                                            previewMode: _previewMode,
                                            onTogglePreview: _togglePreview,
                                            allNotes: notes,
                                            onOpenNote: _openNoteById,
                                            onTypeChange: _updateType,
                                            onCurrencyChange: _updateCurrency,
                                            onAmountsChange: _updateAmounts,
                                            onTagsChange: _updateTags,
                                            onArchive: _archive,
                                            onDelete: _trash,
                                            onTogglePin: _togglePin,
                                            customCategories: _customCategories,
                                            recentCategories: _recentCategories,
                                            onCategoryUsed: _onCategoryUsed,
                                            onSaveNow: () {
                                              _persistNow();
                                              _showSnackBar('Saved');
                                            },
                                            onToggleContext: canShowContext
                                                ? _toggleContextPanel
                                                : null,
                                            contextPanelOpen: showContext,
                                            saveState: _saveState,
                                          )
                                        : _activeFilter == 'finance'
                                        ? FinanceWorkspace(
                                            summary: _financeSummary,
                                            period: _financePeriod,
                                            onPeriodChanged: (p) =>
                                                setState(() => _financePeriod = p),
                                            currencySymbol: _dashboardCurrencySymbol,
                                            currencyScope: _financeCurrency,
                                            currencyOptions: _financeCurrencyOptions,
                                            onCurrencyChanged: (currency) => setState(
                                              () => _financeCurrency = currency,
                                            ),
                                            budgets: _budgets,
                                            budgetActuals: _budgetActuals,
                                            onAddBudget: _addBudget,
                                            onRemoveBudget: _removeBudget,
                                            onSelectNote: _selectNote,
                                            onSelectEntry: _editEntryFromDashboard,
                                            onAddExpense: _quickAddEntry,
                                            onAddIncome: _quickAddIncome,
                                            dailyTotals: _last14DaySpend,
                                          )
                                        : Container(
                                            color: context.colors.bg,
                                            child: Center(
                                              child: Text(
                                                'Select a note to start editing',
                                                style: TextStyle(
                                                  color: context.colors.muted,
                                                ),
                                              ),
                                            ),
                                          ),
                                  ),
                                  if (showContext)
                                    ContextPanel(
                                      note: _currentNote!,
                                      onClose: _toggleContextPanel,
                                      onTogglePin: () => _togglePin(_currentNote!),
                                      onArchive: () => _archive(_currentNote!),
                                      onDelete: () => _trash(_currentNote!),
                                      onTypeChange: _updateType,
                                      onTagFilter: _onTagFilter,
                                      allNotes: notes,
                                      onOpenNote: _openNoteById,
                                    ),
                                ],
                              ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildMobile() {
    return PopScope(
      canPop: !_showEditor,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeEditor();
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: SizedBox(
          width: 280,
          child: Drawer(
            child: Material(
              color: context.colors.sidebarBg,
              child: SafeArea(
                child: Sidebar(
                  activeFilter: _activeFilter,
                  onFilterChanged: (f) {
                    _setFilter(f);
                    Navigator.pop(context);
                  },
                  sidebarState: 'expanded',
                  onCollapse: () => Navigator.pop(context),
                  onTagFilter: (tag) {
                    _onTagFilter(tag);
                    Navigator.pop(context);
                  },
                  onSettings: () {
                    Navigator.pop(context);
                    _openSettings();
                  },
                  counts: _counts,
                  allTags: _allTags,
                  tagCounts: _tagCounts,
                  pinnedNotes: _pinnedNotes,
                  onNoteSelected: (id) {
                    _selectNote(id);
                    Navigator.pop(context);
                  },
                ),
              ),
            ),
          ),
        ),
        body: AnimatedSwitcher(
          duration: AppMotion.duration(context, AppMotion.page),
          switchInCurve: AppMotion.decelerate,
          switchOutCurve: AppMotion.accelerate,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: _showEditor
              ? KeyedSubtree(
                  key: const ValueKey('mobile-editor'),
                  child: SizedBox.expand(child: _buildEditorFullScreen()),
                )
              : KeyedSubtree(
                  key: const ValueKey('mobile-shell'),
                  child: SizedBox.expand(
                    child: SafeArea(
                      top: true,
                      bottom: false,
                      child: Column(
                        children: [
                          _buildMobileMenuBar(),
                          Expanded(child: _buildMobileContent()),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
        bottomNavigationBar: AnimatedSize(
          duration: AppMotion.duration(context, AppMotion.page),
          curve: AppMotion.emphasized,
          child: _showEditor
              ? const SizedBox.shrink()
              : MobileNav(
                  currentTab: _currentTab,
                  onTabChanged: _onTabChanged,
                  onCreate: _onDockCreate,
                ),
        ),
      ),
    );
  }

  String get _backTargetLabel {
    if (_activeTag != null) return 'Notes';
    return const {
          'notes': 'Notes',
          'home': 'Home',
          'finance': 'Finance',
          'tasks': 'Tasks',
          'archive': 'Archive',
          'trash': 'Trash',
          'today': 'Today',
          'pinned': 'Pinned',
        }[_activeFilter] ??
        'Notes';
  }

  Widget _buildEditorFullScreen() {
    return SafeArea(
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: context.colors.surface,
              border: Border(bottom: BorderSide(color: context.colors.border)),
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: _closeEditor,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chevron_left,
                          size: 20,
                          color: context.colors.accent,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          _backTargetLabel,
                          style: TextStyle(
                            fontSize: AppType.t13_5,
                            color: context.colors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      (_currentNote?.title ?? '').trim().isEmpty
                          ? 'Untitled'
                          : _currentNote!.title,
                      style: TextStyle(
                        fontSize: AppType.t13_5,
                        fontWeight: FontWeight.w600,
                        color: context.colors.fg,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: InkWell(
                    onTap: _togglePreview,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _previewMode
                            ? context.colors.accentDim
                            : context.colors.surface,
                        border: Border.all(
                          color: _previewMode
                              ? context.colors.accent.withAlpha(60)
                              : context.colors.border,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                      ),
                      child: Text(
                        _previewMode ? 'Edit' : 'Preview',
                        style: TextStyle(
                          fontSize: AppType.t13_5,
                          letterSpacing: 0.02,
                          fontWeight: FontWeight.w500,
                          color: _previewMode
                              ? context.colors.accent
                              : context.colors.fg,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Editor(
              note: _currentNote,
              onTitleChange: _updateTitle,
              onContentChange: _updateContent,
              onImageAdded: _onImageAdded,
              previewMode: _previewMode,
              onTogglePreview: _togglePreview,
              allNotes: notes,
              onOpenNote: _openNoteById,
              onTypeChange: _updateType,
              onCurrencyChange: _updateCurrency,
              onAmountsChange: _updateAmounts,
              onTagsChange: _updateTags,
              onArchive: _archive,
              onDelete: _trash,
              onTogglePin: _togglePin,
              customCategories: _customCategories,
              recentCategories: _recentCategories,
              onCategoryUsed: _onCategoryUsed,
              onSaveNow: () {
                _persistNow();
                _showSnackBar('Saved');
              },
              saveState: _saveState,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteListMobile() {
    return SafeArea(
      child: NoteList(
        notes: _filteredNotes,
        currentNoteId: _currentNoteId,
        onSelectNote: _selectNote,
        sortDesc: _sortDesc,
        onSortToggle: _toggleSort,
        searchQuery: _searchQuery,
        onSearchChanged: _onSearchInput,
        activeFilter: _activeFilter,
        onArchive: _archive,
        onDelete: _trash,
        onRestore: _restore,
        onDeletePermanent: _deletePermanently,
        onTogglePin: _togglePin,
        onNewNote: _openTemplatePicker,
        activeTag: _activeTag,
        onClearActiveTag: _clearActiveTag,
        onOpenSettings: _openSettings,
        onEmptyTrash: _emptyTrash,
        financeSummary: _activeFilter == 'finance' ? _financeSummary : null,
        financePeriod: _financePeriod,
        onFinancePeriodChanged: (p) => setState(() => _financePeriod = p),
        financeCurrency: _financeCurrency,
        financeCurrencyOptions: _financeCurrencyOptions,
        onFinanceCurrencyChanged: (currency) =>
            setState(() => _financeCurrency = currency),
        dashboardCurrencySymbol: _dashboardCurrencySymbol,
        budgets: _budgets,
        budgetActuals: _budgetActuals,
        financeMode: _financeMode,
        onFinanceModeChanged: (mode) => setState(() => _financeMode = mode),
        onAddBudget: _addBudget,
        onRemoveBudget: _removeBudget,
        onQuickAddEntry: _quickAddEntry,
        onQuickAddIncome: _quickAddIncome,
        onSelectEntry: _editEntryFromDashboard,
        financeDailyTotals: _last14DaySpend,
        onChecklistToggle: _toggleChecklistItem,
      ),
    );
  }

  Widget _buildMobileContent() {
    final Widget content;
    switch (_currentTab) {
      case 'home':
        content = _buildHomeScreen();
        break;
      case 'notes':
      case 'finance':
      case 'tasks':
        content = _buildNoteListMobile();
        break;
      default:
        content = _buildNoteListMobile();
        break;
    }
    return AnimatedSwitcher(
      duration: AppMotion.duration(context, AppMotion.slow),
      switchInCurve: AppMotion.decelerate,
      switchOutCurve: AppMotion.accelerate,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey('mobtab-$_currentTab'),
        child: SizedBox.expand(child: content),
      ),
    );
  }

  Widget _buildHomeScreen() {
    final isDesktop = MediaQuery.of(context).size.width >= 1024;
    final hasPins = _pinnedNotes.isNotEmpty;
    final jumpRows = _jumpBackInRows();

    final groups = <Widget>[
      _buildHomeIntro(),
      if (hasPins) _homeSection('PINNED', _buildPinnedHome()),
      if (jumpRows.isNotEmpty)
        _homeSection('JUMP BACK IN', _buildJumpBackIn(jumpRows)),
    ];
    final body = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 80),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < groups.length; i++) ...[
                if (i > 0) const SizedBox(height: 24),
                _stagger(i, groups[i], lastIndex: groups.length - 1),
              ],
            ],
          ),
        ),
      ),
    );

    return Container(
      color: context.colors.listBg,
      child: isDesktop ? body : SafeArea(child: body),
    );
  }

  Widget _homeSection(String title, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(title),
        const SizedBox(height: 8),
        content,
      ],
    );
  }

  /// Home sections rise in once per app start, 45 ms apart; after the last
  /// section lands, the plain children render so revisiting Home never
  /// replays the intro.
  Widget _stagger(int index, Widget child, {required int lastIndex}) {
    if (_homeAnimated || MediaQuery.disableAnimationsOf(context)) return child;
    final delayMs = 45.0 * index;
    final total = AppMotion.slow.inMilliseconds + delayMs;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.duration(
        context,
        Duration(milliseconds: total.round()),
      ),
      curve: Interval(delayMs / total, 1.0, curve: AppMotion.decelerate),
      onEnd: () {
        if (mounted && index == lastIndex && !_homeAnimated) {
          setState(() => _homeAnimated = true);
        }
      },
      // translate-only: no opacity fade, so a frozen frame can never leave
      // the home content invisible.
      builder: (context, t, _) => Transform.translate(
        offset: Offset(0, 16 * (1 - t)),
        child: child,
      ),
    );
  }

  Widget _buildMobileMenuBar() {
    return _buildWorkspaceHeader(isMobile: true);
  }

  Widget _buildHomeIntro() {
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 18
        ? 'Good afternoon'
        : 'Good evening';
    final c = context.colors;
    final isDesktop = MediaQuery.of(context).size.width >= 1024;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: AppSpacing.s4),
              _buildHomeMetaLine(now),
            ],
          ),
        ),
        if (isDesktop) ...[
          const SizedBox(width: 12),
          Semantics(
            label: 'Create',
            button: true,
            child: InkWell(
              onTap: _openTemplatePicker,
              borderRadius: BorderRadius.circular(AppRadius.panel),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(AppRadius.panel),
                ),
                child: Icon(Icons.add, size: 18, color: c.onAccent),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// One quiet text line under the greeting: short date · month spend ·
  /// open tasks. The old TODAY card and THIS MONTH cards fold into this
  /// line — numbers bold on foreground, connective text muted.
  Widget _buildHomeMetaLine(DateTime now) {
    final c = context.colors;
    final (hasData, spent, _, currency, _) = _monthFinanceTotals();
    final openTasks = openTaskCount(notes);
    final muted = TextStyle(fontSize: AppType.t11, color: c.muted);
    final bold = TextStyle(
      fontSize: AppType.t11,
      fontWeight: FontWeight.w600,
      color: c.fg,
    );

    final spans = <InlineSpan>[TextSpan(text: dayLabel(now), style: muted)];
    if (hasData) {
      final major = minorToMajor(spent, currency);
      final amount = formatNumber(
        major,
        decimals: major == major.roundToDouble() ? 0 : currencyDecimals(currency),
      );
      spans.addAll([
        TextSpan(text: '  ·  ', style: muted),
        currencySpan(currency, bold),
        TextSpan(text: amount, style: bold),
        TextSpan(text: ' spent', style: muted),
      ]);
    }
    spans.addAll([
      TextSpan(text: '  ·  ', style: muted),
      TextSpan(text: '$openTasks', style: bold),
      TextSpan(
        text: openTasks == 1 ? ' open task' : ' open tasks',
        style: muted,
      ),
    ]);

    return Text.rich(
      TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: AppType.t12,
        fontWeight: FontWeight.w500,
        color: context.colors.muted,
        letterSpacing: 0.08,
      ),
    );
  }

  /// Merged home list: the Continue heuristic picks (first finance, first
  /// todo, first journal) lead, then the most recently updated pages fill
  /// the rest — deduped by id, capped at 5 note rows.
  List<(Note, IconData)> _jumpBackInRows() {
    // Guides are reference material, not work in progress — exclude them
    // the way the old Continue and Recent sections did.
    final workingNotes =
        notes
            .where(
              (n) => !n.isArchived && !n.isDeleted && !n.tags.contains('guide'),
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final rows = <(Note, IconData)>[];
    final financeNote = workingNotes.cast<Note?>().firstWhere(
      (n) => n!.type != 'text' && n.type != 'todo',
      orElse: () => null,
    );
    if (financeNote != null) {
      rows.add((financeNote, Icons.account_balance_wallet_outlined));
    }
    final todoNote = workingNotes.cast<Note?>().firstWhere(
      (n) => n!.type == 'todo' || n.title.toLowerCase().contains('todo'),
      orElse: () => null,
    );
    if (todoNote != null && !rows.any((r) => r.$1.id == todoNote.id)) {
      rows.add((todoNote, Icons.check_circle_outline));
    }
    final journalNote = workingNotes.cast<Note?>().firstWhere(
      (n) => n!.title.toLowerCase().contains('journal'),
      orElse: () => null,
    );
    if (journalNote != null && !rows.any((r) => r.$1.id == journalNote.id)) {
      rows.add((journalNote, Icons.menu_book_outlined));
    }
    for (final note in workingNotes) {
      if (rows.length >= 5) break;
      if (rows.any((r) => r.$1.id == note.id)) continue;
      rows.add((
        note,
        note.isPinned
            ? Icons.push_pin_outlined
            : note.type == 'todo'
            ? Icons.check_circle_outline
            : note.type != 'text'
            ? Icons.account_balance_wallet_outlined
            : Icons.article_outlined,
      ));
    }

    return rows;
  }

  Widget _buildJumpBackIn(List<(Note, IconData)> rows) {
    return Column(
      children: [
        ...rows.map(
          (r) => _homeQuietRow(
            icon: r.$2,
            title: r.$1.title.isEmpty ? 'Untitled' : r.$1.title,
            subtitle: _continueSubtitle(r.$1),
            trailing: _relativeTimeLabel(r.$1.updatedAt),
            onTap: () => Future.microtask(() => _selectNote(r.$1.id)),
          ),
        ),
      ],
    );
  }

  Widget _homeQuietRow({
    required IconData icon,
    required String title,
    String? subtitle,
    String? trailing,
    Color? titleColor,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: c.border.withValues(alpha: 0.7)),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: c.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.t13_5,
                      fontWeight: FontWeight.w500,
                      color: titleColor ?? c.fg,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    _previewLine(
                      subtitle,
                      TextStyle(fontSize: AppType.t11, color: c.muted),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              Text(trailing, style: TextStyle(fontSize: AppType.t11, color: c.muted)),
            ],
          ],
        ),
      ),
    );
  }

  static final RegExp _leadingCurrencySymbol = RegExp(r'^[₱$€£¥₹]');

  /// Renders a preview line that may start with a currency symbol. The UI
  /// fonts have no ₱ glyph and named fallback families don't rescue it on
  /// device, so the symbol gets its own span in the platform font — the same
  /// approach as finance_utils.currencySpan.
  Widget _previewLine(String text, TextStyle style) {
    if (!_leadingCurrencySymbol.hasMatch(text)) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(
            text: text[0],
            style: style.copyWith(
              fontFamily: 'Roboto',
              fontFamilyFallback: const ['Noto Sans', 'sans-serif'],
            ),
          ),
          TextSpan(text: text.substring(1)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  String? _continueSubtitle(Note note) {
    if (note.type != 'text' && note.type != 'todo' && note.amounts.isNotEmpty) {
      final counts = <String, int>{};
      for (final e in note.amounts) {
        final cur = e.currency ?? note.currency ?? 'PHP';
        counts[cur] = (counts[cur] ?? 0) + 1;
      }
      var dominant = note.currency ?? 'PHP';
      if (!counts.containsKey(dominant)) {
        dominant = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      }
      var total = 0;
      var count = 0;
      final others = <String>{};
      for (final e in note.amounts) {
        final cur = e.currency ?? note.currency ?? 'PHP';
        if (cur == dominant) {
          total += e.amount;
          count++;
        } else {
          others.add(cur);
        }
      }
      final excl = others.isEmpty ? '' : ' · excl. ${others.join(' · ')}';
      return '${formatMinorAmount(total, dominant)} · $count '
          '${count == 1 ? 'entry' : 'entries'}$excl';
    }
    if (note.type == 'todo' || note.title.toLowerCase().contains('todo')) {
      final counts = countChecklist(note.content);
      if (counts.total > 0) {
        final progress = '${counts.done} of ${counts.total} done';
        final next = firstOpenItem(note.content);
        if (next == null) return progress;
        final label = next.length > 40 ? '${next.substring(0, 40)}…' : next;
        return '$label · $progress';
      }
      return null;
    }
    final preview = _homeContentPreview(note.content);
    return preview.isEmpty ? null : preview;
  }

  Widget _buildPinnedHome() {
    final pinned = _pinnedNotes.toList();
    final c = context.colors;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: pinned.take(8).map((note) {
        return InkWell(
          onTap: () => Future.microtask(() => _selectNote(note.id)),
          borderRadius: BorderRadius.circular(AppRadius.panel),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(AppRadius.panel),
              border: Border.all(color: c.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.push_pin, size: 11, color: c.accent),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    note.title.isEmpty ? 'Untitled' : note.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.t12,
                      fontWeight: FontWeight.w500,
                      color: c.fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Calendar-month finance totals for the home snapshot, scoped to the
  /// dominant currency (same approach as the finance dashboard): entries in
  /// other currencies are counted for the mixed-currency hint but never
  /// silently summed into the dominant figures.
  /// [anchor] selects the calendar month to total (defaults to the current month).
  (bool, int, int, String, bool) _monthFinanceTotals([DateTime? anchor]) {
    final now = anchor ?? DateTime.now();
    final start = DateTime(now.year, now.month);
    final end = DateTime(now.year, now.month + 1);
    final incomeBy = <String, int>{};
    final expenseBy = <String, int>{};
    for (final n in notes) {
      if (n.type == 'text' || n.isArchived || n.isDeleted) continue;
      for (final e in n.amounts) {
        if (e.date.isBefore(start) || !e.date.isBefore(end)) continue;
        final cur = e.currency ?? n.currency ?? 'PHP';
        final t = e.type ?? n.type;
        if (t == 'income') {
          incomeBy[cur] = (incomeBy[cur] ?? 0) + e.amount;
        } else if (t == 'expense') {
          expenseBy[cur] = (expenseBy[cur] ?? 0) + e.amount;
        }
      }
    }
    final currencies = <String>{...incomeBy.keys, ...expenseBy.keys};
    if (currencies.isEmpty) return (false, 0, 0, 'PHP', false);
    var dominant = 'PHP';
    var best = -1;
    for (final cur in currencies) {
      final total = (incomeBy[cur] ?? 0) + (expenseBy[cur] ?? 0);
      if (total > best) {
        best = total;
        dominant = cur;
      }
    }
    return (
      true,
      expenseBy[dominant] ?? 0,
      incomeBy[dominant] ?? 0,
      dominant,
      currencies.length > 1,
    );
  }

  String _homeContentPreview(String content) =>
      contentPreview(content, maxChars: 90);

  static String _relativeTimeLabel(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${d.month}/${d.day}';
  }
}
