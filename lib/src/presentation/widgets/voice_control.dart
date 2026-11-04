import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../application/go_live_controller.dart';
import '../../application/self_video_controller.dart';
import '../../application/voice_controller.dart';
import '../../theme/flucord_icons.dart';

/// What one voice button says and does.
///
/// The Room's toolbar, the voice panel and the user panel draw these controls
/// in their own styles. This keeps their words, icons and actions the same.
final class VoiceControl {
  /// Mute and deafen rest outside a room: the controller keeps no flags
  /// there, so a press would do nothing. A room being joined still takes them.
  VoiceControl.mute(VoiceController voice)
    : tooltip = voice.isMuted ? 'Unmute' : 'Mute',
      icon = voice.isMuted ? FlucordIcons.micOff : FlucordIcons.mic,
      danger = voice.isMuted,
      active = false,
      onPressed = _inRoom(voice) ? (() => unawaited(voice.toggleMute())) : null;

  VoiceControl.deafen(VoiceController voice)
    : tooltip = voice.isDeafened ? 'Undeafen' : 'Deafen',
      icon = voice.isDeafened
          ? FlucordIcons.headphonesOff
          : FlucordIcons.headphones,
      danger = voice.isDeafened,
      active = false,
      onPressed = _inRoom(voice)
          ? (() => unawaited(voice.toggleDeafen()))
          : null;

  /// A machine with no camera keeps the button, disabled. Hiding it would
  /// leave somebody who unplugged a webcam wondering where the control went.
  VoiceControl.camera(SelfVideoController camera)
    : tooltip = camera.cameras.isEmpty
          ? 'No camera attached'
          : camera.isOn
          ? 'Turn camera off'
          : 'Turn camera on',
      icon = camera.isOn ? FlucordIcons.camera : FlucordIcons.cameraOff,
      danger = false,
      active = camera.isOn,
      onPressed = camera.cameras.isEmpty || camera.isBusy
          ? null
          : (() => unawaited(camera.toggle()));

  /// Go Live, started or stopped by [toggle]. Null [goLive] is a session
  /// with no Go Live at all, which keeps the button and says why it rests.
  /// A build without the encoder can still stop a share, never start one.
  VoiceControl.screenShare(
    GoLiveController? goLive, {
    required void Function(GoLiveController goLive) toggle,
  }) : onPressed = switch (goLive) {
         final GoLiveController live
             when live.isSupported && (live.isSharing || live.canEncode) =>
           () => toggle(live),
         _ => null,
       },
       tooltip = switch (goLive) {
         null || GoLiveController(isSupported: false) =>
           'Screen sharing needs a Discord session',
         GoLiveController(isSharing: true) => 'Stop streaming',
         _ => 'Share your screen',
       },
       icon = goLive?.isSharing ?? false
           ? FlucordIcons.screenShareOff
           : FlucordIcons.screenShare,
       danger = false,
       active = goLive?.isSharing ?? false;

  /// Discord Activities, which Flucord cannot launch yet. The button holds
  /// their place in the panel so the layout does not move when they arrive.
  const VoiceControl.activities()
    : tooltip = 'Activities are not supported yet',
      icon = FlucordIcons.activities,
      danger = false,
      active = false,
      onPressed = null;

  static bool _inRoom(VoiceController voice) =>
      voice.isConnected || voice.isBusy;

  final String tooltip;
  final FlucordIconData icon;

  /// Something the person should notice: they cannot be heard, or cannot hear.
  final bool danger;

  /// The control is on, and that is not a problem.
  final bool active;

  /// Null while the control cannot be used.
  final VoidCallback? onPressed;
}
