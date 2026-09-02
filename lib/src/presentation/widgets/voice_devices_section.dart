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
