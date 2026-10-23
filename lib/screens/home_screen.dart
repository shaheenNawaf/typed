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
import '../utils/note_kind.dart';
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
import '../widgets/home_modules.dart';
import '../widgets/tasks_view.dart';
import '../widgets/workspace_sheet.dart';
import '../widgets/entry_sheet.dart';
import '../widgets/context_panel.dart';
import '../widgets/workspace_header.dart';
import '../widgets/command_palette.dart';
import '../widgets/voice_memo_sheet.dart';
import '../widgets/voice_model_sheet.dart';
import '../voice/voice_model.dart';
import '../voice/transcriber.dart';
import '../voice/voice_shaper.dart';
import 'onboarding_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  /// Home's sense of "now" (greeting, evening prompt, day line). Tests pin
  /// it so time-of-day features don't flip depending on when they run.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

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

  /// Mobile dock minimized while the page scrolls down (reading), restored
  /// on scroll up, at the top, on tab change, or by tapping it.
  bool _dockCollapsed = false;

  /// "Swipe up on the dock" pill, shown until the sheet has been opened once
  /// (or the pill is dismissed). Teaches the gesture without a snackbar that
  /// could queue in front of an Undo.
  static const _dockHintKey = 'dock_swipe_hint_seen_v1';

  /// Tasks finished today, for Home's acknowledgement ("2 done today").
  /// Stored as "epochDay:count" and reset by a new day.
  static const _doneTodayKey = 'done_today_v1';
  int _doneToday = 0;
  int _doneTodayDay = -1;

  /// "From your notes": hidden for the rest of the day with "Not today".
  static const _resurfaceHiddenKey = 'resurface_hidden_day_v1';

  /// What Home calls you ("Good evening, Sam"). Local only, optional.
  static const _displayNameKey = 'display_name_v1';
  String? _displayName;
  int _resurfaceHiddenDay = -1;
  bool _showDockHint = false;
  bool _previewMode = false;
  bool _isLoading = true;
  Object? _loadError;
  Timer? _persistTimer;
  List<String> _customCategories = [];
  List<String> _recentCategories = [];
  Future<void> _categoryWrite = Future.value();
  String _financePeriod = 'all';
  /// Simple mode's own scope. Advanced keeps [_financePeriod]; the two are
  /// deliberately separate because their defaults differ (month vs all).
  String _financeSimplePeriod = 'month';
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
  String _saveState = 'idle'; // idle | saving | saved
  static const _shellPrefsKey = 'shell_state_v1';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
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
          'financeSimplePeriod': _financeSimplePeriod,
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
      final simplePeriod = data['financeSimplePeriod'] as String?;
      if (simplePeriod != null) _financeSimplePeriod = simplePeriod;
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
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
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
      if (!_isLoading) {
        // Recurring entries used to materialize only on a cold start: an app
        // left in the background across the 1st never showed the new rent.
        _generateRecurringEntries();
        unawaited(_drainWidgetToggles().then(
          (_) => _storage.refreshWidgets(notes).catchError((_) {}),
        ));
      }
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
        // Before any save below (recurring entries, onboarding) rewrites the
        // widget payload from notes that don't have the home-screen ticks yet.
        await _drainWidgetToggles();
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
      _showDockHint = !(prefs.getBool(_dockHintKey) ?? false);
      final doneRaw = (prefs.getString(_doneTodayKey) ?? '').split(':');
      if (doneRaw.length == 2) {
        _doneTodayDay = int.tryParse(doneRaw[0]) ?? -1;
        _doneToday = int.tryParse(doneRaw[1]) ?? 0;
      }
      _resurfaceHiddenDay = prefs.getInt(_resurfaceHiddenKey) ?? -1;
      final name = prefs.getString(_displayNameKey)?.trim();
      _displayName = (name == null || name.isEmpty) ? null : name;
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
      await _drainWidgetToggles();
      unawaited(_storage.refreshWidgets(notes).catchError((_) {}));
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

  /// Written by the Android to-do widget (WidgetActionActivity.kt), which
  /// ticks items on the home screen without opening the app.
  static const _widgetTogglesKey = 'widget_pending_toggles_v1';

  /// Applies to-do toggles made on the home-screen widget since the last
  /// load or resume. Each carries the item's state at tap time, so replaying
  /// one that already landed is a no-op.
  Future<void> _drainWidgetToggles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // The native side wrote behind the plugin's in-memory cache.
      await prefs.reload();
      final raw = prefs.getString(_widgetTogglesKey);
      if (raw == null || raw.isEmpty) return;
      await prefs.remove(_widgetTogglesKey);
      for (final toggle in jsonDecode(raw) as List) {
        if (toggle is! Map) continue;
        final id = toggle['id'];
        final text = toggle['text'];
        if (id is! String || text is! String) continue;
        _toggleChecklistByContent(
          id,
          text,
          expectedDone: toggle['done'] is bool ? toggle['done'] as bool : null,
        );
      }
    } catch (_) {
      // Optional, Android-only channel; a bad payload must not block launch.
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
    } else if (intentAction == 'voice') {
      // Widget mic, app-icon shortcut or quick-settings tile.
      if (VoiceMemo.isSupported()) _openVoiceMemo();
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
    final marker = RegExp(r'^(\s*[-*+]\s+\[)([ xX])(\]\s+.*)$');
    for (var i = 0; i < lines.length; i++) {
      final m = marker.firstMatch(lines[i]);
      if (m == null || stripInlineMarkdown(m.group(3)!.substring(1)) != stripInlineMarkdown(text)) {
        continue;
      }
      final checked = m.group(2) != ' ';
      // Not in the tapped state: either a duplicate line with the same text
      // (keep looking) or a stale replay (no line matches; nothing happens).
      if (expectedDone != null && checked != expectedDone) {
        continue;
      }
      lines[i] = '${m.group(1)}${checked ? ' ' : 'x'}${m.group(3)}';
      note.content = lines.join('\n');
      note.updatedAt = DateTime.now();
      _countDone(!checked);
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
      if (!isFinanceNote(note)) continue;
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
    if (changed) {
      _persistNow();
      if (mounted) setState(() {});
    }
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

  /// The default destination for dashboard quick-adds: ONE note per calendar
  /// month holding both directions, e.g. "Finance — September 2026". Existing
  /// per-day "Quick …" notes are left untouched and still count toward
  /// totals, because the dashboard aggregates across every finance note.
  ///
  /// A missing monthly note is returned as an unsaved draft: the caller
  /// inserts it on the first actual save, so opening quick-add and cancelling
  /// no longer leaves an empty note behind (in the list and on the Android
  /// Recent widget).
  Note _monthlyFinanceNoteOrDraft() {
    final today = DateTime.now();
    final label = 'Finance — ${monthName(today.month)} ${today.year}';
    for (final n in notes) {
      if (n.isArchived || n.isDeleted) continue;
      if (!isFinanceNote(n)) continue;
      if (n.title == label) return n;
    }
    final note = Note(
      id: generateId('n'),
      title: label,
      content: '',
      tags: ['finance'],
      // The note holds both directions; per-entry `type` is what actually
      // decides income vs expense. 'expense' keeps isFinanceNote true and
      // matches the existing seed notes.
      type: 'expense',
      currency: 'PHP',
    );
    return note;
  }

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
    var note = _monthlyFinanceNoteOrDraft();
    // Quick-add inherits the workspace's currency scope (05-C2): logging money while
    // scoped to USD must not silently create a PHP entry. 'all' (and simple mode,
    // which has no scope selector) falls back to the destination note's currency.
    final effectiveScope = _effectiveFinanceCurrency;
    final scopeCurrency =
        effectiveScope != 'all' ? effectiveScope : note.currency;
    // Stay on the dashboard: the editor is deliberately NOT opened, so the
    // totals update in place behind the sheet instead of navigating away.
    setState(() {
      _activeFilter = 'finance';
      _currentTab = 'finance';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      EntrySheet.show(
        context,
        onSave: (entry) {
          if (!notes.any((n) => n.id == note.id)) notes.insert(0, note);
          // The sheet parsed the amount in the scope currency. Unless the
          // entry says so explicitly it would inherit the destination note's
          // currency: a USD-scoped add landed as PHP, and a PHP amount moved
          // to a JPY note was read as 100x yen.
          final parsedIn = entry.currency ?? scopeCurrency;
          if (parsedIn != note.currency) entry.currency = parsedIn;
          note.amounts.add(entry);
          note.updatedAt = DateTime.now();
          _persistNow();
          setState(() {});
          HapticFeedback.lightImpact();
          _showLogLandingSnackBar(entry, note);
        },
        currencySymbol: currencySymbol(scopeCurrency),
        noteCurrency: scopeCurrency,
        // Prefill the form from the button the user clicked, not from the
        // note's own type — the monthly note holds both directions.
        noteType: type,
        customCategories: _customCategories,
        recentCategories: _recentCategories,
        onCategoryUsed: _onCategoryUsed,
        destinationLabel: note.title,
        onChangeDestination: () async {
          final picked = await _pickFinanceNoteDestination(note);
          if (picked == null) return null;
          note = picked;
          return picked.title;
        },
      );
    });
  }

  /// Destination picker shown from the quick-add form's "Change" affordance.
  /// Returns the chosen finance note, or null when dismissed. Lists existing
  /// finance notes only — it never creates one.
  Future<Note?> _pickFinanceNoteDestination(Note current) {
    final candidates = notes
        .where((n) => isFinanceNote(n) && !n.isArchived && !n.isDeleted)
        .toList();
    // The monthly note may still be an unsaved draft; keep it pickable.
    if (!candidates.any((n) => n.id == current.id)) candidates.insert(0, current);
    final c = context.colors;
    return showModalBottomSheet<Note>(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.panel)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Save to',
                style: TextStyle(
                  fontSize: AppType.t12,
                  fontWeight: FontWeight.w600,
                  color: c.muted,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final n in candidates)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        n.id == current.id
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color: n.id == current.id ? c.accent : c.muted,
                      ),
                      title: Text(
                        n.title.isEmpty ? 'Untitled' : n.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: AppType.t13_5),
                      ),
                      subtitle: Text(
                        '${n.amounts.length} '
                        '${n.amounts.length == 1 ? 'entry' : 'entries'}',
                        style: TextStyle(fontSize: AppType.t11, color: c.muted),
                      ),
                      onTap: () => Navigator.pop(sheetContext, n),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
      onDelete: () {
        // Id-based, mirroring editor.dart _removeEntry: the captured index can go
        // stale between opening the sheet and tapping Delete.
        final index = note.amounts.indexWhere((e) => e.id == entryId);
        if (index == -1) return;
        final removed = note.amounts.removeAt(index);
        note.updatedAt = DateTime.now();
        _persistNow();
        setState(() {});
        // Delete sits next to Update and fires without a dialog; one
        // mis-tap must stay recoverable.
        _showSnackBar(
          'Entry deleted',
          onUndo: () {
            if (note.amounts.any((e) => e.id == removed.id)) return;
            note.amounts.insert(index.clamp(0, note.amounts.length), removed);
            _persistNow();
            if (mounted) setState(() {});
          },
        );
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
    'finance': notes.where(isVisibleFinanceNote).length,
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

  // Simple mode has its own persisted scope (Day/Week/Month/All) and always spans
  // all currencies; the Advanced dashboard keeps the stored period + currency scope.
  String get _effectiveFinancePeriod =>
      _financeMode == 'simple' ? _financeSimplePeriod : _financePeriod;
  String get _effectiveFinanceCurrency =>
      _financeMode == 'simple' ? 'all' : _financeCurrency;

  /// Calendar-day arithmetic (`DateTime(y, m, d - n)`), never
  /// `subtract(Duration(days: n))`: across a daylight-saving change a 24-hour
  /// step lands at 23:00/01:00 and shifts week starts and day buckets.
  static DateTime _weekStart(DateTime now) =>
      DateTime(now.year, now.month, now.day - (now.weekday - 1));

  bool _isInPeriod(DateTime d) {
    final now = DateTime.now();
    switch (_effectiveFinancePeriod) {
      case 'day':
        return _isToday(d);
      case 'week':
        final startOfWeek = _weekStart(now);
        return !d.isBefore(startOfWeek) &&
            d.isBefore(DateTime(startOfWeek.year, startOfWeek.month,
                startOfWeek.day + 7));
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

  /// The SAME stretch of the previous period: on Oct 16 the month comparison
  /// is Sep 1 – Sep 16, not all of September. Comparing a partial period with
  /// a full one made every early-month chip read "Spending down 97%".
  bool _isInPreviousPeriod(DateTime d) {
    final now = DateTime.now();
    final (DateTime prevStart, DateTime curStart, DateTime sameMoment) =
        switch (_effectiveFinancePeriod) {
      'day' => (
          DateTime(now.year, now.month, now.day - 1),
          DateTime(now.year, now.month, now.day),
          DateTime(now.year, now.month, now.day - 1, now.hour, now.minute,
              now.second),
        ),
      'week' => (
          DateTime(_weekStart(now).year, _weekStart(now).month,
              _weekStart(now).day - 7),
          _weekStart(now),
          DateTime(now.year, now.month, now.day - 7, now.hour, now.minute,
              now.second),
        ),
      'month' => (
          DateTime(now.year, now.month - 1, 1),
          DateTime(now.year, now.month, 1),
          // Mar 31 -> "Feb 31" normalizes into March; capped below.
          DateTime(now.year, now.month - 1, now.day, now.hour, now.minute,
              now.second),
        ),
      'year' => (
          DateTime(now.year - 1, 1, 1),
          DateTime(now.year, 1, 1),
          DateTime(now.year - 1, now.month, now.day, now.hour, now.minute,
              now.second),
        ),
      _ => (now, now, now),
    };
    if (!prevStart.isBefore(curStart)) return false;
    final end = sameMoment.isBefore(curStart) ? sameMoment : curStart;
    return !d.isBefore(prevStart) && !d.isAfter(end);
  }

  double get _daysInCurrentPeriod {
    final now = DateTime.now();
    switch (_effectiveFinancePeriod) {
      case 'day':
        return 1;
      case 'week':
        return now.weekday.toDouble();
      case 'month':
        return now.day.toDouble();
      case 'year':
        // Day of year, counted in calendar days (DST-safe).
        return (DateTime.utc(now.year, now.month, now.day)
                    .difference(DateTime.utc(now.year, 1, 1))
                    .inDays +
                1)
            .toDouble();
      default:
        return 0;
    }
  }

  FinanceSummary get _financeSummary {
    final financeNotes = notes.where(isVisibleFinanceNote);

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
      averageAvailable: _effectiveFinancePeriod != 'all',
      noteIds: noteIdsInPeriod,
      entriesByNote: entriesByNote,
      hasAnyEntries: _hasAnyFinanceEntries,
    );
  }

  /// True when the user has ever recorded a transaction, ignoring the period and
  /// currency filters entirely. Distinguishes "brand new to Finance" (one
  /// centered empty state, no cards) from "nothing in this period" (full layout,
  /// em-dash stats). Deliberately mirrors `_financeSummary`'s inclusion rules
  /// minus the period/currency gates — including its treatment of sample data —
  /// so the empty state can never contradict the transaction list below it.
  /// Sample entries are only removed by the explicit Settings action
  /// `_removeSampleData`, so until the user takes it they are real rows on
  /// screen and must count here too.
  bool get _hasAnyFinanceEntries {
    for (final n in notes) {
      if (!isVisibleFinanceNote(n)) continue;
      for (final e in n.amounts) {
        final t = e.type ?? n.type;
        if (t == 'income' || t == 'expense') return true;
      }
    }
    return false;
  }

  /// Desktop only: the Finance workspace takes the whole content width — the
  /// note-list pane never renders while Finance is active, with or without
  /// entries. The monthly ledger note stays reachable via the workspace's
  /// ledger-note link, the sidebar, the #finance tag, the command palette and
  /// transaction rows. An open editor always keeps the pane.
  bool get _hideFinanceListPane => _activeFilter == 'finance' && !_showEditor;

  /// Desktop Tasks, nothing open: the grouped view takes the whole canvas
  /// (like Home) instead of a 340px column beside an empty editor. Opening
  /// a list brings the column back next to it.
  bool get _tasksOwnCanvas =>
      _activeFilter == 'tasks' && !(_showEditor && _currentNote != null);

  /// Part 4.2: bare E / I add an expense / income on the Finance tab. A
  /// global keyboard handler, not a Shortcuts binding: a binding claimed the
  /// key even when it then did nothing — so lowercase e and i never reached
  /// any text field on a hardware keyboard — and a focus-tree handler never
  /// saw the key when nothing was focused. This claims it only when it fires.
  bool _onHardwareKey(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent) return false;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed ||
        keys.isMetaPressed ||
        keys.isAltPressed ||
        keys.isShiftPressed) {
      return false;
    }
    final type = event.logicalKey == LogicalKeyboardKey.keyE
        ? 'expense'
        : event.logicalKey == LogicalKeyboardKey.keyI
            ? 'income'
            : null;
    if (type == null || !_financeShortcutApplies) return false;
    _financeShortcut(type);
    return true;
  }

  bool get _financeShortcutApplies {
    if (_currentTab != 'finance') return false;
    if (_commandPaletteOpen || _onboardingOpen) return false;
    // Not over a sheet, dialog or pushed route: a second E used to stack a
    // second entry sheet on the first.
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    // A focused field's focus context is the Focus widget *inside*
    // EditableText, never EditableText itself, so look up the tree.
    final focusContext = FocusManager.instance.primaryFocus?.context;
    return focusContext?.findAncestorStateOfType<EditableTextState>() == null;
  }

  void _financeShortcut(String type) {
    if (!_financeShortcutApplies) return;
    if (type == 'income') {
      _quickAddIncome();
    } else {
      _quickAddEntry();
    }
  }

  /// Minor-unit expense totals per day for the last 14 days (oldest -> newest,
  /// index 13 = today), in the dashboard's dominant currency. Feeds the
  /// SpendSparkline trend card.
  List<int> get _last14DaySpend =>
      _last14DaySpendIn(_financeSummary.dominantCurrency);

  List<int> _last14DaySpendIn(String dominant) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(today.year, today.month, today.day - 13);
    final totals = List<int>.filled(14, 0);
    for (final n in notes) {
      if (!isVisibleFinanceNote(n)) continue;
      for (final e in n.amounts) {
        if ((e.type ?? n.type) != 'expense') continue;
        if ((e.currency ?? n.currency ?? 'PHP') != dominant) continue;
        final day = DateTime(e.date.year, e.date.month, e.date.day);
        if (day.isBefore(start) || day.isAfter(today)) continue;
        // UTC dates: a DST change inside the window shortens one local
        // "day" to 23h, which inDays would round into the previous bucket.
        final index = DateTime.utc(day.year, day.month, day.day)
            .difference(DateTime.utc(start.year, start.month, start.day))
            .inDays;
        totals[index] += e.amount;
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
    final weekStart = _weekStart(today);
    final monthStart = DateTime(now.year, now.month);
    final yearStart = DateTime(now.year);

    final actuals = <String, int>{};
    for (final budget in _budgets) {
      final (start, end) = switch (budget.period) {
        'week' => (
            weekStart,
            DateTime(weekStart.year, weekStart.month, weekStart.day + 7),
          ),
        'year' => (yearStart, DateTime(now.year + 1)),
        _ => (monthStart, DateTime(now.year, now.month + 1)),
      };
      var spent = 0;
      for (final n in notes) {
        if (!isVisibleFinanceNote(n)) continue;
        for (final e in n.amounts) {
          if ((e.type ?? n.type) != 'expense') continue;
          // Bounded on both sides: a bill dated next month is not this
          // month's spend (the budget alerts already bound it this way).
          if (e.date.isBefore(start) || !e.date.isBefore(end)) continue;
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
      if (!isVisibleFinanceNote(note)) continue;
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
            .where(isVisibleFinanceNote)
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
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
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

  /// Undo for archive/trash puts back exactly what was there: an archived
  /// note trashed and restored used to land in Notes, and every undo counted
  /// as a fresh edit (reordering Recent and feeding the writing streak).
  VoidCallback _undoTo(Note note) {
    final wasArchived = note.isArchived;
    final wasDeleted = note.isDeleted;
    final updatedAt = note.updatedAt;
    return () {
      note.isArchived = wasArchived;
      note.isDeleted = wasDeleted;
      note.updatedAt = updatedAt;
      _persistNow();
      if (mounted) setState(() {});
    };
  }

  void _archive(Note note) {
    final undo = _undoTo(note);
    note.isArchived = true;
    note.updatedAt = DateTime.now();
    if (_currentNoteId == note.id) {
      _currentNoteId = null;
      _showEditor = false;
    }
    _persistNow();
    setState(() {});
    _showSnackBar('Archived', onUndo: undo);
  }

  void _togglePin(Note note) {
    // Not an edit: bumping updatedAt moved the note under "Today", to the
    // top of Recent, and counted toward the writing streak.
    note.isPinned = !note.isPinned;
    _persistNow();
    setState(() {});
    _showSnackBar(note.isPinned ? 'Pinned' : 'Unpinned');
  }

  void _trash(Note note) {
    final undo = _undoTo(note);
    note.isDeleted = true;
    note.updatedAt = DateTime.now();
    if (_currentNoteId == note.id) {
      _currentNoteId = null;
      _showEditor = false;
    }
    _persistNow();
    setState(() {});
    _showSnackBar('Moved to trash', onUndo: undo);
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
        if (notes.any((n) => n.id == note.id)) return;
        setState(() {
          // The list may have shrunk since (Empty trash inside the undo
          // window): a stale index threw a RangeError and lost the note.
          notes.insert(index.clamp(0, notes.length), note);
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
      displayName: _displayName,
      onEditName: _editDisplayName,
      onVoiceModel: VoiceMemo.isSupported() && VoiceModel.isSupported()
          ? () => VoiceModelSheet.show(context)
          : null,
    );
  }

  /// "What should we call you?" — from Settings, or by tapping the greeting.
  Future<void> _editDisplayName() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(initial: _displayName),
    );
    if (result == null || !mounted) return;
    final name = result.trim();
    setState(() => _displayName = name.isEmpty ? null : name);
    final prefs = await SharedPreferences.getInstance();
    if (name.isEmpty) {
      await prefs.remove(_displayNameKey);
    } else {
      await prefs.setString(_displayNameKey, name);
    }
  }

  bool get _hasSampleData =>
      _budgets.any((b) => b.isDemo) ||
      notes.any(
        (n) => n.id.endsWith('_finance') || n.amounts.any((e) => e.isDemo),
      );

  void _removeSampleData({bool notify = true}) {
    final previousNotes = List<Note>.of(notes);
    final previousAmounts = {
      for (final n in notes) n.id: List<MoneyEntry>.of(n.amounts),
    };
    final previousBudgets = _budgets;
    setState(() {
      for (final n in notes) {
        n.amounts.removeWhere((e) => e.isDemo);
      }
      // The sample ledger is offered as a quick-add destination, so it can
      // hold the user's own entries: drop the note only once nothing real is
      // left in it (it used to go wholesale, real entries included).
      notes = notes
          .where((n) => !n.id.endsWith('_finance') || n.amounts.isNotEmpty)
          .toList();
      _budgets = _budgets.where((b) => !b.isDemo).toList();
    });
    _persistNow();
    _storage.saveBudgets(_budgets);
    if (!notify) return;
    _showSnackBar(
      'Sample finance data removed',
      onUndo: () {
        if (!mounted) return;
        // Put back only what was removed, so anything created inside the
        // undo window survives.
        setState(() {
          for (final n in previousNotes) {
            if (!notes.any((x) => x.id == n.id)) notes.add(n);
            final kept = n.amounts.map((e) => e.id).toSet();
            n.amounts.addAll(
              (previousAmounts[n.id] ?? const <MoneyEntry>[])
                  .where((e) => !kept.contains(e.id)),
            );
          }
          _budgets = [
            ..._budgets,
            ...previousBudgets.where((b) => !_budgets.any((x) => x.id == b.id)),
          ];
        });
        _persistNow();
        _storage.saveBudgets(_budgets);
      },
    );
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
    _dockCollapsed = false;
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
      if (width >= 1200 && !_contextPanelDismissed) {
        _contextPanelOpen = true;
      }
    });
  }

  void _openNoteById(String id) {
    _selectNote(id);
  }

  void _createNote() {
    // Ctrl/Cmd+N bubbles past the open palette; don't create behind it.
    if (_commandPaletteOpen) return;
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
      onVoiceMemo: VoiceMemo.isSupported() ? _openVoiceMemo : null,
    );
  }

  /// Voice memo → reviewed draft → a note or a to-do list.
  bool _voiceSheetOpen = false;

  Future<void> _openVoiceMemo() async {
    // A second launch (tile tapped twice) must not stack a second recorder.
    if (_voiceSheetOpen) return;
    _voiceSheetOpen = true;
    try {
      await _runVoiceMemo();
    } finally {
      _voiceSheetOpen = false;
    }
  }

  Future<void> _runVoiceMemo() async {
    // Open lists, most recently edited first, as places tasks can go.
    final lists = notes
        .where((n) => n.type == 'todo' && !n.isArchived && !n.isDeleted)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final result = await VoiceMemoSheet.show(
      context,
      lists: [
        for (final n in lists)
          VoiceListTarget(n.id, n.title.trim().isEmpty ? 'Untitled list' : n.title),
      ],
    );
    if (result == null || !mounted) return;
    final target = result.appendToId == null ? null : _noteById(result.appendToId);
    if (target != null && result.tasks.isNotEmpty) {
      _appendVoiceTasks(target, result.tasks);
      return;
    }
    final todo = result.kind == VoiceKind.todo;
    final note = Note(
      id: generateId('n'),
      title: result.title,
      content: result.content,
      tags: todo ? ['todo'] : [],
      type: todo ? 'todo' : 'text',
    );
    setState(() => notes.insert(0, note));
    _persistNow();
    _showSnackBar(
      todo ? 'List saved' : 'Saved to Notes',
      onUndo: () {
        setState(() => notes.removeWhere((n) => n.id == note.id));
        _persistNow();
      },
    );
  }

  /// Voice memo tasks added to an existing list; Undo removes exactly the
  /// lines it added (not edits or ticks made since).
  void _appendVoiceTasks(Note target, List<String> tasks) {
    final lines = [
      for (final t in tasks) '- [ ] ${t.replaceAll('\n', ' ').trim()}',
    ];
    setState(() {
      final current = target.content;
      final sep = current.isEmpty || current.endsWith('\n') ? '' : '\n';
      target.content = '$current$sep${lines.join('\n')}\n';
      target.updatedAt = DateTime.now();
    });
    _persistNow();
    final n = lines.length;
    _showSnackBar(
      'Added ${n == 1 ? '1 task' : '$n tasks'} to ${target.title}',
      onUndo: () {
        setState(() {
          final all = target.content.split('\n');
          for (final line in lines.reversed) {
            final i = all.lastIndexOf(line);
            if (i != -1) all.removeAt(i);
          }
          target.content = all.join('\n');
        });
        _persistNow();
      },
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

  /// Keeps today's finished-task count in step with ticks and unticks.
  void _countDone(bool nowDone) {
    final today = localEpochDay(DateTime.now());
    if (today != _doneTodayDay) {
      _doneTodayDay = today;
      _doneToday = 0;
    }
    _doneToday = (_doneToday + (nowDone ? 1 : -1)).clamp(0, 9999);
    final value = '$_doneTodayDay:$_doneToday';
    unawaited(
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setString(_doneTodayKey, value))
          .catchError((_) => false),
    );
  }

  int get _doneTodayNow =>
      _doneTodayDay == localEpochDay(DateTime.now()) ? _doneToday : 0;

  /// One older page brought back each day — rediscovery, not a feed. Only
  /// prose pages with something to read, untouched for a week; the pick is
  /// stable for the day (seeded by the date) so Home doesn't reshuffle.
  Note? _resurfaceNote(DateTime now) {
    final today = localEpochDay(now);
    if (_resurfaceHiddenDay == today) return null;
    final cutoff = now.subtract(const Duration(days: 7));
    final pool = notes
        .where((n) =>
            !n.isArchived &&
            !n.isDeleted &&
            !isSeedNote(n) &&
            n.type != 'todo' &&
            !isFinanceNote(n) &&
            n.updatedAt.isBefore(cutoff) &&
            _homeContentPreview(n.content).length >= 30)
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    if (pool.isEmpty) return null;
    return pool[today % pool.length];
  }

  void _hideResurfaceToday() {
    final today = localEpochDay(DateTime.now());
    setState(() => _resurfaceHiddenDay = today);
    unawaited(
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setInt(_resurfaceHiddenKey, today))
          .catchError((_) => false),
    );
  }

  void _toggleChecklistItem(Note note, int lineIndex, bool checked) {
    final lines = note.content.split('\n');
    if (lineIndex < 0 || lineIndex >= lines.length) return;
    final marker = RegExp(r'\[[ xX]\]');
    final current = marker.firstMatch(lines[lineIndex]);
    if (current == null) return;
    final wasDone = current.group(0) != '[ ]';
    if (wasDone != checked) _countDone(checked);
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
    if (isFinanceType(type) && (note.currency == null || note.currency!.isEmpty)) {
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
      _dockCollapsed = false;
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

  bool _onMobileScroll(ScrollUpdateNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final delta = n.scrollDelta ?? 0;
    final atTop = n.metrics.pixels <= n.metrics.minScrollExtent + 8;
    final collapse = atTop
        ? false
        : delta > 6
            ? true
            : delta < -6
                ? false
                : _dockCollapsed;
    if (collapse != _dockCollapsed) setState(() => _dockCollapsed = collapse);
    return false;
  }

  void _onTabChanged(String tab) {
    setState(() {
      _dockCollapsed = false;
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
    setState(() {
      _showEditor = false;
      _dockCollapsed = false;
    });
  }

  void _togglePreview() {
    setState(() => _previewMode = !_previewMode);
  }

  /// Set when the user closes the context panel; selecting another note
  /// then leaves it closed instead of popping it back open.
  bool _contextPanelDismissed = false;

  void _toggleContextPanel() {
    setState(() {
      _contextPanelOpen = !_contextPanelOpen;
      _contextPanelDismissed = !_contextPanelOpen;
    });
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

  /// Pages as palette results so the top-right Search actually finds notes —
  /// matched on title and content via the palette's haystack. The 40 most
  /// recent are listed up front; every other page is search-only (it used to
  /// be unfindable: the palette is the app's only search).
  List<CommandPaletteAction> _noteSearchActions() {
    final candidates =
        notes.where((n) => !n.isArchived && !n.isDeleted).toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    var rank = 0;
    return candidates.map((note) {
      final searchOnly = rank++ >= 40;
      final icon = note.type == 'todo'
          ? Icons.check_circle_outline
          : isFinanceNote(note)
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
        searchOnly: searchOnly,
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
      // Phones navigate from the dock (swipe up); no corner hamburger.
      onMenu: null,
      onOpenCommandPalette: _openCommandPalette,
    );
  }

  /// Pane transition for the workspace/tab AnimatedSwitchers. Incoming
  /// children are fully opaque from their first frame — an entrance that
  /// starts at opacity 0 leaves the pane blank forever in renderers whose
  /// animation clock can freeze (occluded preview panes, battery saver),
  /// the same doctrine as the home _stagger translate-only entrance. The
  /// outgoing child still dissolves; it sits underneath a fully visible
  /// incoming page, so a freeze mid-leave can never blank the pane.
  Widget _paneTransition(
    Widget child,
    Animation<double> animation, {
    double slide = 0.02,
  }) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final leaving = animation.status == AnimationStatus.reverse;
        return FadeTransition(
          opacity: AlwaysStoppedAnimation(leaving ? animation.value : 1.0),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(0, slide),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildDesktop() {
    final screenWidth = MediaQuery.of(context).size.width;
    final sidebarOccupied = _sidebarState == 'expanded' ? 232.0 : 48.0;
    final canShowContext =
        screenWidth >= 1200 && _currentNote != null && _showEditor;
    final showContext = canShowContext && _contextPanelOpen;
    final contextWidth = showContext ? 280.0 : 0.0;
    final remaining = screenWidth - sidebarOccupied - contextWidth;
    final noteListW = (remaining * 0.28).clamp(280.0, 340.0);

    // The workspace's ledger-note link target: the most recently updated
    // visible finance note (null -> link hidden, e.g. fresh install).
    final latestFinanceNote = notes
        .where(isVisibleFinanceNote)
        .fold<Note?>(null, (a, n) => a == null || n.updatedAt.isAfter(a.updatedAt) ? n : a);

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
                  onSearch: _openCommandPalette,
                  onCreate: _openTemplatePicker,
                  activeTag: _activeTag,
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
                          transitionBuilder: (child, animation) =>
                              _paneTransition(child, animation),
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
                                  // Plan 08: Finance always takes the full
                                  // canvas — the pane only returns for the
                                  // editor (any open editor wins).
                                  if (!_hideFinanceListPane &&
                                      !_tasksOwnCanvas)
                                  SizedBox(
                                    width: noteListW,
                                    child: _activeFilter == 'tasks'
                                        ? _buildTasksView()
                                        : NoteList(
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
                                            onTaskToggled: _countDone,
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
                                            onViewAllTime: () => setState(
                                              () => _financePeriod = 'all',
                                            ),
                                            dailyTotals: _last14DaySpend,
                                            ledgerNoteLabel: latestFinanceNote?.title,
                                            onOpenLedgerNote: latestFinanceNote == null
                                                ? null
                                                : () => _selectNote(
                                                    latestFinanceNote.id,
                                                  ),
                                          )
                                        : _activeFilter == 'tasks'
                                        ? _buildTasksView(fullCanvas: true)
                                        : _buildNoSelection(),
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
    // Android back unwinds the app before leaving it: search palette, then
    // the open note, then back to Home from any other tab or filter (Trash,
    // a tag, ...). Previously back exited straight from all of those.
    final atRoot = _activeFilter == 'home' && _currentTab == 'home';
    return PopScope(
      canPop: !_commandPaletteOpen && !_showEditor && atRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_commandPaletteOpen) {
          _closeCommandPalette();
        } else if (_showEditor) {
          _closeEditor();
        } else {
          _onTabChanged('home');
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        // Pages scroll under the floating glass dock; Scaffold reports the
        // dock's height as bottom padding so lists can clear it.
        // ...but not while the keyboard is up: the dock's height would then
        // count as visible body behind the keyboard and fields near the
        // bottom would not scroll into view.
        extendBody: MediaQuery.viewInsetsOf(context).bottom == 0,
        body: AnimatedSwitcher(
          duration: AppMotion.duration(context, AppMotion.page),
          switchInCurve: AppMotion.decelerate,
          switchOutCurve: AppMotion.accelerate,
          transitionBuilder: (child, animation) =>
              _paneTransition(child, animation, slide: 0.04),
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
                          Expanded(
                            child: NotificationListener<ScrollUpdateNotification>(
                              onNotification: _onMobileScroll,
                              child: _buildMobileContent(),
                            ),
                          ),
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
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_showDockHint) _buildDockHint(),
                    MobileNav(
                  currentTab: _currentTab,
                  onTabChanged: _onTabChanged,
                  onCreate: _onDockCreate,
                  collapsed: _dockCollapsed,
                  onExpand: () => setState(() => _dockCollapsed = false),
                  onOpenNavigation: _openWorkspaceSheet,
                ),
                  ],
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
                // Preview is a prose concept: lists and ledgers have none.
                if (_currentNote == null ||
                    (!isFinanceNote(_currentNote!) &&
                        _currentNote!.type != 'todo'))
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: InkWell(
                      onTap: _togglePreview,
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _previewMode
                              ? context.colors.accentDim
                              : context.colors.surface,
                          border: Border.all(
                            color: _previewMode
                                ? context.colors.accent
                                : context.colors.accent.withAlpha(150),
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                        ),
                        child: Text(
                          _previewMode ? 'Edit' : 'Preview',
                          style: TextStyle(
                            fontSize: AppType.t13_5,
                            letterSpacing: 0.02,
                            fontWeight: FontWeight.w600,
                            color: context.colors.accent,
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
              onTaskToggled: _countDone,
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

  /// Phone navigation beyond the dock: a bottom sheet, not a side drawer.
  void _dismissDockHint() {
    if (!_showDockHint) return;
    setState(() => _showDockHint = false);
    unawaited(
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setBool(_dockHintKey, true))
          .catchError((_) => false),
    );
  }

  Widget _buildDockHint() {
    final c = context.colors;
    return Padding(
      // Centred over the tab capsule (which sits left of centre, beside the
      // Create key), so the tip points at the grabber it describes.
      padding: const EdgeInsets.only(bottom: 2, right: 68),
      child: Center(
        child: ConstrainedBox(
          // Never wider than the screen: large text shrinks it to an
          // ellipsis instead of overflowing.
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width - 32,
          ),
          child: Material(
          color: c.surface,
          shape: StadiumBorder(side: BorderSide(color: c.border)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: InkWell(
                onTap: _openWorkspaceSheet,
                customBorder: const StadiumBorder(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.swipe_up_alt_rounded, size: 16, color: c.muted),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Swipe up for more',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: AppType.t12, color: c.fg),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ),
              IconButton(
                tooltip: 'Dismiss tip',
                onPressed: _dismissDockHint,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded, size: 16, color: c.muted),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  void _openWorkspaceSheet() {
    _dismissDockHint();
    WorkspaceSheet.show(
      context,
      activeFilter: _activeFilter,
      activeTag: _activeTag,
      counts: _counts,
      pinnedNotes: _pinnedNotes,
      tags: _allTags,
      tagCounts: _tagCounts,
      onFilter: _setFilter,
      onTag: _onTagFilter,
      onNote: _selectNote,
      onSettings: _openSettings,
    );
  }

  /// Desktop editor pane with nothing open: a quiet pointer to the two ways
  /// forward instead of a lone grey sentence.
  Widget _buildNoSelection() {
    final c = context.colors;
    return ColoredBox(
      color: c.bg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.article_outlined, size: 28, color: c.muted),
            const SizedBox(height: 12),
            Text(
              'Nothing open',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c.fg,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pick a page from the list, or press Ctrl N for a new one.',
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
          ],
        ),
      ),
    );
  }

  /// Tasks tab: every list's open tasks in one grouped, tickable view.
  Widget _buildTasksView({bool fullCanvas = false}) {
    return TasksView(
      fullCanvas: fullCanvas,
      lists: _filteredNotes,
      onToggle: _toggleChecklistItem,
      onOpenList: (note) => _selectNote(note.id),
      onAddTask: _appendTask,
      onNewList: () => _createNoteFromTemplate(
        getNoteTemplates().firstWhere((t) => t.type == 'todo'),
      ),
    );
  }

  /// Appends an open checklist line to [note], keeping lines separate even
  /// when its content does not end in a newline.
  void _appendTask(Note note, String text) {
    final line = '- [ ] ${text.replaceAll('\n', ' ').trim()}';
    final current = note.content;
    setState(() {
      note.content = current.isEmpty || current.endsWith('\n')
          ? '$current$line\n'
          : '$current\n$line\n';
      note.updatedAt = DateTime.now();
    });
    _persistNow();
  }

  Widget _buildNoteListMobile() {
    if (_activeFilter == 'tasks') {
      return SafeArea(bottom: false, child: _buildTasksView());
    }
    // bottom: false — the list runs under the glass dock and clears it with
    // its own end padding (NoteList._listPadding).
    return SafeArea(
      bottom: false,
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
        financeSimplePeriod: _financeSimplePeriod,
        onFinanceSimplePeriodChanged: (p) =>
            setState(() => _financeSimplePeriod = p),
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
      transitionBuilder: (child, animation) =>
          _paneTransition(child, animation),
      child: KeyedSubtree(
        key: ValueKey('mobtab-$_currentTab'),
        child: SizedBox.expand(child: content),
      ),
    );
  }

  /// Home, built for focus: a greeting, then one thing per block — say
  /// what's on your mind, the one next task, the one note to return to, one
  /// line of money. A single reading-width column on every screen size, so
  /// the eye never has to choose between panels.
  Widget _buildHomeScreen() {
    final isDesktop = MediaQuery.of(context).size.width >= 1024;
    final now = HomeScreen.clock();
    final continueNote = _continueNote();

    final blocks = <Widget>[
      _buildHomeIntro(now),
      HomeCaptureBar(
        onSaveNote: _captureNote,
        onAddTask: _captureTask,
        onVoice: VoiceMemo.isSupported() ? _openVoiceMemo : null,
      ),
      if (notes.isEmpty) _buildHomeEmptyCta(),
      // Evening with nothing open: the empty Next up gives way to one
      // optional prompt to set up tomorrow (the subline already says the
      // plate is clear — two "nothing here" cards would just repeat it).
      if (now.hour >= 18 && _upNextItems().isEmpty)
        HomeWindDown(onAdd: _captureTask)
      else
        _buildNextUp(),
      if (continueNote != null)
        HomeContinueCard(
          note: continueNote,
          icon: _noteIcon(continueNote),
          subtitle: _continueSubtitle(continueNote),
          when: _relativeTimeLabel(continueNote.updatedAt),
          onOpen: () => Future.microtask(() => _selectNote(continueNote.id)),
        ),
      if (_resurfaceNote(now) case final old?)
        HomeResurfaceCard(
          note: old,
          preview: _homeContentPreview(old.content),
          age: _ageLabel(old.updatedAt, now),
          onOpen: () => Future.microtask(() => _selectNote(old.id)),
          onDismiss: _hideResurfaceToday,
        ),
      _buildHomeMoney(now),
    ];

    final body = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        isDesktop ? 56 : 28,
        20,
        // Clears the floating dock, which the page scrolls under.
        32 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < blocks.length; i++) ...[
                if (i > 0) SizedBox(height: i == 1 ? 24 : 32),
                blocks[i],
              ],
            ],
          ),
        ),
      ),
    );

    return Container(
      color: context.colors.listBg,
      child: isDesktop ? body : SafeArea(bottom: false, child: body),
    );
  }

  /// Every open checklist line across lists, freshest list first.
  List<UpNextItem> _upNextItems() {
    final lists = notes
        .where((n) => !n.isArchived && !n.isDeleted && !isSeedNote(n))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return [
      for (final note in lists)
        for (final item in parseChecklist(note.content))
          if (!item.done && item.text.isNotEmpty)
            UpNextItem(
              note: note,
              lineIndex: item.lineIndex,
              text: stripInlineMarkdown(item.text),
            ),
    ];
  }

  Widget _buildNextUp() {
    return HomeNextUp(
      items: _upNextItems(),
      doneToday: _doneTodayNow,
      onComplete: (item) {
        _toggleChecklistItem(item.note, item.lineIndex, true);
        _showSnackBar(
          'Done: ${item.text}',
          // By content: the list may have changed since (lines added or
          // removed above it), so the old index could untick another task.
          onUndo: () => _toggleChecklistByContent(
            item.note.id,
            item.text,
            expectedDone: true,
          ),
        );
      },
      onOpen: (item) => _selectNote(item.note.id),
      onViewAll: () => _onTabChanged('tasks'),
    );
  }

  Widget _buildHomeMoney(DateTime now) {
    final (hasData, spent, _, currency, _) = _monthFinanceTotals();
    return HomeMoneyLine(
      monthLabel: monthName(now.month),
      hasData: hasData,
      currency: currency,
      spent: spent,
      onOpen: () => _onTabChanged('finance'),
    );
  }

  /// The page most recently written in. Task lists and finance ledgers are
  /// left out — Next Up and the money line already cover them, and showing
  /// the same list twice splits attention. Guides are reference, not work.
  Note? _continueNote() {
    Note? best;
    for (final n in notes) {
      if (n.isArchived || n.isDeleted || n.tags.contains('guide')) continue;
      if (n.type == 'todo' || isFinanceNote(n)) continue;
      if (best == null || n.updatedAt.isAfter(best.updatedAt)) best = n;
    }
    return best;
  }

  IconData _noteIcon(Note note) => note.type == 'todo'
      ? Icons.check_circle_outline
      : isFinanceNote(note)
          ? Icons.account_balance_wallet_outlined
          : Icons.article_outlined;

  /// Home capture -> a new note. A short single line becomes the title; a
  /// longer thought keeps its full text as the body under a trimmed title.
  void _captureNote(String text) {
    final body = text.trim();
    final lines = body.split('\n');
    final first = lines.first.trim();
    final single = lines.length == 1 && first.length <= 60;
    String title = first;
    if (first.length > 60) {
      final cut = first.lastIndexOf(' ', 57);
      title = '${first.substring(0, cut > 20 ? cut : 57)}…';
    }
    final note = Note(
      id: generateId('n'),
      title: title,
      content: single ? '' : body,
      tags: [],
    );
    setState(() => notes.insert(0, note));
    _persistNow();
    _showSnackBar(
      'Saved to Notes',
      onUndo: () {
        setState(() => notes.removeWhere((n) => n.id == note.id));
        _persistNow();
      },
    );
  }

  /// Home capture -> a task on the Inbox list (created on first use).
  void _captureTask(String text) {
    Note? inbox;
    for (final n in notes) {
      if (n.type == 'todo' &&
          n.title == 'Inbox' &&
          !n.isArchived &&
          !n.isDeleted) {
        inbox = n;
        break;
      }
    }
    final created = inbox == null;
    final target = inbox ??
        Note(
          id: generateId('n'),
          title: 'Inbox',
          content: '',
          tags: ['todo'],
          type: 'todo',
        );
    final previous = target.content;
    final line = '- [ ] ${text.replaceAll('\n', ' ').trim()}';
    setState(() {
      if (created) notes.insert(0, target);
      target.content = previous.isEmpty || previous.endsWith('\n')
          ? '$previous$line\n'
          : '$previous\n$line\n';
      target.updatedAt = DateTime.now();
    });
    _persistNow();
    _showSnackBar(
      'Added to Inbox',
      // Undo removes only the line this capture added — restoring a
      // snapshot would also wipe tasks added or ticked since.
      onUndo: () {
        setState(() {
          final lines = target.content.split('\n');
          final i = lines.lastIndexOf(line);
          if (i != -1) lines.removeAt(i);
          target.content = lines.join('\n');
          final leftover = target.content.trim().isEmpty;
          if (created && leftover) {
            notes.removeWhere((n) => n.id == target.id);
          }
        });
        _persistNow();
      },
    );
  }

  /// Zero-notes home: one explanation + one primary CTA (same action as the
  /// dock + button). Hidden as soon as any note exists.
  Widget _buildHomeEmptyCta() {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nothing here yet',
            style: TextStyle(
              fontSize: AppType.t15,
              fontWeight: FontWeight.w600,
              color: c.fg,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Create a note, track an expense, or start a task list — '
            'the + button does it all.',
            style: TextStyle(fontSize: AppType.t12, height: 1.45, color: c.muted),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _openTemplatePicker,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Create your first note'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(44, 44),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileMenuBar() {
    return _buildWorkspaceHeader(isMobile: true);
  }

  /// Greeting and the date — nothing else competes with the first glance.
  /// "3 weeks ago", "2 months ago" — how long a page has been resting.
  static String _ageLabel(DateTime then, DateTime now) {
    final days = DateTime.utc(now.year, now.month, now.day)
        .difference(DateTime.utc(then.year, then.month, then.day))
        .inDays;
    if (days < 14) return '$days days ago';
    if (days < 60) return '${days ~/ 7} weeks ago';
    if (days < 365) return '${days ~/ 30} months ago';
    final years = days ~/ 365;
    return years == 1 ? 'a year ago' : '$years years ago';
  }

  /// One sentence that knows the day: what you've finished, what's waiting,
  /// or that there's room to write. Encouraging, never a nag.
  String _homeSubline() {
    final done = _doneTodayNow;
    final open = _upNextItems().length;
    String tasks(int n) => n == 1 ? '1 task' : '$n tasks';
    if (done > 0 && open == 0) {
      return 'You finished ${tasks(done)} today. Nothing else waiting.';
    }
    if (done > 0) return '${tasks(done)} done today. Keep the momentum.';
    if (open == 0) return 'Nothing on your plate. A good moment to write.';
    if (open == 1) return 'One thing waiting for you.';
    return '$open things waiting. One at a time.';
  }

  /// Greeting, date, and one line about the day — nothing else competes
  /// with the first glance.
  Widget _buildHomeIntro(DateTime now) {
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 18
            ? 'Good afternoon'
            : 'Good evening';
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${weekdayName(now.weekday)}, ${monthName(now.month)} ${now.day}',
            style: TextStyle(
              fontSize: AppType.t13_5,
              fontWeight: FontWeight.w500,
              color: c.muted,
            ),
          ),
          const SizedBox(height: 4),
          Semantics(
            button: true,
            hint: _displayName == null ? 'Add your name' : 'Change your name',
            child: GestureDetector(
              onTap: _editDisplayName,
              child: Text(
                _displayName == null ? greeting : '$greeting, $_displayName',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.8,
                      color: c.fg,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: AppMotion.duration(context, AppMotion.base),
            child: Text(
              _homeSubline(),
              key: ValueKey(_homeSubline()),
              style: TextStyle(fontSize: AppType.t15, color: c.muted),
            ),
          ),
        ],
      ),
    );
  }

  String? _continueSubtitle(Note note) {
    if (isFinanceNote(note) && note.amounts.isNotEmpty) {
      final counts = <String, int>{};
      for (final e in note.amounts) {
        final cur = e.currency ?? note.currency ?? 'PHP';
        counts[cur] = (counts[cur] ?? 0) + 1;
      }
      var dominant = note.currency ?? 'PHP';
      if (!counts.containsKey(dominant)) {
        dominant = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      }
      var income = 0;
      var expense = 0;
      var count = 0;
      final others = <String>{};
      for (final e in note.amounts) {
        final cur = e.currency ?? note.currency ?? 'PHP';
        if (cur == dominant) {
          // A monthly note holds both directions; adding them together
          // showed ₱15,000 income + ₱180 spent as "₱15,180.00".
          if ((e.type ?? note.type) == 'income') {
            income += e.amount;
          } else {
            expense += e.amount;
          }
          count++;
        } else {
          others.add(cur);
        }
      }
      final amount = income > 0 && expense > 0
          ? 'Net ${formatMinorAmount(income - expense, dominant)}'
          : formatMinorAmount(income + expense, dominant);
      final excl = others.isEmpty ? '' : ' · excl. ${others.join(' · ')}';
      return '$amount · $count '
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
      if (!isVisibleFinanceNote(n)) continue;
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

/// "What should we call you?" — owns its controller, so the field is only
/// disposed after the dialog's closing animation has finished with it.
class _NameDialog extends StatefulWidget {
  final String? initial;

  const _NameDialog({required this.initial});

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('What should we call you?'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLength: 30,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(hintText: 'Your first name'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        if (widget.initial != null)
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Remove'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
