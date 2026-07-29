import 'dart:async';

import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/domain/voice_media.dart';
import 'package:flucord/src/presentation/widgets/voice_devices_section.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<VoiceController> pumpSection(
    WidgetTester tester, {
    required _FakeMedia media,
  }) async {
    final controller = VoiceController(media);
    addTearDown(controller.dispose);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(body: VoiceDevicesSection(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('picks the microphone and the speakers', (tester) async {
    final media = _FakeMedia();
    final controller = await pumpSection(tester, media: media);

    expect(find.byKey(const ValueKey('voice-devices-section')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('voice-settings-input')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Headset').last);
    await tester.pumpAndSettle();

    expect(controller.selectedInputId, 'mic-2');

    await tester.tap(find.byKey(const ValueKey('voice-settings-output')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monitor').last);
    await tester.pumpAndSettle();

    expect(controller.selectedOutputId, 'out-2');
  });

  testWidgets('a machine with no devices says so rather than offering a menu', (
    tester,
  ) async {
    final media = _FakeMedia()..devices = const [];
    await pumpSection(tester, media: media);

    expect(find.text('No devices found'), findsNWidgets(2));
    // Disabled rather than an empty menu that opens onto nothing.
    final input = tester.widget<DropdownButtonFormField<String>>(
      find.descendant(
        of: find.byKey(const ValueKey('voice-settings-input')),
        matching: find.byType(DropdownButtonFormField<String>),
      ),
    );
    expect(input.onChanged, isNull);
  });

  testWidgets('devices that would not open can be tried again', (tester) async {
    final media = _FakeMedia()..failNext = true;
    final controller = await pumpSection(tester, media: media);

    expect(find.byKey(const ValueKey('voice-settings-error')), findsOneWidget);

    media.failNext = false;
    await tester.tap(find.byKey(const ValueKey('voice-settings-retry')));
    await tester.pumpAndSettle();

    expect(controller.deviceError, isNull);
    expect(find.byKey(const ValueKey('voice-settings-error')), findsNothing);
  });
}

final class _FakeMedia implements VoiceMediaService {
  bool failNext = false;
  List<VoiceDevice> devices = const [
    VoiceDevice(id: 'mic-1', label: 'Webcam', kind: VoiceDeviceKind.audioInput),
    VoiceDevice(id: 'mic-2', label: 'Headset', kind: VoiceDeviceKind.audioInput),
    VoiceDevice(
      id: 'out-1',
      label: 'Speakers',
      kind: VoiceDeviceKind.audioOutput,
    ),
    VoiceDevice(
      id: 'out-2',
      label: 'Monitor',
      kind: VoiceDeviceKind.audioOutput,
    ),
  ];

  @override
  Future<void> initialize() async {
    if (failNext) throw StateError('no audio devices');
  }

  @override
  Future<List<VoiceDevice>> enumerateDevices() async => devices;

  @override
  Object? get previewRenderer => null;

  @override
  Stream<VoicePcmChunk> get microphonePcm => const Stream.empty();

  @override
  Stream<void> get screenShareEnded => const Stream.empty();

  @override
  Future<void> startMicrophone(String? deviceId) async {}

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {}

  @override
  Future<void> selectAudioOutput(String deviceId) async {}

  @override
  Future<List<VoiceCaptureSource>> enumerateCaptureSources() async => const [];

  @override
  Future<void> startScreenShare(String? sourceId) async {}

  @override
  Future<void> stopScreenShare() async {}

  @override
  Future<void> stopMicrophone() async {}

  @override
  Future<void> dispose() async {}
}
