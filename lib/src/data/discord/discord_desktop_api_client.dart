import '../../domain/chat_models.dart';
import 'discord_multipart_body.dart';
import 'discord_rest_client.dart';

final class DiscordDesktopApiClient {
  DiscordDesktopApiClient({
    required String authorization,
    required Map<String, String> headers,
    DiscordHttpTransport? transport,
    DelayFunction? delay,
    Uri? baseUri,
  }) : _rest = DiscordRestClient(
         authorization: DiscordDesktopAuthorization(authorization),
         additionalHeaders: headers,
         transport: transport,
         delay: delay,
         baseUri: baseUri ?? Uri.parse('https://discord.com/api/v9'),
       );

  final DiscordRestClient _rest;

  Future<List<Map<String, Object?>>> getChannelMessages(
    String channelId, {
    int limit = 100,
    String? beforeMessageId,
  }) => _rest.getList(
    '/channels/$channelId/messages',
    query: {'limit': '${limit.clamp(1, 100)}', 'before': ?beforeMessageId},
  );

  Future<List<Map<String, Object?>>> getChannelPins(String channelId) async {
    final payload = await _rest.requestObject(
      'GET',
      '/channels/$channelId/messages/pins',
      query: const {'limit': '50'},
    );
    final items = payload['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((item) {
          final message = item['message'];
          return message is Map
              ? {...message.cast<String, Object?>(), 'pinned': true}
              : <String, Object?>{};
        })
        .where((message) => message.isNotEmpty)
        .toList(growable: false);
  }

  Future<Map<String, Object?>> createDirectMessageChannel(String recipientId) =>
      _rest.requestObject(
        'POST',
        '/users/@me/channels',
        body: {
          'recipients': [recipientId],
        },
      );

  Future<Map<String, Object?>> createThreadFromMessage({
    required String channelId,
    required String messageId,
    required String name,
    required int autoArchiveDurationMinutes,
  }) => _rest.requestObject(
    'POST',
    '/channels/$channelId/messages/$messageId/threads',
    body: {'name': name, 'auto_archive_duration': autoArchiveDurationMinutes},
  );

  Future<Map<String, Object?>> createMessage({
    required String channelId,
    required String content,
    required String nonce,
    List<PendingAttachment> attachments = const [],
    String? replyToMessageId,
    bool suppressNotifications = false,
  }) async {
    final payload = <String, Object?>{
      'content': content,
      'nonce': nonce,
      'tts': false,
      'flags': suppressNotifications ? 4096 : 0,
      if (replyToMessageId != null)
        'message_reference': {'message_id': replyToMessageId},
      if (attachments.isNotEmpty)
        'attachments': [
          for (var index = 0; index < attachments.length; index++)
            {'id': index, 'filename': attachments[index].name},
        ],
    };
    if (attachments.isEmpty) {
      return _rest.requestObject(
        'POST',
        '/channels/$channelId/messages',
        body: payload,
      );
    }
    final multipart = await DiscordMultipartBody.build(payload, attachments);
    final response = await _rest.request(
      'POST',
      '/channels/$channelId/messages',
      rawBody: multipart.bytes,
      contentType: multipart.contentType,
    );
    if (response is! Map) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Expected a message object',
      );
    }
    return response.cast<String, Object?>();
  }

  Future<Map<String, Object?>> editMessage({
    required String channelId,
    required String messageId,
    required String content,
  }) => _rest.requestObject(
    'PATCH',
    '/channels/$channelId/messages/$messageId',
    body: {'content': content},
  );

  Future<void> deleteMessage({
    required String channelId,
    required String messageId,
  }) =>
      _rest.requestEmpty('DELETE', '/channels/$channelId/messages/$messageId');

  Future<void> addReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => _rest.requestEmpty(
    'PUT',
    '/channels/$channelId/messages/$messageId/reactions/${Uri.encodeComponent(emoji)}/@me',
  );

  Future<void> removeReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) => _rest.requestEmpty(
    'DELETE',
    '/channels/$channelId/messages/$messageId/reactions/${Uri.encodeComponent(emoji)}/@me',
  );

  Future<void> setPinned({
    required String channelId,
    required String messageId,
    required bool pinned,
  }) => _rest.requestEmpty(
    pinned ? 'PUT' : 'DELETE',
    '/channels/$channelId/messages/pins/$messageId',
  );

  Future<void> startTyping(String channelId) =>
      _rest.requestEmpty('POST', '/channels/$channelId/typing');

  Future<String> getGatewayUrl() async {
    final payload = await _rest.getObject('/gateway');
    final url = payload['url'];
    if (url is! String || url.isEmpty) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Gateway URL missing from response',
      );
    }
    return url;
  }

  void close() => _rest.close();
}
