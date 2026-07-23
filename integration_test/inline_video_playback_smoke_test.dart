import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets('decodes a local MP4 through the Windows native texture', (
    tester,
  ) async {
    final fixture = File('test/fixtures/inline_video_smoke.mp4').absolute;
    expect(await fixture.exists(), isTrue);

    final player = Player();
    addTearDown(player.dispose);
    final controller = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        width: 320,
        height: 180,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 180,
            child: Video(controller: controller, controls: NoVideoControls),
          ),
        ),
      ),
    );
    await tester.pump();

    final durationReady = player.stream.duration.firstWhere(
      (value) => value > const Duration(seconds: 1),
    );
    await player.open(Media(fixture.uri.toString()));
    await controller.waitUntilFirstFrameRendered.timeout(
      const Duration(seconds: 15),
    );
    final duration = await durationReady.timeout(const Duration(seconds: 5));

    expect(controller.rect.value?.width, 320);
    expect(controller.rect.value?.height, 180);
    expect(duration, greaterThan(const Duration(seconds: 1)));
    await player.pause();
    await player.seek(const Duration(seconds: 1));
    final muted = player.stream.volume.firstWhere((value) => value <= 0);
    await player.setVolume(0);
    expect(await muted.timeout(const Duration(seconds: 5)), 0);
    expect(tester.takeException(), isNull);
  });
}
