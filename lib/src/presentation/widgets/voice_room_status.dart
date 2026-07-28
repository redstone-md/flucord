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
String? voiceRoomWarning(VoiceController controller) {
  if (controller.joinBlockedReason case final reason?) return reason;
  if (controller.connectionStatus == VoiceConnectionStatus.failure) {
    return 'Discord refused the voice connection. Leaving and rejoining the '
        'channel usually re-establishes it.';
  }
  if (controller.microphoneError != null) {
    return 'Your microphone could not be opened, so nobody can hear you. '
        'You can still hear everyone else.';
  }
  if (controller.error != null) return 'Media device unavailable.';
  return null;
}
