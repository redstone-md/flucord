import '../../domain/voice_connection.dart';

/// Pairs the two dispatches that together are a voice connection's credentials.
///
/// R08: the self `VOICE_STATE_UPDATE` carries the session id and the
/// `VOICE_SERVER_UPDATE` carries the endpoint and token, in no guaranteed
/// order. They are matched on the session key rather than on the guild, because
/// a DM or group-DM call has no guild: its `VOICE_SERVER_UPDATE` arrives with
/// `guild_id: null` and `channel_id` set, and the pairing key is R08's
/// `guildId ?? channelId`.
final class DiscordVoiceSessionAssembler {
  final Map<VoiceSessionKey, _PendingVoiceSession> _pending = {};

  VoiceServerCredentials? accept({
    required String eventName,
    required Map<String, Object?> data,
    required String currentUserId,
  }) => switch (eventName) {
    'VOICE_STATE_UPDATE' => _acceptVoiceState(data, currentUserId),
    'VOICE_SERVER_UPDATE' => _acceptServerUpdate(data),
    _ => null,
  };

  void clear(VoiceSessionKey key) => _pending.remove(key);

  /// Restores the identity halves a re-issued server update needs.
  ///
  /// A consumed pairing leaves nothing behind, yet the ping that asks Discord
  /// to re-issue is answered with the server half alone: the state half is
  /// whatever the session already was, and Discord does not repeat it.
  /// Seeding the last known identity lets that lone frame complete; the token
  /// and the endpoint stay absent, so nothing stale can complete it.
  void remember({
    required VoiceSessionKey key,
    required String channelId,
    required String userId,
    required String sessionId,
  }) {
    _pending[key] = _PendingVoiceSession(key)
      ..channelId = channelId
      ..userId = userId
      ..sessionId = sessionId;
  }

  void clearAll() => _pending.clear();

  VoiceServerCredentials? _acceptVoiceState(
    Map<String, Object?> data,
    String currentUserId,
  ) {
    if (data['user_id'] != currentUserId) return null;
    final guildId = _nonEmpty(data['guild_id']);
    final channelId = _nonEmpty(data['channel_id']);
    final sessionId = _nonEmpty(data['session_id']);
    if (channelId == null || sessionId == null) {
      _forgetDeparture(guildId);
      return null;
    }
    final key = guildId == null
        ? VoiceSessionKey.privateCall(channelId)
        : VoiceSessionKey.guild(guildId);
    final pending = _pending.putIfAbsent(key, () => _PendingVoiceSession(key));
    pending
      ..channelId = channelId
      ..userId = currentUserId
      ..sessionId = sessionId;
    return _complete(key, pending);
  }

  VoiceServerCredentials? _acceptServerUpdate(Map<String, Object?> data) {
    final guildId = _nonEmpty(data['guild_id']);
    final channelId = _nonEmpty(data['channel_id']);
    // R08: guild voice names only the guild, a private call only the channel.
    // A frame that names neither cannot be attributed to a session at all.
    final key = guildId != null
        ? VoiceSessionKey.guild(guildId)
        : channelId != null
        ? VoiceSessionKey.privateCall(channelId)
        : null;
    if (key == null) return null;
    final token = _nonEmpty(data['token']);
    final endpoint = _nonEmpty(data['endpoint']);
    if (token == null || endpoint == null) {
      _pending.remove(key);
      return null;
    }
    final pending = _pending.putIfAbsent(key, () => _PendingVoiceSession(key));
    pending
      ..token = token
      ..endpoint = endpoint;
    // A private call's server update also names the channel, and it is the only
    // frame that does when the self voice state has not landed yet.
    pending.channelId ??= key.isPrivateCall ? key.callChannelId : channelId;
    return _complete(key, pending);
  }

  VoiceServerCredentials? _complete(
    VoiceSessionKey key,
    _PendingVoiceSession pending,
  ) {
    final credentials = pending.build();
    if (credentials != null) _pending.remove(key);
    return credentials;
  }

  /// A self voice state with no channel is a disconnect.
  ///
  /// Guild voice names the guild it left, so only that session is forgotten. A
  /// private-call disconnect names neither guild nor channel, and since Discord
  /// grants one voice connection at a time, forgetting every half-built call is
  /// the honest reading — it is strictly safer than leaving a stale token
  /// behind to be paired with the next call's session id.
  void _forgetDeparture(String? guildId) {
    if (guildId != null) {
      _pending.remove(VoiceSessionKey.guild(guildId));
      return;
    }
    _pending.removeWhere((key, _) => key.isPrivateCall);
  }

  static String? _nonEmpty(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}

final class _PendingVoiceSession {
  _PendingVoiceSession(this.key);

  final VoiceSessionKey key;
  String? channelId;
  String? userId;
  String? sessionId;
  String? token;
  String? endpoint;

  VoiceServerCredentials? build() {
    final channelId = this.channelId;
    final userId = this.userId;
    final sessionId = this.sessionId;
    final token = this.token;
    final endpoint = this.endpoint;
    if (channelId == null ||
        userId == null ||
        sessionId == null ||
        token == null ||
        endpoint == null) {
      return null;
    }
    return VoiceServerCredentials(
      guildId: key.guildId,
      channelId: channelId,
      userId: userId,
      sessionId: sessionId,
      token: token,
      endpoint: endpoint,
    );
  }
}
