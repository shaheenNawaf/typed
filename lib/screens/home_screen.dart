import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/money_entry.dart';
import '../models/note.dart';
import '../models/budget.dart';
import '../theme/app_colors.dart';
import '../utils/backup.dart';
import '../utils/finance_utils.dart';
import '../utils/note_storage.dart';
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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
  bool _previewMode = false;
  bool _isLoading = true;
  Timer? _persistTimer;
  List<String> _customCategories = [];
  List<String> _recentCategories = [];
  String _financePeriod = 'all';
  List<Budget> _budgets = [];

  @override
  void initState() {
    super.initState();
    _loadAndHandleIntent();
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAndHandleIntent() async {
    final hasData = await _storage.hasSavedData();
    if (hasData) {
      final loaded = await _storage.load();
      if (mounted) setState(() => notes = loaded);
    }
    _generateRecurringEntries();
    final prefs = await SharedPreferences.getInstance();
    final cats = prefs.getStringList('custom_categories') ?? [];
    final recent = prefs.getStringList('recent_categories') ?? [];
    final loadedBudgets = await _storage.loadBudgets();
    if (mounted) {
      setState(() {
        _customCategories = cats;
        _recentCategories = recent;
        _budgets = loadedBudgets;
      });
    }
    const channel = MethodChannel('com.z4yed.typed/widget');
    String? intentAction;
    try {
      intentAction = await channel.invokeMethod<String>('getIntent');
    } catch (_) {}
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (intentAction == 'new') {
      _openTemplatePicker();
    } else if (intentAction != null && intentAction.startsWith('open:')) {
      final id = intentAction.substring(5);
      if (notes.any((n) => n.id == id)) _selectNote(id);
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
    SharedPreferences.getInstance().then((prefs) {
      prefs.setStringList('recent_categories', _recentCategories);
      prefs.setStringList('custom_categories', _customCategories);
    });
  }

  void _generateRecurringEntries() {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    var changed = false;

    for (final note in notes) {
      if (note.type == 'text') continue;
      for (final entry in note.amounts.toList()) {
        if (!entry.isRecurring || entry.recurInterval == null) continue;
        entry.lastGenerated ??= entry.date;

        var next = _nextDate(entry.lastGenerated!, entry.recurInterval!);
        while (!next.isAfter(todayDate)) {
          if (entry.recurEnd != null && next.isAfter(entry.recurEnd!)) break;

          note.amounts.add(MoneyEntry(
            id: 'm${DateTime.now().millisecondsSinceEpoch}',
            amount: entry.amount,
            category: entry.category,
            date: next,
            note: entry.note,
            paymentMethod: entry.paymentMethod,
            currency: entry.currency,
          ));
          entry.lastGenerated = next;
          changed = true;
          next = _nextDate(next, entry.recurInterval!);
        }
      }
    }
    if (changed) _persistNow();
  }

  DateTime _nextDate(DateTime from, String interval) {
    switch (interval) {
      case 'daily':
        return from.add(const Duration(days: 1));
      case 'weekly':
        return from.add(const Duration(days: 7));
      case 'monthly':
        return DateTime(from.year, from.month + 1, from.day);
      case 'yearly':
        return DateTime(from.year + 1, from.month, from.day);
      default:
        return from.add(const Duration(days: 1));
    }
  }

  void _addBudget(Budget budget) {
    setState(() => _budgets = [..._budgets, budget]);
    _storage.saveBudgets(_budgets);
  }

  void _removeBudget(Budget budget) {
    setState(() => _budgets = _budgets.where((b) => b.id != budget.id).toList());
    _storage.saveBudgets(_budgets);
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
      final nDate = DateTime(n.updatedAt.year, n.updatedAt.month, n.updatedAt.day);
      if (nDate == todayDate) return n;
    }
    // Otherwise create one
    final id = 'n${DateTime.now().millisecondsSinceEpoch}';
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

  String _quickDateLabel(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  void _quickAddEntry() {
    final note = _findOrCreateQuickNote('expense');
    setState(() {
      _currentNoteId = note.id;
      _activeFilter = 'finance';
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
          _showSnackBar(
            'Added ${formatAmount(entry.amount, note.currency)} to ${note.title}',
          );
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

  void _persist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 400), () {
      _storage.save(notes);
    });
  }

  void _persistNow() {
    _persistTimer?.cancel();
    _storage.save(notes);
  }

  List<String> get _allTags {
    final tags = <String>{};
    for (final n in notes) {
      tags.addAll(n.tags);
    }
    final list = tags.toList()..sort();
    return list;
  }

  Map<String, int> get _tagCounts {
    final counts = <String, int>{};
    for (final n in notes.where((n) => !n.isArchived && !n.isDeleted)) {
      for (final tag in n.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    return counts;
  }

  List<Note> get _pinnedNotes => notes
      .where((n) => n.isPinned && !n.isArchived && !n.isDeleted)
      .toList();

  Map<String, int> get _counts => {
        'pinned': notes
            .where((n) => n.isPinned && !n.isArchived && !n.isDeleted)
            .length,
        'notes': notes.where((n) => !n.isArchived && !n.isDeleted).length,
        'untagged': notes
            .where((n) => n.tags.isEmpty && !n.isArchived && !n.isDeleted)
            .length,
        'tasks': notes
            .where((n) =>
                !n.isArchived &&
                !n.isDeleted &&
                (n.type == 'todo' ||
                    n.title.toLowerCase().contains('todo') ||
                    n.content.contains('[ ]')))
            .length,
        'today': notes.where((n) =>
            !n.isArchived && !n.isDeleted &&
            _isToday(n.updatedAt)).length,
        'meeting': notes.where((n) =>
            !n.isArchived && !n.isDeleted &&
            n.title.toLowerCase().contains('meeting')).length,
        'journal': notes.where((n) =>
            !n.isArchived && !n.isDeleted &&
            n.title.toLowerCase().contains('journal')).length,
        'finance': notes
            .where((n) =>
                n.type != 'text' && !n.isArchived && !n.isDeleted)
            .length,
        'archive':
            notes.where((n) => n.isArchived && !n.isDeleted).length,
        'trash': notes.where((n) => n.isDeleted).length,
      };

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  bool _isInPeriod(DateTime d) {
    final now = DateTime.now();
    switch (_financePeriod) {
      case 'week':
        final monday = now.subtract(Duration(days: now.weekday - 1));
        final startOfWeek = DateTime(monday.year, monday.month, monday.day);
        return !d.isBefore(startOfWeek);
      case 'month':
        final startOfMonth = DateTime(now.year, now.month, 1);
        return !d.isBefore(startOfMonth);
      case 'year':
        final startOfYear = DateTime(now.year, 1, 1);
        return !d.isBefore(startOfYear);
      default:
        return true;
    }
  }

  bool _isInPreviousPeriod(DateTime d) {
    final now = DateTime.now();
    switch (_financePeriod) {
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
    switch (_financePeriod) {
      case 'week':
        return 7;
      case 'month':
        final start = DateTime(now.year, now.month, 1);
        final nextMonth = DateTime(now.year, now.month + 1, 1);
        return nextMonth.difference(start).inDays.toDouble();
      case 'year': {
        final start = DateTime(now.year, 1, 1);
        final end = DateTime(now.year, 12, 31);
        return end.difference(start).inDays.toDouble() + 1;
      }
      default:
        return 0;
    }
  }

  FinanceSummary get _financeSummary {
    final financeNotes =
        notes.where((n) => n.type != 'text' && !n.isArchived && !n.isDeleted);

    double totalIncome = 0;
    double totalExpense = 0;
    double prevIncome = 0;
    double prevExpense = 0;
    final byCategory = <String, double>{};
    final allEntries = <(MoneyEntry, Note)>[];
    final currencyCounts = <String, int>{};
    final incomeByCurrency = <String, double>{};
    final expenseByCurrency = <String, double>{};
    final currenciesUsed = <String>{};

    for (final n in financeNotes) {
      for (final e in n.amounts) {
        final inPeriod = _isInPeriod(e.date);
        final inPrev = _isInPreviousPeriod(e.date);
        if (!inPeriod && !inPrev) continue;

        final cur = e.currency ?? n.currency ?? 'PHP';
        final effectiveType = e.type ?? n.type;

        if (inPeriod) {
          allEntries.add((e, n));
          currenciesUsed.add(cur);
          if (effectiveType == 'income') {
            totalIncome += e.amount;
            incomeByCurrency[cur] = (incomeByCurrency[cur] ?? 0) + e.amount;
          } else {
            totalExpense += e.amount;
            expenseByCurrency[cur] = (expenseByCurrency[cur] ?? 0) + e.amount;
          }
          byCategory[e.category] = (byCategory[e.category] ?? 0) + e.amount;
          currencyCounts[cur] = (currencyCounts[cur] ?? 0) + 1;
        }

        if (inPrev) {
          if (effectiveType == 'income') {
            prevIncome += e.amount;
          } else {
            prevExpense += e.amount;
          }
        }
      }
    }

    allEntries.sort((a, b) => b.$1.date.compareTo(a.$1.date));
    final sortedCategories = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final dominant = currencyCounts.entries
        .fold<String>('PHP', (acc, e) => e.value > (currencyCounts[acc] ?? 0) ? e.key : acc);

    final avgDaily = _daysInCurrentPeriod > 0
        ? totalExpense / _daysInCurrentPeriod
        : 0.0;

    return FinanceSummary(
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      categories: sortedCategories,
      recentEntries: allEntries.take(5).toList(),
      entryCount: allEntries.length,
      dominantCurrency: dominant,
      incomeByCurrency: incomeByCurrency,
      expenseByCurrency: expenseByCurrency,
      hasMixedCurrencies: currenciesUsed.length > 1,
      previousPeriodExpense: prevExpense,
      previousPeriodIncome: prevIncome,
      averageDailySpend: avgDaily,
    );
  }

  String _dashboardCurrencySymbol(String? code) => currencySymbol(code);

  String _dashboardFormatAmount(double amount, String? currency) {
    final effective = currency ?? _financeSummary.dominantCurrency;
    return formatAmount(amount, effective);
  }

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
        filtered = filtered
            .where((n) =>
                !n.isArchived &&
                !n.isDeleted &&
                (n.type == 'todo' ||
                    n.title.toLowerCase().contains('todo') ||
                    n.content.contains('[ ]')))
            .toList();
      case 'today':
        filtered = filtered
            .where((n) =>
                !n.isArchived && !n.isDeleted && _isToday(n.updatedAt))
            .toList();
      case 'finance':
        filtered = filtered
            .where((n) =>
                n.type != 'text' && !n.isArchived && !n.isDeleted)
            .toList();
      case 'meeting':
        filtered = filtered.where((n) =>
            !n.isArchived && !n.isDeleted &&
            n.title.toLowerCase().contains('meeting')).toList();
      case 'journal':
        filtered = filtered.where((n) =>
            !n.isArchived && !n.isDeleted &&
            n.title.toLowerCase().contains('journal')).toList();
      case 'archive':
        filtered =
            filtered.where((n) => n.isArchived && !n.isDeleted).toList();
      case 'trash':
        filtered = filtered.where((n) => n.isDeleted).toList();
      default:
        filtered =
            filtered.where((n) => !n.isArchived && !n.isDeleted).toList();
    }

    if (_activeTag != null) {
      filtered = filtered.where((n) => n.tags.contains(_activeTag)).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered
          .where((n) =>
              n.title.toLowerCase().contains(q) ||
              n.content.toLowerCase().contains(q) ||
              n.tags.any((t) => t.toLowerCase().contains(q)))
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

  String get _listTitle {
    switch (_activeFilter) {
      case 'home':
        return 'Home';
      case 'pinned':
        return 'Pinned';
      case 'notes':
        return 'All Notes';
      case 'untagged':
        return 'Untagged';
      case 'tasks':
        return 'Tasks';
      case 'today':
        return 'Today';
      case 'meeting':
        return 'Meetings';
      case 'journal':
        return 'Journal';
      case 'finance':
        return 'Finance';
      case 'archive':
        return 'Archive';
      case 'trash':
        return 'Trash';
      default:
        return 'All Notes';
    }
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
            style: TextButton.styleFrom(foregroundColor: context.colors.destructive),
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
    _showSnackBar('Deleted permanently', onUndo: () {
      setState(() {
        notes.insert(index, note);
        note.isArchived = wasArchived;
        note.isDeleted = wasDeleted;
      });
      _persistNow();
    });
  }

  Future<void> _emptyTrash() async {
    final trashed = notes.where((n) => n.isDeleted).toList();
    if (trashed.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Empty trash?'),
        content: Text('${trashed.length} note${trashed.length == 1 ? '' : 's'} will be deleted permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: context.colors.destructive),
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

  void _showSnackBar(String message, {VoidCallback? onUndo}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 5),
        action: onUndo != null
            ? SnackBarAction(label: 'Undo', onPressed: onUndo)
            : null,
      ),
    );
  }

  Future<void> _exportNotes() async {
    try {
      final path = await Backup.exportToFile(notes);
      await Share.shareXFiles(
        [XFile(path)],
        text: 'Typed notes backup',
      );
    } catch (e) {
      _showSnackBar('Export failed: $e');
    }
  }

  Future<void> _exportFinance() async {
    try {
      final path = await Backup.exportFinanceCsv(notes);
      await Share.shareXFiles(
        [XFile(path)],
        text: 'Typed finance export',
      );
    } catch (e) {
      _showSnackBar('Export failed: $e');
    }
  }

  Future<void> _importNotes() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.first.path;
      if (path == null) return;

      final imported = await Backup.importFromFile(path);
      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Replace all notes?'),
          content: Text(
            'This will replace all ${notes.length} current note${notes.length == 1 ? '' : 's'} '
            'with ${imported.length} imported note${imported.length == 1 ? '' : 's'}. '
            'This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: context.colors.destructive),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      setState(() {
        notes
          ..clear()
          ..addAll(imported);
        _currentNoteId = null;
        _showEditor = false;
      });
      _persistNow();
      _showSnackBar('Imported ${imported.length} notes');
    } catch (e) {
      _showSnackBar('Import failed: $e');
    }
  }

  void _openSettings() {
    SettingsSheet.show(
      context,
      onExport: _exportNotes,
      onImport: _importNotes,
      onExportFinance: _exportFinance,
    );
  }

  void _selectNote(String id) {
    final note = _noteById(id);
    if (note == null) return;
    note.viewedAt = DateTime.now();
    setState(() {
      _currentNoteId = id;
      _showEditor = true;
      _previewMode = note.content.isNotEmpty;
    });
  }

  void _openNoteById(String id) {
    _selectNote(id);
  }

  void _createNote([String? title]) {
    final id = 'n${DateTime.now().millisecondsSinceEpoch}';
    final note = Note(
      id: id,
      title: title ?? 'Untitled',
      content: '',
      tags: [],
      viewedAt: DateTime.now(),
    );
    setState(() {
      notes.insert(0, note);
      _currentNoteId = id;
      _activeFilter = 'notes';
      _showEditor = true;
      _previewMode = false;
    });
    _persistNow();
  }

  void _openTemplatePicker() {
    TemplatePickerSheet.show(
      context,
      onPick: _createNoteFromTemplate,
    );
  }

  void _createNoteFromTemplate(NoteTemplate template) {
    final id = 'n${DateTime.now().millisecondsSinceEpoch}';
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
      _showEditor = true;
      _previewMode = template.type != null && template.type != 'text'
          ? false
          : template.content.isNotEmpty;
    });
    _persistNow();
  }

  void _updateTitle(String title) {
    if (_currentNoteId == null) {
      if (title.trim().isNotEmpty) _createNote(title);
      return;
    }
    final note = _noteById(_currentNoteId);
    if (note == null) return;
    note.title = title;
    note.updatedAt = DateTime.now();
    _persist();
  }

  void _updateContent(String content) {
    final note = _noteById(_currentNoteId);
    if (note == null) return;
    note.content = content;
    note.updatedAt = DateTime.now();
    _persist();
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
    note.tags
      ..clear()
      ..addAll(tags);
    note.updatedAt = DateTime.now();
    _persistNow();
    setState(() {});
  }

  void _onTagFilter(String tag) {
    setState(() {
      _activeFilter = 'notes';
      _activeTag = tag;
      _searchQuery = '';
      _currentNoteId = null;
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
      if (filter == 'home') { _currentTab = 'home'; }
      else if (filter == 'finance') { _currentTab = 'finance'; }
      else if (filter == 'tasks') { _currentTab = 'tasks'; }
      else { _currentTab = 'notes'; }
    });
  }

  void _onTabChanged(String tab) {
    setState(() {
      _currentTab = tab;
      _showEditor = false;
      _searchQuery = '';
      _activeTag = null;
      if (tab == 'notes') { _activeFilter = 'notes'; }
      else if (tab == 'finance') { _activeFilter = 'finance'; }
      else if (tab == 'tasks') { _activeFilter = 'tasks'; }
    });
  }

  void _onQuickAction(String action) {
    switch (action) {
      case 'finance':
        _onTabChanged('finance');
      case 'tasks':
        _onTabChanged('tasks');
      case 'meeting': {
        final templates = getNoteTemplates();
        final tmpl = templates.firstWhere((t) => t.name == 'Meeting notes');
        _createNoteFromTemplate(tmpl);
      }
      case 'journal': {
        final templates = getNoteTemplates();
        final tmpl = templates.firstWhere((t) => t.name == 'Daily journal');
        _createNoteFromTemplate(tmpl);
      }
      case 'blank':
        _createNote();
    }
  }

  void _toggleSort() {
    setState(() => _sortDesc = !_sortDesc);
  }

  void _toggleSidebar() {
    setState(() {
      _sidebarState = _sidebarState == 'expanded' ? 'icons' : 'expanded';
    });
  }

  void _setSidebarState(String state) {
    setState(() => _sidebarState = state);
  }

  void _closeEditor() {
    setState(() => _showEditor = false);
  }

  void _togglePreview() {
    setState(() => _previewMode = !_previewMode);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.colors.bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrandMark(size: 56),
              const SizedBox(height: 20),
              Text('Typed',
                  style: GoogleFonts.dmSans(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: context.colors.fg,
                    letterSpacing: -0.5,
                  )),
              const SizedBox(height: 12),
              Text('Loading your notes\u2026',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.colors.muted,
                  )),
            ],
          ),
        ),
      );
    }
    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _openTemplatePicker,
        SingleActivator(LogicalKeyboardKey.escape): _closeEditor,
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 1024) return _buildMobile();
          return _buildDesktop();
        },
      ),
    );
  }

  Widget _buildDesktop() {
    final screenWidth = MediaQuery.of(context).size.width;
    final sidebarOccupied = _sidebarState == 'expanded' ? 232.0 : 48.0;
    final remaining = screenWidth - sidebarOccupied;
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
              onRequestOpen: () => _setSidebarState('expanded'),
              onSettings: _openSettings,
              counts: _counts,
              allTags: _allTags,
              tagCounts: _tagCounts,
              pinnedNotes: _pinnedNotes,
              onNoteSelected: _selectNote,
            ),
            SizedBox(
              width: noteListW,
              child: _activeFilter == 'home'
                  ? _buildHomeScreen()
                  : NoteList(
                      notes: _filteredNotes,
                      currentNoteId: _currentNoteId,
                      onSelectNote: _selectNote,
                      sortDesc: _sortDesc,
                      onSortToggle: _toggleSort,
                      listTitle: _listTitle,
                      searchQuery: _searchQuery,
                      onSearchChanged: (v) => setState(() => _searchQuery = v),
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
                      dashboardCurrencySymbol: _dashboardCurrencySymbol,
                      dashboardFormatAmount: _dashboardFormatAmount,
                      budgets: _budgets,
                      onAddBudget: _addBudget,
                      onRemoveBudget: _removeBudget,
                      onQuickAddEntry: _quickAddEntry,
                    ),
            ),
            Expanded(
              child: _showEditor && _currentNote != null
                  ? Editor(
                      key: ValueKey(_currentNote?.id ?? '__empty__'),
                      note: _currentNote,
                      onTitleChange: _updateTitle,
                      onContentChange: _updateContent,
                      onCreateNote: _createNote,
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
                      onNewNote: _openTemplatePicker,
                      customCategories: _customCategories,
                      recentCategories: _recentCategories,
                      onCategoryUsed: _onCategoryUsed,
                      onSaveNow: () {
                        _persistNow();
                        _showSnackBar('Saved');
                      },
                    )
                  : Container(
                      color: context.colors.bg,
                      child: Center(
                        child: Text(
                          'Select a note to start editing',
                          style: TextStyle(color: context.colors.muted),
                        ),
                      ),
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
        body: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(1.15),
          ),
          child: _showEditor ? _buildEditorFullScreen() : _buildMobileContent(),
        ),
        bottomNavigationBar: _showEditor
            ? null
            : MobileNav(
                currentTab: _currentTab,
                onTabChanged: _onTabChanged,
              ),
      ),
    );
  }

  Widget _buildEditorFullScreen() {
    return SafeArea(
      child: Column(
        children: [
          Container(
            decoration:  BoxDecoration(
              color: context.colors.surface,
              border: Border(bottom: BorderSide(color: context.colors.border)),
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: _closeEditor,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chevron_left,
                            size: 20, color: context.colors.accent),
                        const SizedBox(width: 2),
                        Text('Notes',
                            style: TextStyle(
                                fontSize: 14, color: context.colors.accent)),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      _currentNote?.title ?? 'Untitled',
                      style: TextStyle(
                        fontSize: 14,
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
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _previewMode
                            ? context.colors.accentDim
                            : null,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _previewMode ? 'Edit' : 'Preview',
                        style: TextStyle(
                          fontSize: 13,
                          letterSpacing: 0.02,
                          color: _previewMode
                              ? context.colors.accent
                              : context.colors.muted,
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
              onCreateNote: _createNote,
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
              onNewNote: _openTemplatePicker,
              customCategories: _customCategories,
              recentCategories: _recentCategories,
              onCategoryUsed: _onCategoryUsed,
              onSaveNow: () {
                _persistNow();
                _showSnackBar('Saved');
              },
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
        listTitle: _listTitle,
        searchQuery: _searchQuery,
        onSearchChanged: (v) => setState(() => _searchQuery = v),
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
        dashboardCurrencySymbol: _dashboardCurrencySymbol,
        dashboardFormatAmount: _dashboardFormatAmount,
        budgets: _budgets,
        onAddBudget: _addBudget,
        onRemoveBudget: _removeBudget,
        onQuickAddEntry: _quickAddEntry,
      ),
    );
  }

  Widget _buildMobileContent() {
    switch (_currentTab) {
      case 'home':
        return _buildHomeScreen();
      case 'notes':
      case 'finance':
      case 'tasks':
        return _buildNoteListMobile();
      default:
        return _buildNoteListMobile();
    }
  }

  Widget _buildHomeScreen() {
    final isDesktop = MediaQuery.of(context).size.width >= 1024;
    final recentNotes = notes
        .where((n) => !n.isArchived && !n.isDeleted)
        .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final body = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, isDesktop ? 16 : 10, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHomeSearch(),
          const SizedBox(height: 24),
          _buildSectionTitle('CONTINUE WORKING'),
          const SizedBox(height: 8),
          _buildContinueWorking(),
          const SizedBox(height: 24),
          _buildSectionTitle('QUICK ACTIONS'),
          const SizedBox(height: 8),
          _buildQuickActions(),
          const SizedBox(height: 24),
          _buildSectionTitle('TODAY\'S OVERVIEW'),
          const SizedBox(height: 8),
          _buildTodaysOverview(),
          const SizedBox(height: 24),
          _buildSectionTitle('RECENT NOTES'),
          const SizedBox(height: 8),
          _buildRecentNotes(recentNotes),
        ],
      ),
    );

    return Container(
      color: context.colors.listBg,
      child: isDesktop ? body : SafeArea(child: body),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: context.colors.muted,
        letterSpacing: 0.08,
      ),
    );
  }

  Widget _buildHomeSearch() {
    final isMobile = MediaQuery.of(context).size.width < 1024;
    return TextField(
      readOnly: true,
      onTap: () => Future.microtask(() => _onTabChanged('notes')),
      decoration: InputDecoration(
        hintText: 'Search notes...',
        hintStyle: TextStyle(
          fontSize: isMobile ? 15 : 13.5,
          color: context.colors.muted,
        ),
        prefixIcon: Icon(Icons.search, size: 20, color: context.colors.muted),
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
    );
  }

  Widget _buildContinueWorking() {
    final workingNotes = notes
        .where((n) => !n.isArchived && !n.isDeleted)
        .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final items = <Widget>[];
    final financeNote = workingNotes.cast<Note?>().firstWhere(
      (n) => n!.type != 'text' && n.type != 'todo',
      orElse: () => null,
    );
    if (financeNote != null) {
      items.add(_buildContinueCard(financeNote, Icons.account_balance_wallet_outlined));
    }
    final todoNote = workingNotes.cast<Note?>().firstWhere(
      (n) => n!.type == 'todo' || n.title.toLowerCase().contains('todo'),
      orElse: () => null,
    );
    if (todoNote != null) {
      items.add(_buildContinueCard(todoNote, Icons.check_circle_outline));
    }
    final journalNote = workingNotes.cast<Note?>().firstWhere(
      (n) => n!.title.toLowerCase().contains('journal'),
      orElse: () => null,
    );
    if (journalNote != null) {
      items.add(_buildContinueCard(journalNote, Icons.menu_book_outlined));
    }

    if (items.isEmpty) {
      items.addAll([
        _buildPlaceholderCard('Finance Note', Icons.account_balance_wallet_outlined),
        _buildPlaceholderCard('To-do List', Icons.check_circle_outline),
        _buildPlaceholderCard('Journal', Icons.menu_book_outlined),
      ]);
    }

    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => items[i],
      ),
    );
  }

  Widget _buildContinueCard(Note note, IconData icon) {
    return InkWell(
      onTap: () => Future.microtask(() => _selectNote(note.id)),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: context.colors.accent),
            const Spacer(),
            Text(
              note.title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.colors.fg,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderCard(String label, IconData icon) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: context.colors.muted),
          const Spacer(),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: context.colors.muted,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    final isDesktop = MediaQuery.of(context).size.width >= 1024;
    final availableWidth = isDesktop ? 300.0 : MediaQuery.of(context).size.width - 32;
    final cardWidth = (availableWidth - 10) / 2;

    final actions = [
      ('Finance', Icons.account_balance_wallet_outlined, 'finance'),
      ('Task', Icons.check_circle_outline, 'tasks'),
      ('Meeting', Icons.groups_outlined, 'meeting'),
      ('Journal', Icons.menu_book_outlined, 'journal'),
      ('Blank Note', Icons.note_add_outlined, 'blank'),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: actions.map((a) {
        return InkWell(
          onTap: () => Future.microtask(() => _onQuickAction(a.$3)),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: cardWidth,
            height: 80,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(a.$2, size: 20, color: context.colors.accent),
                Text(
                  a.$1,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: context.colors.fg,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTodaysOverview() {
    final todayCount = notes.where((n) =>
        !n.isArchived && !n.isDeleted && _isToday(n.updatedAt)).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: context.colors.accentDim,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.calendar_today_outlined,
                size: 18, color: context.colors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  todayCount == 1
                      ? '1 note edited today'
                      : '$todayCount notes edited today',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.colors.fg,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tap to view today\'s activity',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.colors.muted,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => Future.microtask(() => _onTabChanged('notes')),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.chevron_right,
                  size: 18, color: context.colors.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentNotes(List<Note> recentNotes) {
    if (recentNotes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            'No notes yet',
            style: TextStyle(fontSize: 13, color: context.colors.muted),
          ),
        ),
      );
    }

    return Column(
      children: recentNotes.take(5).map((note) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: InkWell(
            onTap: () => Future.microtask(() => _selectNote(note.id)),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    note.type == 'todo'
                        ? Icons.check_circle_outline
                        : note.type != 'text'
                            ? Icons.account_balance_wallet_outlined
                            : Icons.article_outlined,
                    size: 16,
                    color: context.colors.accent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      note.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: context.colors.fg,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    _relativeTimeLabel(note.updatedAt),
                    style: TextStyle(
                      fontSize: 10,
                      color: context.colors.muted,
                      fontFamily: context.colors.monoFontFamily,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

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


