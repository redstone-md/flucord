import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../application/go_live_controller.dart';
import '../../application/self_video_controller.dart';
import '../../application/voice_controller.dart';
import '../../domain/voice_connection.dart';
import '../../theme/flucord_icons.dart';

/// What one voice button says and does.
///
/// The Room's toolbar, the voice panel and the user panel draw these controls
/// in their own styles. This keeps their words, icons and actions the same.
final class VoiceControl {
  /// Mute and deafen rest outside a room: the controller keeps no flags
  /// there, so a press would do nothing. A room being joined still takes them.
  /// A moderator's mute or deafen gets its own mark, [byServer], and says so,
  /// since only the moderator can lift it. Any other reason the account
  /// cannot speak is marked the same way. The button still toggles the
  /// account's own mute underneath, as in Discord.
  VoiceControl.mute(VoiceController voice)
    : tooltip = _withServer(
        _heldMute(voice.speechBlock),
        voice.isMuted ? 'Unmute' : 'Mute',
      ),
      icon = voice.isMuted || voice.speechBlock != null
          ? FlucordIcons.micOff
          : FlucordIcons.mic,
      danger = voice.isMuted || voice.speechBlock != null,
      byServer = voice.speechBlock != null,
      active = false,
      onPressed = _inRoom(voice) ? (() => unawaited(voice.toggleMute())) : null;

  VoiceControl.deafen(VoiceController voice)
    : tooltip = _withServer(
        voice.isServerDeafened ? 'Server deafened' : null,
        voice.isDeafened ? 'Undeafen' : 'Deafen',
      ),
      icon = voice.isDeafened || voice.isServerDeafened
          ? FlucordIcons.headphonesOff
          : FlucordIcons.headphones,
      danger = voice.isDeafened || voice.isServerDeafened,
      byServer = voice.isServerDeafened,
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
      byServer = false,
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
         GoLiveController(canEncode: false) =>
           'Screen sharing is not available in this build',
         _ => 'Share your screen',
       },
       icon = goLive?.isSharing ?? false
           ? FlucordIcons.screenShareOff
           : FlucordIcons.screenShare,
       danger = false,
       byServer = false,
       active = goLive?.isSharing ?? false;

  /// Discord Activities, which Flucord cannot launch yet. The button holds
  /// their place in the panel so the layout does not move when they arrive.
  const VoiceControl.activities()
    : tooltip = 'Activities are not supported yet',
      icon = FlucordIcons.activities,
      danger = false,
      byServer = false,
      active = false,
      onPressed = null;

  static bool _inRoom(VoiceController voice) =>
      voice.isConnected || voice.isBusy;

  /// What the tooltip says of [block], the reason the account cannot be
  /// heard whatever its own mute says.
  static String? _heldMute(SpeechBlock? block) => switch (block) {
    SpeechBlock.serverMuted => 'Server muted',
    SpeechBlock.noPermission =>
      'You do not have permission to speak in this channel',
    SpeechBlock.suppressed => 'You are suppressed in this channel',
    null => null,
  };

  static String _withServer(String? server, String action) =>
      server == null ? action : '$server · $action';

  final String tooltip;
  final FlucordIconData icon;

  /// Something the person should notice: they cannot be heard, or cannot hear.
  final bool danger;

  /// A moderator holds this state, which the person cannot lift. Drawn apart
  /// from [danger], as the room's marks draw a server mute.
  final bool byServer;

  /// The control is on, and that is not a problem.
  final bool active;

  /// Null while the control cannot be used.
  final VoidCallback? onPressed;
}
