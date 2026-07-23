import '../../domain/voice_connection.dart';

final class DiscordVoiceSessionAssembler {
  final Map<String, _PendingVoiceSession> _pending = {};

  VoiceServerCredentials? accept({
    required String eventName,
    required Map<String, Object?> data,
    required String currentUserId,
  }) {
    final guildId = data['guild_id'] as String?;
    if (guildId == null || guildId.isEmpty) return null;
    final pending = _pending.putIfAbsent(
      guildId,
      () => _PendingVoiceSession(guildId),
    );

    switch (eventName) {
      case 'VOICE_STATE_UPDATE':
        if (data['user_id'] != currentUserId) return null;
        final channelId = data['channel_id'] as String?;
        final sessionId = data['session_id'] as String?;
        if (channelId == null || sessionId == null || sessionId.isEmpty) {
          _pending.remove(guildId);
          return null;
        }
        pending
          ..channelId = channelId
          ..userId = currentUserId
          ..sessionId = sessionId;
      case 'VOICE_SERVER_UPDATE':
        final token = data['token'] as String?;
        final endpoint = data['endpoint'] as String?;
        if (token == null ||
            token.isEmpty ||
            endpoint == null ||
            endpoint.isEmpty) {
          _pending.remove(guildId);
          return null;
        }
        pending
          ..token = token
          ..endpoint = endpoint;
      default:
        return null;
    }

    final credentials = pending.build();
    if (credentials != null) _pending.remove(guildId);
    return credentials;
  }

  void clear(String guildId) => _pending.remove(guildId);

  void clearAll() => _pending.clear();
}

final class _PendingVoiceSession {
  _PendingVoiceSession(this.guildId);

  final String guildId;
  String? channelId;
  String? userId;
  String? sessionId;
  String? token;
  String? endpoint;

  VoiceServerCredentials? build() {
    if (channelId == null ||
        userId == null ||
        sessionId == null ||
        token == null ||
        endpoint == null) {
      return null;
    }
    return VoiceServerCredentials(
      guildId: guildId,
      channelId: channelId!,
      userId: userId!,
      sessionId: sessionId!,
      token: token!,
      endpoint: endpoint!,
    );
  }
}
