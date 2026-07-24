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

  @override
  Future<void> editMessage({
    required String userId,
    required String messageId,
    required String content,
  }) => Future.error(const DiscordSocialSdkException('unsupported_platform'));

  @override
  Future<void> deleteMessage({
    required String userId,
    required String messageId,
  }) => Future.error(const DiscordSocialSdkException('unsupported_platform'));

  @override
  Future<void> setShowingChat(bool showing) =>
      Future.error(const DiscordSocialSdkException('unsupported_platform'));
}
