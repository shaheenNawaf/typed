import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The optional on-device model for "Smarter voice memos".
///
/// Never bundled in the app: a user who turns it on downloads it once into
/// the app's private storage, and can delete it again. Integrity is checked
/// with SHA-256 before it is ever loaded.
class VoiceModel {
  VoiceModel._();

  static const fileName = 'voice-shaper-v1.gguf';
  static const url =
      'https://github.com/shaheenNawaf/typed/releases/download/voice-model-v1/'
      '$fileName';
  static const sha256Hex =
      '8fc9aa5370a6d1426e348e5fa986f217d843156066c1df7699d8add4d2b4b4da';
  static const sizeBytes = 444414880;

  static const _enabledKey = 'voice_model_enabled_v1';

  /// Android 64-bit only: the native library is built for arm64-v8a and
  /// x86_64 (see android/app/build.gradle.kts). Swappable for tests.
  static bool Function() isSupported =
      () => !kIsWeb && Platform.isAndroid && _cpuCanRun();

  static bool? _cpu;

  /// The native library is built for ARMv8.2 dot-product + fp16 (fast
  /// llama.cpp kernels); cores without them would crash on load, so they
  /// never see the option. x86_64 (emulators) is built for its baseline.
  static bool _cpuCanRun() => _cpu ??= () {
        if (Platform.version.contains('x64')) return true;
        try {
          final info = File('/proc/cpuinfo').readAsStringSync();
          return info.contains('asimddp') && info.contains('fphp');
        } catch (_) {
          return false;
        }
      }();

  static Future<File> file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/models/$fileName');
  }

  /// Installed and switched on.
  static Future<String?> activePath() async {
    if (!isSupported()) return null;
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_enabledKey) ?? false)) return null;
    final f = await file();
    return await f.exists() ? f.path : null;
  }

  static Future<bool> isInstalled() async => (await file()).exists();

  /// Downloads to a temp file, verifies the hash, then moves it into place.
  /// [onProgress] gets 0..1. Throws on network or integrity failure.
  static Future<void> download({
    void Function(double progress)? onProgress,
    HttpClient? client,
  }) async {
    final target = await file();
    await target.parent.create(recursive: true);
    final part = File('${target.path}.part');
    final http = client ?? HttpClient();
    try {
      final req = await http.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode}');
      }
      final total = res.contentLength > 0 ? res.contentLength : sizeBytes;
      final sink = part.openWrite();
      var got = 0;
      final digestSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      await for (final chunk in res) {
        sink.add(chunk);
        hasher.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress?.call(got / total);
      }
      await sink.close();
      hasher.close();
      if (digestSink.value.toString() != sha256Hex) {
        await part.delete();
        throw const FileSystemException('Model download failed its check');
      }
      await part.rename(target.path);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, true);
    } finally {
      if (client == null) http.close(force: true);
      if (await part.exists()) await part.delete();
    }
  }

  static Future<void> remove() async {
    final f = await file();
    if (await f.exists()) await f.delete();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
