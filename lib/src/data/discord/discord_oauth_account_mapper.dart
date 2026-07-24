import '../../domain/discord_oauth.dart';
import 'discord_cdn.dart';

final class DiscordOAuthAccountMapper {
  const DiscordOAuthAccountMapper();

  DiscordOAuthAccount map({
    required Map<String, Object?> user,
    required List<Map<String, Object?>> guilds,
  }) {
    final id = user['id'];
    final username = user['username'];
    if (id is! String || username is! String) {
      throw const DiscordOAuthException(
        'Discord returned an invalid account identity.',
      );
    }
    final globalName = user['global_name'];
    final avatar = user['avatar'];
    return DiscordOAuthAccount(
      id: id,
      username: username,
      displayName: globalName is String && globalName.isNotEmpty
          ? globalName
          : username,
      avatarUrl: DiscordCdn.userAvatar(
        id,
        avatar is String ? avatar : null,
        size: 64,
      ),
      guilds: guilds.map(_mapGuild).whereType<DiscordOAuthGuild>(),
    );
  }

  DiscordOAuthGuild? _mapGuild(Map<String, Object?> payload) {
    final id = payload['id'];
    final name = payload['name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      return null;
    }
    final icon = payload['icon'];
    final banner = payload['banner'];
    return DiscordOAuthGuild(
      id: id,
      name: name,
      iconUrl: DiscordCdn.guildIcon(id, icon is String ? icon : null, size: 64),
      bannerUrl: DiscordCdn.guildBanner(id, banner is String ? banner : null),
      isOwner: payload['owner'] == true,
      permissions: payload['permissions']?.toString() ?? '0',
      features: (payload['features'] as List? ?? const []).whereType<String>(),
      approximateMemberCount: _count(payload['approximate_member_count']),
      approximatePresenceCount: _count(payload['approximate_presence_count']),
    );
  }

  static int? _count(Object? value) =>
      value is int && value >= 0 ? value : null;
}
