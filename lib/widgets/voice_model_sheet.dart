import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
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
  double? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    VoiceModel.isInstalled().then((v) {
      if (mounted) setState(() => _installed = v);
    });
  }

  String get _size =>
      VoiceModel.sizeBytes > 0
          ? '${(VoiceModel.sizeBytes / 1e6).round()} MB'
          : 'a few hundred MB';

  Future<void> _download() async {
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      await VoiceModel.download(
        onProgress: (p) => mounted ? setState(() => _progress = p) : null,
      );
      if (mounted) setState(() => _installed = true);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'The download didn’t finish. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  Future<void> _remove() async {
    await VoiceModel.remove();
    if (mounted) setState(() => _installed = false);
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
          ] else ...[
            if (_error != null) ...[
              Text(_error!, style: TextStyle(fontSize: 13, color: c.destructive)),
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
