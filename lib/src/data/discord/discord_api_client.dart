import 'dart:convert';
import 'dart:io';

import '../../domain/chat_models.dart';
import 'discord_multipart_body.dart';
import 'discord_poll_codec.dart';

final class DiscordHttpResponse {
  const DiscordHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, String> headers;
  final String body;
}

abstract interface class DiscordHttpTransport {
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  });

  void close();
}

final class IoDiscordHttpTransport implements DiscordHttpTransport {
  IoDiscordHttpTransport({HttpClient? client})
    : _client = client ?? HttpClient();

  final HttpClient _client;

  @override
  Future<DiscordHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    final request = await _client.openUrl(method, uri);
    headers.forEach(request.headers.set);
    if (body != null) {
      request.add(body);
    }
    final response = await request.close();
    final responseHeaders = <String, String>{};
    response.headers.forEach((name, values) {
      responseHeaders[name.toLowerCase()] = values.join(',');
    });
    return DiscordHttpResponse(
      statusCode: response.statusCode,
      headers: responseHeaders,
      body: await utf8.decoder.bind(response).join(),
    );
  }

  @override
  void close() => _client.close(force: true);
}

final class DiscordApiException implements Exception {
  const DiscordApiException({required this.statusCode, required this.message});

  final int statusCode;
  final String message;

  bool get isUnauthorized => statusCode == HttpStatus.unauthorized;
  bool get isForbidden => statusCode == HttpStatus.forbidden;

  @override
  String toString() => 'Discord API $statusCode: $message';
}

typedef DelayFunction = Future<void> Function(Duration duration);

final class DiscordApiClient {
  DiscordApiClient({
    required String botToken,
    DiscordHttpTransport? transport,
    DelayFunction? delay,
    Uri? baseUri,
  }) : _botToken = botToken.trim(),
       _transport = transport ?? IoDiscordHttpTransport(),
       _delay = delay ?? Future<void>.delayed,
       _baseUri = baseUri ?? Uri.parse('https://discord.com/api/v10') {
    if (_botToken.isEmpty) {
      throw ArgumentError.value(botToken, 'botToken', 'Token cannot be empty');
    }
  }

  final String _botToken;
  final DiscordHttpTransport _transport;
  final DelayFunction _delay;
  final Uri _baseUri;

  static const _userAgent = 'Flucord/0.1.0 (native Flutter client)';

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

  Future<Map<String, Object?>> createMessage({
    required String channelId,
    required String content,
    List<PendingAttachment> attachments = const [],
    String? replyToMessageId,
    PendingPoll? poll,
  }) {
    final payload = <String, Object?>{
      'content': content,
      if (replyToMessageId != null)
        'message_reference': {'message_id': replyToMessageId},
      if (poll != null) 'poll': DiscordPollCodec.request(poll),
      if (attachments.isNotEmpty)
        'attachments': [
          for (var index = 0; index < attachments.length; index++)
            {'id': index, 'filename': attachments[index].name},
        ],
    };
    if (attachments.isEmpty) {
      return _requestObject(
        'POST',
        '/channels/$channelId/messages',
        body: payload,
      );
    }
    return _createMultipartObject(
      '/channels/$channelId/messages',
      payload,
      attachments,
    );
  }

  Future<Map<String, Object?>> editMessage({
    required String channelId,
    required String messageId,
    required String content,
  }) => _requestObject(
    'PATCH',
    '/channels/$channelId/messages/$messageId',
    body: {'content': content},
  );

  Future<Map<String, Object?>> endPoll({
    required String channelId,
    required String messageId,
  }) => _requestObject('POST', '/channels/$channelId/polls/$messageId/expire');

  Future<void> deleteMessage({
    required String channelId,
    required String messageId,
  }) => _requestEmpty('DELETE', '/channels/$channelId/messages/$messageId');

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

  Future<String> getGatewayUrl() async {
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

  Future<Map<String, Object?>> _getObject(String path) =>
      _requestObject('GET', path);

  Future<List<Map<String, Object?>>> _getList(
    String path, {
    Map<String, String>? query,
  }) async {
    final payload = await _request('GET', path, query: query);
    if (payload is! List) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Expected a JSON array',
      );
    }
    return payload
        .whereType<Map>()
        .map((item) => item.cast<String, Object?>())
        .toList(growable: false);
  }

  Future<Map<String, Object?>> _requestObject(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    final payload = await _request(method, path, query: query, body: body);
    if (payload is! Map) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Expected a JSON object',
      );
    }
    return payload.cast<String, Object?>();
  }

  Future<void> _requestEmpty(String method, String path) async {
    await _request(method, path);
  }

  Future<Object?> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    List<int>? rawBody,
    String contentType = 'application/json',
  }) async {
    final uri = Uri.parse(
      '${_baseUri.toString()}$path',
    ).replace(queryParameters: query);
    for (var attempt = 0; attempt < 3; attempt++) {
      final response = await _transport.send(
        method: method,
        uri: uri,
        headers: {
          HttpHeaders.authorizationHeader: 'Bot $_botToken',
          HttpHeaders.acceptHeader: 'application/json',
          HttpHeaders.contentTypeHeader: contentType,
          HttpHeaders.userAgentHeader: _userAgent,
        },
        body: rawBody ?? (body == null ? null : utf8.encode(jsonEncode(body))),
      );
      final payload = response.body.isEmpty ? null : jsonDecode(response.body);
      if (response.statusCode == HttpStatus.tooManyRequests && attempt < 2) {
        await _delay(_retryAfter(payload, response.headers));
        continue;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw DiscordApiException(
          statusCode: response.statusCode,
          message: _errorMessage(payload),
        );
      }
      return payload;
    }
    throw const DiscordApiException(
      statusCode: 429,
      message: 'Rate limit retry budget exhausted',
    );
  }

  static Duration _retryAfter(Object? payload, Map<String, String> headers) {
    num? seconds;
    if (payload is Map) seconds = payload['retry_after'] as num?;
    seconds ??= num.tryParse(headers['retry-after'] ?? '');
    return Duration(milliseconds: ((seconds ?? 1) * 1000).ceil());
  }

  static String _errorMessage(Object? payload) {
    if (payload is Map && payload['message'] is String) {
      return payload['message']! as String;
    }
    return 'Request failed';
  }

  void close() => _transport.close();
}
