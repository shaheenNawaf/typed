import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

/// Runs one completion of the on-device model on a background isolate:
/// load → generate → free. Returns the text, or "ERR:…".
Future<String> runLlm(String modelPath, String prompt, String grammar) =>
    Isolate.run(() => _runNative(modelPath, prompt, grammar));

// ── native ────────────────────────────────────────────────────────────────

typedef _RunC = Pointer<Utf8> Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Int32, Int32, Int32);
typedef _RunDart = Pointer<Utf8> Function(
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int, int, int);
typedef _FreeC = Void Function(Pointer<Utf8>);
typedef _FreeDart = void Function(Pointer<Utf8>);

/// Runs on a background isolate: one load → generate → free.
String _runNative(String modelPath, String prompt, String grammar) {
  final lib = DynamicLibrary.open('libtyped_llm.so');
  final run = lib.lookupFunction<_RunC, _RunDart>('typed_llm_run');
  final free = lib.lookupFunction<_FreeC, _FreeDart>('typed_llm_free');
  final m = modelPath.toNativeUtf8();
  final p = prompt.toNativeUtf8();
  final g = grammar.toNativeUtf8();
  try {
    // Big cores only: more threads than performance cores slows llama.cpp.
    final threads = (Platform.numberOfProcessors / 2).clamp(2, 4).toInt();
    // 20 s: past that the rules draft is the answer.
    final out = run(m, p, g, 400, threads, 20000);
    final text = out.toDartString();
    free(out);
    return text;
  } finally {
    malloc.free(m);
    malloc.free(p);
    malloc.free(g);
  }
}
