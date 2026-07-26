import '../../domain/voice_connection.dart';

/// Remembers who is sitting in which voice channel of a guild.
///
/// Discord announces a voice channel's occupants once, inside the `GUILD_CREATE`
/// that lands during bootstrap, and never repeats them: after that only
/// arrivals, departures and mute changes arrive as `VOICE_STATE_UPDATE`. A
/// client that listens to the live dispatch alone therefore walks into an empty
/// room and only ever sees people who joined *after* it did. Retaining every
/// state seen since connect is what lets a join replay the room it is entering.
///
/// The roster is deliberately not filtered to the channel being joined. Which
/// channel that is only becomes known when the user presses join, and by then
/// the bulk dispatch that carried the occupants is long gone.
final class DiscordVoiceStateRoster {
  final Map<String, Map<String, VoiceParticipantStateEvent>> _byGuild = {};

  /// Folds [data] into the roster, returning the states it produced.
  ///
  /// Only the sources whose guild attribution is established are read.
  /// `GUILD_CREATE` names its guild in `id` and its members' states omit
  /// `guild_id`, so the parent supplies it; the two `VOICE_STATE_UPDATE` forms
  /// carry their own. Guildless states — DM and group-DM calls — are dropped:
  /// they key on a channel rather than a guild and belong to the call surface.
  List<VoiceParticipantStateEvent> accept({
    required String eventName,
    required Map<String, Object?> data,
  }) => switch (eventName) {
    'VOICE_STATE_UPDATE' => _apply([data], null),
    'VOICE_STATE_UPDATE_BATCH' => _apply(_objects(data['voice_states']), null),
    'GUILD_CREATE' => _replaceGuild(data),
    // A replayed READY starts a new session's view of the world. Keeping the
    // old seats would replay occupants who may have left, and the following
    // GUILD_CREATE burst is what repopulates them.
    'READY' => _clearOnReady(),
    _ => const [],
  };

  /// Everyone currently known to be in [channelId].
  List<VoiceParticipantStateEvent> participantsIn({
    required String guildId,
    required String channelId,
  }) => (_byGuild[guildId]?.values ?? const <VoiceParticipantStateEvent>[])
      .where((state) => state.channelId == channelId)
      .toList(growable: false);

  void clearAll() => _byGuild.clear();

  List<VoiceParticipantStateEvent> _clearOnReady() {
    final departures = [
      for (final guild in _byGuild.values)
        for (final event in guild.values) event.asDeparture(),
    ];
    _byGuild.clear();
    return departures;
  }

  /// `GUILD_CREATE` is a whole snapshot, so it replaces rather than merges.
  ///
  /// It is also the only thing that reports a departure which happened while
  /// the socket was down: the `VOICE_STATE_UPDATE` announcing it was never
  /// delivered, so merging would keep that user seated forever.
  List<VoiceParticipantStateEvent> _replaceGuild(Map<String, Object?> guild) {
    final guildId = guild['id'];
    if (guildId is! String || guildId.isEmpty) return const [];
    final previous = _byGuild.remove(guildId) ?? const {};
    final applied = _apply(_objects(guild['voice_states']), guildId);
    // Dropping the old seats silently would leave anyone who left while the
    // socket was down sitting on the grid forever: the snapshot is the only
    // notice of their departure, so it has to be turned into one.
    final seated = {for (final event in applied) event.userId};
    final departures = [
      for (final entry in previous.entries)
        if (!seated.contains(entry.key)) entry.value.asDeparture(),
    ];
    return [...departures, ...applied];
  }

  /// Forgets a guild's seats, as a replayed `READY` requires.
  void clearGuild(String guildId) => _byGuild.remove(guildId);

  List<VoiceParticipantStateEvent> _apply(
    List<Map<String, Object?>> states,
    String? fallbackGuildId,
  ) {
    final applied = <VoiceParticipantStateEvent>[];
    for (final state in states) {
      final event = _read(state, fallbackGuildId);
      if (event == null) continue;
      // A null channel is a departure, not a seat: keeping the row would leave
      // a ghost in whichever channel the user was last seen in. A departure for
      // a guild we hold nothing for must also not create an empty bucket that
      // is never reclaimed.
      if (event.channelId == null) {
        final members = _byGuild[event.guildId];
        members?.remove(event.userId);
        if (members != null && members.isEmpty) _byGuild.remove(event.guildId);
      } else {
        _byGuild.putIfAbsent(event.guildId, () => {})[event.userId] = event;
      }
      applied.add(event);
    }
    return applied;
  }

  static VoiceParticipantStateEvent? _read(
    Map<String, Object?> state,
    String? fallbackGuildId,
  ) {
    final userId = state['user_id'];
    final guildId = state['guild_id'] ?? fallbackGuildId;
    if (userId is! String || guildId is! String || guildId.isEmpty) return null;
    final channelId = state['channel_id'];
    if (channelId != null && channelId is! String) return null;
    return VoiceParticipantStateEvent(
      userId: userId,
      guildId: guildId,
      channelId: channelId as String?,
      selfMuted: state['self_mute'] == true,
      selfDeafened: state['self_deaf'] == true,
      serverMuted: state['mute'] == true,
      serverDeafened: state['deaf'] == true,
      isStreaming: state['self_stream'] == true,
      isVideoEnabled: state['self_video'] == true,
    );
  }

  static List<Map<String, Object?>> _objects(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((item) => item.cast<String, Object?>())
            .toList(growable: false)
      : const [];
}
