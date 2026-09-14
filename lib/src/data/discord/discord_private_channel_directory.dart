import 'discord_private_channel_order.dart';

/// The DM and group-DM directory as READY and READY_SUPPLEMENTAL deliver it.
///
/// READY carries the list, and READY_SUPPLEMENTAL may top it up with
/// `lazy_private_channels`. Discord does not merge the two dispatches: it
/// rebuilds the directory from the remembered READY list and then applies the
/// lazy entries over it. Remembering that list is part of the contract — replay
/// it and a late top-up can neither drop the channels READY listed nor leave
/// behind a READY copy of a channel the second dispatch meant to replace.
///
/// Discord additionally hides the DM with its changelog account by recipient
/// id. That id is a literal snowflake, which this repository's privacy audit
/// refuses to carry, so the exclusion is deliberately not ported.
final class DiscordPrivateChannelDirectory {
  final Map<String, Map<String, Object?>> _channels = {};
  List<Map<String, Object?>>? _initial;
  Map<String, String> _readStateLastMessageIds = const {};

  /// Every known private channel, ordered as the DM list renders it.
  List<Map<String, Object?>> get ordered => DiscordPrivateChannelOrder.sorted(
    _channels.values,
    readStateLastMessageIds: _readStateLastMessageIds,
  );

  /// Hands the directory the read-state cursors READY carried.
  ///
  /// R09 orders the DM list on the read state's cursor in preference to the
  /// channel record's `last_message_id`, so a conversation whose newest message
  /// was deleted keeps the position the account last read it at.
  void useReadStateCursors(Map<String, String> lastMessageIds) =>
      _readStateLastMessageIds = Map.unmodifiable({...lastMessageIds});

  /// Replaces the directory with `READY.private_channels`.
  void applyReady(Iterable<Map<String, Object?>> channels) {
    final initial = List<Map<String, Object?>>.of(channels);
    _initial = initial;
    _channels.clear();
    _insertAll(initial);
  }

  /// Applies `READY_SUPPLEMENTAL.lazy_private_channels` over the READY list.
  void applySupplemental(Iterable<Map<String, Object?>> channels) {
    final initial = _initial;
    if (initial != null) {
      _channels.clear();
      _insertAll(initial);
    }
    _insertAll(channels);
  }

  /// Forgets everything, including the remembered READY list.
  void clear() {
    _channels.clear();
    _initial = null;
    _readStateLastMessageIds = const {};
  }

  void _insertAll(Iterable<Map<String, Object?>> channels) {
    for (final channel in channels) {
      final id = channel['id'];
      if (id is! String || id.isEmpty) continue;
      _channels[id] = channel;
    }
  }
}
