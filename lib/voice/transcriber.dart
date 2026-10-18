import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

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
  /// a failure that ends the session.
  Future<void> start({
    required void Function(String text) onText,
    required void Function(TranscriberProblem problem) onProblem,
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

  @visibleForTesting
  static void reset() {
    isSupported = _defaultSupported;
    createTranscriber = SystemTranscriber.new;
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
  }) async {
    _buffer.clear();
    _onText = onText;
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

/// The memo's text across recognition sessions: settled words plus the
/// current session's best guess.
///
/// Android's on-device recogniser can end a session with an *empty* final
/// result, or with no final result at all, after streaming good partials.
/// Taking the final as gospel wiped the transcript the user had just watched
/// appear; here an empty final, or a session that simply ends, settles the
/// last guess instead.
class TranscriptBuffer {
  final _settled = <String>[];
  String _guess = '';

  String get text => [..._settled, _guess]
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .join(' ');

  /// A live guess for the current session; it may be revised freely, but an
  /// empty one never erases what was heard.
  void partial(String words) {
    if (words.trim().isNotEmpty) _guess = words;
  }

  /// The recogniser's final words for the session (preferred over the
  /// guess), or the guess when the final came back empty.
  void finalResult(String words) {
    final heard = words.trim().isNotEmpty ? words : _guess;
    if (heard.trim().isNotEmpty) _settled.add(heard);
    _guess = '';
  }

  /// The session ended without a final result: keep the guess.
  void endSession() {
    if (_guess.trim().isNotEmpty) _settled.add(_guess);
    _guess = '';
  }

  void clear() {
    _settled.clear();
    _guess = '';
  }
}
