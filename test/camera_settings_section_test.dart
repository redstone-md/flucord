import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/self_video_controller.dart';
import 'package:flucord/src/domain/video_capture_hub.dart';
import 'package:flucord/src/presentation/widgets/camera_settings_section.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

import 'support/fake_video_encoder.dart';

void main() {
  testWidgets('picks the camera the next call uses', (tester) async {
    final camera = _camera(const ['Front', 'Back']);
    addTearDown(camera.dispose);
    await _pump(tester, camera);

    expect(find.text('Front'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('camera-settings-camera')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back').last);
    await tester.pumpAndSettle();

    expect(camera.selectedCamera, 1);
  });

  testWidgets('a machine with no camera says so', (tester) async {
    final camera = _camera(const []);
    addTearDown(camera.dispose);
    await _pump(tester, camera);

    expect(find.text('No cameras found'), findsOneWidget);
  });
}

SelfVideoController _camera(List<String> names) => SelfVideoController(
  capture: VideoCaptureHub(encoder: FakeVideoEncoder(cameras: names)),
  transportProvider: () => null,
  sinkProvider: () => null,
  isVoiceReady: () => false,
  announceSelfVideo: ({required bool enabled}) async => true,
);

Future<void> _pump(WidgetTester tester, SelfVideoController camera) =>
    tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(body: CameraSettingsSection(controller: camera)),
      ),
    );
