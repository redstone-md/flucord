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
