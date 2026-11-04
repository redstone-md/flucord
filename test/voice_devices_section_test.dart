import 'dart:async';

import 'package:flucord/src/application/voice_controller.dart';
import 'package:flucord/src/domain/voice_media.dart';
import 'package:flucord/src/domain/voice_processing.dart';
import 'package:flucord/src/presentation/widgets/flucord_controls.dart';
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
        // Settings scrolls its page, as here.
        home: Scaffold(
          body: SingleChildScrollView(
            child: VoiceDevicesSection(controller: controller),
          ),
        ),
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

  testWidgets('the two device selects sit side by side', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpSection(tester, media: _FakeMedia());

    final input = tester.getRect(
      find.byKey(const ValueKey('voice-settings-input')),
    );
    final output = tester.getRect(
      find.byKey(const ValueKey('voice-settings-output')),
    );
    expect(output.top, input.top);
    expect(output.left, greaterThan(input.right));
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
        // Settings scrolls its page, as here.
        home: Scaffold(
          body: SingleChildScrollView(
            child: VoiceDevicesSection(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(_toggle(key));
    await tester.pumpAndSettle();

    expect(controller.noiseSuppression, isTrue);
    expect(
      repository.saved,
      const VoiceProcessingSettings(noiseSuppression: true),
    );
    expect(tester.widget<FlucordToggle>(_toggle(key)).value, isTrue);
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
        // Settings scrolls its page, as here.
        home: Scaffold(
          body: SingleChildScrollView(
            child: VoiceDevicesSection(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The switch is offered only where the machine can attenuate at all.
    expect(find.byKey(switchKey), findsOneWidget);
    expect(find.byKey(levelKey), findsNothing);

    await tester.tap(_toggle(switchKey));
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
    await tester.tap(_toggle(switchKey));
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

  testWidgets('input sensitivity is a mark on the live input meter', (
    tester,
  ) async {
    const switchKey = ValueKey('voice-settings-manual-sensitivity');
    const meterKey = ValueKey('voice-settings-input-sensitivity');
    const markKey = ValueKey('voice-input-meter-mark');

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
        // Settings scrolls its page, as here.
        home: Scaffold(
          body: SingleChildScrollView(
            child: VoiceDevicesSection(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The automatic gate is the default: the meter shows the level, with no
    // mark until one is asked for.
    expect(find.byKey(meterKey), findsOneWidget);
    expect(find.byKey(markKey), findsNothing);

    await tester.tap(_toggle(switchKey));
    await tester.pumpAndSettle();
    expect(
      find.text('The microphone opens when your voice passes the mark.'),
      findsOneWidget,
    );
    // The mark starts at the midpoint of the gate's range, drawn where that
    // level is on the meter's -80 to 0 dB scale.
    final meter = tester.getRect(find.byKey(meterKey));
    expect(
      tester.getCenter(find.byKey(markKey)).dx,
      closeTo(meter.left + meter.width * 32.5 / 80, 0.01),
    );
    expect(controller.inputSensitivity, -47.5);

    await tester.drag(find.byKey(markKey), Offset(meter.width / 16, 0));
    await tester.pumpAndSettle();
    // A sixteenth of the 80 dB scale.
    expect(controller.inputSensitivity, closeTo(-42.5, 0.01));
    expect(
      repository.saved!.inputSensitivity,
      controller.inputSensitivity,
      reason: 'the manual level is kept for the next session',
    );

    // Back to automatic: the mark goes away and nothing is saved.
    await tester.tap(_toggle(switchKey));
    await tester.pumpAndSettle();
    expect(find.byKey(markKey), findsNothing);
    expect(find.byKey(meterKey), findsOneWidget);
    expect(controller.inputSensitivity, isNull);
    expect(repository.saved!.inputSensitivity, isNull);
  });

  testWidgets('the meter holds the microphone only while the section is open', (
    tester,
  ) async {
    final media = _FakeMedia();
    await pumpSection(tester, media: media);
    expect(media.microphoneOpen, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(media.microphoneOpen, isFalse);
  });

  testWidgets('the release delay offers the steps a key needs', (tester) async {
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
        // Settings scrolls its page, as here.
        home: Scaffold(
          body: SingleChildScrollView(
            child: VoiceDevicesSection(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Every step is on screen at once, as a segmented group.
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('1000 ms'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('voice-settings-release-delay-100')),
    );
    await tester.pumpAndSettle();

    expect(controller.pushToTalkReleaseDelayMs, 100);
    expect(repository.saved!.pushToTalkReleaseDelayMs, 100);
  });

  testWidgets('a saved delay between the steps shows as it is', (tester) async {
    final controller = VoiceController(
      _FakeMedia(),
      audioCodecFactory: FakeVoiceOpusCodecFactory(),
      processingRepository: MemoryVoiceProcessingRepository(
        const VoiceProcessingSettings(pushToTalkReleaseDelayMs: 120),
      ),
    );
    addTearDown(controller.dispose);
    await controller.loadProcessingSettings();
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: VoiceDevicesSection(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    bool selected(int ms) => tester
        .widget<FlucordTab>(
          find.byKey(ValueKey('voice-settings-release-delay-$ms')),
        )
        .selected;
    expect(controller.pushToTalkReleaseDelayMs, 120);
    expect(selected(120), isTrue);
    expect(selected(100), isFalse);
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
        // Settings scrolls its page, as here.
        home: Scaffold(
          body: SingleChildScrollView(
            child: VoiceDevicesSection(controller: controller),
          ),
        ),
      ),
    );
    await controller.loadProcessingSettings();
    await tester.pumpAndSettle();

    // The saved switches come back as they were left, and the tiles show
    // them.
    expect(find.byKey(echoKey), findsOneWidget);
    expect(find.byKey(gainKey), findsOneWidget);
    expect(
      tester.widget<FlucordToggle>(_toggle(echoKey)).value,
      isTrue,
      reason: 'on by default',
    );

    await tester.tap(_toggle(echoKey));
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

/// The on/off pill of the setting row keyed [key].
Finder _toggle(Key key) =>
    find.descendant(of: find.byKey(key), matching: find.byType(FlucordToggle));

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
  bool microphoneOpen = false;
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
  Future<void> startMicrophone(String? deviceId) async => microphoneOpen = true;

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {}

  @override
  Future<void> selectAudioOutput(String deviceId) async {}

  @override
  Future<void> stopMicrophone() async => microphoneOpen = false;

  @override
  Future<void> dispose() async {}
}
