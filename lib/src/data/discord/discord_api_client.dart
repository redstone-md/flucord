import '../../domain/chat_models.dart';
import '../../domain/reaction_repository.dart';
import '../../domain/voice_message_recorder.dart';
import 'discord_multipart_body.dart';
import 'discord_poll_codec.dart';
import 'discord_rest_client.dart';

export 'discord_rest_client.dart';

part 'discord_api_client_scheduled_events.dart';
part 'discord_api_client_reactions.dart';
part 'discord_api_client_forwards.dart';
part 'discord_api_client_messages.dart';

/// Bot-only Discord REST facade for chat, guild, message, and Gateway routes.
final class DiscordApiClient {
  factory DiscordApiClient({
    required String botToken,
    DiscordHttpTransport? transport,
    DelayFunction? delay,
    Uri? baseUri,
  }) => DiscordApiClient._(
    DiscordRestClient(
      authorization: DiscordBotAuthorization(botToken),
      transport: transport,
      delay: delay,
      baseUri: baseUri,
    ),
  );

  const DiscordApiClient._(this._rest);

  final DiscordRestClient _rest;

  Future<Map<String, Object?>> getCurrentUser() => _getObject('/users/@me');

  Future<List<Map<String, Object?>>> getCurrentUserGuilds() async {
    final guilds = <Map<String, Object?>>[];
    String? after;
    do {
      final query = <String, String>{'limit': '200'};
      if (after != null) query['after'] = after;
      final page = await _getList('/users/@me/guilds', query: query);
      guilds.addAll(page);
      after = page.length == 200 ? page.last['id'] as String? : null;
    } while (after != null);
    return guilds;
  }

  Future<List<Map<String, Object?>>> getGuildChannels(String guildId) =>
      _getList('/guilds/$guildId/channels');

  Future<Map<String, Object?>> createDirectMessageChannel(String recipientId) =>
      _requestObject(
        'POST',
        '/users/@me/channels',
        body: {'recipient_id': recipientId},
      );

  Future<Map<String, Object?>> createThreadFromMessage({
    required String channelId,
    required String messageId,
    required String name,
    required int autoArchiveDurationMinutes,
  }) => _requestObject(
    'POST',
    '/channels/$channelId/messages/$messageId/threads',
    body: {'name': name, 'auto_archive_duration': autoArchiveDurationMinutes},
  );

  Future<Map<String, Object?>> getPublicArchivedThreads(
    String channelId, {
    DateTime? before,
    int limit = 50,
  }) => _requestObject(
    'GET',
    '/channels/$channelId/threads/archived/public',
    query: {
      'limit': '$limit',
      if (before != null) 'before': before.toUtc().toIso8601String(),
    },
  );

  Future<Map<String, Object?>> createForumPost({
    required String channelId,
    required String name,
    required String content,
    required int autoArchiveDurationMinutes,
    List<PendingAttachment> attachments = const [],
    List<String> appliedTagIds = const [],
  }) {
    final payload = <String, Object?>{
      'name': name,
      'auto_archive_duration': autoArchiveDurationMinutes,
      'message': {
        'content': content,
        if (attachments.isNotEmpty)
          'attachments': [
            for (var index = 0; index < attachments.length; index++)
              {'id': index, 'filename': attachments[index].name},
          ],
      },
      if (appliedTagIds.isNotEmpty) 'applied_tags': appliedTagIds,
    };
    final path = '/channels/$channelId/threads';
    if (attachments.isEmpty) {
      return _requestObject('POST', path, body: payload);
    }
    return _createMultipartObject(path, payload, attachments);
  }

  Future<List<Map<String, Object?>>> getGuildRoles(String guildId) =>
      _getList('/guilds/$guildId/roles');

  Future<List<Map<String, Object?>>> getGuildEmojis(String guildId) =>
      _getList('/guilds/$guildId/emojis');

  Future<List<Map<String, Object?>>> getGuildStickers(String guildId) =>
      _getList('/guilds/$guildId/stickers');

  Future<List<Map<String, Object?>>> getGuildMembers(String guildId) async {
    final members = <Map<String, Object?>>[];
    String? after;
    do {
      final query = <String, String>{'limit': '1000'};
      if (after != null) query['after'] = after;
      final page = await _getList('/guilds/$guildId/members', query: query);
      members.addAll(page);
      final lastUser = page.isEmpty ? null : page.last['user'];
      after = page.length == 1000 && lastUser is Map
          ? lastUser['id'] as String?
          : null;
    } while (after != null);
    return members;
  }

  Future<List<Map<String, Object?>>> getChannelMessages(
    String channelId, {
    int limit = 100,
    String? beforeMessageId,
  }) => _getList(
    '/channels/$channelId/messages',
    query: {
      'limit': limit.clamp(1, 100).toString(),
      'before': ?beforeMessageId,
    },
  );

  Future<List<Map<String, Object?>>> getChannelPins(String channelId) async {
    final messages = <Map<String, Object?>>[];
    String? before;
    var hasMore = true;
    while (hasMore) {
      final payload = await _requestObject(
        'GET',
        '/channels/$channelId/messages/pins',
        query: {'limit': '50', 'before': ?before},
      );
      final items = payload['items'];
      if (items is! List) break;
      final mappedItems = items.whereType<Map>().toList(growable: false);
      for (final item in mappedItems) {
        final rawMessage = item['message'];
        if (rawMessage is Map) {
          messages.add({...rawMessage.cast<String, Object?>(), 'pinned': true});
        }
      }
      hasMore = payload['has_more'] == true && mappedItems.isNotEmpty;
      before = hasMore ? mappedItems.last['pinned_at'] as String? : null;
      if (hasMore && before == null) break;
    }
    return messages;
  }

  Future<Map<String, Object?>> endPoll({
    required String channelId,
    required String messageId,
  }) => _requestObject('POST', '/channels/$channelId/polls/$messageId/expire');

  Future<void> addReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) {
    final encodedEmoji = Uri.encodeComponent(emoji);
    return _requestEmpty(
      'PUT',
      '/channels/$channelId/messages/$messageId/reactions/$encodedEmoji/@me',
    );
  }

  Future<void> removeReaction({
    required String channelId,
    required String messageId,
    required String emoji,
  }) {
    final encodedEmoji = Uri.encodeComponent(emoji);
    return _requestEmpty(
      'DELETE',
      '/channels/$channelId/messages/$messageId/reactions/$encodedEmoji/@me',
    );
  }

  Future<void> pinMessage({
    required String channelId,
    required String messageId,
  }) => _requestEmpty('PUT', '/channels/$channelId/messages/pins/$messageId');

  Future<void> unpinMessage({
    required String channelId,
    required String messageId,
  }) =>
      _requestEmpty('DELETE', '/channels/$channelId/messages/pins/$messageId');

  Future<void> startTyping(String channelId) =>
      _requestEmpty('POST', '/channels/$channelId/typing');

  Future<List<Map<String, Object?>>> getGuildActiveThreads(
    String guildId,
  ) async {
    final payload = await _requestObject(
      'GET',
      '/guilds/$guildId/threads/active',
    );
    final threads = payload['threads'];
    if (threads is! List) return const [];
    return threads
        .whereType<Map>()
        .map((thread) => thread.cast<String, Object?>())
        .toList(growable: false);
  }

  Future<Map<String, Object?>> _createMultipartObject(
    String path,
    Map<String, Object?> payload,
    List<PendingAttachment> attachments,
  ) async {
    final multipart = await DiscordMultipartBody.build(payload, attachments);
    final response = await _request(
      'POST',
      path,
      rawBody: multipart.bytes,
      contentType: multipart.contentType,
    );
    if (response is! Map) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Expected a JSON object',
      );
    }
    return response.cast<String, Object?>();
  }

  Future<String> getBotGatewayUrl() async {
    final payload = await _getObject('/gateway/bot');
    final url = payload['url'];
    if (url is! String || url.isEmpty) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Gateway URL missing from response',
      );
    }
    return url;
  }

  Future<Map<String, Object?>> _getObject(String path) => _rest.getObject(path);

  Future<List<Map<String, Object?>>> _getList(
    String path, {
    Map<String, String>? query,
  }) async {
    return _rest.getList(path, query: query);
  }

  Future<Map<String, Object?>> _requestObject(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    return _rest.requestObject(method, path, query: query, body: body);
  }

  Future<void> _requestEmpty(String method, String path) async {
    await _rest.requestEmpty(method, path);
  }

  Future<Object?> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    List<int>? rawBody,
    String contentType = 'application/json',
  }) => _rest.request(
    method,
    path,
    query: query,
    body: body,
    rawBody: rawBody,
    contentType: contentType,
  );

  void close() => _rest.close();
}
