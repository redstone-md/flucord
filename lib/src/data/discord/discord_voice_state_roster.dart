import '../../domain/voice_connection.dart';
import 'discord_voice_state_reader.dart';

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

  /// Everyone seated, grouped by the channel they are in.
  ///
  /// The sidebar needs this for channels nobody has joined from here, so it is
  /// read off the whole tracked set rather than off a connection.
  Map<String, List<VoiceParticipantStateEvent>> get seatedByChannel {
    final byChannel = <String, List<VoiceParticipantStateEvent>>{};
    for (final guild in _byGuild.values) {
      for (final state in guild.values) {
        final channelId = state.channelId;
        if (channelId == null) continue;
        byChannel.putIfAbsent(channelId, () => []).add(state);
      }
    }
    return Map<String, List<VoiceParticipantStateEvent>>.unmodifiable({
      for (final entry in byChannel.entries)
        entry.key: List<VoiceParticipantStateEvent>.unmodifiable(entry.value),
    });
  }

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
      final event = DiscordVoiceStateReader.read(
        state,
        fallbackGuildId: fallbackGuildId,
      );
      // A guildless state is a DM or group-DM call seat. It keys on a channel,
      // not a guild, so it belongs to the call roster and is dropped here
      // rather than filed under a guild that does not exist.
      if (event == null || event.guildId == null) continue;
      // A null channel is a departure, not a seat: keeping the row would leave
      // a ghost in whichever channel the user was last seen in. A departure for
      // a guild we hold nothing for must also not create an empty bucket that
      // is never reclaimed.
      final guildId = event.guildId!;
      if (event.channelId == null) {
        final members = _byGuild[guildId];
        members?.remove(event.userId);
        if (members != null && members.isEmpty) _byGuild.remove(guildId);
      } else {
        _byGuild.putIfAbsent(guildId, () => {})[event.userId] = event;
      }
      applied.add(event);
    }
    return applied;
  }

  static List<Map<String, Object?>> _objects(Object? value) =>
      DiscordVoiceStateReader.objects(value);
}
