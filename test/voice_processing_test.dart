import 'dart:io';

import 'package:flucord/src/data/file_voice_processing_repository.dart';
import 'package:flucord/src/domain/voice_processing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('noise suppression is off until asked for, and round trips', () {
    expect(const VoiceProcessingSettings().noiseSuppression, isFalse);
    const on = VoiceProcessingSettings(noiseSuppression: true);

    expect(VoiceProcessingSettings.fromJson(on.toJson()), on);
    expect(
      VoiceProcessingSettings.fromJson({'noise_suppression': 'yes'}),
      const VoiceProcessingSettings(),
    );
    expect(
      VoiceProcessingSettings.fromJson('junk'),
      const VoiceProcessingSettings(),
    );
  });

  test('the file survives a restart and shrugs off a broken one', () async {
    final directory = await Directory.systemTemp.createTemp('flucord-voice');
    addTearDown(() => directory.delete(recursive: true));
    final repository = FileVoiceProcessingRepository(
      directory: () async => directory,
    );

    expect(await repository.load(), const VoiceProcessingSettings());
    await repository.save(
      const VoiceProcessingSettings(noiseSuppression: true),
    );
    expect(
      await repository.load(),
      const VoiceProcessingSettings(noiseSuppression: true),
    );

    await File(
      '${directory.path}/${FileVoiceProcessingRepository.fileName}',
    ).writeAsString('{not json');
    expect(await repository.load(), const VoiceProcessingSettings());
  });

  test('the last save wins, even when an earlier one is slower', () async {
    final directory = await Directory.systemTemp.createTemp('flucord-voice');
    addTearDown(() => directory.delete(recursive: true));
    // The first save finds its directory late, as a busy disk would.
    var calls = 0;
    final repository = FileVoiceProcessingRepository(
      directory: () async {
        if (calls++ == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        return directory;
      },
    );

    await Future.wait([
      repository.save(const VoiceProcessingSettings(inputSensitivity: -40)),
      repository.save(const VoiceProcessingSettings(inputSensitivity: -55)),
    ]);

    expect((await repository.load()).inputSensitivity, -55);
  });
}
