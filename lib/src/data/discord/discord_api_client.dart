import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/chat_models.dart';

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

  Future<List<Map<String, Object?>>> getChannelMessages(
    String channelId, {
    int limit = 100,
  }) => _getList(
    '/channels/$channelId/messages',
    query: {'limit': limit.clamp(1, 100).toString()},
  );

  Future<Map<String, Object?>> createMessage({
    required String channelId,
    required String content,
    List<PendingAttachment> attachments = const [],
    String? replyToMessageId,
  }) {
    final payload = <String, Object?>{
      'content': content,
      if (replyToMessageId != null)
        'message_reference': {'message_id': replyToMessageId},
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
    return _createMultipartMessage(channelId, payload, attachments);
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

  Future<Map<String, Object?>> _createMultipartMessage(
    String channelId,
    Map<String, Object?> payload,
    List<PendingAttachment> attachments,
  ) async {
    final multipart = await _DiscordMultipartBody.build(payload, attachments);
    final response = await _request(
      'POST',
      '/channels/$channelId/messages',
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
    Map<String, Object?>? body,
  }) async {
    final payload = await _request(method, path, body: body);
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

final class _DiscordMultipartBody {
  const _DiscordMultipartBody({required this.bytes, required this.contentType});

  final List<int> bytes;
  final String contentType;

  static Future<_DiscordMultipartBody> build(
    Map<String, Object?> payload,
    List<PendingAttachment> attachments,
  ) async {
    final boundary =
        '----flucord-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    final builder = BytesBuilder(copy: false);

    void text(String value) => builder.add(utf8.encode(value));

    text('--$boundary\r\n');
    text('Content-Disposition: form-data; name="payload_json"\r\n');
    text('Content-Type: application/json\r\n\r\n');
    text(jsonEncode(payload));
    text('\r\n');

    for (var index = 0; index < attachments.length; index++) {
      final attachment = attachments[index];
      final safeName = attachment.name
          .replaceAll(RegExp(r'[\r\n"]'), '_')
          .trim();
      text('--$boundary\r\n');
      text(
        'Content-Disposition: form-data; name="files[$index]"; '
        'filename="$safeName"\r\n',
      );
      text('Content-Type: ${_contentTypeFor(safeName)}\r\n\r\n');
      builder.add(await File(attachment.path).readAsBytes());
      text('\r\n');
    }
    text('--$boundary--\r\n');
    return _DiscordMultipartBody(
      bytes: builder.takeBytes(),
      contentType: 'multipart/form-data; boundary=$boundary',
    );
  }

  static String _contentTypeFor(String name) {
    final extension = name.split('.').last.toLowerCase();
    return switch (extension) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'txt' || 'log' || 'md' => 'text/plain',
      'pdf' => 'application/pdf',
      _ => 'application/octet-stream',
    };
  }
}
