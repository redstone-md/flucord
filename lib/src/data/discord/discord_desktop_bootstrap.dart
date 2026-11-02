import '../../domain/read_state.dart';
import 'discord_private_channel_directory.dart';
import 'discord_read_state_codec.dart';
import 'discord_ready_user_table.dart';
import '../../app_log.dart';

final class DiscordDesktopWorkspaceSnapshot {
  DiscordDesktopWorkspaceSnapshot({
    required Map<String, Object?> currentUser,
    required Iterable<Map<String, Object?>> guilds,
    required Iterable<Map<String, Object?>> directChannels,
    required Map<String, List<Map<String, Object?>>> channelsByGuild,
    Map<String, List<Map<String, Object?>>> rolesByGuild = const {},
    Map<String, List<Map<String, Object?>>> membersByGuild = const {},
    Map<String, List<Map<String, Object?>>> emojisByGuild = const {},
    Map<String, List<Map<String, Object?>>> stickersByGuild = const {},
    required this.privateChannelsComplete,
  }) : currentUser = Map<String, Object?>.unmodifiable(currentUser),
       guilds = List<Map<String, Object?>>.unmodifiable(
         guilds.map(Map<String, Object?>.unmodifiable),
       ),
       directChannels = List<Map<String, Object?>>.unmodifiable(
         directChannels.map(Map<String, Object?>.unmodifiable),
       ),
       channelsByGuild = _byGuild(channelsByGuild),
       rolesByGuild = _byGuild(rolesByGuild),
       membersByGuild = _byGuild(membersByGuild),
       emojisByGuild = _byGuild(emojisByGuild),
       stickersByGuild = _byGuild(stickersByGuild);

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

  /// The servers' own emoji and stickers. On this transport they arrive only
  /// inside READY's guild entries, and the composer's pickers draw from them.
  final Map<String, List<Map<String, Object?>>> emojisByGuild;
  final Map<String, List<Map<String, Object?>>> stickersByGuild;

  /// False from READY until READY_SUPPLEMENTAL. Until then a private channel
  /// missing from [directChannels] may still be on its way as a lazy one.
  final bool privateChannelsComplete;

  /// Guilds READY marks as in an outage on Discord's side. The account is still
  /// in them, but the entry carries nothing else.
  Set<String> get unavailableGuildIds => {
    for (final guild in guilds)
      if (guild['unavailable'] == true) guild['id']! as String,
  };

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
  final Map<String, List<Map<String, Object?>>> _emojisByGuild = {};
  final Map<String, List<Map<String, Object?>>> _stickersByGuild = {};
  Map<String, Object?>? _currentUser;
  bool _privateChannelsComplete = false;

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
    _emojisByGuild.clear();
    _stickersByGuild.clear();
    _privateChannelsComplete = false;
    _privateChannels
      ..useReadStateCursors(_readStateCursors(ready['read_state']))
      ..applyReady(_expand(_objects(ready['private_channels'])));
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
    _privateChannelsComplete = true;
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
    _emojisByGuild[id] = _named(guild['emojis']);
    _stickersByGuild[id] = _named(guild['stickers']);
  }

  /// Forgets a guild the account left. A later pass over the snapshot must not
  /// bring it back.
  void removeGuild(String id) {
    _guilds.remove(id);
    _channelsByGuild.remove(id);
    _rolesByGuild.remove(id);
    _membersByGuild.remove(id);
    _emojisByGuild.remove(id);
    _stickersByGuild.remove(id);
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
      emojisByGuild: _emojisByGuild,
      stickersByGuild: _stickersByGuild,
      privateChannelsComplete: _privateChannelsComplete,
    );
  }

  void reset() {
    _currentUser = null;
    _privateChannelsComplete = false;
    _guilds.clear();
    _channelsByGuild.clear();
    _rolesByGuild.clear();
    _membersByGuild.clear();
    _emojisByGuild.clear();
    _stickersByGuild.clear();
    _privateChannels.clear();
    users.clear();
  }

  /// The emoji or stickers that have what the mapper requires. One broken entry
  /// must not stop the whole workspace from being built.
  static List<Map<String, Object?>> _named(Object? entries) => _objects(
    entries,
  ).where((entry) => entry['id'] is String && entry['name'] is String).toList();

  /// The channel read states' ack cursors, keyed by channel id.
  static Map<String, String> _readStateCursors(Object? block) {
    if (block is! Map) return const {};
    final cursors = <String, String>{};
    for (final entry in _objects(block.cast<String, Object?>()['entries'])) {
      final state = DiscordReadStateCodec.readState(entry);
      final acked = state?.lastAckedId;
      if (state == null || acked == null) continue;
      if (state.type != ReadStateType.channel) continue;
      cursors[state.entityId] = acked;
    }
    return cursors;
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
      AppLog.warning(
        'discord.gateway',
        'Discord private channels referenced $missed recipient(s) missing '
            'from the READY user table.',
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
