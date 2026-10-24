import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:typed/voice/voice_model.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('typed_model');
    await Directory('${dir.path}/models').create();
    VoiceModel.supportDir = () async => dir;
    VoiceModel.isSupported = () => true;
    SharedPreferences.setMockInitialValues({'voice_model_enabled_v1': true});
  });
  tearDown(() => dir.delete(recursive: true));

  File model(String name) => File('${dir.path}/models/$name');

  test(
    'a phone with the old model keeps using it and is offered the update',
    () async {
      await model('voice-shaper-v1.gguf').writeAsString('v1');
      expect(await VoiceModel.isInstalled(), isTrue);
      expect(await VoiceModel.hasUpdate(), isTrue);
      expect(await VoiceModel.activePath(), endsWith('voice-shaper-v1.gguf'));
    },
  );

  test('the current model wins and needs no update', () async {
    await model('voice-shaper-v1.gguf').writeAsString('v1');
    await model(VoiceModel.fileName).writeAsString('v2');
    expect(await VoiceModel.hasUpdate(), isFalse);
    expect(await VoiceModel.activePath(), endsWith(VoiceModel.fileName));
  });

  test('nothing installed: no update, nothing active', () async {
    expect(await VoiceModel.isInstalled(), isFalse);
    expect(await VoiceModel.hasUpdate(), isFalse);
    expect(await VoiceModel.activePath(), isNull);
  });

  test('remove deletes old and new models', () async {
    await model('voice-shaper-v1.gguf').writeAsString('v1');
    await model(VoiceModel.fileName).writeAsString('v2');
    await VoiceModel.remove();
    expect(await VoiceModel.isInstalled(), isFalse);
    expect(model('voice-shaper-v1.gguf').existsSync(), isFalse);
  });
}
