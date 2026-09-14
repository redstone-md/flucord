import 'dart:async';

import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/domain/voice_media.dart';
import 'package:flucord/src/domain/voice_processing.dart';
import 'package:flucord/src/presentation/widgets/voice_devices_section.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_voice_audio.dart';

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

  testWidgets('offers the noise suppression switch only with a suppressor', (
    tester,
  ) async {
    const key = ValueKey('voice-settings-noise-suppression');
    await pumpSection(tester, media: _FakeMedia());
    expect(find.byKey(key), findsNothing);

    final repository = MemoryVoiceProcessingRepository();
    final controller = VoiceController(
      _FakeMedia(),
      audioCodecFactory: FakeVoiceOpusCodecFactory(),
      noiseSuppressorFactory: () async => FakeNoiseSuppressor(),
      processingRepository: repository,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(body: VoiceDevicesSection(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();

    expect(controller.noiseSuppression, isTrue);
    expect(
      repository.saved,
      const VoiceProcessingSettings(noiseSuppression: true),
    );
    expect(tester.widget<SwitchListTile>(find.byKey(key)).value, isTrue);
  });

  testWidgets('attenuation offers a switch and a level', (tester) async {
    const switchKey = ValueKey('voice-settings-attenuation');
    const levelKey = ValueKey('voice-settings-attenuation-level');

    final attenuation = _RecordingAttenuation();
    final repository = MemoryVoiceProcessingRepository();
    final controller = VoiceController(
      _FakeMedia(),
      audioCodecFactory: FakeVoiceOpusCodecFactory(),
      processingRepository: repository,
      applicationAttenuation: attenuation,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(body: VoiceDevicesSection(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    // The switch is offered only where the machine can attenuate at all.
    expect(find.byKey(switchKey), findsOneWidget);
    expect(find.byKey(levelKey), findsNothing);

    await tester.tap(find.byKey(switchKey));
    await tester.pumpAndSettle();
    expect(controller.attenuateApplications, isTrue);
    expect(repository.saved!.listening.attenuateApplications, isTrue);

    // Switched on, the level appears beside it.
    expect(find.byKey(levelKey), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);

    await tester.drag(find.byKey(levelKey), const Offset(40, 0));
    await tester.pumpAndSettle();
    // The drag moved the level: wherever the pointer landed is what the
    // switch now holds, and the label follows it.
    final level = controller.attenuationLevel;
    expect(level, isNot(equals(0.8)));
    expect(level, allOf(greaterThan(0), lessThan(1)));
    expect(find.text('${(level * 100).round()}%'), findsOneWidget);

    // Switched off, the level goes away and the machine is released.
    await tester.tap(find.byKey(switchKey));
    await tester.pumpAndSettle();
    expect(find.byKey(levelKey), findsNothing);
    expect(attenuation.calls, contains('release'));
  });

  testWidgets('an unsupported machine offers no attenuation switch', (
    tester,
  ) async {
    await pumpSection(tester, media: _FakeMedia());
    expect(
      find.byKey(const ValueKey('voice-settings-attenuation')),
      findsNothing,
    );
  });

  testWidgets('input sensitivity offers a switch and a slider', (tester) async {
    const switchKey = ValueKey('voice-settings-manual-sensitivity');
    const sliderKey = ValueKey('voice-settings-input-sensitivity');

    final repository = MemoryVoiceProcessingRepository();
    final controller = VoiceController(
      _FakeMedia(),
      audioCodecFactory: FakeVoiceOpusCodecFactory(),
      processingRepository: repository,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(body: VoiceDevicesSection(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    // The automatic gate is the default: no slider until it is asked for.
    expect(find.byKey(switchKey), findsOneWidget);
    expect(find.byKey(sliderKey), findsNothing);

    await tester.tap(find.byKey(switchKey));
    await tester.pumpAndSettle();
    expect(find.byKey(sliderKey), findsOneWidget);
    // The slider starts at the automatic threshold's midpoint.
    final value = tester.widget<Slider>(find.byKey(sliderKey)).value;
    expect(value, inExclusiveRange(-65, -30));
    expect(controller.inputSensitivity, value);
    expect(
      repository.saved!.inputSensitivity,
      value,
      reason: 'the manual level is kept for the next session',
    );

    // Back to automatic: the slider goes away and nothing is saved.
    await tester.tap(find.byKey(switchKey));
    await tester.pumpAndSettle();
    expect(find.byKey(sliderKey), findsNothing);
    expect(controller.inputSensitivity, isNull);
    expect(repository.saved!.inputSensitivity, isNull);
  });

  testWidgets('the release delay offers the steps a key needs', (tester) async {
    const key = ValueKey('voice-settings-release-delay');

    final repository = MemoryVoiceProcessingRepository();
    final controller = VoiceController(
      _FakeMedia(),
      audioCodecFactory: FakeVoiceOpusCodecFactory(),
      processingRepository: repository,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(body: VoiceDevicesSection(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
    await tester.tap(find.text('100 ms').last);
    await tester.pumpAndSettle();

    expect(controller.pushToTalkReleaseDelayMs, 100);
    expect(repository.saved!.pushToTalkReleaseDelayMs, 100);
  });

  testWidgets('echo and gain are offered only with the machine stages', (
    tester,
  ) async {
    const echoKey = ValueKey('voice-settings-echo-cancellation');
    const gainKey = ValueKey('voice-settings-automatic-gain-control');

    // No enhancer: the switches are not offered at all.
    await pumpSection(tester, media: _FakeMedia());
    expect(find.byKey(echoKey), findsNothing);
    expect(find.byKey(gainKey), findsNothing);

    final repository = MemoryVoiceProcessingRepository();
    final controller = VoiceController(
      _FakeMedia(),
      audioCodecFactory: FakeVoiceOpusCodecFactory(),
      microphoneEnhancerFactory:
          ({required echoCancellation, required automaticGainControl}) async =>
              FakeMicrophoneEnhancer(),
      processingRepository: repository,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(body: VoiceDevicesSection(controller: controller)),
      ),
    );
    await controller.loadProcessingSettings();
    await tester.pumpAndSettle();

    // The saved switches come back as they were left, and the tiles show
    // them.
    expect(find.byKey(echoKey), findsOneWidget);
    expect(find.byKey(gainKey), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byKey(echoKey)).value,
      isTrue,
      reason: 'on by default',
    );

    await tester.tap(find.byKey(echoKey));
    await tester.pumpAndSettle();
    expect(controller.echoCancellation, isFalse);
    expect(repository.saved!.echoCancellation, isFalse);
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

final class _RecordingAttenuation implements ApplicationAttenuation {
  final List<String> calls = [];

  @override
  bool get isSupported => true;

  @override
  Future<void> attenuate(double level) async =>
      calls.add('attenuate:${level.toStringAsFixed(2)}');

  @override
  Future<void> release() async => calls.add('release');

  @override
  Future<void> dispose() async => calls.add('dispose');
}

final class _FakeMedia implements VoiceMediaService {
  bool failNext = false;
  List<VoiceDevice> devices = const [
    VoiceDevice(id: 'mic-1', label: 'Webcam', kind: VoiceDeviceKind.audioInput),
    VoiceDevice(
      id: 'mic-2',
      label: 'Headset',
      kind: VoiceDeviceKind.audioInput,
    ),
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
  Stream<VoicePcmChunk> get microphonePcm => const Stream.empty();

  @override
  Future<void> startMicrophone(String? deviceId) async {}

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {}

  @override
  Future<void> selectAudioOutput(String deviceId) async {}

  @override
  Future<void> stopMicrophone() async {}

  @override
  Future<void> dispose() async {}
}
