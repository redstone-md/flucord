import '../../domain/discord_oauth.dart';
import 'discord_cdn.dart';

final class DiscordOAuthGuildMembershipMapper {
  const DiscordOAuthGuildMembershipMapper();

  DiscordOAuthGuildMembership map({
    required String guildId,
    required Map<String, Object?> payload,
  }) {
    final user = payload['user'];
    final userId = user is Map ? user['id'] : null;
    if (userId is! String || userId.isEmpty) {
      throw const DiscordOAuthException(
        'Discord returned an invalid guild membership.',
      );
    }
    final avatar = payload['avatar'];
    final nickname = payload['nick'];
    return DiscordOAuthGuildMembership(
      guildId: guildId,
      nickname: nickname is String ? nickname : null,
      avatarUrl: DiscordCdn.guildMemberAvatar(
        guildId,
        userId,
        avatar is String ? avatar : null,
        size: 64,
      ),
      roleIds: (payload['roles'] as List? ?? const []).whereType<String>(),
      joinedAt: _timestamp(payload['joined_at']),
      premiumSince: _timestamp(payload['premium_since']),
      pending: payload['pending'] == true,
      communicationDisabledUntil: _timestamp(
        payload['communication_disabled_until'],
      ),
    );
  }

  static DateTime? _timestamp(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;
}
