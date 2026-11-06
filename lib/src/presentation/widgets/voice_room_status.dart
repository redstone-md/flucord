import 'package:flutter/material.dart';

import '../../application/voice_controller.dart';
import '../../domain/voice_connection.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'chat_header.dart';

String voiceRoomStatusLabel(VoiceController controller) {
  if (!controller.isConnected) return 'Disconnected';
  if (!controller.hasDiscordSignaling) return 'Local media ready';
  return switch (controller.connectionStatus) {
    VoiceConnectionStatus.disconnected => 'Disconnected',
    VoiceConnectionStatus.joining => 'Joining voice channel...',
    VoiceConnectionStatus.connecting ||
    VoiceConnectionStatus.discovering ||
    VoiceConnectionStatus.negotiating => 'Connecting...',
    VoiceConnectionStatus.ready when controller.isDeafened =>
      'Voice connected, deafened',
    VoiceConnectionStatus.ready when controller.isMuted =>
      'Voice connected, muted',
    VoiceConnectionStatus.ready => 'Voice connected',
    VoiceConnectionStatus.reconnecting => 'Reconnecting...',
    VoiceConnectionStatus.failure when _needsEncryption(controller) =>
      'Encrypted voice unavailable',
    VoiceConnectionStatus.failure => 'Could not connect',
  };
}

/// Whether Discord refused the room for end-to-end encryption this build
/// cannot offer. Not a fault: joining again is refused the same way.
bool _needsEncryption(VoiceController controller) =>
    controller.error is VoiceEncryptionRequiredException;

/// The Room header's words: "Connected" and the ping once the connection is
/// up, else the same words as everywhere else. Muted and deafened are left
/// to the control row, which shows them on its buttons.
String voiceRoomHeaderLabel(VoiceController controller) {
  if (controller.connectionStatus != VoiceConnectionStatus.ready ||
      !controller.isConnected) {
    return voiceRoomStatusLabel(controller);
  }
  return switch (controller.roundTrip) {
    final roundTrip? => 'Connected · ${roundTrip.inMilliseconds} ms',
    null => 'Connected',
  };
}

/// The voice channel Room's connection state, for the channel header.
/// Draws nothing while this account is not in [channelId]: there is no
/// connection of this channel's to report.
class VoiceRoomStatusLine extends StatelessWidget {
  const VoiceRoomStatusLine({
    required this.controller,
    required this.channelId,
    super.key,
  });

  final VoiceController controller;
  final String channelId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (controller.connectedChannelId != channelId) {
        return const SizedBox.shrink();
      }
      return Row(
        key: const ValueKey('voice-room-status'),
        children: [
          const ChatHeaderDivider(),
          const SizedBox(width: 12),
          Flexible(
            child: VoiceSignalLine(
              isUp: controller.isTransportReady,
              text: TextSpan(text: voiceRoomHeaderLabel(controller)),
            ),
          ),
        ],
      );
    },
  );
}

/// A Room's connection state on one line: the signal mark, green while the
/// transport is up, then [text]. The voice channel header and the DM call
/// band both draw it, so the two read alike.
class VoiceSignalLine extends StatelessWidget {
  const VoiceSignalLine({required this.isUp, required this.text, super.key});

  final bool isUp;
  final InlineSpan text;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        FlucordIcon(
          FlucordIcons.signal,
          size: 14,
          color: isUp ? surfaces.success : surfaces.muted,
        ),
        Flexible(
          child: Text.rich(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FlucordTextRole.caption.style.copyWith(
              color: surfaces.muted,
            ),
          ),
        ),
      ],
    );
  }
}

/// The one thing most worth saying about a room that is not working, or null.
///
/// Ordered by what blocks the most: a session that cannot reach voice at all,
/// then a connection that failed, then a microphone that would not open, which
/// still leaves a usable room, so it is reported last.
///
/// Each answer says which of the three it is. The old wording called every
/// one of them "Media device unavailable", which sent somebody to check a
/// headset that was working while the real problem was the connection.
String? voiceRoomWarning(VoiceController controller) {
  if (controller.joinBlockedReason case final reason?) return reason;
  if (controller.connectionStatus == VoiceConnectionStatus.failure) {
    if (_needsEncryption(controller)) {
      return 'End-to-end encrypted voice is not available in this build.';
    }
    return 'Discord voice did not answer, or refused the connection.';
  }
  if (controller.deviceError case final error?) {
    // The reason is included rather than summarised: "in use by another
    // application" and "no device at all" are different problems with
    // different fixes, and only the platform knows which one happened.
    return 'Audio devices could not be opened: ${_describe(error)}';
  }
  if (controller.microphoneError case final error?) {
    return 'Your microphone could not be opened, so nobody can hear you. You '
        'can still hear everyone else. (${_describe(error)})';
  }
  if (controller.error case final error?) {
    return 'Voice ran into a problem: ${_describe(error)}';
  }
  return null;
}

/// Whether the room should offer to join again after its connection failed.
bool voiceRoomOffersConnectionRetry(VoiceController controller) =>
    controller.isConnected &&
    controller.hasDiscordSignaling &&
    controller.connectionStatus == VoiceConnectionStatus.failure &&
    !_needsEncryption(controller);

/// Whether the room should offer to open the audio devices again.
bool voiceRoomOffersDeviceRetry(VoiceController controller) =>
    controller.deviceError != null || controller.microphoneError != null;

/// One line of whatever the platform threw.
///
/// Trimmed to a single line because these arrive as multi-line platform
/// exceptions, and a paragraph of stack in a status strip pushes the room off
/// the screen.
String _describe(Object error) {
  final text = error.toString().trim();
  final firstLine = text.split(RegExp(r'[\r\n]')).first.trim();
  const limit = 160;
  if (firstLine.length <= limit) return firstLine;
  return '${firstLine.substring(0, limit)}…';
}
