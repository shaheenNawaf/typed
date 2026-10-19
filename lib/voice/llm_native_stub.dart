/// Web (and any platform without dart:ffi): there is no on-device model.
Future<String> runLlm(String modelPath, String prompt, String grammar) async =>
    'ERR:unsupported';
