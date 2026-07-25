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
    if (body != null) request.add(body);
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
  const DiscordApiException({
    required this.statusCode,
    required this.message,
    this.responsePayload,
  });

  final int statusCode;
  final String message;
  final Map<String, Object?>? responsePayload;

  bool get isUnauthorized => statusCode == HttpStatus.unauthorized;
  bool get isForbidden => statusCode == HttpStatus.forbidden;

  @override
  String toString() => 'Discord API $statusCode: $message';
}

sealed class DiscordRestAuthorization {
  DiscordRestAuthorization._(String credential, String argumentName)
    : _credential = credential.trim() {
    if (_credential.isEmpty) {
      throw ArgumentError.value(
        credential,
        argumentName,
        'Credential cannot be empty',
      );
    }
  }

  final String _credential;

  String get _headerValue;

  @override
  String toString() => '$runtimeType(<redacted>)';
}

final class DiscordBotAuthorization extends DiscordRestAuthorization {
  DiscordBotAuthorization(String token) : super._(token, 'token');

  @override
  String get _headerValue => 'Bot $_credential';
}

final class DiscordBearerAuthorization extends DiscordRestAuthorization {
  DiscordBearerAuthorization(String accessToken)
    : super._(accessToken, 'accessToken');

  @override
  String get _headerValue => 'Bearer $_credential';
}

final class DiscordDesktopAuthorization extends DiscordRestAuthorization {
  DiscordDesktopAuthorization(String authorization)
    : super._(authorization, 'authorization');

  @override
  String get _headerValue => _credential;
}

typedef DelayFunction = Future<void> Function(Duration duration);

final class DiscordHttpExecutor {
  DiscordHttpExecutor({
    DiscordHttpTransport? transport,
    DelayFunction? delay,
    Uri? baseUri,
  }) : _transport = transport ?? IoDiscordHttpTransport(),
       _delay = delay ?? Future<void>.delayed,
       _baseUri = baseUri ?? Uri.parse('https://discord.com/api/v10');

  final DiscordHttpTransport _transport;
  final DelayFunction _delay;
  final Uri _baseUri;

  Future<Object?> execute(
    String method,
    String path, {
    Map<String, String>? query,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    final uri = Uri.parse(
      '${_baseUri.toString()}$path',
    ).replace(queryParameters: query);
    for (var attempt = 0; attempt < 3; attempt++) {
      final response = await _transport.send(
        method: method,
        uri: uri,
        headers: headers,
        body: body,
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
          responsePayload: payload is Map
              ? Map.unmodifiable(payload.cast<String, Object?>())
              : null,
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
    if (payload is Map) {
      for (final key in const ['message', 'error_description', 'error']) {
        final value = payload[key];
        if (value is String && value.isNotEmpty) return value;
      }
      final details = <String>[];
      _collectErrorDetails(payload, '', details);
      if (details.isNotEmpty) return details.take(3).join('; ');
    }
    return 'Request failed';
  }

  static void _collectErrorDetails(
    Object? value,
    String path,
    List<String> details,
  ) {
    if (details.length >= 3) return;
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString();
        if (const {'message', 'error_description', 'error'}.contains(key)) {
          continue;
        }
        final childPath = path.isEmpty ? key : '$path.$key';
        _collectErrorDetails(entry.value, childPath, details);
      }
      return;
    }
    if (value is List) {
      for (final item in value) {
        _collectErrorDetails(item, path, details);
      }
      return;
    }
    if (value is String && value.trim().isNotEmpty) {
      final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
      final looksLikeSecret =
          normalized.length > 32 &&
          RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(normalized);
      details.add('$path: ${looksLikeSecret ? '<redacted>' : normalized}');
      return;
    }
    if (value is num || value is bool) details.add('$path: $value');
  }

  void close() => _transport.close();
}

final class DiscordRestClient {
  DiscordRestClient({
    required this._authorization,
    Map<String, String> additionalHeaders = const {},
    DiscordHttpTransport? transport,
    DelayFunction? delay,
    Uri? baseUri,
  }) : _additionalHeaders = Map.unmodifiable({...additionalHeaders}),
       _executor = DiscordHttpExecutor(
         transport: transport,
         delay: delay,
         baseUri: baseUri,
       );

  static const _userAgent = 'Flucord/0.1.0 (native Flutter client)';

  final DiscordRestAuthorization _authorization;
  final Map<String, String> _additionalHeaders;
  final DiscordHttpExecutor _executor;

  Future<Map<String, Object?>> getObject(String path) =>
      requestObject('GET', path);

  Future<List<Map<String, Object?>>> getList(
    String path, {
    Map<String, String>? query,
  }) async {
    final payload = await request('GET', path, query: query);
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

  Future<Map<String, Object?>> requestObject(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    final payload = await request(method, path, query: query, body: body);
    if (payload is! Map) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Expected a JSON object',
      );
    }
    return payload.cast<String, Object?>();
  }

  Future<void> requestEmpty(String method, String path) async {
    await request(method, path);
  }

  Future<Object?> request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    List<int>? rawBody,
    String contentType = 'application/json',
  }) => _executor.execute(
    method,
    path,
    query: query,
    headers: {
      HttpHeaders.acceptHeader: 'application/json',
      HttpHeaders.contentTypeHeader: contentType,
      HttpHeaders.userAgentHeader: _userAgent,
      ..._additionalHeaders,
      HttpHeaders.authorizationHeader: _authorization._headerValue,
    },
    body: rawBody ?? (body == null ? null : utf8.encode(jsonEncode(body))),
  );

  void close() => _executor.close();

  @override
  String toString() => 'DiscordRestClient($_authorization)';
}
