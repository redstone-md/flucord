import 'dart:async';

import 'package:flutter/material.dart';

import '../data/video/clip_recorder.dart';
import '../data/video/screenshot_service.dart';
import '../domain/keybind.dart';
import 'self_video_controller.dart';
import 'streamer_mode_controller.dart';
import 'voice_controller.dart';
import 'voice_overlay_controller.dart';
import 'workspace_controller.dart';

/// Carries out one bound action.
///
/// The keybind controller hands each press here rather than to the widget:
/// a binding fires wherever the focus is, and its targets are controllers,
/// not screens. Push to talk and push to mute are opposites of each other
/// rather than two separate mechanisms: both set the mute flag, one on
/// press and one on release.
final class KeybindActions {
  KeybindActions({
    required VoiceController voice,
    required SelfVideoController selfVideo,
    required WorkspaceController workspace,
    required StreamerModeController streamerMode,
    required VoiceOverlayController overlay,
    required ScreenshotService screenshot,
    required ClipRecorder clip,
    required GlobalKey<ScaffoldMessengerState> messenger,
  }) : _voice = voice,
       _selfVideo = selfVideo,
       _workspace = workspace,
       _streamerMode = streamerMode,
       _overlay = overlay,
       _screenshot = screenshot,
       _clip = clip,
       _messenger = messenger;

  final VoiceController _voice;
  final SelfVideoController _selfVideo;
  final WorkspaceController _workspace;
  final StreamerModeController _streamerMode;
  final VoiceOverlayController _overlay;
  final ScreenshotService _screenshot;
  final ClipRecorder _clip;

  /// Held so a keybind can say where a screenshot went: the action runs
  /// from the keyboard rather than from a widget, and has no context of
  /// its own to find a messenger through.
  final GlobalKey<ScaffoldMessengerState> _messenger;

  void call(KeybindAction action, {required bool pressed}) {
    switch (action) {
      case KeybindAction.pushToTalk:
        unawaited(_voice.setMuted(muted: !pressed));
      case KeybindAction.pushToMute:
        unawaited(_voice.setMuted(muted: pressed));
      case KeybindAction.toggleMute:
        if (pressed) unawaited(_voice.toggleMute());
      case KeybindAction.toggleDeafen:
        if (pressed) unawaited(_voice.toggleDeafen());
      case KeybindAction.toggleCamera:
        if (pressed) unawaited(_selfVideo.toggle());
      case KeybindAction.disconnectFromVoiceChannel:
        if (pressed) unawaited(_voice.disconnect());
      case KeybindAction.toggleVoiceChannelChat:
        if (pressed) _workspace.toggleVoiceChannelChat();
      case KeybindAction.toggleStreamerMode:
        if (pressed) unawaited(_streamerMode.toggle());
      case KeybindAction.saveScreenshot:
        if (pressed) unawaited(_saveScreenshot());
      case KeybindAction.saveClip:
        if (pressed) unawaited(_saveClip());
      case KeybindAction.toggleOverlay:
        if (pressed) unawaited(_overlay.toggle());
    }
  }

  /// Writes the last few seconds of what was being encoded.
  ///
  /// Only whatever the encoder is already producing: a clip is the recording
  /// that was running, and nothing starts one on the way to saving it.
  Future<void> _saveClip() async {
    final result = await _clip.save();
    _messenger.currentState?.showSnackBar(
      SnackBar(
        key: const ValueKey('clip-result'),
        content: Text(
          result.isSaved
              ? 'Clip saved to ${result.path}'
              : switch (result.failure) {
                  ClipFailure.empty =>
                    'Nothing to clip: start a stream or a camera first.',
                  ClipFailure.write => 'The clip could not be written.',
                  _ => 'This build cannot save clips.',
                },
        ),
      ),
    );
  }

  /// Writes a screenshot and says where it went.
  ///
  /// Reported through the same messenger the rest of the client speaks with:
  /// a screenshot saved with no acknowledgement is one nobody can find, and
  /// one that failed silently is worse.
  Future<void> _saveScreenshot() async {
    final result = await _screenshot.save();
    final messenger = _messenger.currentState;
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        key: const ValueKey('screenshot-result'),
        content: Text(
          result.isSaved
              ? 'Screenshot saved to ${result.path}'
              : result.failure == ScreenshotFailure.write
              ? 'The screenshot could not be written to disk.'
              : 'This build cannot capture the screen.',
        ),
      ),
    );
  }
}
