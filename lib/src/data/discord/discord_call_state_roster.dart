import '../../domain/voice_connection.dart';
import 'discord_voice_state_reader.dart';

/// Remembers who is sitting in which DM or group-DM call.
///
/// The guild roster cannot hold these: a call voice state carries no
/// `guild_id`, so it keys on the channel instead. Splitting the two stores also
/// splits their snapshot sources — a guild's occupants arrive on `GUILD_CREATE`
/// and a call's on `CALL_CREATE` — and each snapshot has to replace rather than
/// merge, so folding them together would have made one event clear the other's
/// seats.
///
/// A departure is the awkward case. Discord announces it as a voice state with
/// `channel_id: null` and, for a call, no `guild_id` either — the frame names
/// nobody's channel, so the row it retracts is only findable by remembering
/// where that user was last seen. The desktop renderer synthesises the same
/// `oldChannelId` from its own store for exactly this reason.
final class DiscordCallStateRoster {
  final Map<String, Map<String, VoiceParticipantStateEvent>> _byChannel = {};
  final Map<String, String> _channelByUser = {};

  /// Folds [data] into the roster, returning the seats and departures it
  /// produced paired with the call channel each belongs to.
  List<DiscordCallSeatChange> accept({
    required String eventName,
    required Map<String, Object?> data,
  }) => switch (eventName) {
    'VOICE_STATE_UPDATE' => _apply([data]),
    'VOICE_STATE_UPDATE_BATCH' => _apply(
      DiscordVoiceStateReader.objects(data['voice_states']),
    ),
    'CALL_CREATE' => _replaceCall(data),
    'CALL_DELETE' => _endCall(data['channel_id']),
    // A replayed READY starts a new session's view of the world, and the
    // CALL_CREATE that follows each re-subscription is what repopulates it.
    'READY' => _clearOnReady(),
    _ => const [],
  };

  /// Everyone currently known to be in [channelId]'s call.
  /// Everyone seated, grouped by call channel — the same shape guild voice
  /// reports, so the sidebar reads one map rather than two.
  Map<String, List<VoiceParticipantStateEvent>> get seatedByChannel =>
      Map<String, List<VoiceParticipantStateEvent>>.unmodifiable({
        for (final entry in _byChannel.entries)
          if (entry.value.isNotEmpty)
            entry.key: List<VoiceParticipantStateEvent>.unmodifiable(
              entry.value.values,
            ),
      });

  List<VoiceParticipantStateEvent> participantsIn(String channelId) =>
      (_byChannel[channelId]?.values ?? const <VoiceParticipantStateEvent>[])
          .toList(growable: false);

  void clearAll() {
    _byChannel.clear();
    _channelByUser.clear();
  }

  /// `CALL_CREATE` is a whole snapshot of the call, so it replaces rather than
  /// merges — and whoever it no longer seats has to be reported as gone, since
  /// the snapshot is the only notice of a departure the socket missed.
  List<DiscordCallSeatChange> _replaceCall(Map<String, Object?> data) {
    final channelId = data['channel_id'];
    if (channelId is! String || channelId.isEmpty) return const [];
    final previous = _byChannel.remove(channelId) ?? const {};
    for (final userId in previous.keys) {
      _channelByUser.remove(userId);
    }
    final applied = _apply(
      DiscordVoiceStateReader.objects(data['voice_states']),
      fallbackChannelId: channelId,
    );
    final seated = {for (final change in applied) change.state.userId};
    return [
      for (final entry in previous.entries)
        if (!seated.contains(entry.key))
          DiscordCallSeatChange(channelId, entry.value.asDeparture()),
      ...applied,
    ];
  }

  List<DiscordCallSeatChange> _endCall(Object? rawChannelId) {
    if (rawChannelId is! String) return const [];
    final seats = _byChannel.remove(rawChannelId);
    if (seats == null) return const [];
    for (final userId in seats.keys) {
      _channelByUser.remove(userId);
    }
    return [
      for (final seat in seats.values)
        DiscordCallSeatChange(rawChannelId, seat.asDeparture()),
    ];
  }

  List<DiscordCallSeatChange> _clearOnReady() {
    final departures = [
      for (final entry in _byChannel.entries)
        for (final seat in entry.value.values)
          DiscordCallSeatChange(entry.key, seat.asDeparture()),
    ];
    clearAll();
    return departures;
  }

  List<DiscordCallSeatChange> _apply(
    List<Map<String, Object?>> states, {
    String? fallbackChannelId,
  }) {
    final applied = <DiscordCallSeatChange>[];
    for (final state in states) {
      final event = DiscordVoiceStateReader.read(
        state,
        fallbackChannelId: fallbackChannelId,
      );
      // A state that names a guild is guild voice and belongs to the guild
      // roster, even when it rides in on the same dispatch.
      if (event == null || event.guildId != null) continue;
      final channelId = event.channelId;
      if (channelId == null) {
        final previous = _channelByUser.remove(event.userId);
        if (previous == null) continue;
        final seats = _byChannel[previous];
        seats?.remove(event.userId);
        if (seats != null && seats.isEmpty) _byChannel.remove(previous);
        applied.add(DiscordCallSeatChange(previous, event));
        continue;
      }
      // Moving between calls has to vacate the old seat, or the person shows up
      // in two calls at once.
      final previous = _channelByUser[event.userId];
      if (previous != null && previous != channelId) {
        final seats = _byChannel[previous];
        seats?.remove(event.userId);
        if (seats != null && seats.isEmpty) _byChannel.remove(previous);
        applied.add(DiscordCallSeatChange(previous, event.asDeparture()));
      }
      _channelByUser[event.userId] = channelId;
      _byChannel.putIfAbsent(channelId, () => {})[event.userId] = event;
      applied.add(DiscordCallSeatChange(channelId, event));
    }
    return applied;
  }
}

/// A seat change together with the call it happened in.
///
/// The channel has to travel alongside the state because a departure carries a
/// null channel: without it the caller could not tell which call emptied.
final class DiscordCallSeatChange {
  const DiscordCallSeatChange(this.channelId, this.state);

  final String channelId;
  final VoiceParticipantStateEvent state;
}
