import 'dart:collection';

import 'discord_member_list_ranges.dart';

/// Tracks what Flucord is subscribed to per guild for opcode 37.
///
/// Discord's bulk subscription frame is a *replace*, not a merge: whatever the
/// `channels` map contains becomes the complete set of subscribed member-list
/// ranges for that guild. So the client has to own the authoritative state,
/// including the eviction policy — dropping a channel from the map is the only
/// way to unsubscribe it.
final class DiscordGuildSubscriptions {
  /// Channels the renderer keeps subscribed per guild before evicting.
  ///
  /// Discord caps this at five and relies on eviction as an implicit
  /// unsubscribe. A larger cap would keep rosters warm but makes every frame
  /// bigger and holds server-side state Flucord is not using.
  static const maxChannelsPerGuild = 5;

  final Map<String, _GuildSubscription> _guilds = {};

  /// Guilds with any tracked subscription state.
  Iterable<String> get guildIds => _guilds.keys;

  /// Ranges currently subscribed for a channel, or `null` when unsubscribed.
  List<List<int>>? rangesFor(String guildId, String channelId) =>
      _guilds[guildId]?.channels[channelId];

  /// Records the base per-guild flags. Returns `true` when anything changed.
  bool setFlags(
    String guildId, {
    bool typing = true,
    bool threads = true,
    bool activities = true,
    bool memberUpdates = false,
  }) {
    final known = _guilds.containsKey(guildId);
    final guild = _guilds.putIfAbsent(guildId, _GuildSubscription.new);
    // A first registration counts as a change even when every flag already
    // holds its default: the server has not been told about the guild yet.
    final changed =
        !known ||
        guild.typing != typing ||
        guild.threads != threads ||
        guild.activities != activities ||
        guild.memberUpdates != memberUpdates;
    guild
      ..typing = typing
      ..threads = threads
      ..activities = activities
      ..memberUpdates = memberUpdates;
    return changed;
  }

  /// Subscribes [ranges] for a channel. Returns `true` when anything changed.
  ///
  /// An identical range set is dropped so scrolling inside one page does not
  /// produce a frame, which is exactly why the renderer can recompute ranges on
  /// every scroll tick.
  bool setChannelRanges(
    String guildId,
    String channelId,
    List<List<int>> ranges,
  ) {
    final guild = _guilds.putIfAbsent(guildId, _GuildSubscription.new);
    final existing = guild.channels[channelId];
    if (existing != null &&
        DiscordMemberListRanges.sameRanges(existing, ranges)) {
      // Touch the entry so an unchanged but actively viewed channel is not the
      // one evicted next.
      guild.channels
        ..remove(channelId)
        ..[channelId] = existing;
      return false;
    }
    guild.channels
      ..remove(channelId)
      ..[channelId] = List<List<int>>.unmodifiable(
        ranges.map(List<int>.unmodifiable),
      );
    while (guild.channels.length > maxChannelsPerGuild) {
      guild.channels.remove(guild.channels.keys.first);
    }
    return true;
  }

  /// Unsubscribes one channel. Returns `true` when it was subscribed.
  bool removeChannel(String guildId, String channelId) =>
      _guilds[guildId]?.channels.remove(channelId) != null;

  /// Forgets a guild entirely without sending anything.
  void removeGuild(String guildId) => _guilds.remove(guildId);

  void clear() => _guilds.clear();

  /// The complete subscription object for one guild.
  Map<String, Object?> snapshot(String guildId) {
    final guild = _guilds[guildId] ?? _GuildSubscription();
    return Map<String, Object?>.unmodifiable({
      'typing': guild.typing,
      'threads': guild.threads,
      'activities': guild.activities,
      'member_updates': guild.memberUpdates,
      'members': const <Object?>[],
      'channels': Map<String, Object?>.unmodifiable({
        for (final entry in guild.channels.entries) entry.key: entry.value,
      }),
      'thread_member_lists': const <Object?>[],
    });
  }

  /// Complete subscription objects for every tracked guild.
  Map<String, Map<String, Object?>> snapshotAll() => {
    for (final guildId in _guilds.keys) guildId: snapshot(guildId),
  };
}

final class _GuildSubscription {
  bool typing = true;
  bool threads = true;
  bool activities = true;
  bool memberUpdates = false;

  /// Insertion-ordered so the oldest entry is the eviction candidate.
  final LinkedHashMap<String, List<List<int>>> channels = LinkedHashMap();
}
