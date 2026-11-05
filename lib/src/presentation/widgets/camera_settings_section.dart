import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/self_video_controller.dart';
import 'flucord_controls.dart';
import 'user_settings_controls.dart';

/// Which camera a call's video uses, chosen beside the audio devices since
/// it is a property of the machine too.
class CameraSettingsSection extends StatelessWidget {
  const CameraSettingsSection({required this.controller, super.key});

  final SelfVideoController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final cameras = controller.cameras;
      return Column(
        key: const ValueKey('camera-settings-section'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SettingsSectionHeader(title: 'Video'),
          const SizedBox(height: 12),
          FlucordSelect<int>(
            key: const ValueKey('camera-settings-camera'),
            label: 'Camera',
            items: [for (final (index, name) in cameras.indexed) (index, name)],
            value: cameras.isEmpty ? null : controller.selectedCamera,
            hintText: cameras.isEmpty ? 'No cameras found' : 'Choose a camera',
            onChanged: cameras.isEmpty || controller.isBusy
                ? null
                : (index) => unawaited(controller.selectCamera(index)),
          ),
        ],
      );
    },
  );
}
