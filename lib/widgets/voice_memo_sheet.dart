import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../voice/spend_parser.dart';
import '../voice/transcriber.dart';
import '../voice/voice_shaper.dart';
import '../voice/when_parser.dart';
import 'entry_sheet.dart' show kDefaultCategories;
import 'home_modules.dart';
import 'quiet_choice.dart';
import 'task_row.dart';

/// An existing to-do list a voice memo's tasks can be added to.
class VoiceListTarget {
  final String id;
  final String title;
  const VoiceListTarget(this.id, this.title);
}

/// What the user chose to save from a voice memo.
class VoiceMemoResult {
  final VoiceKind kind;
  final String title;
  final String content;

  /// Add the tasks to this existing list instead of creating one.
  final String? appendToId;

  /// The task lines on their own (for appending).
  final List<String> tasks;

  /// Tasks with the reminder each one asked for.
  final List<VoiceTaskOut> taskItems;

  /// Expenses (and income) to log, for [VoiceKind.expense].
  final List<VoiceSpend> spends;

  const VoiceMemoResult({
    required this.kind,
    required this.title,
    required this.content,
    this.appendToId,
    this.tasks = const [],
    this.taskItems = const [],
    this.spends = const [],
  });
}

/// A saved task line and when to remind about it (null: no reminder).
class VoiceTaskOut {
  final String line;
  final DateTime? remindAt;
  const VoiceTaskOut(this.line, this.remindAt);
}

/// Dictating into an open note or list: the shape is fixed to match it and
/// Save adds to it.
class VoiceAppendTarget {
  final String title;
  final bool isList;
  const VoiceAppendTarget(this.title, {required this.isList});
}

class _TaskEdit {
  final TextEditingController ctrl;
  SpokenWhen? when;
  bool remind;

  _TaskEdit(String text, [this.when])
    : ctrl = TextEditingController(text: text),
      remind = when != null;

  factory _TaskEdit.from(VoiceTask t) => _TaskEdit(t.text, t.when);

  String get line {
    final text = ctrl.text.trim();
    return when == null ? text : '$text — ${when!.label}';
  }
}

class _SpendEdit {
  final TextEditingController amount;
  final TextEditingController note;
  String category;
  String type;

  _SpendEdit(VoiceSpend s)
    : amount = TextEditingController(text: s.amount),
      note = TextEditingController(text: s.note),
      category = s.category,
      type = s.type;

  void dispose() {
    amount.dispose();
    note.dispose();
  }
}

/// Record → live transcript → review as a note or a to-do list.
///
/// The transcript is written to prefs as it arrives, so a dismissed sheet,
/// a crash or a lost permission never loses a memo: the next time the sheet
/// opens it picks the draft back up. Only Save or Discard clears it.
class VoiceMemoSheet extends StatefulWidget {
  /// Existing lists a to-do memo can be added to, most recent first.
  final List<VoiceListTarget> lists;

  /// Dictating into this open note or list instead of making a new one.
  final VoiceAppendTarget? appendTo;

  /// Shown before expense amounts ("₱").
  final String currencySymbol;

  const VoiceMemoSheet({
    super.key,
    this.lists = const [],
    this.appendTo,
    this.currencySymbol = '',
  });

  static const draftKey = 'voice_draft_v1';

  static Future<VoiceMemoResult?> show(
    BuildContext context, {
    List<VoiceListTarget> lists = const [],
    VoiceAppendTarget? appendTo,
    String currencySymbol = '',
  }) {
    final c = context.colors;
    return showModalBottomSheet<VoiceMemoResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: c.surface,
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => VoiceMemoSheet(
        lists: lists,
        appendTo: appendTo,
        currencySymbol: currencySymbol,
      ),
    );
  }

  @override
  State<VoiceMemoSheet> createState() => _VoiceMemoSheetState();
}

enum _Phase { preparing, listening, problem, review }

class _VoiceMemoSheetState extends State<VoiceMemoSheet>
    with SingleTickerProviderStateMixin {
  late final Transcriber _transcriber = VoiceMemo.createTranscriber();
  // Not `late`: a lazily-made controller was first created inside
  // dispose() when the sheet opened straight into a recovered draft.
  late final AnimationController _pulse;

  _Phase _phase = _Phase.preparing;
  TranscriberProblem? _problem;
  bool _recovered = false;

  /// Transcript from earlier takes ("Keep talking" appends to it).
  String _before = '';
  String _live = '';

  /// Seconds recorded this take, counted by [_ticker].
  int _seconds = 0;
  Timer? _ticker;

  // Review state.
  VoiceKind _kind = VoiceKind.note;
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _tasks = <_TaskEdit>[];
  final _spends = <_SpendEdit>[];
  List<String> _other = const [];
  VoiceDraft? _draft;
  bool _titleEdited = false;
  bool _bodyEdited = false;

  /// The optional on-device model is reshaping the draft.
  bool _refining = false;
  bool _refined = false;

  /// Any edit in review: a late model draft must never overwrite it.
  bool _touched = false;
  int _refineRun = 0;

  /// Recent input loudness (0..1), newest last, for the level meter.
  final _levels = <double>[];
  bool _heardSound = false;

  /// "Keep talking" after editing: the new take is shaped on its own and
  /// added to the edited draft instead of replacing it.
  int? _mergeFrom;

  /// Review: the raw transcript, editable, behind a toggle.
  bool _showTranscript = false;
  final _transcriptCtrl = TextEditingController();

  /// Review: which list a to-do memo goes to (null = a new list).
  String? _appendToId;

  String get _transcript =>
      [_before, _live].where((s) => s.trim().isNotEmpty).join(' ').trim();

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _begin();
  }

  Future<void> _begin() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(VoiceMemoSheet.draftKey)?.trim() ?? '';
    if (!mounted) return;
    if (saved.isNotEmpty) {
      // A memo from last time was never saved or discarded: offer it first.
      _before = saved;
      _recovered = true;
      _toReview();
      return;
    }
    await _listen();
  }

  Future<void> _listen() async {
    setState(() {
      _phase = _Phase.preparing;
      _problem = null;
    });
    final problem = await _transcriber.prepare();
    if (!mounted) return;
    if (problem != null) {
      setState(() {
        _phase = _Phase.problem;
        _problem = problem;
      });
      return;
    }
    HapticFeedback.lightImpact();
    _live = '';
    _levels.clear();
    _heardSound = false;
    _seconds = 0;
    _ticker?.cancel();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => mounted ? setState(() => _seconds++) : null,
    );
    if (!MediaQuery.disableAnimationsOf(context)) {
      _pulse.repeat(reverse: true);
    }
    setState(() => _phase = _Phase.listening);
    await _transcriber.start(
      onText: (text) {
        if (!mounted) return;
        // Never let a blank update erase words already on screen.
        if (text.trim().isEmpty && _live.trim().isNotEmpty) return;
        setState(() => _live = text);
        _saveDraft();
      },
      onLevel: (level) {
        if (!mounted) return;
        setState(() {
          _levels.add(level);
          if (_levels.length > 40) _levels.removeAt(0);
          if (level > 0.15) _heardSound = true;
        });
      },
      onProblem: (problem) {
        if (!mounted) return;
        _stopClock();
        // Keep whatever was heard; the review explains what happened.
        _before = _transcript;
        _live = '';
        _saveDraft();
        if (_before.isNotEmpty) {
          _toReview();
        } else {
          setState(() {
            _phase = _Phase.problem;
            _problem = problem;
          });
        }
      },
    );
  }

  void _stopClock() {
    _ticker?.cancel();
    _pulse.stop();
  }

  Future<void> _done() async {
    _stopClock();
    HapticFeedback.lightImpact();
    final shown = _live;
    final stopped = await _transcriber.stop();
    if (!mounted) return;
    // What the user watched appear is the floor: a recogniser that hands
    // back less (or nothing) on stop must not empty the memo.
    final text = stopped.trim().length >= shown.trim().length ? stopped : shown;
    _before = [_before, text].where((s) => s.trim().isNotEmpty).join(' ');
    _live = '';
    _saveDraft();
    _toReview();
  }

  /// Cancel keeps nothing from this take; earlier takes stay in review.
  Future<void> _cancelTake() async {
    _stopClock();
    await _transcriber.cancel();
    if (!mounted) return;
    _live = '';
    if (_before.isEmpty) {
      await _clearDraft();
      if (mounted) Navigator.of(context).pop();
    } else {
      await _saveDraft();
      _toReview();
    }
  }

  void _toReview() {
    final mergeFrom = _mergeFrom;
    _mergeFrom = null;
    if (mergeFrom != null) {
      // The user had edited the draft: keep their edits and add what the
      // new take said on its own.
      final added = _transcript.length > mergeFrom
          ? _transcript.substring(mergeFrom).trim()
          : '';
      if (added.isNotEmpty) _mergeTake(shapeVoiceMemo(added));
      _transcriptCtrl.text = _transcript;
      setState(() => _phase = _Phase.review);
      return;
    }
    _applyDraft(shapeVoiceMemo(_transcript));
    _transcriptCtrl.text = _transcript;
    _touched = false;
    _refined = false;
    setState(() => _phase = _Phase.review);
    _refine();
  }

  void _mergeTake(VoiceDraft take) {
    _tasks.addAll(take.tasks.map(_TaskEdit.from));
    _spends.addAll(take.spends.map(_SpendEdit.new));
    _other = [..._other, ...take.other];
    final extra = take.noteBody.trim();
    if (extra.isNotEmpty) {
      _body.text = [
        _body.text.trim(),
        extra,
      ].where((s) => s.isNotEmpty).join('\n\n');
    }
  }

  /// Re-shape from the (possibly corrected) transcript. Replaces the
  /// draft, so it is an explicit action.
  void _reshape() {
    final text = _transcriptCtrl.text.trim();
    _before = text;
    _live = '';
    _saveDraft();
    _showTranscript = false;
    _toReview();
  }

  /// Rules draft first (instant), then the model's, if it is installed and
  /// the user has not started editing.
  Future<void> _refine() async {
    final run = ++_refineRun;
    final transcript = _transcript;
    if (transcript.isEmpty) return;
    setState(() => _refining = true);
    VoiceDraft? better;
    try {
      better = await VoiceMemo.refine(transcript);
    } catch (_) {
      better = null;
    }
    if (!mounted || run != _refineRun) return;
    setState(() {
      _refining = false;
      if (better != null && !_touched) {
        _applyDraft(better);
        _refined = true;
      }
    });
  }

  void _applyDraft(VoiceDraft draft) {
    for (final t in _tasks) {
      t.ctrl.dispose();
    }
    for (final s in _spends) {
      s.dispose();
    }
    _tasks
      ..clear()
      ..addAll(draft.tasks.map(_TaskEdit.from));
    _spends
      ..clear()
      ..addAll(draft.spends.map(_SpendEdit.new));
    _other = List.of(draft.other);
    _draft = draft;
    // Dictating into an open note or list: its shape is fixed.
    final into = widget.appendTo;
    _kind = into == null
        ? draft.kind
        : into.isList
        ? VoiceKind.todo
        : VoiceKind.note;
    _title.text = draft.title;
    _body.text = draft.noteBody;
    _titleEdited = false;
    _bodyEdited = false;
  }

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(VoiceMemoSheet.draftKey, _transcript);
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(VoiceMemoSheet.draftKey);
  }

  void _setKind(String value) {
    final kind = switch (value) {
      'todo' => VoiceKind.todo,
      'expense' => VoiceKind.expense,
      _ => VoiceKind.note,
    };
    if (kind == _kind) return;
    _touched = true;
    setState(() {
      _kind = kind;
      final draft = _draft;
      if (!_titleEdited && draft != null) {
        _title.text = kind == VoiceKind.todo
            ? draft.listTitle
            : draft.noteTitle;
      }
      // An untouched note body follows the edited task list.
      if (kind == VoiceKind.note && !_bodyEdited) {
        _body.text = _noteBodyFromReview();
      }
    });
  }

  List<_TaskEdit> get _liveTasks =>
      _tasks.where((t) => t.ctrl.text.trim().isNotEmpty).toList();

  List<String> get _taskTexts => [for (final t in _liveTasks) t.line];

  String _noteBodyFromReview() => VoiceDraft(
    noteTitle: '',
    listTitle: '',
    kind: VoiceKind.note,
    tasks: [for (final t in _liveTasks) VoiceTask(t.ctrl.text.trim(), t.when)],
    other: _other,
  ).noteBody;

  List<VoiceSpend> get _spendsOut => [
    for (final e in _spends)
      if (double.tryParse(e.amount.text.replaceAll(',', '').trim())
          case final v? when v > 0)
        VoiceSpend(
          amount: e.amount.text.replaceAll(',', '').trim(),
          note: e.note.text.trim(),
          category: e.category,
          type: e.type,
        ),
  ];

  void _save() {
    final title = _title.text.trim();
    final todo = _kind == VoiceKind.todo;
    final content = todo
        ? _taskTexts.map((t) => '- [ ] $t\n').join()
        : _body.text.trim();
    _clearDraft();
    final now = DateTime.now();
    Navigator.of(context).pop(
      VoiceMemoResult(
        kind: _kind,
        title: title.isEmpty ? (_draft?.title ?? 'Voice memo') : title,
        content: content,
        tasks: todo ? _taskTexts : const [],
        taskItems: [
          for (final t in _liveTasks)
            VoiceTaskOut(
              t.line,
              t.remind && t.when != null && t.when!.at.isAfter(now)
                  ? t.when!.at
                  : null,
            ),
        ],
        appendToId: todo ? _appendToId : null,
        spends: _kind == VoiceKind.expense ? _spendsOut : const [],
      ),
    );
  }

  void _discard() {
    _clearDraft();
    Navigator.of(context).pop();
  }

  void _keepTalking() {
    _recovered = false;
    _refineRun++;
    _refining = false;
    // Edited drafts keep their edits; the new take is added to them.
    if (_touched) _mergeFrom = _transcript.length;
    _listen();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulse.dispose();
    if (_phase == _Phase.listening || _phase == _Phase.preparing) {
      // Swiped away mid-memo: the draft is already saved; just stop the mic.
      _transcriber.cancel();
    }
    _title.dispose();
    _body.dispose();
    _transcriptCtrl.dispose();
    for (final t in _tasks) {
      t.ctrl.dispose();
    }
    for (final s in _spends) {
      s.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: c.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: AppMotion.duration(context, AppMotion.base),
                switchInCurve: AppMotion.decelerate,
                transitionBuilder: (child, a) =>
                    FadeTransition(opacity: a, child: child),
                child: KeyedSubtree(
                  key: ValueKey(_phase),
                  child: switch (_phase) {
                    _Phase.preparing => _preparing(context),
                    _Phase.listening => _listening(context),
                    _Phase.problem => _problemView(context),
                    _Phase.review => _review(context),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── listening ───────────────────────────────────────────────────────────

  Widget _preparing(BuildContext context) => const SizedBox(
    height: 180,
    child: Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );

  Widget _listening(BuildContext context) {
    final c = context.colors;
    final secs = _seconds;
    final time = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            FadeTransition(
              opacity: Tween(begin: 1.0, end: 0.3).animate(_pulse),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: c.destructive,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: const HomeLabel('LISTENING'),
              ),
            ),
            Text(
              time,
              style: TextStyle(
                fontSize: 13,
                color: c.muted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Live input level: proof the mic is hearing you.
        ExcludeSemantics(
          child: SizedBox(
            height: 28,
            child: CustomPaint(
              painter: _LevelPainter(
                levels: List.of(_levels),
                color: c.fg,
                track: c.border,
              ),
            ),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 120, maxHeight: 280),
          child: SingleChildScrollView(
            reverse: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _transcript.isEmpty
                  ? Text(
                      // After a few silent seconds, say why nothing shows.
                      secs >= 4 && !_heardSound
                          ? 'Not hearing much yet. Hold the phone a little '
                                'closer, or speak up a bit.'
                          : 'Start talking. “New task…” starts a task; “spent 250 on '
                                'lunch” logs money.',
                      style: TextStyle(
                        fontSize: 17,
                        height: 1.45,
                        color: c.muted,
                      ),
                    )
                  : Semantics(
                      liveRegion: true,
                      child: Text(
                        _transcript,
                        style: TextStyle(
                          fontSize: 17,
                          height: 1.45,
                          color: c.fg,
                        ),
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 14, color: c.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Transcribed on this device',
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            ),
            TextButton(
              onPressed: _cancelTake,
              style: TextButton.styleFrom(foregroundColor: c.muted),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 6),
            _InkButton(label: 'Done', onPressed: _done),
          ],
        ),
      ],
    );
  }

  Widget _problemView(BuildContext context) {
    final c = context.colors;
    final (title, body) = switch (_problem) {
      TranscriberProblem.permission => (
        'Microphone access is off',
        'Allow microphone access for Typed in your phone’s settings, then '
            'try again.',
      ),
      TranscriberProblem.language => (
        'No offline speech for this language',
        'Download it in Settings → System → Languages → On-device speech '
            'recognition, then try again.',
      ),
      _ => (
        'Voice memos need on-device speech',
        'This phone has no on-device speech recognition (it needs Android '
            '12 or later). Typed never sends your voice to the cloud.',
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.mic_off_outlined, size: 28, color: c.muted),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: c.fg,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.4, color: c.muted),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(foregroundColor: c.muted),
                child: const Text('Close'),
              ),
              const SizedBox(width: 8),
              _InkButton(label: 'Try again', onPressed: _listen),
            ],
          ),
        ],
      ),
    );
  }

  // ── review ──────────────────────────────────────────────────────────────

  Widget _review(BuildContext context) {
    final c = context.colors;
    final maxH = MediaQuery.sizeOf(context).height * 0.62;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: widget.appendTo != null
                  ? Text(
                      'Adding to ${widget.appendTo!.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.muted,
                      ),
                    )
                  : QuietChoice(
                      value: _kind.name,
                      onChanged: _setKind,
                      options: {
                        'note': 'Note',
                        'todo': 'To-do list',
                        // Offered when money was heard (or already chosen).
                        if (_spends.isNotEmpty || _kind == VoiceKind.expense)
                          'expense': 'Expense',
                      },
                    ),
            ),
            if (_refining)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: c.muted,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Refining…',
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                ],
              )
            else if (_refined)
              Text(
                'Shaped on this device',
                style: TextStyle(fontSize: 12, color: c.muted),
              )
            else if (_recovered)
              Text(
                'From your last memo',
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // Expenses have no title; a note being added to keeps its own.
        if (_kind != VoiceKind.expense && widget.appendTo == null)
          TextField(
            controller: _title,
            onChanged: (_) => _titleEdited = _touched = true,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: c.fg,
            ),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
              hintText: 'Title',
            ),
          ),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SingleChildScrollView(
            child: _kind == VoiceKind.todo
                ? _taskEditor(context)
                : _kind == VoiceKind.expense
                ? _spendEditor(context)
                : TextField(
                    controller: _body,
                    onChanged: (_) => _bodyEdited = _touched = true,
                    minLines: 3,
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(fontSize: 16, height: 1.5, color: c.fg),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Nothing was heard. Type instead?',
                      hintStyle: TextStyle(color: c.muted),
                    ),
                  ),
          ),
        ),
        if (_kind == VoiceKind.todo &&
            widget.lists.isNotEmpty &&
            widget.appendTo == null)
          _destination(context),
        _transcriptPanel(context),
        const SizedBox(height: 12),
        Row(
          children: [
            // Flexible: the label gives way on narrow phones and large text
            // before Save can be pushed off the edge.
            Flexible(
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _keepTalking,
                  icon: const Icon(Icons.mic_none_rounded, size: 18),
                  label: const Text(
                    'Keep talking',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: TextButton.styleFrom(foregroundColor: c.fg),
                ),
              ),
            ),
            const SizedBox(width: 6),
            TextButton(
              onPressed: _discard,
              style: TextButton.styleFrom(foregroundColor: c.muted),
              child: const Text('Discard'),
            ),
            const SizedBox(width: 6),
            _InkButton(
              label: widget.appendTo != null
                  ? 'Add'
                  : _kind == VoiceKind.expense
                  ? 'Log'
                  : 'Save',
              onPressed: _save,
            ),
          ],
        ),
      ],
    );
  }

  /// "Save to: New list ▾" — add the tasks to an existing list instead.
  Widget _destination(BuildContext context) {
    final c = context.colors;
    final current = widget.lists
        .where((l) => l.id == _appendToId)
        .map((l) => l.title)
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Text('Save to', style: TextStyle(fontSize: 13, color: c.muted)),
          const SizedBox(width: 6),
          Flexible(
            child: PopupMenuButton<String>(
              tooltip: 'Choose where the tasks go',
              onSelected: (id) =>
                  setState(() => _appendToId = id.isEmpty ? null : id),
              itemBuilder: (_) => [
                const PopupMenuItem(value: '', child: Text('A new list')),
                for (final l in widget.lists.take(8))
                  PopupMenuItem(value: l.id, child: Text(l.title)),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        current ?? 'A new list',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.fg,
                        ),
                      ),
                    ),
                    Icon(Icons.expand_more_rounded, size: 18, color: c.muted),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The raw transcript behind a toggle: fix a misheard word, then
  /// re-shape the draft from it.
  Widget _transcriptPanel(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _showTranscript = !_showTranscript),
            icon: Icon(
              _showTranscript
                  ? Icons.expand_less_rounded
                  : Icons.subject_rounded,
              size: 18,
            ),
            label: Text(_showTranscript ? 'Hide transcript' : 'Transcript'),
            style: TextButton.styleFrom(foregroundColor: c.muted),
          ),
        ),
        if (_showTranscript) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            decoration: BoxDecoration(
              color: c.fg.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _transcriptCtrl,
              minLines: 2,
              maxLines: 6,
              style: TextStyle(fontSize: 14.5, height: 1.45, color: c.fg),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'What was heard',
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _reshape,
              style: TextButton.styleFrom(foregroundColor: c.fg),
              child: const Text('Re-shape from transcript'),
            ),
          ),
        ],
      ],
    );
  }

  /// Under each task: its date as a chip (tap to change, × to clear) and a
  /// reminder bell. Undated tasks get a quiet "Add date".
  Widget _whenRow(BuildContext context, _TaskEdit t) {
    final c = context.colors;
    final when = t.when;
    final canRemind = when != null && when.at.isAfter(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(left: 30, bottom: 4),
      child: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _pickWhen(t),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: when == null
                    ? Colors.transparent
                    : c.fg.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_rounded, size: 14, color: c.muted),
                  const SizedBox(width: 5),
                  Text(
                    when?.label ?? 'Add date',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: when == null ? c.muted : c.fg,
                      fontWeight: when == null
                          ? FontWeight.w400
                          : FontWeight.w500,
                    ),
                  ),
                  if (when != null) ...[
                    const SizedBox(width: 4),
                    Semantics(
                      button: true,
                      label: 'Clear date',
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _touched = true;
                          t.when = null;
                          t.remind = false;
                        }),
                        child: Icon(
                          Icons.close_rounded,
                          size: 13,
                          color: c.muted,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (when != null)
            IconButton(
              tooltip: !canRemind
                  ? 'That time has passed'
                  : t.remind
                  ? 'Reminder on'
                  : 'Remind me',
              visualDensity: VisualDensity.compact,
              onPressed: canRemind
                  ? () => setState(() {
                      _touched = true;
                      t.remind = !t.remind;
                    })
                  : null,
              icon: Icon(
                t.remind && canRemind
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
                size: 18,
                color: t.remind && canRemind ? c.fg : c.muted,
              ),
            ),
        ],
      ),
    );
  }

  /// Date, then (optionally) time. Cancelling the time keeps a date-only
  /// reminder at 9 AM.
  Future<void> _pickWhen(_TaskEdit t) async {
    final now = DateTime.now();
    final start = t.when?.day ?? DateTime(now.year, now.month, now.day);
    final day = await showDatePicker(
      context: context,
      initialDate: start.isBefore(DateTime(now.year, now.month, now.day))
          ? now
          : start,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: t.when?.hour ?? 9,
        minute: t.when?.minute ?? 0,
      ),
      helpText: 'Remind at (optional)',
    );
    if (!mounted) return;
    setState(() {
      _touched = true;
      t.when = time == null
          ? SpokenWhen(day)
          : SpokenWhen.fromDateTime(
              DateTime(day.year, day.month, day.day, time.hour, time.minute),
            );
      t.remind = true;
    });
  }

  /// Money heard in the memo: description, amount and category per row.
  Widget _spendEditor(BuildContext context) {
    final c = context.colors;
    final cats = [...kDefaultCategories, 'Income', 'Salary'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _spends.length; i++)
          Padding(
            key: ObjectKey(_spends[i]),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Semantics(
                  button: true,
                  label: _spends[i].type == 'income'
                      ? 'Income, tap for expense'
                      : 'Expense, tap for income',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => setState(() {
                      _touched = true;
                      final e = _spends[i];
                      e.type = e.type == 'income' ? 'expense' : 'income';
                    }),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        _spends[i].type == 'income'
                            ? Icons.add_rounded
                            : Icons.remove_rounded,
                        size: 18,
                        color: _spends[i].type == 'income' ? c.income : c.fg,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _spends[i].note,
                    onChanged: (_) => _touched = true,
                    textCapitalization: TextCapitalization.sentences,
                    style: taskTextStyle(context, done: false),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: _spends[i].category,
                    ),
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: _spends[i].amount,
                    onChanged: (_) => _touched = true,
                    textAlign: TextAlign.end,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: c.fg,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      prefixText: widget.currencySymbol,
                      hintText: '0',
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Category',
                  onSelected: (v) => setState(() {
                    _touched = true;
                    _spends[i].category = v;
                  }),
                  itemBuilder: (_) => [
                    for (final cat in cats)
                      PopupMenuItem(value: cat, child: Text(cat)),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    child: Text(
                      _spends[i].category,
                      style: TextStyle(fontSize: 12.5, color: c.muted),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    _touched = true;
                    _spends.removeAt(i).dispose();
                  }),
                  icon: Icon(Icons.close_rounded, size: 16, color: c.muted),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() {
              _touched = true;
              _spends.add(
                _SpendEdit(
                  const VoiceSpend(amount: '', note: '', category: 'Other'),
                ),
              );
            }),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(_spends.isEmpty ? 'Add an expense' : 'Add another'),
            style: TextButton.styleFrom(foregroundColor: c.muted),
          ),
        ),
      ],
    );
  }

  Widget _taskEditor(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _tasks.length; i++)
          Column(
            key: ObjectKey(_tasks[i]),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: ExcludeSemantics(
                      child: TaskCheck(done: false, onTap: () {}, size: 20),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _tasks[i].ctrl,
                      onChanged: (_) => _touched = true,
                      // Wrap: a dated task ("… — Sun, Oct 25") ran off the edge.
                      minLines: 1,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      style: taskTextStyle(context, done: false),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove task',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() {
                      _touched = true;
                      _tasks.removeAt(i).ctrl.dispose();
                    }),
                    icon: Icon(Icons.close_rounded, size: 16, color: c.muted),
                  ),
                ],
              ),
              _whenRow(context, _tasks[i]),
            ],
          ),
        TaskAddRow(
          dense: true,
          hint: _tasks.isEmpty ? 'Add the first task' : 'Add a task',
          onSubmit: (t) => setState(() {
            _touched = true;
            _tasks.add(_TaskEdit(t));
          }),
        ),
        if (_other.isNotEmpty) ...[
          const SizedBox(height: 14),
          const HomeLabel('NOT IN THE LIST'),
          for (var i = 0; i < _other.length; i++)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() {
                _touched = true;
                final text = _other[i].replaceFirst(RegExp(r'[.!?]$'), '');
                _tasks.add(_TaskEdit(text));
                _other = List.of(_other)..removeAt(i);
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 10),
                      child: Icon(Icons.add_rounded, size: 16, color: c.muted),
                    ),
                    Expanded(
                      child: Text(
                        _other[i],
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: c.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// The solid ink key used for the sheet's primary action.
class _InkButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _InkButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: c.fg,
        foregroundColor: c.bg,
        minimumSize: const Size(88, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

/// A rolling row of thin bars: recent input loudness, newest on the right.
class _LevelPainter extends CustomPainter {
  final List<double> levels;
  final Color color;
  final Color track;

  _LevelPainter({
    required this.levels,
    required this.color,
    required this.track,
  });

  static const _bars = 40;

  @override
  void paint(Canvas canvas, Size size) {
    final gap = 3.0;
    final w = ((size.width - gap * (_bars - 1)) / _bars).clamp(1.5, 4.0);
    final total = _bars * w + (_bars - 1) * gap;
    final left = (size.width - total) / 2;
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < _bars; i++) {
      final k = i - (_bars - levels.length);
      final v = k >= 0 ? levels[k] : 0.0;
      final h = (size.height * (0.12 + 0.88 * v)).clamp(2.0, size.height);
      final x = left + i * (w + gap) + w / 2;
      paint
        ..strokeWidth = w
        ..color = v > 0.05 ? color.withValues(alpha: 0.35 + 0.5 * v) : track;
      canvas.drawLine(
        Offset(x, (size.height - h) / 2),
        Offset(x, (size.height + h) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LevelPainter old) =>
      old.levels.length != levels.length ||
      (levels.isNotEmpty && old.levels.lastOrNull != levels.last);
}
