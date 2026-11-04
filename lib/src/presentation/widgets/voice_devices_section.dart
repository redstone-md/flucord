import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/voice_activity_gate.dart';
import '../../application/voice_controller.dart';
import '../../domain/user_settings.dart';
import '../../domain/voice_media.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'flucord_button.dart';
import 'flucord_controls.dart';
import 'user_settings_controls.dart';
import 'voice_input_meter.dart';

/// Which microphone and which speakers voice uses.
///
/// This lives in settings rather than in the voice room: it is a property of
/// the machine, not of the channel on screen, and the room panel it replaces
/// took a fifth of the room's width away from the people in it — permanently,
/// to hold two dropdowns nobody touches twice a month.
class VoiceDevicesSection extends StatelessWidget {
  const VoiceDevicesSection({required this.controller, super.key});

  final VoiceController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Column(
      key: const ValueKey('voice-devices-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsSectionHeader(
          title: 'Devices',
          subtitle:
              'Devices are read from the machine, so they are the same '
              'whichever account is signed in.',
        ),
        const SizedBox(height: 12),
        _SideBySide(
          start: _DeviceSelect(
            key: const ValueKey('voice-settings-input'),
            label: 'Input device',
            devices: controller.inputDevices,
            selectedId: controller.selectedInputId,
            onChanged: controller.selectInput,
          ),
          end: _DeviceSelect(
            key: const ValueKey('voice-settings-output'),
            label: 'Output device',
            devices: controller.outputDevices,
            selectedId: controller.selectedOutputId,
            onChanged: controller.selectOutput,
          ),
        ),
        const SizedBox(height: 8),
        _SensitivityRow(controller: controller),
        _ReleaseDelayRow(controller: controller),
        if (controller.isMicrophoneEnhancementAvailable ||
            controller.isNoiseSuppressionAvailable ||
            controller.isApplicationAttenuationAvailable) ...[
          const SizedBox(height: 16),
          const SettingsSectionHeader(title: 'Voice processing'),
        ],
        if (controller.isMicrophoneEnhancementAvailable) ...[
          _VoiceToggleRow(
            switchKey: const ValueKey('voice-settings-echo-cancellation'),
            title: 'Echo cancellation',
            description:
                'Takes what the speakers are playing out of the microphone, '
                'so the room does not hear itself.',
            value: controller.echoCancellation,
            onChanged: (value) => unawaited(
              controller.setMicrophoneEnhancement(echoCancellation: value),
            ),
          ),
          _VoiceToggleRow(
            switchKey: const ValueKey('voice-settings-automatic-gain-control'),
            title: 'Automatic gain control',
            description:
                'Keeps the microphone at a steady level without touching its '
                'own volume knob.',
            value: controller.automaticGainControl,
            onChanged: (value) => unawaited(
              controller.setMicrophoneEnhancement(automaticGainControl: value),
            ),
          ),
        ],
        if (controller.isNoiseSuppressionAvailable)
          _VoiceToggleRow(
            switchKey: const ValueKey('voice-settings-noise-suppression'),
            title: 'Noise suppression',
            description:
                'Removes keyboards, fans and other voices from the microphone. '
                'Costs some CPU while in a call.',
            value: controller.noiseSuppression,
            onChanged: (value) =>
                unawaited(controller.setNoiseSuppression(value)),
          ),
        if (controller.isApplicationAttenuationAvailable) ...[
          _VoiceToggleRow(
            switchKey: const ValueKey('voice-settings-attenuation'),
            title: 'Attenuate other applications',
            description:
                'Turns the rest of the machine down while you speak, so the '
                'room stays audible over music and games.',
            value: controller.attenuateApplications,
            onChanged: (value) =>
                unawaited(controller.setAttenuateApplications(value)),
          ),
          if (controller.attenuateApplications)
            _LabelledSlider(
              sliderKey: const ValueKey('voice-settings-attenuation-level'),
              min: 0,
              max: 1,
              value: controller.attenuationLevel.clamp(0.0, 1.0),
              valueLabel: '${(controller.attenuationLevel * 100).round()}%',
              onChanged: (value) =>
                  unawaited(controller.setAttenuationLevel(value)),
            ),
        ],
        if (controller.deviceError case final error?) ...[
          const SizedBox(height: 14),
          Text(
            key: const ValueKey('voice-settings-error'),
            'Audio devices could not be opened: $error',
            style: FlucordTextRole.caption.style.copyWith(
              color: context.surfaces.errorText,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FlucordButton(
              key: const ValueKey('voice-settings-retry'),
              label: 'Try the devices again',
              onPressed: () => unawaited(controller.retryDevices()),
            ),
          ),
        ],
      ],
    ),
  );
}

/// Two controls on one line, 16 apart, stacked when the pane is narrow.
class _SideBySide extends StatelessWidget {
  const _SideBySide({required this.start, required this.end});

  final Widget start;
  final Widget end;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        constraints.maxWidth < SettingRow.stackedWidth
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [start, const SizedBox(height: 12), end],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: start),
              const SizedBox(width: 16),
              Expanded(child: end),
            ],
          ),
  );
}

/// A setting row with a toggle. Every voice setting is one Flucord applies,
/// so none carries a support note.
class _VoiceToggleRow extends StatelessWidget {
  const _VoiceToggleRow({
    required this.switchKey,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final Key switchKey;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SettingRow(
    title: title,
    description: description,
    support: UserSettingSupport.applied,
    child: SettingSwitch(key: switchKey, value: value, onChanged: onChanged),
  );
}

/// A slider with its value written at its end.
class _LabelledSlider extends StatelessWidget {
  const _LabelledSlider({
    required this.sliderKey,
    required this.min,
    required this.max,
    required this.value,
    required this.valueLabel,
    required this.onChanged,
  });

  final Key sliderKey;
  final double min;
  final double max;
  final double value;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Slider(
          key: sliderKey,
          min: min,
          max: max,
          value: value,
          onChanged: onChanged,
        ),
      ),
      SizedBox(
        width: 52,
        child: Text(
          valueLabel,
          textAlign: TextAlign.end,
          style: FlucordTextRole.caption.style.copyWith(
            color: context.surfaces.muted,
          ),
        ),
      ),
    ],
  );
}

class _DeviceSelect extends StatelessWidget {
  const _DeviceSelect({
    required this.label,
    required this.devices,
    required this.selectedId,
    required this.onChanged,
    super.key,
  });

  final String label;
  final List<VoiceDevice> devices;
  final String? selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => FlucordSelect<String>(
    label: label,
    items: [for (final device in devices) (device.id, device.label)],
    value: selectedId,
    hintText: devices.isEmpty ? 'No devices found' : 'Choose a device',
    // Disabled rather than an empty menu that opens onto nothing.
    onChanged: devices.isEmpty ? null : onChanged,
  );
}

/// The input sensitivity: automatic, or a level chosen by hand.
///
/// Discord offers the same pair, and the automatic one is what makes a
/// gate fit a room nobody measured: the floor is learned from whatever is
/// there, and the manual one is for the microphone that never fits. The
/// live meter under it is what makes a level chosen by hand mean something:
/// the mark sits on the bar the voice moves.
class _SensitivityRow extends StatelessWidget {
  const _SensitivityRow({required this.controller});

  final VoiceController controller;

  /// The meter's whole range, in dB relative to full scale: the range the
  /// gate holds a threshold to.
  static const double _min = VoiceActivityGate.lowestThreshold;
  static const double _max = VoiceActivityGate.highestThreshold;

  @override
  Widget build(BuildContext context) {
    final sensitivity = controller.inputSensitivity;
    final automatic = sensitivity == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _VoiceToggleRow(
          switchKey: const ValueKey('voice-settings-manual-sensitivity'),
          title: 'Manual input sensitivity',
          description: automatic
              ? 'Flucord learns how loud the room is and opens the microphone '
                    'when you speak above it.'
              : 'The microphone opens when your voice passes the mark.',
          value: !automatic,
          onChanged: (value) => unawaited(
            controller.setInputSensitivity(value ? (_min + _max) / 2 : null),
          ),
        ),
        VoiceInputMeter(
          key: const ValueKey('voice-settings-input-sensitivity'),
          source: controller,
          min: _min,
          max: _max,
          threshold: sensitivity,
          onThresholdChanged: (value) =>
              unawaited(controller.setInputSensitivity(value)),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// The push-to-talk release delay, in the steps Discord's own settings
/// offer. Zero ends speech with the key, which is what a toggle user has.
class _ReleaseDelayRow extends StatelessWidget {
  const _ReleaseDelayRow({required this.controller});

  final VoiceController controller;

  static const List<int> _steps = [
    0,
    20,
    50,
    100,
    150,
    200,
    250,
    300,
    400,
    500,
    1000,
  ];

  @override
  Widget build(BuildContext context) {
    final held = controller.pushToTalkReleaseDelayMs;
    final step = _steps.contains(held)
        ? held
        : _steps.reduce((a, b) => (a - held).abs() < (b - held).abs() ? a : b);
    return SettingRow(
      title: 'Push-to-talk release delay',
      description:
          'Keeps the microphone live for this long after the key is '
          'released, so the ends of words survive.',
      support: UserSettingSupport.applied,
      child: FlucordSegmented<int>(
        key: const ValueKey('voice-settings-release-delay'),
        keyPrefix: 'voice-settings-release-delay',
        options: [
          for (final step in _steps)
            FlucordSegment(step, step == 0 ? 'Off' : '$step ms'),
        ],
        selected: step,
        onSelected: (value) =>
            unawaited(controller.setPushToTalkReleaseDelayMs(value)),
      ),
    );
  }
}
