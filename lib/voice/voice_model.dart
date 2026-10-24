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

  static const fileName = 'voice-shaper-v2.gguf';
  static const url =
      'https://github.com/shaheenNawaf/typed/releases/download/voice-model-v2/'
      '$fileName';
  static const sha256Hex =
      '9f445847380e33f7ae22e64138e8c0ee323bb82c64555c9a22605d27557d327a';
  static const sizeBytes = 444414880;

  static const _enabledKey = 'voice_model_enabled_v1';

  /// Older models a phone may still have. One keeps working until the
  /// update is downloaded, then it is deleted.
  static const _previous = ['voice-shaper-v1.gguf'];

  /// Android 64-bit only: the native library is built for arm64-v8a and
  /// x86_64 (see android/app/build.gradle.kts). Swappable for tests.
  static bool Function() isSupported = () =>
      !kIsWeb && Platform.isAndroid && _cpuCanRun();

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

  /// Where models live. Swappable for tests.
  static Future<Directory> Function() supportDir =
      getApplicationSupportDirectory;

  static Future<File> file() async {
    final dir = await supportDir();
    return File('${dir.path}/models/$fileName');
  }

  static Future<List<File>> _previousFiles() async {
    final dir = await supportDir();
    return [for (final name in _previous) File('${dir.path}/models/$name')];
  }

  /// The model on this phone: the current one, else an older one.
  static Future<File?> _installed() async {
    final current = await file();
    if (await current.exists()) return current;
    for (final f in await _previousFiles()) {
      if (await f.exists()) return f;
    }
    return null;
  }

  /// Installed and switched on.
  static Future<String?> activePath() async {
    if (!isSupported()) return null;
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_enabledKey) ?? false)) return null;
    return (await _installed())?.path;
  }

  static Future<bool> isInstalled() async => await _installed() != null;

  /// An older model is installed and a better one can be downloaded.
  static Future<bool> hasUpdate() async =>
      !await (await file()).exists() && await _installed() != null;

  /// Progress of the one download in flight (0..1), or null when idle.
  /// A single shared job: closing and reopening the Settings sheet shows
  /// the same download instead of starting a second one.
  static final progress = ValueNotifier<double?>(null);
  static Future<void>? _inFlight;

  /// Downloads (or resumes) into a `.part` file, verifies the SHA-256 of
  /// the whole file, then moves it into place. Joins a download already
  /// running. Throws on network or integrity failure.
  static Future<void> download({HttpClient? client}) {
    return _inFlight ??= _download(client).whenComplete(() {
      _inFlight = null;
      progress.value = null;
    });
  }

  static Future<void> _download(HttpClient? client) async {
    final target = await file();
    await target.parent.create(recursive: true);
    final part = File('${target.path}.part');
    final http = client ?? HttpClient();
    progress.value = 0;
    try {
      var have = await part.exists() ? await part.length() : 0;
      final req = await http.getUrl(Uri.parse(url));
      // Resume a download a dropped connection cut short.
      if (have > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
      final res = await req.close();
      if (res.statusCode == 200) {
        have = 0; // The server sent the whole file: start over.
      } else if (res.statusCode != 206) {
        throw HttpException('HTTP ${res.statusCode}');
      }
      final digestSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      if (have > 0) {
        await for (final chunk in part.openRead()) {
          hasher.add(chunk);
        }
      }
      final sink = part.openWrite(
        mode: have > 0 ? FileMode.append : FileMode.write,
      );
      var got = have;
      try {
        await for (final chunk in res) {
          sink.add(chunk);
          hasher.add(chunk);
          got += chunk.length;
          progress.value = (got / sizeBytes).clamp(0.0, 1.0);
        }
      } finally {
        await sink.close();
      }
      hasher.close();
      if (digestSink.value.toString() != sha256Hex) {
        await part.delete(); // Corrupt: never resume from it.
        throw const FileSystemException('Model download failed its check');
      }
      await part.rename(target.path);
      for (final old in await _previousFiles()) {
        if (await old.exists()) await old.delete();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, true);
    } finally {
      if (client == null) http.close(force: true);
    }
  }

  static Future<void> remove() async {
    final f = await file();
    if (await f.exists()) await f.delete();
    final part = File('${f.path}.part');
    if (await part.exists()) await part.delete();
    for (final old in await _previousFiles()) {
      if (await old.exists()) await old.delete();
    }
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
