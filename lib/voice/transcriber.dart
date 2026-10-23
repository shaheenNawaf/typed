import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'llm_shaper.dart';
import 'voice_model.dart';
import 'voice_shaper.dart';

/// Why a transcriber could not start.
enum TranscriberProblem {
  /// Microphone or speech permission was refused.
  permission,

  /// No on-device recogniser for this language on this phone.
  language,

  /// No speech service at all, or it failed to start.
  unavailable,
}

/// Speech → text. One implementation per tier of the voice pipeline (the
/// phone's on-device recogniser today; Moonshine or Gemma later), so the
/// recorder sheet never knows which one it is talking to.
abstract class Transcriber {
  /// Null when ready to [start]; otherwise why it cannot.
  Future<TranscriberProblem?> prepare();

  /// Starts listening. [onText] gets the whole transcript so far each time
  /// it changes (settled words plus the current guess). [onProblem] reports
  /// a failure that ends the session. [onLevel], when the recogniser reports
  /// it, gets the input loudness as 0..1 so the user can see they are heard.
  Future<void> start({
    required void Function(String text) onText,
    required void Function(TranscriberProblem problem) onProblem,
    void Function(double level)? onLevel,
  });

  /// Stops listening and returns the final transcript.
  Future<String> stop();

  /// Stops listening and throws the transcript away.
  Future<void> cancel();
}

/// Where voice memos are offered, and which transcriber they use. Both are
/// swappable for tests.
class VoiceMemo {
  VoiceMemo._();

  /// On-device recognition only: on the web (and desktop) speech goes to a
  /// cloud service, which would break the "everything stays on this
  /// device" promise.
  static bool Function() isSupported = _defaultSupported;

  static Transcriber Function() createTranscriber = SystemTranscriber.new;

  /// The model tier: a refined draft, or null when the optional model is
  /// not installed (or its answer was unusable). The rules draft stands.
  static Future<VoiceDraft?> Function(String transcript) refine =
      _defaultRefine;

  @visibleForTesting
  static void reset() {
    isSupported = _defaultSupported;
    createTranscriber = SystemTranscriber.new;
    refine = _defaultRefine;
  }

  static Future<VoiceDraft?> _defaultRefine(String transcript) async {
    final path = await VoiceModel.activePath();
    if (path == null) return null;
    return LlmShaper.shape(transcript, path);
  }

  static bool _defaultSupported() =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);
}

/// The phone's own recogniser, forced on-device. Android ends a recognition
/// session after each pause, so this restarts it until [stop] and keeps the
/// settled text across sessions — one continuous memo for the user.
class SystemTranscriber implements Transcriber {
  final SpeechToText _speech;

  SystemTranscriber([SpeechToText? speech]) : _speech = speech ?? SpeechToText();

  final _buffer = TranscriptBuffer();

  /// Bumped per recognition session; results from an ended session are
  /// ignored (its words were already settled).
  int _session = 0;
  bool _active = false;
  bool _restarting = false;
  void Function(String)? _onText;
  void Function(double)? _onLevel;
  void Function(TranscriberProblem)? _onProblem;
  Completer<void>? _finished;

  static const _channel = MethodChannel('com.z4yed.typed/widget');

  @override
  Future<TranscriberProblem?> prepare() async {
    try {
      // Android: refuse rather than let the plugin fall back to a cloud
      // recogniser (Android 12+ with an on-device model only).
      if (Platform.isAndroid &&
          await _channel.invokeMethod<bool>('onDeviceSpeechAvailable') !=
              true) {
        return TranscriberProblem.unavailable;
      }
      final ok = await _speech.initialize(
        onStatus: _onStatus,
        onError: _onError,
        finalTimeout: const Duration(milliseconds: 1500),
      );
      if (ok) return null;
      return await _speech.hasPermission
          ? TranscriberProblem.unavailable
          : TranscriberProblem.permission;
    } catch (_) {
      return TranscriberProblem.unavailable;
    }
  }

  @override
  Future<void> start({
    required void Function(String text) onText,
    required void Function(TranscriberProblem problem) onProblem,
    void Function(double level)? onLevel,
  }) async {
    _buffer.clear();
    _onText = onText;
    _onLevel = onLevel;
    _onProblem = onProblem;
    _active = true;
    await _listen();
  }

  Future<void> _listen() async {
    _finished = Completer<void>();
    final session = ++_session;
    try {
      await _speech.listen(
        onResult: (r) => _onResult(r, session),
        onSoundLevelChange: (db) => _onLevel?.call(normaliseLevel(db)),
        listenOptions: SpeechListenOptions(
          // Never fall back to a cloud recogniser.
          onDevice: true,
          partialResults: true,
          autoPunctuation: true,
          listenMode: ListenMode.dictation,
          cancelOnError: false,
          pauseFor: const Duration(seconds: 30),
          listenFor: const Duration(minutes: 10),
        ),
      );
    } catch (_) {
      _fail(TranscriberProblem.unavailable);
    }
  }

  void _onResult(SpeechRecognitionResult result, int session) {
    if (session != _session) return;
    if (result.finalResult) {
      _buffer.finalResult(result.recognizedWords);
      if (!(_finished?.isCompleted ?? true)) _finished!.complete();
    } else if (result.resultTypeValue == ResultType.intermediate) {
      // A phrase locked in mid-session (fast, unbroken speech).
      _buffer.intermediate(result.recognizedWords);
    } else {
      _buffer.partial(result.recognizedWords);
    }
    _onText?.call(_buffer.text);
  }

  void _onStatus(String status) {
    if (status != SpeechToText.doneStatus) return;
    // The session is over: whatever is still a guess is the best we have.
    _buffer.endSession();
    _session++;
    if (!(_finished?.isCompleted ?? true)) _finished!.complete();
    // The recogniser gave up after a pause; keep the memo going.
    if (_active && !_restarting) {
      _restarting = true;
      Future<void>.delayed(const Duration(milliseconds: 150), () async {
        _restarting = false;
        if (_active) await _listen();
      });
    }
  }

  void _onError(SpeechRecognitionError error) {
    switch (error.errorMsg) {
      // Silence or an unclear phrase: not a failure, the session restarts.
      case 'error_no_match':
      case 'error_speech_timeout':
        return;
      case 'error_language_unavailable':
      case 'error_language_not_supported':
        _fail(TranscriberProblem.language);
      case 'error_permission':
      case 'error_insufficient_permissions':
        _fail(TranscriberProblem.permission);
      default:
        if (error.permanent) _fail(TranscriberProblem.unavailable);
    }
  }

  void _fail(TranscriberProblem problem) {
    if (!_active) return;
    _active = false;
    _speech.cancel();
    _onProblem?.call(problem);
  }

  @override
  Future<String> stop() async {
    _active = false;
    try {
      await _speech.stop();
      // The last words arrive just after stop(); wait briefly for them.
      await (_finished?.future ?? Future<void>.value())
          .timeout(const Duration(seconds: 2), onTimeout: () {});
    } catch (_) {}
    // Whatever was still a guess is better kept than lost.
    _buffer.endSession();
    _session++;
    final text = _buffer.text;
    _buffer.clear();
    return text;
  }

  @override
  Future<void> cancel() async {
    _active = false;
    _session++;
    _buffer.clear();
    try {
      await _speech.cancel();
    } catch (_) {}
  }
}

/// Recogniser loudness (dB-ish: Android reports about -2..10, iOS about
/// -50..0) as 0..1 for a meter.
double normaliseLevel(double db) {
  final (lo, hi) = Platform.isIOS ? (-50.0, 0.0) : (-2.0, 10.0);
  return ((db - lo) / (hi - lo)).clamp(0.0, 1.0);
}

/// The memo's text across recognition sessions: settled words, the
/// segments locked in during the current session, and its live guess.
///
/// Android's on-device recogniser misbehaves in two ways this absorbs:
/// - It can end a session with an *empty* final result (or none) after
///   streaming good partials; the last guess is kept instead.
/// - When someone talks without pausing, it locks in each finished phrase
///   mid-session (an "intermediate" result) and then reports the next phrase
///   from scratch. Treating those as ordinary guesses let every new phrase
///   overwrite the previous one, so fast speech lost most of its words.
///   Locked phrases are kept as segments; a later result that repeats them
///   (some recognisers report the whole session cumulatively) is trimmed so
///   nothing is doubled.
class TranscriptBuffer {
  final _settled = <String>[];
  final _segments = <String>[];
  String _guess = '';

  String get text => [..._settled, ..._segments, _guess]
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .join(' ');

  /// A live guess for the current phrase; revised freely, but an empty one
  /// never erases what was heard.
  void partial(String words) {
    final fresh = _afterSegments(words);
    if (fresh.trim().isNotEmpty) _guess = fresh;
  }

  /// The recogniser locked in a phrase mid-session; the next partials start
  /// a new one.
  void intermediate(String words) {
    final fresh = _afterSegments(words);
    final phrase = fresh.trim().isNotEmpty ? fresh : _guess;
    if (phrase.trim().isNotEmpty) _segments.add(phrase);
    _guess = '';
  }

  /// The recogniser's final words for the session (preferred over the
  /// guess), or the guess when the final came back empty.
  void finalResult(String words) {
    var fresh = _afterSegments(words);
    // A final that only repeats the last locked phrase adds nothing.
    if (_segments.isNotEmpty && _norm(fresh) == _norm(_segments.last)) {
      fresh = '';
    }
    final heard = fresh.trim().isNotEmpty ? fresh : _guess;
    _settled.addAll(_segments);
    if (heard.trim().isNotEmpty) _settled.add(heard);
    _segments.clear();
    _guess = '';
  }

  /// The session ended without a final result: keep what it heard.
  void endSession() {
    _settled.addAll(_segments);
    if (_guess.trim().isNotEmpty) _settled.add(_guess);
    _segments.clear();
    _guess = '';
  }

  void clear() {
    _settled.clear();
    _segments.clear();
    _guess = '';
  }

  /// [words] minus this session's locked phrases when it starts with them
  /// (a cumulative report); otherwise [words] unchanged.
  String _afterSegments(String words) {
    if (_segments.isEmpty) return words;
    final locked = _norm(_segments.join(' ')).split(' ');
    final heard = words.trim().split(RegExp(r'\s+'));
    if (heard.length < locked.length) return words;
    for (var i = 0; i < locked.length; i++) {
      if (_norm(heard[i]) != locked[i]) return words;
    }
    return heard.sublist(locked.length).join(' ');
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r"[^\w\s']"), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
