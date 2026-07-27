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

/// One successful HTTP answer, with the parts a caller needs when the status
/// line is itself part of the protocol.
///
/// Message search is why this exists: Discord answers a query whose corpus it
/// has not finished indexing with `202 Accepted` and a `Retry-After` header,
/// which is a step of the flow rather than a failure. Neither the status nor
/// the header survives a call that hands back only the decoded body, and a
/// client that cannot tell 202 from 200 shows "no results" for a search the
/// server never ran.
final class DiscordApiResponse {
  const DiscordApiResponse({
    required this.statusCode,
    required this.headers,
    required this.payload,
  });

  final int statusCode;

  /// Header names are lower-cased by the transport, so lookups are too.
  final Map<String, String> headers;
  final Object? payload;

  /// The `Retry-After` header in whole seconds, or null when the server sent
  /// none, sent something unparseable, or asked for zero.
  ///
  /// Discord's own client reads this with `parseInt`, which takes the leading
  /// integer and ignores the rest, so `"3.5"` means three seconds and not a
  /// parse failure. A zero is treated as absent by every caller, so it is
  /// folded in here rather than at each of them.
  Duration? get retryAfter {
    final match = _leadingInteger.firstMatch(headers['retry-after'] ?? '');
    final seconds = match == null ? null : int.tryParse(match.group(0)!);
    if (seconds == null || seconds <= 0) return null;
    return Duration(seconds: seconds);
  }

  static final _leadingInteger = RegExp(r'^\s*\d+');
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
    Map<String, Object?>? query,
    required Map<String, String> headers,
    List<int>? body,
  }) async => (await send(
    method,
    path,
    query: query,
    headers: headers,
    body: body,
  )).payload;

  /// Like [execute], but hands back the status and headers as well.
  ///
  /// [query] takes `String` values, or `List<String>` for a parameter Discord
  /// repeats — `has=image&has=video` — which is how every list-valued search
  /// filter travels.
  Future<DiscordApiResponse> send(
    String method,
    String path, {
    Map<String, Object?>? query,
    required Map<String, String> headers,
    List<int>? body,
  }) async {
    final uri = Uri.parse(
      '${_baseUri.toString()}$path',
    ).replace(queryParameters: _queryParameters(query));
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
      return DiscordApiResponse(
        statusCode: response.statusCode,
        headers: response.headers,
        payload: payload,
      );
    }
    throw const DiscordApiException(
      statusCode: 429,
      message: 'Rate limit retry budget exhausted',
    );
  }

  /// Renders a query map the way Discord's own client does.
  ///
  /// Three rules, all of them load-bearing:
  ///
  /// * `null` values are **deleted**, not sent as the string "null". The
  ///   renderer strips them before every request, and a literal `null` in a
  ///   query is a filter nobody asked for — `action_type=null` is not the same
  ///   request as an unfiltered audit log.
  /// * A list repeats the key, which is how `include_roles` and `user_ids`
  ///   travel.
  /// * Booleans render lowercase, and everything else through `toString`, so an
  ///   `int` limit does not have to be pre-stringified at every call site.
  static Map<String, dynamic>? _queryParameters(Map<String, Object?>? query) {
    if (query == null) return null;
    final parameters = <String, dynamic>{};
    for (final entry in query.entries) {
      final value = entry.value;
      switch (value) {
        case null:
          continue;
        case final Iterable<Object?> items:
          final rendered = [
            for (final item in items)
              if (item != null) '$item',
          ];
          if (rendered.isNotEmpty) parameters[entry.key] = rendered;
        case final bool flag:
          parameters[entry.key] = flag ? 'true' : 'false';
        default:
          parameters[entry.key] = '$value';
      }
    }
    return parameters;
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

  /// The header Discord attributes a moderation action by in the audit log.
  static const auditLogReasonHeader = 'X-Audit-Log-Reason';

  Future<Map<String, Object?>> getObject(String path) =>
      requestObject('GET', path);

  Future<List<Map<String, Object?>>> getList(
    String path, {
    Map<String, Object?>? query,
  }) async {
    final payload = await request('GET', path, query: query);
    return _asList(payload);
  }

  Future<Map<String, Object?>> requestObject(
    String method,
    String path, {
    Map<String, Object?>? query,
    Map<String, Object?>? body,
    String? auditLogReason,
  }) async {
    final payload = await request(
      method,
      path,
      query: query,
      body: body,
      auditLogReason: auditLogReason,
    );
    if (payload is! Map) {
      throw const DiscordApiException(
        statusCode: 502,
        message: 'Expected a JSON object',
      );
    }
    return payload.cast<String, Object?>();
  }

  /// Sends a bare JSON **array** body and reads an array back.
  ///
  /// The role and channel reorder routes take a top-level array, not an object
  /// wrapping one, so they cannot go through [requestObject] at all.
  Future<List<Map<String, Object?>>> requestJsonArray(
    String method,
    String path, {
    required List<Object?> body,
    String? auditLogReason,
  }) async {
    final payload = await _execute(
      method,
      path,
      encodedBody: utf8.encode(jsonEncode(body)),
      auditLogReason: auditLogReason,
    );
    return payload == null ? const [] : _asList(payload);
  }

  Future<void> requestEmpty(
    String method,
    String path, {
    Map<String, Object?>? query,
    Map<String, Object?>? body,
    String? auditLogReason,
  }) async {
    await request(
      method,
      path,
      query: query,
      body: body,
      auditLogReason: auditLogReason,
    );
  }

  Future<Object?> request(
    String method,
    String path, {
    Map<String, Object?>? query,
    Map<String, Object?>? body,
    List<int>? rawBody,
    String contentType = 'application/json',
    String? auditLogReason,
  }) => _execute(
    method,
    path,
    query: query,
    encodedBody:
        rawBody ?? (body == null ? null : utf8.encode(jsonEncode(body))),
    contentType: contentType,
    auditLogReason: auditLogReason,
  );

  Future<Object?> _execute(
    String method,
    String path, {
    Map<String, Object?>? query,
    List<int>? encodedBody,
    String contentType = 'application/json',
    String? auditLogReason,
  }) => _executor.execute(
    method,
    path,
    query: query,
    headers: _headers(contentType, auditLogReason),
    body: encodedBody,
  );

  /// A request whose status and headers the caller needs, for the routes where
  /// a non-200 success carries meaning of its own.
  Future<DiscordApiResponse> requestDetailed(
    String method,
    String path, {
    Map<String, Object?>? query,
  }) => _executor.send(method, path, query: query, headers: _headers());

  Map<String, String> _headers([
    String contentType = 'application/json',
    String? auditLogReason,
  ]) => {
    HttpHeaders.acceptHeader: 'application/json',
    HttpHeaders.contentTypeHeader: contentType,
    HttpHeaders.userAgentHeader: _userAgent,
    ..._additionalHeaders,
    // Percent-encoded whole, the way the desktop client does it. A reason is
    // free text a moderator typed, and a raw newline or non-Latin-1 byte in
    // an HTTP header is either rejected outright or, worse, splits the
    // request — so it is encoded here rather than trusted to the socket.
    if (auditLogReason != null && auditLogReason.trim().isNotEmpty)
      auditLogReasonHeader: Uri.encodeComponent(auditLogReason.trim()),
    HttpHeaders.authorizationHeader: _authorization._headerValue,
  };

  static List<Map<String, Object?>> _asList(Object? payload) {
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

  void close() => _executor.close();

  @override
  String toString() => 'DiscordRestClient($_authorization)';
}
