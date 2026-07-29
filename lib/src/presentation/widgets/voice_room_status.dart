import '../../application/voice_controller.dart';
import '../../domain/voice_connection.dart';

String voiceRoomStatusLabel(VoiceController controller) {
  if (!controller.isConnected) return 'Disconnected';
  if (!controller.hasDiscordSignaling) return 'Local media ready';
  return switch (controller.connectionStatus) {
    VoiceConnectionStatus.disconnected => 'Voice transport disconnected',
    VoiceConnectionStatus.joining => 'Joining voice channel...',
    VoiceConnectionStatus.connecting => 'Connecting to voice server...',
    VoiceConnectionStatus.discovering => 'Discovering UDP route...',
    VoiceConnectionStatus.negotiating => 'Negotiating DAVE encryption...',
    VoiceConnectionStatus.ready when controller.isAudioPlaybackActive =>
      controller.isMuted
          ? 'Encrypted voice connected - muted'
          : 'Encrypted voice connected',
    VoiceConnectionStatus.ready when controller.isAudioUplinkActive =>
      'Encrypted voice uplink active',
    VoiceConnectionStatus.ready => 'Encrypted transport ready',
    VoiceConnectionStatus.reconnecting => 'Reconnecting voice transport...',
    VoiceConnectionStatus.failure => 'Voice transport failed',
  };
}

/// The one thing most worth saying about a room that is not working, or null.
///
/// Ordered by what blocks the most: a session that cannot reach voice at all,
/// then a transport that failed, then a microphone that would not open — which
/// still leaves a usable room, so it is reported last.
///
/// Each answer says which of the three it is. The old wording called every
/// one of them "Media device unavailable", which sent somebody to check a
/// headset that was working while the real problem was the connection.
String? voiceRoomWarning(VoiceController controller) {
  if (controller.joinBlockedReason case final reason?) return reason;
  if (controller.connectionStatus == VoiceConnectionStatus.failure) {
    return 'Discord refused the voice connection. Leaving and rejoining the '
        'channel usually re-establishes it.';
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
