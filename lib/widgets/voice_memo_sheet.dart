import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../voice/transcriber.dart';
import '../voice/voice_shaper.dart';
import 'home_modules.dart';
import 'quiet_choice.dart';
import 'task_row.dart';

/// What the user chose to save from a voice memo.
class VoiceMemoResult {
  final VoiceKind kind;
  final String title;
  final String content;

  const VoiceMemoResult({
    required this.kind,
    required this.title,
    required this.content,
  });
}

/// Record → live transcript → review as a note or a to-do list.
///
/// The transcript is written to prefs as it arrives, so a dismissed sheet,
/// a crash or a lost permission never loses a memo: the next time the sheet
/// opens it picks the draft back up. Only Save or Discard clears it.
class VoiceMemoSheet extends StatefulWidget {
  const VoiceMemoSheet({super.key});

  static const draftKey = 'voice_draft_v1';

  static Future<VoiceMemoResult?> show(BuildContext context) {
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
      builder: (_) => const VoiceMemoSheet(),
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
  final _clock = Stopwatch();
  Timer? _ticker;

  // Review state.
  VoiceKind _kind = VoiceKind.note;
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _tasks = <TextEditingController>[];
  List<String> _other = const [];
  VoiceDraft? _draft;
  bool _titleEdited = false;
  bool _bodyEdited = false;

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
    _clock
      ..reset()
      ..start();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => mounted ? setState(() {}) : null,
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
    _clock.stop();
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
    final draft = shapeVoiceMemo(_transcript);
    for (final t in _tasks) {
      t.dispose();
    }
    _tasks
      ..clear()
      ..addAll(draft.tasks.map((t) => TextEditingController(text: t)));
    _other = List.of(draft.other);
    _draft = draft;
    _kind = draft.kind;
    _title.text = draft.title;
    _body.text = draft.noteBody;
    _titleEdited = false;
    _bodyEdited = false;
    setState(() => _phase = _Phase.review);
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
    final kind = value == 'todo' ? VoiceKind.todo : VoiceKind.note;
    if (kind == _kind) return;
    setState(() {
      _kind = kind;
      final draft = _draft;
      if (!_titleEdited && draft != null) {
        _title.text =
            kind == VoiceKind.todo ? draft.listTitle : draft.noteTitle;
      }
      // An untouched note body follows the edited task list.
      if (kind == VoiceKind.note && !_bodyEdited) {
        _body.text = _noteBodyFromReview();
      }
    });
  }

  List<String> get _taskTexts => _tasks
      .map((c) => c.text.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  String _noteBodyFromReview() => VoiceDraft(
        noteTitle: '',
        listTitle: '',
        kind: VoiceKind.note,
        tasks: _taskTexts,
        other: _other,
      ).noteBody;

  void _save() {
    final title = _title.text.trim();
    final content = _kind == VoiceKind.todo
        ? _taskTexts.map((t) => '- [ ] $t\n').join()
        : _body.text.trim();
    _clearDraft();
    Navigator.of(context).pop(
      VoiceMemoResult(
        kind: _kind,
        title: title.isEmpty ? (_draft?.title ?? 'Voice memo') : title,
        content: content,
      ),
    );
  }

  void _discard() {
    _clearDraft();
    Navigator.of(context).pop();
  }

  void _keepTalking() {
    // Edits to the draft are dropped; what was said is kept and extended.
    _recovered = false;
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
    for (final t in _tasks) {
      t.dispose();
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
    final secs = _clock.elapsed.inSeconds;
    final time =
        '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
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
            const Expanded(child: HomeLabel('LISTENING')),
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
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 120, maxHeight: 280),
          child: SingleChildScrollView(
            reverse: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _transcript.isEmpty
                  ? Text(
                      'Start talking. Say “I need to…” or “remember to…” '
                      'and it becomes a task.',
                      style: TextStyle(fontSize: 17, height: 1.45, color: c.muted),
                    )
                  : Text(
                      _transcript,
                      style: TextStyle(fontSize: 17, height: 1.45, color: c.fg),
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
              child: QuietChoice(
                value: _kind == VoiceKind.todo ? 'todo' : 'note',
                onChanged: _setKind,
                options: const {'note': 'Note', 'todo': 'To-do list'},
              ),
            ),
            if (_recovered)
              Text(
                'From your last memo',
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _title,
          onChanged: (_) => _titleEdited = true,
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
                : TextField(
                    controller: _body,
                    onChanged: (_) => _bodyEdited = true,
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
            _InkButton(label: 'Save', onPressed: _save),
          ],
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
          Row(
            key: ObjectKey(_tasks[i]),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: ExcludeSemantics(
                  child: TaskCheck(done: false, onTap: () {}, size: 20),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _tasks[i],
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
                  _tasks.removeAt(i).dispose();
                }),
                icon: Icon(Icons.close_rounded, size: 16, color: c.muted),
              ),
            ],
          ),
        TaskAddRow(
          dense: true,
          hint: _tasks.isEmpty ? 'Add the first task' : 'Add a task',
          onSubmit: (t) => setState(
            () => _tasks.add(TextEditingController(text: t)),
          ),
        ),
        if (_other.isNotEmpty) ...[
          const SizedBox(height: 14),
          const HomeLabel('NOT IN THE LIST'),
          for (var i = 0; i < _other.length; i++)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() {
                final text = _other[i].replaceFirst(RegExp(r'[.!?]$'), '');
                _tasks.add(TextEditingController(text: text));
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
