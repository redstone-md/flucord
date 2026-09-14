import '../../domain/discord_oauth.dart';
import 'discord_cdn.dart';

final class DiscordOAuthAccountMapper {
  const DiscordOAuthAccountMapper();

  DiscordOAuthAccount map({
    required Map<String, Object?> user,
    required List<Map<String, Object?>> guilds,
    List<Map<String, Object?>> connections = const [],
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
    final banner = user['banner'];
    final accentColor = user['accent_color'];
    final discriminator = user['discriminator'];
    final locale = user['locale'];
    final publicFlags = user['public_flags'];
    return DiscordOAuthAccount(
      id: id,
      username: username,
      displayName: globalName is String && globalName.isNotEmpty
          ? globalName
          : username,
      discriminator: discriminator is String ? discriminator : null,
      avatarUrl: DiscordCdn.userAvatar(
        id,
        avatar is String ? avatar : null,
        size: 64,
      ),
      bannerUrl: DiscordCdn.userBanner(id, banner is String ? banner : null),
      accentColor: accentColor is int ? accentColor : null,
      locale: locale is String ? locale : null,
      isVerified: user['verified'] == true,
      mfaEnabled: user['mfa_enabled'] == true,
      publicFlags: publicFlags is int ? publicFlags : 0,
      guilds: guilds.map(_mapGuild).whereType<DiscordOAuthGuild>(),
      connections: connections
          .map(_mapConnection)
          .whereType<DiscordOAuthConnection>(),
    );
  }

  DiscordOAuthConnection? _mapConnection(Map<String, Object?> payload) {
    final id = payload['id'];
    final name = payload['name'];
    final type = payload['type'];
    final visibility = payload['visibility'];
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        name.isEmpty ||
        type is! String ||
        type.isEmpty) {
      return null;
    }
    return DiscordOAuthConnection(
      id: id,
      name: name,
      type: type,
      revoked: payload['revoked'] == true,
      verified: payload['verified'] == true,
      friendSync: payload['friend_sync'] == true,
      showActivity: payload['show_activity'] == true,
      twoWayLink: payload['two_way_link'] == true,
      visibility: visibility is int ? visibility : 0,
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
