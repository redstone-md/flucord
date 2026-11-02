import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/self_video_controller.dart';
import '../../application/voice_controller.dart';

/// What one voice button says and does.
///
/// The Room's toolbar and the connection bar draw the same three controls in
/// their own styles. This keeps their words, icons and actions the same.
final class VoiceControl {
  VoiceControl.mute(VoiceController voice)
    : tooltip = voice.isMuted ? 'Unmute' : 'Mute',
      icon = voice.isMuted ? Icons.mic_off : Icons.mic,
      danger = voice.isMuted,
      active = false,
      onPressed = (() => unawaited(voice.toggleMute()));

  VoiceControl.deafen(VoiceController voice)
    : tooltip = voice.isDeafened ? 'Undeafen' : 'Deafen',
      icon = voice.isDeafened ? Icons.headset_off : Icons.headset,
      danger = voice.isDeafened,
      active = false,
      onPressed = (() => unawaited(voice.toggleDeafen()));

  /// A machine with no camera keeps the button, disabled. Hiding it would
  /// leave somebody who unplugged a webcam wondering where the control went.
  VoiceControl.camera(SelfVideoController camera)
    : tooltip = camera.cameras.isEmpty
          ? 'No camera attached'
          : camera.isOn
          ? 'Turn camera off'
          : 'Turn camera on',
      icon = camera.isOn ? Icons.videocam : Icons.videocam_off_outlined,
      danger = false,
      active = camera.isOn,
      onPressed = camera.cameras.isEmpty || camera.isBusy
          ? null
          : (() => unawaited(camera.toggle()));

  final String tooltip;
  final IconData icon;

  /// Something the person should notice: they cannot be heard, or cannot hear.
  final bool danger;

  /// The control is on, and that is not a problem.
  final bool active;

  /// Null while the control cannot be used.
  final VoidCallback? onPressed;
}
