import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/soloud_voice_playback_service.dart';
import 'package:flucord/src/domain/voice_audio.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('initializes native playback and accepts live PCM', (
    tester,
  ) async {
    final playback = SoLoudVoicePlaybackService();
    addTearDown(playback.dispose);

    await playback.initialize();
    final devices = await playback.enumerateOutputDevices();
    expect(devices, isNotEmpty);
    await playback.selectOutput(devices.first.id);
    await playback.setEnabled(true);
    for (var index = 0; index < 4; index++) {
      playback.addPcmFrame(
        VoiceRemotePcmFrame(userId: 'smoke', samples: Int16List(1920)),
      );
    }
    await tester.pump(const Duration(milliseconds: 120));
    await playback.setEnabled(false);
  });
}
