import 'dart:convert';
import 'dart:io';

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
    String? body,
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
    String? body,
  }) async {
    final request = await _client.openUrl(method, uri);
    headers.forEach(request.headers.set);
    if (body != null) {
      request.add(utf8.encode(body));
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
  }) => _requestObject(
    'POST',
    '/channels/$channelId/messages',
    body: {'content': content},
  );

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

  Future<Object?> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    final uri = _baseUri.replace(
      path: '${_baseUri.path}$path',
      queryParameters: query,
    );
    for (var attempt = 0; attempt < 3; attempt++) {
      final response = await _transport.send(
        method: method,
        uri: uri,
        headers: {
          HttpHeaders.authorizationHeader: 'Bot $_botToken',
          HttpHeaders.contentTypeHeader: 'application/json',
          HttpHeaders.userAgentHeader: _userAgent,
        },
        body: body == null ? null : jsonEncode(body),
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
