import 'discord_member_list_id.dart';

/// Remembers enough guild shape to say which member list a channel reads from.
///
/// [DiscordMemberListId] can derive the identifier, but only from a channel
/// record and the guild's `@everyone` permissions — neither of which the
/// dispatch that needs them carries. Discord hands both out once, in READY and
/// `GUILD_CREATE`, and never repeats them, so the client has to keep them or it
/// can never match an inbound roster to the channel it asked about.
final class DiscordMemberListDirectory {
  /// Channel types that are threads and therefore inherit their parent's
  /// visibility instead of carrying overwrites of their own.
  static const threadTypes = {10, 11, 12};

  /// A private thread never counts as readable by `@everyone`.
  static const privateThreadType = 12;

  final Map<String, _Guild> _guilds = {};

  /// Guilds the directory can resolve channels for.
  Iterable<String> get guildIds => _guilds.keys;

  /// Replaces everything with the guilds a fresh READY describes.
  ///
  /// A replayed READY is authoritative, so a guild the account left while
  /// disconnected must not survive and keep answering channel lookups.
  void acceptReady(Map<String, Object?> ready) {
    _guilds.clear();
    for (final guild in _objects(ready['guilds'])) {
      acceptGuild(guild);
    }
  }

  /// Records one guild's channels, threads, and `@everyone` permissions.
  void acceptGuild(Map<String, Object?> guild) {
    final id = guild['id'];
    if (id is! String) return;
    final channels = <String, Map<String, Object?>>{};
    for (final channel in [
      ..._objects(guild['channels']),
      ..._objects(guild['threads']),
    ]) {
      final channelId = channel['id'];
      if (channelId is String) channels[channelId] = channel;
    }
    final roles = _objects(guild['roles']);
    _guilds[id] = _Guild(
      channels: channels,
      roles: roles,
      // The `@everyone` role always carries the guild's own id.
      everyonePermissions: _bits(
        roles
            .where((role) => role['id'] == id)
            .map((role) => role['permissions'])
            .firstOrNull,
      ),
    );
  }

  void removeGuild(String guildId) => _guilds.remove(guildId);

  void clear() => _guilds.clear();

  /// Raw role payloads for a guild, in the order Discord sent them.
  List<Map<String, Object?>> rolesOf(String guildId) =>
      _guilds[guildId]?.roles ?? const [];

  /// The member list identifier the channel's roster arrives on.
  ///
  /// Threads are resolved to their parent for the visibility test only, which
  /// is what the renderer does; the thread's own `member_list_id` still wins
  /// when the server supplied one.
  String memberListIdFor({required String guildId, required String channelId}) {
    final guild = _guilds[guildId];
    final channel = guild?.channels[channelId];
    if (guild == null || channel == null) return DiscordMemberListId.everyone;

    final serverProvided = channel['member_list_id'];
    if (serverProvided is String && serverProvided.isNotEmpty) {
      return serverProvided;
    }

    final parentId = channel['parent_id'];
    final visibility =
        threadTypes.contains(channel['type']) && parentId is String
        ? guild.channels[parentId] ?? channel
        : channel;
    return DiscordMemberListId.resolve(
      channel: visibility,
      everyoneRolePermissions: guild.everyonePermissions,
      isPrivateThread: channel['type'] == privateThreadType,
    );
  }

  static BigInt _bits(Object? value) => switch (value) {
    final int bits => BigInt.from(bits),
    final String bits => BigInt.tryParse(bits) ?? BigInt.zero,
    _ => BigInt.zero,
  };

  static List<Map<String, Object?>> _objects(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((item) => item.cast<String, Object?>())
            .toList(growable: false)
      : const [];
}

final class _Guild {
  const _Guild({
    required this.channels,
    required this.roles,
    required this.everyonePermissions,
  });

  final Map<String, Map<String, Object?>> channels;
  final List<Map<String, Object?>> roles;
  final BigInt everyonePermissions;
}
