import '../domain/discord_social_dm.dart';
import '../domain/discord_relationship.dart';

final class UnavailableDiscordSocialDmGateway
    implements DiscordSocialDmGateway {
  const UnavailableDiscordSocialDmGateway();

  @override
  Future<List<DiscordSocialDmConversation>> fetchConversations() =>
      Future.error(const DiscordSocialSdkException('unsupported_platform'));

  @override
  Future<List<DiscordSocialDmMessage>> fetchMessages({
    required String userId,
    int limit = 100,
  }) => Future.error(const DiscordSocialSdkException('unsupported_platform'));

  @override
  Future<String> sendMessage({
    required String userId,
    required String content,
  }) => Future.error(const DiscordSocialSdkException('unsupported_platform'));
}
