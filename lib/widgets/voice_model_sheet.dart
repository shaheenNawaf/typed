import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../voice/voice_feedback.dart';
import '../voice/voice_model.dart';

/// Settings → "Smarter voice memos": download, progress, delete.
class VoiceModelSheet extends StatefulWidget {
  const VoiceModelSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: context.colors.surface,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const VoiceModelSheet(),
    );
  }

  @override
  State<VoiceModelSheet> createState() => _VoiceModelSheetState();
}

class _VoiceModelSheetState extends State<VoiceModelSheet> {
  bool? _installed;
  bool _update = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Reopened mid-download: follow the job already running.
    VoiceModel.progress.addListener(_onProgress);
  }

  @override
  void dispose() {
    VoiceModel.progress.removeListener(_onProgress);
    super.dispose();
  }

  void _onProgress() {
    if (!mounted) return;
    setState(() {});
    // A download started before this sheet opened has just ended.
    if (VoiceModel.progress.value == null) _refresh();
  }

  Future<void> _refresh() async {
    final installed = await VoiceModel.isInstalled();
    final update = await VoiceModel.hasUpdate();
    if (mounted) {
      setState(() {
        _installed = installed;
        _update = update;
      });
    }
  }

  double? get _progress => VoiceModel.progress.value;

  String get _size => VoiceModel.sizeBytes > 0
      ? '${(VoiceModel.sizeBytes / 1e6).round()} MB'
      : 'a few hundred MB';

  Future<void> _download() async {
    setState(() => _error = null);
    try {
      await VoiceModel.download();
      if (mounted) {
        setState(() {
          _installed = true;
          _update = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The download stopped. Tap Download to pick '
              'up where it left off.',
        );
      }
    }
  }

  Future<void> _remove() async {
    await VoiceModel.remove();
    if (mounted) {
      setState(() {
        _installed = false;
        _update = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final busy = _progress != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Smarter voice memos',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: c.fg,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'A small model, trained just for voice memos, that understands '
            'what you meant: tasks you didn’t phrase as tasks, afterthoughts, '
            'and real titles. It runs on this phone; nothing you say leaves '
            'it.',
            style: TextStyle(fontSize: 14, height: 1.45, color: c.muted),
          ),
          const SizedBox(height: 14),
          if (_installed == null)
            const SizedBox(height: 44)
          else if (busy) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: _progress == 0 ? null : _progress,
                minHeight: 4,
                backgroundColor: c.border,
                color: c.fg,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Downloading… ${((_progress ?? 0) * 100).round()}%',
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
          ] else if (_installed!) ...[
            Row(
              children: [
                Icon(Icons.check_rounded, size: 18, color: c.fg),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'On. New memos are shaped on this device.',
                    style: TextStyle(fontSize: 14, color: c.fg),
                  ),
                ),
                TextButton(
                  onPressed: _remove,
                  style: TextButton.styleFrom(foregroundColor: c.muted),
                  child: const Text('Remove'),
                ),
              ],
            ),
            if (_update) ...[
              const SizedBox(height: 12),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(fontSize: 13, color: c.destructive),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'A better model is ready: cleaner tasks and titles. '
                      '$_size; the old one is removed after.',
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _download,
                    style: FilledButton.styleFrom(
                      backgroundColor: c.fg,
                      foregroundColor: c.bg,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Update'),
                  ),
                ],
              ),
            ],
          ] else ...[
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(fontSize: 13, color: c.destructive),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    'One-time download, $_size. Best on Wi-Fi.',
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                ),
                FilledButton(
                  onPressed: _download,
                  style: FilledButton.styleFrom(
                    backgroundColor: c.fg,
                    foregroundColor: c.bg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Download'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _showSheet(BuildContext context, Widget child) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: context.colors.surface,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => child,
  );
}

Widget _sheetTitle(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Text(
    text,
    style: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: context.colors.fg,
    ),
  ),
);

/// Settings → "Voice language": which language voice memos listen for.
/// Only languages this phone can recognise on-device are offered.
class VoiceLanguageSheet extends StatefulWidget {
  const VoiceLanguageSheet({super.key});

  static Future<void> show(BuildContext context) =>
      _showSheet(context, const VoiceLanguageSheet());

  @override
  State<VoiceLanguageSheet> createState() => _VoiceLanguageSheetState();
}

class _VoiceLanguageSheetState extends State<VoiceLanguageSheet> {
  List<LocaleName>? _locales;
  String? _current;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final current = await VoiceLanguage.get();
    var locales = <LocaleName>[];
    try {
      final speech = SpeechToText();
      if (await speech.initialize()) locales = await speech.locales();
    } catch (_) {}
    // English and Filipino first: what a Taglish memo needs.
    int rank(LocaleName l) {
      final id = l.localeId.toLowerCase();
      if (id.startsWith('fil') || id.startsWith('tl')) return 0;
      if (id.startsWith('en')) return id.contains('ph') ? 1 : 2;
      return 3;
    }

    locales.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.name.compareTo(b.name);
    });
    if (!mounted) return;
    setState(() {
      _locales = locales;
      _current = current;
    });
  }

  Future<void> _pick(String? id) async {
    await VoiceLanguage.set(id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final locales = _locales;
    Widget row(String label, String? id) => InkWell(
      onTap: () => _pick(id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: TextStyle(fontSize: 15, color: c.fg)),
            ),
            if (_current == id) Icon(Icons.check_rounded, size: 18, color: c.fg),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sheetTitle(context, 'Voice language'),
          if (locales == null)
            const SizedBox(height: 60)
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  row('Same as this phone', null),
                  for (final l in locales) row(l.name, l.localeId),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Settings → "Voice memo log": the saved memos kept on this phone for
/// improving voice (what was heard, drafted and saved), to share or clear.
class VoiceLogSheet extends StatefulWidget {
  const VoiceLogSheet({super.key});

  static Future<void> show(BuildContext context) =>
      _showSheet(context, const VoiceLogSheet());

  @override
  State<VoiceLogSheet> createState() => _VoiceLogSheetState();
}

class _VoiceLogSheetState extends State<VoiceLogSheet> {
  int? _count;

  @override
  void initState() {
    super.initState();
    VoiceFeedback.count().then((n) {
      if (mounted) setState(() => _count = n);
    });
  }

  Future<void> _share() async {
    final file = await VoiceFeedback.exportFile();
    await Share.shareXFiles([file], text: 'Typed voice memo log');
  }

  Future<void> _clear() async {
    await VoiceFeedback.clear();
    if (mounted) setState(() => _count = 0);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = _count ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sheetTitle(context, 'Voice memo log'),
          Text(
            n == 0
                ? 'No memos yet. Each one you save is kept here, on this '
                      'phone only.'
                : '$n ${n == 1 ? 'memo' : 'memos'}: what was heard and what '
                      'you saved. On this phone only, until you share it.',
            style: TextStyle(fontSize: 14, height: 1.45, color: c.muted),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton(
                onPressed: n == 0 ? null : _share,
                style: FilledButton.styleFrom(
                  backgroundColor: c.fg,
                  foregroundColor: c.bg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Share file'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: n == 0 ? null : _clear,
                style: TextButton.styleFrom(foregroundColor: c.muted),
                child: const Text('Clear'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
