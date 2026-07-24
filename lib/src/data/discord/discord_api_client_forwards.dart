part of 'discord_api_client.dart';

extension DiscordApiClientForwards on DiscordApiClient {
  Future<Map<String, Object?>> forwardMessage({
    required String sourceChannelId,
    required String sourceMessageId,
    required String targetChannelId,
  }) => _requestObject(
    'POST',
    '/channels/$targetChannelId/messages',
    body: {
      'message_reference': {
        'type': DiscordMessageReferenceType.forward.discordValue,
        'message_id': sourceMessageId,
        'channel_id': sourceChannelId,
      },
    },
  );
}
