import '../../domain/voice_connection.dart';

/// The single reader for every shape a voice state arrives in.
///
/// Discord delivers the same object from six places — `VOICE_STATE_UPDATE`, its
/// batch form, `GUILD_CREATE`, `READY_SUPPLEMENTAL`, `CALL_CREATE` and
/// `PASSIVE_UPDATE_V2` — and R08 warns that reading them in more than one place
/// is how a roster diverges from what the server thinks it sent. Guild seats
/// and call seats are held in different stores because they are keyed
/// differently, but both parse through here so a mute flag can never mean one
/// thing in a guild and another in a call.
abstract final class DiscordVoiceStateReader {
  /// Reads one voice state.
  ///
  /// [fallbackGuildId] supplies the guild for sources that name it on the
  /// parent instead of the state (`GUILD_CREATE`), and [fallbackChannelId] does
  /// the same for `CALL_CREATE`, whose states belong to the call's channel.
  /// Returns null when the state cannot be attributed to a user, which is the
  /// only field with no defensible default.
  static VoiceParticipantStateEvent? read(
    Map<String, Object?> state, {
    String? fallbackGuildId,
    String? fallbackChannelId,
  }) {
    final userId = state['user_id'];
    if (userId is! String || userId.isEmpty) return null;
    final guildId = state['guild_id'] ?? fallbackGuildId;
    if (guildId != null && (guildId is! String || guildId.isEmpty)) return null;
    // `channel_id: null` is a departure and has to survive the read; an absent
    // key on a CALL_CREATE state means "the call's own channel".
    final rawChannelId = state.containsKey('channel_id')
        ? state['channel_id']
        : fallbackChannelId;
    if (rawChannelId != null && rawChannelId is! String) return null;
    return VoiceParticipantStateEvent(
      userId: userId,
      guildId: guildId as String?,
      channelId: rawChannelId as String?,
      selfMuted: state['self_mute'] == true,
      selfDeafened: state['self_deaf'] == true,
      serverMuted: state['mute'] == true,
      serverDeafened: state['deaf'] == true,
      isStreaming: state['self_stream'] == true,
      isVideoEnabled: state['self_video'] == true,
    );
  }

  /// The most voice states a single frame is allowed to seat.
  ///
  /// The count comes straight off the wire and drives allocation, so it is
  /// bounded rather than trusted. Discord's own hard cap on a voice channel is
  /// far below this, and a group DM tops out at ten.
  static const maxStatesPerFrame = 4096;

  /// Reads a `voice_states`-shaped list, dropping anything that is not an
  /// object and refusing to grow past [maxStatesPerFrame].
  static List<Map<String, Object?>> objects(Object? value) {
    if (value is! List) return const [];
    final objects = <Map<String, Object?>>[];
    for (final item in value) {
      if (objects.length >= maxStatesPerFrame) break;
      if (item is Map) objects.add(item.cast<String, Object?>());
    }
    return objects;
  }
}
