/// Who the account is, and which roles it holds in each guild.
///
/// A fold over the dispatches that say so: READY names the account and its
/// member row in each guild, `GUILD_CREATE` does the same for a guild that
/// arrives later, and `GUILD_MEMBER_UPDATE` carries a change of roles. READY
/// compresses a member's user to a bare `user_id`, and its user table leaves out
/// the account itself, so both shapes of member row are read here.
final class DiscordAccountRoles {
  final Map<String, Set<String>> _rolesByGuild = {};
  String? _accountId;

  String? get accountId => _accountId;

  Set<String> inGuild(String guildId) => _rolesByGuild[guildId] ?? const {};

  void accept(String name, Map<String, Object?> data) {
    switch (name) {
      case 'READY':
        _acceptReady(data);
      case 'GUILD_CREATE':
        _acceptGuild(data, data['members']);
      case 'GUILD_MEMBER_UPDATE':
        _acceptMember(data['guild_id'], data);
    }
  }

  void clear() {
    _accountId = null;
    _rolesByGuild.clear();
  }

  void _acceptReady(Map<String, Object?> data) {
    final user = data['user'];
    if (user is Map && user['id'] is String) _accountId = user['id'] as String;
    _rolesByGuild.clear();
    final guilds = data['guilds'];
    if (guilds is! List) return;
    // `merged_members` is positional against `guilds`, unavailable ones too.
    final merged = data['merged_members'];
    for (var index = 0; index < guilds.length; index++) {
      final guild = guilds[index];
      if (guild is! Map) continue;
      final map = guild.cast<String, Object?>();
      _acceptGuild(map, map['members']);
      if (merged is List && index < merged.length) {
        _acceptGuild(map, merged[index]);
      }
    }
  }

  void _acceptGuild(Map<String, Object?> guild, Object? members) {
    if (members is! List) return;
    for (final member in members.whereType<Map>()) {
      _acceptMember(guild['id'], member.cast<String, Object?>());
    }
  }

  void _acceptMember(Object? guildId, Map<String, Object?> member) {
    if (guildId is! String || !_isAccount(member)) return;
    final roles = member['roles'];
    if (roles is List) {
      _rolesByGuild[guildId] = roles.whereType<String>().toSet();
    }
  }

  bool _isAccount(Map<String, Object?> member) {
    final user = member['user'];
    final id = user is Map ? user['id'] : member['user_id'];
    return id != null && id == _accountId;
  }
}
