import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/voice_controller.dart';
import '../../domain/voice_media.dart';
import '../../theme/flucord_theme.dart';

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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Devices are read from the machine, so they are the same whichever '
          'account is signed in.',
          style: TextStyle(color: context.surfaces.muted, fontSize: 12),
        ),
        const SizedBox(height: 16),
        _DeviceSelect(
          key: const ValueKey('voice-settings-input'),
          label: 'Input device',
          devices: controller.inputDevices,
          selectedId: controller.selectedInputId,
          onChanged: controller.selectInput,
        ),
        const SizedBox(height: 14),
        _DeviceSelect(
          key: const ValueKey('voice-settings-output'),
          label: 'Output device',
          devices: controller.outputDevices,
          selectedId: controller.selectedOutputId,
          onChanged: controller.selectOutput,
        ),
        const SizedBox(height: 14),
        _SensitivityRow(controller: controller),
        const SizedBox(height: 14),
        _ReleaseDelayRow(controller: controller),
        if (controller.isMicrophoneEnhancementAvailable) ...[
          const SizedBox(height: 14),
          SwitchListTile(
            key: const ValueKey('voice-settings-echo-cancellation'),
            contentPadding: EdgeInsets.zero,
            value: controller.echoCancellation,
            onChanged: (value) => unawaited(
              controller.setMicrophoneEnhancement(echoCancellation: value),
            ),
            title: const Text(
              'Echo cancellation',
              style: TextStyle(fontSize: 13),
            ),
            subtitle: Text(
              'Takes what the speakers are playing out of the microphone, '
              'so the room does not hear itself.',
              style: TextStyle(fontSize: 11, color: context.surfaces.muted),
            ),
          ),
          const SizedBox(height: 14),
          SwitchListTile(
            key: const ValueKey('voice-settings-automatic-gain-control'),
            contentPadding: EdgeInsets.zero,
            value: controller.automaticGainControl,
            onChanged: (value) => unawaited(
              controller.setMicrophoneEnhancement(automaticGainControl: value),
            ),
            title: const Text(
              'Automatic gain control',
              style: TextStyle(fontSize: 13),
            ),
            subtitle: Text(
              'Keeps the microphone at a steady level without touching its '
              'own volume knob.',
              style: TextStyle(fontSize: 11, color: context.surfaces.muted),
            ),
          ),
        ],
        if (controller.isNoiseSuppressionAvailable) ...[
          const SizedBox(height: 14),
          SwitchListTile(
            key: const ValueKey('voice-settings-noise-suppression'),
            contentPadding: EdgeInsets.zero,
            value: controller.noiseSuppression,
            onChanged: (value) =>
                unawaited(controller.setNoiseSuppression(value)),
            title: const Text(
              'Noise suppression',
              style: TextStyle(fontSize: 13),
            ),
            subtitle: Text(
              'Removes keyboards, fans and other voices from the microphone '
              'with DeepFilterNet. Costs some CPU while in a call.',
              style: TextStyle(fontSize: 11, color: context.surfaces.muted),
            ),
          ),
        ],
        if (controller.isApplicationAttenuationAvailable) ...[
          const SizedBox(height: 14),
          SwitchListTile(
            key: const ValueKey('voice-settings-attenuation'),
            contentPadding: EdgeInsets.zero,
            value: controller.attenuateApplications,
            onChanged: (value) =>
                unawaited(controller.setAttenuateApplications(value)),
            title: const Text(
              'Attenuate other applications',
              style: TextStyle(fontSize: 13),
            ),
            subtitle: Text(
              'Turns the rest of the machine down while you speak, so the '
              'room stays audible over music and games.',
              style: TextStyle(fontSize: 11, color: context.surfaces.muted),
            ),
          ),
          if (controller.attenuateApplications) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    key: const ValueKey('voice-settings-attenuation-level'),
                    min: 0,
                    max: 1,
                    value: controller.attenuationLevel.clamp(0.0, 1.0),
                    onChanged: (value) =>
                        unawaited(controller.setAttenuationLevel(value)),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${(controller.attenuationLevel * 100).round()}%',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.surfaces.muted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
        if (controller.deviceError case final error?) ...[
          const SizedBox(height: 14),
          Text(
            key: const ValueKey('voice-settings-error'),
            'Audio devices could not be opened: $error',
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('voice-settings-retry'),
              onPressed: () => unawaited(controller.retryDevices()),
              child: const Text('Try the devices again'),
            ),
          ),
        ],
      ],
    ),
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
  Widget build(BuildContext context) {
    // A dropdown whose value is not among its items throws, and the list is
    // empty until the devices have been enumerated.
    final value = devices.any((device) => device.id == selectedId)
        ? selectedId
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: context.surfaces.muted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true),
          items: [
            for (final device in devices)
              DropdownMenuItem(
                value: device.id,
                child: Text(device.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: devices.isEmpty
              ? null
              : (id) {
                  if (id != null) onChanged(id);
                },
          hint: Text(
            devices.isEmpty ? 'No devices found' : 'Choose a device',
            style: TextStyle(color: context.surfaces.muted, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// The input sensitivity: automatic, or a level chosen by hand.
///
/// Discord offers the same pair, and the automatic one is what makes a
/// gate fit a room nobody measured: the floor is learned from whatever is
/// there, and the manual one is for the microphone that never fits.
class _SensitivityRow extends StatelessWidget {
  const _SensitivityRow({required this.controller});

  final VoiceController controller;

  /// The slider's whole range, in dB relative to full scale. The gate
  /// clamps to its own range, so the two ends here are the same ones it
  /// uses.
  static const double _min = -65;
  static const double _max = -30;

  @override
  Widget build(BuildContext context) {
    final sensitivity = controller.inputSensitivity;
    final automatic = sensitivity == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: const ValueKey('voice-settings-manual-sensitivity'),
          contentPadding: EdgeInsets.zero,
          value: !automatic,
          onChanged: (value) => unawaited(
            controller.setInputSensitivity(value ? (_min + _max) / 2 : null),
          ),
          title: const Text(
            'Manual input sensitivity',
            style: TextStyle(fontSize: 13),
          ),
          subtitle: Text(
            automatic
                ? 'The gate learns the room and opens a margin above its '
                      'noise floor.'
                : 'The gate opens above the level chosen here, whatever the '
                      'room sounds like.',
            style: TextStyle(fontSize: 11, color: context.surfaces.muted),
          ),
        ),
        if (!automatic) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Slider(
                  key: const ValueKey('voice-settings-input-sensitivity'),
                  min: _min,
                  max: _max,
                  value: sensitivity.clamp(_min, _max),
                  onChanged: (value) =>
                      unawaited(controller.setInputSensitivity(value)),
                ),
              ),
              SizedBox(
                width: 52,
                child: Text(
                  '${sensitivity.toStringAsFixed(0)} dB',
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 11, color: context.surfaces.muted),
                ),
              ),
            ],
          ),
        ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Push-to-talk release delay',
                style: TextStyle(fontSize: 13),
              ),
            ),
            DropdownButton<int>(
              key: const ValueKey('voice-settings-release-delay'),
              value: _steps.contains(held)
                  ? held
                  : _steps.reduce(
                      (a, b) => (a - held).abs() < (b - held).abs() ? a : b,
                    ),
              items: [
                for (final step in _steps)
                  DropdownMenuItem(
                    value: step,
                    child: Text(step == 0 ? 'Off' : '$step ms'),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  unawaited(controller.setPushToTalkReleaseDelayMs(value));
                }
              },
            ),
          ],
        ),
        Text(
          'Keeps the microphone live for this long after the key is '
          'released, so the ends of words survive.',
          style: TextStyle(fontSize: 11, color: context.surfaces.muted),
        ),
      ],
    );
  }
}
