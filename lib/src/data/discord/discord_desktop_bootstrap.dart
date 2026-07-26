import 'dart:developer' as developer;

import 'discord_private_channel_directory.dart';
import 'discord_ready_user_table.dart';

final class DiscordDesktopWorkspaceSnapshot {
  DiscordDesktopWorkspaceSnapshot({
    required Map<String, Object?> currentUser,
    required Iterable<Map<String, Object?>> guilds,
    required Iterable<Map<String, Object?>> directChannels,
    required Map<String, List<Map<String, Object?>>> channelsByGuild,
    Map<String, List<Map<String, Object?>>> rolesByGuild = const {},
    Map<String, List<Map<String, Object?>>> membersByGuild = const {},
  }) : currentUser = Map<String, Object?>.unmodifiable(currentUser),
       guilds = List<Map<String, Object?>>.unmodifiable(
         guilds.map(Map<String, Object?>.unmodifiable),
       ),
       directChannels = List<Map<String, Object?>>.unmodifiable(
         directChannels.map(Map<String, Object?>.unmodifiable),
       ),
       channelsByGuild = _byGuild(channelsByGuild),
       rolesByGuild = _byGuild(rolesByGuild),
       membersByGuild = _byGuild(membersByGuild);

  final Map<String, Object?> currentUser;
  final List<Map<String, Object?>> guilds;

  /// Private channels with their recipients resolved, newest conversation
  /// first: the DM sidebar renders them in this order.
  final List<Map<String, Object?>> directChannels;
  final Map<String, List<Map<String, Object?>>> channelsByGuild;

  /// Guild roles, carrying the permission bits every channel decision starts
  /// from. Dropping them left the client unable to tell a hidden channel from
  /// a visible one.
  final Map<String, List<Map<String, Object?>>> rolesByGuild;

  /// Guild members READY carried, with their user objects resolved. On this
  /// transport that is normally just the account's own membership per guild,
  /// which is exactly what a permission check needs.
  final Map<String, List<Map<String, Object?>>> membersByGuild;

  static Map<String, List<Map<String, Object?>>> _byGuild(
    Map<String, List<Map<String, Object?>>> source,
  ) => Map<String, List<Map<String, Object?>>>.unmodifiable({
    for (final entry in source.entries)
      entry.key: List<Map<String, Object?>>.unmodifiable(
        entry.value.map(Map<String, Object?>.unmodifiable),
      ),
  });
}

/// Assembles the first workspace view out of the gateway's opening dispatches.
///
/// READY is not self-contained. Its private channels reference users through a
/// separate table, and READY_SUPPLEMENTAL arrives later with more channels that
/// resolve against that same table. Collecting the pieces here keeps the
/// cross-dispatch ordering in one readable place and leaves the socket client
/// with transport concerns only.
final class DiscordDesktopBootstrap {
  /// The READY user table, shared with every section that references users by
  /// bare id. Guild members and presences join it in the member-list phase.
  final DiscordReadyUserTable users = DiscordReadyUserTable();

  final DiscordPrivateChannelDirectory _privateChannels =
      DiscordPrivateChannelDirectory();
  final Map<String, Map<String, Object?>> _guilds = {};
  final Map<String, List<Map<String, Object?>>> _channelsByGuild = {};
  final Map<String, List<Map<String, Object?>>> _rolesByGuild = {};
  final Map<String, List<Map<String, Object?>>> _membersByGuild = {};
  Map<String, Object?>? _currentUser;

  void acceptReady(Map<String, Object?> ready) {
    final user = ready['user'];
    if (user is Map) _currentUser = user.cast<String, Object?>();
    // Each READY carries its own user table. A reconnect that replays READY
    // must not resolve recipients against the previous session's users.
    users
      ..clear()
      ..addAll(ready['users']);
    // The same applies to guild state: a replayed READY is the authoritative
    // list, so a guild the account left while disconnected must not survive.
    _guilds.clear();
    _channelsByGuild.clear();
    _rolesByGuild.clear();
    _membersByGuild.clear();
    _privateChannels.applyReady(_expand(_objects(ready['private_channels'])));
    // `merged_members` is positional against `guilds` and counts every entry,
    // including the unavailable ones, so the two are walked by index rather
    // than zipped over the guilds that happen to have content.
    final mergedMembers = ready['merged_members'];
    final guilds = _objects(ready['guilds']);
    for (var index = 0; index < guilds.length; index++) {
      acceptGuild(
        guilds[index],
        members: mergedMembers is List && index < mergedMembers.length
            ? _objects(mergedMembers[index]).map(users.expandMember)
            : null,
      );
    }
  }

  void acceptSupplemental(Map<String, Object?> supplemental) {
    _privateChannels.applySupplemental(
      _expand(_objects(supplemental['lazy_private_channels'])),
    );
    // Discord drops the user table at exactly this point; every section that
    // needs it has been hydrated by now.
    users.clear();
  }

  /// Records one guild. [members] is READY's positional `merged_members` entry
  /// for it; a `GUILD_CREATE` instead carries its members inline.
  void acceptGuild(
    Map<String, Object?> guild, {
    Iterable<Map<String, Object?>>? members,
  }) {
    final id = guild['id'];
    if (id is! String) return;
    _guilds[id] = Map<String, Object?>.unmodifiable(guild);
    final channels = [
      ..._objects(guild['channels']),
      ..._objects(guild['threads']),
    ];
    if (channels.isNotEmpty) _channelsByGuild[id] = channels;
    final roles = _objects(guild['roles']);
    if (roles.isNotEmpty) _rolesByGuild[id] = roles;
    final resolved = [
      ...?members,
      ..._objects(guild['members']).map(users.expandMember),
    ].where((member) => member['user'] is Map).toList(growable: false);
    if (resolved.isNotEmpty) _membersByGuild[id] = resolved;
  }

  /// The snapshot so far, or null while the current user is still unknown.
  DiscordDesktopWorkspaceSnapshot? snapshot() {
    final user = _currentUser;
    if (user == null) return null;
    return DiscordDesktopWorkspaceSnapshot(
      currentUser: user,
      guilds: _guilds.values,
      directChannels: _privateChannels.ordered,
      channelsByGuild: _channelsByGuild,
      rolesByGuild: _rolesByGuild,
      membersByGuild: _membersByGuild,
    );
  }

  void reset() {
    _currentUser = null;
    _guilds.clear();
    _channelsByGuild.clear();
    _rolesByGuild.clear();
    _membersByGuild.clear();
    _privateChannels.clear();
    users.clear();
  }

  List<Map<String, Object?>> _expand(List<Map<String, Object?>> channels) {
    final alreadyUnresolved = users.unresolvedIds.length;
    final expanded = [
      for (final channel in channels) users.expandRecipients(channel),
    ];
    final missed = users.unresolvedIds.length - alreadyUnresolved;
    if (missed > 0) {
      // The recipients are simply absent from those channels, so the DM rows
      // will render without a name. Worth a line in the log, not a failed
      // bootstrap.
      developer.log(
        'Discord private channels referenced $missed recipient(s) missing '
        'from the READY user table.',
        name: 'flucord.discord.gateway',
        level: 900,
      );
    }
    return expanded;
  }

  static List<Map<String, Object?>> _objects(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((item) => item.cast<String, Object?>())
            .toList(growable: false)
      : const [];
}
